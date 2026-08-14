import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../../widgets/common.dart';

/// Choix des métiers d'un ouvrier, sur un écran dédié.
///
/// La sélection vivait auparavant dans le formulaire de profil, sous la
/// forme de deux rangées de puces : une par catégorie, une par métier de la
/// catégorie ouverte. Changer de catégorie faisait disparaître les métiers
/// déjà cochés — ils restaient sélectionnés, mais plus rien ne les montrait,
/// et la seule trace était un compteur « 2 métier(s) sélectionné(s) ». On ne
/// pouvait donc pas relire son propre choix avant d'enregistrer.
///
/// Ici la sélection est toujours en tête d'écran, quelle que soit la
/// catégorie parcourue, et le multiple est explicite plutôt que deviné.
class TradePickerPage extends StatefulWidget {
  const TradePickerPage({super.key, required this.initial});

  final Set<int> initial;

  @override
  State<TradePickerPage> createState() => _TradePickerPageState();
}

class _TradePickerPageState extends State<TradePickerPage> {
  final _search = TextEditingController();
  List<TradeCategory> _categories = [];
  List<Trade> _trades = [];
  late Set<int> _selected;
  int? _categoryId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
    _init();
  }

  Future<void> _init() async {
    _categories = await CatalogService.categories();
    _trades = await CatalogService.trades();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// La recherche traverse les catégories : un ouvrier qui tape « soud »
  /// ne sait pas nécessairement sous quelle rubrique le soudage est rangé.
  List<Trade> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      return _trades
          .where((t) => t.nameFr.toLowerCase().contains(q))
          .toList();
    }
    if (_categoryId == null) return const [];
    return _trades.where((t) => t.categoryId == _categoryId).toList();
  }

  Trade? _byId(int id) {
    for (final t in _trades) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final recherche = _search.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes métiers'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected),
            child: Text('Valider',
                style: TextStyle(
                    color: _selected.isEmpty ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Loading()
          : Column(children: [
              // Sélection courante, toujours visible.
              if (_selected.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_selected.length} métier(s) retenu(s)',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final id in _selected)
                            InputChip(
                              label: Text(_byId(id)?.nameFr ?? '#$id'),
                              onDeleted: () =>
                                  setState(() => _selected.remove(id)),
                            ),
                        ]),
                      ]),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Chercher un métier',
                    suffixIcon: recherche
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _search.clear()),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),

              if (!recherche)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in _categories) ...[
                        ChoiceChip(
                          label: Text(c.nameFr),
                          selected: _categoryId == c.id,
                          onSelected: (v) =>
                              setState(() => _categoryId = v ? c.id : null),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),

              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: recherche
                            ? Icons.search_off
                            : Icons.category_outlined,
                        title: recherche
                            ? 'Aucun métier trouvé'
                            : 'Choisis une catégorie',
                        subtitle: recherche
                            ? 'Essaie un autre mot.'
                            : 'Puis coche autant de métiers que tu exerces.',
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = visible[i];
                          final on = _selected.contains(t.id);
                          return CheckboxListTile(
                            value: on,
                            title: Text(t.nameFr),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setState(() {
                              v == true
                                  ? _selected.add(t.id)
                                  : _selected.remove(t.id);
                            }),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
