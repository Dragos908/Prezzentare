// lib/features/display/bloc/display_event.dart

import '../../../core/model.dart';

abstract class DisplayEvent {}

class SlideChangedEvent extends DisplayEvent {
  final int idx;
  SlideChangedEvent(this.idx);
}

class TouchEnabledChangedEvent extends DisplayEvent {
  final bool val;
  TouchEnabledChangedEvent(this.val);
}

class SlidesLoadedEvent extends DisplayEvent {
  final List<SlideModel> slides;
  SlidesLoadedEvent(this.slides);
}

/// Emis intern după ce tranziția s-a terminat (înlocuiește Future.delayed + emit).
class TransitionDoneEvent extends DisplayEvent {}

/// Toggle touch direct de pe ecranul Display.
class ToggleTouchDisplayEvent extends DisplayEvent {}

/// Eveniment produs de atingerea tablei (stânga / dreapta).
class NavigateTapEvent extends DisplayEvent {
  final bool forward;
  NavigateTapEvent(this.forward);
}

/// Eveniment produs de tastele ← → Spațiu.
class NavigateKeyEvent extends DisplayEvent {
  final bool forward;
  NavigateKeyEvent(this.forward);
}