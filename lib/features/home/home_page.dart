// lib/features/home/home_page.dart
//
// Pagina de start: alege între Display și Control (cu parolă).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060f),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo / titlu ──
            const Text(
              'PREZENTARE',
              style: TextStyle(
                color:         Colors.white,
                fontSize:      22,
                fontWeight:    FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Selectează modul de utilizare',
              style: TextStyle(
                color:    Colors.white.withOpacity(0.3),
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 56),

            // ── Butoane ──
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeCard(
                  icon:        Icons.tv_outlined,
                  label:       'DISPLAY',
                  description: 'Ecranul prezentării\npentru tablă / proiector',
                  color:       const Color(0xFF00D9A3),
                  onTap:       () {
                    // Intră în fullscreen înainte de a naviga la /display
                    try {
                      web.document.documentElement?.requestFullscreen();
                    } catch (_) {}
                    context.go('/display');
                  },
                ),
                const SizedBox(width: 24),
                _ModeCard(
                  icon:        Icons.tune_outlined,
                  label:       'CONTROL',
                  description: 'Panoul profesorului\n(necesită parolă)',
                  color:       const Color(0xFF6C63FF),
                  onTap:       () => context.go('/control'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final String   label;
  final String   description;
  final Color    color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width:  200,
          height: 220,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withOpacity(0.12)
                : const Color(0xFF0d0d18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovered
                  ? widget.color.withOpacity(0.6)
                  : Colors.white.withOpacity(0.08),
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [
              BoxShadow(
                color:      widget.color.withOpacity(0.15),
                blurRadius: 32,
                offset:     const Offset(0, 8),
              )
            ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width:  64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(_hovered ? 0.2 : 0.1),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size:  28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.label,
                style: TextStyle(
                  color:         _hovered ? Colors.white : Colors.white70,
                  fontSize:      14,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:    Colors.white.withOpacity(0.35),
                  fontSize: 11,
                  height:   1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}