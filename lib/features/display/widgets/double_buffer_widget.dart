// lib/features/display/widgets/double_buffer_widget.dart
//
// ── DOUBLE BUFFER + TRANZIȚII ────────────────────────────────────────────────
//
// Slide-ul nou se montează în buffer-ul inactiv, iar tranziția către el depinde
// de câmpul opțional `transitionIn` al slide-ului (vezi model.dart):
//
//   'flash' (implicit) — crossfade + dâră de lumină care taie ecranul (~700 ms):
//        1. FLASH IN   (0–120 ms)   dâra luminoasă traversează ecranul
//        2. HOLD       (120–200 ms) flash la opacitate maximă, noul slide intră
//        3. FADE OUT   (200–700 ms) flash-ul dispare, noul slide e vizibil
//
//   'fade'  — crossfade simplu, fără dâră de lumină.
//
//   'black' — MUTARE SPRE ECRAN NEGRU (~1 s): imaginea veche se stinge spre
//             negru, ecranul rămâne complet negru o clipă, iar slide-ul nou
//             apare din negru. Comutarea buffer-elor se face exact când
//             ecranul e opac negru, deci nu se vede nicio „săritură”.
//
//   'cut'   — schimbare instantanee.
//
// ── Video în tranziție ────────────────────────────────────────────────────────
//   • slide-ul care iese este amuțit imediat (nu se aud două sunete deodată);
//   • videoclipul care intră se încarcă imediat, dar așteaptă (`hold`) să
//     devină vizibil, ca imaginea și sunetul să înceapă împreună;
//   • doar slide-ul curent publică heartbeat-ul video către Control.
//
// ── Navigare rapidă ───────────────────────────────────────────────────────────
// Dacă vine o nouă comandă de slide cât timp rulează o tranziție, ea nu se mai
// pierde: se reține ultima destinație și se aplică imediat după tranziție.
//
// ── PREÎNCĂRCARE IFRAME ───────────────────────────────────────────────────────
// Toate slide-urile iframe sunt montate cu Offstage(offstage: true) pentru
// preîncărcare invizibilă. Browserul descarcă conținutul în fundal.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/model.dart';
import 'slide_iframe_widget.dart';
import '/features/display/display_page.dart';

enum _TransitionMode { flash, fade, black, cut }

_TransitionMode _modeFor(SlideModel next) {
  switch (next.transitionIn?.trim().toLowerCase()) {
    case 'fade':
      return _TransitionMode.fade;
    case 'black':
      return _TransitionMode.black;
    case 'cut':
      return _TransitionMode.cut;
    default:
      return _TransitionMode.flash;
  }
}

class DoubleBufferWidget extends StatefulWidget {
  final SlideModel        currentSlide;
  final List<SlideModel>  allSlides;
  final bool              touchEnabled;
  final int               iframePageIndex;
  final bool              overlayEnabled;
  final Duration          transitionDuration;

  /// Volumul 0.0–1.0 pentru slide-urile video (din Control, prin Firebase).
  final double            volume;

