// lib/features/display/widgets/slide_announce_widget.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/model.dart';

// Culori fixe roșu — nu mai depind de Firebase
const _kRed      = Color(0xFFD32F2F);
const _kRedLight = Color(0xFFFF5252);

class SlideAnnounceWidget extends StatefulWidget {
  final SlideModel slide;
  const SlideAnnounceWidget({required this.slide, super.key});

  @override
  State<SlideAnnounceWidget> createState() => _SlideAnnounceWidgetState();
}

class _SlideAnnounceWidgetState extends State<SlideAnnounceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;

  static const _rules = [
    (icon: '📵', text: 'Opriți sau puneți pe silențios telefonul'),
    (icon: '🤫', text: 'Păstrați liniștea în timpul prezentării'),
    (icon: '📸', text: 'Fotografierea este permisă fără bliț'),
    (icon: '🚪', text: 'Intrările/ieșirile — discret, între lucrări'),
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [

        // ── Fundal ────────────────────────────────────────────────────────────
        Container(color: const Color(0xFF04040C)),

        // ── Blob-uri ambientale roșii ─────────────────────────────────────────
        AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) => CustomPaint(
            painter: _AmbientPainter(t: _bgCtrl.value * math.pi * 2),
            child: const SizedBox.expand(),
          ),
        ),

        // ── Linie decorativă superioară ───────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent, _kRed, _kRedLight, Colors.transparent,
                ],
              ),
            ),
          ).animate().fadeIn(duration: 1200.ms),
        ),

        // ── CONȚINUT PRINCIPAL ────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                // ── Coloana stângă: titlu ─────────────────────────────────────
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Subtitlu
                      Text(
                        (widget.slide.subtitle ??
                            'Vă rugăm să evitați folosirea telefoanelor')
                            .toUpperCase(),
                        style: const TextStyle(
                          color:         Color(0xAAFF5252),
                          fontSize:      13,
                          fontWeight:    FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 700.ms)
                          .slideX(
                          begin: -0.1, end: 0,
                          duration: 700.ms, curve: Curves.easeOut),

                      const SizedBox(height: 20),

                      // Heading principal
                      Text(
                        widget.slide.heading ?? 'Pentru o\nvizionare\nplăcută',
                        style: const TextStyle(
                          color:         Colors.white,
                          fontSize:      72,
                          fontWeight:    FontWeight.w800,
                          letterSpacing: -2,
                          height:        1.05,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 350.ms, duration: 800.ms)
                          .slideY(
                          begin: 0.15, end: 0,
                          duration: 800.ms, curve: Curves.easeOut),

                      const SizedBox(height: 40),

                      // Linie separator
                      Container(
                        width: 120,
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_kRed, _kRedLight]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 600.ms, duration: 600.ms)
                          .scaleX(
                          begin: 0, end: 1,
                          duration: 600.ms,
                          alignment: Alignment.centerLeft,
                          curve: Curves.easeOut),
                    ],
                  ),
                ),

                const SizedBox(width: 80),

                // Separator vertical
                Container(
                  width: 1,
                  height: 300,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x4DD32F2F),
                        Color(0x4DFF5252),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 800.ms),

                const SizedBox(width: 80),

                // ── Coloana dreaptă: reguli ───────────────────────────────────
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _rules.asMap().entries.map((entry) {
                      final i     = entry.key;
                      final rule  = entry.value;
                      final delay = Duration(milliseconds: 500 + i * 160);
                      final color = i.isEven ? _kRed : _kRedLight;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: _RuleRow(
                          icon:   rule.icon,
                          text:   rule.text,
                          accent: color,
                          delay:  delay,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Linie decorativă inferioară ───────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent, _kRedLight, _kRed, Colors.transparent,
                ],
              ),
            ),
          ).animate().fadeIn(delay: 800.ms, duration: 1000.ms),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rândul cu o regulă
// ─────────────────────────────────────────────────────────────────────────────
class _RuleRow extends StatelessWidget {
  final String   icon;
  final String   text;
  final Color    accent;
  final Duration delay;

  const _RuleRow({
    required this.icon,
    required this.text,
    required this.accent,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width:  52,
          height: 52,
          decoration: BoxDecoration(
            shape:  BoxShape.circle,
            color:  accent.withOpacity(0.10),
            border: Border.all(
                color: accent.withOpacity(0.30), width: 1.5),
          ),
          child: Center(
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color:      Colors.white.withOpacity(0.85),
              fontSize:   20,
              fontWeight: FontWeight.w400,
              height:     1.3,
            ),
          ),
        ),
        Container(
          width: 3, height: 24,
          margin: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color:        accent.withOpacity(0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(delay: delay, duration: 600.ms)
        .slideX(
        begin: 0.12, end: 0,
        delay: delay, duration: 600.ms,
        curve: Curves.easeOut);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fundal ambient — 2 blob-uri roșii animate
// ─────────────────────────────────────────────────────────────────────────────
class _AmbientPainter extends CustomPainter {
  final double t;
  const _AmbientPainter({required this.t});

  @override
  void paint(Canvas canvas, Size sz) {
    final p1 = Offset(
      sz.width  * (0.08 + 0.06 * math.sin(t * 0.7)),
      sz.height * (0.15 + 0.08 * math.cos(t * 0.5)),
    );
    canvas.drawCircle(
      p1, sz.height * 0.45,
      Paint()
        ..shader = RadialGradient(
          colors: [_kRed.withOpacity(0.12), Colors.transparent],
        ).createShader(
            Rect.fromCircle(center: p1, radius: sz.height * 0.45)),
    );

    final p2 = Offset(
      sz.width  * (0.85 + 0.05 * math.cos(t * 0.6 + 1)),
      sz.height * (0.75 + 0.07 * math.sin(t * 0.8 + 2)),
    );
    canvas.drawCircle(
      p2, sz.height * 0.38,
      Paint()
        ..shader = RadialGradient(
          colors: [_kRedLight.withOpacity(0.09), Colors.transparent],
        ).createShader(
            Rect.fromCircle(center: p2, radius: sz.height * 0.38)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t;
}