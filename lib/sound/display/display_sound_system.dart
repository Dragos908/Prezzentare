// lib/sound/display/display_sound_system.dart
//
// Compoziția sistemului de sunet pe pagina de prezentare: guard (mut), ceas comun,
// follower de sincronizare. Video-ul sunetelor se redă din linkul (Google Drive)
// scris în baza de date, nu din aplicație. Se creează o singură dată de DisplayPage.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/drive_link.dart';
import '../core/clock_sync.dart';
import '../core/models.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';
import '../data/rtdb_sync_channel.dart';
import 'display_audio_guard.dart';
import 'display_sync_follower.dart';
import 'video_player_adapter.dart';

class DisplaySoundSystem with WidgetsBindingObserver {
  late final RtdbSyncChannel _channel = RtdbSyncChannel();
  final MonoClock _mono = SystemMonoClock();
  late final ClockSync _clock = ClockSync(mono: _mono, source: _channel);

  /// Sursa redabilă a video-ului unui sunet: linkul scris în baza de date. Un link
  /// Google Drive (…/file/d/ID/view) devine URL de descărcare directă, iar orice
  /// alt link https rămâne neschimbat. null = sunetul n-are încă link, deci
  /// displayul nu arată nimic. Video-ul nu e în aplicație și nu se ține în cache.
  static Future<String?> _resolveVideo(SoundItem item) async {
    final link = item.videoUrl;
    if (link == null || link.trim().isEmpty) return null;
    return DriveLink.playableUrl(link);
  }

  /// Creat leneș (poate fi citit în build chiar înainte de start()).
  late final DisplaySyncFollower follower = DisplaySyncFollower(
    channel: _channel,
    clock: ClockSyncServerClock(_clock),
    mono: _mono,
    createPort: () => FlutterVideoPort(),
    resolveMediaUrl: _resolveVideo,
    guard: guard,
  );
  final DisplayAudioGuard guard = DisplayAudioGuard.instance;

  bool _started = false;

  /// True ~150 ms în momentul `startAt` al testului de calibrare (bliț alb).
  final ValueNotifier<bool> calibrationFlash = ValueNotifier<bool>(false);
  StreamSubscription<int>? _calSub;
  final Set<int> _calSeen = <int>{};

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // 1) mut garantat de la început (implicit activ, înainte de orice setare)
    guard.setMuted(true);
    guard.startAudit();

    _calSub = _channel.calibrationStream().listen(_onCalibration);
    WidgetsBinding.instance.addObserver(this);
    // 2) ceasul comun, apoi follower-ul (setările sosesc imediat din stream)
    unawaited(_clock.start());
    await follower.start();
  }

  void _onCalibration(int startAt) {
    if (!_calSeen.add(startAt)) return; // aceeași comandă, o singură dată
    final wait = startAt - _clock.serverNowMs;
    if (wait < -1500) return; // comandă veche (citită la conectare)
    Timer(Duration(milliseconds: wait < 0 ? 0 : wait), () {
      calibrationFlash.value = true;
      Timer(const Duration(milliseconds: 150), () => calibrationFlash.value = false);
    });
  }

  /// Revenire din fundal → citește starea din DB și sare la poziția corectă.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) {
      unawaited(follower.resync());
    }
  }

  Future<void> dispose() async {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    await _calSub?.cancel();
    await follower.dispose();
    _clock.dispose();
    guard.stopAudit();
  }
}
