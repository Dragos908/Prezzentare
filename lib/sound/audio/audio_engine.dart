// lib/sound/audio/audio_engine.dart
//
// AudioEngine (control) — voci audio, preîncărcare, volum și detectarea
// sfârșitului / buclei. NU știe nimic de baza de date sau de display.
//
//  • volum efectiv redat = master × volumul canalului (rampele modifică doar
//    canalul, deci schimbarea lui master nu le întrerupe);
//  • tăiere non-distructivă: pornește de la trimStart și se oprește / reia la trimEnd;
//  • pad-urile sunt pre-încărcate (player gata, în pauză) ca startul să fie aproape
//    instant; la oprire playerul revine în pool, gata pentru următoarea apăsare;
//  • limită de voci simultane (cele mai vechi se opresc la depășire).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/fade_engine.dart';
import '../core/models.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';

enum EngineEventKind { ended, rampDone }

class EngineEvent {
  final EngineEventKind kind;
  final String itemId;

  /// Pentru `ended`: true dacă a ajuns singur la sfârșit (nu a fost oprit).
  final bool natural;

  /// Pentru `rampDone`: eticheta rampei.
  final Object? tag;

  const EngineEvent(this.kind, this.itemId, {this.natural = false, this.tag});
}

class PadState {
  final bool playing;
  final bool paused;
  final bool loading;

  /// Volumul canalului (0..1), după rampă.
  final double volume;
  final double progress;
  final int positionMs;
  final int rampRemainingMs;
  final Object? rampTag;

  const PadState({
    this.playing = false,
    this.paused = false,
    this.loading = false,
    this.volume = 1.0,
    this.progress = 0.0,
    this.positionMs = 0,
    this.rampRemainingMs = 0,
    this.rampTag,
  });

  bool get active => playing || paused;

  @override
  bool operator ==(Object other) =>
      other is PadState &&
      other.playing == playing &&
      other.paused == paused &&
      other.loading == loading &&
      other.volume == volume &&
      other.progress == progress &&
      other.positionMs == positionMs &&
      other.rampRemainingMs == rampRemainingMs &&
      other.rampTag == rampTag;

  @override
  int get hashCode => Object.hash(playing, paused, loading, volume, progress,
      positionMs, rampRemainingMs, rampTag);
}

class _Voice {
  SoundItem item;
  final AudioPlayerPort port;
  bool playing = false;
  bool paused = false;
  int loopGuardUntilUs = 0;
  double volumeBeforePause = 1.0;
  StreamSubscription<void>? completedSub;
  final int startedUs;

  _Voice(this.item, this.port, this.startedUs);
}

const String kPauseFadeTag = 'pauseFade';

class AudioEngine {
  final MonoClock clock;
  final AudioPlayerFactory createPlayer;

  /// Rezolvă URL-ul local redabil pentru un sunet (din magazia persistentă).
  final Future<String?> Function(String itemId) resolveUrl;
  final int maxVoices;
  final int maxPrepared;

  late final FadeController fade =
      FadeController(clock: clock, onValue: _onFadeValue, onComplete: _onFadeDone);

  final ValueNotifier<double> master = ValueNotifier<double>(1.0);
  FadeCurveKind curve = FadeCurveKind.natural;

  final Map<String, _Voice> _voices = <String, _Voice>{};
  final Map<String, AudioPlayerPort> _prepared = <String, AudioPlayerPort>{};
  final Map<String, ValueNotifier<PadState>> _pads =
      <String, ValueNotifier<PadState>>{};
  final Map<String, Completer<void>> _rampWaiters = <String, Completer<void>>{};
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();

  Timer? _watch;
  int _lastUiUs = 0;
  bool _disposed = false;

  AudioEngine({
    required this.clock,
    required this.createPlayer,
    required this.resolveUrl,
    this.maxVoices = 16,
    this.maxPrepared = 24,
  }) {
    master.addListener(_applyAll);
  }

  Stream<EngineEvent> get events => _events.stream;

