// lib/features/display/widgets/slide_transition_widget.dart
//
// Slide de tranziție animat — apare OPȚIONAL între proiecte.
// Tipuri disponibile (câmpul `animation` în Firebase):
//   'wave'      — valuri colorate (default)
//   'particles' — particule plutitoare
//   'morph'     — gradiente fluide care se transformă (NOU)
//
// Dacă nu mai vrei slide-uri de tranziție explicit, pur și simplu nu le mai
// adăuga în Firebase — tranziția cinematică din DoubleBufferWidget se face
// automat între orice două slide-uri.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/model.dart';

class SlideTransitionWidget extends StatelessWidget {
  final SlideModel slide;
  const SlideTransitionWidget({required this.slide, super.key});

  @override
  Widget build(BuildContext context) {
    final anim = slide.animation ?? 'wave';
    final c1 = slide.color1 != null ? hexToColor(slide.color1!) : const Color(0xFF050510);
    final c2 = slide.color2 != null ? hexToColor(slide.color2!) : const Color(0xFF6C63FF);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: c1),

        if (anim == 'wave')
          _WaveAnimation(color1: c1, color2: c2)
        else if (anim == 'morph')
          _MorphAnimation(color1: c1, color2: c2)
        else
          _ParticlesAnimation(color1: c2),

        // Text centrat opțional (heading / subtitle)
        if (slide.heading != null || slide.subtitle != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slide.heading != null)
                  Text(
                    slide.heading!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 150.ms, duration: 700.ms)
                      .slideY(begin: 0.2, end: 0, duration: 700.ms, curve: Curves.easeOut),

                if (slide.subtitle != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    slide.subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 26,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 700.ms),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wave animation (îmbunătățit — 4 valuri în loc de 3)
// ─────────────────────────────────────────────────────────────────────────────
class _WaveAnimation extends StatefulWidget {
  final Color color1, color2;
  const _WaveAnimation({required this.color1, required this.color2});

  @override
  State<_WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<_WaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _WavePainter(
          progress: _ctrl.value,
          color1:   widget.color1,
          color2:   widget.color2,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color  color1, color2;

  _WavePainter({
    required this.progress,
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size sz) {
    void wave(double yFrac, Color c, double amp, double phase, double op) {
      final p = Paint()..color = c.withOpacity(op)..style = PaintingStyle.fill;
      final path = Path()..moveTo(0, sz.height);
      for (double x = 0; x <= sz.width; x++) {
        path.lineTo(x, sz.height * yFrac +
            amp * math.sin((x / sz.width * 2 * math.pi) +
                (progress * 2 * math.pi) + phase));
      }
      path.lineTo(sz.width, sz.height);
      path.close();
      canvas.drawPath(path, p);
    }

    wave(0.48, color2, 65, 0,              0.40);
    wave(0.53, color1, 55, math.pi * 0.4,  0.35);
    wave(0.58, color2, 45, math.pi * 0.8,  0.30);
    wave(0.63, color1, 35, math.pi * 1.2,  0.25);
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Morph animation — gradiente fluide care se mișcă lent (NOU)
// ─────────────────────────────────────────────────────────────────────────────
class _MorphAnimation extends StatefulWidget {
  final Color color1, color2;
  const _MorphAnimation({required this.color1, required this.color2});

  @override
  State<_MorphAnimation> createState() => _MorphAnimationState();
}

class _MorphAnimationState extends State<_MorphAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _MorphPainter(
          t:      _ctrl.value,
          color1: widget.color1,
          color2: widget.color2,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  final double t;
  final Color  color1, color2;
  const _MorphPainter({required this.t, required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size sz) {
    // 3 blob-uri circulare animate care se mișcă pe traiectorii Lissajous
    final blobs = [
      (x: 0.5 + 0.4 * math.sin(t * math.pi * 2),
      y: 0.5 + 0.35 * math.cos(t * math.pi * 2 * 0.7),
      r: sz.shortestSide * 0.55,
      c: color2.withOpacity(0.30)),
      (x: 0.5 + 0.38 * math.cos(t * math.pi * 2 * 1.3 + 1),
      y: 0.5 + 0.38 * math.sin(t * math.pi * 2 * 0.9 + 0.5),
      r: sz.shortestSide * 0.45,
      c: color1.withOpacity(0.25)),
      (x: 0.5 + 0.3 * math.sin(t * math.pi * 2 * 0.6 + 2),
      y: 0.5 + 0.3 * math.cos(t * math.pi * 2 * 1.1 + 1),
      r: sz.shortestSide * 0.35,
      c: color2.withOpacity(0.20)),
    ];

    for (final b in blobs) {
      final center = Offset(b.x * sz.width, b.y * sz.height);
      canvas.drawCircle(
        center, b.r,
        Paint()
          ..shader = RadialGradient(
            colors: [b.c, Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: b.r)),
      );
    }
  }

  @override
  bool shouldRepaint(_MorphPainter o) => o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Particles animation (îmbunătățit — mai multe particule, mișcare fluida)
// ─────────────────────────────────────────────────────────────────────────────
class _ParticlesAnimation extends StatelessWidget {
  final Color color1;
  const _ParticlesAnimation({required this.color1});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(28, (i) {
        final rng   = math.Random(i * 31 + 7);
        final delay = Duration(milliseconds: i * 120);
        final top   = rng.nextDouble() * 900;
        final left  = rng.nextDouble() * 1600;
        final size  = 4.0 + rng.nextDouble() * 18;
        final dur   = 1200 + (rng.nextDouble() * 1800).toInt();

        return Positioned(
          top: top, left: left,
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color1.withOpacity(0.55),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true), delay: delay)
              .scale(
            begin: const Offset(0.3, 0.3),
            end:   const Offset(1.5, 1.5),
            duration: dur.ms, curve: Curves.easeInOut,
          )
              .fadeIn(duration: 600.ms),
        );
      }),
    );
  }
}