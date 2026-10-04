// lib/sound/ui/sound_pad.dart
//
// Un pad de sunet. Două tipuri, vizual diferite: audio (icon notă, culoarea
// sunetului) și video (icon film, accent turcoaz + insignă „DISPLAY”).
// Fiecare pad ascultă DOAR propriul ValueListenable<PadState>, deci un tick de
// poziție / volum reconstruiește un singur pad, nu tot dock-ul.
// Butoanele de fade apar contextual, doar pe pad-ul care rulează.

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../audio/audio_engine.dart';
import '../audio/playback_coordinator.dart';
import '../core/models.dart';
import '../data/sound_library.dart';

class SoundPad extends StatelessWidget {
  final SoundItem item;
  final AudioEngine engine;
  final PlaybackCoordinator coordinator;
  final MediaHealth health;
  final String size; // small | medium | large
  final bool isCurrent;
  final VoidCallback onEdit;
  final VoidCallback onReattach;

  const SoundPad({
    super.key,
    required this.item,
    required this.engine,
    required this.coordinator,
    required this.health,
    required this.size,
    required this.isCurrent,
    required this.onEdit,
    required this.onReattach,
  });

  double get _width => switch (size) {
        'small' => 156,
        'large' => 244,
        _ => 196,
      };

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: _width,
        child: ValueListenableBuilder<PadState>(
          valueListenable: engine.pad(item.id),
          builder: (context, ps, _) => _PadBody(
            item: item,
            ps: ps,
            coordinator: coordinator,
            health: health,
            isCurrent: isCurrent,
            onEdit: onEdit,
            onReattach: onReattach,
          ),
        ),
      ),
    );
  }
}

class _PadBody extends StatelessWidget {
  final SoundItem item;
  final PadState ps;
  final PlaybackCoordinator coordinator;
  final MediaHealth health;
  final bool isCurrent;
  final VoidCallback onEdit;
  final VoidCallback onReattach;

