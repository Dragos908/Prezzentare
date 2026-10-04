// lib/sound/ui/sound_dock.dart
//
// Dock-ul „Sunet”: fix, pliabil, mereu vizibil jos pe pagina de control.
//   header: volum general · Anterior / Pauză-Reluare / Următorul · fade global ·
//           „OPREȘTE TOT” · + Adaugă sunet · Gestionează
//   corp:   grila de pad-uri (audio + video), bara de import
// Responsive: header-ul trece pe mai multe rânduri (Wrap), grila se împachetează.
// Fiecare pad se reconstruiește singur la tick-uri de poziție / volum.

import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../audio/audio_engine.dart';
import '../audio/playback_coordinator.dart';
import '../core/models.dart';
import '../data/settings_repository.dart';
import '../data/sound_library.dart';
import 'add_sound_dialog.dart';
import 'manage_sounds_sheet.dart';
import 'sound_edit_sheet.dart';
import 'sound_pad.dart';

class SoundDock extends StatefulWidget {
  final PlaybackCoordinator coordinator;
  final SoundLibrary library;
  final AudioEngine engine;
  final SettingsRepository settings;

  /// false în teste (desktop_drop folosește un canal de platformă).
  final bool enableDrop;

  const SoundDock({
    super.key,
    required this.coordinator,
    required this.library,
    required this.engine,
    required this.settings,
    this.enableDrop = true,
  });

  @override
  State<SoundDock> createState() => _SoundDockState();
}

class _SoundDockState extends State<SoundDock> {
  bool _expanded = true;
  bool _dropHover = false;

  Future<void> _dropped(DropDoneDetails d) async {
    final picked = <PickedMedia>[];
    for (final f in d.files) {
      try {
        picked.add(PickedMedia(
            name: f.name, bytes: await f.readAsBytes(), mime: f.mimeType));
      } catch (_) {}
    }
    if (picked.isNotEmpty) widget.library.importFiles(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final maxGrid = math.min(MediaQuery.sizeOf(context).height * 0.38, 360.0);

    Widget grid = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxGrid),
      child: _PadGrid(
        coordinator: widget.coordinator,
        library: widget.library,
        engine: widget.engine,
        settings: widget.settings,
      ),
    );
    if (widget.enableDrop) {
      grid = DropTarget(
        onDragEntered: (_) => setState(() => _dropHover = true),
        onDragExited: (_) => setState(() => _dropHover = false),
        onDragDone: (d) {
          setState(() => _dropHover = false);
          _dropped(d);
        },
        child: grid,
      );
    }

