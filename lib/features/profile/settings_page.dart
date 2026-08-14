import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/common.dart';

/// Réglages de la plateforme, générés depuis la base.
///
/// Cet écran ne connaît aucun réglage en particulier. Il lit
/// `editable_settings()`, qui rend pour chaque ligne le type de contrôle à
/// afficher, son libellé, ses bornes et ses choix — et fabrique
/// l'interface correspondante.
///
/// C'est ce qui rend vraie la promesse répétée partout dans ce projet :
/// « ajustable sans republier ». Un réglage ajouté en base demain apparaît
/// ici sans une ligne de Dart, et les onze réglages qui n'étaient
/// modifiables que depuis l'éditeur SQL le deviennent depuis un téléphone.
///
/// Les bornes sont appliquées deux fois, à dessein : ici pour guider la
/// saisie, et par le trigger `app_settings_clamp` côté base pour que le
/// garde-fou tienne quel que soit le chemin d'écriture.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<SettingDef> _settings = [];
  bool _loading = true;
  String? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _settings = await SettingsService.editable();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(SettingDef s, dynamic value) async {
    setState(() => _saving = s.key);
    try {
      await SettingsService.set(s.key, value);

      // Les emplacements publicitaires sont lus au démarrage : sans ce
      // rechargement, un changement de fréquence ne prendrait effet qu'au
      // prochain lancement de l'application.
      await AdsService.loadPlacements();
      await SettingsService.load();
      await _load();
      if (mounted) showOk(context, 'Enregistré');
    } catch (e) {
      if (mounted) showError(context, humanError(e));
      await _load();
    }
    if (mounted) setState(() => _saving = null);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SettingDef>>{};
    for (final s in _settings) {
      groups.putIfAbsent(s.group ?? 'Divers', () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Loading()
          : _settings.isEmpty
              ? const EmptyState(
                  icon: Icons.tune,
                  title: 'Aucun réglage',
                  subtitle:
                      'Aucun réglage modifiable n\'est déclaré, ou ce compte '
                      'n\'est pas administrateur.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Ces valeurs prennent effet immédiatement, sans '
                        'republier l\'application. Les bornes sont imposées '
                        'côté base : une saisie hors limites est ramenée à la '
                        'valeur la plus proche.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 18),
                      for (final g in groups.entries) ...[
                        Text(g.key,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary)),
                        const SizedBox(height: 8),
                        for (final s in g.value) _tile(s),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _tile(SettingDef s) {
    final busy = _saving == s.key;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(s.label ?? s.key,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (busy)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _control(s),
        ]),
        if (s.description != null) ...[
          const SizedBox(height: 4),
          Text(s.description!,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
        if (s.control == 'list') ...[
          const SizedBox(height: 8),
          _listEditor(s),
        ],
      ]),
    );
  }

  Widget _control(SettingDef s) {
    switch (s.control) {
      case 'switch':
        return Switch(
          value: s.value == true,
          onChanged: (v) => _save(s, v),
        );

      case 'number':
        return SizedBox(
          width: 132,
          child: _NumberField(
            value: (s.value as num?)?.toDouble() ?? 0,
            min: s.min,
            max: s.max,
            step: s.step ?? 1,
            suffix: s.suffix,
            onSubmit: (v) => _save(s, v),
          ),
        );

      case 'choice':
        return DropdownButton<String>(
          value: '${s.value}',
          underline: const SizedBox.shrink(),
          items: [
            for (final c in s.choices)
              DropdownMenuItem(
                value: '${c['value']}',
                child: Text('${c['label'] ?? c['value']}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) _save(s, v);
          },
        );

      case 'list':
        final n = (s.value as List?)?.length ?? 0;
        return Text('$n élément${n > 1 ? "s" : ""}',
            style: const TextStyle(fontSize: 12, color: Colors.black45));

      // Une adresse de fiche ou un numéro de version : trop long pour un
      // champ dans la ligne, trop court pour un écran. On ouvre une boîte.
      case 'text':
        return TextButton(
          onPressed: () => _editText(s),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              '${s.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );

      default:
        return Text('${s.value}',
            style: const TextStyle(fontSize: 12, color: Colors.black45));
    }
  }

  /// Éditeur d'une valeur textuelle.
  ///
  /// Le champ est prérempli et sélectionnable : le cas le plus fréquent
  /// n'est pas d'écrire une adresse de zéro, mais de corriger un numéro de
  /// version d'un chiffre.
  Future<void> _editText(SettingDef s) async {
    final champ = TextEditingController(text: '${s.value}');
    final valeur = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.label ?? s.key),
        content: TextField(
          controller: champ,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, champ.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    champ.dispose();
    if (valeur != null && valeur != '${s.value}') await _save(s, valeur);
  }

  /// Éditeur de liste : suffisant pour les deux usages actuels — les
  /// identifiants d'appareils de test et l'échelle de récompense du
  /// parrainage — sans imposer un écran par type de contenu.
  Widget _listEditor(SettingDef s) {
    final items = (s.value as List?) ?? const [];

    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < items.length; i++)
        InputChip(
          label: Text('${items[i]}'),
          onDeleted: () {
            final next = [...items]..removeAt(i);
            _save(s, next);
          },
        ),
      ActionChip(
        avatar: const Icon(Icons.add, size: 16),
        label: const Text('Ajouter'),
        onPressed: () => _addToList(s, items),
      ),
      if (items.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.copy, size: 16),
          label: const Text('Copier'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: items.join(', ')));
            if (mounted) showOk(context, 'Copié');
          },
        ),
    ]);
  }

  Future<void> _addToList(SettingDef s, List items) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.label ?? s.key),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nouvelle valeur'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ajouter')),
        ],
      ),
    );

    final raw = c.text.trim();
    c.dispose();
    if (ok != true || raw.isEmpty) return;

    // Une échelle de récompense contient des nombres, une liste
    // d'appareils des chaînes. On respecte ce que l'utilisateur a tapé.
    final parsed = num.tryParse(raw);
    await _save(s, [...items, parsed ?? raw]);
  }
}

/// Champ numérique avec pas, bornes et validation à la sortie.
///
/// La saisie n'est enregistrée qu'à la validation, jamais à chaque frappe :
/// écrire « 12 » passe par « 1 », et sauvegarder « 1 » déclencherait le
/// bornage côté base sur une valeur que personne n'a voulue.
class _NumberField extends StatefulWidget {
  final double value;
  final double? min;
  final double? max;
  final double step;
  final String? suffix;
  final ValueChanged<num> onSubmit;

  const _NumberField({
    required this.value,
    required this.step,
    required this.onSubmit,
    this.min,
    this.max,
    this.suffix,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: _fmt(widget.value));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    var v = double.tryParse(_c.text.replaceAll(',', '.'));
    if (v == null) {
      _c.text = _fmt(widget.value);
      return;
    }
    if (widget.min != null) v = v.clamp(widget.min!, double.infinity);
    if (widget.max != null) v = v.clamp(double.negativeInfinity, widget.max!);
    _c.text = _fmt(v);
    if (v != widget.value) {
      widget.onSubmit(v == v.roundToDouble() ? v.toInt() : v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
        _submit();
      },
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        suffixStyle: const TextStyle(fontSize: 11),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }
}
