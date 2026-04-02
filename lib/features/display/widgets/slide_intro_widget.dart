// lib/features/display/widgets/slide_intro_widget.dart

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
      final segs = uri.pathSegments;
      final embedIdx = segs.indexOf('embed');
      if (embedIdx != -1 && embedIdx + 1 < segs.length) {
        return segs[embedIdx + 1];
      }
    }
    return null;
  }

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
      
      // HTML-ul custom care include YouTube IFrame API și CSS pentru fullscreen (cover)
      final htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          /* Setări pentru a elimina marginile și a ascunde scroll-ul */
          body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: black; }
          
          /* Truc CSS pentru a face iframe-ul să se comporte ca 'object-fit: cover' */
          .video-container {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 100vw;
            height: 56.25vw; /* Ratio 16:9 */
            min-height: 100vh;
            min-width: 177.77vh; /* 16/9 = 1.777 */
            pointer-events: none; /* Previne orice interacțiune (click/pauză) */
          }
          iframe { width: 100%; height: 100%; border: none; }
        </style>
      </head>
      <body>
        <div class="video-container"><div id="player"></div></div>
        
        <script>
          // 1. Încarcă asincron codul pentru YouTube IFrame API
          var tag = document.createElement('script');
          tag.src = "https://www.youtube.com/iframe_api";
          var firstScriptTag = document.getElementsByTagName('script')[0];
          firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

          var player;
          // 2. Această funcție este apelată automat de API când e gata
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '$vid',
              playerVars: {
                'autoplay': 1,
                'controls': 0,
                'showinfo': 0,
                'modestbranding': 1,
                'loop': 1,
                'playlist': '$vid',
                'mute': 1, /* MUST BE 1: Browserele blochează autoplay dacă sunetul e pornit */
                'rel': 0,
                'iv_load_policy': 3,
                'disablekb': 1
              },
              events: {
                'onReady': function(event) {
                  // Sugerează calitatea maximă la încărcare
                  event.target.setPlaybackQuality('hd1080'); 
                  event.target.playVideo();
                },
                'onStateChange': function(event) {
                  // Forțează calitatea imediat cum video-ul începe să ruleze
                  if (event.data == YT.PlayerState.PLAYING) {
                    event.target.setPlaybackQuality('hd1080');
                  }
                }
              }
            });
          }
        </script>
      </body>
      </html>
      ''';

      ui.platformViewRegistry.registerViewFactory(_viewId!, (_) {
        final el = web.HTMLIFrameElement()
          ..srcdoc              = htmlContent
          ..style.border        = 'none'
          ..style.width         = '100%'
          ..style.height        = '100%'
          ..style.pointerEvents = 'none' // Dublă siguranță pentru interacțiuni
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
          // Renderizarea IFrame-ului creat în initState
          HtmlElementView(viewType: _viewId!),

          // Vignette subtil pe margini (păstrat din designul tău)
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.25,
                colors: [Colors.transparent, Color(0x66000000)], // Ușor mai întunecat pentru contrast text
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
                  // Am adăugat un blur pentru a face orb-urile mai organice
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

// O funcție helper presupusă că o ai undeva în proiect
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
