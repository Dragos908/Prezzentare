// lib/features/viewer/viewer_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/firebase_service.dart';
import '../../core/model.dart';
import '../display/display_page.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late PresentationState _state =
      FirebaseService.instance.cachedState ?? const PresentationState();

  late final StreamSubscription<int>              _indexSub;
  late final StreamSubscription<List<SlideModel>> _slidesSub;
  late final StreamSubscription<int>              _iframePageSub;
  late final StreamSubscription<bool>             _touchSub;
  late final StreamSubscription<bool>             _overlaySub;

  bool _prevPressed = false;
  bool _nextPressed = false;

  final FocusNode _focusNode = FocusNode();

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

    _iframePageSub = fb.iframePageIndexStream.listen((p) {
      if (mounted) setState(() => _state = _state.copyWith(iframePageIndex: p));
    });

    _touchSub = fb.touchEnabledStream.listen((v) {
      if (mounted) setState(() => _state = _state.copyWith(touchEnabled: v));
    });

    _overlaySub = fb.overlayEnabledStream.listen((v) {
      if (mounted) setState(() => _state = _state.copyWith(overlayEnabled: v));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _indexSub.cancel();
    _slidesSub.cancel();
    _iframePageSub.cancel();
    _touchSub.cancel();
    _overlaySub.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isIframeSlide {
    if (_state.slides.isEmpty) return false;
    final slide = _state.slides[
    _state.currentSlide.clamp(0, _state.slides.length - 1)];
    return slide.type == SlideType.iframe;
  }

  void _navigate(bool forward) {
    if (!_isIframeSlide) return;
    final newPage = forward
        ? _state.iframePageIndex + 1
        : (_state.iframePageIndex - 1).clamp(0, 999);
    if (newPage == _state.iframePageIndex) return;
    FirebaseService.instance.setIframePageIndex(newPage);
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space) {
      _flashNext();
      _navigate(true);
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.backspace) {
      if (_state.iframePageIndex > 0) {
        _flashPrev();
        _navigate(false);
      }
    }
  }

  Future<void> _flashNext() async {
    setState(() => _nextPressed = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _nextPressed = false);
  }

  Future<void> _flashPrev() async {
    setState(() => _prevPressed = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _prevPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_state.slides.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
      );
    }

    final slide = _state.slides[
    _state.currentSlide.clamp(0, _state.slides.length - 1)];
    final showControls = _isIframeSlide;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [

            // ── Slide display ───────────────────────────────────────────────
            Expanded(
              child: SlideRenderer(
                slide:           slide,
                touchEnabled:    false,
                iframePageIndex: _state.iframePageIndex,
                overlayEnabled:  false,
              ),
            ),

            // ── Bara de control ─────────────────────────────────────────────
            AnimatedCrossFade(
              duration:       const Duration(milliseconds: 250),
              crossFadeState: showControls
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild:  const SizedBox(width: double.infinity, height: 72),
              secondChild: _ControlBar(
                pageIndex:   _state.iframePageIndex,
                prevPressed: _prevPressed,
                nextPressed: _nextPressed,
                onPrev: _state.iframePageIndex > 0
                    ? () { _flashPrev(); _navigate(false); }
                    : null,
                onNext: () { _flashNext(); _navigate(true); },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _ControlBar extends StatelessWidget {
  final int          pageIndex;
  final bool         prevPressed;
  final bool         nextPressed;
  final VoidCallback? onPrev;
  final VoidCallback  onNext;

  const _ControlBar({
    required this.pageIndex,
    required this.prevPressed,
    required this.nextPressed,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height:  72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0a0a14),
        border: Border(top: BorderSide(color: Color(0xFF1e1e2e), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NavButton(
            icon:    Icons.chevron_left_rounded,
            label:   'ÎNAPOI',
            hint:    '← / ⌫',
            enabled: onPrev != null,
            pressed: prevPressed,
            onTap:   onPrev,
            color:   const Color(0xFF6C63FF),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${pageIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'pagina',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 10, letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          _NavButton(
            icon:    Icons.chevron_right_rounded,
            label:   'ÎNAINTE',
            hint:    '→ / Space',
            enabled: true,
            pressed: nextPressed,
            onTap:   onNext,
            color:   const Color(0xFF00D9A3),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _NavButton extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final String        hint;
  final bool          enabled;
  final bool          pressed;
  final VoidCallback? onTap;
  final Color         color;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.pressed,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : color.withOpacity(0.25);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color:        pressed ? c.withOpacity(0.20) : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: pressed ? c.withOpacity(0.70) : c.withOpacity(0.25),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon == Icons.chevron_left_rounded)
                  Icon(icon, color: c, size: 22),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: c, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 4),
                if (icon == Icons.chevron_right_rounded)
                  Icon(icon, color: c, size: 22),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              hint,
              style: TextStyle(
                color: c.withOpacity(0.45),
                fontSize: 9, letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}