  // ── stare ─────────────────────────────────────────────────────────────────
  ValueNotifier<PadState> _padNotifier(String id) =>
      _pads.putIfAbsent(id, () => ValueNotifier<PadState>(const PadState()));

  ValueListenable<PadState> pad(String id) => _padNotifier(id);

  bool isPlaying(String id) => _voices[id]?.playing ?? false;
  bool isPaused(String id) => _voices[id]?.paused ?? false;
  bool isActive(String id) => _voices.containsKey(id);
  Iterable<String> get activeIds => List<String>.of(_voices.keys);
  Iterable<String> get playingIds =>
      _voices.entries.where((e) => e.value.playing).map((e) => e.key).toList();
  bool get anyPlaying => _voices.values.any((v) => v.playing);

  int positionMs(String id) => _voices[id]?.port.positionMs ?? 0;

  double channelVolume(String id) => fade.volumeOf(id);

  /// Actualizează metadatele unui sunet care rulează (tăiere, buclă etc.).
  void updateItem(SoundItem item) {
    final v = _voices[item.id];
    if (v != null) v.item = item;
  }

  void _publishPad(String id) {
    final v = _voices[id];
    final n = _padNotifier(id);
    if (v == null) {
      n.value = PadState(volume: fade.volumeOf(id, fallback: n.value.volume));
      return;
    }
    final pos = v.port.positionMs;
    final len = v.item.trimLengthMs;
    final prog = len <= 0 ? 0.0 : ((pos - v.item.trimStartMs) / len).clamp(0.0, 1.0).toDouble();
    final r = fade.rampOf(id);
    n.value = PadState(
      playing: v.playing,
      paused: v.paused,
      volume: fade.volumeOf(id),
      progress: prog,
      positionMs: pos,
      rampRemainingMs: r == null ? 0 : fade.remainingMs(id),
      rampTag: r?.tag,
    );
  }

  // ── volum ─────────────────────────────────────────────────────────────────
  void _apply(String id) {
    final v = _voices[id];
    if (v == null) return;
    v.port.setVolume((master.value * fade.volumeOf(id)).clamp(0.0, 1.0).toDouble());
  }

  void _applyAll() {
    for (final id in List<String>.of(_voices.keys)) {
      _apply(id);
    }
  }

  void _onFadeValue(String id, double value) {
    _apply(id);
    if (_voices.containsKey(id)) _publishPad(id);
  }

  void _onFadeDone(String id, Object? tag) {
    _publishPad(id);
    final w = _rampWaiters.remove(id);
    if (w != null && !w.isCompleted) w.complete();
    if (!_events.isClosed) {
      _events.add(EngineEvent(EngineEventKind.rampDone, id, tag: tag));
    }
  }

  /// Setare manuală a volumului canalului (slider) — anulează rampa activă.
  void setChannelVolume(String id, double v) {
    fade.setVolume(id, v);
    _publishPad(id);
  }

  void rampTo(String id, double to,
      {required int ms, Object? tag, FadeCurveKind? curveOverride}) {
    if (!_voices.containsKey(id)) return;
    fade.ramp(id, to: to, durationMs: ms, curve: curveOverride ?? curve, tag: tag);
    _publishPad(id);
  }

  /// Rampă + așteptare până se termină (sau este anulată).
  Future<void> rampAndWait(String id, double to,
      {required int ms, Object? tag}) {
    final c = Completer<void>();
    _rampWaiters[id] = c;
    rampTo(id, to, ms: ms, tag: tag);
    if (!fade.isRamping(id) && !c.isCompleted) c.complete();
    return c.future.timeout(Duration(milliseconds: ms + 500), onTimeout: () {});
  }

  // ── preîncărcare ──────────────────────────────────────────────────────────
  Future<void> preload(SoundItem item) async {
    if (_disposed || _voices.containsKey(item.id) || _prepared.containsKey(item.id)) {
      return;
    }
    while (_prepared.length >= maxPrepared) {
      final oldest = _prepared.keys.first;
      await _prepared.remove(oldest)?.dispose();
    }
    final url = await resolveUrl(item.id);
    if (url == null) return;
    final p = createPlayer();
    try {
      await p.load(url);
      await p.seek(item.trimStartMs);
      _prepared[item.id] = p;
    } catch (_) {
      await p.dispose();
    }
  }

