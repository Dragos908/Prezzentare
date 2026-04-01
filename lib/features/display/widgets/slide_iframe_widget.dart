// lib/features/display/widgets/slide_iframe_widget.dart
//
// ── ROOT CAUSE FIX ───────────────────────────────────────────────────────────
//
// Problema: registerViewFactory() acceptă o singură înregistrare per _viewId.
// Closure-ul din factory capturează `_iframeEl` din PRIMA instanță de state.
// Când DoubleBuffer distruge și recreează SlideIframeWidget pentru același
// slide (A→B→A), noua instanță are `_iframeEl = null` permanent deoarece
// factory-ul scrie în instanța veche (distrusă). Toate comenzile de navigare
// devin no-op → "slidurile se opresc".
//
// FIX: _activeStates static — înregistrăm instanța CURENTĂ activă per viewId.
// Factory-ul apelează `_activeStates[_viewId]?._setIframeEl(el)` care scrie
// întotdeauna în instanța vie, indiferent de câte ori widget-ul e recreat.
//
// ── NAVIGARE CANVA PREZENTARE (canva.com) ────────────────────────────────────
//
// postMessage nu funcționează pentru Canva (restricții cross-origin).
// Canva suportă parametrul `slide=N` în URL-urile de tip /view sau /present.
// URL Canva embed:  https://www.canva.com/design/DAGxxxx/slug/view?embed
// → slide 3:        https://www.canva.com/design/DAGxxxx/slug/view?embed&slide=3
//
// ── CANVA WEBSITE PUBLICAT (my.canva.site) ────────────────────────────────────
//
// URL-urile de tipul https://xxx.my.canva.site sunt website-uri publicate,
// NU prezentări embed. Nu suportă parametrul slide=N — se încarcă direct
// ca un site web normal. Nu trimitem postMessage, nu modificăm URL-ul.
// Se tratează ca _usesUrlNavigation = true (fără postMessage) dar
// _buildPagedUrl returnează URL-ul nemodificat.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import '../../../core/model.dart';
import '../../../core/firebase_service.dart';

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

  // Root cause fix: map static viewId -> instanta activa curenta
  static final Map<String, _SlideIframeWidgetState> _activeStates  = {};
  static final Set<String>                          _registeredIds = {};

  // Guard pentru postMessage dublu (folosit doar pentru iframe-uri non-URL-nav)
  int _lastPostedPage = -1;

  // ── Detectare tip iframe ───────────────────────────────────────────────────

  bool get _isGoogleSlides =>
      widget.slide.url?.contains('docs.google.com/presentation') ?? false;

  /// Prezentare Canva embed (canva.com/design/...) — suportă slide=N în URL.
  bool get _isCanvaEmbed =>
      (widget.slide.url?.contains('canva.com') ?? false) &&
          !(widget.slide.url?.contains('canva.site') ?? false);

  /// Website publicat Canva (xxx.my.canva.site sau orice *.canva.site).
  /// Se încarcă direct ca iframe normal — fără parametri slide=N.
  bool get _isCanvaSite =>
      widget.slide.url?.contains('canva.site') ?? false;

  /// true → navigăm schimbând `src` cu parametrul `slide=N` (Google Slides + Canva embed).
  /// true → și pentru canva.site dar _buildPagedUrl nu adaugă nimic (website simplu).
  /// false → încercăm postMessage (alte iframe-uri custom).
  bool get _usesUrlNavigation => _isGoogleSlides || _isCanvaEmbed || _isCanvaSite;

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Apelat de factory cand creeaza un element DOM nou
  void _setIframeEl(web.HTMLIFrameElement el) {
    _iframeEl = el;
    _iframeEl!.style.pointerEvents = widget.overlayEnabled ? 'none' : 'auto';
  }

  /// Construiește URL-ul cu indexul de pagină pentru tipurile care suportă
  /// navigarea prin parametru de URL (Google Slides și Canva embed).
  /// Pentru canva.site (website publicat) returnează URL-ul nemodificat.
  static String _buildPagedUrl(String base, int page) {
    if (page == 0) return base;

    // ── Google Slides ──────────────────────────────────────────────────────
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

    // ── Canva embed (canva.com/design/...) ────────────────────────────────
    // Suportă ?slide=N (1-indexed) în URL-urile de tip /view sau /present.
    // Exemplu: https://www.canva.com/design/DAGxxxx/slug/view?embed&slide=3
    if (base.contains('canva.com') && !base.contains('canva.site')) {
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

    // ── Canva site publicat (*.canva.site) ────────────────────────────────
    // Website normal — nu suportă parametri slide=N. Returnăm URL-ul intact.
    if (base.contains('canva.site')) {
      return base;
    }

    return base;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _viewId = 'iframe-${widget.slide.id}-${widget.slide.url.hashCode}';

    // Inregistram ACEASTA instanta ca activa
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

        // Root cause fix: scriem in instanta ACTIVA, nu in cea veche
        _activeStates[_viewId]?._setIframeEl(el);
        return el;
      });
    }
  }

  @override
  void dispose() {
    if (_activeStates[_viewId] == this) {
      _activeStates.remove(_viewId);
    }
    super.dispose();
  }

  // ── Navigare ───────────────────────────────────────────────────────────────

  /// Trimite postMessage (ArrowLeft/Right + metode proprietare) pentru
  /// iframe-uri care nu suportă URL navigation (non-Canva, non-Google Slides).
  void _sendNavigationToIframe(bool forward) {
    try {
      final iframeWindow = _iframeEl?.contentWindow;
      if (iframeWindow == null) return;

      final keyName = forward ? 'ArrowRight' : 'ArrowLeft';
      final keyCode = forward ? 39 : 37;

      iframeWindow.postMessage(
        '{"type":"keydown","key":"$keyName","keyCode":$keyCode}'.toJS,
        '*'.toJS,
      );
      iframeWindow.postMessage(
        '{"method":"${forward ? 'goToNextSlide' : 'goToPreviousSlide'}"'
            ',"params":{}}'.toJS,
        '*'.toJS,
      );
      iframeWindow.postMessage(
        '{"action":"${forward ? 'next' : 'prev'}","source":"prezentare"}'.toJS,
        '*'.toJS,
      );
    } catch (_) {}

    try {
      _iframeEl?.focus();
    } catch (_) {}
  }

  /// Apelat de overlay la tap/swipe.
  /// Pentru URL navigation (Google Slides / Canva embed): doar actualizăm Firebase;
  /// `didUpdateWidget` va schimba `src` automat.
  /// Pentru canva.site: Firebase se actualizează dar src rămâne același (website).
  /// Pentru alte iframe-uri: Firebase + postMessage imediat.
  void _navigate(bool forward) {
    final newPage = forward
        ? widget.iframePageIndex + 1
        : (widget.iframePageIndex - 1).clamp(0, 999);
    if (newPage == widget.iframePageIndex) return;

    FirebaseService.instance.setIframePageIndex(newPage);

    if (!_usesUrlNavigation) {
      // postMessage pentru iframe-uri custom (non-Canva, non-Google Slides)
      _lastPostedPage = newPage;
      _sendNavigationToIframe(forward);
    }
    // Pentru Google Slides și Canva embed: src-ul se schimbă în didUpdateWidget.
    // Pentru canva.site: src rămâne neschimbat (website simplu, fără sub-pagini).
  }

  @override
  void didUpdateWidget(SlideIframeWidget old) {
    super.didUpdateWidget(old);

    if (old.iframePageIndex != widget.iframePageIndex) {
      if (_usesUrlNavigation) {
        // ── Google Slides + Canva embed: schimbăm src cu slide=N ────────────
        // ── Canva site: _buildPagedUrl returnează același URL (no-op) ────────
        final newUrl =
        _buildPagedUrl(widget.slide.url ?? '', widget.iframePageIndex);
        _iframeEl?.src = newUrl;
      } else {
        // ── Alte iframe-uri: postMessage (cu guard anti-dublu) ──────────────
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