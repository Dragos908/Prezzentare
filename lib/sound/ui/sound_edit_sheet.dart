// lib/sound/ui/sound_edit_sheet.dart
//
// Editarea unui sunet: nume, tăiere non-distructivă (Start / Sfârșit, cu butoane
// „Setează aici” în timpul redării), volum, target_level, buclă, fade-in, durate
// de fade per sunet (suprascriu valorile implicite din Setări). Fișierul original
// rămâne intact: se salvează doar punctele.

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../audio/audio_engine.dart';
import '../core/models.dart';
import '../data/sound_library.dart';

// Fade-out / fade la nivel: null = valoarea implicită din Setări.
const List<int?> _fadeChoices = <int?>[null, 500, 1000, 3000, 5000, 10000, 15000, 30000];
// Fade-in: 0 = pornire directă.
const List<int?> _fadeInChoices = <int?>[0, 500, 1000, 2000, 3000, 5000, 10000];

String _fadeLabel(int? ms) => ms == null
    ? 'Implicit (din Setări)'
    : (ms == 0 ? 'Fără (pornire directă)' : '${ms / 1000} s');

Future<void> showSoundEditSheet(
  BuildContext context, {
  required SoundItem item,
  required SoundLibrary library,
  required AudioEngine engine,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EditDialog(item: item, library: library, engine: engine),
  );
}

