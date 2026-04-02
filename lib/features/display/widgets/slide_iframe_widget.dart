// lib/features/display/widgets/slide_iframe_widget.dart
//
// ── NAVIGARE CANVA ────────────────────────────────────────────────────────────
//
// Canva embed (canva.com/design/...) NU suportă parametrul ?slide=N în URL
// și IGNORĂ postMessage-urile de la pagina părinte (cross-origin).
//
// Soluție funcțională — 3 metode în cascadă:
//
//   1. postMessage — formate multiple (pentru Reveal.js, Slidev, iframe-uri custom).
//
//   2. Click simulat cu coordonate exacte:
//      Creăm un PointerEvent + MouseEvent cu clientX/Y la jumătatea dreaptă
//      (sau stângă) a iframe-ului și îl dispatch-uim pe documentul părinte.
//      Chrome face hit-testing pe coordonate → routează click-ul ÎNĂUNTRUL
//      iframe-ului cross-origin, exact ca un click fizic al utilizatorului.
//      Canva reacționează la click pe jumătatea dreaptă (next) / stângă (prev).
//
//   3. contentWindow.focus() + KeyboardEvent pe document.body:
//      Fallback: mutăm focus-ul în iframe, apoi trimitem ArrowRight/Left.
//      Funcționează în unele versiuni Chrome, ignorat în altele.
//
// ── NAVIGARE GOOGLE SLIDES ───────────────────────────────────────────────────
// Google Slides suportă ?slide=N → reîncărcăm src cu parametrul corect.
//
// ── CANVA SITE (my.canva.site) ───────────────────────────────────────────────
// Website publicat — fără sub-pagini, src rămâne neschimbat.

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import '../../../core/model.dart';
import '../../../core/firebase_service.dart';

// ── JS interop — KeyboardEvent ────────────────────────────────────────────────

extension type _KbInit._(JSObject _) implements JSObject {
  external factory _KbInit();
  external set key(String v);
  external set code(String v);
  external set keyCode(int v);
  external set which(int v);
  external set bubbles(bool v);
  external set cancelable(bool v);
  external set composed(bool v);
}

@JS('KeyboardEvent')
extension type _KbEvent._(JSObject _) implements JSObject {
  external factory _KbEvent(String type, JSObject init);
}

// ── JS interop — PointerEvent / MouseEvent ────────────────────────────────────

extension type _PointerInit._(JSObject _) implements JSObject {
  external factory _PointerInit();
  external set clientX(double v);
  external set clientY(double v);
  external set screenX(double v);
  external set screenY(double v);
  external set button(int v);
  external set buttons(int v);
  external set bubbles(bool v);
  external set cancelable(bool v);
  external set composed(bool v);
  external set isPrimary(bool v);
  external set pointerId(int v);
  external set pointerType(String v);
}

@JS('PointerEvent')
extension type _PointerEvent._(JSObject _) implements JSObject {
  external factory _PointerEvent(String type, JSObject init);
}

@JS('MouseEvent')
extension type _MouseEvent._(JSObject _) implements JSObject {
  external factory _MouseEvent(String type, JSObject init);
}

// ─────────────────────────────────────────────────────────────────────────────

class SlideIframeWidget extends StatefulWidget {
  final SlideModel slide;
  final bool touchEnabled;
  final int  iframePageIndex;
  final bool overlayEnabled;

  const SlideIframeWidget({
    required this.slide,
    required this.touchEnabled,
    this.iframePageIndex = 0,
    this.overlayEnabled  = true,
    super.key,
  });

  @override
  State<SlideIframeWidget> createState() => _SlideIframeWidgetState();
}

class _SlideIframeWidgetState extends State<SlideIframeWidget> {
  late final String _viewId;
  web.HTMLIFrameElement? _iframeEl;

  static final Map<String, _SlideIframeWidgetState> _activeStates  = {};
  static final Set<String>                          _registeredIds = {};

  int _lastPostedPage = -1;

  // ── Detectare tip iframe ───────────────────────────────────────────────────

  bool get _isGoogleSlides =>
      widget.slide.url?.contains('docs.google.com/presentation') ?? false;

  bool get _isCanvaEmbed =>
      (widget.slide.url?.contains('canva.com') ?? false) &&
          !(widget.slide.url?.contains('canva.site') ?? false);

  bool get _isCanvaSite =>
      widget.slide.url?.contains('canva.site') ?? false;

  bool get _usesUrlNavigation => _isGoogleSlides || _isCanvaSite;

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setIframeEl(web.HTMLIFrameElement el) {
    _iframeEl = el;
    _iframeEl!.style.pointerEvents = widget.overlayEnabled ? 'none' : 'auto';
  }

