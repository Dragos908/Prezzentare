// lib/sound/ui/manage_sounds_sheet.dart
//
// Gestionarea bibliotecii: reordonare prin drag, redenumire, editare, ștergere
// (cu confirmare), re-adăugarea fișierelor lipsă, spațiul ocupat + golire cache.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../audio/audio_engine.dart';
import '../core/models.dart';
import '../data/sound_library.dart';
import 'sound_edit_sheet.dart';

Future<void> showManageSoundsSheet(
  BuildContext context, {
  required SoundLibrary library,
  required AudioEngine engine,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ManageSoundsDialog(library: library, engine: engine),
  );
}

/// Alege un fișier și îl re-atașează unui sunet cu fișier local lipsă.
Future<void> reattachFile(
    BuildContext context, SoundLibrary library, SoundItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final f = await openFile(acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(
        label: 'Audio și video',
        extensions: <String>[...SoundLibrary.audioExt, ...SoundLibrary.videoExt],
      ),
    ]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    await library.reattach(
        item.id, PickedMedia(name: f.name, bytes: bytes, mime: f.mimeType));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class ManageSoundsDialog extends StatelessWidget {
  final SoundLibrary library;
  final AudioEngine engine;
  const ManageSoundsDialog({super.key, required this.library, required this.engine});

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Șterge')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _rename(BuildContext context, SoundItem it) async {
    final c = TextEditingController(text: it.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redenumește'),
        content: TextField(controller: c, autofocus: true,
            onSubmitted: (s) => Navigator.pop(ctx, s)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvează')),
        ],
      ),
    );
    c.dispose();
    if (v != null) await library.rename(it.id, v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.rLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Gestionează sunetele', style: t.title)),
                IconButton(
                  tooltip: 'Închide',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
              Text('Trage de mâner pentru a schimba ordinea pad-urilor.', style: t.caption),
              const SizedBox(height: 8),
              Flexible(
                child: ValueListenableBuilder<List<SoundItem>>(
                  valueListenable: library.items,
                  builder: (context, items, _) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('Nu există sunete.', style: t.label)),
                      );
                    }
                    return ValueListenableBuilder<Map<String, MediaHealth>>(
                      valueListenable: library.health,
                      builder: (context, health, _) => ReorderableListView.builder(
                        shrinkWrap: true,
                        buildDefaultDragHandles: false,
                        itemCount: items.length,
                        onReorder: (oldI, newI) {
                          final ids = items.map((e) => e.id).toList();
                          if (newI > oldI) newI -= 1;
                          ids.insert(newI, ids.removeAt(oldI));
                          library.reorder(ids);
                        },
                        itemBuilder: (context, i) {
                          final it = items[i];
                          final missing = health[it.id] == MediaHealth.missing;
                          // video fără link Google Drive: displayul nu are imagine
                          final noPicture = it.isVideo && it.videoUrl == null;
                          return ListTile(
                            key: ValueKey<String>(it.id),
                            contentPadding: EdgeInsets.zero,
                            leading: ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle_rounded),
                              ),
                            ),
                            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${it.isVideo ? 'Video' : 'Audio'} · ${formatClock(it.durationMs)}'
                              '${missing ? ' · fișier lipsă' : ''}'
                              '${noPicture ? ' · fără imagine pe display: lipsește linkul Google Drive '
                                  '(apasă „Editează” și lipește-l)' : ''}',
                              style: TextStyle(
                                  color: (missing || noPicture) ? t.warning : t.textLo),
                            ),
                            trailing: Wrap(children: [
                              if (missing)
                                IconButton(
                                  tooltip: 'Adaugă din nou fișierul',
                                  icon: Icon(Icons.refresh_rounded, color: t.warning),
                                  onPressed: () => reattachFile(context, library, it),
                                ),
                              IconButton(
                                tooltip: 'Redenumește',
                                icon: const Icon(Icons.drive_file_rename_outline_rounded),
                                onPressed: () => _rename(context, it),
                              ),
                              IconButton(
                                tooltip: 'Editează',
                                icon: const Icon(Icons.tune_rounded),
                                onPressed: () => showSoundEditSheet(context,
                                    item: it, library: library, engine: engine),
                              ),
                              IconButton(
                                tooltip: 'Șterge',
                                icon: Icon(Icons.delete_outline_rounded, color: t.danger),
                                onPressed: () async {
                                  final ok = await _confirm(context, 'Ștergi „${it.name}”?',
                                      'Fișierul local va fi șters din browser, iar sunetul din '
                                      'listă. Video-ul din Google Drive nu este afectat.');
                                  if (!ok) return;
                                  await engine.stop(it.id, fadeMs: 0);
                                  engine.forget(it.id);
                                  await library.remove(it.id);
                                },
                              ),
                            ]),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 24),
              FutureBuilder<int>(
                future: library.usedBytes(),
                builder: (context, snap) {
                  final mb = ((snap.data ?? 0) / (1024 * 1024)).toStringAsFixed(1);
                  return Row(children: [
                    Expanded(child: Text('Spațiu local ocupat: $mb MB', style: t.caption)),
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await _confirm(context, 'Golești cache-ul local?',
                            'Fișierele locale vor fi șterse; sunetele rămân în listă și trebuie re-adăugate.');
                        if (ok) {
                          await engine.stopAll();
                          await library.clearLocalCache();
                        }
                      },
                      icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                      label: const Text('Golește cache'),
                    ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
