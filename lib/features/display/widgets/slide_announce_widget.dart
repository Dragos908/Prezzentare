// lib/features/display/widgets/slide_announce_widget.dart
//
// Ecran de anunț — afișat înainte de prezentare pentru reguli de conduită.
// Conținut implicit complet, personalizabil din Firebase:
//
//   heading  → titlul principal (implicit: "Pentru o vizionare plăcută")
//   subtitle → subtitlu mic deasupra (implicit: "Vă rugăm să respectați")
//   color1   → culoarea accentului (implicit: #6C63FF)
//   color2   → a doua culoare gradient (implicit: #00D9A3)
//
// Regulile afișate sunt fixe și animate cu stagger.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/model.dart';

class SlideAnnounceWidget extends StatefulWidget {
  final SlideModel slide;
  const SlideAnnounceWidget({required this.slide, super.key});

  @override
  State<SlideAnnounceWidget> createState() => _SlideAnnounceWidgetState();
}

class _SlideAnnounceWidgetState extends State<SlideAnnounceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;

  Color get _accent => widget.slide.color1 != null
      ? hexToColor(widget.slide.color1!)
      : const Color(0xFF6C63FF);

  Color get _accent2 => widget.slide.color2 != null
      ? hexToColor(widget.slide.color2!)
      : const Color(0xFF00D9A3);

  static const _rules = [
    (icon: '📵', text: 'Opriți sau puneți pe silențios telefonul'),
    (icon: '🤫', text: 'Păstrați liniștea în timpul prezentării'),
    (icon: '📸', text: 'Fotografierea este permisă fără bliț'),
    (icon: '🚪', text: 'Intrările/ieșirile — discret, între slide-uri'),
    (icon: '💬', text: 'Întrebările — la finalul prezentării'),
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
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

        // ── Fundal negru-adânc ───────────────────────────────────────────────
        Container(color: const Color(0xFF04040C)),

        // ── Orb-uri animate (fundal ambient) ────────────────────────────────
        AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) {
            final t = _bgCtrl.value * math.pi * 2;
            return CustomPaint(
              painter: _AmbientPainter(t: t, c1: _accent, c2: _accent2),
              child: const SizedBox.expand(),
            );
          },
        ),

        // ── Linie decorativă superioară ──────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, _accent, _accent2, Colors.transparent],
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 1200.ms),
        ),

        // ── CONȚINUT PRINCIPAL ───────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                // ── Coloana stângă: titlu + iconiță ─────────────────────────
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Subtitlu mic deasupra
                      Text(
                        (widget.slide.subtitle ?? 'Vă rugăm să respectați').toUpperCase(),
                        style: TextStyle(
                          color:         _accent.withOpacity(0.7),
                          fontSize:      13,
                          fontWeight:    FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 700.ms)
                          .slideX(begin: -0.1, end: 0, duration: 700.ms, curve: Curves.easeOut),

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
                          .slideY(begin: 0.15, end: 0, duration: 800.ms, curve: Curves.easeOut),

                      const SizedBox(height: 40),

                      // Linie separator cu gradient
                      Container(
                        width: 120,
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [_accent, _accent2]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 600.ms, duration: 600.ms)
                          .scaleX(begin: 0, end: 1, duration: 600.ms,
                          alignment: Alignment.centerLeft, curve: Curves.easeOut),

                      const SizedBox(height: 40),

                      // Iconiță mare animată
                      _PulsingIcon(color: _accent),
                    ],
                  ),
                ),

                const SizedBox(width: 80),

                // Separator vertical
                Container(
                  width: 1,
                  height: 340,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        _accent.withOpacity(0.3),
                        _accent2.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 500.ms, duration: 800.ms),

                const SizedBox(width: 80),

                // ── Coloana dreaptă: lista de reguli ─────────────────────────
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _rules.asMap().entries.map((entry) {
                      final i    = entry.key;
                      final rule = entry.value;
                      final delay = Duration(milliseconds: 500 + i * 160);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: _RuleRow(
                          icon:    rule.icon,
                          text:    rule.text,
                          accent:  i.isEven ? _accent : _accent2,
                          delay:   delay,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Linie decorativă inferioară ──────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, _accent2, _accent, Colors.transparent],
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 800.ms, duration: 1000.ms),
        ),

        // ── Număr/logo colț dreapta jos ──────────────────────────────────────
        Positioned(
          bottom: 28, right: 48,
          child: Text(
            '★',
            style: TextStyle(
              color:    _accent.withOpacity(0.15),
              fontSize: 64,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(delay: 1200.ms, duration: 1000.ms)
              .then()
              .shimmer(duration: 3.seconds, color: _accent.withOpacity(0.3)),
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
        // Iconiță emoji în container rotund
        Container(
          width:  52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withOpacity(0.1),
            border: Border.all(color: accent.withOpacity(0.25), width: 1.5),
          ),
          child: Center(
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
        ),

        const SizedBox(width: 20),

        // Text regulă
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color:      Colors.white.withOpacity(0.82),
              fontSize:   20,
              fontWeight: FontWeight.w400,
              height:     1.3,
            ),
          ),
        ),

        // Linie colorată la final
        Container(
          width: 3, height: 24,
          margin: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color:        accent.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(delay: delay, duration: 600.ms)
        .slideX(begin: 0.12, end: 0, delay: delay, duration: 600.ms, curve: Curves.easeOut);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Iconiță pulsantă (telefon cu X)
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingIcon extends StatefulWidget {
  final Color color;
  const _PulsingIcon({required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glow  = Tween(begin: 0.2,  end: 0.6)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Container(
          width:  96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(0.08),
            boxShadow: [
              BoxShadow(
                color:        widget.color.withOpacity(_glow.value),
                blurRadius:   40,
                spreadRadius: 4,
              ),
            ],
            border: Border.all(
              color: widget.color.withOpacity(0.25 + _glow.value * 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.phone_android, color: widget.color, size: 40),
                Positioned(
                  right: 16, top: 16,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6584),
                      border: Border.all(color: const Color(0xFF04040C), width: 2),
                    ),
                    child: const Icon(Icons.close, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 900.ms, duration: 800.ms)
        .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1),
        delay: 900.ms, duration: 800.ms, curve: Curves.elasticOut);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fundal ambient — 2 blob-uri mari care se mișcă lent
// ─────────────────────────────────────────────────────────────────────────────
class _AmbientPainter extends CustomPainter {
  final double t;
  final Color  c1, c2;
  const _AmbientPainter({required this.t, required this.c1, required this.c2});

  @override
  void paint(Canvas canvas, Size sz) {
    // Blob stânga-sus
    final p1 = Offset(
      sz.width  * (0.08 + 0.06 * math.sin(t * 0.7)),
      sz.height * (0.15 + 0.08 * math.cos(t * 0.5)),
    );
    canvas.drawCircle(p1, sz.height * 0.45,
        Paint()..shader = RadialGradient(
          colors: [c1.withOpacity(0.13), Colors.transparent],
        ).createShader(Rect.fromCircle(center: p1, radius: sz.height * 0.45)));

    // Blob dreapta-jos
    final p2 = Offset(
      sz.width  * (0.85 + 0.05 * math.cos(t * 0.6 + 1)),
      sz.height * (0.75 + 0.07 * math.sin(t * 0.8 + 2)),
    );
    canvas.drawCircle(p2, sz.height * 0.38,
        Paint()..shader = RadialGradient(
          colors: [c2.withOpacity(0.11), Colors.transparent],
        ).createShader(Rect.fromCircle(center: p2, radius: sz.height * 0.38)));
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t;
}