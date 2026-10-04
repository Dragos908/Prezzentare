// lib/sound/audio/just_audio_port.dart
//
// AudioPlayerPort peste just_audio (suportă Web: HTMLAudioElement). Sursa e un URL
// (ex. blob: din magazia locală). Fișierele video se redau doar ca audio (se aude
// doar pista audio, direct din fișierul video).

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../core/ports.dart';

class JustAudioPort implements AudioPlayerPort {
  final AudioPlayer _p = AudioPlayer();

  @override
  Future<int?> load(String url) async {
    final d = await _p.setUrl(url);
    return d?.inMilliseconds;
  }

  /// just_audio: `play()` se termină abia la sfârșitul redării → NU îl așteptăm.
  @override
  Future<void> play() {
    unawaited(_p.play().catchError((Object _) {}));
    return Future<void>.value();
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(int ms) =>
      _p.seek(Duration(milliseconds: ms < 0 ? 0 : ms));

  @override
  void setVolume(double v) {
    unawaited(_p.setVolume(v.clamp(0.0, 1.0).toDouble()));
  }

  @override
  int get positionMs => _p.position.inMilliseconds;

  @override
  bool get isPlaying => _p.playing;

  @override
  int? get durationMs => _p.duration?.inMilliseconds;

  @override
  Stream<void> get completed => _p.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> dispose() => _p.dispose();
}
