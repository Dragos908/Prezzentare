// lib/sound/core/ports.dart
//
// Interfețele (porturile) din spatele cărora stau pluginurile. DART PUR:
// logica (sincronizare, fade, coordonare) vorbește doar cu aceste interfețe,
// deci se testează cu implementări „fake”, fără Flutter sau plugin-uri.

import 'dart:async';
import 'dart:typed_data';

import 'clock_sync.dart';
import 'models.dart';

/// Player audio (control). Implementare: just_audio.
abstract class AudioPlayerPort {
  /// Încarcă sursa; întoarce durata în ms (dacă o știe).
  Future<int?> load(String url);

  /// Pornește redarea. NU așteaptă sfârșitul redării.
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);

  /// Volumul efectiv 0..1 (deja înmulțit cu master).
  void setVolume(double v);

  int get positionMs;
  bool get isPlaying;
  int? get durationMs;

  /// Emite când fișierul a ajuns la sfârșitul NATURAL.
  Stream<void> get completed;

  Future<void> dispose();
}

typedef AudioPlayerFactory = AudioPlayerPort Function();

/// Player video (display), ÎNTOTDEAUNA mut pentru conținutul sincronizat.
abstract class VideoPlayerPort {
  /// [url] = URL direct redabil (link direct https sau linkul Google Drive deja
  /// transformat de `DriveLink.playableUrl`). Video-ul nu e în aplicație.
  Future<void> initialize(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(int ms);

  /// Citire ASINCRONĂ a poziției reale (nu `value.position`, actualizat rar).
  Future<int> readPositionMs();
  Future<void> setPlaybackSpeed(double rate);
  Future<void> setVolume(double v);

  double get volume;
  bool get isInitialized;
  bool get isBuffering;
  bool get isPlaying;
  int get durationMs;

  /// Dimensiunea nativă a imaginii (pentru încadrare).
  double get videoWidth;
  double get videoHeight;

  Future<void> dispose();
}

typedef VideoPortFactory = VideoPlayerPort Function();

/// Stocare locală persistentă pentru fișierele audio/video importate pe control.
abstract class MediaStorePort {
  Future<void> init();
  Future<void> put(String key, Uint8List bytes, String mime);
  Future<bool> has(String key);

  /// URL redabil local (ex. blob:) sau null dacă fișierul lipsește.
  Future<String?> playableUrl(String key);
  Future<void> delete(String key);
  Future<int> totalBytes();
  Future<void> clear();

  /// Spațiul liber estimat (octeți) sau null dacă platforma nu îl poate spune.
  Future<double?> freeBytes();
}

/// Ceasul de server văzut de follower/coordinator.
abstract class ServerClock {
  int get serverNowMs;
  bool get isSynced;
  int? get bestRttMs;
}

/// Adaptează ClockSync la interfața ServerClock (folosit pe control și pe display).
class ClockSyncServerClock implements ServerClock {
  final ClockSync _c;
  ClockSyncServerClock(this._c);
  @override
  int get serverNowMs => _c.serverNowMs;
  @override
  bool get isSynced => _c.isSynced;
  @override
  int? get bestRttMs => _c.bestRttMs;
}

/// Canalul realtime către baza de date. Implementare: Firebase RTDB.
/// Control și display comunică DOAR prin acest canal.
abstract class SyncChannelPort extends ServerTimeProbe {
  // setări
  Stream<AppSettings> settingsStream();
  Future<void> saveSettings(Map<String, Object?> values);

  // biblioteca de sunete (metadate)
  Stream<List<SoundItem>> itemsStream();
  Future<void> upsertItem(SoundItem item);
  Future<void> deleteItem(String id);
  Future<void> setOrder(List<String> orderedIds);

  // stare de redare + heartbeat
  Stream<PlaybackState> playbackStream();
  Future<PlaybackState> readPlayback();
  Future<void> writePlayback(PlaybackState state);
  Stream<Heartbeat> heartbeatStream();
  Future<void> writeHeartbeat(Heartbeat beat);

  // starea displayului
  Stream<DisplayStatus> displayStatusStream();
  Future<void> writeDisplayStatus(DisplayStatus status);

  // calibrare A/V: controlul scrie `startAt` (timp de server), displayul
  // clipește alb exact atunci, iar controlul redă un bip la același moment
  Stream<int> calibrationStream();
  Future<void> triggerCalibration(int startAtTs);

  // best-effort la închidere
  Future<void> armDisplayDisconnect();
  Future<void> armControlDisconnect();
}
