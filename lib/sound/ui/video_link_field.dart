// lib/sound/ui/video_link_field.dart
//
// Câmpul „Link video Google Drive”, folosit la adăugarea și la editarea unui sunet
// video: validare pe loc (link de folder, fără ID, fără https://) și butonul
// „Testează linkul”, care încarcă video-ul exact cum îl va încărca displayul și
// spune dacă se poate reda. Linkul se salvează de către dialogul care îl conține.

import 'package:flutter/material.dart';

import '../../core/drive_link.dart';
import '../../core/theme/app_tokens.dart';
import '../data/video_link_probe.dart';

class VideoLinkField extends StatefulWidget {
  final TextEditingController controller;

  /// Apelat la fiecare modificare a textului (dialogul își poate recalcula starea,
  /// de ex. dacă butonul „Importă” e activ).
  final VoidCallback? onChanged;

  const VideoLinkField({super.key, required this.controller, this.onChanged});

  @override
  State<VideoLinkField> createState() => _VideoLinkFieldState();
}

class _VideoLinkFieldState extends State<VideoLinkField> {
  bool _testing = false;
  VideoLinkProbeResult? _result;

  /// Crește la fiecare test și la fiecare modificare a textului: rezultatul unui
  /// test mai vechi nu are voie să apară lângă un link schimbat între timp.
  int _run = 0;

  Future<void> _test() async {
    final run = ++_run;
    final link = widget.controller.text.trim();
    setState(() {
      _testing = true;
      _result = null;
    });
    final r = await probeVideoLink(link);
    if (!mounted || run != _run) return;
    setState(() {
      _testing = false;
      _result = r;
    });
  }

  void _changed(String _) {
    _run++;
    setState(() {
      _testing = false;
      _result = null;
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final text = widget.controller.text.trim();
    final error = DriveLink.validate(text);
    final canTest = text.isNotEmpty && error == null && !_testing;
    final r = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.url,
          onChanged: _changed,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Link video Google Drive (pentru display)',
            hintText: 'https://drive.google.com/file/d/ID/view',
            helperText: 'Fișierul din Drive trebuie partajat „Oricine are linkul” (cu '
                'descărcarea permisă). Linkul se salvează în baza de date, iar displayul '
                'redă video-ul de acolo.',
            helperMaxLines: 3,
            errorText: error,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: canTest ? _test : null,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: Text(_testing ? 'Se verifică…' : 'Testează linkul'),
          ),
        ),
        if (r != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: r.ok ? t.success : t.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.message,
                    style: TextStyle(
                      color: r.ok ? t.success : t.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
