// lib/features/control/widgets/control_widgets.dart
//
//   • TouchToggleWidget    — toggle atingere pe tablă
//   • OverlayToggleWidget  — toggle overlay iframe
//   • VolumeControlWidget  — slider volum + butoane rapide
//   • CompactTimerPanel    — timer compact 2-col: general + slide curent + TOTAL
//   • TimerPanel           — original (compatibilitate)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/model.dart';
import '../bloc/control_bloc.dart';
import '../bloc/control_event.dart';

// ═════════════════════════════════════════════════════════════════════════════
// TOUCH TOGGLE
// ═════════════════════════════════════════════════════════════════════════════
class TouchToggleWidget extends StatelessWidget {
  const TouchToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final enabled = state.touchEnabled;
        final color = enabled
            ? const Color(0xFF00D9A3)
            : const Color(0xFFFF6584);

        return GestureDetector(
          onTap: () => context.read<ControlBloc>().add(ToggleTouchEvent()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  enabled ? Icons.touch_app : Icons.do_not_touch_outlined,
                  color: color, size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ATINGERE PE TABLĂ',
                        style: TextStyle(
                          color:         color,
                          fontSize:      9,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        enabled ? 'Activată' : 'Blocată',
                        style: TextStyle(color: color.withOpacity(0.6),
                            fontSize: 10),
                      ),
                    ],
                  ),
                ),
                _Switch(enabled: enabled, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// OVERLAY TOGGLE
// ═════════════════════════════════════════════════════════════════════════════
class OverlayToggleWidget extends StatelessWidget {
  const OverlayToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final enabled = state.overlayEnabled;
        final color = enabled
            ? const Color(0xFF6C63FF)
            : const Color(0xFFFF9800);

        return GestureDetector(
          onTap: () => context.read<ControlBloc>().add(ToggleOverlayEvent()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  enabled
                      ? Icons.layers_outlined
                      : Icons.layers_clear_outlined,
                  color: color, size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OVERLAY NAVIGARE',
                        style: TextStyle(
                          color:         color,
                          fontSize:      9,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        enabled
                            ? 'Activ — click stânga/dreapta'
                            : 'Dezactivat — iframe interactiv',
                        style: TextStyle(color: color.withOpacity(0.6),
                            fontSize: 10),
                      ),
                    ],
                  ),
                ),
                _Switch(enabled: enabled, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Switch vizual reutilizabil ────────────────────────────────────────────────
class _Switch extends StatelessWidget {
  final bool  enabled;
  final Color color;
  const _Switch({required this.enabled, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40, height: 22,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:        enabled ? color : Colors.white12,
        borderRadius: BorderRadius.circular(11),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16, height: 16,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// VOLUME CONTROL
// ═════════════════════════════════════════════════════════════════════════════
class VolumeControlWidget extends StatelessWidget {
  const VolumeControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc    = context.read<ControlBloc>();
        final vol     = state.volume;
        final isMuted = vol == 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isMuted ? Icons.volume_off : Icons.volume_up_outlined,
                    size: 16, color: Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'VOLUM',
                    style: TextStyle(
                      color:         Colors.white.withOpacity(0.5),
                      fontSize:      9,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    isMuted ? 'Mut' : '${(vol * 100).round()}%',
                    style: TextStyle(
                      color:      isMuted ? Colors.white30 : Colors.white70,
                      fontSize:   11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor:   const Color(0xFF6C63FF),
                  inactiveTrackColor: Colors.white12,
                  thumbColor:         const Color(0xFF6C63FF),
                  overlayColor:
                  const Color(0xFF6C63FF).withOpacity(0.15),
                  trackHeight:  3,
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14),
                ),
                child: Slider(
                  value:     vol,
                  min:       0.0,
                  max:       1.0,
                  onChanged: (v) => bloc.add(SetVolumeEvent(v)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [0.0, 0.25, 0.5, 0.75, 1.0].map((v) {
                  final isActive = (vol - v).abs() < 0.01;
                  return GestureDetector(
                    onTap: () => bloc.add(SetVolumeEvent(v)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF6C63FF).withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF6C63FF).withOpacity(0.5)
                              : Colors.white12,
                        ),
                      ),
                      child: Text(
                        v == 0 ? '0%' : '${(v * 100).round()}%',
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF6C63FF)
                              : Colors.white38,
                          fontSize:   9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ANNOUNCE BUTTON
// ═════════════════════════════════════════════════════════════════════════════
class AnnounceButtonWidget extends StatefulWidget {
  const AnnounceButtonWidget({super.key});

  @override
  State<AnnounceButtonWidget> createState() => _AnnounceButtonWidgetState();
}

class _AnnounceButtonWidgetState extends State<AnnounceButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseScale;
  late Animation<double>   _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startPulse(bool isActive) {
    if (isActive) {
      _pulseCtrl.repeat();
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc = context.read<ControlBloc>();

        final announceIdx =
        state.slides.indexWhere((s) => s.type == SlideType.announce);
        final hasAnnounce = announceIdx >= 0;

        final isActive = hasAnnounce &&
            state.currentSlide == announceIdx;

        // Pornește / oprește pulsul
        WidgetsBinding.instance.addPostFrameCallback(
                (_) => _startPulse(isActive));

        const orange     = Color(0xFFFF9800);
        const orangeDim  = Color(0xFFFF6F00);

        if (!hasAnnounce) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 15, color: Colors.white.withOpacity(0.18)),
                const SizedBox(width: 8),
                Text(
                  'Niciun slide de anunț',
                  style: TextStyle(
                    color:    Colors.white.withOpacity(0.25),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: isActive
              ? null
              : () => bloc.add(NavigateEvent(announceIdx)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isActive
                  ? orange.withOpacity(0.18)
                  : orangeDim.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? orange.withOpacity(0.75)
                    : orange.withOpacity(0.30),
                width: isActive ? 1.5 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                BoxShadow(
                  color:      orange.withOpacity(0.22),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ]
                  : [],
            ),
            child: Row(
              children: [
                // ── Iconiță cu inel pulsant ─────────────────────────────────
                SizedBox(
                  width:  36,
                  height: 36,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // inel pulsant exterior
                      if (isActive)
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, __) => Transform.scale(
                            scale: _pulseScale.value,
                            child: Container(
                              width:  36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: orange
                                      .withOpacity(_pulseOpacity.value),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // cerc fundal
                      Container(
                        width:  32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: orange.withOpacity(isActive ? 0.22 : 0.10),
                        ),
                        child: Icon(
                          Icons.campaign_rounded,
                          size:  17,
                          color: isActive ? orange : orange.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ── Text ────────────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive ? 'ANUNȚ ACTIV' : 'SALT LA ANUNȚ',
                        style: TextStyle(
                          color: isActive
                              ? orange
                              : orange.withOpacity(0.75),
                          fontSize:      10,
                          fontWeight:    FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive
                            ? 'Slide-ul de anunț este afișat acum'
                            : 'Apasă sau tasta [A] pentru salt rapid',
                        style: TextStyle(
                          color:    Colors.white.withOpacity(0.35),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // ── Badge shortcut / status ──────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? orange.withOpacity(0.20)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? orange.withOpacity(0.50)
                          : Colors.white.withOpacity(0.10),
                    ),
                  ),
                  child: Text(
                    isActive ? '● ON' : '[A]',
                    style: TextStyle(
                      color: isActive ? orange : Colors.white38,
                      fontSize:      9,
                      fontFamily:    'monospace',
                      fontWeight:    FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// COMPACT TIMER PANEL
//
// Afișează:
//   1. Timer general (start / pauză / reset)
//   2. Timp pe slide-ul curent, actualizat live prin _ticker (1s)
//   3. TOTAL acumulat pe toate slide-urile cu excepția intro-ului
//
// Cronometrarea per-slide funcționează astfel:
//   • La navigare, Firebase setează slideTimers[idx].startTs = now
//   • Câmpul endTs rămâne null cât timp slide-ul e activ
//   • SlideTimerData.totalMs = accumulated + (now - startTs)
//   • _ticker forțează rebuild la fiecare secundă → counter live
// ═════════════════════════════════════════════════════════════════════════════
class CompactTimerPanel extends StatefulWidget {
  const CompactTimerPanel({super.key});

  @override
  State<CompactTimerPanel> createState() => _CompactTimerPanelState();
}

class _CompactTimerPanelState extends State<CompactTimerPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Suma tuturor timer-elor, exclusiv slide-urile cu tipul din [excludeTypes].
  int _totalExcluding(
      PresentationState state, {
        Set<SlideType> excludeTypes = const {SlideType.intro},
      }) {
    int sum = 0;
    for (var i = 0; i < state.slides.length; i++) {
      if (excludeTypes.contains(state.slides[i].type)) continue;
      sum += state.slideTimers[i]?.totalMs ?? 0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc   = context.read<ControlBloc>();
        final genMs  = state.timerTotalMs;

        final curIdx   = state.currentSlide;
        final curTimer = state.slideTimers[curIdx];
        final slideMs  = curTimer?.totalMs ?? 0;
        // Slide în desfășurare = startTs setat și endTs null
        final slideRunning =
            curTimer != null &&
                curTimer.startTs != null &&
                curTimer.endTs == null;

        final curSlide = state.slides.isNotEmpty
            ? state.slides[curIdx.clamp(0, state.slides.length - 1)]
            : null;

        final totalSlidesMs = _totalExcluding(state);

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Timer general ─────────────────────────────────────────────
              _CompactTimerDisplay(
                timeStr: formatMs(genMs),
                running: state.timerRunning,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SmallBtn(
                      label: state.timerRunning ? '⏸ PAUZĂ' : '▶ START',
                      color: state.timerRunning
                          ? const Color(0xFFFF6584)
                          : const Color(0xFF00D9A3),
                      onTap: () => bloc.add(TimerToggleEvent()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SmallBtn(
                    label: '↺',
                    color: Colors.white24,
                    onTap: () => bloc.add(TimerResetEvent()),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Timer slide curent ────────────────────────────────────────
              _SlideTimerRow(
                label:   curSlide?.title ?? '—',
                timeMs:  slideMs,
                running: slideRunning,
                color:   const Color(0xFF00D9A3),
              ),
              const SizedBox(height: 6),

              // ── Total acumulat (fără intro) ───────────────────────────────
              _SlideTimerRow(
                label:   'TOTAL (fără intro)',
                timeMs:  totalSlidesMs,
                running: false,
                color:   const Color(0xFF6C63FF),
                isTotal: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Rând timer (slide curent sau total) ──────────────────────────────────────
class _SlideTimerRow extends StatelessWidget {
  final String label;
  final int    timeMs;
  final bool   running;
  final Color  color;
  final bool   isTotal;

  const _SlideTimerRow({
    required this.label,
    required this.timeMs,
    required this.running,
    required this.color,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isTotal
            ? color.withOpacity(0.07)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: running
              ? color.withOpacity(0.40)
              : isTotal
              ? color.withOpacity(0.25)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          if (running) ...[
            _RunningDot(color: color),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:      Colors.white.withOpacity(isTotal ? 0.55 : 0.50),
                fontSize:   isTotal ? 9 : 10,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
                letterSpacing: isTotal ? 0.8 : 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMs(timeMs),
            style: TextStyle(
              color:      color,
              fontSize:   isTotal ? 15 : 17,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot verde pulsant ─────────────────────────────────────────────────────────
class _RunningDot extends StatefulWidget {
  final Color color;
  const _RunningDot({required this.color});
  @override
  State<_RunningDot> createState() => _RunningDotState();
}

class _RunningDotState extends State<_RunningDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.4 + 0.6 * _ctrl.value,
        child: Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.6),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Timer display mare (timer general) ───────────────────────────────────────
class _CompactTimerDisplay extends StatelessWidget {
  final String timeStr;
  final bool   running;

  const _CompactTimerDisplay({required this.timeStr, required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: running
            ? const Color(0xFF6C63FF).withOpacity(0.10)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: running
              ? const Color(0xFF6C63FF).withOpacity(0.4)
              : Colors.white12,
        ),
      ),
      child: Text(
        timeStr,
        style: TextStyle(
          color:         running ? Colors.white : Colors.white60,
          fontSize:      32,
          fontFamily:    'monospace',
          fontWeight:    FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
    );
  }
}

// ── Buton mic ─────────────────────────────────────────────────────────────────
class _SmallBtn extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:        color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color == Colors.white24 ? Colors.white54 : color,
            fontSize:      11,
            fontWeight:    FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TIMER PANEL (original — păstrat pentru compatibilitate)
// ═════════════════════════════════════════════════════════════════════════════
class TimerPanel extends StatefulWidget {
  const TimerPanel({super.key});
  @override
  State<TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends State<TimerPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _ticker?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc     = context.read<ControlBloc>();
        final totalMs  = state.timerTotalMs;
        final curTimer = state.slideTimers[state.currentSlide];
        final slideMs  = curTimer?.totalMs ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('CRONOMETRU GENERAL'),
              const SizedBox(height: 8),
              _TimerDisplay(
                timeStr: formatMs(totalMs),
                running: state.timerRunning,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ControlButton(
                      label: state.timerRunning ? '⏸ PAUZĂ' : '▶ PORNEȘTE',
                      color: state.timerRunning
                          ? const Color(0xFFFF6584)
                          : const Color(0xFF00D9A3),
                      onTap: () => bloc.add(TimerToggleEvent()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ControlButton(
                    label: '↺ RESET',
                    color: Colors.white24,
                    onTap: () => bloc.add(TimerResetEvent()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('CRONOMETRU SLIDE CURENT'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.slides.isEmpty ? '—'
                              : state.slides[state.currentSlide
                              .clamp(0, state.slides.length - 1)].title,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text('timp pe slide-ul activ',
                            style: TextStyle(
                                color: Colors.white30, fontSize: 10)),
                      ],
                    ),
                    Text(
                      formatMs(slideMs),
                      style: const TextStyle(
                        color:      Color(0xFF00D9A3),
                        fontSize:   22,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  final String timeStr;
  final bool   running;
  const _TimerDisplay({required this.timeStr, required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: running
            ? const Color(0xFF6C63FF).withOpacity(0.1)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: running
              ? const Color(0xFF6C63FF).withOpacity(0.4)
              : Colors.white12,
        ),
      ),
      child: Text(
        timeStr,
        style: TextStyle(
          color:         running ? Colors.white : Colors.white60,
          fontSize:      44,
          fontFamily:    'monospace',
          fontWeight:    FontWeight.w700,
          letterSpacing: 4,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _ControlButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:        color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color == Colors.white24 ? Colors.white54 : color,
            fontSize:      12,
            fontWeight:    FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
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