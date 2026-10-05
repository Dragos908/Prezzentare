// lib/sound/display/display_sync_follower.dart
//
// DisplaySyncFollower — „slave”-ul sincronizării. Redă DOAR imaginea (mut) și o
// aliniază la audio-ul din pagina de control, singura referință.
//
// Ce face:
//   • ascultă starea de redare (la evenimente) + heartbeat-ul (~1/s) din DB;
//   • pre-încălzește controllerul video (initialize + seek la start) înainte de Play;
//   • la „Play” așteaptă `anchorTs` (start programat) și pornește exact atunci;
//   • la ~250 ms citește poziția REALĂ (asincron) și corectează driftul:
//       |drift| > hard → seek · soft…hard → viteză ±2–5 % · < soft → nimic;
//   • dacă heartbeat-ul lipsește > 5 s cât timp e „playing” → pauză (nu rulează fără
//     sunet) și se realiniază când revine;
//   • la reconectare / revenire din fundal citește starea din DB și sare la poziția
//     corectă (resync); ignoră actualizările cu seq mai vechi;
//   • raportează în DB (la ~1 s) starea: conectat, gata, buffering, poziție, drift.
//
// Nu scrie și nu citește nimic în afara canalului realtime (SyncChannelPort).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';
import 'display_audio_guard.dart';

/// Ce trebuie desenat de overlay.
class ActiveVideo {
  final VideoPlayerPort port;
  final String itemId;
  const ActiveVideo(this.port, this.itemId);
}

class DisplaySyncFollower {
  final SyncChannelPort channel;
  final ServerClock clock;
  final MonoClock mono;
  final VideoPortFactory createPort;
  final Future<String?> Function(SoundItem item) resolveMediaUrl;
  final Future<void> Function(Iterable<SoundItem> items)? prefetchAll;
  final DisplayAudioGuard guard;

  /// Cât timp lipsa heartbeat-ului e tolerată înainte de pauză.
  final int heartbeatTimeoutMs;

  /// Pragul sub care o diferență de heartbeat e ignorată (anti-oscilație).
  final int heartbeatDeadbandMs;

  /// Pornire anticipată a lui play() (latența de pornire a elementului video).
  final int startLeadMs;

  DisplaySyncFollower({
    required this.channel,
    required this.clock,
    required this.mono,
    required this.createPort,
    required this.resolveMediaUrl,
    this.prefetchAll,
    DisplayAudioGuard? guard,
    this.heartbeatTimeoutMs = 5000,
    this.heartbeatDeadbandMs = 25,
    this.startLeadMs = 50,
  }) : guard = guard ?? DisplayAudioGuard.instance;

  // ── stare observabilă ─────────────────────────────────────────────────────
  final ValueNotifier<ActiveVideo?> active = ValueNotifier<ActiveVideo?>(null);

  /// Opacitatea imaginii (1 → 0 în fade-ul opțional), calculată din ceasul de server.
  double get imageOpacity => imageFadeOpacity(
        fadeStartTs: _state.fadeOutStartTs,
        fadeMs: _state.fadeOutMs,
        serverNowMs: clock.serverNowMs,
      );

  bool get isFading => _state.fadeOutStartTs != null && imageOpacity < 1.0;

  // ── interne ───────────────────────────────────────────────────────────────
  AppSettings _settings = const AppSettings();
  PlaybackState _state = PlaybackState.idle;
  SyncSnapshot? _hb;
  int _lastBeatMonoMs = 0;
  final SeqGate _gate = SeqGate();
  final Map<String, SoundItem> _items = <String, SoundItem>{};

  VideoPlayerPort? _port;
  String? _currentItemId;
  bool _ready = false;
  bool _stale = false;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;
  int _lastDriftMs = 0;
  int _lastPositionMs = 0;

  /// seq-ul sesiunii care s-a terminat natural (nu o mai repornim din greșeală).
  int _endedSeq = -1;
  String? lastError;