class _EditDialog extends StatefulWidget {
  final SoundItem item;
  final SoundLibrary library;
  final AudioEngine engine;
  const _EditDialog({required this.item, required this.library, required this.engine});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item.name);
  late int _start = widget.item.trimStartMs;
  late int _end = widget.item.effectiveTrimEndMs;
  late double _volume = widget.item.volume;
  late double _target = widget.item.targetLevel;
  late bool _loop = widget.item.loop;
  late int _fadeIn = widget.item.fadeInMs;
  late int? _fadeOut = widget.item.fadeOutMs;
  late int? _fadeTo = widget.item.fadeToLevelMs;
  late int _color = widget.item.color;

  static bool _isLink(String? p) =>
      p != null && (p.startsWith('http://') || p.startsWith('https://'));

  /// Link direct către video, folosit de display (doar pentru sunete video).
  late final TextEditingController _link = TextEditingController(
      text: _isLink(widget.item.assetPath) ? widget.item.assetPath : '');
  String? _linkError;

  int get _duration => widget.item.durationMs;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  void _setFromPlayhead({required bool start}) {
    final pos = widget.engine.positionMs(widget.item.id);
    setState(() {
      if (start) {
        _start = pos.clamp(0, _end - 100).toInt();
      } else {
        _end = pos.clamp(_start + 100, _duration).toInt();
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? widget.item.name : _name.text.trim();
    final trimEnd = _end >= _duration ? null : _end; // null = până la sfârșit

    // Link video pentru display: completat = îl folosește; golit (dacă era link)
    // = displayul rămâne fără imagine; altfel calea din assets rămâne neschimbată.
    String? asset = widget.item.assetPath;
    if (widget.item.isVideo) {
      final link = _link.text.trim();
      if (link.isNotEmpty && !_isLink(link)) {
        setState(() => _linkError = 'Linkul trebuie să înceapă cu https://');
        return;
      }
      if (link.isNotEmpty) {
        asset = link;
      } else if (_isLink(asset)) {
        asset = null;
      }
    }

    final updated = widget.item.copyWith(
      name: name,
      trimStartMs: _start,
      trimEndMs: trimEnd,
      volume: _volume,
      targetLevel: _target,
      loop: _loop,
      fadeInMs: _fadeIn,
      fadeOutMs: _fadeOut,
      fadeToLevelMs: _fadeTo,
      color: _color,
      assetPath: asset,
    );
    await widget.library.save(updated);
    widget.engine.updateItem(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _fadeDropdown(
      String label, int? value, List<int?> base, ValueChanged<int?> onChanged) {
    // valoarea salvată poate lipsi din listă (ex. 750 ms): o adăugăm, altfel
    // DropdownButton ar eșua cu „exact un item cu valoarea…”.
    final choices = <int?>[...base];
    if (!choices.contains(value)) choices.add(value);
    return InputDecorator(
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final c in choices)
              DropdownMenuItem<int?>(value: c, child: Text(_fadeLabel(c))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final maxMs = _duration > 0 ? _duration : (_end > 0 ? _end : 1000);
    final active = widget.engine.isActive(widget.item.id);

    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.rLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text('Editează sunetul', style: t.title)),
                  IconButton(
                    tooltip: 'Închide',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Nume', border: OutlineInputBorder()),
                ),
                if (widget.item.isVideo) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _link,
                    keyboardType: TextInputType.url,
                    onChanged: (_) {
                      if (_linkError != null) setState(() => _linkError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Link video pentru display (opțional)',
                      hintText: 'https://…/IMG_8677.mp4',
                      helperText: 'Link direct către fișierul video. Displayul îl redă '
                          'de acolo, în loc de assets/sound_video/.',
                      helperMaxLines: 2,
                      errorText: _linkError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // ── tăiere ──────────────────────────────────────────────────
                Text('Tăiere (non-distructivă)', style: t.label),
                RangeSlider(
                  values: RangeValues(
                    _start.clamp(0, maxMs).toDouble(),
                    _end.clamp(0, maxMs).toDouble(),
                  ),
                  min: 0,
                  max: maxMs.toDouble(),
                  onChanged: (v) => setState(() {
                    _start = v.start.round();
                    _end = v.end.round();
                  }),
                ),
                Row(children: [
                  Text('Start ${formatClock(_start)}', style: t.caption),
                  const Spacer(),
                  Text('Durată ${formatClock((_end - _start).clamp(0, maxMs).toInt())}',
                      style: t.caption),
                  const Spacer(),
                  Text('Sfârșit ${formatClock(_end)}', style: t.caption),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: active ? () => _setFromPlayhead(start: true) : null,
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Setează start aici'),
                  ),
                  OutlinedButton.icon(
                    onPressed: active ? () => _setFromPlayhead(start: false) : null,
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: const Text('Setează sfârșit aici'),
                  ),
                ]),
                if (!active)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Pornește sunetul ca să poți marca punctele în timpul redării.',
                        style: t.caption),
                  ),
                const SizedBox(height: 16),

                // ── volum ───────────────────────────────────────────────────
                Text('Volum de bază: ${(_volume * 100).round()}%', style: t.label),
                Slider(value: _volume, onChanged: (v) => setState(() => _volume = v)),
                Text('Nivel pentru „Fade la nivel”: ${(_target * 100).round()}%',
                    style: t.label),
                Slider(value: _target, onChanged: (v) => setState(() => _target = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Buclă'),
                  value: _loop,
                  onChanged: (v) => setState(() => _loop = v),
                ),
                const SizedBox(height: 8),

                // ── fade-uri ────────────────────────────────────────────────
                Text('Fade-uri', style: t.label),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(
                    width: 240,
                    child: _fadeDropdown('Fade-in la pornire', _fadeIn, _fadeInChoices,
                        (v) => setState(() => _fadeIn = v ?? 0)),
                  ),
                  SizedBox(
                    width: 240,
                    child: _fadeDropdown('Fade-out', _fadeOut, _fadeChoices,
                        (v) => setState(() => _fadeOut = v)),
                  ),
                  SizedBox(
                    width: 240,
                    child: _fadeDropdown('Fade la nivel / normal', _fadeTo, _fadeChoices,
                        (v) => setState(() => _fadeTo = v)),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── culoare ─────────────────────────────────────────────────
                if (!widget.item.isVideo) ...[
                  Text('Culoare', style: t.label),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final c in const <int>[
                      0xFF6C63FF, 0xFF00D9A3, 0xFFFF5468, 0xFFFFB020,
                      0xFF3DA5FF, 0xFFE056FF, 0xFF7ED957,
                    ])
                      Semantics(
                        button: true,
                        selected: _color == c,
                        label: 'Culoare',
                        child: InkWell(
                          onTap: () => setState(() => _color = c),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _color == c ? Colors.white : Colors.transparent,
                                  width: 2),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 16),
                ],

                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Anulează'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Salvează'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}