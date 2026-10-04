// lib/sound/display/display_media_factory.dart
//
// SINGURUL loc din codul displayului unde se creează playere video. Orice player
// creat aici este înregistrat în DisplayAudioGuard. Un test static
// (test/display_audio_static_test.dart) eșuează dacă în lib/features/display sau
// lib/sound/display apare un player creat direct, în afara acestui fișier.

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'display_audio_guard.dart';

class _GuardedVideo implements GuardedMedia {
  final VideoPlayerController controller;
  final DisplayAudioGuard guard;
  @override
  final String label;

  _GuardedVideo(this.controller, this.guard, this.label);

  void attach() {
    controller.addListener(_onChange);
    guard.register(this);
  }

  void detach() {
    controller.removeListener(_onChange);
    guard.unregister(this);
  }

  // La orice schimbare de stare (initialize / play / volume): dacă a apărut
  // volum cât timp displayul e mut, îl readucem imediat la 0.
  void _onChange() {
    if (guard.muted && controller.value.volume > 0.0) {
      controller.setVolume(0);
    }
  }

  @override
  double readVolume() => controller.value.volume;

  @override
  void forceMute() {
    controller.setVolume(0);
  }
}

class DisplayMediaFactory {
  final DisplayAudioGuard guard;
  final Map<VideoPlayerController, _GuardedVideo> _live =
      <VideoPlayerController, _GuardedVideo>{};

  DisplayMediaFactory([DisplayAudioGuard? guard])
      : guard = guard ?? DisplayAudioGuard.instance;

  static final DisplayMediaFactory instance = DisplayMediaFactory();

  VideoPlayerController createAsset(String asset, {String label = 'asset'}) =>
      _wrap(VideoPlayerController.asset(asset), label);

  VideoPlayerController createNetwork(Uri uri, {String label = 'network'}) =>
      _wrap(VideoPlayerController.networkUrl(uri), label);

  VideoPlayerController _wrap(VideoPlayerController c, String label) {
    final g = _GuardedVideo(c, guard, label);
    _live[c] = g;
    g.attach();
    // volum 0 ÎNAINTE de initialize: video_player îl aplică la inițializare
    if (guard.muted) c.setVolume(0);
    return c;
  }

  /// Volumul pe care are voie să-l ceară un widget (0 cât timp displayul e mut).
  double allowedVolume(double requested) => guard.effectiveVolume(requested);

  /// Elibera ÎNTOTDEAUNA prin fabrică (scoate din guard, apoi dispose).
  Future<void> release(VideoPlayerController c) async {
    _live.remove(c)?.detach();
    await c.dispose();
  }

  @visibleForTesting
  int get liveCount => _live.length;
}
