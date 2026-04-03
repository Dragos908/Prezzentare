import 'dart:js_interop';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:prezentare_interactiva/core/model.dart';


// 1. Declarăm Widget-ul principal
class SlideIntroWidget extends StatefulWidget {
  final SlideModel slide; // Presupun că obiectul tău se numește 'Slide'

  const SlideIntroWidget({super.key, required this.slide});

  @override
  State<SlideIntroWidget> createState() => _SlideIntroWidgetState();
}

// 2. Declarăm clasa de Stare (State)
class _SlideIntroWidgetState extends State<SlideIntroWidget> {
  // 3. Declarăm variabilele necesare
  static int _idCounter = 0;
  String? _viewId;
  String? _videoId;

  @override
  void initState() {
    super.initState();

    // AICI AM MODIFICAT: Am pus ID-ul extras din link-ul tău (8geijnkhe4Y)
    _videoId = '8geijnkhe4Y';

    final vid = _videoId;
    if (vid != null) {
      _viewId = 'intro-yt-${_idCounter++}';

      final htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: black; }
          .video-container {
            position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
            width: 100vw; height: 56.25vw; min-height: 100vh; min-width: 177.77vh;
            pointer-events: none;
          }
          iframe { width: 100%; height: 100%; border: none; }
        </style>
      </head>
      <body>
        <div class="video-container"><div id="player"></div></div>
        <script>
          var tag = document.createElement('script');
          tag.src = "https://www.youtube.com/iframe_api";
          var firstScriptTag = document.getElementsByTagName('script')[0];
          firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '$vid',
              playerVars: {
                'autoplay': 1, 'controls': 0, 'modestbranding': 1,
                'loop': 1, 'playlist': '$vid', 'mute': 1, 'rel': 0
              },
              events: {
                'onReady': function(e) { e.target.setPlaybackQuality('hd1080'); e.target.playVideo(); },
                'onStateChange': function(e) { if(e.data == 1) e.target.setPlaybackQuality('hd1080'); }
              }
            });
          }
        </script>
      </body>
      </html>
      ''';

      ui.platformViewRegistry.registerViewFactory(_viewId!, (_) {
        final el = web.HTMLIFrameElement()
          ..srcdoc              = htmlContent.toJS
          ..style.border        = 'none'
          ..style.width         = '100%'
          ..style.height        = '100%'
          ..style.pointerEvents = 'none'
          ..allowFullscreen     = true;

        el.setAttribute('allow', 'autoplay; fullscreen; encrypted-media; picture-in-picture');
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

          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.25,
                colors: [Colors.transparent, Color(0x66000000)],
              ),
            ),
          ),

          if (widget.slide.subtitle != null)
            Positioned(
              bottom: 52, left: 0, right: 0,
              child: Text(
                widget.slide.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:         Colors.white.withOpacity(0.90),
                  fontSize:      24,
                  fontWeight:    FontWeight.w400,
                  letterSpacing: 2,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2))
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 900.ms, duration: 1200.ms)
                  .slideY(begin: 0.2, end: 0, curve: Curves.easeOut),
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
                    boxShadow: [
                      BoxShadow(
                        color: hexToColor(e.value).withOpacity(0.1),
                        blurRadius: 100,
                        spreadRadius: 20,
                      )
                    ]
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
                    color:         Colors.white.withOpacity(0.65),
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

// Funcție ajutătoare în afara claselor
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