    return Material(
      color: t.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _dropHover ? t.accent : t.border, width: _dropHover ? 2 : 1)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DockHeader(
                coordinator: widget.coordinator,
                library: widget.library,
                engine: widget.engine,
                expanded: _expanded,
                onToggle: () => setState(() => _expanded = !_expanded),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? grid
                    : const SizedBox(width: double.infinity),
              ),
              _ImportStrip(library: widget.library),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _DockHeader extends StatelessWidget {
  final PlaybackCoordinator coordinator;
  final SoundLibrary library;
  final AudioEngine engine;
  final bool expanded;
  final VoidCallback onToggle;

  const _DockHeader({
    required this.coordinator,
    required this.library,
    required this.engine,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AppIconButton(
            icon: expanded ? Icons.expand_more_rounded : Icons.expand_less_rounded,
            tooltip: expanded ? 'Restrânge Sunet' : 'Extinde Sunet',
            onPressed: onToggle,
          ),
          Text('SUNET',
              style: t.label.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: 2.5, color: t.textHi)),

          // ── volum general ──────────────────────────────────────────────────
          SizedBox(
            width: 210,
            child: ValueListenableBuilder<double>(
              valueListenable: engine.master,
              builder: (context, v, _) => Row(
                children: [
                  Icon(v <= 0.001 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: t.textMid, size: 20),
                  Expanded(
                    child: Semantics(
                      label: 'Volum general',
                      child: Slider(
                        value: v.clamp(0.0, 1.0).toDouble(),
                        onChanged: coordinator.setMasterVolume,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text('${(v * 100).round()}%',
                        textAlign: TextAlign.right, style: t.caption),
                  ),
                ],
              ),
            ),
          ),

          // ── transport global ───────────────────────────────────────────────
          AppIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Sunetul anterior',
            onPressed: () => coordinator.previous(),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: coordinator.anyPlaying,
            builder: (context, playing, _) => AppIconButton(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tooltip: playing ? 'Pauză (toate)' : 'Reia (toate)',
              active: playing,
              onPressed: coordinator.toggleGlobalPause,
            ),
          ),
          AppIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Sunetul următor',
            onPressed: () => coordinator.next(),
          ),

          // ── fade global (doar când rulează ceva) ───────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: coordinator.anyPlaying,
            builder: (context, playing, _) {
              if (!playing) return const SizedBox.shrink();
              return Wrap(spacing: 8, children: [
                AppIconButton(
                  icon: Icons.volume_down_rounded,
                  tooltip: 'Fade la nivel (toate)',
                  onPressed: coordinator.fadeToLevelAll,
                ),
                AppIconButton(
                  icon: Icons.volume_up_rounded,
                  tooltip: 'Revino la normal (toate)',
                  onPressed: coordinator.returnToNormalAll,
                ),
                AppIconButton(
                  icon: Icons.trending_down_rounded,
                  tooltip: 'Fade-out tot',
                  onPressed: coordinator.fadeOutAll,
                ),
              ]);
            },
          ),

          // ── OPREȘTE TOT ────────────────────────────────────────────────────
          Semantics(
            button: true,
            label: 'Oprește tot, instant',
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: t.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: coordinator.stopAll,
                icon: const Icon(Icons.stop_circle_rounded),
                label: const Text('OPREȘTE TOT',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            ),
          ),

          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => showAddSoundDialog(context, library),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adaugă sunet'),
            ),
          ),
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Gestionează sunetele',
            onPressed: () =>
                showManageSoundsSheet(context, library: library, engine: engine),
          ),

          // ── mesaj discret (ex. „Ultimul sunet din listă”) ──────────────────
          ValueListenableBuilder<String?>(
            valueListenable: coordinator.notice,
            builder: (context, msg, _) => msg == null
                ? const SizedBox.shrink()
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(msg,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.warning, fontSize: 12)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _PadGrid extends StatelessWidget {
  final PlaybackCoordinator coordinator;
  final SoundLibrary library;
  final AudioEngine engine;
  final SettingsRepository settings;

  const _PadGrid({
    required this.coordinator,
    required this.library,
    required this.engine,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ValueListenableBuilder<List<SoundItem>>(
      valueListenable: library.items,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Nu ai sunete încă. Apasă „Adaugă sunet” sau trage fișiere audio / video aici.',
                style: t.label,
              ),
            ),
          );
        }
        return ValueListenableBuilder<Map<String, MediaHealth>>(
          valueListenable: library.health,
          builder: (context, health, _) => ValueListenableBuilder<AppSettings>(
            valueListenable: settings.settings,
            builder: (context, s, _) => ValueListenableBuilder<String?>(
              valueListenable: coordinator.currentId,
              builder: (context, current, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final it in items)
                        SoundPad(
                          key: ValueKey<String>(it.id),
                          item: it,
                          engine: engine,
                          coordinator: coordinator,
                          health: health[it.id] ?? MediaHealth.ok,
                          size: s.padSize,
                          isCurrent: current == it.id,
                          onEdit: () => showSoundEditSheet(context,
                              item: it, library: library, engine: engine),
                          onReattach: () => reattachFile(context, library, it),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Progresul importurilor în curs (și erorile lor).
class _ImportStrip extends StatelessWidget {
  final SoundLibrary library;
  const _ImportStrip({required this.library});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ImportJob>>(
      valueListenable: library.jobs,
      builder: (context, jobs, _) {
        if (jobs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            children: [for (final j in jobs) _JobRow(job: j, library: library)],
          ),
        );
      },
    );
  }
}

class _JobRow extends StatelessWidget {
  final ImportJob job;
  final SoundLibrary library;
  const _JobRow({required this.job, required this.library});

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ValueListenableBuilder<JobState>(
      valueListenable: job.state,
      builder: (context, st, _) {
        final failed = st == JobState.failed;
        final done = st == JobState.done;
        return Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.surfaceHigh,
            borderRadius: BorderRadius.circular(t.rSm),
            border: Border.all(color: failed ? t.danger : t.border),
          ),
          child: Row(children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : done
                      ? Icons.check_circle_outline_rounded
                      : Icons.upload_file_rounded,
              size: 18,
              color: failed ? t.danger : (done ? t.success : t.textMid),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                  if (failed || (done && job.error != null))
                    Text(job.error ?? 'Eroare',
                        maxLines: 5,
                        style: TextStyle(color: failed ? t.danger : t.warning, fontSize: 12))
                  else if (!done)
                    ValueListenableBuilder<double>(
                      valueListenable: job.progress,
                      builder: (context, p, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(value: p <= 0 ? null : p),
                      ),
                    ),
                ],
              ),
            ),
            if (failed || done)
              IconButton(
                tooltip: 'Ascunde',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => library.dismissJob(job),
              ),
          ]),
        );
      },
    );
  }
}
