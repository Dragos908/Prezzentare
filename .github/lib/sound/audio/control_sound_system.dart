// lib/sound/audio/control_sound_system.dart
//
// Compoziția (composition root) a sistemului de sunet pe pagina de control:
// canal RTDB, ceas comun, setări, bibliotecă + magazie locală, motor audio,
// coordonator. O singură instanță pe sesiune, partajată de pagina de control și
// de pagina de Setări. Serviciile primesc dependențele prin constructor, deci
// testele le înlocuiesc cu implementări fake (vezi test/sound/).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock_sync.dart';
import '../core/models.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';
import '../data/bundled_videos.dart';
import '../data/hive_media_store.dart';
import '../data/rtdb_sync_channel.dart';
import '../data/settings_repository.dart';
import '../data/sound_library.dart';
import 'audio_engine.dart';
import 'calibration_service.dart';
import 'just_audio_port.dart';
import 'playback_coordinator.dart';

class ControlSoundSystem {
  ControlSoundSystem._();
  static final ControlSoundSystem instance = ControlSoundSystem._();

  late final RtdbSyncChannel channel = RtdbSyncChannel();
  final MonoClock mono = SystemMonoClock();
  late final ClockSync clockSync = ClockSync(mono: mono, source: channel);
  late final SettingsRepository settings = SettingsRepository(channel);
  late final HiveMediaStore store = HiveMediaStore(namespace: 'sound_media');
  late final SoundLibrary library = SoundLibrary(
    channel: channel,
    store: store,
    playerFactory: () => JustAudioPort(),
    bundledVideos: BundledVideos(),
  );
  late final AudioEngine engine = AudioEngine(
    clock: mono,
    createPlayer: () => JustAudioPort(),
    resolveUrl: store.playableUrl,
  );
  late final PlaybackCoordinator coordinator = PlaybackCoordinator(
    engine: engine,
    library: library,
    settings: settings,
    channel: channel,
    clock: ClockSyncServerClock(clockSync),
  );

  late final CalibrationService calibration = CalibrationService(
    channel: channel,
    clock: ClockSyncServerClock(clockSync),
    audioLatencyMs: () => coordinator.audioLatencyMs,
  );

  /// Starea displayului, scrisă de el la ~1 s.
  final ValueNotifier<DisplayStatus> displayStatus =
      ValueNotifier<DisplayStatus>(const DisplayStatus());

  StreamSubscription<DisplayStatus>? _dsSub;
  Future<void>? _starting;

  int get serverNowMs => clockSync.serverNowMs;

  /// Idempotent: poate fi apelat din orice pagină.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    settings.start();
    unawaited(clockSync.start());
    await library.start();
    _dsSub = channel.displayStatusStream().listen((d) => displayStatus.value = d);
    await coordinator.init();
  }

  Future<void> dispose() async {
    await _dsSub?.cancel();
    clockSync.dispose();
    await coordinator.dispose();
    await engine.dispose();
    library.dispose();
    settings.dispose();
  }
}
