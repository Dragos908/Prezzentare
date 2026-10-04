// lib/sound/audio/playback_coordinator.dart
//
// PlaybackCoordinator (control = ceas MASTER).
//
//  • orchestrează AudioEngine (sunetul) și publică în baza de date starea de
//    redare a sunetului VIDEO curent, ca displayul să-i arate imaginea;
//  • scrie starea la fiecare EVENIMENT (play / pauză / seek / stop / tăiere /
//    următorul) + heartbeat la ~1 s cu poziția reală a audio;
//  • Play = start programat: start_at = serverNow + lead. Controlul NU așteaptă
//    niciodată displayul: audio pornește oricum la start_at;
//  • măsoară latența reală de pornire a audio și publică ancora corectată;
//  • fade la nivel / revino la normal / fade-out / fade-in / crossfade — toate
//    prin FadeController (din AudioEngine);
//  • Următorul / Anterior (ordinea pad-urilor, buclă opțională) cu tranziție:
//    tăiere, fade-out apoi start, sau crossfade; auto-avans opțional.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/playlist_logic.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';
import '../data/settings_repository.dart';
import '../data/sound_library.dart';
import 'audio_engine.dart';

const String kTagToLevel = 'toLevel';
const String kTagToNormal = 'toNormal';
const String kTagFadeOut = 'fadeOut';
const String kTagFadeIn = 'fadeIn';
const String kTagCrossOut = 'crossOut';
const String kTagTransitionOut = 'transitionOut';

class PlaybackCoordinator {
  final AudioEngine engine;
  final SoundLibrary library;
  final SettingsRepository settings;
  final SyncChannelPort channel;
  final ServerClock clock;

  /// Mesaj discret pentru UI (ex. „Ultimul sunet din listă”).
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// Ultimul sunet pornit / selectat (referința pentru Următorul / Anterior).
  final ValueNotifier<String?> currentId = ValueNotifier<String?>(null);

  /// Cel puțin un sunet rulează (pentru butonul Pauză/Reluare din dock).
  final ValueNotifier<bool> anyPlaying = ValueNotifier<bool>(false);

  /// Dacă ultima scriere în baza de date a eșuat (afișat în bara de stare).
  final ValueNotifier<String?> syncError = ValueNotifier<String?>(null);

  PlaybackState _state = PlaybackState.idle;
  String? _syncedId;
  int _lastSeq = 0;
  /// Epoca crește la „Oprește tot”; token-ul pe sunet crește la fiecare play/stop
  /// al acelui sunet. Un start programat se anulează doar dacă i s-a dat contraordin.
  int _epoch = 0;
  final Map<String, int> _tokens = <String, int>{};
  int _bump(String id) => _tokens[id] = (_tokens[id] ?? 0) + 1;
  bool _stale(String id, int token, int epoch) =>
      epoch != _epoch || _tokens[id] != token;
  bool _beatArmed = false;
  int _audioLatencyMs = 40; // medie mobilă a latenței de pornire audio
  Timer? _beatTimer;
  Timer? _noticeTimer;
  StreamSubscription<EngineEvent>? _engineSub;
  final Map<String, Completer<void>> _rampWaiters = <String, Completer<void>>{};
  bool _disposed = false;

  PlaybackCoordinator({
    required this.engine,
    required this.library,
    required this.settings,
    required this.channel,
    required this.clock,
  });

  AppSettings get _s => settings.value;

  PlaybackState get state => _state;
  String? get syncedId => _syncedId;
  int get audioLatencyMs => _audioLatencyMs;

  // ═════════════════════════════════════════════════════════════════════════
  // Inițializare
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> init() async {
    try {
      _lastSeq = (await channel.readPlayback()).seq;
      await channel.armControlDisconnect();
    } catch (_) {/* offline la pornire: seq se ia din ceasul serverului */}

    engine.master.value = _s.masterVolume;
    engine.curve = _s.fadeCurve;
    settings.settings.addListener(_onSettings);
    library.items.addListener(_onItemsChanged);
    _engineSub = engine.events.listen(_onEngineEvent);
    _restartHeartbeat();

    // curăță o stare veche rămasă în DB (displayul nu trebuie să arate nimic)
    await _publishStopped();
    unawaited(_preloadAll());
  }

