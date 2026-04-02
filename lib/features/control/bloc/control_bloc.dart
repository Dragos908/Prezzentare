// lib/features/control/bloc/control_bloc.dart
//
// FIX: starea inițială din cachedState — UI-ul nu mai apare gol la start.

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/firebase_service.dart';
import '../../../core/model.dart';
import 'control_event.dart';

class _SlideIndexUpdated   extends ControlEvent { final int idx;                        _SlideIndexUpdated(this.idx); }
class _TouchUpdated        extends ControlEvent { final bool val;                       _TouchUpdated(this.val); }
class _VolumeUpdated       extends ControlEvent { final double vol;                     _VolumeUpdated(this.vol); }
class _SlidesUpdated       extends ControlEvent { final List<SlideModel> slides;        _SlidesUpdated(this.slides); }
class _TimerRunningUpdated extends ControlEvent { final bool running;                   _TimerRunningUpdated(this.running); }
class _TimerBaseUpdated    extends ControlEvent { final int base;                       _TimerBaseUpdated(this.base); }
class _TimerStartUpdated   extends ControlEvent { final int start;                      _TimerStartUpdated(this.start); }
class _SlideTimersUpdated  extends ControlEvent { final Map<int, SlideTimerData> slideTimers; _SlideTimersUpdated(this.slideTimers); }
class _IframePageUpdated   extends ControlEvent { final int page;                       _IframePageUpdated(this.page); }
class _OverlayUpdated      extends ControlEvent { final bool enabled;                   _OverlayUpdated(this.enabled); }
class _PointerUpdated      extends ControlEvent { final double x, y; final bool active; _PointerUpdated(this.x, this.y, this.active); }

class ControlBloc extends Bloc<ControlEvent, PresentationState> {
  final FirebaseService _fb;

  late final StreamSubscription<int>                      _indexSub;
  late final StreamSubscription<bool>                     _touchSub;
  late final StreamSubscription<double>                   _volumeSub;
  late final StreamSubscription<List<SlideModel>>         _slidesSub;
  late final StreamSubscription<bool>                     _timerRunningSub;
  late final StreamSubscription<int>                      _timerBaseSub;
  late final StreamSubscription<int>                      _timerStartSub;
  late final StreamSubscription<Map<int, SlideTimerData>> _slideTimersSub;
  late final StreamSubscription<int>                      _iframePageSub;
  late final StreamSubscription<bool>                     _overlaySub;
  late final StreamSubscription<Map<String, dynamic>>     _pointerSub;

  ControlBloc(this._fb) : super(_fb.cachedState ?? const PresentationState()) {

    on<_SlideIndexUpdated>  ((e, emit) => emit(state.copyWith(currentSlide: e.idx)));
    on<_TouchUpdated>       ((e, emit) => emit(state.copyWith(touchEnabled: e.val)));
    on<_VolumeUpdated>      ((e, emit) => emit(state.copyWith(volume: e.vol)));
    on<_SlidesUpdated>      ((e, emit) => emit(state.copyWith(slides: e.slides)));
    on<_TimerRunningUpdated>((e, emit) => emit(state.copyWith(timerRunning: e.running)));
    on<_TimerBaseUpdated>   ((e, emit) => emit(state.copyWith(timerBase: e.base)));
    on<_TimerStartUpdated>  ((e, emit) => emit(state.copyWith(timerStart: e.start)));
    on<_SlideTimersUpdated> ((e, emit) => emit(state.copyWith(slideTimers: e.slideTimers)));
    on<_IframePageUpdated>  ((e, emit) => emit(state.copyWith(iframePageIndex: e.page)));
    on<_OverlayUpdated>     ((e, emit) => emit(state.copyWith(overlayEnabled: e.enabled)));
    on<_PointerUpdated>     ((e, emit) => emit(state.copyWith(pointerX: e.x, pointerY: e.y, pointerActive: e.active)));

    on<NavigateEvent>        (_onNavigate);
    on<NavigateRelativeEvent>(_onNavigateRelative);
    on<GoToFirstEvent>       (_onGoToFirst);
    on<ToggleTouchEvent>     (_onToggleTouch);
    on<SetVolumeEvent>       (_onSetVolume);
    on<TimerToggleEvent>     (_onTimerToggle);
    on<TimerResetEvent>      (_onTimerReset);
    on<IframeNavigateEvent>  (_onIframeNavigate);
    on<IframeResetPageEvent> (_onIframeResetPage);
    on<ToggleOverlayEvent>   (_onToggleOverlay);
    on<SetPointerEvent>      (_onSetPointer);
    on<ClearPointerEvent>    (_onClearPointer);
    on<SetPointerClickEvent> (_onSetPointerClick);

    _indexSub        = _fb.currentSlideStream .listen((i) => add(_SlideIndexUpdated(i)));
    _touchSub        = _fb.touchEnabledStream .listen((v) => add(_TouchUpdated(v)));
    _volumeSub       = _fb.volumeStream       .listen((v) => add(_VolumeUpdated(v)));
    _slidesSub       = _fb.slidesStream       .listen((s) => add(_SlidesUpdated(s)));
    _timerRunningSub = _fb.timerRunningStream .listen((v) => add(_TimerRunningUpdated(v)));
    _timerBaseSub    = _fb.timerBaseStream    .listen((v) => add(_TimerBaseUpdated(v)));
    _timerStartSub   = _fb.timerStartStream   .listen((v) => add(_TimerStartUpdated(v)));
    _slideTimersSub  = _fb.slideTimersStream  .listen((m) => add(_SlideTimersUpdated(m)));
    _iframePageSub   = _fb.iframePageIndexStream.listen((p) => add(_IframePageUpdated(p)));
    _overlaySub      = _fb.overlayEnabledStream .listen((v) => add(_OverlayUpdated(v)));
    _pointerSub      = _fb.pointerStream.listen((m) {
      final x      = (m['x']      as num?)?.toDouble() ?? 0.5;
      final y      = (m['y']      as num?)?.toDouble() ?? 0.5;
      final active = m['active'] == true || m['active'] == 1;
      add(_PointerUpdated(x, y, active));
    });
  }

