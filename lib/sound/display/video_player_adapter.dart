// lib/sound/display/video_player_adapter.dart
//
// VideoPlayerPort peste video_player. Playerul se creează EXCLUSIV prin
// DisplayMediaFactory (deci e mutat de guard). Imaginea e afișată fără sunet.

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../core/ports.dart';
import 'display_media_factory.dart';

class FlutterVideoPort implements VideoPlayerPort {
  final DisplayMediaFactory mediaFactory;
  VideoPlayerController? _c;

  FlutterVideoPort({DisplayMediaFactory? mediaFactory})
      : mediaFactory = mediaFactory ?? DisplayMediaFactory.instance;

  VideoPlayerController get _ctrl {
    final c = _c;
    if (c == null) throw StateError('FlutterVideoPort neinițializat');
    return c;
  }

  @override
  Future<void> initialize(String url) async {
    // URL direct de redare: linkul din baza de date (Google Drive sau link direct),
    // deja transformat de DriveLink.playableUrl. Video-ul nu e în aplicație.
    final c = mediaFactory.createNetwork(Uri.parse(url), label: 'sync-overlay');
    _c = c;
    try {
      await c.initialize();
    } catch (_) {
      _c = null;
      await mediaFactory.release(c);
      rethrow;
    }
    await c.setLooping(false); // bucla se face din poziția așteptată, nu din player
    await c.setVolume(0);
  }

  @override
  Future<void> play() => _ctrl.play();

  @override
  Future<void> pause() => _ctrl.pause();

  @override
  Future<void> seekTo(int ms) => _ctrl.seekTo(Duration(milliseconds: ms < 0 ? 0 : ms));

  @override
  Future<int> readPositionMs() async {
    final c = _ctrl;
    final p = await c.position; // citire reală, asincronă
    return (p ?? c.value.position).inMilliseconds;
  }

  @override
  Future<void> setPlaybackSpeed(double rate) => _ctrl.setPlaybackSpeed(rate);

  @override
  Future<void> setVolume(double v) => _ctrl.setVolume(mediaFactory.allowedVolume(0));

  @override
  double get volume => _c?.value.volume ?? 0;

  @override
  bool get isInitialized => _c?.value.isInitialized ?? false;

  @override
  bool get isBuffering => _c?.value.isBuffering ?? false;

  @override
  bool get isPlaying => _c?.value.isPlaying ?? false;

  @override
  int get durationMs => _c?.value.duration.inMilliseconds ?? 0;

  @override
  double get videoWidth => _c?.value.size.width ?? 0;

  @override
  double get videoHeight => _c?.value.size.height ?? 0;

  /// Widgetul care desenează imaginea (folosit de overlay).
  Widget buildView() => VideoPlayer(_ctrl);

  @override
  Future<void> dispose() async {
    final c = _c;
    _c = null;
    if (c != null) await mediaFactory.release(c);
  }
}
