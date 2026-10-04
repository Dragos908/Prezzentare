// lib/sound/audio/calibration_service.dart
//
// Test de calibrare A/V: controlul alege un moment de server (start_at), displayul
// clipește alb exact atunci, iar controlul redă un bip la același moment (compensat
// cu latența de pornire audio măsurată). Dacă bipul se aude înaintea / după bliț,
// operatorul ajustează `avSyncOffsetMs` în Setări.

import 'dart:async';

import '../core/ports.dart';
import '../data/web_blob.dart';
import 'calibration_tone.dart';
import 'just_audio_port.dart';

class CalibrationService {
  final SyncChannelPort channel;
  final ServerClock clock;
  final int Function() audioLatencyMs;

  CalibrationService({
    required this.channel,
    required this.clock,
    required this.audioLatencyMs,
  });

  /// Pornește testul; întoarce momentul (timp de server) la care au fost programate
  /// blițul și bipul.
  Future<int> run({int leadMs = 1500}) async {
    final startAt = clock.serverNowMs + leadMs;
    await channel.triggerCalibration(startAt);

    final url = createBlobUrl(buildBeepWav(), 'audio/wav');
    final player = JustAudioPort();
    try {
      await player.load(url);
      await player.seek(0);
      player.setVolume(1.0);
      final wait = startAt - clock.serverNowMs - audioLatencyMs();
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } finally {
      await player.dispose();
      revokeBlobUrl(url);
    }
    return startAt;
  }
}
