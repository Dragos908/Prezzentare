// lib/features/control/widgets/sound_status_pills.dart
//
// Pastilele din bara de sus a controlului: starea displayului, sincronizarea audio↔video
// (drift live, ex. „Sync ±12 ms ✓”) și garanția de mut („Display: sunet blocat ✓”).
// Se reîmprospătează la 1 s, ca un display căzut să apară offline chiar dacă nu mai
// vine nicio actualizare din baza de date.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../sound/audio/control_sound_system.dart';
import '../../../sound/core/models.dart';

class SoundStatusPills extends StatefulWidget {
  const SoundStatusPills({super.key});

  @override
  State<SoundStatusPills> createState() => _SoundStatusPillsState();
}

class _SoundStatusPillsState extends State<SoundStatusPills> {
  final ControlSoundSystem _sys = ControlSoundSystem.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ValueListenableBuilder<DisplayStatus>(
      valueListenable: _sys.displayStatus,
      builder: (context, d, _) {
        final online = d.isOnline(_sys.serverNowMs);
        final playingVideo = _sys.coordinator.syncedId != null;
        final pills = <Widget>[];

        // ── Display ──────────────────────────────────────────────────────────
        if (!online) {
          pills.add(StatusPill(
            icon: Icons.cloud_off_rounded,
            text: 'Display offline',
            color: t.warning,
            tooltip: 'Displayul nu a mai scris în baza de date în ultimele secunde.',
          ));
        } else if (d.buffering) {
          pills.add(StatusPill(
            icon: Icons.hourglass_top_rounded,
            text: 'Display: buffering',
            color: t.warning,
          ));
        } else {
          pills.add(StatusPill(
            icon: Icons.cast_connected_rounded,
            text: 'Display online',
            color: t.success,
          ));
        }

        // ── Sincronizare ─────────────────────────────────────────────────────
        if (online && playingVideo) {
          final drift = d.driftMs.abs();
          final color = drift <= 40 ? t.success : (drift <= 100 ? t.warning : t.danger);
          pills.add(StatusPill(
            icon: Icons.sync_rounded,
            text: 'Sync ±$drift ms ${drift <= 40 ? '✓' : '⚠'}',
            color: color,
            tooltip: 'Diferența dintre imaginea de pe display și audio-ul de pe control.',
          ));
        } else if (_sys.clockSync.isSynced) {
          pills.add(StatusPill(
            icon: Icons.schedule_rounded,
            text: 'Ceas sincronizat',
            color: t.textMid,
          ));
        }

        // ── Sunet display (mut garantat) ─────────────────────────────────────
        if (online) {
          if (d.guardActive && d.guardUnmuted == 0) {
            pills.add(StatusPill(
              icon: Icons.volume_off_rounded,
              text: 'Display: sunet blocat ✓',
              color: t.success,
              tooltip: d.embedsUnmutable > 0
                  ? '${d.embedsUnmutable} embed(uri) extern(e) nu pot fi mutate din aplicație.'
                  : 'Toate playerele de pe display sunt mutate.',
            ));
          } else if (d.guardActive) {
            pills.add(StatusPill(
              icon: Icons.warning_amber_rounded,
              text: 'Display: ${d.guardUnmuted} nemutate',
              color: t.danger,
            ));
          } else {
            pills.add(StatusPill(
              icon: Icons.volume_up_rounded,
              text: 'Display: sunet permis',
              color: t.warning,
            ));
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              pills[i],
            ],
          ],
        );
      },
    );
  }
}
