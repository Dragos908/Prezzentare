// lib/features/control/bloc/control_event.dart

abstract class ControlEvent {}

/// Navighează la un slide anume (index direct).
class NavigateEvent extends ControlEvent {
  final int idx;
  NavigateEvent(this.idx);
}

/// Navighează relativ: +1 (forward=true) sau -1.
class NavigateRelativeEvent extends ControlEvent {
  final bool forward;
  NavigateRelativeEvent(this.forward);
}

/// Salt la primul slide.
class GoToFirstEvent extends ControlEvent {}

/// Activează / dezactivează atingerea pe tablă.
class ToggleTouchEvent extends ControlEvent {}

/// Setează volumul (0.0 – 1.0).
class SetVolumeEvent extends ControlEvent {
  final double vol;
  SetVolumeEvent(this.vol);
}

/// Pornește sau oprește cronometrul general.
class TimerToggleEvent extends ControlEvent {}

/// Resetează cronometrul general.
class TimerResetEvent extends ControlEvent {}

// ── Navigare iframe (sub-slides: Canva, Google Slides etc.) ──────────────────

/// Avansează sau retrocedează un sub-slide în iframe-ul curent.
class IframeNavigateEvent extends ControlEvent {
  final bool forward;
  IframeNavigateEvent(this.forward);
}

/// Resetează sub-slide-ul iframe la 0 (prima pagină).
class IframeResetPageEvent extends ControlEvent {}

// ── Overlay navigare iframe ───────────────────────────────────────────────────

/// Activează / dezactivează overlay-ul de navigare pe iframe.
/// Când este dezactivat, iframe-ul devine complet interactiv
/// (util pentru a reda un video pe proiector fără overlay).
class ToggleOverlayEvent extends ControlEvent {}

// ── Pointer laser ─────────────────────────────────────────────────────────────

/// Trimite poziția pointer-ului pe Display (coordonate normalizate 0.0–1.0).
class SetPointerEvent extends ControlEvent {
  final double x;
  final double y;
  SetPointerEvent(this.x, this.y);
}

/// Ascunde pointer-ul de pe Display.
class ClearPointerEvent extends ControlEvent {}

/// Trimite un click real la coordonatele normalizate 0.0–1.0 pe Display.
/// Mod CLICK — diferit de LASER care doar afișează dot-ul.
class SetPointerClickEvent extends ControlEvent {
  final double x;
  final double y;
  SetPointerClickEvent(this.x, this.y);
}