  Future<void> _preloadAll() async {
    for (final it in library.items.value) {
      if (_disposed) return;
      // doar sunetele scurte: un fișier mare se încarcă la apăsare (nu umplem memoria)
      if (it.durationMs > 0 && it.durationMs <= 120000) await engine.preload(it);
    }
  }

  void _onSettings() {
    engine.master.value = _s.masterVolume;
    engine.curve = _s.fadeCurve;
    _restartHeartbeat();
  }

  SoundItem? _syncedSnapshot;

  /// Tăiere / buclă modificate cât timp video-ul rulează → republicăm starea.
  void _onItemsChanged() {
    for (final it in library.items.value) {
      engine.updateItem(it);
    }
    final id = _syncedId;
    if (id == null) return;
    final cur = library.byId(id);
    final old = _syncedSnapshot;
    if (cur == null) return;
    _syncedSnapshot = cur;
    if (old == null) return;
    if (cur.trimStartMs != old.trimStartMs ||
        cur.effectiveTrimEndMs != old.effectiveTrimEndMs ||
        cur.loop != old.loop) {
      final playing = engine.isPlaying(id);
      unawaited(_publish(
        playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        cur,
        positionMs: engine.positionMs(id),
        anchorTs: clock.serverNowMs,
      ));
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Publicare stare
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> _write(Future<void> Function() op) async {
    try {
      await op();
      if (syncError.value != null) syncError.value = null;
    } catch (e) {
      syncError.value = 'Scriere în baza de date eșuată: $e';
    }
  }

  Future<void> _publish(
    PlaybackStatus status,
    SoundItem item, {
    required int positionMs,
    required int anchorTs,
    int? fadeStartTs,
    int? fadeMs,
  }) {
    final seq = nextSeq(_lastSeq, clock.serverNowMs);
    _lastSeq = seq;
    _state = PlaybackState(
      seq: seq,
      itemId: item.id,
      status: status,
      positionMs: positionMs,
      anchorTs: anchorTs,
      rate: 1.0,
      trimStartMs: item.trimStartMs,
      trimEndMs: item.effectiveTrimEndMs,
      loop: item.loop,
      fadeOutStartTs: fadeStartTs,
      fadeOutMs: fadeMs,
    );
    return _write(() => channel.writePlayback(_state));
  }

  Future<void> _publishStopped() {
    final seq = nextSeq(_lastSeq, clock.serverNowMs);
    _lastSeq = seq;
    _state = PlaybackState(
      seq: seq,
      itemId: null,
      status: PlaybackStatus.stopped,
      positionMs: 0,
      anchorTs: clock.serverNowMs,
    );
    _beatArmed = false;
    return _write(() => channel.writePlayback(_state));
  }

  // ── heartbeat (~1 s) ──────────────────────────────────────────────────────
  void _restartHeartbeat() {
    _beatTimer?.cancel();
    _beatTimer = Timer.periodic(
      Duration(milliseconds: _s.heartbeatMs),
      (_) => _sendHeartbeat(),
    );
  }

  /// Scrie poziția REALĂ a audio la momentul de server corespunzător. Nu se trimite
  /// înainte ca audio să fi pornit efectiv (altfel displayul ar porni prea devreme).
  void _sendHeartbeat() {
    final id = _syncedId;
    if (id == null || !_beatArmed || !_state.isActive) return;
    if (!engine.isActive(id)) return;
    final playing = engine.isPlaying(id);
    final pos = engine.positionMs(id);
    final ts = clock.serverNowMs;
    unawaited(_write(() => channel.writeHeartbeat(Heartbeat(
          seq: _state.seq,
          itemId: id,
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          positionMs: pos,
          anchorTs: ts,
        ))));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Play / Pauză / Seek / Stop
  // ═════════════════════════════════════════════════════════════════════════
  /// Un singur gest: dacă rulează → oprește, altfel pornește.
  Future<void> togglePad(SoundItem item) async {
    if (engine.isActive(item.id)) {
      await stop(item.id);
    } else {
      await play(item);
    }
  }

  Future<void> play(
    SoundItem item, {
    bool fromTransition = false,
    int? fadeInMs,
  }) async {
    if (library.health.value[item.id] == MediaHealth.missing) {
      _notice('Fișier lipsă pentru „${item.name}” — re-adaugă-l din Gestionare.');
      return;
    }
    currentId.value = item.id;
    final fadeIn = fadeInMs ?? (item.fadeInMs > 0 ? item.fadeInMs : _s.defaultFadeInMs);
    final token = _bump(item.id);
    final epoch = _epoch;

    if (item.isVideo) {
      await _playVideo(item, fadeIn, token, epoch, fromTransition);
    } else {
      final ok = await engine.start(item, startVolume: fadeIn > 0 ? 0.0 : item.volume);
      if (!ok) {
        _notice('Nu s-a putut reda „${item.name}”.');
        return;
      }
      if (fadeIn > 0) engine.rampTo(item.id, item.volume, ms: fadeIn, tag: kTagFadeIn);
    }
    _refreshAnyPlaying();
  }

  Future<void> _playVideo(SoundItem item, int fadeIn, int token, int epoch,
      bool fromTransition) async {
    // doar UN video sincronizat odată: pornirea altuia îl oprește pe cel curent
    final prev = _syncedId;
    if (prev != null && prev != item.id && !fromTransition) {
      await engine.stop(prev, fadeMs: 0);
    }

    final ok = await engine.arm(item, startVolume: fadeIn > 0 ? 0.0 : item.volume);
    if (!ok) {
      _notice('Nu s-a putut reda „${item.name}”.');
      return;
    }
    if (_stale(item.id, token, epoch)) {
      // între timp a venit un contraordin (stop / alt play al aceluiași sunet)
      if (!engine.isPlaying(item.id)) await engine.stop(item.id, fadeMs: 0);
      return;
    }

    _syncedId = item.id;
    _syncedSnapshot = item;
    _beatArmed = false;

    // start programat: control și display pornesc la același moment de server
    final lead = adaptiveLeadMs(baseLeadMs: _s.leadMs, rttMs: clock.bestRttMs);
    final startAt = scheduledStartTs(clock.serverNowMs, lead);
    await _publish(PlaybackStatus.playing, item,
        positionMs: item.trimStartMs, anchorTs: startAt);

    await _waitUntil(startAt - _audioLatencyMs);
    if (_stale(item.id, token, epoch) ||
        _syncedId != item.id ||
        !engine.isActive(item.id)) {
      return; // oprit între timp
    }

    final tPlay = clock.serverNowMs;
    await engine.go(item.id);
    if (fadeIn > 0) engine.rampTo(item.id, item.volume, ms: fadeIn, tag: kTagFadeIn);
    unawaited(_measureStartLatency(item, tPlay, fromMs: item.trimStartMs));
  }

  Future<void> _waitUntil(int serverTs) async {
    final wait = serverTs - clock.serverNowMs;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
  }

  /// Latența reală de pornire: de la play() până la prima avansare a poziției.
  /// Ancora corectată se publică IMEDIAT într-un heartbeat.
  Future<void> _measureStartLatency(SoundItem item, int tPlay,
      {required int fromMs}) async {
    final base = fromMs;
    for (var i = 0; i < 120; i++) {
      if (_disposed || _syncedId != item.id) return;
      if (engine.positionMs(item.id) > base + 3) {
        final measured = clock.serverNowMs - tPlay;
        if (measured >= 0 && measured < 2000) {
          _audioLatencyMs = ((_audioLatencyMs * 0.6) + (measured * 0.4)).round();
        }
        _beatArmed = true;
        _sendHeartbeat();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // poziția nu s-a mișcat (autoplay blocat?): avertizăm, dar nu blocăm
    _beatArmed = true;
    _notice('Audio nu a pornit — fă un click în pagina de control și reîncearcă.');
  }

  Future<void> pause(String id) async {
    if (!engine.isPlaying(id)) return;
    await engine.pause(id);
    if (id == _syncedId) {
      final item = library.byId(id);
      if (item != null) {
        await _publish(PlaybackStatus.paused, item,
            positionMs: engine.positionMs(id), anchorTs: clock.serverNowMs);
        _beatArmed = true;
      }
    }
    _refreshAnyPlaying();
  }

  Future<void> resume(String id) async {
    if (!engine.isPaused(id)) return;
    final item = library.byId(id);
    if (item == null) return;
    if (id == _syncedId) {
      final lead = adaptiveLeadMs(baseLeadMs: _s.leadMs, rttMs: clock.bestRttMs);
      final startAt = scheduledStartTs(clock.serverNowMs, lead);
      _beatArmed = false;
      await _publish(PlaybackStatus.playing, item,
          positionMs: engine.positionMs(id), anchorTs: startAt);
      await _waitUntil(startAt - _audioLatencyMs);
      if (!engine.isPaused(id)) return;
      final from = engine.positionMs(id);
      final tPlay = clock.serverNowMs;
      await engine.resume(id);
      unawaited(_measureStartLatency(item, tPlay, fromMs: from));
    } else {
      await engine.resume(id);
    }
    _refreshAnyPlaying();
  }

  /// Pauză / Reluare globală (dock).
  Future<void> toggleGlobalPause() async {
    if (engine.anyPlaying) {
      for (final id in engine.playingIds) {
        await pause(id);
      }
    } else {
      for (final id in engine.activeIds) {
        if (engine.isPaused(id)) await resume(id);
      }
    }
  }

  Future<void> seek(String id, int ms) async {
    final item = library.byId(id);
    if (item == null || !engine.isActive(id)) return;
    final clamped = ms.clamp(item.trimStartMs, item.effectiveTrimEndMs).toInt();
    await engine.seek(id, clamped);
    if (id == _syncedId) {
      await _publish(
        engine.isPlaying(id) ? PlaybackStatus.playing : PlaybackStatus.paused,
        item,
        positionMs: engine.positionMs(id),
        anchorTs: clock.serverNowMs,
      );
      _sendHeartbeat();
    }
  }

  /// Restart de la trim_start, cu fade foarte scurt.
  Future<void> restart(String id) async {
    final item = library.byId(id);
    if (item == null || !engine.isActive(id)) return;
    await engine.softSeek(id, item.trimStartMs);
    if (id == _syncedId) {
      await _publish(
        engine.isPlaying(id) ? PlaybackStatus.playing : PlaybackStatus.paused,
        item,
        positionMs: engine.positionMs(id),
        anchorTs: clock.serverNowMs,
      );
      _sendHeartbeat();
    }
  }

  Future<void> stop(String id) async {
    _bump(id); // anulează un start programat în curs, chiar dacă vocea e încă în armare
    if (!engine.isActive(id)) return;
    await engine.stop(id);
    if (id == _syncedId) {
      _syncedId = null;
      await _publishStopped();
    }
    _refreshAnyPlaying();
  }

  /// „Oprește tot”: instant, anulează orice fade, oprește și video-ul sincronizat.
  Future<void> stopAll() async {
    _epoch++;
    for (final w in _rampWaiters.values) {
      if (!w.isCompleted) w.complete();
    }
    _rampWaiters.clear();
    await engine.stopAll();
    _syncedId = null;
    await _publishStopped();
    _refreshAnyPlaying();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Volum + fade
  // ═════════════════════════════════════════════════════════════════════════
  /// Mutarea slider-ului de volum al unui sunet (anulează rampa) + persistare.
  Timer? _volSave;
  void setSoundVolume(String id, double v) {
    final item = library.byId(id);
    if (item == null) return;
    if (engine.isActive(id)) engine.setChannelVolume(id, v);
    _volSave?.cancel();
    _volSave = Timer(const Duration(milliseconds: 400), () {
      final fresh = library.byId(id);
      if (fresh != null) unawaited(library.save(fresh.copyWith(volume: v)));
    });
  }

  void setMasterVolume(double v) {
    engine.master.value = v;
    settings.update((s) => s.copyWith(masterVolume: v));
  }

  bool _isRampingWith(String id, String tag) =>
      engine.fade.isRamping(id) && engine.fade.rampOf(id)?.tag == tag;

  /// „Fade la nivel”: de la volumul curent la target_level, lent.
  /// A doua apăsare cât rampa e activă o anulează (volumul rămâne unde a ajuns).
  void fadeToLevel(String id, {int? ms}) {
    final item = library.byId(id);
    if (item == null || !engine.isActive(id)) return;
    if (_isRampingWith(id, kTagToLevel)) {
      engine.fade.cancel(id);
      return;
    }
    engine.rampTo(id, item.targetLevel,
        ms: ms ?? resolveFadeMs(perItem: item.fadeToLevelMs, fallback: _s.defaultFadeToLevelMs),
        tag: kTagToLevel);
  }

  /// „Revino la normal”: de la volumul curent înapoi la volumul de bază.
  void returnToNormal(String id, {int? ms}) {
    final item = library.byId(id);
    if (item == null || !engine.isActive(id)) return;
    if (_isRampingWith(id, kTagToNormal)) {
      engine.fade.cancel(id);
      return;
    }
    engine.rampTo(id, item.volume,
        ms: ms ?? resolveFadeMs(perItem: item.fadeToLevelMs, fallback: _s.defaultFadeToLevelMs),
        tag: kTagToNormal);
  }

  /// „Fade-out”: la zero, lent (chiar și din mijlocul altei rampe). La final:
  /// oprire sau pauză (setare), iar volumul revine la valoarea de bază.
  void fadeOut(String id, {int? ms}) {
    final item = library.byId(id);
    if (item == null || !engine.isActive(id)) return;
    if (_isRampingWith(id, kTagFadeOut)) {
      engine.fade.cancel(id);
      return;
    }
    final dur = ms ?? resolveFadeMs(perItem: item.fadeOutMs, fallback: _s.defaultFadeOutMs);
    engine.rampTo(id, 0.0, ms: dur, tag: kTagFadeOut);

    // opțional: și imaginea face fade-out, calculat de display din același ceas
    if (id == _syncedId && _s.fadeImageWithAudio) {
      unawaited(_publish(PlaybackStatus.playing, item,
          positionMs: engine.positionMs(id),
          anchorTs: clock.serverNowMs,
          fadeStartTs: clock.serverNowMs,
          fadeMs: dur));
    }
  }

  void fadeOutAll() {
    for (final id in engine.playingIds) {
      fadeOut(id);
    }
  }

  void fadeToLevelAll() {
    for (final id in engine.playingIds) {
      fadeToLevel(id);
    }
  }

  void returnToNormalAll() {
    for (final id in engine.playingIds) {
      returnToNormal(id);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Evenimente de la motor
  // ═════════════════════════════════════════════════════════════════════════
  void _onEngineEvent(EngineEvent e) {
    switch (e.kind) {
      case EngineEventKind.rampDone:
        _onRampDone(e.itemId, e.tag);
        break;
      case EngineEventKind.ended:
        _onEnded(e);
        break;
    }
  }

  void _onRampDone(String id, Object? tag) {
    final w = _rampWaiters.remove(id);
    if (w != null && !w.isCompleted) w.complete();

    if (tag == kTagFadeOut) {
      unawaited(_afterFadeOut(id));
    } else if (tag == kTagCrossOut) {
      unawaited(_afterCrossOut(id));
    }
  }

  Future<void> _afterFadeOut(String id) async {
    if (!engine.isActive(id)) return;
    final item = library.byId(id);
    if (_s.afterFadeOut == AfterFadeOut.pause) {
      await engine.pause(id, fadeMs: 0, resumeVolume: item?.volume ?? 1.0);
      if (id == _syncedId && item != null) {
        await _publish(PlaybackStatus.paused, item,
            positionMs: engine.positionMs(id), anchorTs: clock.serverNowMs);
      }
    } else {
      await engine.stop(id, fadeMs: 0); // restabilește și volumul de bază
      if (id == _syncedId) {
        _syncedId = null;
        await _publishStopped(); // imaginea se oprește exact la sfârșitul rampei
      }
    }
    _refreshAnyPlaying();
  }

  Future<void> _afterCrossOut(String id) async {
    await engine.stop(id, fadeMs: 0);
    if (id == _syncedId) {
      // nu a pornit alt video între timp (audio → audio / video → audio)
      _syncedId = null;
      await _publishStopped();
    }
    _refreshAnyPlaying();
  }

  void _onEnded(EngineEvent e) {
    final id = e.itemId;
    if (id == _syncedId && e.natural) {
      _syncedId = null;
      unawaited(_publishStopped());
    }
    _refreshAnyPlaying();

    final item = library.byId(id);
    if (e.natural &&
        item != null &&
        currentId.value == id &&
        shouldAutoAdvance(
          autoAdvance: _s.autoAdvance,
          itemLoops: item.loop,
          endedNaturally: true,
        )) {
      unawaited(next());
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Următorul / Anterior
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> next({NextTransition? mode}) => _step(1, mode);
  Future<void> previous({NextTransition? mode}) => _step(-1, mode);

  Future<void> _step(int direction, NextTransition? override) async {
    final ordered = library.items.value.map((e) => e.id).toList();
    final r = neighbor(
      orderedIds: ordered,
      currentId: currentId.value,
      direction: direction,
      loop: _s.loopPlaylist,
    );
    if (r.id == null) {
      _notice(direction > 0 ? 'Ultimul sunet din listă' : 'Primul sunet din listă');
      return;
    }
    final target = library.byId(r.id!);
    if (target == null) return;

    final cur = currentId.value;
    final curActive = cur != null && cur != target.id && engine.isActive(cur);
    final mode = override ?? _s.nextTransition;
    final ms = _s.nextFadeMs;

    switch (mode) {
      case NextTransition.cut:
        if (curActive) await stop(cur);
        await play(target);
        break;

      case NextTransition.fadeThenStart:
        if (curActive) {
          await _fadeOutAndWait(cur, ms);
          await stop(cur);
        }
        await play(target);
        break;

      case NextTransition.crossfade:
        if (curActive) {
          // cel curent iese în fade; următorul intră în același timp
          engine.rampTo(cur, 0.0, ms: ms, tag: kTagCrossOut);
        }
        await play(target, fromTransition: true, fadeInMs: curActive ? ms : null);
        break;
    }
  }

  Future<void> _fadeOutAndWait(String id, int ms) {
    final c = Completer<void>();
    _rampWaiters[id] = c;
    engine.rampTo(id, 0.0, ms: ms, tag: kTagTransitionOut);
    if (!engine.fade.isRamping(id) && !c.isCompleted) c.complete();
    return c.future.timeout(Duration(milliseconds: ms + 800), onTimeout: () {});
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UI helpers
  // ═════════════════════════════════════════════════════════════════════════
  void _refreshAnyPlaying() {
    anyPlaying.value = engine.anyPlaying;
  }

  void _notice(String msg) {
    notice.value = msg;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (notice.value == msg) notice.value = null;
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _beatTimer?.cancel();
    _noticeTimer?.cancel();
    _volSave?.cancel();
    settings.settings.removeListener(_onSettings);
    library.items.removeListener(_onItemsChanged);
    await _engineSub?.cancel();
    notice.dispose();
    currentId.dispose();
    anyPlaying.dispose();
    syncError.dispose();
  }
}
