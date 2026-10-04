// lib/core/theme/app_tokens.dart
//
// Tokeni de design (culori, spațiere, raze, tipografie) ca ThemeExtension, plus
// widgeturi reutilizabile pentru pagina de control și pagina de Setări.
// Tema închisă e implicită (săli întunecate); culorile pornesc din identitatea
// aplicației (violet + turcoaz). Un widget fără extensia instalată (ex. în teste)
// folosește AppTokens.dark.

import 'package:flutter/material.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color accent;
  final Color accent2;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textHi;
  final Color textMid;
  final Color textLo;

  // spațiere
  final double sp1;
  final double sp2;
  final double sp3;
  final double sp4;
  final double sp5;
  final double sp6;

  // raze
  final double rSm;
  final double rMd;
  final double rLg;

  const AppTokens({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.accent,
    required this.accent2,
    required this.success,
    required this.warning,
    required this.danger,
    required this.textHi,
    required this.textMid,
    required this.textLo,
    this.sp1 = 4,
    this.sp2 = 8,
    this.sp3 = 12,
    this.sp4 = 16,
    this.sp5 = 24,
    this.sp6 = 32,
    this.rSm = 8,
    this.rMd = 14,
    this.rLg = 20,
  });

  static const AppTokens dark = AppTokens(
    bg: Color(0xFF0A0A12),
    surface: Color(0xFF12121F),
    surfaceHigh: Color(0xFF1A1A2C),
    border: Color(0xFF2A2A40),
    accent: Color(0xFF6C63FF),
    accent2: Color(0xFF00D9A3),
    success: Color(0xFF2ECC71),
    warning: Color(0xFFFFB020),
    danger: Color(0xFFFF5468),
    textHi: Color(0xFFF5F4FF),
    textMid: Color(0xFFB9B8D6),
    textLo: Color(0xFF7B7A99),
  );

  // tipografie
  TextStyle get title => TextStyle(
      color: textHi, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2);
  TextStyle get label =>
      TextStyle(color: textMid, fontSize: 13, fontWeight: FontWeight.w500);
  TextStyle get body => TextStyle(color: textHi, fontSize: 14, height: 1.3);
  TextStyle get caption => TextStyle(color: textLo, fontSize: 12);

  @override
  AppTokens copyWith({Color? accent, Color? accent2}) => AppTokens(
        bg: bg,
        surface: surface,
        surfaceHigh: surfaceHigh,
        border: border,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        success: success,
        warning: warning,
        danger: danger,
        textHi: textHi,
        textMid: textMid,
        textLo: textLo,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) => this;
}

extension AppTokensContext on BuildContext {
  AppTokens get tk => Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgeturi reutilizabile
// ─────────────────────────────────────────────────────────────────────────────

/// Card cu titlu opțional — blocul de bază al paginilor.
class AppCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.padding,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.rMd),
        border: Border.all(color: t.border),
      ),
      padding: padding ?? EdgeInsets.all(t.sp4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: t.accent2),
                  SizedBox(width: t.sp2),
                ],
                Expanded(child: Text(title!, style: t.title.copyWith(fontSize: 16))),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: t.sp3),
          ],
          child,
        ],
      ),
    );
  }
}

/// Buton-icon mare (≥ 48×48 dp), cu stare activă, tooltip și Semantics.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.color,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final c = color ?? t.accent2;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? c.withOpacity(0.22) : t.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.rSm + 2),
            side: BorderSide(color: active ? c : t.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.rSm + 2),
            onTap: onPressed,
            focusColor: c.withOpacity(0.25),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon,
                  size: size * 0.5,
                  color: enabled ? (active ? c : t.textHi) : t.textLo),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilă de stare (conexiune, sincronizare, sunet).
class StatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final String? tooltip;

  const StatusPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Semantics(
      label: text,
      child: tooltip == null ? pill : Tooltip(message: tooltip!, child: pill),
    );
  }
}

/// Formatează milisecunde ca m:ss (nume distinct de funcția deja existentă în control).
String formatClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