  late DriftController _drift = _newDrift();

  Timer? _driftTimer;
  Timer? _statusTimer;
  Timer? _startTimer;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];

  DriftController _newDrift() => DriftController(
        hardMs: _settings.driftHardMs,
        softMs: _settings.driftSoftMs,
      );

  // ── ciclu de viață ────────────────────────────────────────────────────────
  Future<void> start() async {
    _subs.add(channel.settingsStream().listen(_onSettings));
    _subs.add(channel.itemsStream().listen(_onItems));
    _subs.add(channel.playbackStream().listen((s) => unawaited(_onPlayback(s))));
    _subs.add(channel.heartbeatStream().listen(_onHeartbeat));
    try {
      await channel.armDisplayDisconnect();
    } catch (_) {}
    _driftTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) => unawaited(driftTick()));
    _statusTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => unawaited(reportStatus()));
    unawaited(reportStatus());
  }

  /// Reconectare / revenire din fundal: citește starea din DB și sare direct la
  /// poziția corectă.
  Future<void> resync() async {
    try {
      final s = await channel.readPlayback();
      _gate.reset();
      await _onPlayback(s);
    } catch (_) {/* rămâne pe starea curentă */}
  }

  // ── setări / bibliotecă ───────────────────────────────────────────────────
  void _onSettings(AppSettings s) {
    final changed = s.driftHardMs != _settings.driftHardMs ||
        s.driftSoftMs != _settings.driftSoftMs;
    _settings = s;
    if (changed) _drift = _newDrift();
    guard.setMuted(s.displayAudioMuted);
    guard.setBlockUnmutable(s.blockUnmutableEmbeds);
  }

  void _onItems(List<SoundItem> list) {
    _items
      ..clear()
      ..addEntries(list.map((i) => MapEntry<String, SoundItem>(i.id, i)));
    final pf = prefetchAll;
    if (pf != null) unawaited(pf(list.where((i) => i.isVideo)));
    // dacă itemul curent tocmai a apărut / s-a schimbat, reaplicăm starea
    if (_state.isActive && _port == null && !_disposed) {
      unawaited(_applyState());
    }
  }

  // ── stare de redare ───────────────────────────────────────────────────────
  Future<void> _onPlayback(PlaybackState s) async {
    if (_disposed) return;
    if (!_gate.accept(s.seq)) return; // seq mai vechi / duplicat
    _state = s;
    _hb = null; // heartbeat-ul vechi aparține altei sesiuni
    _lastBeatMonoMs = mono.nowMs;
    _stale = false;
    await _applyState();
  }

  Future<void> _applyState() async {
    final s = _state;
    final id = s.itemId;
    if (!s.isActive || id == null) {
      await _hide();
      return;
    }
    if (_endedSeq == s.seq) return; // sesiunea s-a terminat deja pe acest display
    final item = _items[id];
    if (item == null || !item.isVideo) {
      await _hide(); // sunet simplu sau item necunoscut: displayul nu arată nimic
      return;
    }
    if (_currentItemId != id || _port == null) {
      await _switchTo(item);
    }
    if (_port == null || !_ready) return;
    await _syncToSnapshot();
  }

  Future<void> _switchTo(SoundItem item) async {
    final epoch = ++_epoch;
    _startTimer?.cancel();
    await _releasePort();
    if (epoch != _epoch || _disposed) return;

    _currentItemId = item.id;
    _ready = false;
    _drift.reset();
    lastError = null;

    final url = await resolveMediaUrl(item);
    if (epoch != _epoch || _disposed) return;
    if (url == null) {
      lastError = 'Sunetul „${item.name}” nu are link video (Google Drive) pentru display.';
      return;
    }

    final port = createPort();
    try {
      await port.initialize(url);
      await port.setVolume(0); // mut, indiferent de setare
      await port.seekTo(item.trimStartMs);
    } catch (e) {
      lastError = 'Video indisponibil pe display: $e (verifică linkul: fișierul din '
          'Drive trebuie partajat „Oricine are linkul”)';
      await port.dispose();
      return;
    }
    if (epoch != _epoch || _disposed) {
      await port.dispose();
      return;
    }
    _port = port;
    _ready = true;
    active.value = ActiveVideo(port, item.id);
  }

  SyncSnapshot? _snapshot() {
    if (!_state.isActive) return null;
    final hb = _hb;
    if (hb != null && hb.seq == _state.seq) return hb;
    return SyncSnapshot.fromState(_state);
  }

  /// Aliniază playerul la starea curentă (după Play / Pauză / Seek / resync).
  Future<void> _syncToSnapshot() async {
    final port = _port;
    final snap = _snapshot();
    if (port == null || snap == null || !_ready) return;
    final epoch = _epoch;
    final now = clock.serverNowMs;
    _startTimer?.cancel();
    _drift.reset();

    try {
      await port.setPlaybackSpeed(1.0);
      if (snap.status == PlaybackStatus.paused) {
        await port.pause();
        await port.seekTo(snap.positionMs); // pauză: poziție exactă
        return;
      }

      if (now < snap.anchorTs) {
        // START PROGRAMAT: stăm pe poziția de start și pornim exact la anchorTs
        await port.pause();
        await port.seekTo(snap.positionMs);
        final wait = snap.anchorTs - clock.serverNowMs - startLeadMs;
        _startTimer = Timer(
          Duration(milliseconds: wait < 0 ? 0 : wait),
          () => unawaited(_startNow(epoch, scheduled: true)),
        );
        return;
      }
      // Display întârziat (repornit / conectat târziu) sau stare nouă în timpul
      // redării: se aliniază doar dacă poziția chiar a derivat.
      await _startNow(epoch, scheduled: false);
    } catch (e) {
      lastError = 'Sincronizare: $e';
    }
  }

  /// [scheduled] = true: momentul programat (`anchorTs`) a sosit — playerul e deja
  /// pe poziția de start, doar pornim. false: pornire târzie / stare nouă — sărim la
  /// poziția așteptată NUMAI dacă diferă de cea reală peste pragul soft (altfel un
  /// simplu eveniment, ex. începutul unui fade, ar provoca un seek vizibil).
  Future<void> _startNow(int epoch, {required bool scheduled}) async {
    final port = _port;
    final snap = _snapshot();
    if (port == null || snap == null || epoch != _epoch) return;
    try {
      if (!scheduled) {
        final now = clock.serverNowMs;
        final expected = expectedPositionMs(snap, now);
        final actual = await port.readPositionMs();
        final drift = signedDriftMs(
          actualMs: actual,
          expectedMs: expected,
          avOffsetMs: _settings.avSyncOffsetMs,
          loop: snap.loop,
          windowMs: snap.windowMs,
        ).abs();
        if (!(port.isPlaying && drift <= _settings.driftSoftMs)) {
          await port.seekTo(
              expected + _settings.avSyncOffsetMs + _drift.seekLeadMs);
        }
      }
      if (!port.isPlaying) await port.play();
    } catch (e) {
      lastError = 'Pornire: $e';
    }
  }

  // ── heartbeat ─────────────────────────────────────────────────────────────
  void _onHeartbeat(Heartbeat h) {
    final s = _state;
    if (!s.isActive || h.seq != s.seq || h.itemId != s.itemId) return;
    _lastBeatMonoMs = mono.nowMs; // proaspăt, chiar dacă diferența e mică

    final cand = SyncSnapshot.fromHeartbeat(h, s);
    final cur = _snapshot();
    final now = clock.serverNowMs;
    if (cur != null && cur.status == cand.status) {
      final diff = signedDriftMs(
        actualMs: expectedPositionMs(cand, now),
        expectedMs: expectedPositionMs(cur, now),
        loop: cand.loop,
        windowMs: cand.windowMs,
      ).abs();
      if (diff < heartbeatDeadbandMs) return; // ignorat: nu oscilăm
    }
    _hb = cand;
  }

  // ── bucla de corecție a driftului (~250 ms) ───────────────────────────────
  @visibleForTesting
  Future<void> driftTick() async {
    if (_busy || _disposed) return;
    final port = _port;
    final snap = _snapshot();
    if (port == null || snap == null || !_ready) return;
    _busy = true;
    try {
      final now = clock.serverNowMs;

      // heartbeat lipsă → pauză, apoi realiniere
      if (snap.status == PlaybackStatus.playing) {
        final age = mono.nowMs - _lastBeatMonoMs;
        if (age > heartbeatTimeoutMs && now >= snap.anchorTs) {
          if (!_stale) {
            _stale = true;
            await port.pause();
          }
          return;
        }
        if (_stale) {
          _stale = false;
          await _syncToSnapshot();
          return;
        }
      }
      if (snap.status != PlaybackStatus.playing || now < snap.anchorTs) return;

      // sfârșit decis din aceeași poziție așteptată ca pe control
      if (hasReachedEnd(snap, now)) {
        await port.pause();
        await port.seekTo(snap.trimEndMs);
        _endedSeq = snap.seq;
        await _hide(keepState: true);
        return;
      }

      final expected = expectedPositionMs(snap, now);
      final actual = await port.readPositionMs();
      _lastPositionMs = actual;
      final drift = signedDriftMs(
        actualMs: actual,
        expectedMs: expected,
        avOffsetMs: _settings.avSyncOffsetMs,
        loop: snap.loop,
        windowMs: snap.windowMs,
      );
      _lastDriftMs = drift;

      final d = _drift.decide(driftMs: drift, expectedMs: expected, playing: true);
      switch (d.kind) {
        case DriftActionKind.seek:
          await port.seekTo(d.seekToMs! + _settings.avSyncOffsetMs);
          await port.setPlaybackSpeed(1.0);
          break;
        case DriftActionKind.adjustRate:
          await port.setPlaybackSpeed(d.rate);
          break;
        case DriftActionKind.resetRate:
          await port.setPlaybackSpeed(1.0);
          break;
        case DriftActionKind.none:
          break;
      }
      if (!port.isPlaying) await port.play();
    } catch (e) {
      lastError = 'Drift: $e';
    } finally {
      _busy = false;
    }
  }

  // ── ascundere / eliberare ─────────────────────────────────────────────────
  Future<void> _hide({bool keepState = false}) async {
    _epoch++;
    _startTimer?.cancel();
    active.value = null;
    await _releasePort();
    if (!keepState) {
      _currentItemId = null;
      _ready = false;
    }
  }

  Future<void> _releasePort() async {
    final p = _port;
    _port = null;
    _ready = false;
    if (p != null) {
      try {
        await p.pause();
      } catch (_) {}
      await p.dispose();
    }
  }

  // ── raportare către control (~1 s) ────────────────────────────────────────
  @visibleForTesting
  Future<void> reportStatus() async {
    if (_disposed) return;
    final g = guard.report();
    final status = DisplayStatus(
      connected: true,
      lastSeen: clock.serverNowMs,
      ready: _currentItemId == null || _ready,
      buffering: _port?.isBuffering ?? false,
      itemId: _currentItemId,
      positionMs: _lastPositionMs,
      driftMs: _lastDriftMs,
      guardActive: g.active,
      guardPlayers: g.players,
      guardUnmuted: g.unmuted,
      embedsUnmutable: g.embedsUnmutable,
    );
    try {
      await channel.writeDisplayStatus(status);
    } catch (_) {/* offline: se reia la următorul tick */}
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    _driftTimer?.cancel();
    _statusTimer?.cancel();
    _startTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    active.value = null;
    await _releasePort();
    active.dispose();
  }
}