  const _PadBody({
    required this.item,
    required this.ps,
    required this.coordinator,
    required this.health,
    required this.isCurrent,
    required this.onEdit,
    required this.onReattach,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final missing = health == MediaHealth.missing;
    final base = item.isVideo ? t.accent2 : Color(item.color);
    final active = ps.active;
    final border = missing
        ? t.warning
        : active
            ? base
            : (isCurrent ? base.withOpacity(0.55) : t.border);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: active ? base.withOpacity(0.14) : t.surfaceHigh,
        borderRadius: BorderRadius.circular(t.rMd),
        border: Border.all(color: border, width: active ? 1.6 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── zona principală: Play/Stop dintr-o apăsare ─────────────────────
          Semantics(
            button: true,
            label: '${item.name}: ${active ? 'oprește' : 'pornește'}',
            child: InkWell(
              borderRadius: BorderRadius.circular(t.rMd),
              onTap: missing
                  ? onReattach
                  : () => coordinator.togglePad(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                  child: Row(
                    children: [
                      _TypeChip(item: item, color: base, active: active),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.body.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            _SubLine(item: item, ps: ps, missing: missing),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          tooltip: 'Editează „${item.name}”',
                          icon: Icon(Icons.more_vert, size: 20, color: t.textMid),
                          onPressed: onEdit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (missing)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text('Fișier lipsă — apasă pentru a-l adăuga din nou',
                  style: TextStyle(color: t.warning, fontSize: 11)),
            ),

          // ── controale contextuale (doar când rulează) ──────────────────────
          if (active) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: _SeekBar(item: item, ps: ps, coordinator: coordinator, color: base),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: _VolumeBar(item: item, ps: ps, coordinator: coordinator, color: base),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              child: _PadButtons(item: item, ps: ps, coordinator: coordinator, color: base),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final SoundItem item;
  final Color color;
  final bool active;
  const _TypeChip({required this.item, required this.color, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(active ? 0.30 : 0.16),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        active
            ? Icons.graphic_eq_rounded
            : (item.isVideo ? Icons.movie_rounded : Icons.music_note_rounded),
        color: color,
        size: 22,
      ),
    );
  }
}

class _SubLine extends StatelessWidget {
  final SoundItem item;
  final PadState ps;
  final bool missing;
  const _SubLine({required this.item, required this.ps, required this.missing});

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final len = item.trimLengthMs;
    String text;
    if (ps.active) {
      final pos = ps.positionMs - item.trimStartMs;
      text = '${formatClock(pos)} / ${formatClock(len)}';
      if (ps.rampRemainingMs > 0) {
        text += '  ·  ${(ps.rampRemainingMs / 1000).ceil()} s';
      }
    } else {
      text = formatClock(len);
    }
    return Row(
      children: [
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(
                  color: ps.rampRemainingMs > 0 ? t.warning : t.textLo)),
        ),
        if (item.loop) ...[
          const SizedBox(width: 4),
          Icon(Icons.repeat_rounded, size: 13, color: t.textLo),
        ],
        if (item.isVideo) ...[
          const SizedBox(width: 4),
          Icon(Icons.cast_connected_rounded, size: 13, color: t.accent2),
        ],
      ],
    );
  }
}

SliderThemeData _thin(BuildContext context, Color c) =>
    SliderTheme.of(context).copyWith(
      trackHeight: 3,
      activeTrackColor: c,
      inactiveTrackColor: c.withOpacity(0.22),
      thumbColor: c,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: SliderComponentShape.noOverlay,
    );

/// Bara de progres cu seek (se actualizează la ~12 Hz din motor).
class _SeekBar extends StatefulWidget {
  final SoundItem item;
  final PadState ps;
  final PlaybackCoordinator coordinator;
  final Color color;
  const _SeekBar({
    required this.item,
    required this.ps,
    required this.coordinator,
    required this.color,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final len = it.trimLengthMs;
    return Semantics(
      label: 'Poziție în sunet',
      child: SliderTheme(
        data: _thin(context, widget.color),
        child: SizedBox(
          height: 28,
          child: Slider(
            value: (_drag ?? widget.ps.progress).clamp(0.0, 1.0).toDouble(),
            onChanged: len <= 0 ? null : (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              setState(() => _drag = null);
              widget.coordinator.seek(it.id, it.trimStartMs + (v * len).round());
            },
          ),
        ),
      ),
    );
  }
}

/// Volumul sunetului: mutat manual anulează rampa. Marcajul arată target_level.
class _VolumeBar extends StatelessWidget {
  final SoundItem item;
  final PadState ps;
  final PlaybackCoordinator coordinator;
  final Color color;
  const _VolumeBar({
    required this.item,
    required this.ps,
    required this.coordinator,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final ramping = ps.rampRemainingMs > 0;
    return Row(
      children: [
        Icon(Icons.volume_up_rounded, size: 16, color: ramping ? t.warning : t.textMid),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: _thin(context, ramping ? t.warning : color),
            child: SizedBox(
              height: 28,
              child: LayoutBuilder(
                builder: (context, c) {
                  const pad = 6.0; // = raza thumb-ului
                  final x = pad + (c.maxWidth - 2 * pad) * item.targetLevel;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Slider(
                        value: ps.volume.clamp(0.0, 1.0).toDouble(),
                        onChanged: (v) => coordinator.setSoundVolume(item.id, v),
                      ),
                      // marcaj target_level (ținta lui „Fade la nivel”)
                      Positioned(
                        left: x - 1,
                        top: 4,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Container(width: 2, color: t.textHi.withOpacity(0.55)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text('${(ps.volume * 100).round()}%',
              textAlign: TextAlign.right, style: t.caption),
        ),
      ],
    );
  }
}

/// Butoanele contextuale: pauză, restart, fade la nivel, revino la normal, fade-out.
/// Apăsare lungă pe un fade → alegerea rapidă a duratei (1 / 3 / 5 / 10 s).
class _PadButtons extends StatelessWidget {
  final SoundItem item;
  final PadState ps;
  final PlaybackCoordinator coordinator;
  final Color color;
  const _PadButtons({
    required this.item,
    required this.ps,
    required this.coordinator,
    required this.color,
  });

  Future<void> _pickDuration(BuildContext context, void Function(int ms) run) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final ms = await showMenu<int>(
      context: context,
      position: pos,
      items: const [
        PopupMenuItem(value: 1000, child: Text('1 s')),
        PopupMenuItem(value: 3000, child: Text('3 s')),
        PopupMenuItem(value: 5000, child: Text('5 s')),
        PopupMenuItem(value: 10000, child: Text('10 s')),
      ],
    );
    if (ms != null) run(ms);
  }

  Widget _fade(BuildContext context, IconData icon, String tip, Object tag,
      void Function(int? ms) run) {
    return Builder(
      builder: (ctx) => GestureDetector(
        onLongPress: () => _pickDuration(ctx, (ms) => run(ms)),
        child: AppIconButton(
          icon: icon,
          tooltip: '$tip (apăsare lungă: alege durata)',
          active: ps.rampTag == tag,
          color: color,
          onPressed: () => run(null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = item.id;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        AppIconButton(
          icon: ps.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tooltip: ps.paused ? 'Reia' : 'Pauză',
          color: color,
          onPressed: () => ps.paused ? coordinator.resume(id) : coordinator.pause(id),
        ),
        AppIconButton(
          icon: Icons.replay_rounded,
          tooltip: 'Restart de la început',
          color: color,
          onPressed: () => coordinator.restart(id),
        ),
        _fade(context, Icons.volume_down_rounded, 'Fade la nivel', kTagToLevel,
            (ms) => coordinator.fadeToLevel(id, ms: ms)),
        _fade(context, Icons.volume_up_rounded, 'Revino la normal', kTagToNormal,
            (ms) => coordinator.returnToNormal(id, ms: ms)),
        _fade(context, Icons.trending_down_rounded, 'Fade-out', kTagFadeOut,
            (ms) => coordinator.fadeOut(id, ms: ms)),
      ],
    );
  }
}
