// lib/core/drive_link.dart
//
// Linkuri Google Drive pentru video. DART PUR (fără Flutter): se testează direct.
//
// Baza de date păstrează linkul AȘA CUM L-A COPIAT utilizatorul din Drive, de
// exemplu https://drive.google.com/file/d/ID/view. Un astfel de link deschide o
// PAGINĂ web, nu fișierul video, deci un <video> nu poate reda direct de la el.
// De aceea, în momentul redării, linkul se transformă într-un URL de descărcare
// directă. Transformarea se face aici, într-un singur loc, și o folosesc și
// video-urile din biblioteca de sunete, și cele din slide-uri.
//
// În Drive: fișierul trebuie partajat „Oricine are linkul” (Vizualizator).
//
// Cheie API (opțională). Fără cheie se folosește endpoint-ul public de descărcare
// al Drive, pe care Google îl poate limita (cote de descărcări). Cu o cheie
// (Google Drive API activat în proiectul Google Cloud) se folosește API-ul
// oficial, mai stabil la fișiere mari sau la multe redări:
//   flutter build web --dart-define=DRIVE_API_KEY=cheia_ta

class DriveLink {
  DriveLink._();

  /// Cheia API Google, dată la build cu `--dart-define=DRIVE_API_KEY=...`.
  /// Goală = se folosește descărcarea publică, fără cheie.
  static const String apiKey = String.fromEnvironment('DRIVE_API_KEY');

  static const Set<String> _hosts = <String>{
    'drive.google.com',
    'drive.usercontent.google.com',
    'docs.google.com',
  };

  /// ID-urile Drive: litere, cifre, `_` și `-` (de regulă 25–45 de caractere).
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{10,}$');

  /// `/file/d/ID/view` și varianta cu cont: `/file/u/0/d/ID/view`.
  static final RegExp _filePath = RegExp(r'/file/(?:u/\d+/)?d/([A-Za-z0-9_-]+)');

  static final RegExp _folderPath = RegExp(r'/folders/');

  /// [link] ca Uri http(s) cu gazdă, sau null.
  static Uri? _httpUri(String link) {
    final u = Uri.tryParse(link.trim());
    if (u == null || !u.hasScheme) return null;
    final scheme = u.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (u.host.isEmpty) return null;
    return u;
  }

  /// True dacă [link] e un link http(s) către Google Drive / Docs.
  static bool isDrive(String link) {
    final u = _httpUri(link);
    return u != null && _hosts.contains(u.host.toLowerCase());
  }

  /// ID-ul fișierului dintr-un link Drive. Recunoaște:
  ///   • https://drive.google.com/file/d/ID/view  (și /preview, /edit, ?usp=sharing)
  ///   • https://drive.google.com/file/u/0/d/ID/view
  ///   • https://drive.google.com/open?id=ID
  ///   • https://drive.google.com/uc?id=ID&export=download
  ///   • https://drive.usercontent.google.com/download?id=ID&export=download
  /// null = nu e link Drive sau nu e link de FIȘIER (ex. folder).
  static String? idOf(String link) {
    final u = _httpUri(link);
    if (u == null || !_hosts.contains(u.host.toLowerCase())) return null;

    final fromPath = _filePath.firstMatch(u.path)?.group(1);
    if (fromPath != null && _idPattern.hasMatch(fromPath)) return fromPath;

    String? fromQuery;
    try {
      fromQuery = u.queryParameters['id'];
    } catch (_) {
      fromQuery = null; // parametri cu codare procentuală stricată
    }
    if (fromQuery != null && _idPattern.hasMatch(fromQuery)) return fromQuery;
    return null;
  }

  /// URL-ul pe care îl poate reda un player (<video>):
  ///   • link Drive → URL de descărcare directă (cu cheie API, dacă există);
  ///   • orice alt link → neschimbat (se presupune link direct către fișier).
  static String playableUrl(String link) {
    final id = idOf(link);
    if (id == null) return link.trim();
    if (apiKey.isNotEmpty) {
      return 'https://www.googleapis.com/drive/v3/files/$id'
          '?alt=media&key=${Uri.encodeQueryComponent(apiKey)}';
    }
    // `confirm=t` sare peste pagina „Google Drive nu poate scana fișierul”, care
    // apare la fișierele mari și nu e video.
    return 'https://drive.usercontent.google.com/download'
        '?id=$id&export=download&confirm=t';
  }

  /// null = valid (și gol: câmpul e opțional). Altfel, mesajul de eroare în română.
  static String? validate(String? input) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return null;

    final u = _httpUri(s);
    if (u == null) return 'Linkul trebuie să înceapă cu https://';
    if (!_hosts.contains(u.host.toLowerCase())) return null; // link direct, alt server
    if (idOf(s) != null) return null;

    if (_folderPath.hasMatch(u.path)) {
      return 'Acesta e linkul unui folder. Deschide fișierul video în Drive și '
          'copiază linkul lui (Partajează → Copiază linkul).';
    }
    return 'Nu găsesc ID-ul fișierului în linkul Google Drive. Folosește un link '
        'de forma https://drive.google.com/file/d/ID/view';
  }
}
