// lib/features/display/widgets/slide_announce_widget.dart
//
// ── PANOUL DE ANUNȚ ──────────────────────────────────────────────────────────
// Ecranul „Telefoanele pe silențios” afișat publicului înainte / în timpul
// prezentării. Gândit pentru citit de la distanță, pe proiector sau tablă:
//
//   • un singur simbol mare (telefonul cu clopoțelul barat) — se înțelege
//     dintr-o privire, fără să citești nimic;
//   • titlu clar + o frază de rugăminte + regulile pe rânduri scurte;
//   • iconițe vectoriale (Material) — NU emoji: emoji-urile depind de un font
//     descărcat din rețea și pe unele calculatoare apăreau ca pătrățele goale;
//   • culorile aplicației (violet + turcoaz); roșul apare o singură dată,
//     exclusiv la bara de interdicție de pe telefon;
//   • layout pe o pânză fixă 16:9 (1280×720) scalată uniform → arată identic pe
//     orice rezoluție (720p … 4K), fără text tăiat sau depășiri.
//
// ── Date din Firebase (toate opționale) ──────────────────────────────────────
//   heading  → titlul mare            (implicit: „Pentru o vizionare plăcută”)
//   subtitle → fraza de sub titlu     (implicit: „Vă rugăm să evitați …”)
//   rules    → lista de reguli (max. 5 rânduri afișate); iconița fiecărui
//              rând se alege singură după cuvintele din text.
//
// ── Miniaturi ────────────────────────────────────────────────────────────────
// `animate: false` afișează direct starea finală, fără animații. Panoul de
// Control folosește exact acest widget pentru previzualizare, deci miniatura
// este identică cu ce vede publicul (o singură sursă de adevăr).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/model.dart';

// ── Paletă (aceeași familie cu restul aplicației) ────────────────────────────
const Color _kInkTop    = Color(0xFF15144A);
const Color _kInkMid    = Color(0xFF0B0B26);
const Color _kInkBottom = Color(0xFF060616);
const Color _kViolet    = Color(0xFF6C63FF);
const Color _kTeal      = Color(0xFF00D9A3);
const Color _kSignal    = Color(0xFFFF5468); // DOAR bara de interdicție
const Color _kText      = Color(0xFFF5F4FF);

// ── Pânza de proiectare ──────────────────────────────────────────────────────
const double _kCanvasW = 1280;
const double _kCanvasH = 720;

// ── Texte implicite ──────────────────────────────────────────────────────────
const String _kDefaultHeading  = 'Pentru o vizionare plăcută';
const String _kDefaultSubtitle = 'Vă rugăm să evitați folosirea telefoanelor';
const List<String> _kDefaultRules = [
  'Telefonul oprit sau pe silențios',
  'Liniște în timpul prezentării',
  'Fotografii permise, fără bliț',
  'Intrări și ieșiri discrete, între lucrări',
];

class SlideAnnounceWidget extends StatefulWidget {
  final SlideModel slide;

  /// false → afișează direct starea finală, fără animații (miniaturi).
  final bool animate;

  const SlideAnnounceWidget({
    required this.slide,
    this.animate = true,
    super.key,
  });

  @override
  State<SlideAnnounceWidget> createState() => _SlideAnnounceWidgetState();
}

