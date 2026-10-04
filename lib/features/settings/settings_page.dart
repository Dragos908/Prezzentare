// lib/features/settings/settings_page.dart
//
// Pagina separată de Setări (/settings). Toate setările se salvează AUTOMAT în baza de
// date (debounce 500 ms + confirmare discretă „Salvat”) și ajung în timp real la
// display. Secțiuni: Display & sunet · Sincronizare · Sunet & fade · Bibliotecă
// sunete · Aspect · Diagnostic.
//
// Accesul: butonul ⚙ din bara de sus a paginii de control (fără reintroducerea
// parolei) sau ruta /settings (protejată de aceeași parolă).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../../sound/audio/control_sound_system.dart';
import '../../sound/core/models.dart';
import '../../sound/data/settings_repository.dart';
import '../../sound/data/web_blob.dart';
import '../../sound/ui/manage_sounds_sheet.dart';
import '../../sound/ui/sound_shortcuts.dart';

// Taste deja folosite de pagina de control (nu pot fi realocate sunetelor).
const Set<String> _reservedKeys = <String>{
  't', 'o', 'p', 'r', 'a', 'enter', 'space', 'home', 'end', 'pageup', 'pagedown',
};

const List<(String, String)> _shortcutActions = <(String, String)>[
  ('stopAll', 'Oprește tot'),
  ('fadeOut', 'Fade-out'),
  ('fadeToLevel', 'Fade la nivel'),
  ('next', 'Următorul'),
  ('previous', 'Anterior'),
  ('restart', 'Restart'),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ControlSoundSystem sys = ControlSoundSystem.instance;
  final List<GlobalKey> _keys = List<GlobalKey>.generate(6, (_) => GlobalKey());
  static const List<String> _titles = <String>[
    'Display & sunet',
    'Sincronizare',
    'Sunet & fade',
    'Bibliotecă sunete',
    'Aspect',
    'Diagnostic',
  ];

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(sys.start()); // idempotent
    // numerele din Diagnostic se reîmprospătează la 1 s
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(sys.settings.flush()); // nu pierde o modificare recentă
    super.dispose();
  }

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/control');
    }
  }

  void _jump(int i) {
    final ctx = _keys[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _set(AppSettings Function(AppSettings s) f) => sys.settings.update(f);

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: IconButton(
          tooltip: 'Înapoi la control',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: Text('Setări', style: t.title),
        actions: [
          ValueListenableBuilder<SaveStatus>(
            valueListenable: sys.settings.status,
            builder: (context, st, _) {
              final (IconData icon, String text, Color c) = switch (st) {
                SaveStatus.saving => (Icons.sync_rounded, 'Se salvează…', t.textMid),
                SaveStatus.saved => (Icons.check_circle_rounded, 'Salvat', t.success),
                SaveStatus.error =>
                  (Icons.error_outline_rounded, 'Nu s-a putut salva', t.danger),
                SaveStatus.idle => (Icons.cloud_done_outlined, 'Salvare automată', t.textLo),
              };
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: StatusPill(icon: icon, text: text, color: c)),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: sys.settings.settings,
        builder: (context, s, _) => Column(
          children: [
            // navigare rapidă între secțiuni
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _titles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ActionChip(
                  label: Text(_titles[i]),
                  onPressed: () => _jump(i),
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section(0, Icons.cast_rounded, _displaySection(context, s)),
                          _section(1, Icons.sync_alt_rounded, _syncSection(s)),
                          _section(2, Icons.graphic_eq_rounded, _fadeSection(s)),
                          _section(3, Icons.library_music_rounded, _librarySection(context)),
                          _section(4, Icons.palette_outlined, _lookSection(s)),
                          _section(5, Icons.monitor_heart_outlined, _diagSection(context, s)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(int i, IconData icon, Widget child) => Padding(
        key: _keys[i],
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(title: _titles[i], icon: icon, child: child),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // 1) Display & sunet
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _displaySection(BuildContext context, AppSettings s) {
    final t = context.tk;
    return ValueListenableBuilder<DisplayStatus>(
      valueListenable: sys.displayStatus,
      builder: (context, d, _) {
        final online = d.isOnline(sys.serverNowMs);
        Widget status;
        if (!online) {
          status = StatusPill(
              icon: Icons.cloud_off_rounded, text: 'Display offline', color: t.warning);
        } else if (d.guardActive && d.guardUnmuted == 0) {
          status = StatusPill(
              icon: Icons.volume_off_rounded,
              text: 'Display: sunet blocat ✓ (${d.guardPlayers} playere)',
              color: t.success);
        } else if (d.guardActive) {
          status = StatusPill(
              icon: Icons.warning_amber_rounded,
              text: 'Atenție: ${d.guardUnmuted} playere nemutate (se corectează)',
              color: t.danger);
        } else {
          status = StatusPill(
              icon: Icons.volume_up_rounded,
              text: 'Display: sunet PERMIS',
              color: t.warning);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SwitchRow(
              title: 'Display mut (fără niciun sunet)',
              subtitle:
                  'Cât timp e activ, pagina de prezentare nu redă niciun sunet: nici video, nici '
                  'audio, nici embeduri. Efect în ≤ 1 s, fără repornire. Sunetele video din dock '
                  'sunt mute pe display indiferent de această setare.',
              value: s.displayAudioMuted,
              onChanged: (v) => _set((x) => x.copyWith(displayAudioMuted: v)),
            ),
            const SizedBox(height: 8),
            status,
            if (online && d.embedsUnmutable > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${d.embedsUnmutable} embed(uri) extern(e) (iframe) nu pot fi mutate din aplicație. '
                'Pentru garanție completă pornește browserul displayului cu --mute-audio '
                'sau activează blocarea de mai jos.',
                style: TextStyle(color: t.warning, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            _SwitchRow(
              title: 'Blochează embedurile care nu pot fi mutate',
              subtitle:
                  'Cât timp displayul e mut, iframe-urile externe nu se mai încarcă (în loc de ele '
                  'apare un ecran negru). Implicit oprit, ca să nu dispară conținutul proiectelor.',
              value: s.blockUnmutableEmbeds,
              onChanged: (v) => _set((x) => x.copyWith(blockUnmutableEmbeds: v)),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Dispozitiv de ieșire audio',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: Text(
                'Indisponibil pe Web: browserul folosește ieșirea implicită a sistemului. '
                'Alege boxele din setările sistemului / browserului.',
                style: t.caption,
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2) Sincronizare
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _syncSection(AppSettings s) {
    return Column(
      children: [
        _SliderRow(
          label: 'Decalaj audio ↔ video (av_sync_offset)',
          help: 'Pentru latențe (boxe Bluetooth, procesarea proiectorului). Folosește testul din Diagnostic.',
          value: s.avSyncOffsetMs,
          min: -2000,
          max: 2000,
          step: 10,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(avSyncOffsetMs: v)),
        ),
        _SliderRow(
          label: 'Start programat (lead)',
          help: 'Cât în avans se anunță pornirea. Mai mare = display mai sigur aliniat la start.',
          value: s.leadMs,
          min: 100,
          max: 3000,
          step: 50,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(leadMs: v)),
        ),
        _SliderRow(
          label: 'Prag seek (drift hard)',
          help: 'Peste acest drift, displayul sare direct la poziția corectă.',
          value: s.driftHardMs,
          min: 60,
          max: 1000,
          step: 10,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(driftHardMs: v)),
        ),
        _SliderRow(
          label: 'Prag ajustare fină (drift soft)',
          help: 'Între acest prag și cel de seek, displayul își ajustează viteza ±2–5 %.',
          value: s.driftSoftMs,
          min: 10,
          max: 200,
          step: 5,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(driftSoftMs: v)),
        ),
        _SliderRow(
          label: 'Heartbeat',
          help: 'La câte ms control-ul scrie poziția reală a audio în baza de date.',
          value: s.heartbeatMs,
          min: 250,
          max: 5000,
          step: 250,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(heartbeatMs: v)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3) Sunet & fade
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _fadeSection(AppSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SliderRow(
          label: 'Volum general (master)',
          value: (s.masterVolume * 100).round(),
          min: 0,
          max: 100,
          step: 1,
          unit: '%',
          onChanged: (v) {
            sys.engine.master.value = v / 100;
            _set((x) => x.copyWith(masterVolume: v / 100));
          },
        ),
        _SliderRow(
          label: 'Fade-in implicit',
          help: '0 = pornire directă.',
          value: s.defaultFadeInMs,
          min: 0,
          max: 30000,
          step: 500,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(defaultFadeInMs: v)),
        ),
        _SliderRow(
          label: 'Fade-out implicit',
          value: s.defaultFadeOutMs,
          min: 500,
          max: 30000,
          step: 500,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(defaultFadeOutMs: v)),
        ),
        _SliderRow(
          label: 'Fade la nivel / revino la normal (implicit)',
          value: s.defaultFadeToLevelMs,
          min: 500,
          max: 30000,
          step: 500,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(defaultFadeToLevelMs: v)),
        ),
        _SliderRow(
          label: 'Nivel țintă implicit (target_level)',
          value: (s.defaultTargetLevel * 100).round(),
          min: 0,
          max: 100,
          step: 1,
          unit: '%',
          onChanged: (v) => _set((x) => x.copyWith(defaultTargetLevel: v / 100)),
        ),
        const SizedBox(height: 4),
        _SegRow<FadeCurveKind>(
          label: 'Curba fade-urilor',
          value: s.fadeCurve,
          options: const {
            FadeCurveKind.natural: 'Naturală',
            FadeCurveKind.linear: 'Liniară',
          },
          onChanged: (v) => _set((x) => x.copyWith(fadeCurve: v)),
        ),
        _SegRow<AfterFadeOut>(
          label: 'După fade-out',
          value: s.afterFadeOut,
          options: const {AfterFadeOut.stop: 'Oprește', AfterFadeOut.pause: 'Pauză'},
          onChanged: (v) => _set((x) => x.copyWith(afterFadeOut: v)),
        ),
        _SwitchRow(
          title: 'Imaginea video face fade-out odată cu sunetul',
          subtitle: 'Displayul calculează fade-ul imaginii din același ceas de server.',
          value: s.fadeImageWithAudio,
          onChanged: (v) => _set((x) => x.copyWith(fadeImageWithAudio: v)),
        ),
        const Divider(height: 28),
        _SegRow<NextTransition>(
          label: 'Tranziția la Următorul / Anterior',
          value: s.nextTransition,
          options: const {
            NextTransition.cut: 'Tăiere',
            NextTransition.fadeThenStart: 'Fade-out apoi start',
            NextTransition.crossfade: 'Crossfade',
          },
          onChanged: (v) => _set((x) => x.copyWith(nextTransition: v)),
        ),
        _SliderRow(
          label: 'Durata tranziției',
          value: s.nextFadeMs,
          min: 500,
          max: 30000,
          step: 500,
          unit: 'ms',
          onChanged: (v) => _set((x) => x.copyWith(nextFadeMs: v)),
        ),
        _SwitchRow(
          title: 'Auto-avans',
          subtitle: 'La sfârșitul unui sunet (fără buclă) pornește automat următorul.',
          value: s.autoAdvance,
          onChanged: (v) => _set((x) => x.copyWith(autoAdvance: v)),
        ),
        _SwitchRow(
          title: 'Listă circulară',
          subtitle: 'După ultimul sunet urmează primul (altfel Următorul nu face nimic la capăt).',
          value: s.loopPlaylist,
          onChanged: (v) => _set((x) => x.copyWith(loopPlaylist: v)),
        ),
        const Divider(height: 28),
        Text('Scurtături de tastatură', style: context.tk.label),
        const SizedBox(height: 4),
        Text('Folosește o literă, o cifră sau „Escape”. Tastele T, O, P, R, A, Enter, Space, '
            'Home, End și PageUp/PageDown sunt deja folosite de pagina de control.',
            style: context.tk.caption),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final a in _shortcutActions)
              _ShortcutField(
                key: ValueKey<String>('sc-${a.$1}'),
                label: a.$2,
                value: s.shortcuts[a.$1] ?? AppSettings.defaultShortcuts[a.$1] ?? '',
                onValid: (v) => _set((x) =>
                    x.copyWith(shortcuts: <String, String>{...x.shortcuts, a.$1: v})),
              ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4) Bibliotecă sunete
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _librarySection(BuildContext context) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<List<SoundItem>>(
          valueListenable: sys.library.items,
          builder: (context, items, _) => FutureBuilder<int>(
            future: sys.library.usedBytes(),
            builder: (context, snap) {
              final mb = ((snap.data ?? 0) / (1024 * 1024)).toStringAsFixed(1);
              return Text('${items.length} sunete · spațiu local ocupat: $mb MB', style: t.body);
            },
          ),
        ),
        const SizedBox(height: 4),
        Text('Fișierele sunt copiate în stocarea persistentă a browserului (IndexedDB) și rămân '
            'după repornire. Metadatele (nume, tăiere, volume) sunt în baza de date.',
            style: t.caption),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () =>
                showManageSoundsSheet(context, library: sys.library, engine: sys.engine),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Gestionează sunetele'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Golești cache-ul local?'),
                  content: const Text(
                      'Fișierele locale vor fi șterse; sunetele rămân în listă și trebuie re-adăugate.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Anulează')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Golește')),
                  ],
                ),
              );
              if (ok == true) {
                await sys.engine.stopAll();
                await sys.library.clearLocalCache();
                if (mounted) setState(() {});
              }
            },
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('Golește cache-ul local'),
          ),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5) Aspect
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _lookSection(AppSettings s) {
    return _SegRow<String>(
      label: 'Mărimea pad-urilor de sunet',
      value: s.padSize,
      options: const {'small': 'Mici', 'medium': 'Medii', 'large': 'Mari'},
      onChanged: (v) => _set((x) => x.copyWith(padSize: v)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6) Diagnostic
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _diagSection(BuildContext context, AppSettings s) {
    final t = context.tk;
    final cs = sys.clockSync;
    final rtt = cs.bestRttMs;
    return ValueListenableBuilder<DisplayStatus>(
      valueListenable: sys.displayStatus,
      builder: (context, d, _) {
        final online = d.isOnline(sys.serverNowMs);
        Widget kv(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 220, child: Text(k, style: t.label)),
                Expanded(child: Text(v, style: t.body)),
              ]),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kv('Ceas comun', cs.isSynced ? 'sincronizat' : 'se sincronizează…'),
            kv('Offset față de server', '${cs.offsetMs.toStringAsFixed(1)} ms'),
            kv('Cel mai bun RTT', rtt == null ? '—' : '$rtt ms'),
            kv('Latența de pornire audio', '${sys.coordinator.audioLatencyMs} ms (măsurată)'),
            const Divider(height: 24),
            kv('Display', online ? 'online' : 'offline'),
            kv('Gata / buffering', '${d.ready ? 'gata' : 'se încarcă'} / ${d.buffering ? 'da' : 'nu'}'),
            kv('Poziție video / drift', '${d.positionMs} ms / ${d.driftMs >= 0 ? '+' : ''}${d.driftMs} ms'),
            kv('Audio guard', d.guardActive
                ? 'activ · ${d.guardPlayers} playere · nemutate: ${d.guardUnmuted}'
                : 'inactiv (sunet permis)'),
            kv('Embeduri nemutabile', '${d.embedsUnmutable}'),
            ValueListenableBuilder<String?>(
              valueListenable: sys.coordinator.syncError,
              builder: (context, err, _) => err == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(err, style: TextStyle(color: t.danger, fontSize: 12)),
                    ),
            ),
            const SizedBox(height: 16),
            Text('Test de calibrare', style: t.label),
            const SizedBox(height: 4),
            Text(
              'Displayul clipește alb și controlul redă un bip, la același moment. Dacă bipul se aude '
              'ÎNAINTEA blițului, mărește decalajul; dacă după, scade-l (secțiunea Sincronizare).',
              style: t.caption,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: online
                    ? () async {
                        try {
                          await sys.calibration.run();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Calibrarea a eșuat: $e')));
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.flash_on_rounded),
                label: const Text('Pornește testul'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await requestPersistentStorage();
                  final est = await storageEstimate();
                  if (!context.mounted) return;
                  final free = est == null
                      ? ''
                      : ' Liber ≈ ${(est.freeBytes / (1024 * 1024)).floor()} MB.';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Stocare persistentă acordată.$free'
                          : 'Browserul nu a acordat stocare persistentă (poate fi ștearsă sub presiune de spațiu).$free')));
                },
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Cere stocare persistentă'),
              ),
            ]),
            if (!online)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Testul necesită displayul online.',
                    style: TextStyle(color: t.warning, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Rânduri reutilizabile
// ═════════════════════════════════════════════════════════════════════════════
class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: t.body.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: t.caption),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String? help;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;

  const _SliderRow({
    required this.label,
    this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
  });

  String _fmt(int v) {
    if (unit == 'ms' && max >= 5000 && min >= 0) {
      final s = v / 1000;
      return s == s.roundToDouble() ? '${s.round()} s' : '${s.toStringAsFixed(1)} s';
    }
    return '$v $unit';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final v = value.clamp(min, max).toInt();
    final divisions = ((max - min) / step).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: t.body.copyWith(fontWeight: FontWeight.w600))),
            Text(_fmt(v), style: t.label.copyWith(color: t.accent2)),
          ]),
          Semantics(
            label: label,
            child: Slider(
              value: v.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions > 0 ? divisions : null,
              onChanged: (x) => onChanged(((x / step).round() * step).clamp(min, max).toInt()),
            ),
          ),
          if (help != null) Text(help!, style: t.caption),
        ],
      ),
    );
  }
}

class _SegRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const _SegRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final e in options.entries)
                ButtonSegment<T>(value: e.key, label: Text(e.value)),
            ],
            selected: <T>{value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

class _ShortcutField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onValid;
  const _ShortcutField({
    super.key,
    required this.label,
    required this.value,
    required this.onValid,
  });

  @override
  State<_ShortcutField> createState() => _ShortcutFieldState();
}

class _ShortcutFieldState extends State<_ShortcutField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _change(String v) {
    final label = v.trim();
    if (label.isEmpty) return;
    if (_reservedKeys.contains(label.toLowerCase())) {
      setState(() => _error = 'Tastă folosită deja');
      return;
    }
    if (SoundShortcuts.parseKey(label) == null) {
      setState(() => _error = 'Tastă nerecunoscută');
      return;
    }
    setState(() => _error = null);
    widget.onValid(label);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: TextField(
        controller: _c,
        maxLength: 10,
        onChanged: _change,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
          isDense: true,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
