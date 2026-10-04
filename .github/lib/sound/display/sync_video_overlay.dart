// lib/sound/display/sync_video_overlay.dart
//
// Stratul (overlay) pe tot ecranul în care apare IMAGINEA sunetelor video,
// deasupra conținutului curent, fără să schimbe ruta sau starea de dedesubt.
// Când nu e nimic de arătat, nu desenează nimic (SizedBox.shrink). Imaginea e
// încadrată `contain` pe fundal negru: nu taie cadrul, iar stratul acoperă tot
// ecranul. Ignoră gesturile, ca să nu blocheze controlul laser / clic-urile.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'display_sync_follower.dart';
import 'video_player_adapter.dart';

class SyncVideoOverlay extends StatelessWidget {
  final DisplaySyncFollower follower;

  /// Bliț alb scurt pentru testul de calibrare A/V (opțional).
  final ValueListenable<bool>? flash;

  const SyncVideoOverlay({super.key, required this.follower, this.flash});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<ActiveVideo?>(
              valueListenable: follower.active,
              builder: (context, video, _) => _video(video),
            ),
            if (flash != null)
              ValueListenableBuilder<bool>(
                valueListenable: flash!,
                builder: (context, on, _) =>
                    on ? const ColoredBox(color: Colors.white) : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _video(ActiveVideo? video) {
    if (video == null) return const SizedBox.shrink();
    final port = video.port;
    if (port is! FlutterVideoPort || !port.isInitialized) {
      return const SizedBox.shrink();
    }
    final w = port.videoWidth <= 0 ? 16.0 : port.videoWidth;
    final h = port.videoHeight <= 0 ? 9.0 : port.videoHeight;
    return _FadingLayer(
      follower: follower,
      child: ColoredBox(
        color: Colors.black,
        child: RepaintBoundary(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: w, height: h, child: port.buildView()),
          ),
        ),
      ),
    );
  }
}

/// Aplică fade-ul opțional al imaginii, calculat per cadru din ceasul de server.
/// Rulează un Ticker DOAR cât timp fade-ul e activ.
class _FadingLayer extends StatefulWidget {
  final DisplaySyncFollower follower;
  final Widget child;
  const _FadingLayer({required this.follower, required this.child});

  @override
  State<_FadingLayer> createState() => _FadingLayerState();
}

class _FadingLayerState extends State<_FadingLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final o = widget.follower.imageOpacity;
      if (o != _opacity) setState(() => _opacity = o);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_opacity >= 1.0) return widget.child;
    return Opacity(opacity: _opacity.clamp(0.0, 1.0).toDouble(), child: widget.child);
  }
}
