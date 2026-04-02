// lib/features/display/display_page.dart
//
// ── ARHITECTURĂ SIMPLIFICATĂ ──────────────────────────────────────────────────
// Display-ul citește dintr-un singur nod Firebase — fără logică multi-proiect.
// Secvența de slide-uri este unică (ID 0–12) și stocată direct în _ref.
//
// Subscripții active:
//   currentSlideStream  → actualizează slide-ul afișat
//   slidesStream        → actualizează lista de slide-uri
//   touchEnabledStream  → toggle overlay atingere
//   volumeStream        → volum audio
//   iframePageIndexStream → pagina activă în iframe
//   overlayEnabledStream  → overlay navigare iframe
//   pointerStream         → laser pointer
//   pointerClickStream    → click simulat pe display

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../../core/firebase_service.dart';
import '../../core/model.dart';
import 'widgets/double_buffer_widget.dart';
import 'widgets/slide_intro_widget.dart';
import 'widgets/slide_transition_widget.dart';
import 'widgets/slide_iframe_widget.dart';
import 'widgets/slide_end_widget.dart';
import 'widgets/slide_announce_widget.dart';

class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key});

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  // Starea inițială din cachedState — disponibilă imediat fără loading screen.
  late PresentationState _state =
      FirebaseService.instance.cachedState ?? const PresentationState();

  // ── Subscripții Firebase ──────────────────────────────────────────────────
  late final StreamSubscription<int>                  _indexSub;
  late final StreamSubscription<List<SlideModel>>     _slidesSub;
  late final StreamSubscription<bool>                 _touchSub;
  late final StreamSubscription<double>               _volumeSub;
  late final StreamSubscription<int>                  _iframePageSub;
  late final StreamSubscription<bool>                 _overlaySub;
  late final StreamSubscription<Map<String, dynamic>> _pointerSub;
  late final StreamSubscription<Map<String, dynamic>> _clickSub;

  @override
  void initState() {
    super.initState();
    final fb = FirebaseService.instance;

    _indexSub = fb.currentSlideStream.listen((idx) {
      if (mounted) setState(() => _state = _state.copyWith(currentSlide: idx));
    });

    _slidesSub = fb.slidesStream.listen((slides) {
      if (mounted) setState(() => _state = _state.copyWith(slides: slides));
    });

    _touchSub = fb.touchEnabledStream.listen((v) {
      if (mounted) setState(() => _state = _state.copyWith(touchEnabled: v));
    });

    _volumeSub = fb.volumeStream.listen((v) {
      if (mounted) setState(() => _state = _state.copyWith(volume: v));
    });

    _iframePageSub = fb.iframePageIndexStream.listen((p) {
      if (mounted) setState(() => _state = _state.copyWith(iframePageIndex: p));
    });

    _overlaySub = fb.overlayEnabledStream.listen((v) {
      if (mounted) setState(() => _state = _state.copyWith(overlayEnabled: v));
    });

    _pointerSub = fb.pointerStream.listen((m) {
      if (!mounted) return;
      final x      = (m['x']      as num?)?.toDouble() ?? 0.5;
      final y      = (m['y']      as num?)?.toDouble() ?? 0.5;
      final active = m['active'] == true || m['active'] == 1;
      setState(() => _state = _state.copyWith(
        pointerX: x, pointerY: y, pointerActive: active,
      ));
    });

    _clickSub = fb.pointerClickStream.listen((m) {
      if (!mounted) return;
      final x  = (m['x']  as num?)?.toDouble() ?? 0.5;
      final y  = (m['y']  as num?)?.toDouble() ?? 0.5;
      final ts = (m['ts'] as int?)  ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts < 3000) {
        _dispatchDomClick(x, y);
      }
    });
  }

  @override
  void dispose() {
    _indexSub.cancel();
    _slidesSub.cancel();
    _touchSub.cancel();
    _volumeSub.cancel();
    _iframePageSub.cancel();
    _overlaySub.cancel();
    _pointerSub.cancel();
    _clickSub.cancel();
    super.dispose();
  }

  void _dispatchDomClick(double nx, double ny) {
    if (!kIsWeb) return;
    Future.delayed(const Duration(milliseconds: 80), () {
      try {
        final w  = web.window.innerWidth.toDouble();
        final h  = web.window.innerHeight.toDouble();
        final px = nx * w;
        final py = ny * h;
        final el = web.document.elementFromPoint(px.toInt(), py.toInt());
        if (el is web.HTMLElement) el.click();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_state.slides.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final slide = _state.slides[
    _state.currentSlide.clamp(0, _state.slides.length - 1)];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DoubleBufferWidget(
            currentSlide:    slide,
            allSlides:       _state.slides,
            touchEnabled:    _state.touchEnabled,
            iframePageIndex: _state.iframePageIndex,
            overlayEnabled:  _state.overlayEnabled,
          ),
          if (_state.pointerActive)
            _LaserPointerOverlay(x: _state.pointerX, y: _state.pointerY),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Laser Pointer Overlay
// ─────────────────────────────────────────────────────────────────────────────
class _LaserPointerOverlay extends StatelessWidget {
  final double x, y;
  const _LaserPointerOverlay({required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final px = (x * constraints.maxWidth).clamp(0.0, constraints.maxWidth);
      final py = (y * constraints.maxHeight).clamp(0.0, constraints.maxHeight);
      return Stack(fit: StackFit.expand, children: [
        Positioned(left: px - 22, top: py - 22, child: const _PulsingDot()),
      ]);
    });
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _scale   = Tween<double>(begin: 0.75, end: 1.25)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 0.75, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF2244).withOpacity(0.25),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFFF2244).withOpacity(0.5),
                  blurRadius: 28, spreadRadius: 4,
                )],
              ),
            ),
            Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF2244),
                boxShadow: [BoxShadow(
                  color: Color(0xFFFF2244),
                  blurRadius: 12, spreadRadius: 2,
                )],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SlideRenderer — alege widget-ul potrivit pentru tipul de slide
// ─────────────────────────────────────────────────────────────────────────────
class SlideRenderer extends StatelessWidget {
  final SlideModel slide;
  final bool touchEnabled;
  final int  iframePageIndex;
  final bool overlayEnabled;

  const SlideRenderer({
    required this.slide,
    required this.touchEnabled,
    this.iframePageIndex = 0,
    this.overlayEnabled  = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return switch (slide.type) {
      SlideType.intro      => SlideIntroWidget(slide: slide),
      SlideType.transition => SlideTransitionWidget(slide: slide),
      SlideType.iframe     => SlideIframeWidget(
        slide:           slide,
        touchEnabled:    touchEnabled,
        iframePageIndex: iframePageIndex,
        overlayEnabled:  overlayEnabled,
      ),
      SlideType.end        => SlideEndWidget(slide: slide),
      SlideType.announce   => SlideAnnounceWidget(slide: slide),
    };
  }
}