class _SlideAnnounceWidgetState extends State<SlideAnnounceWidget>
    with TickerProviderStateMixin {
  /// Secvența de intrare (rulează o singură dată, ~2,6 s).
  late final AnimationController _intro;

  /// Deriva lentă a luminii de fundal (buclă de 20 s, fără salt la reluare).
  late final AnimationController _ambient;

  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animate && !reduceMotion) {
      _intro.forward();
      _ambient.repeat();
    } else {
      _intro.value   = 1.0; // starea finală
      _ambient.value = 0.25;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  static String _clean(String? v, String fallback) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final slide    = widget.slide;
    final heading  = _clean(slide.heading, _kDefaultHeading);
    final subtitle = _clean(slide.subtitle, _kDefaultSubtitle);
    final rules    = (slide.rules != null && slide.rules!.isNotEmpty)
        ? slide.rules!.take(5).toList()
        : _kDefaultRules;

    return ColoredBox(
      color: _kInkBottom,
      child: Stack(
        fit: StackFit.expand,
        children: [

          // ── Fundal: gradient indigo + lumini violet / turcoaz care derivă ──
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ambient,
              builder: (_, __) => CustomPaint(
                painter: _BackdropPainter(t: _ambient.value * 2 * math.pi),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ── Conținut: pânză 16:9 scalată uniform ──────────────────────────
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _kCanvasW,
                height: _kCanvasH,
                child: _AnnounceCanvas(
                  t:        _intro,
                  heading:  heading,
                  subtitle: subtitle,
                  rules:    rules,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pânza 1280×720: coloana de text (stânga) + simbolul mare (dreapta)
// ─────────────────────────────────────────────────────────────────────────────
class _AnnounceCanvas extends StatelessWidget {
  final Animation<double> t;
  final String            heading;
  final String            subtitle;
  final List<String>      rules;

  const _AnnounceCanvas({
    required this.t,
    required this.heading,
    required this.subtitle,
    required this.rules,
  });

  static const double _textW = 600;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 88, vertical: 64),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Dacă textul din baza de date e foarte lung, se micșorează uniform
          // (nu iese niciodată din ecran).
          SizedBox(
            width: _textW,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: _textW,
                child: _TextColumn(
                  t:        t,
                  heading:  heading,
                  subtitle: subtitle,
                  rules:    rules,
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 480,
            height: 480,
            child: _SilenceHero(t: t),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coloana de text
// ─────────────────────────────────────────────────────────────────────────────
class _TextColumn extends StatelessWidget {
  final Animation<double> t;
  final String            heading;
  final String            subtitle;
  final List<String>      rules;

  const _TextColumn({
    required this.t,
    required this.heading,
    required this.subtitle,
    required this.rules,
  });

  static const TextStyle _headingStyle = TextStyle(
    color:         _kText,
    fontSize:      66,
    fontWeight:    FontWeight.w700,
    letterSpacing: -1.6,
    height:        1.05,
  );

  static const TextStyle _subtitleStyle = TextStyle(
    color:         Color(0xC7F5F4FF), // ~78 %
    fontSize:      28,
    fontWeight:    FontWeight.w400,
    letterSpacing: 0.1,
    height:        1.35,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Reveal(
          t: t, from: 0.02, to: 0.32, dy: 18,
          child: Text(heading, maxLines: 4, overflow: TextOverflow.ellipsis, style: _headingStyle),
        ),
        const SizedBox(height: 18),
        _Reveal(
          t: t, from: 0.10, to: 0.38, dy: 14,
          child: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: _subtitleStyle),
        ),
        const SizedBox(height: 36),
        for (var i = 0; i < rules.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _Reveal(
            t: t,
            from: 0.24 + i * 0.07,
            to:   0.48 + i * 0.07,
            dx: 22,
            child: _RuleRow(text: rules[i]),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Un rând de regulă: iconiță vectorială + text
// ─────────────────────────────────────────────────────────────────────────────
class _RuleRow extends StatelessWidget {
  final String text;
  const _RuleRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width:  54,
          height: 54,
          decoration: BoxDecoration(
            color:        _kTeal.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kTeal.withOpacity(0.34), width: 1.2),
          ),
          child: Center(
            child: Icon(_iconFor(text), size: 29, color: _kTeal),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color:         _kText,
              fontSize:      26,
              fontWeight:    FontWeight.w500,
              letterSpacing: 0.1,
              height:        1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Alege iconița după cuvintele din regulă (fără diacritice, litere mici).
IconData _iconFor(String text) {
  final s = _fold(text);
  if (s.contains('blit') || s.contains('flash')) return Icons.flash_off_rounded;
  if (s.contains('foto') || s.contains('film') || s.contains('camera')) {
    return Icons.photo_camera_rounded;
  }
  if (s.contains('linist') || s.contains('tacer') ||
      s.contains('zgomot') || s.contains('vorb')) {
    return Icons.mic_off_rounded;
  }
  if (s.contains('telefon') || s.contains('mobil') || s.contains('silent')) {
    return Icons.notifications_off_rounded;
  }
  if (s.contains('intreb') || s.contains('discut')) {
    return Icons.chat_bubble_outline_rounded;
  }
  if (s.contains('intrar') || s.contains('iesir') ||
      s.contains('usa') || s.contains('sala')) {
    return Icons.meeting_room_rounded;
  }
  return Icons.check_circle_outline_rounded;
}

String _fold(String input) {
  const map = {
    'ă': 'a', 'â': 'a', 'î': 'i',
    'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't',
  };
  var out = input.toLowerCase();
  map.forEach((from, to) {
    out = out.replaceAll(from, to);
  });
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Apariție cu fade + deplasare, într-un interval din secvența de intrare
// ─────────────────────────────────────────────────────────────────────────────
class _Reveal extends StatelessWidget {
  final Animation<double> t;
  final double from;
  final double to;
  final double dx;
  final double dy;
  final Widget child;

  const _Reveal({
    required this.t,
    required this.from,
    required this.to,
    this.dx = 0,
    this.dy = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (_, c) {
        final p = Curves.easeOutCubic
            .transform(((t.value - from) / (to - from)).clamp(0.0, 1.0));
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset((1 - p) * dx, (1 - p) * dy),
            child: c,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simbolul mare: telefonul „sună”, undele se sting, clopoțelul e barat
// ─────────────────────────────────────────────────────────────────────────────
class _SilenceHero extends StatelessWidget {
  final Animation<double> t;
  const _SilenceHero({required this.t});

  static double _seg(double v, double a, double b, Curve curve) =>
      curve.transform(((v - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (_, __) {
        final v      = t.value;
        final appear = _seg(v, 0.00, 0.20, Curves.easeOutCubic);
        final wave   = _seg(v, 0.14, 0.60, Curves.linear);
        final slash  = _seg(v, 0.58, 0.80, Curves.easeInOutCubic);
        return CustomPaint(
          painter: _SilencePainter(appear: appear, wave: wave, slash: slash),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _SilencePainter extends CustomPainter {
  final double appear; // 0..1 — telefonul apare
  final double wave;   // 0..1 — undele sună (2 pulsuri), apoi se sting
  final double slash;  // 0..1 — bara de interdicție se trasează

  const _SilencePainter({
    required this.appear,
    required this.wave,
    required this.slash,
  });

  static const double _box = 400;
  static const Offset _c = Offset(200, 200);
  static const Offset _slashA = Offset(94, 62);
  static const Offset _slashB = Offset(306, 338);

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0) return;

    canvas.save();
    canvas.scale(size.width / _box, size.height / _box);

    // 1) Halou violet în spatele telefonului
    const glowR = 190.0;
    canvas.drawCircle(
      _c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _kViolet.withOpacity(0.40 * appear),
            _kViolet.withOpacity(0.0),
          ],
        ).createShader(Rect.fromCircle(center: _c, radius: glowR)),
    );

    // 2) Undele sonore
    _paintWaves(canvas);

    // 3) Telefon + clopoțel, într-un strat separat, ca bara să poată
    //    „decupa” un mic gol în contur (efect de bară „pusă peste”).
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, _box, _box),
      Paint()..color = Color.fromRGBO(255, 255, 255, appear.clamp(0.0, 1.0)),
    );

    canvas.save();
    final sc = 0.94 + 0.06 * appear;
    canvas.translate(_c.dx, _c.dy);
    canvas.scale(sc);
    canvas.translate(-_c.dx, -_c.dy);
    _paintPhone(canvas);
    _paintBell(canvas);
    canvas.restore();

    if (slash > 0) {
      canvas.drawLine(
        _slashA,
        Offset.lerp(_slashA, _slashB, slash)!,
        Paint()
          ..blendMode   = BlendMode.clear
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 30
          ..strokeCap   = StrokeCap.round,
      );
    }
    canvas.restore(); // layer

    // 4) Bara de interdicție (singurul loc unde apare roșul)
    if (slash > 0) {
      final end = Offset.lerp(_slashA, _slashB, slash)!;
      canvas.drawLine(
        _slashA,
        end,
        Paint()
          ..color       = _kSignal.withOpacity(0.35 * appear)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 26
          ..strokeCap   = StrokeCap.round
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawLine(
        _slashA,
        end,
        Paint()
          ..color       = _kSignal
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap   = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  // ── Unde: 3 arce pe fiecare parte, 2 pulsuri, apoi dispar ─────────────────
  void _paintWaves(Canvas canvas) {
    const bases = [0.95, 0.70, 0.45];
    const sweep = 0.60; // ~34°
    for (var i = 0; i < 3; i++) {
      final ph = (wave - i * 0.09) / 0.82;
      if (ph <= 0 || ph >= 1) continue;
      final pulse = 0.5 - 0.5 * math.cos(ph * 2 * math.pi * 2); // 2 pulsuri
      final a = (bases[i] * pulse).clamp(0.0, 1.0);
      if (a < 0.02) continue;

      final r = 116.0 + 28.0 * i + 8.0 * ph;
      final rect = Rect.fromCircle(center: _c, radius: r);
      final p = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap   = StrokeCap.round
        ..color       = _kTeal.withOpacity(a);
      canvas.drawArc(rect, -sweep, 2 * sweep, false, p);            // dreapta
      canvas.drawArc(rect, math.pi - sweep, 2 * sweep, false, p);   // stânga
    }
  }

  void _paintPhone(Canvas canvas) {
    final body   = RRect.fromLTRBR(116, 56, 284, 344, const Radius.circular(36));
    final screen = RRect.fromLTRBR(130, 72, 270, 328, const Radius.circular(24));

    // corp
    canvas.drawRRect(body, Paint()..color = const Color(0xFF0E0E2C));

    // ecran — se stinge treptat pe măsură ce bara se trasează
    final dim = 1.0 - 0.38 * slash;
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [
            _kViolet.withOpacity(0.62 * dim),
            _kTeal.withOpacity(0.34 * dim),
          ],
        ).createShader(screen.outerRect),
    );

    // contur
    canvas.drawRRect(
      body,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color       = _kText.withOpacity(0.96),
    );

    // difuzor + bara de jos
    canvas.drawRRect(
      RRect.fromLTRBR(178, 61, 222, 67, const Radius.circular(3)),
      Paint()..color = _kText.withOpacity(0.45),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(172, 314, 228, 320, const Radius.circular(3)),
      Paint()..color = _kText.withOpacity(0.45),
    );
  }

  void _paintBell(Canvas canvas) {
    // Clopoțel desenat ca traseu (nu icon-font), ca să poată fi decupat de bară.
    final bell = Path()
      ..moveTo(-44, 30)
      ..lineTo(-36, 22)
      ..lineTo(-36, -6)
      ..cubicTo(-36, -34, -20, -46, 0, -46)
      ..cubicTo(20, -46, 36, -34, 36, -6)
      ..lineTo(36, 22)
      ..lineTo(44, 30)
      ..close()
      ..addArc(Rect.fromCircle(center: const Offset(0, 38), radius: 11), 0, math.pi)
      ..addOval(Rect.fromCircle(center: const Offset(0, -52), radius: 6));

    // Se clatină cât „sună”, apoi rămâne nemișcat.
    final shake = (wave > 0 && wave < 1)
        ? 0.20 * math.sin(wave * 2 * math.pi * 5) * (1 - wave)
        : 0.0;

    canvas.save();
    canvas.translate(200, 204);
    canvas.translate(0, -52);
    canvas.rotate(shake);
    canvas.translate(0, 52);
    canvas.drawPath(bell, Paint()..color = _kText.withOpacity(0.97));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SilencePainter old) =>
      old.appear != appear || old.wave != wave || old.slash != slash;
}

// ─────────────────────────────────────────────────────────────────────────────
// Fundal: gradient indigo + 2 lumini (violet sus-stânga, turcoaz jos-dreapta)
// Funcții cu multipli ÎNTREGI ai lui t → bucla de 20 s se reia fără salt.
// ─────────────────────────────────────────────────────────────────────────────
class _BackdropPainter extends CustomPainter {
  final double t; // 0..2π
  const _BackdropPainter({required this.t});

  @override
  void paint(Canvas canvas, Size sz) {
    final rect = Offset.zero & sz;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [_kInkTop, _kInkMid, _kInkBottom],
          stops:  [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    final p1 = Offset(
      sz.width  * (0.12 + 0.04 * math.sin(t)),
      sz.height * (0.10 + 0.05 * math.cos(t)),
    );
    _glow(canvas, p1, sz.shortestSide * 0.90, _kViolet.withOpacity(0.30));

    final p2 = Offset(
      sz.width  * (0.90 + 0.03 * math.cos(t)),
      sz.height * (0.96 + 0.03 * math.sin(2 * t)),
    );
    _glow(canvas, p2, sz.shortestSide * 0.75, _kTeal.withOpacity(0.15));
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}
