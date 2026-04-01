// lib/features/control/widgets/slide_panels.dart
//
// Conține ambele panouri legate de slide-uri:
//   • SlideListPanel    — lista completă de slide-uri (dreapta) cu timp acumulat
//   • SlideMonitorPanel — Presenter View: slide curent + următor + progres
//
// ── Iframe slides ──────────────────────────────────────────────────────────
// Pe Flutter Web, slide-urile de tip iframe se randează ca iframe real
// (HtmlElementView) SANDBOXAT — fără allow-top-navigation, cu
// pointer-events: none — deci NU mai poate redirecționa pagina parentă.
// iframePageIndex (din Firebase) controlează pagina activă în prezentare.
//
// ── FIX REDIRECT ───────────────────────────────────────────────────────────
// _SandboxedPreviewIframe înlocuiește WebIframeWidget în preview:
//   • pointer-events: none  → click-urile nu ajung la iframe
//   • sandbox fără allow-top-navigation → iframe nu poate naviga browserul
//   • src actualizat direct pe elementul HTML (fără rebuild Flutter)

import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/model.dart';
import '../bloc/control_bloc.dart';
import '../bloc/control_event.dart';

// ═════════════════════════════════════════════════════════════════════════════
// FUNCȚII TOP-LEVEL (shared de ambele panouri)
// ═════════════════════════════════════════════════════════════════════════════

/// Construiește URL-ul pentru o pagină anume.
/// Suportă deep-link real pentru Google Slides și Canva embed (canva.com).
/// Canva site publicat (canva.site) este website normal — URL rămâne intact.
String _buildPagedUrl(String base, int page) {
  if (page == 0) return base;
  if (base.contains('docs.google.com/presentation')) {
    try {
      final uri    = Uri.parse(base);
      final params = Map<String, String>.from(uri.queryParameters);
      params['slide'] = (page + 1).toString();
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return base;
    }
  }
  if (base.contains('canva.com') && !base.contains('canva.site')) {
    try {
      final uri    = Uri.parse(base);
      final params = Map<String, String>.from(uri.queryParameters);
      params['slide'] = (page + 1).toString();
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return base;
    }
  }
  // canva.site (website publicat) și alte iframe-uri → URL nemodificat
  return base;
}

bool _isGoogleSlides(String? url) =>
    url != null && url.contains('docs.google.com');

bool _isCanvaEmbed(String? url) =>
    url != null && url.contains('canva.com') && !url.contains('canva.site');

bool _isCanvaSite(String? url) =>
    url != null && url.contains('canva.site');

/// Returnează true dacă URL-ul suportă navigare per pagină (fără warning).
bool _supportsDeepLink(String? url) =>
    _isGoogleSlides(url) || _isCanvaEmbed(url) || _isCanvaSite(url);

