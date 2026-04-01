// lib/features/control/control_page.dart
//
// ── SHORTCUTS TASTATURĂ ──────────────────────────────────────────────────────
//  → / Space / PageDown   — slide următor
//  ←  / PageUp            — slide anterior
//  Home                   — primul slide
//  End                    — ultimul slide
//  T                      — toggle Touch
//  O                      — toggle Overlay navigare iframe
//  P / Enter              — Play/Pause cronometru
//  R                      — Reset cronometru
//  Shift + →              — pagina următoare în iframe (Canva / Google Slides)
//  Shift + ←              — pagina anterioară în iframe
//  Shift + Home           — prima pagină în iframe (reset)
// ─────────────────────────────────────────────────────────────────────────────
//
// FIX: adăugat parametrul `isBroadcast` + badge vizual în AppBar când
//       toate proiectele sunt controlate simultan.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/model.dart';
import '../../core/firebase_service.dart';
import 'bloc/control_bloc.dart';
import 'bloc/control_event.dart';
import 'widgets/slide_panels.dart';
import 'widgets/navigation_panel.dart';
import 'widgets/control_widgets.dart';

class ControlPage extends StatelessWidget {
  /// True → comenzile merg la TOATE proiectele (broadcast mode).
  final bool isBroadcast;

  const ControlPage({this.isBroadcast = false, super.key});

