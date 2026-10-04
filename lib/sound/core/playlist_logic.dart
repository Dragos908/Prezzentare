// lib/sound/core/playlist_logic.dart
//
// Logica „Următorul / Anterior” și auto-avans. DART PUR.

import 'models.dart';

class NeighborResult {
  /// Id-ul sunetului găsit, sau null dacă suntem la capăt (și bucla e oprită).
  final String? id;

  /// True dacă s-a ajuns la capătul listei și nu există sunet de pornit.
  final bool atEdge;

  /// True dacă s-a trecut de la un capăt la celălalt (buclă).
  final bool wrapped;

  const NeighborResult(this.id, {this.atEdge = false, this.wrapped = false});
}

/// Vecinul lui [currentId] în ordinea [orderedIds], în direcția [direction]
/// (+1 = următorul, −1 = anteriorul).
///
/// • fără sunet curent (sau dispărut din listă): +1 → primul, −1 → ultimul;
/// • la capăt: cu [loop] trece la celălalt capăt, altfel întoarce atEdge.
NeighborResult neighbor({
  required List<String> orderedIds,
  required String? currentId,
  required int direction,
  required bool loop,
}) {
  if (orderedIds.isEmpty) return const NeighborResult(null, atEdge: true);
  final dir = direction >= 0 ? 1 : -1;

  final idx = currentId == null ? -1 : orderedIds.indexOf(currentId);
  if (idx < 0) {
    return NeighborResult(dir > 0 ? orderedIds.first : orderedIds.last);
  }

  final n = idx + dir;
  if (n >= 0 && n < orderedIds.length) return NeighborResult(orderedIds[n]);

  if (loop && orderedIds.length > 1) {
    return NeighborResult(
      dir > 0 ? orderedIds.first : orderedIds.last,
      wrapped: true,
    );
  }
  return const NeighborResult(null, atEdge: true);
}

/// Ordinea pad-urilor: după sortOrder, apoi după data creării, apoi după id.
List<SoundItem> sortedItems(Iterable<SoundItem> items) {
  final list = List<SoundItem>.of(items);
  list.sort((a, b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    if (c != 0) return c;
    final d = a.createdAt.compareTo(b.createdAt);
    if (d != 0) return d;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// La sfârșitul natural al unui sunet: pornim următorul doar dacă auto-avansul e
/// activ și sunetul nu rulează în buclă.
bool shouldAutoAdvance({
  required bool autoAdvance,
  required bool itemLoops,
  required bool endedNaturally,
}) =>
    autoAdvance && endedNaturally && !itemLoops;

/// Durata efectivă a unei rampe: valoarea sunetului, altfel cea implicită (0,5–30 s).
int resolveFadeMs({required int? perItem, required int fallback}) {
  final v = perItem ?? fallback;
  if (v < 0) return 0;
  return v > 30000 ? 30000 : v;
}