  static String _buildPagedUrl(String base, int page) {
    if (page == 0) return base;

    if (base.contains('docs.google.com/presentation')) {
      try {
        final withoutFragment = base.split('#').first;
        final uri    = Uri.parse(withoutFragment);
        final params = Map<String, String>.from(uri.queryParameters);
        params['slide'] = (page + 1).toString();
        return uri.replace(queryParameters: params).toString();
      } catch (_) {
        return base;
      }
    }

    if (base.contains('canva.site')) return base;

    return base;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _viewId = 'iframe-${widget.slide.id}-${widget.slide.url.hashCode}';
    _activeStates[_viewId] = this;

    if (!_registeredIds.contains(_viewId)) {
      _registeredIds.add(_viewId);
      ui.platformViewRegistry.registerViewFactory(_viewId, (_) {
        final el = web.HTMLIFrameElement();
        el.src = _buildPagedUrl(widget.slide.url ?? '', widget.iframePageIndex);
        el.style.border        = 'none';
        el.style.width         = '100%';
        el.style.height        = '100%';
        el.style.pointerEvents = widget.overlayEnabled ? 'none' : 'auto';
        el.allowFullscreen     = true;
        el.setAttribute('allow', 'autoplay; fullscreen; picture-in-picture');
        _activeStates[_viewId]?._setIframeEl(el);
        return el;
      });
    }
  }

  @override
  void dispose() {
    if (_activeStates[_viewId] == this) _activeStates.remove(_viewId);
    super.dispose();
  }

  // ── Navigare ───────────────────────────────────────────────────────────────

  /// Trimite comenzi de navigare către iframe — 3 metode în cascadă.
  void _sendNavigationToIframe(bool forward) {
    final keyName = forward ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = forward ? 39 : 37;

    // ── Metoda 1: postMessage (Reveal.js, Slidev, iframe-uri custom) ──────
    try {
      final iframeWindow = _iframeEl?.contentWindow;
      if (iframeWindow != null) {
        iframeWindow.postMessage(
          '{"type":"keydown","key":"$keyName","keyCode":$keyCode}'.toJS,
          '*'.toJS,
        );
        iframeWindow.postMessage(
          '{"method":"${forward ? 'goToNextSlide' : 'goToPreviousSlide'}","params":{}}'.toJS,
          '*'.toJS,
        );
        iframeWindow.postMessage(
          '{"action":"${forward ? 'next' : 'prev'}","source":"prezentare"}'.toJS,
          '*'.toJS,
        );
        iframeWindow.postMessage(
          (forward ? 'nextSlide' : 'prevSlide').toJS,
          '*'.toJS,
        );
      }
    } catch (_) {}

    // ── Metoda 2: Click simulat cu coordonate exacte ───────────────────────
    // Chrome face hit-testing pe clientX/Y → routează click-ul în iframe
    // chiar dacă e cross-origin. Canva navighează la click pe jumătatea
    // dreaptă (next) sau stângă (prev) a prezentării.
    _simulateClickInIframe(forward);

    // ── Metoda 3: contentWindow.focus() + KeyboardEvent (fallback) ────────
    Future.delayed(const Duration(milliseconds: 80), () {
      try {
        // contentWindow.focus() mută focus-ul în browsing context-ul iframe-ului,
        // nu doar pe elementul DOM — diferența esențială față de iframe.focus().
        _iframeEl?.contentWindow?.focus();
      } catch (_) {
        try { _iframeEl?.focus(); } catch (_) {}
      }

      try {
        final init = _KbInit();
        init.key       = keyName;
        init.code      = keyName;
        init.keyCode   = keyCode;
        init.which     = keyCode;
        init.bubbles   = true;
        init.cancelable = true;
        init.composed  = true;

        final kd = _KbEvent('keydown', init);
        final ku = _KbEvent('keyup',   init);

        // Dispatch pe document.body (mai aproape de target-ul real al iframe-ului)
        web.document.body?.dispatchEvent(kd as web.Event);
        web.document.body?.dispatchEvent(ku as web.Event);
        web.document.dispatchEvent(kd as web.Event);
      } catch (_) {}
    });
  }