  void forget(String id) {
    _prepared.remove(id)?.dispose();
    fade.forget(id);
    _pads.remove(id)?.dispose();
  }

  // ── pornire ───────────────────────────────────────────────────────────────
  /// Pregătește vocea: player încărcat, poziționat la [positionMs], volum setat,
  /// DAR încă în pauză. Întoarce false dacă fișierul nu poate fi încărcat.
  Future<bool> arm(SoundItem item, {double? startVolume, int? positionMs}) async {
    if (_disposed) return false;
    final id = item.id;
    if (_voices.containsKey(id)) await stop(id, fadeMs: 0);

    // limită de voci: oprim cea mai veche
    while (_voices.length >= maxVoices) {
      final oldest = _voices.entries.reduce(
          (a, b) => a.value.startedUs <= b.value.startedUs ? a : b);
      await stop(oldest.key, fadeMs: 0);
    }

    _padNotifier(id).value = PadState(loading: true, volume: item.volume);
    AudioPlayerPort? port = _prepared.remove(id);
    if (port == null) {
      final url = await resolveUrl(id);
      if (url == null) {
        _publishPad(id);
        return false;
      }
      port = createPlayer();
      try {
        await port.load(url);
      } catch (_) {
        await port.dispose();
        _publishPad(id);
        return false;
      }
    }

    final v = _Voice(item, port, clock.nowUs);
    _voices[id] = v;
    v.completedSub = port.completed.listen((_) => _onFileCompleted(id));

    fade.setVolume(id, startVolume ?? item.volume);
    _apply(id);
    await port.seek(positionMs ?? item.trimStartMs);
    _publishPad(id);
    return true;
  }

  /// Pornește redarea unei voci pregătite.
  Future<void> go(String id) async {
    final v = _voices[id];
    if (v == null) return;
    await v.port.play();
    v.playing = true;
    v.paused = false;
    _ensureWatch();
    _publishPad(id);
  }

  /// arm + go (pentru sunete simple).
  Future<bool> start(SoundItem item, {double? startVolume, int? positionMs}) async {
    final ok = await arm(item, startVolume: startVolume, positionMs: positionMs);
    if (ok) await go(item.id);
    return ok;
  }

  // ── pauză / reluare (cu fade foarte scurt, fără pocnet) ───────────────────
  Future<void> pause(String id, {int fadeMs = 40, double? resumeVolume}) async {
    final v = _voices[id];
    if (v == null || !v.playing) return;
    v.volumeBeforePause = resumeVolume ?? fade.volumeOf(id);
    if (fadeMs > 0) await rampAndWait(id, 0, ms: fadeMs, tag: kPauseFadeTag);
    if (_voices[id] != v) return; // oprit între timp (ex. „Oprește tot”)
    await v.port.pause();
    v.playing = false;
    v.paused = true;
    fade.setVolume(id, v.volumeBeforePause); // tăcut cât timp e în pauză
    _publishPad(id);
  }

  Future<void> resume(String id, {int fadeMs = 40}) async {
    final v = _voices[id];
    if (v == null || !v.paused) return;
    final target = v.volumeBeforePause;
    if (fadeMs > 0) fade.setVolume(id, 0);
    _apply(id);
    await v.port.play();
    v.playing = true;
    v.paused = false;
    _ensureWatch();
    if (fadeMs > 0) rampTo(id, target, ms: fadeMs, tag: kPauseFadeTag);
    _publishPad(id);
  }

  Future<void> seek(String id, int ms) async {
    final v = _voices[id];
    if (v == null) return;
    await v.port.seek(ms);
    _publishPad(id);
  }

