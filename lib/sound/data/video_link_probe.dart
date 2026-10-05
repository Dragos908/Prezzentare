// lib/sound/data/video_link_probe.dart
//
// „Testează linkul”: încarcă video-ul dintr-un link (Google Drive sau link direct)
// exact cum îl va încărca displayul, adică din URL-ul transformat de DriveLink, și
// spune dacă browserul îl poate reda. Se încarcă doar metadatele; redarea NU
// pornește, deci nu se aude nimic.
//
// Se rulează de pe control, la introducerea linkului: o greșeală (fișier
// nepartajat, link de folder, format nesuportat) se vede imediat, nu abia pe
// display, în timpul evenimentului.

import 'dart:async';

import 'package:video_player/video_player.dart';

import '../../core/drive_link.dart';

class VideoLinkProbeResult {
  final bool ok;
  final String message;
  const VideoLinkProbeResult({required this.ok, required this.message});
}

String _clock(Duration d) {
  final total = d.inSeconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _shorten(Object e) {
  final raw = e.toString().replaceAll('\n', ' ').trim();
  return raw.length > 140 ? '${raw.substring(0, 140)}…' : raw;
}

Future<VideoLinkProbeResult> probeVideoLink(
  String link, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final clean = link.trim();
  if (clean.isEmpty) {
    return const VideoLinkProbeResult(ok: false, message: 'Lipește mai întâi un link.');
  }
  final invalid = DriveLink.validate(clean);
  if (invalid != null) return VideoLinkProbeResult(ok: false, message: invalid);

  final uri = Uri.tryParse(DriveLink.playableUrl(clean));
  if (uri == null) {
    return const VideoLinkProbeResult(ok: false, message: 'Link invalid.');
  }

  final controller = VideoPlayerController.networkUrl(uri);
  try {
    // mut ÎNAINTE de initialize (la fel ca pe display); oricum nu se pornește redarea
    unawaited(controller.setVolume(0));
    await controller.initialize().timeout(timeout);
    final v = controller.value;
    final w = v.size.width.round();
    final h = v.size.height.round();
    return VideoLinkProbeResult(
      ok: true,
      message: 'Se poate reda · ${_clock(v.duration)} · $w×$h',
    );
  } on TimeoutException {
    return VideoLinkProbeResult(
      ok: false,
      message: 'Linkul nu a răspuns în ${timeout.inSeconds} s. Verifică conexiunea '
          'și că fișierul e partajat „Oricine are linkul”.',
    );
  } catch (e) {
    final hint = DriveLink.isDrive(clean)
        ? 'Verifică în Drive: fișierul trebuie partajat „Oricine are linkul” '
            '(Vizualizator), cu descărcarea permisă, să fie video (mp4 H.264 + AAC) '
            'și să nu fi depășit limita de descărcări.'
        : 'Verifică linkul și formatul video (mp4 H.264 + AAC).';
    return VideoLinkProbeResult(
      ok: false,
      message: 'Browserul nu poate reda linkul. $hint (${_shorten(e)})',
    );
  } finally {
    try {
      await controller.dispose();
    } catch (_) {/* deja eliberat */}
  }
}