  /// Simulează PointerEvent + MouseEvent la coordonatele corecte din viewport.
  ///
  /// Logica: găsim bounding rect-ul iframe-ului, calculăm un punct pe
  /// jumătatea dreaptă (next) sau stângă (prev), și dispatch-uim evenimentele
  /// pe elementul de la acele coordonate în documentul părinte.
  /// Chrome routează click-ul în iframe pe baza coordonatelor, nu a target-ului.
  void _simulateClickInIframe(bool forward) {
    try {
      final el = _iframeEl;
      if (el == null) return;

      final rect = el.getBoundingClientRect();

      // Punct de click: 75% din lățime (next) sau 25% (prev), vertical centrat
      final cx = forward
          ? rect.left + rect.width  * 0.75
          : rect.left + rect.width  * 0.25;
      final cy = rect.top  + rect.height * 0.50;

      // Activăm temporar pointer-events pe iframe
      // (altfel elementFromPoint returnează overlay-ul Flutter, nu iframe-ul)
      final prevPE = el.style.pointerEvents;
      el.style.pointerEvents = 'auto';

      final target = web.document.elementFromPoint(cx.toInt(), cy.toInt()) ?? el;

      // --- PointerEvent (mai modern, suportat de Canva) ---
      final pInit = _PointerInit();
      pInit.clientX    = cx;
      pInit.clientY    = cy;
      pInit.screenX    = cx;
      pInit.screenY    = cy;
      pInit.button     = 0;
      pInit.buttons    = 1;
      pInit.bubbles    = true;
      pInit.cancelable = true;
      pInit.composed   = true;
      pInit.isPrimary  = true;
      pInit.pointerId  = 1;
      pInit.pointerType = 'mouse';

      target.dispatchEvent(_PointerEvent('pointerover',  pInit) as web.Event);
      target.dispatchEvent(_PointerEvent('pointerenter', pInit) as web.Event);
      target.dispatchEvent(_PointerEvent('pointermove',  pInit) as web.Event);
      target.dispatchEvent(_PointerEvent('pointerdown',  pInit) as web.Event);
      target.dispatchEvent(_PointerEvent('pointerup',    pInit) as web.Event);

      // --- MouseEvent (compatibilitate) ---
      final mInit = _PointerInit();
      mInit.clientX    = cx;
      mInit.clientY    = cy;
      mInit.screenX    = cx;
      mInit.screenY    = cy;
      mInit.button     = 0;
      mInit.buttons    = 0;
      mInit.bubbles    = true;
      mInit.cancelable = true;
      mInit.composed   = true;

      target.dispatchEvent(_MouseEvent('mousedown', mInit) as web.Event);
      target.dispatchEvent(_MouseEvent('mouseup',   mInit) as web.Event);
      target.dispatchEvent(_MouseEvent('click',     mInit) as web.Event);

      // Restaurăm pointer-events după un scurt delay
      Timer(const Duration(milliseconds: 200), () {
        el.style.pointerEvents = prevPE;
      });
    } catch (_) {}
  }

  /// Apelat de overlay la tap/swipe.
  void _navigate(bool forward) {
    final newPage = forward
        ? widget.iframePageIndex + 1
        : (widget.iframePageIndex - 1).clamp(0, 999);
    if (newPage == widget.iframePageIndex) return;

    FirebaseService.instance.setIframePageIndex(newPage);

    if (!_usesUrlNavigation) {
      _lastPostedPage = newPage;
      _sendNavigationToIframe(forward);
    }
  }

  @override
  void didUpdateWidget(SlideIframeWidget old) {
    super.didUpdateWidget(old);

    if (old.iframePageIndex != widget.iframePageIndex) {
      if (_usesUrlNavigation) {
        final newUrl = _buildPagedUrl(
            widget.slide.url ?? '', widget.iframePageIndex);
        _iframeEl?.src = newUrl;
      } else {
        final bool forward = widget.iframePageIndex > old.iframePageIndex;
        if (widget.iframePageIndex != _lastPostedPage) {
          _sendNavigationToIframe(forward);
        }
        _lastPostedPage = widget.iframePageIndex;
      }
    }

    if (old.overlayEnabled != widget.overlayEnabled) {
      _iframeEl?.style.pointerEvents =
      widget.overlayEnabled ? 'none' : 'auto';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.slide.staticImageUrl != null) {
      return Image.network(
        widget.slide.staticImageUrl!,
        fit: BoxFit.contain,
        frameBuilder: (_, child, frame, __) =>
        frame == null ? const ColoredBox(color: Colors.black) : child,
        errorBuilder: (_, __, ___) => const _ErrorPlaceholder(),
      );
    }

    if (widget.slide.url == null || widget.slide.url!.isEmpty) {
      return const _ErrorPlaceholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewId),
        if (widget.overlayEnabled)
          _NavigationOverlay(
            touchEnabled: widget.touchEnabled,
            onNavigate:   _navigate,
            pageIndex:    widget.iframePageIndex,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay transparent de navigare
// ─────────────────────────────────────────────────────────────────────────────
class _NavigationOverlay extends StatelessWidget {
  final bool touchEnabled;
  final void Function(bool forward) onNavigate;
  final int  pageIndex;

  const _NavigationOverlay({
    required this.touchEnabled,
    required this.onNavigate,
    required this.pageIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (!touchEnabled) return const SizedBox.expand();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0, top: 0, width: w * 0.5, bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: pageIndex > 0 ? () => onNavigate(false) : null,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 200) onNavigate(v > 0);
                },
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: w * 0.5, top: 0, width: w * 0.5, bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => onNavigate(true),
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 200) onNavigate(v < 0);
                },
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Text(
          'Continut indisponibil',
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 18),
        ),
      ),
    );
  }
}