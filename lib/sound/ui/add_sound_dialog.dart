// lib/sound/ui/add_sound_dialog.dart
//
// Adăugare de sunete: selector de fișiere (multiple) + drag & drop, tip detectat
// automat (editabil), nume editabil, validare tip / mărime cu erori clare.
// Progresul importului se vede în bara de import din dock (importul continuă și
// dacă închizi dialogul).

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/drive_link.dart';
import '../../core/theme/app_tokens.dart';
import '../core/models.dart';
import '../data/sound_library.dart';
import 'video_link_field.dart';

class _Draft {
  final PickedMedia media;
  SoundType type;
  final TextEditingController name;

  /// Linkul Google Drive al video-ului (doar pentru tipul video; opțional).
  final TextEditingController link = TextEditingController();
  final String? error;

  _Draft(this.media)
      : type = SoundLibrary.detectType(media) ?? SoundType.audio,
        name = TextEditingController(text: media.baseName),
        error = SoundLibrary.validate(media);

  /// Linkul e valid (sau gol / nefolosit, dacă sunetul nu e video).
  bool get linkOk => type != SoundType.video || DriveLink.validate(link.text) == null;

  bool get canImport => error == null && linkOk;

  void dispose() {
    name.dispose();
    link.dispose();
  }
}

Future<void> showAddSoundDialog(BuildContext context, SoundLibrary library,
    {bool enableDrop = true}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddSoundDialog(library: library, enableDrop: enableDrop),
  );
}

class _AddSoundDialog extends StatefulWidget {
  final SoundLibrary library;
  final bool enableDrop;
  const _AddSoundDialog({required this.library, required this.enableDrop});

  @override
  State<_AddSoundDialog> createState() => _AddSoundDialogState();
}

class _AddSoundDialogState extends State<_AddSoundDialog> {
  /// Tipurile acceptate (audio + video).
  static final XTypeGroup _group = XTypeGroup(
    label: 'Audio și video',
    extensions: <String>[...SoundLibrary.audioExt, ...SoundLibrary.videoExt],
  );

  final List<_Draft> _drafts = <_Draft>[];
  bool _hover = false;
  bool _reading = false;
  String? _pickError;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _reading = true;
      _pickError = null;
    });
    try {
      final files = await openFiles(acceptedTypeGroups: <XTypeGroup>[_group]);
      await _addFiles(files);
    } catch (e) {
      _pickError = 'Nu am putut citi fișierele: $e';
    }
    if (mounted) setState(() => _reading = false);
  }

  Future<void> _onDrop(DropDoneDetails d) async {
    setState(() => _reading = true);
    await _addFiles(d.files);
    if (mounted) setState(() => _reading = false);
  }

  /// Citește fișierele în memorie (după verificarea mărimii, ca un fișier uriaș să nu
  /// umple memoria înainte de validare).
  Future<void> _addFiles(List<XFile> files) async {
    for (final f in files) {
      try {
        final len = await f.length();
        if (len > SoundLibrary.maxBytes) {
          _pickError = 'Fișierul „${f.name}” depășește '
              '${SoundLibrary.maxBytes ~/ (1024 * 1024)} MB.';
          continue;
        }
        _drafts.add(_Draft(
            PickedMedia(name: f.name, bytes: await f.readAsBytes(), mime: f.mimeType)));
      } catch (e) {
        _pickError = 'Nu am putut citi „${f.name}”: $e';
      }
    }
  }

  void _import() {
    for (final d in _drafts.where((d) => d.canImport)) {
      widget.library.importFiles(
        <PickedMedia>[d.media],
        forceType: d.type,
        nameOverride: d.name.text,
        videoLink: d.type == SoundType.video ? d.link.text : null,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final valid = _drafts.where((d) => d.canImport).length;

    Widget zone = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hover ? t.accent.withOpacity(0.14) : t.surfaceHigh,
        borderRadius: BorderRadius.circular(t.rMd),
        border: Border.all(color: _hover ? t.accent : t.border),
      ),
      child: Column(
        children: [
          Icon(Icons.library_music_rounded, size: 34, color: t.accent2),
          const SizedBox(height: 8),
          Text('Trage fișiere aici sau alege-le din calculator', style: t.body),
          const SizedBox(height: 4),
          Text('Audio: mp3, wav, ogg, m4a, flac · Video: mp4, mov, webm  (max. 700 MB)',
              style: t.caption, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
              'Video: imaginea de pe display vine din Google Drive. Urcă fișierul și în '
              'Drive (partajat „Oricine are linkul”) și lipește linkul sub fișier.',
              style: t.caption, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _reading ? null : _pick,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Alege fișiere'),
          ),
        ],
      ),
    );
    if (widget.enableDrop) {
      zone = DropTarget(
        onDragEntered: (_) => setState(() => _hover = true),
        onDragExited: (_) => setState(() => _hover = false),
        onDragDone: (d) {
          setState(() => _hover = false);
          _onDrop(d);
        },
        child: zone,
      );
    }

    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.rLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Adaugă sunet', style: t.title)),
                IconButton(
                  tooltip: 'Închide',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 12),
              zone,
              if (_pickError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_pickError!, style: TextStyle(color: t.danger)),
                ),
              const SizedBox(height: 12),
              Flexible(
                child: _drafts.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _drafts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DraftTile(
                          draft: _drafts[i],
                          onType: (v) => setState(() => _drafts[i].type = v),
                          onLinkChanged: () => setState(() {}),
                          onRemove: () => setState(() {
                            _drafts[i].dispose();
                            _drafts.removeAt(i);
                          }),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Anulează'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: valid == 0 ? null : _import,
                    icon: const Icon(Icons.upload_rounded),
                    label: Text(valid <= 1 ? 'Importă' : 'Importă $valid fișiere'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  final _Draft draft;
  final ValueChanged<SoundType> onType;
  final VoidCallback onLinkChanged;
  final VoidCallback onRemove;
  const _DraftTile({
    required this.draft,
    required this.onType,
    required this.onLinkChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final mb = (draft.media.bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: BorderRadius.circular(t.rSm + 2),
        border: Border.all(color: draft.error == null ? t.border : t.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: draft.name,
                enabled: draft.error == null,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Nume', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            if (draft.error == null)
              SegmentedButton<SoundType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: SoundType.audio,
                      icon: Icon(Icons.music_note_rounded, size: 16),
                      label: Text('Audio')),
                  ButtonSegment(
                      value: SoundType.video,
                      icon: Icon(Icons.movie_rounded, size: 16),
                      label: Text('Video')),
                ],
                selected: <SoundType>{draft.type},
                onSelectionChanged: (s) => onType(s.first),
              ),
            IconButton(
              tooltip: 'Scoate din listă',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onRemove,
            ),
          ]),
          const SizedBox(height: 4),
          Text(draft.error ?? '${draft.media.name} · $mb MB',
              style: draft.error == null ? t.caption : TextStyle(color: t.danger, fontSize: 12)),
          if (draft.error == null && draft.type == SoundType.video) ...[
            const SizedBox(height: 10),
            VideoLinkField(controller: draft.link, onChanged: onLinkChanged),
          ],
        ],
      ),
    );
  }
}