// ═════════════════════════════════════════════════════════════════════════════
// SLIDE LIST PANEL
// Panoul dreapta: lista completă de slide-uri cu timp acumulat.
// Click pe orice slide → salt direct.
// ═════════════════════════════════════════════════════════════════════════════
class SlideListPanel extends StatelessWidget {
  const SlideListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc = context.read<ControlBloc>();

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0d0d14),
            border: Border(left: BorderSide(color: Colors.white.withOpacity(0.07))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Text(
                  'SLIDE-URI',
                  style: const TextStyle(
                    color:         Colors.white,
                    fontSize:      12,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.white.withOpacity(0.07)),

              // ── Listă ──
              Expanded(
                child: state.slides.isEmpty
                    ? Center(
                  child: Text(
                    'NICIUN SLIDE',
                    style: TextStyle(
                      color:         Colors.white.withOpacity(0.15),
                      fontSize:      10,
                      letterSpacing: 2,
                    ),
                  ),
                )
                    : ListView.builder(
                  itemCount: state.slides.length,
                  itemBuilder: (_, i) {
                    final slide    = state.slides[i];
                    final isActive = i == state.currentSlide;
                    final timer    = state.slideTimers[i];
                    final ms       = timer?.totalMs ?? 0;

                    return _SlideListItem(
                      slide:    slide,
                      index:    i,
                      isActive: isActive,
                      timeMs:   ms,
                      onTap:    () => bloc.add(NavigateEvent(i)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlideListItem extends StatelessWidget {
  final SlideModel   slide;
  final int          index;
  final bool         isActive;
  final int          timeMs;
  final VoidCallback onTap;

  const _SlideListItem({
    required this.slide,
    required this.index,
    required this.isActive,
    required this.timeMs,
    required this.onTap,
  });

  static const _typeColors = {
    SlideType.intro:      Color(0xFF6C63FF),
    SlideType.transition: Color(0xFFFF6584),
    SlideType.iframe:     Color(0xFF00D9A3),
    SlideType.end:        Color(0xFFFFBE21),
    SlideType.announce:   Color(0xFFFF9800),
  };

  static const _typeLabels = {
    SlideType.intro:      'INTRO',
    SlideType.transition: 'TRANZ.',
    SlideType.iframe:     'IFRAME',
    SlideType.end:        'FINAL',
    SlideType.announce:   'ANUNȚ',
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[slide.type]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color.withOpacity(0.35) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Indicator activ
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width:  3,
              height: 36,
              decoration: BoxDecoration(
                color:        isActive ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),

            // Număr + info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color:      isActive ? color : Colors.white30,
                          fontSize:   11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color:        color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _typeLabels[slide.type]!,
                          style: TextStyle(
                            color:         color,
                            fontSize:      8,
                            fontWeight:    FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    slide.title,
                    style: TextStyle(
                      color:      isActive ? Colors.white : Colors.white60,
                      fontSize:   12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Timp acumulat
            if (timeMs > 0)
              Text(
                formatMsShort(timeMs),
                style: TextStyle(
                  color:      isActive ? color : Colors.white24,
                  fontSize:   11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SANDBOXED PREVIEW IFRAME  (folosit intern de SlideMonitorPanel)
// • pointer-events: none  → nicio interacțiune a utilizatorului cu iframe-ul
// • sandbox fără allow-top-navigation → iframe-ul NU poate redirecționa
//   fereastra parentă în nicio circumstanță
// • src se actualizează direct în DOM când URL-ul se schimbă
// ═════════════════════════════════════════════════════════════════════════════
class _SandboxedPreviewIframe extends StatefulWidget {
  final String url;
  const _SandboxedPreviewIframe({super.key, required this.url});

  @override
  State<_SandboxedPreviewIframe> createState() =>
      _SandboxedPreviewIframeState();
}

class _SandboxedPreviewIframeState extends State<_SandboxedPreviewIframe> {
  static int _idCounter = 0;
  static final Map<String, web.HTMLIFrameElement> _domCache = {};

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'ctrl-preview-iframe-${_idCounter++}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final el = web.HTMLIFrameElement();
      el.src = widget.url;
      el.style.border        = 'none';
      el.style.width         = '100%';
      el.style.height        = '100%';
      el.style.pointerEvents = 'none';
      el.setAttribute(
        'sandbox',
        'allow-scripts allow-same-origin allow-forms '
            'allow-popups allow-presentation',
      );
      el.setAttribute('scrolling',       'no');
      el.setAttribute('allowfullscreen', 'false');

      _domCache[_viewType] = el;
      return el;
    });
  }

  @override
  void didUpdateWidget(_SandboxedPreviewIframe old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _domCache[_viewType]?.src = widget.url;
    }
  }

  @override
  void dispose() {
    _domCache.remove(_viewType);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

// ═════════════════════════════════════════════════════════════════════════════
// SLIDE MONITOR PANEL  — Presenter View
// ═════════════════════════════════════════════════════════════════════════════
class SlideMonitorPanel extends StatelessWidget {
  const SlideMonitorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        if (state.slides.isEmpty) return const _EmptyPanel();

        final curIdx  = state.currentSlide.clamp(0, state.slides.length - 1);
        final current = state.slides[curIdx];
        final nextIdx = curIdx + 1;
        final hasNext = nextIdx < state.slides.length;
        final next    = hasNext ? state.slides[nextIdx] : null;

        final isCurrentIframe          = current.type == SlideType.iframe;
        final hasNextPage              = isCurrentIframe;
        final nextPageIndex            = state.iframePageIndex + 1;
        final nextPageSupportsDeepLink = _supportsDeepLink(current.url);

        return Container(
          color: const Color(0xFF0b0b16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MonitorHeader(curIdx: curIdx, total: state.slides.length),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [

                      // ── SLIDE CURENT ────────────────────────────────────
                      _PreviewLabel(
                        label: 'PE TABLĂ ACUM',
                        color: const Color(0xFF00D9A3),
                        icon:  Icons.tv_outlined,
                      ),
                      const SizedBox(height: 8),
                      _SlideVisualPreview(
                        slide:           current,
                        index:           curIdx,
                        isCurrent:       true,
                        timeMs:          state.slideTimers[curIdx]?.totalMs ?? 0,
                        iframePageIndex: state.iframePageIndex,
                      ),

                      if (isCurrentIframe) ...[
                        const SizedBox(height: 12),
                        _IframeNavBar(
                          pageIndex: state.iframePageIndex,
                          url:       current.url,
                          bloc:      context.read<ControlBloc>(),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── POINTER PAD ──────────────────────────────────────
                      _PointerPadSection(
                        slide:           current,
                        iframePageIndex: state.iframePageIndex,
                      ),

                      const SizedBox(height: 20),

                      // ── PAGINA URMĂTOARE (în iframe-ul curent) ───────────
                      // Ascundem pentru Canva — nu suportă navigare externă
                      if (hasNextPage && nextPageSupportsDeepLink && !_isCanvaEmbed(current.url) && !_isCanvaSite(current.url)) ...[
                        _PreviewLabel(
                          label: 'PAGINA URMĂTOARE',
                          color: const Color(0xFF00D9A3).withOpacity(0.55),
                          icon:  Icons.navigate_next_outlined,
                        ),
                        const SizedBox(height: 8),
                        _SlideVisualPreview(
                          slide:           current,
                          index:           curIdx,
                          isCurrent:       false,
                          timeMs:          0,
                          iframePageIndex: nextPageIndex,
                          labelOverride:   'Pag. ${nextPageIndex + 1}',
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── SLIDE URMĂTOR ────────────────────────────────────
                      _PreviewLabel(
                        label: 'SLIDE URMĂTOR',
                        color: Colors.white.withOpacity(0.3),
                        icon:  Icons.skip_next_outlined,
                      ),
                      const SizedBox(height: 8),
                      if (next != null)
                        GestureDetector(
                          onTap: () => context
                              .read<ControlBloc>()
                              .add(NavigateEvent(nextIdx)),
                          child: _SlideVisualPreview(
                            slide:           next,
                            index:           nextIdx,
                            isCurrent:       false,
                            timeMs:          state.slideTimers[nextIdx]?.totalMs ?? 0,
                            iframePageIndex: 0,
                          ),
                        )
                      else
                        _EndOfPresentation(),

                      const SizedBox(height: 20),

                      // ── Bară progres ─────────────────────────────────────
                      _ProgressSection(
                        current: curIdx,
                        total:   state.slides.length,
                        slides:  state.slides,
                        onTap:   (i) => context
                            .read<ControlBloc>()
                            .add(NavigateEvent(i)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Header cu titlu + contor slide ───────────────────────────────────────────
class _MonitorHeader extends StatelessWidget {
  final int curIdx;
  final int total;
  const _MonitorHeader({required this.curIdx, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF00D9A3),
              boxShadow: [BoxShadow(color: Color(0x5500D9A3), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'PRESENTER VIEW',
            style: TextStyle(
              color:         Colors.white,
              fontSize:      10,
              fontWeight:    FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          Text(
            '${curIdx + 1} / $total',
            style: TextStyle(
              color:      Colors.white.withOpacity(0.3),
              fontSize:   10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bara de navigare iframe ───────────────────────────────────────────────────
class _IframeNavBar extends StatelessWidget {
  final int       pageIndex;
  final String?   url;
  final ControlBloc bloc;

  const _IframeNavBar({
    required this.pageIndex,
    required this.url,
    required this.bloc,
  });

  String get _serviceName {
    if (url == null) return 'IFRAME';
    if (url!.contains('docs.google.com')) return 'GOOGLE SLIDES';
    if (url!.contains('canva.site'))      return 'CANVA SITE';
    if (url!.contains('canva.com'))       return 'CANVA';
    return 'IFRAME';
  }

  bool get _hasDeepLink => _supportsDeepLink(url);

  bool get _isCanva =>
      url != null && (url!.contains('canva.com') || url!.contains('canva.site'));

  @override
  Widget build(BuildContext context) {
    // Canva nu suportă navigare programatică — ascundem butoanele complet
    if (_isCanva) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color:        const Color(0xFFFF9800).withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 12, color: Color(0xFFFF9800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Canva nu permite navigare externă. Folosește săgețile din prezentarea Canva direct.',
                style: TextStyle(
                  color:     const Color(0xFFFF9800).withOpacity(0.8),
                  fontSize:  9,
                  fontStyle: FontStyle.italic,
                  height:    1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:        const Color(0xFF00D9A3).withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00D9A3).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.web_outlined, size: 10, color: Color(0xFF00D9A3)),
              const SizedBox(width: 5),
              Text(
                'SUB-SLIDE $_serviceName',
                style: const TextStyle(
                  color:         Color(0xFF00D9A3),
                  fontSize:      8,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color:        const Color(0xFF00D9A3).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Pag. ${pageIndex + 1}',
                  style: const TextStyle(
                    color:      Color(0xFF00D9A3),
                    fontSize:   10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              _IframeNavBtn(
                icon:    Icons.chevron_left,
                label:   '← PREV',
                enabled: pageIndex > 0,
                onTap:   () => bloc.add(IframeNavigateEvent(false)),
              ),
              const SizedBox(width: 6),
              _IframeNavBtn(
                icon:    Icons.refresh,
                label:   '↺',
                enabled: pageIndex > 0,
                onTap:   () => bloc.add(IframeResetPageEvent()),
                compact: true,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _IframeNavBtn(
                  icon:    Icons.chevron_right,
                  label:   'NEXT →',
                  enabled: true,
                  primary: true,
                  onTap:   () => bloc.add(IframeNavigateEvent(true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IframeNavBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         enabled;
  final bool         primary;
  final bool         compact;
  final VoidCallback onTap;

  const _IframeNavBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (primary ? const Color(0xFF00D9A3) : Colors.white54)
        : Colors.white12;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? (primary
              ? const Color(0xFF00D9A3).withOpacity(0.15)
              : Colors.white.withOpacity(0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled
                ? (primary
                ? const Color(0xFF00D9A3).withOpacity(0.4)
                : Colors.white12)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: compact
            ? Icon(icon, size: 14, color: color)
            : Text(
          label,
          style: TextStyle(
            color:         color,
            fontSize:      10,
            fontWeight:    FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Preview vizual complet al unui slide ─────────────────────────────────────
class _SlideVisualPreview extends StatelessWidget {
  final SlideModel slide;
  final int        index;
  final bool       isCurrent;
  final int        timeMs;
  final int        iframePageIndex;
  final String?    labelOverride;

  const _SlideVisualPreview({
    required this.slide,
    required this.index,
    required this.isCurrent,
    required this.timeMs,
    required this.iframePageIndex,
    this.labelOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _SlideThumbnailContent(
                  slide:           slide,
                  iframePageIndex: iframePageIndex,
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent
                          ? const Color(0xFF00D9A3).withOpacity(0.8)
                          : Colors.white.withOpacity(0.1),
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                ),
                if (isCurrent)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color:        const Color(0xFF00D9A3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 5, color: Colors.black),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color:         Colors.black,
                              fontSize:      8,
                              fontWeight:    FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 6, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:        Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      labelOverride ?? '${index + 1}',
                      style: const TextStyle(
                        color:      Colors.white70,
                        fontSize:   9,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _TypeBadge(type: slide.type),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labelOverride != null
                    ? '${slide.title} • $labelOverride'
                    : slide.title,
                style: TextStyle(
                  color:      isCurrent ? Colors.white : Colors.white60,
                  fontSize:   11,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (timeMs > 0)
              Text(
                formatMsShort(timeMs),
                style: TextStyle(
                  color:      isCurrent ? const Color(0xFF00D9A3) : Colors.white24,
                  fontSize:   10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Randare vizuală a conținutului unui slide ─────────────────────────────────
class _SlideThumbnailContent extends StatelessWidget {
  final SlideModel slide;
  final int        iframePageIndex;

  const _SlideThumbnailContent({
    required this.slide,
    this.iframePageIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return switch (slide.type) {
      SlideType.intro      => _IntroThumbnail(slide: slide),
      SlideType.transition => _TransitionThumbnail(slide: slide),
      SlideType.iframe     => _IframeThumbnail(
        slide:           slide,
        iframePageIndex: iframePageIndex,
      ),
      SlideType.end        => _EndThumbnail(slide: slide),
      SlideType.announce   => _AnnounceThumbnail(slide: slide),
    };
  }
}

// ── Thumbnails per tip ────────────────────────────────────────────────────────
class _IntroThumbnail extends StatelessWidget {
  final SlideModel slide;
  const _IntroThumbnail({required this.slide});

  @override
  Widget build(BuildContext context) {
    final c1 = slide.color1 != null
        ? hexToColor(slide.color1!) : const Color(0xFF0a0a1a);
    final c2 = slide.color2 != null
        ? hexToColor(slide.color2!) : const Color(0xFF1a0a2e);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
              colors: [c1, c2],
            ),
          ),
        ),
        if (slide.orbColors != null)
          ...slide.orbColors!.take(3).toList().asMap().entries.map((e) {
            final sizes = [120.0, 90.0, 70.0];
            final xPos  = [0.1, 0.6, 0.85][e.key];
            final yPos  = [0.15, 0.65, 0.1][e.key];
            final size  = sizes[e.key];
            return Positioned.fill(
              child: Align(
                alignment: Alignment(xPos * 2 - 1, yPos * 2 - 1),
                child: FractionallySizedBox(
                  widthFactor: size / 292,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hexToColor(e.value).withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slide.heading ?? slide.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3, height: 1.2,
                  ),
                ),
                if (slide.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    slide.subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 7, letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TransitionThumbnail extends StatelessWidget {
  final SlideModel slide;
  const _TransitionThumbnail({required this.slide});

  @override
  Widget build(BuildContext context) {
    final c1 = slide.color1 != null
        ? hexToColor(slide.color1!) : const Color(0xFF050510);
    final c2 = slide.color2 != null
        ? hexToColor(slide.color2!) : const Color(0xFF6C63FF);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: c1),
        CustomPaint(
          painter: _StaticWavePainter(
            color1: c2,
            color2: slide.color2 != null
                ? hexToColor(slide.color2!).withOpacity(0.6)
                : const Color(0xFFFF6584).withOpacity(0.6),
          ),
          child: const SizedBox.expand(),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:        c2.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c2.withOpacity(0.4)),
            ),
            child: Text(
              (slide.animation ?? 'wave').toUpperCase(),
              style: TextStyle(
                color: c2, fontSize: 8,
                fontWeight: FontWeight.w700, letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StaticWavePainter extends CustomPainter {
  final Color color1;
  final Color color2;
  const _StaticWavePainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    void drawWave(double offsetY, Color color, double amp, double phase) {
      final paint = Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 2) {
        final y = offsetY +
            amp * math.sin((x / size.width * 2 * math.pi) + phase);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }

    drawWave(size.height * 0.5,  color1, size.height * 0.12, 0);
    drawWave(size.height * 0.58, color2, size.height * 0.10, math.pi * 0.5);
  }

  @override
  bool shouldRepaint(_StaticWavePainter old) => false;
}

class _IframeThumbnail extends StatelessWidget {
  final SlideModel slide;
  final int        iframePageIndex;

  const _IframeThumbnail({
    required this.slide,
    required this.iframePageIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (slide.staticImageUrl != null) {
      return Image.network(
        slide.staticImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _IframePlaceholder(slide: slide),
      );
    }

    if (kIsWeb && slide.url != null && slide.url!.isNotEmpty) {
      final url = _buildPagedUrl(slide.url!, iframePageIndex);
      return Stack(
        fit: StackFit.expand,
        children: [
          _SandboxedPreviewIframe(url: url),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end:   Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    slide.url!.contains('canva.com')
                        ? Icons.design_services_outlined
                        : Icons.slideshow_outlined,
                    size: 10, color: const Color(0xFF00D9A3),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    slide.url!.contains('canva.com')
                        ? 'CANVA' : 'GOOGLE SLIDES',
                    style: const TextStyle(
                      color: Color(0xFF00D9A3), fontSize: 8,
                      fontWeight: FontWeight.w700, letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '• Pag. ${iframePageIndex + 1}',
                    style: const TextStyle(
                      color: Color(0xFF00D9A3), fontSize: 9,
                      fontFamily: 'monospace', fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _IframePlaceholder(slide: slide);
  }
}

class _EndThumbnail extends StatelessWidget {
  final SlideModel slide;
  const _EndThumbnail({required this.slide});

  @override
  Widget build(BuildContext context) {
    final c1 = slide.color1 != null
        ? hexToColor(slide.color1!) : const Color(0xFF1a0a2e);
    final c2 = slide.color2 != null
        ? hexToColor(slide.color2!) : const Color(0xFF6C63FF);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center, radius: 1.5,
              colors: [c1, Colors.black],
            ),
          ),
        ),
        Center(
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c2.withOpacity(0.3), Colors.transparent],
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slide.heading ?? slide.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w700, height: 1.2,
                  ),
                ),
                if (slide.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    slide.subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 7, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Placeholder Canva (next page fără deep-link) ──────────────────────────────
class _CanvaNextPagePlaceholder extends StatelessWidget {
  final SlideModel slide;
  final int        pageIndex;

  const _CanvaNextPagePlaceholder({
    required this.slide,
    required this.pageIndex,
  });

  @override
  Widget build(BuildContext context) {
    const color  = Color(0xFF7D2AE8);
    const accent = Color(0xFF00D9A3);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
              colors: [const Color(0xFF0d0d18), color.withOpacity(0.15)],
            ),
            border: Border.all(color: color.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  color.withOpacity(0.15),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: const Icon(
                    Icons.design_services_outlined, color: color, size: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'CANVA',
                style: TextStyle(
                  color: color, fontSize: 8,
                  fontWeight: FontWeight.w800, letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color:        accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border:       Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Text(
                  'Pagina ${pageIndex + 1}',
                  style: const TextStyle(
                    color: accent, fontSize: 11,
                    fontFamily: 'monospace', fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Canva nu suportă previzualizare\nper pagină din exterior',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 7.5, height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Placeholder generic iframe ────────────────────────────────────────────────
class _IframePlaceholder extends StatelessWidget {
  final SlideModel slide;
  const _IframePlaceholder({required this.slide});

  @override
  Widget build(BuildContext context) {
    final url            = slide.url ?? '';
    final isGoogleSlides = url.contains('docs.google.com');
    final isCanva        = url.contains('canva.com');

    String   serviceName  = 'IFRAME';
    IconData serviceIcon  = Icons.web_outlined;
    Color    serviceColor = const Color(0xFF00D9A3);

    if (isGoogleSlides) {
      serviceName  = 'GOOGLE SLIDES';
      serviceIcon  = Icons.slideshow_outlined;
      serviceColor = const Color(0xFF4285F4);
    } else if (isCanva) {
      serviceName  = 'CANVA';
      serviceIcon  = Icons.design_services_outlined;
      serviceColor = const Color(0xFF7D2AE8);
    }

    return Container(
      color: const Color(0xFF0d1117),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  serviceColor.withOpacity(0.15),
              border: Border.all(color: serviceColor.withOpacity(0.3)),
            ),
            child: Icon(serviceIcon, color: serviceColor, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            serviceName,
            style: TextStyle(
              color: serviceColor, fontSize: 7,
              fontWeight: FontWeight.w700, letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              slide.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Secțiunea progres + mini dot-uri ─────────────────────────────────────────
class _ProgressSection extends StatelessWidget {
  final int current;
  final int total;
  final List<SlideModel> slides;
  final void Function(int) onTap;

  const _ProgressSection({
    required this.current,
    required this.total,
    required this.slides,
    required this.onTap,
  });

  static const _typeColors = {
    SlideType.intro:      Color(0xFF6C63FF),
    SlideType.transition: Color(0xFFFF6584),
    SlideType.iframe:     Color(0xFF00D9A3),
    SlideType.end:        Color(0xFFFFBE21),
    SlideType.announce:   Color(0xFFFF9800),
  };

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (current + 1) / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PROGRES',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25), fontSize: 8,
                fontWeight: FontWeight.w800, letterSpacing: 2,
              ),
            ),
            Text(
              '${current + 1} din $total',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 9, fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value:           ratio,
            minHeight:       5,
            backgroundColor: Colors.white.withOpacity(0.07),
            valueColor:      const AlwaysStoppedAnimation<Color>(
                Color(0xFF6C63FF)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4, runSpacing: 4,
          children: List.generate(total, (i) {
            final isActive = i == current;
            final color    = _typeColors[slides[i].type]!;
            return GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:  isActive ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color:        isActive ? color : color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Widget helpers ────────────────────────────────────────────────────────────
class _PreviewLabel extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData icon;

  const _PreviewLabel({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color, fontSize: 8,
              fontWeight: FontWeight.w800, letterSpacing: 1.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final SlideType type;
  const _TypeBadge({required this.type});

  static const _colors = {
    SlideType.intro:      Color(0xFF6C63FF),
    SlideType.transition: Color(0xFFFF6584),
    SlideType.iframe:     Color(0xFF00D9A3),
    SlideType.end:        Color(0xFFFFBE21),
    SlideType.announce:   Color(0xFFFF9800),
  };
  static const _labels = {
    SlideType.intro:      'INTRO',
    SlideType.transition: 'TRANZ.',
    SlideType.iframe:     'IFRAME',
    SlideType.end:        'FINAL',
    SlideType.announce:   'ANUNȚ',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        _labels[type]!,
        style: TextStyle(
          color: color, fontSize: 7,
          fontWeight: FontWeight.w800, letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EndOfPresentation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.white.withOpacity(0.2), size: 20),
            const SizedBox(height: 4),
            Text(
              'FINAL PREZENTARE',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0b0b16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_outlined,
                color: Colors.white.withOpacity(0.1), size: 28),
            const SizedBox(height: 10),
            Text(
              'SE CONECTEAZĂ...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.15),
                fontSize: 9, letterSpacing: 3, fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════
// POINTER PAD — previzualizare live + mod LASER / CLICK
// ═══════════════════════════════════════════════════════════════════════════

enum _PointerMode { laser, click }

class _PointerPadSection extends StatefulWidget {
  final SlideModel slide;
  final int        iframePageIndex;

  const _PointerPadSection({
    required this.slide,
    required this.iframePageIndex,
  });

  @override
  State<_PointerPadSection> createState() => _PointerPadSectionState();
}

class _PointerPadSectionState extends State<_PointerPadSection> {
  _PointerMode _mode     = _PointerMode.laser;
  bool         _isActive = false;
  Offset       _normPos  = const Offset(0.5, 0.5);
  DateTime?    _lastSend;

  Offset _clamp(Offset local, Size sz) => Offset(
    (local.dx / sz.width).clamp(0.0, 1.0),
    (local.dy / sz.height).clamp(0.0, 1.0),
  );

  void _onDown(Offset local, Size sz) {
    final n = _clamp(local, sz);
    setState(() { _normPos = n; _isActive = true; });
    context.read<ControlBloc>().add(SetPointerEvent(n.dx, n.dy));
  }

  void _onMove(Offset local, Size sz) {
    final n = _clamp(local, sz);
    setState(() => _normPos = n);
    final now = DateTime.now();
    if (_lastSend == null ||
        now.difference(_lastSend!) > const Duration(milliseconds: 40)) {
      _lastSend = now;
      context.read<ControlBloc>().add(SetPointerEvent(n.dx, n.dy));
    }
  }

  void _onUp() {
    if (_mode == _PointerMode.click) {
      context.read<ControlBloc>().add(SetPointerClickEvent(_normPos.dx, _normPos.dy));
    }
    context.read<ControlBloc>().add(ClearPointerEvent());
    setState(() => _isActive = false);
  }

  Color get _dotColor => _mode == _PointerMode.click
      ? const Color(0xFF00D9A3)
      : const Color(0xFFFF2244);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (ctx, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Header row ──────────────────────────────────────────────
            Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape:     BoxShape.circle,
                  color:     _dotColor,
                  boxShadow: _isActive
                      ? [BoxShadow(color: _dotColor.withOpacity(0.6), blurRadius: 8)]
                      : [],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'POINTER LASER',
                style: TextStyle(
                  color:         const Color(0xFFFF2244).withOpacity(0.85),
                  fontSize:      8,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (_isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        _dotColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _dotColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    '● ACTIV',
                    style: TextStyle(
                      color:         _dotColor,
                      fontSize:      8,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 8),

            // ── Mode toggle ──────────────────────────────────────────────
            Row(children: [
              Expanded(child: _ModeBtn(
                label:  '🔴  LASER',
                sub:    'Arată fără a apăsa',
                active: _mode == _PointerMode.laser,
                color:  const Color(0xFFFF2244),
                onTap:  () => setState(() => _mode = _PointerMode.laser),
              )),
              const SizedBox(width: 8),
              Expanded(child: _ModeBtn(
                label:  '👆  CLICK',
                sub:    'Arată și apasă pe display',
                active: _mode == _PointerMode.click,
                color:  const Color(0xFF00D9A3),
                onTap:  () => setState(() => _mode = _PointerMode.click),
              )),
            ]),
            const SizedBox(height: 10),

            // ── Interactive preview pad ──────────────────────────────────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: LayoutBuilder(builder: (_, constraints) {
                final sz = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  onPointerDown:   (e) => _onDown(e.localPosition, sz),
                  onPointerMove:   (e) => _onMove(e.localPosition, sz),
                  onPointerUp:     (_) => _onUp(),
                  onPointerCancel: (_) => _onUp(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(fit: StackFit.expand, children: [

                      // Live slide thumbnail — identic cu Presenter View
                      _SlideThumbnailContent(
                        slide:           widget.slide,
                        iframePageIndex: widget.iframePageIndex,
                      ),

                      // Border activ/inactiv
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isActive
                                ? _dotColor.withOpacity(0.85)
                                : Colors.white.withOpacity(0.1),
                            width: _isActive ? 2 : 1,
                          ),
                        ),
                      ),

                      // Crosshair + dot în timp ce tragi
                      if (_isActive)
                        CustomPaint(
                          painter: _CrosshairPainter(
                            x: _normPos.dx, y: _normPos.dy, color: _dotColor,
                          ),
                        ),

                      // Dot Firebase când nu tragi tu (alt utilizator activ)
                      if (state.pointerActive && !_isActive)
                        Positioned(
                          left: state.pointerX * sz.width  - 9,
                          top:  state.pointerY * sz.height - 9,
                          child: Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF2244),
                              boxShadow: [BoxShadow(
                                color:      const Color(0xFFFF2244).withOpacity(0.5),
                                blurRadius: 10,
                              )],
                            ),
                          ),
                        ),

                      // Hint când e inactiv
                      if (!_isActive && !state.pointerActive)
                        Center(child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color:        Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _mode == _PointerMode.laser
                                ? 'Trage pentru pointer pe proiector'
                                : 'Apasă pentru a da click pe proiector',
                            style: const TextStyle(
                              color: Colors.white60, fontSize: 9,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )),

                      // Badge mod curent
                      Positioned(
                        top: 6, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color:        Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _dotColor.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            _mode == _PointerMode.laser ? '🔴 LASER' : '👆 CLICK',
                            style: TextStyle(
                              color:      _dotColor,
                              fontSize:   8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ),

            const SizedBox(height: 6),
            Text(
              _mode == _PointerMode.laser
                  ? 'LASER — arată doar unde privești, fără a interacționa cu conținutul.'
                  : 'CLICK — trimite un click real la poziția indicată pe proiector.',
              style: TextStyle(
                color:    Colors.white.withOpacity(0.25),
                fontSize: 8.5,
                height:   1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode button
// ─────────────────────────────────────────────────────────────────────────────
class _ModeBtn extends StatelessWidget {
  final String       label, sub;
  final bool         active;
  final Color        color;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.label,
    required this.sub,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? color.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active
                ? color.withOpacity(0.5)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              color:      active ? color : Colors.white38,
              fontSize:   10,
              fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(
              color:    active ? color.withOpacity(0.6) : Colors.white24,
              fontSize: 8,
            )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crosshair painter — linie + dot + ring
// ─────────────────────────────────────────────────────────────────────────────
class _CrosshairPainter extends CustomPainter {
  final double x, y;
  final Color  color;

  const _CrosshairPainter({
    required this.x,
    required this.y,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final px = x * size.width;
    final py = y * size.height;

    // Linii crosshair
    final linePaint = Paint()
      ..color       = color.withOpacity(0.30)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(0, py), Offset(size.width, py), linePaint);
    canvas.drawLine(Offset(px, 0), Offset(px, size.height), linePaint);

    // Dot central plin
    canvas.drawCircle(
      Offset(px, py), 7,
      Paint()..color = color,
    );

    // Ring exterior semi-transparent
    canvas.drawCircle(
      Offset(px, py), 14,
      Paint()
        ..color       = color.withOpacity(0.35)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CrosshairPainter o) =>
      o.x != x || o.y != y || o.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Thumbnail tip ANNOUNCE — pentru Presenter View și lista de slide-uri
// ─────────────────────────────────────────────────────────────────────────────
class _AnnounceThumbnail extends StatelessWidget {
  final SlideModel slide;
  const _AnnounceThumbnail({required this.slide});

  @override
  Widget build(BuildContext context) {
    final accent = slide.color1 != null
        ? hexToColor(slide.color1!)
        : const Color(0xFF6C63FF);
    final accent2 = slide.color2 != null
        ? hexToColor(slide.color2!)
        : const Color(0xFF00D9A3);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fundal întunecat
        Container(color: const Color(0xFF04040C)),

        // Gradient ambient
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.5),
              radius: 1.2,
              colors: [accent.withOpacity(0.18), Colors.transparent],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.7, 0.6),
              radius: 1.0,
              colors: [accent2.withOpacity(0.14), Colors.transparent],
            ),
          ),
        ),

        // Linie de accentColor sus
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, accent, accent2, Colors.transparent],
              ),
            ),
          ),
        ),

        // Conținut centrat
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Iconiță telefon
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.12),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text('📵', style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 6),

              // Titlu principal
              Text(
                slide.heading ?? 'Pentru o vizionare plăcută',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   10,
                  fontWeight: FontWeight.w700,
                  height:     1.2,
                ),
              ),
              const SizedBox(height: 5),

              // Mini reguli
              ...['📵 Silențios', '🤫 Liniște', '💬 Întrebări la final']
                  .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(r,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontSize: 7,
                  ),
                ),
              )),
            ],
          ),
        ),

        // Badge tip
        Positioned(
          bottom: 5, right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color:        const Color(0xFFFF9800).withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.4)),
            ),
            child: const Text('ANUNȚ', style: TextStyle(
              color: Color(0xFFFF9800), fontSize: 6,
              fontWeight: FontWeight.w800, letterSpacing: 0.5,
            )),
          ),
        ),
      ],
    );
  }
}