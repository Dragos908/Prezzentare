// lib/features/display/widgets/double_buffer_widget.dart
//
// ── DOUBLE BUFFER + TRANZIȚIE CINEMATICĂ ─────────────────────────────────────
//
// Tranziția între slide-uri se face în 3 faze suprapuse (total ~700 ms):
//
//   1. FLASH IN   (0–120 ms)  — un line-sweep luminos taie ecranul de la stânga
//                               la dreapta; simultan slide-ul vechi se dizolvă.
//   2. HOLD       (120–200 ms)— flash-ul atinge opacitate maximă; noul slide
//                               intră deja în fundal.
//   3. FADE OUT   (200–700 ms)— flash-ul dispare lin; noul slide e complet vizibil.
//
// Efectul net: o tăietură rapidă de lumină care "rulează" ecranul, mai dramatică
// decât un crossfade simplu dar fără să fie obositoare la utilizare repetată.
//
// ── PREÎNCĂRCARE IFRAME ───────────────────────────────────────────────────────
// Toate slide-urile iframe sunt montate cu Offstage(offstage: true) pentru
// preîncărcare invizibilă. Browserul descarcă conținutul în fundal.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/model.dart';
import 'slide_iframe_widget.dart';
import '/features/display/display_page.dart';

class DoubleBufferWidget extends StatefulWidget {
  final SlideModel        currentSlide;
  final List<SlideModel>  allSlides;
  final bool              touchEnabled;
  final int               iframePageIndex;
  final bool              overlayEnabled;
  final Duration          transitionDuration;

  const DoubleBufferWidget({
    required this.currentSlide,
    this.allSlides          = const [],
    required this.touchEnabled,
    this.iframePageIndex    = 0,
    this.overlayEnabled     = true,
    this.transitionDuration = const Duration(milliseconds: 700),
    super.key,
  });

  @override
  State<DoubleBufferWidget> createState() => _DoubleBufferWidgetState();
}