  Future<void> _onNavigate(NavigateEvent e, Emitter<PresentationState> emit) async {
    debugPrint('[Bloc] Navigate → ${e.idx}');
    if (state.slides.isEmpty) return;
    final idx = e.idx.clamp(0, state.slides.length - 1);
    await _fb.setCurrentSlide(idx, state.currentSlide);
  }

  Future<void> _onNavigateRelative(NavigateRelativeEvent e, Emitter<PresentationState> emit) async {
    if (state.slides.isEmpty) return;
    final next = e.forward
        ? (state.currentSlide + 1).clamp(0, state.slides.length - 1)
        : (state.currentSlide - 1).clamp(0, state.slides.length - 1);
    if (next == state.currentSlide) return;
    await _fb.setCurrentSlide(next, state.currentSlide);
  }

  Future<void> _onGoToFirst(GoToFirstEvent e, Emitter<PresentationState> emit) async {
    if (state.currentSlide == 0) return;
    await _fb.setCurrentSlide(0, state.currentSlide);
  }

  Future<void> _onToggleTouch(ToggleTouchEvent e, Emitter<PresentationState> emit) async =>
      _fb.setTouchEnabled(!state.touchEnabled);

  Future<void> _onSetVolume(SetVolumeEvent e, Emitter<PresentationState> emit) async =>
      _fb.setVolume(e.vol);

  Future<void> _onTimerToggle(TimerToggleEvent e, Emitter<PresentationState> emit) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!state.timerRunning) {
      await _fb.setTimerRunning(true);
      emit(state.copyWith(timerRunning: true, timerStart: now));
    } else {
      final elapsed = state.timerBase +
          (state.timerStart > 0 ? now - state.timerStart : 0);
      await _fb.setTimerRunning(false, base: elapsed);
      emit(state.copyWith(timerRunning: false, timerBase: elapsed));
    }
  }

  Future<void> _onTimerReset(TimerResetEvent e, Emitter<PresentationState> emit) async {
    await _fb.setTimerRunning(false, base: 0);
    emit(state.copyWith(timerRunning: false, timerBase: 0, timerStart: 0));
  }

  Future<void> _onIframeNavigate(IframeNavigateEvent e, Emitter<PresentationState> emit) async {
    final newPage = e.forward
        ? state.iframePageIndex + 1
        : (state.iframePageIndex - 1).clamp(0, 999);
    emit(state.copyWith(iframePageIndex: newPage));
    await _fb.setIframePageIndex(newPage);
  }

  Future<void> _onIframeResetPage(IframeResetPageEvent e, Emitter<PresentationState> emit) async {
    emit(state.copyWith(iframePageIndex: 0));
    await _fb.setIframePageIndex(0);
  }

  Future<void> _onToggleOverlay(ToggleOverlayEvent e, Emitter<PresentationState> emit) async =>
      _fb.setOverlayEnabled(!state.overlayEnabled);

  Future<void> _onSetPointer(SetPointerEvent e, Emitter<PresentationState> emit) async {
    emit(state.copyWith(pointerX: e.x, pointerY: e.y, pointerActive: true));
    await _fb.setPointer(e.x, e.y);
  }

  Future<void> _onClearPointer(ClearPointerEvent e, Emitter<PresentationState> emit) async {
    emit(state.copyWith(pointerActive: false));
    await _fb.clearPointer();
  }

  Future<void> _onSetPointerClick(SetPointerClickEvent e, Emitter<PresentationState> emit) async =>
      _fb.setPointerClick(e.x, e.y);

  @override
  Future<void> close() {
    _indexSub.cancel();
    _touchSub.cancel();
    _volumeSub.cancel();
    _slidesSub.cancel();
    _timerRunningSub.cancel();
    _timerBaseSub.cancel();
    _timerStartSub.cancel();
    _slideTimersSub.cancel();
    _iframePageSub.cancel();
    _overlaySub.cancel();
    _pointerSub.cancel();
    return super.close();
  }
}