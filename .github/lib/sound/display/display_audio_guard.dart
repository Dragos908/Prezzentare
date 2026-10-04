// lib/sound/display/display_audio_guard.dart
//
// DisplayAudioGuard — garanția că pagina de prezentare NU scoate sunet cât timp
// setarea `displayAudioMuted` e activă (implicit ACTIVĂ, chiar înainte să sosească
// setările din baza de date: fail-safe).
//
// Bariere (de la cea mai apropiată de player spre sistem):
//   1. la creare (DisplayMediaFactory) playerul primește volum 0;
//   2. un listener pe fiecare controller re-forțează 0 la ORICE schimbare de stare
//      (initialize / play / setVolume);
//   3. audit periodic la ~1 s: citește volumul real și re-forțează;
//   4. embeduri: mutate prin API-ul lor (ex. YouTube postMessage). Cele care nu
//      pot fi mutate garantat (iframe-uri externe) sunt numărate și raportate;
//      opțional (`blockUnmutableEmbeds`) nu se încarcă deloc;
//   5. la nivel de sistem, unde platforma permite (browser cu --mute-audio) — vezi README.

import 'dart:async';

import 'package:flutter/foundation.dart';

abstract class GuardedMedia {
  String get label;

  /// Volumul curent citit din API-ul playerului (0 dacă nu poate fi citit).
  double readVolume();
  void forceMute();
}

class EmbedHandle {
  final String label;

  /// True dacă embedul poate fi mutat prin API (YouTube / Vimeo cu JS API).
  final bool canMute;
  final void Function()? mute;

  const EmbedHandle({required this.label, required this.canMute, this.mute});
}

class GuardReport {
  final bool active;
  final int players;
  final int unmuted;
  final int embedsUnmutable;
  const GuardReport({
    required this.active,
    required this.players,
    required this.unmuted,
    required this.embedsUnmutable,
  });
}

class DisplayAudioGuard {
  DisplayAudioGuard();

  /// Instanța folosită de pagina de prezentare.
  static final DisplayAudioGuard instance = DisplayAudioGuard();

  /// Implicit true: dacă setările nu au ajuns încă, displayul rămâne mut.
  final ValueNotifier<bool> mutedNotifier = ValueNotifier<bool>(true);

  /// Dacă e true (și displayul e mut), embedurile care nu pot fi mutate nu se încarcă.
  final ValueNotifier<bool> blockUnmutable = ValueNotifier<bool>(false);

  final Set<GuardedMedia> _media = <GuardedMedia>{};
  final Set<EmbedHandle> _embeds = <EmbedHandle>{};
  Timer? _timer;

  bool get muted => mutedNotifier.value;

  /// Volumul permis pentru un player: 0 cât timp displayul e mut.
  double effectiveVolume(double requested) {
    if (muted) return 0.0;
    return requested.clamp(0.0, 1.0).toDouble();
  }

  void setMuted(bool value) {
    mutedNotifier.value = value;
    if (value) enforce();
  }

  void setBlockUnmutable(bool value) => blockUnmutable.value = value;

  // ── playere ───────────────────────────────────────────────────────────────
  void register(GuardedMedia m) {
    _media.add(m);
    if (muted) _safeMute(m);
  }

  void unregister(GuardedMedia m) => _media.remove(m);

  // ── embeduri ──────────────────────────────────────────────────────────────
  void registerEmbed(EmbedHandle e) {
    _embeds.add(e);
    if (muted && e.canMute) e.mute?.call();
  }

  void unregisterEmbed(EmbedHandle e) => _embeds.remove(e);

  /// True dacă un embed care NU poate fi mutat trebuie blocat acum.
  bool get shouldBlockUnmutableEmbeds => muted && blockUnmutable.value;

  // ── aplicare + audit ──────────────────────────────────────────────────────
  void _safeMute(GuardedMedia m) {
    try {
      m.forceMute();
    } catch (_) {
      // controller deja eliberat: îl uităm
      _media.remove(m);
    }
  }

  /// Forțează volum 0 pe toate playerele și mută toate embedurile mutabile.
  void enforce() {
    for (final m in List<GuardedMedia>.of(_media)) {
      _safeMute(m);
    }
    for (final e in List<EmbedHandle>.of(_embeds)) {
      if (e.canMute) {
        try {
          e.mute?.call();
        } catch (_) {}
      }
    }
  }

  /// Un audit: întoarce câte playere erau NEMUTATE și le re-forțează.
  int audit() {
    if (!muted) return 0;
    var found = 0;
    for (final m in List<GuardedMedia>.of(_media)) {
      double v;
      try {
        v = m.readVolume();
      } catch (_) {
        _media.remove(m);
        continue;
      }
      if (v > 0.0001) {
        found++;
        _safeMute(m);
      }
    }
    for (final e in List<EmbedHandle>.of(_embeds)) {
      if (e.canMute) {
        try {
          e.mute?.call();
        } catch (_) {}
      }
    }
    return found;
  }

  void startAudit([Duration every = const Duration(seconds: 1)]) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => audit());
  }

  void stopAudit() {
    _timer?.cancel();
    _timer = null;
  }

  GuardReport report() {
    var audible = 0;
    if (muted) {
      for (final m in _media) {
        try {
          if (m.readVolume() > 0.0001) audible++;
        } catch (_) {}
      }
    }
    final unmutable = _embeds.where((e) => !e.canMute).length;
    return GuardReport(
      active: muted,
      players: _media.length,
      unmuted: audible,
      embedsUnmutable: unmutable,
    );
  }

  /// Doar pentru teste.
  @visibleForTesting
  int get registeredPlayers => _media.length;

  void dispose() {
    stopAudit();
    _media.clear();
    _embeds.clear();
  }
}