  /// Seek cu fade foarte scurt (restart fără pocnet).
  Future<void> softSeek(String id, int ms, {int fadeMs = 40}) async {
    final v = _voices[id];
    if (v == null) return;
    final base = fade.volumeOf(id);
    if (v.playing && fadeMs > 0) await rampAndWait(id, 0, ms: fadeMs, tag: kPauseFadeTag);
    await v.port.seek(ms);
    if (v.playing && fadeMs > 0) {
      rampTo(id, base, ms: fadeMs, tag: kPauseFadeTag);
    } else {
      fade.setVolume(id, base);
    }
    _publishPad(id);
  }

  // ── oprire ────────────────────────────────────────────────────────────────
  /// Oprește vocea. [fadeMs] > 0 → fade scurt înainte (fără pocnet);
  /// 0 → instant. Playerul revine în pool, gata pentru următoarea apăsare.
  Future<void> stop(String id, {int fadeMs = 40, bool natural = false}) async {
    final v = _voices[id];
    if (v == null) return;
    if (fadeMs > 0 && v.playing) {
      await rampAndWait(id, 0, ms: fadeMs, tag: kPauseFadeTag);
    }
    if (!_voices.containsKey(id)) return;
    await _release(id, natural: natural);
  }

  Future<void> _release(String id, {required bool natural}) async {
    final v = _voices.remove(id);
    if (v == null) return;
    fade.cancel(id);
    final w = _rampWaiters.remove(id);
    if (w != null && !w.isCompleted) w.complete();
    await v.completedSub?.cancel();
    try {
      await v.port.pause();
      await v.port.seek(v.item.trimStartMs);
    } catch (_) {}
    fade.setVolume(id, v.item.volume); // volumul revine la valoarea de bază
    if (_prepared.length < maxPrepared) {
      _prepared[id] = v.port; // gata pentru următorul play instant
    } else {
      await v.port.dispose();
    }
    _publishPad(id);
    if (_voices.isEmpty) _stopWatch();
    if (!_events.isClosed) {
      _events.add(EngineEvent(EngineEventKind.ended, id, natural: natural));
    }
  }

  /// „Oprește tot”: instant, anulează orice fade.
  Future<void> stopAll() async {
    fade.cancelAll();
    for (final id in List<String>.of(_voices.keys)) {
      await _release(id, natural: false);
    }
  }

  // ── sfârșit / buclă ───────────────────────────────────────────────────────
  void _onFileCompleted(String id) {
    final v = _voices[id];
    if (v == null || !v.playing) return;
    if (v.item.loop) {
      unawaited(v.port.seek(v.item.trimStartMs).then((_) => v.port.play()));
    } else {
      unawaited(_release(id, natural: true));
    }
  }

  void _ensureWatch() {
    _watch ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _watchTick());
  }

  void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  void _watchTick() {
    final now = clock.nowUs;
    final updateUi = now - _lastUiUs >= 80000; // ~12 Hz pentru bara de progres
    if (updateUi) _lastUiUs = now;

    for (final id in List<String>.of(_voices.keys)) {
      final v = _voices[id];
      if (v == null || !v.playing) continue;
      final pos = v.port.positionMs;
      final end = v.item.effectiveTrimEndMs;
      if (end > 0) {
        if (v.item.loop) {
          if (pos >= end - 5 && now >= v.loopGuardUntilUs) {
            v.loopGuardUntilUs = now + 250000;
            unawaited(v.port.seek(v.item.trimStartMs));
          }
        } else if (pos >= end - 10) {
          unawaited(_release(id, natural: true));
          continue;
        }
      }
      if (updateUi && !fade.isRamping(id)) _publishPad(id);
    }
  }

  /// Doar pentru teste: un pas al watcher-ului.
  @visibleForTesting
  void debugTick() => _watchTick();

  Future<void> dispose() async {
    _disposed = true;
    _stopWatch();
    master.removeListener(_applyAll);
    fade.dispose();
    for (final id in List<String>.of(_voices.keys)) {
      final v = _voices.remove(id);
      await v?.completedSub?.cancel();
      await v?.port.dispose();
    }
    for (final p in _prepared.values) {
      await p.dispose();
    }
    _prepared.clear();
    for (final n in _pads.values) {
      n.dispose();
    }
    _pads.clear();
    await _events.close();
    master.dispose();
  }
}