class _DoubleBufferWidgetState extends State<DoubleBufferWidget>
    with SingleTickerProviderStateMixin {

  // ── Double buffer ─────────────────────────────────────────────────────────
  SlideModel? _bufferA;
  SlideModel? _bufferB;
  bool        _aIsVisible   = true;
  bool        _isTransiting = false;

  // ── Flash / sweep animation ───────────────────────────────────────────────
  late AnimationController _flashCtrl;

  // Sweep: 0 → 1 = linia luminoasă se mișcă de la stânga la dreapta
  late Animation<double> _sweepAnim;
  // Flash opacity: crește rapid, apoi dispare lin
  late Animation<double> _flashOpacity;

  bool _showFlash = false;

  // Culoarea flash-ului — schimbată înainte de fiecare tranziție pentru varietate
  Color _flashColor = Colors.white;

  // Paleta de culori folosite ciclic pentru flash
  static const _flashColors = [
    Color(0xFFFFFFFF),
    Color(0xFF6C63FF),
    Color(0xFF00D9A3),
    Color(0xFFFF6584),
    Color(0xFFFFBE21),
  ];
  int _flashColorIdx = 0;

  @override
  void initState() {
    super.initState();
    _bufferA = widget.currentSlide;

    _flashCtrl = AnimationController(
      vsync:    this,
      duration: widget.transitionDuration,
    );

    // Sweep merge de la -0.15 la 1.15 (depășește marginile pentru un look propriu)
    _sweepAnim = Tween<double>(begin: -0.15, end: 1.15).animate(
      CurvedAnimation(
        parent: _flashCtrl,
        curve:  const Interval(0.0, 0.65, curve: Curves.easeInOut),
      ),
    );

    // Flash atinge peak la 20% din animație, apoi dispare complet la 85%
    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.85)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: 15,
      ),
    ]).animate(_flashCtrl);
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DoubleBufferWidget old) {
    super.didUpdateWidget(old);
    if (old.currentSlide.id != widget.currentSlide.id && !_isTransiting) {
      _doTransition(widget.currentSlide);
    }
  }

  void _doTransition(SlideModel next) {
    _isTransiting  = true;
    _flashColor    = _flashColors[_flashColorIdx % _flashColors.length];
    _flashColorIdx = (_flashColorIdx + 1) % _flashColors.length;

    // Încarcă noul slide în buffer-ul inactiv
    setState(() {
      if (_aIsVisible) { _bufferB = next; } else { _bufferA = next; }
      _showFlash = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Comută vizibilitatea (crossfade) puțin după ce flash-ul pornește
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        setState(() => _aIsVisible = !_aIsVisible);
      });

      // Pornește animația flash
      _flashCtrl.forward(from: 0).then((_) {
        if (!mounted) return;
        setState(() {
          // Curăță buffer-ul invizibil
          if (_aIsVisible) { _bufferB = null; } else { _bufferA = null; }
          _showFlash    = false;
          _isTransiting = false;
        });
      });
    });
  }

  Set<int> get _activeBufferIds {
    final ids = <int>{};
    if (_bufferA != null) ids.add(_bufferA!.id);
    if (_bufferB != null) ids.add(_bufferB!.id);
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final activeIds    = _activeBufferIds;
    final preloadSlides = widget.allSlides
        .where((s) => s.type == SlideType.iframe && !activeIds.contains(s.id))
        .toList();

    return Stack(
      fit: StackFit.expand,
      children: [

        // ── Preîncărcare iframe (invizibil) ──────────────────────────────────
        for (final slide in preloadSlides)
          Offstage(
            key:      ValueKey('preload-${slide.id}'),
            offstage: true,
            child: SlideIframeWidget(
              slide:           slide,
              touchEnabled:    false,
              overlayEnabled:  false,
              iframePageIndex: 0,
            ),
          ),

        // ── Buffer A ──────────────────────────────────────────────────────────
        AnimatedOpacity(
          opacity:  _aIsVisible ? 1.0 : 0.0,
          duration: widget.transitionDuration,
          curve:    Curves.easeInOut,
          child: _bufferA != null
              ? RepaintBoundary(
            child: SlideRenderer(
              slide:           _bufferA!,
              touchEnabled:    widget.touchEnabled,
              iframePageIndex: widget.iframePageIndex,
              overlayEnabled:  widget.overlayEnabled,
            ),
          )
              : const SizedBox.expand(),
        ),

        // ── Buffer B ──────────────────────────────────────────────────────────
        AnimatedOpacity(
          opacity:  _aIsVisible ? 0.0 : 1.0,
          duration: widget.transitionDuration,
          curve:    Curves.easeInOut,
          child: _bufferB != null
              ? RepaintBoundary(
            child: SlideRenderer(
              slide:           _bufferB!,
              touchEnabled:    widget.touchEnabled,
              iframePageIndex: widget.iframePageIndex,
              overlayEnabled:  widget.overlayEnabled,
            ),
          )
              : const SizedBox.expand(),
        ),

        // ── Flash / sweep overlay ─────────────────────────────────────────────
        if (_showFlash)
          AnimatedBuilder(
            animation: _flashCtrl,
            builder: (_, __) => CustomPaint(
              painter: _SweepFlashPainter(
                sweep:   _sweepAnim.value,
                opacity: _flashOpacity.value,
                color:   _flashColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — linie luminoasă diagonală care traversează ecranul
// ─────────────────────────────────────────────────────────────────────────────
class _SweepFlashPainter extends CustomPainter {
  final double sweep;    // 0.0 → 1.0 (poziție de la stânga la dreapta)
  final double opacity;  // 0.0 → 1.0
  final Color  color;

  const _SweepFlashPainter({
    required this.sweep,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0) return;

    final w = size.width;
    final h = size.height;

    // Centrul liniei — se mișcă orizontal
    final cx = sweep * w;

    // Lățimea benzii luminoase (proporțional cu lățimea ecranului)
    final bandW = w * 0.22;

    // Gradient de-a lungul axei X — vârf la centru, 0 pe margini
    final rect = Rect.fromLTWH(cx - bandW, 0, bandW * 2, h);
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end:   Alignment.centerRight,
      colors: [
        Colors.transparent,
        color.withOpacity(opacity * 0.45),
        color.withOpacity(opacity),
        color.withOpacity(opacity * 0.45),
        Colors.transparent,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(rect);

    // Path diagonal ușor (8° față de verticală) pentru look cinematic
    final angle = math.tan(8 * math.pi / 180) * h;
    final path  = Path()
      ..moveTo(cx - bandW - angle, 0)
      ..lineTo(cx + bandW - angle, 0)
      ..lineTo(cx + bandW + angle, h)
      ..lineTo(cx - bandW + angle, h)
      ..close();

    canvas.drawPath(path, paint);

    // Linie centrală mai îngustă și mai strălucitoare
    final corePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end:   Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(opacity * 0.9),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(cx - 8, 0, 16, h));

    final corePath = Path()
      ..moveTo(cx - 4 - angle * 0.5, 0)
      ..lineTo(cx + 4 - angle * 0.5, 0)
      ..lineTo(cx + 4 + angle * 0.5, h)
      ..lineTo(cx - 4 + angle * 0.5, h)
      ..close();

    canvas.drawPath(corePath, corePaint);
  }

  @override
  bool shouldRepaint(_SweepFlashPainter old) =>
      old.sweep != sweep || old.opacity != opacity || old.color != color;
}