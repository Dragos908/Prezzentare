// lib/features/control/widgets/control_widgets.dart
//
// Conține toate widget-urile de control UI:
//   • TouchToggleWidget   — toggle atingere pe tablă
//   • VolumeControlWidget — slider volum + butoane rapide
//   • TimerPanel          — cronometru general + cronometru slide curent

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/model.dart';
import '../bloc/control_bloc.dart';
import '../bloc/control_event.dart';

// ═════════════════════════════════════════════════════════════════════════════
// TOUCH TOGGLE WIDGET
// Toggle on/off pentru atingerile pe tablă.
// Sincronizat cu Firebase — schimbarea apare instantaneu pe display.
// ═════════════════════════════════════════════════════════════════════════════
class TouchToggleWidget extends StatelessWidget {
  const TouchToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final enabled = state.touchEnabled;
        final color   = enabled
            ? const Color(0xFF00D9A3)
            : const Color(0xFFFF6584);

        return GestureDetector(
          onTap: () => context.read<ControlBloc>().add(ToggleTouchEvent()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  enabled ? Icons.touch_app : Icons.do_not_touch_outlined,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ATINGERE PE TABLĂ',
                        style: TextStyle(
                          color:         color,
                          fontSize:      10,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        enabled ? 'Activată' : 'Blocată',
                        style: TextStyle(
                          color:    color.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Switch vizual
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:  44,
                  height: 24,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color:        enabled ? color : Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration:  const Duration(milliseconds: 200),
                    alignment: enabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width:  18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
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
// OVERLAY TOGGLE WIDGET
// Toggle on/off pentru overlay-ul de navigare iframe.
// Când dezactivat, iframe-ul devine complet interactiv (ex: video).
// ═════════════════════════════════════════════════════════════════════════════
class OverlayToggleWidget extends StatelessWidget {
  const OverlayToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final enabled = state.overlayEnabled;
        final color   = enabled
            ? const Color(0xFF6C63FF)
            : const Color(0xFFFF9800);

        return GestureDetector(
          onTap: () => context.read<ControlBloc>().add(ToggleOverlayEvent()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  enabled ? Icons.layers_outlined : Icons.layers_clear_outlined,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OVERLAY NAVIGARE',
                        style: TextStyle(
                          color:         color,
                          fontSize:      10,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        enabled ? 'Activ — click stânga/dreapta' : 'Dezactivat — iframe interactiv',
                        style: TextStyle(
                          color:    color.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Switch vizual
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:  44,
                  height: 24,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color:        enabled ? color : Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration:  const Duration(milliseconds: 200),
                    alignment: enabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width:  18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
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
// VOLUME CONTROL WIDGET
// ═════════════════════════════════════════════════════════════════════════════
class VolumeControlWidget extends StatelessWidget {
  const VolumeControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc   = context.read<ControlBloc>();
        final vol    = state.volume;
        final isMuted = vol == 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    isMuted
                        ? Icons.volume_off
                        : vol < 0.5
                        ? Icons.volume_down
                        : Icons.volume_up,
                    color: Colors.white54,
                    size:  18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'VOLUM',
                    style: TextStyle(
                      color:         Colors.white.withOpacity(0.5),
                      fontSize:      10,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(vol * 100).round()}%',
                    style: const TextStyle(
                      color:      Colors.white70,
                      fontSize:   12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Slider
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor:   const Color(0xFF6C63FF),
                  inactiveTrackColor: Colors.white12,
                  thumbColor:         Colors.white,
                  overlayColor:       const Color(0xFF6C63FF).withOpacity(0.2),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  trackHeight: 4,
                ),
                child: Slider(
                  value:    vol,
                  min:      0.0,
                  max:      1.0,
                  onChanged: (v) => bloc.add(SetVolumeEvent(v)),
                ),
              ),
              const SizedBox(height: 8),

              // Butoane rapide
              Row(
                children: [
                  _QuickButton(
                    label: '🔇 MUT',
                    active: isMuted,
                    onTap:  () => bloc.add(SetVolumeEvent(0.0)),
                  ),
                  const SizedBox(width: 8),
                  _QuickButton(
                    label: '50%',
                    active: vol == 0.5,
                    onTap:  () => bloc.add(SetVolumeEvent(0.5)),
                  ),
                  const SizedBox(width: 8),
                  _QuickButton(
                    label: '🔊 MAX',
                    active: vol == 1.0,
                    onTap:  () => bloc.add(SetVolumeEvent(1.0)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  const _QuickButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF6C63FF).withOpacity(0.2)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? const Color(0xFF6C63FF).withOpacity(0.5)
                : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      active ? const Color(0xFF6C63FF) : Colors.white38,
            fontSize:   11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TIMER PANEL
// Afișează cronometrul general și cronometrul slide-ului curent.
// Folosește un Timer intern (1s) pentru a forța rebuild la fiecare secundă
// — Firebase nu trimite update-uri atât de des.
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
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ControlBloc, PresentationState>(
      builder: (context, state) {
        final bloc    = context.read<ControlBloc>();
        final totalMs = state.timerTotalMs;
        final curTimer = state.slideTimers[state.currentSlide];
        final slideMs  = curTimer?.totalMs ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Cronometru General ──
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

              // ── Cronometru Slide Curent ──
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
                          state.slides.isEmpty
                              ? '—'
                              : state.slides[
                          state.currentSlide.clamp(
                              0, state.slides.length - 1)
                          ].title,
                          style: const TextStyle(
                            color:    Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'timp pe slide-ul activ',
                          style: TextStyle(
                            color:    Colors.white30,
                            fontSize: 10,
                          ),
                        ),
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

// ── Helpers private TimerPanel ────────────────────────────────────────────────

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
            color:         color == Colors.white24 ? Colors.white54 : color,
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