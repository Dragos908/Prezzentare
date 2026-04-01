// lib/features/control/widgets/navigation_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/model.dart';
import '../bloc/control_bloc.dart';
import '../bloc/control_event.dart';

class NavigationPanel extends StatelessWidget {
  const NavigationPanel({super.key});

  // Helper: arată un snackbar scurt cu ce se întâmplă
  void _debug(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1a1a2e),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc    = context.read<ControlBloc>();
        final total   = state.slides.length;
        final cur     = state.currentSlide;
        final canPrev = cur > 0;
        final canNext = cur < total - 1;

        final currentSlide = state.slides.isNotEmpty
            ? state.slides[cur.clamp(0, state.slides.length - 1)]
            : null;
        final isIframeSlide = currentSlide?.type == SlideType.iframe;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Banner avertisment dacă slides sunt goale ──
              if (total == 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFBE21).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFBE21).withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFFFBE21), size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Slide-urile nu s-au încărcat din Firebase.\nButoanele nu pot naviga fără slide-uri.',
                          style: TextStyle(color: Color(0xFFFFBE21), fontSize: 11, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Navigare principală slide-uri ──
              Row(
                children: [
                  Expanded(
                    child: _NavButton(
                      label:   '← ANTERIOR',
                      onTap:   canPrev
                          ? () {
                        _debug(context, '← Slide anterior: ${cur} → ${cur - 1}');
                        bloc.add(NavigateRelativeEvent(false));
                      }
                          : () => _debug(context, '⚠ Ești deja pe primul slide (${cur + 1})'),
                      enabled: canPrev,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NavButton(
                      label:   'URMĂTOR →',
                      onTap:   canNext
                          ? () {
                        _debug(context, '→ Slide următor: ${cur} → ${cur + 1}');
                        bloc.add(NavigateRelativeEvent(true));
                      }
                          : () => _debug(context, total == 0
                          ? '⚠ Niciun slide în Firebase!'
                          : '⚠ Ești deja pe ultimul slide (${cur + 1}/$total)'),
                      enabled: canNext,
                      primary: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Reset la primul slide ──
              _NavButton(
                label:   '↩ PRIMUL SLIDE',
                onTap:   cur > 0
                    ? () {
                  _debug(context, '↩ Salt la slide 1 (de la ${cur + 1})');
                  bloc.add(GoToFirstEvent());
                }
                    : () => _debug(context, '⚠ Ești deja pe primul slide'),
                enabled: cur > 0,
              ),

              // ── Navigare iframe (apare doar pe slide-uri de tip iframe) ──
              if (isIframeSlide) ...[
                const SizedBox(height: 20),
                _IframeNavigationSection(
                  state: state,
                  bloc:  bloc,
                  slide: currentSlide!,
                ),
              ],

              const SizedBox(height: 24),

              // ── Grilă numerică ──
              const _SectionLabel('SALT DIRECT LA SLIDE'),
              const SizedBox(height: 10),
              if (total > 0)
                _SlideGridButtons(
                  total:    total,
                  current:  cur,
                  onSelect: (i) {
                    _debug(context, '🔢 Salt direct la slide ${i + 1}');
                    bloc.add(NavigateEvent(i));
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Secțiunea de navigare în cadrul unui iframe
// ─────────────────────────────────────────────
class _IframeNavigationSection extends StatelessWidget {
  final PresentationState state;
  final ControlBloc        bloc;
  final SlideModel         slide;

  const _IframeNavigationSection({
    required this.state,
    required this.bloc,
    required this.slide,
  });

  String get _serviceName {
    final url = slide.url ?? '';
    if (url.contains('docs.google.com')) return 'GOOGLE SLIDES';
    if (url.contains('canva.site'))      return 'CANVA SITE';
    if (url.contains('canva.com'))       return 'CANVA';
    return 'IFRAME';
  }

  bool get _supportsDeepLink {
    final url = slide.url ?? '';
    // Google Slides și Canva embed suportă navigare prin parametrul slide=N.
    // Canva site publicat (canva.site) este un website normal — nu are
    // concept de sub-pagini/deep-link, deci nu afișăm warning-ul.
    if (url.contains('docs.google.com')) return true;
    if (url.contains('canva.site'))      return true;  // website simplu, fără sub-slide-uri
    if (url.contains('canva.com'))       return true;  // embed canva cu slide=N
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final page    = state.iframePageIndex;
    final color   = const Color(0xFF00D9A3);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'NAVIGARE ÎN $_serviceName',
                style: TextStyle(
                  color:         color,
                  fontSize:      9,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              // Indicator pagina curentă
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Pag. ${page + 1}',
                  style: TextStyle(
                    color:      color,
                    fontSize:   12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Butoane mari prev / next ──
          Row(
            children: [
              Expanded(
                child: _IframeNavButton(
                  label:   '⟵ PAGINA ANTERIOARĂ',
                  enabled: page > 0,
                  onTap:   () => bloc.add(IframeNavigateEvent(false)),
                  color:   color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IframeNavButton(
                  label:   'PAGINA URMĂTOARE ⟶',
                  enabled: true,
                  onTap:   () => bloc.add(IframeNavigateEvent(true)),
                  color:   color,
                  primary: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Reset ──
          _IframeNavButton(
            label:   '↺ PRIMA PAGINĂ',
            enabled: page > 0,
            onTap:   () => bloc.add(IframeResetPageEvent()),
            color:   Colors.white38,
          ),

          // ── Hint keyboard shortcut ──
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _KeyBadge('Shift + ←'),
              const SizedBox(width: 6),
              Text(
                '/',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 6),
              _KeyBadge('Shift + →'),
              const SizedBox(width: 8),
              Text(
                'navigare rapidă',
                style: TextStyle(
                  color:    Colors.white.withOpacity(0.2),
                  fontSize: 9,
                ),
              ),
            ],
          ),

          // ── Warning dacă serviciul nu suportă deep-link ──
          if (!_supportsDeepLink) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        const Color(0xFFFFBE21).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFFFBE21).withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 11, color: Color(0xFFFFBE21)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_serviceName nu suportă deep-linking per pagină. '
                          'Contorul este trimis ecranului display — asigură-te că '
                          'display_bloc.dart ascultă iframePageIndexStream.',
                      style: TextStyle(
                        color:    const Color(0xFFFFBE21).withOpacity(0.7),
                        fontSize: 8.5,
                        height:   1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IframeNavButton extends StatelessWidget {
  final String label;
  final bool   enabled;
  final bool   primary;
  final Color  color;
  final VoidCallback onTap;

  const _IframeNavButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.color,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? color.withOpacity(primary ? 0.2 : 0.07)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? color.withOpacity(primary ? 0.5 : 0.2)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:         enabled ? color : Colors.white24,
            fontSize:      11,
            fontWeight:    FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String text;
  const _KeyBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color:      Colors.white54,
          fontSize:   9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Buton navigare slide principal
// ─────────────────────────────────────────────
class _NavButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool primary;

  const _NavButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? (primary
              ? const Color(0xFF6C63FF)
              : Colors.white.withOpacity(0.08))
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? (primary
                ? const Color(0xFF6C63FF)
                : Colors.white12)
                : Colors.white.withOpacity(0.04),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:         enabled ? Colors.white : Colors.white24,
            fontSize:      13,
            fontWeight:    FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grilă numerică
// ─────────────────────────────────────────────
class _SlideGridButtons extends StatelessWidget {
  final int total;
  final int current;
  final void Function(int) onSelect;

  const _SlideGridButtons({
    required this.total,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: List.generate(total, (i) {
        final isActive = i == current;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:        isActive
                  ? const Color(0xFF6C63FF)
                  : Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF6C63FF)
                    : Colors.white12,
              ),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color:      isActive ? Colors.white : Colors.white60,
                fontSize:   14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color:         Colors.white.withOpacity(0.35),
        fontSize:      9,
        letterSpacing: 2,
        fontWeight:    FontWeight.w600,
      ),
    );
  }
}