  const DoubleBufferWidget({
    required this.currentSlide,
    this.allSlides          = const [],
    required this.touchEnabled,
    this.iframePageIndex    = 0,
    this.overlayEnabled     = true,
    this.transitionDuration = const Duration(milliseconds: 700),
    this.volume             = 1.0,
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

  /// Ultimul slide cerut cât timp rula o tranziție — se aplică după ea.
  SlideModel? _pending;

  /// Tipul tranziției curente / ultimei tranziții.
  _TransitionMode _mode = _TransitionMode.flash;

  /// Care buffer este cel care INTRĂ (true = A) cât timp rulează tranziția,
  /// și dacă comutarea vizibilității a avut deja loc.
  bool? _incomingIsA;
  bool  _swapped = false;

  // ── Flash / sweep / black animation ───────────────────────────────────────
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

  /// Durata tranziției „black” (mai lentă decât flash-ul, ca să se simtă).
  static const Duration _blackDuration = Duration(milliseconds: 1000);

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

  SlideModel? get _visibleSlide => _aIsVisible ? _bufferA : _bufferB;

  @override
  void didUpdateWidget(DoubleBufferWidget old) {
    super.didUpdateWidget(old);
    final now = widget.currentSlide;

    // ── Alt slide ────────────────────────────────────────────────────────
    if (old.currentSlide.id != now.id) {
      if (_isTransiting) {
        _pending = now; // nu pierdem comanda: o aplicăm după tranziție
      } else {
        _doTransition(now);
      }
      return;
    }

    // ── Același slide, dar conținut modificat live în Firebase ───────────
    if (old.currentSlide != now && !_isTransiting) {
      setState(() {
        if (_aIsVisible) {
          _bufferA = now;
        } else {
          _bufferB = now;
        }
      });
    }
  }

  void _doTransition(SlideModel next) {
    _isTransiting = true;
    _mode         = _modeFor(next);
    _swapped      = false;
    _incomingIsA  = !_aIsVisible;

    final Duration total = switch (_mode) {
      _TransitionMode.black => _blackDuration,
      _TransitionMode.cut   => const Duration(milliseconds: 120),
      _                     => widget.transitionDuration,
    };
    final Duration swapAfter = switch (_mode) {
      _TransitionMode.black => Duration(milliseconds: total.inMilliseconds ~/ 2),
      _TransitionMode.cut   => Duration.zero,
      _                     => const Duration(milliseconds: 80),
    };

    _flashCtrl.duration = total;
    _flashCtrl.value    = 0.0;

    if (_mode == _TransitionMode.flash) {
      _flashColor    = _flashColors[_flashColorIdx % _flashColors.length];
      _flashColorIdx = (_flashColorIdx + 1) % _flashColors.length;
    }

    // Încarcă noul slide în buffer-ul inactiv
    setState(() {
      if (_aIsVisible) { _bufferB = next; } else { _bufferA = next; }
      _showFlash = _mode == _TransitionMode.flash ||
          _mode == _TransitionMode.black;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Comută vizibilitatea (crossfade / la mijlocul „negrului”)
      Future.delayed(swapAfter, () {
        if (!mounted) return;
        setState(() {
          _aIsVisible = !_aIsVisible;
          _swapped    = true;
        });
      });

      // Pornește animația overlay-ului
      _flashCtrl.forward(from: 0).then((_) {
        if (!mounted) return;
        setState(() {
          // Curăță buffer-ul invizibil
          if (_aIsVisible) { _bufferB = null; } else { _bufferA = null; }
          _showFlash    = false;
          _isTransiting = false;
          _incomingIsA  = null;
          _swapped      = false;
        });
        _afterTransition();
      });
    });
  }

  /// Apelată la sfârșitul fiecărei tranziții: aplică o comandă primită între
  /// timp sau reîmprospătează conținutul slide-ului vizibil.
  void _afterTransition() {
    final pending = _pending;
    _pending = null;
    final visible = _visibleSlide;

    if (pending != null && (visible == null || pending.id != visible.id)) {
      _doTransition(pending);
      return;
    }

    final latest = widget.currentSlide;
    if (visible != null && latest.id == visible.id && latest != visible) {
      setState(() {
        if (_aIsVisible) {
          _bufferA = latest;
        } else {
          _bufferB = latest;
        }
      });
    }
  }

  Set<int> get _activeBufferIds {
    final ids = <int>{};
    if (_bufferA != null) ids.add(_bufferA!.id);
    if (_bufferB != null) ids.add(_bufferB!.id);
    return ids;
  }

  // ── Stare per buffer (în timpul tranziției) ───────────────────────────────
  bool _isOutgoing(bool bufferIsA) =>
      _incomingIsA != null && _incomingIsA != bufferIsA;

  bool _isHeld(bool bufferIsA) => _incomingIsA == bufferIsA && !_swapped;

  /// Opacitatea overlay-ului negru la momentul t (0..1) al tranziției „black”:
  /// 0→1 (0–42%), negru complet (42–58%), 1→0 (58–100%).
  static double _blackOpacityAt(double t) {
    if (t < 0.42) return Curves.easeIn.transform(t / 0.42);
    if (t <= 0.58) return 1.0;
    return 1.0 - Curves.easeOut.transform((t - 0.58) / 0.42);
  }

  Widget _buffer(SlideModel? slide, bool isA) {
    if (slide == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: SlideRenderer(
        slide:            slide,
        touchEnabled:     widget.touchEnabled,
        iframePageIndex:  widget.iframePageIndex,
        overlayEnabled:   widget.overlayEnabled,
        volume:           _isOutgoing(isA) ? 0.0 : widget.volume,
        hold:             _isHeld(isA),
        publishHeartbeat: !_isOutgoing(isA),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIds     = _activeBufferIds;
    final preloadSlides = widget.allSlides
        .where((s) =>
            s.type == SlideType.iframe &&
            !s.isVideoSlide &&
            !activeIds.contains(s.id))
        .toList();

    // „black” și „cut” comută buffer-ele instantaneu (sub negru / fără efect).
    final Duration bufferFade =
        (_mode == _TransitionMode.black || _mode == _TransitionMode.cut)
            ? Duration.zero
            : widget.transitionDuration;

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
          duration: bufferFade,
          curve:    Curves.easeInOut,
          child:    _buffer(_bufferA, true),
        ),

        // ── Buffer B ──────────────────────────────────────────────────────────
        AnimatedOpacity(
          opacity:  _aIsVisible ? 0.0 : 1.0,
          duration: bufferFade,
          curve:    Curves.easeInOut,
          child:    _buffer(_bufferB, false),
        ),

        // ── Overlay: dâră de lumină (flash) sau negru (black) ─────────────────
        if (_showFlash)
          AnimatedBuilder(
            animation: _flashCtrl,
            builder: (_, __) {
              if (_mode == _TransitionMode.black) {
                return IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black
                        .withOpacity(_blackOpacityAt(_flashCtrl.value)),
                    child: const SizedBox.expand(),
                  ),
                );
              }
              return CustomPaint(
                painter: _SweepFlashPainter(
                  sweep:   _sweepAnim.value,
                  opacity: _flashOpacity.value,
                  color:   _flashColor,
                ),
                child: const SizedBox.expand(),
              );
            },
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