  @override
  Widget build(BuildContext context) {
    return _ControlView(isBroadcast: isBroadcast);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ControlView
// ─────────────────────────────────────────────────────────────────────────────
class _ControlView extends StatefulWidget {
  final bool isBroadcast;
  const _ControlView({required this.isBroadcast});

  @override
  State<_ControlView> createState() => _ControlViewState();
}

class _ControlViewState extends State<_ControlView> {
  final _focusNode = FocusNode();
  bool _pointerMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(
      KeyEvent event, ControlBloc bloc, PresentationState state) {
    if (event is! KeyDownEvent) return;

    final key     = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isIframe = state.slides.isNotEmpty &&
        state.slides[state.currentSlide.clamp(0, state.slides.length - 1)]
            .type ==
            SlideType.iframe;

    if (isShift) {
      if (key == LogicalKeyboardKey.arrowRight) {
        if (isIframe) bloc.add(IframeNavigateEvent(true));
        return;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (isIframe) bloc.add(IframeNavigateEvent(false));
        return;
      }
      if (key == LogicalKeyboardKey.home) {
        if (isIframe) bloc.add(IframeResetPageEvent());
        return;
      }
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      bloc.add(NavigateRelativeEvent(true));
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      bloc.add(NavigateRelativeEvent(false));
    } else if (key == LogicalKeyboardKey.home) {
      bloc.add(GoToFirstEvent());
    } else if (key == LogicalKeyboardKey.end) {
      if (state.slides.isNotEmpty) {
        bloc.add(NavigateEvent(state.slides.length - 1));
      }
    } else if (key == LogicalKeyboardKey.keyT) {
      bloc.add(ToggleTouchEvent());
    } else if (key == LogicalKeyboardKey.keyO) {
      bloc.add(ToggleOverlayEvent());
    } else if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.enter) {
      bloc.add(TimerToggleEvent());
    } else if (key == LogicalKeyboardKey.keyR) {
      bloc.add(TimerResetEvent());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc = context.read<ControlBloc>();

        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (e) => _handleKey(e, bloc, state),
          child: Scaffold(
            backgroundColor: const Color(0xFF07070f),
            appBar: _ControlAppBar(
              state:           state,
              bloc:            bloc,
              isBroadcast:     widget.isBroadcast,
              pointerMode:     _pointerMode,
              onTogglePointer: () {
                if (_pointerMode) bloc.add(ClearPointerEvent());
                setState(() => _pointerMode = !_pointerMode);
              },
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 320,
                      child: SlideMonitorPanel(),
                    ),
                    Expanded(child: _CenterPanel(isBroadcast: widget.isBroadcast)),
                    const SizedBox(
                      width: 220,
                      child: SlideListPanel(),
                    ),
                  ],
                ),
                if (_pointerMode)
                  _PointerScreen(
                    bloc:   bloc,
                    onExit: () {
                      bloc.add(ClearPointerEvent());
                      setState(() => _pointerMode = false);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar
// ─────────────────────────────────────────────────────────────────────────────
class _ControlAppBar extends StatelessWidget implements PreferredSizeWidget {
  final PresentationState state;
  final ControlBloc       bloc;
  final bool              isBroadcast;
  final bool              pointerMode;
  final VoidCallback      onTogglePointer;

  const _ControlAppBar({
    required this.state,
    required this.bloc,
    required this.isBroadcast,
    required this.pointerMode,
    required this.onTogglePointer,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final isIframe = state.slides.isNotEmpty &&
        state.slides[state.currentSlide.clamp(0, state.slides.length - 1)]
            .type ==
            SlideType.iframe;

    return AppBar(
      backgroundColor: isBroadcast
          ? const Color(0xFF1a1200)   // fundal galben-închis în broadcast mode
          : const Color(0xFF0b0b16),
      elevation: 0,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // ── Badge BROADCAST (vizibil când controlăm toate proiectele) ──
            if (isBroadcast) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFFBE21).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFBE21).withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.broadcast_on_personal,
                      size: 12, color: Color(0xFFFFBE21),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'BROADCAST — ${FirebaseService.kAllProjects.length} PROIECTE',
                      style: const TextStyle(
                        color:         Color(0xFFFFBE21),
                        fontSize:      10,
                        fontWeight:    FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ] else ...[
              Text(
                'CONTROL — ${FirebaseService.instance.currentProject.toUpperCase()}',
                style: const TextStyle(
                  color:         Colors.white,
                  fontSize:      13,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(width: 20),
            ],

            _ShortcutBadge('← →', 'slide'),
            const SizedBox(width: 8),
            _ShortcutBadge('T', 'touch'),
            const SizedBox(width: 8),
            _ShortcutBadge('O', 'overlay'),
            const SizedBox(width: 8),
            _ShortcutBadge('P', 'timer'),
            const SizedBox(width: 8),
            _ShortcutBadge('R', 'reset'),
            if (isIframe) ...[
              const SizedBox(width: 8),
              _ShortcutBadge('⇧ ← →', 'iframe'),
            ],
            const Spacer(),

            // ── Buton Pointer Laser ──────────────────────────────────────
            GestureDetector(
              onTap: onTogglePointer,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: pointerMode
                      ? const Color(0xFFFF2244).withOpacity(0.2)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: pointerMode
                        ? const Color(0xFFFF2244).withOpacity(0.6)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pointerMode
                          ? Icons.spatial_tracking
                          : Icons.spatial_tracking_outlined,
                      size:  14,
                      color: pointerMode
                          ? const Color(0xFFFF2244)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pointerMode ? 'POINTER ON' : 'POINTER',
                      style: TextStyle(
                        color: pointerMode
                            ? const Color(0xFFFF2244)
                            : Colors.white38,
                        fontSize:      10,
                        fontWeight:    FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (isIframe) ...[
              _IframePageBadge(
                pageIndex: state.iframePageIndex,
                onPrev: () => bloc.add(IframeNavigateEvent(false)),
                onNext: () => bloc.add(IframeNavigateEvent(true)),
              ),
              const SizedBox(width: 12),
            ],
            GestureDetector(
              onTap: () => bloc.add(TimerToggleEvent()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: state.timerRunning
                      ? const Color(0xFF6C63FF).withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: state.timerRunning
                        ? const Color(0xFF6C63FF).withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.timerRunning) ...[
                      _PulseDot(),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      formatMs(state.timerTotalMs),
                      style: TextStyle(
                        color:         state.timerRunning
                            ? Colors.white
                            : Colors.white38,
                        fontSize:      15,
                        fontFamily:    'monospace',
                        fontWeight:    FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StatusDot(label: 'Firebase', active: true),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isBroadcast
              ? const Color(0xFFFFBE21).withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
        ),
      ),
    );
  }
}

class _IframePageBadge extends StatelessWidget {
  final int          pageIndex;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _IframePageBadge({
    required this.pageIndex,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF00D9A3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: pageIndex > 0 ? onPrev : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: pageIndex > 0
                  ? color.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(6)),
              border: Border.all(
                  color: color.withOpacity(pageIndex > 0 ? 0.4 : 0.15)),
            ),
            child: Icon(
              Icons.chevron_left,
              size:  14,
              color: pageIndex > 0 ? color : color.withOpacity(0.25),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:  color.withOpacity(0.1),
            border: Border.symmetric(
              horizontal: BorderSide(color: color.withOpacity(0.4)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.web_outlined, size: 10, color: color),
              const SizedBox(width: 5),
              Text(
                'Pag. ${pageIndex + 1}',
                style: const TextStyle(
                  color:      color,
                  fontSize:   11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onNext,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(6)),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: const Icon(Icons.chevron_right, size: 14, color: color),
          ),
        ),
      ],
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  final String key_;
  final String label;
  const _ShortcutBadge(this.key_, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Text(
            key_,
            style: const TextStyle(
              color:      Colors.white54,
              fontSize:   9,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color:         Colors.white.withOpacity(0.2),
            fontSize:      9,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final bool   active;
  const _StatusDot({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF00D9A3) : Colors.redAccent,
            boxShadow: active
                ? [BoxShadow(
                color:      const Color(0xFF00D9A3).withOpacity(0.5),
                blurRadius: 6)]
                : [],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.3), fontSize: 10),
        ),
      ],
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.4 + 0.6 * _ctrl.value,
        child: Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF6C63FF),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panoul central
// ─────────────────────────────────────────────────────────────────────────────
class _CenterPanel extends StatelessWidget {
  final bool isBroadcast;
  const _CenterPanel({required this.isBroadcast});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left:  BorderSide(color: Colors.white.withOpacity(0.05)),
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Banner broadcast (dacă e activ) ─────────────────────────────
          if (isBroadcast)
            _BroadcastBanner(),

          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                    icon: Icons.navigation_outlined, label: 'NAVIGARE'),
                const Expanded(child: NavigationPanel()),
              ],
            ),
          ),

          _Separator(),

          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionHeader(
                      icon: Icons.timer_outlined, label: 'CRONOMETRE'),
                  const TimerPanel(),

                  _Separator(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                            icon: Icons.touch_app_outlined,
                            label: 'TABLĂ INTERACTIVĂ'),
                        const SizedBox(height: 8),
                        const TouchToggleWidget(),
                        const SizedBox(height: 8),
                        const OverlayToggleWidget(),
                        const SizedBox(height: 8),
                        const VolumeControlWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner vizibil în modul broadcast
class _BroadcastBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFFBE21);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: color.withOpacity(0.07),
      child: Row(
        children: [
          const Icon(Icons.broadcast_on_personal, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MOD BROADCAST — Comenzile se transmit simultan la TOATE cele '
                  '${FirebaseService.kAllProjects.length} proiecte. '
                  'Starea afișată este a proiectului "${FirebaseService.kAllProjects.first}" (referință).',
              style: TextStyle(
                color:    color.withOpacity(0.85),
                fontSize: 10,
                height:   1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.white.withOpacity(0.2)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color:         Colors.white.withOpacity(0.2),
              fontSize:      9,
              fontWeight:    FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color:  Colors.white.withOpacity(0.04),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ecran Pointer Laser
// ─────────────────────────────────────────────────────────────────────────────
class _PointerScreen extends StatefulWidget {
  final ControlBloc  bloc;
  final VoidCallback onExit;

  const _PointerScreen({required this.bloc, required this.onExit});

  @override
  State<_PointerScreen> createState() => _PointerScreenState();
}

class _PointerScreenState extends State<_PointerScreen> {
  double?   _dotX, _dotY;
  bool      _isDown = false;
  DateTime? _lastSend;

  static const _throttle = Duration(milliseconds: 30);

  void _updatePointer(Offset local, BoxConstraints constraints) {
    final nx = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final ny = (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
    setState(() { _dotX = nx; _dotY = ny; });

    final now = DateTime.now();
    if (_lastSend == null || now.difference(_lastSend!) >= _throttle) {
      _lastSend = now;
      widget.bloc.add(SetPointerEvent(nx, ny));
    }
  }

  void _releasePointer() {
    setState(() => _isDown = false);
    widget.bloc.add(ClearPointerEvent());
  }

  @override
  Widget build(BuildContext context) {
    const red    = Color(0xFFFF2244);
    const purple = Color(0xFF6C63FF);

    return Container(
      color: const Color(0xEA07070f),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              border: Border(
                bottom: BorderSide(color: red.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border:       Border.all(color: red.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.spatial_tracking, color: red, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'MOD POINTER',
                        style: TextStyle(
                          color: red, fontSize: 11,
                          fontWeight: FontWeight.w800, letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _isDown
                      ? 'Pointer activ pe Display'
                      : 'Apasă oriunde în zonă pentru a indica pe Display',
                  style: TextStyle(
                    color:    _isDown ? red : Colors.white38,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:  8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:      _isDown ? red : Colors.white12,
                    boxShadow: _isDown
                        ? [BoxShadow(color: red.withOpacity(0.7), blurRadius: 8)]
                        : [],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: widget.onExit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border:       Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 13, color: Colors.white54),
                        SizedBox(width: 6),
                        Text(
                          'IEȘI',
                          style: TextStyle(
                            color: Colors.white54, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      return Listener(
                        onPointerDown: (e) {
                          setState(() => _isDown = true);
                          _updatePointer(e.localPosition, constraints);
                        },
                        onPointerMove: (e) {
                          if (_isDown) _updatePointer(e.localPosition, constraints);
                        },
                        onPointerUp:     (_) => _releasePointer(),
                        onPointerCancel: (_) => _releasePointer(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isDown
                                    ? red.withOpacity(0.6)
                                    : purple.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CustomPaint(
                                    painter: _GridPainter(),
                                    child: const SizedBox.expand(),
                                  ),
                                  if (!_isDown)
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.touch_app_outlined,
                                            color: purple.withOpacity(0.3),
                                            size: 40,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Apasă sau trage pentru a indica pe ecranul Display',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color:    Colors.white.withOpacity(0.2),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_isDown && _dotX != null && _dotY != null)
                                    Positioned(
                                      left: _dotX! * constraints.maxWidth  - 12,
                                      top:  _dotY! * constraints.maxHeight - 12,
                                      child: Container(
                                        width:  24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: red.withOpacity(0.85),
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color:      red.withOpacity(0.6),
                                              blurRadius: 16,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.black.withOpacity(0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HintChip(icon: Icons.mouse, text: 'Click și trage pentru mișcare continuă'),
                const SizedBox(width: 24),
                _HintChip(icon: Icons.touch_app, text: 'Funcționează și cu touch'),
                const SizedBox(width: 24),
                _HintChip(icon: Icons.visibility_off_outlined,
                    text: 'Laser dispare la eliberare'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _HintChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white24),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white24, fontSize: 10)),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final centerPaint = Paint()
      ..color       = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(size.width / 2, 0), Offset(size.width / 2, size.height), centerPaint);
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), centerPaint);
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}