// lib/core/backup_service.dart
//
// Oglindește (best-effort) fiecare scriere din Realtime Database
// într-o colecție Firestore, ca backup redundant.
// Eșecurile de backup NU blochează și NU întârzie scrierea principală în RTDB —
// e strict o rețea de siguranță, nu o dependință critică.

import 'package:cloud_firestore/cloud_firestore.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Map<String, dynamic>> _col;
  bool _initialized = false;

  void init(String project) {
    if (_initialized) return;
    _initialized = true;
    _col = _firestore.collection('rtdb_backup_$project');
  }

  /// Backup pentru o scriere punctuală (set/update pe un singur câmp/nod).
  Future<void> backupField(String path, dynamic value) async {
    if (!_initialized) return;
    try {
      await _col.doc(path.replaceAll('/', '_')).set({
        'path':      path,
        'value':     value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('BackupService: eșec backup pentru "$path" — $e');
    }
  }

  /// Backup pentru o stare completă (snapshot), util la reinițializări.
  Future<void> backupSnapshot(Map<String, dynamic> fullState) async {
    if (!_initialized) return;
    try {
      await _col.doc('_full_state').set({
        ...fullState,
        'backedUpAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('BackupService: eșec backup snapshot — $e');
    }
  }

  /// Restaurare manuală (ex. dacă RTDB pică) — citește ultimul snapshot complet.
  Future<Map<String, dynamic>?> restoreFullState() async {
    if (!_initialized) return null;
    try {
      final snap = await _col.doc('_full_state').get();
      return snap.data();
    } catch (e) {
      // ignore: avoid_print
      print('BackupService: eșec restore — $e');
      return null;
    }
  }
}
