// lib/features/display/widgets/slide_intro_widget.dart
//
// Dacă slide-ul intro are câmpul `url` completat, redă un video YouTube
// fullscreen (autoplay, loop, fără controale, fără click).
//
// URL acceptat:
//   • standard:  https://www.youtube.com/watch?v=XXXX
//   • embed:     https://www.youtube.com/embed/XXXX
//   • scurt:     https://youtu.be/XXXX
//
// Dacă `url` lipsește → layout clasic cu orb-uri animate și text.

import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/model.dart';

class SlideIntroWidget extends StatefulWidget {
  final SlideModel slide;
  const SlideIntroWidget({required this.slide, super.key});

  @override
  State<SlideIntroWidget> createState() => _SlideIntroWidgetState();
}

class _SlideIntroWidgetState extends State<SlideIntroWidget> {
  static int _idCounter = 0;
  String? _viewId;

  static String? _extractYoutubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host == 'youtu.be') return uri.pathSegments.firstOrNull;
    if (uri.host.contains('youtube.com')) {
      if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
      final segs     = uri.pathSegments;
      final embedIdx = segs.indexOf('embed');
      if (embedIdx != -1 && embedIdx + 1 < segs.length) return segs[embedIdx + 1];
    }
    return null;
  }

  static String _embedUrl(String id) =>
      'https://www.youtube.com/embed/$id'
          '?autoplay=1&mute=0&controls=0&loop=1&playlist=$id'
          '&rel=0&showinfo=0&modestbranding=1&iv_load_policy=3&disablekb=1';

  String? get _videoId =>
      (widget.slide.url?.isNotEmpty == true)
          ? _extractYoutubeId(widget.slide.url!)
          : null;

  @override
  void initState() {
    super.initState();
    final vid = _videoId;
    if (vid != null) {
      _viewId = 'intro-yt-${_idCounter++}';
      ui.platformViewRegistry.registerViewFactory(_viewId!, (_) {
        final el = web.HTMLIFrameElement()
          ..src                 = _embedUrl(vid)
          ..style.border        = 'none'
          ..style.width         = '100%'
          ..style.height        = '100%'
          ..style.pointerEvents = 'none'
          ..allowFullscreen     = true;
        el.setAttribute('allow',
            'autoplay; fullscreen; encrypted-media; picture-in-picture');
        return el;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ─── VIDEO MODE ───────────────────────────────────────────────────────────
    if (_viewId != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          HtmlElementView(viewType: _viewId!),

          // Vignette subtil pe margini
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.25,
                colors: [Colors.transparent, Color(0x44000000)],
              ),
            ),
          ),

          // Subtitle opțional suprapus
          if (widget.slide.subtitle != null)
            Positioned(
              bottom: 52, left: 0, right: 0,
              child: Text(
                widget.slide.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:         Colors.white.withOpacity(0.80),
                  fontSize:      22,
                  fontWeight:    FontWeight.w300,
                  letterSpacing: 3,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 16)],
                ),
              )
                  .animate()
                  .fadeIn(delay: 900.ms, duration: 1200.ms),
            ),
        ],
      );
    }

    // ─── TEXT / ORB MODE (fallback) ───────────────────────────────────────────
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
              colors: [
                widget.slide.color1 != null
                    ? hexToColor(widget.slide.color1!)
                    : const Color(0xFF0a0a1a),
                widget.slide.color2 != null
                    ? hexToColor(widget.slide.color2!)
                    : const Color(0xFF1a0a2e),
              ],
            ),
          ),
        ),

        if (widget.slide.orbColors != null)
          ...widget.slide.orbColors!.asMap().entries.map((e) {
            const sizes = [500.0, 380.0, 320.0, 280.0];
            final idx   = e.key % sizes.length;
            return Positioned(
              top:  [100.0, 350.0, 50.0,  400.0][idx],
              left: [80.0,  500.0, 900.0, 200.0][idx],
              child: Container(
                width:  sizes[idx],
                height: sizes[idx],
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hexToColor(e.value).withOpacity(0.22),
                ),
              )
                  .animate(
                onPlay: (c) => c.repeat(reverse: true),
                delay:  Duration(milliseconds: idx * 600),
              )
                  .scaleXY(begin: 0.88, end: 1.12, duration: 4.seconds, curve: Curves.easeInOut),
            );
          }),

        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.slide.heading ?? widget.slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize:      80,
                  fontWeight:    FontWeight.w800,
                  color:         Colors.white,
                  letterSpacing: -1.5,
                  height:        1.1,
                ),
              )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 600.ms)
                  .slideY(begin: 0.25, end: 0, duration: 600.ms, curve: Curves.easeOut),

              if (widget.slide.subtitle != null) ...[
                const SizedBox(height: 20),
                Text(
                  widget.slide.subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize:      30,
                    color:         Colors.white.withOpacity(0.55),
                    fontWeight:    FontWeight.w300,
                    letterSpacing: 1.5,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 300.ms, duration: 600.ms)
                    .slideY(begin: 0.25, end: 0, duration: 600.ms, curve: Curves.easeOut),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
