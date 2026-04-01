// lib/features/display/widgets/slide_end_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/model.dart';

class SlideEndWidget extends StatelessWidget {
  final SlideModel slide;

  const SlideEndWidget({required this.slide, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fundal
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [
                slide.color1 != null
                    ? hexToColor(slide.color1!)
                    : const Color(0xFF1a0a2e),
                Colors.black,
              ],
            ),
          ),
        ),

        // Orb central
        Center(
          child: Container(
            width:  600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (slide.color2 != null
                      ? hexToColor(slide.color2!)
                      : const Color(0xFF6C63FF)).withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.85, end: 1.15, duration: 5.seconds,
              curve: Curves.easeInOut),
        ),

        // Text central
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slide.heading ?? slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize:      72,
                  fontWeight:    FontWeight.w700,
                  color:         Colors.white,
                  letterSpacing: -1.0,
                ),
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 800.ms)
              .scale(begin: const Offset(0.9, 0.9),
                  end: const Offset(1, 1),
                  duration: 800.ms,
                  curve: Curves.easeOut),

              if (slide.subtitle != null) ...[
                const SizedBox(height: 24),
                Text(
                  slide.subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize:   26,
                    color:      Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms, duration: 800.ms),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
