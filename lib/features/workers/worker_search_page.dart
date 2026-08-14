import 'package:flutter/material.dart';

import '../../core/countries.dart';
import '../../core/supabase.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/catalog_service.dart';
import '../../services/session.dart';
import '../../services/workers_service.dart';
import '../../widgets/common.dart';
import '../../widgets/country_picker.dart';
import 'worker_detail_page.dart';

/// Recherche d'ouvriers — écran d'accueil côté client.
class WorkerSearchPage extends StatefulWidget {
  const WorkerSearchPage({super.key});
  @override
  State<WorkerSearchPage> createState() => _WorkerSearchPageState();
}

class _WorkerSearchPageState extends State<WorkerSearchPage> {
  final _query = TextEditingController();
  List<TradeCategory> _categories = [];
  List<Trade> _trades = [];
  int? _tradeId;
  int? _categoryId;
  List<WorkerSearchResult> _results = [];
  bool _loading = true;
  bool _onlyAvailable = true;

  /// Pays du chantier recherché, pas celui de l'utilisateur.
  ///
  /// Initialisé sur son profil, mais modifiable : on peut vivre à Lomé et
  /// avoir un chantier à Abidjan. C'est fréquent en Afrique de l'Ouest, et
  /// la version précédente rendait ces recherches impossibles.
  late String _country = AppSession.currentCountry;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _pickCountry() async {
    final picked = await chooseCountry(context);
    if (picked != null && picked.code != _country) {
      setState(() => _country = picked.code);
      await _search();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _categories = await CatalogService.categories();
    _trades = await CatalogService.trades();
    await _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await WorkersService.search(
        tradeId: _tradeId,
        countryCode: _country,
        query: _query.text.trim().isEmpty ? null : _query.text.trim(),
      );
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Les profils indisponibles restent accessibles par la recherche, mais
  /// sont masqués par défaut : proposer un ouvrier injoignable est le
  /// meilleur moyen de perdre un client au premier essai.
  List<WorkerSearchResult> get _visible => _onlyAvailable
      ? _results.where((w) => w.availability == 'available').toList()
      : _results;

  @override
  Widget build(BuildContext context) {
    final visibleTrades = _categoryId == null
        ? <Trade>[]
        : _trades.where((t) => t.categoryId == _categoryId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Trouver un ouvrier')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Maçon, chauffeur, plombier…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.tune),
                onPressed: _search,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // Le pays en tête des filtres, et visible en permanence :
              // c'est le seul qui peut vider la liste sans qu'on comprenne
              // pourquoi. Un chantier à Abidjan depuis Lomé se cherche ici.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: Text(Countries.byCode(_country).flag,
                      style: const TextStyle(fontSize: 15)),
                  label: Text(Countries.byCode(_country).name),
                  onPressed: _pickCountry,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  avatar: const Icon(Icons.podcasts_rounded, size: 16),
                  label: const Text('Disponibles'),
                  selected: _onlyAvailable,
                  onSelected: (v) => setState(() => _onlyAvailable = v),
                ),
              ),
              for (final c in _categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(c.nameFr),
                    selected: _categoryId == c.id,
                    onSelected: (v) => setState(() {
                      _categoryId = v ? c.id : null;
                      _tradeId = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        if (visibleTrades.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in visibleTrades)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(t.nameFr),
                      selected: _tradeId == t.id,
                      onSelected: (v) {
                        setState(() => _tradeId = v ? t.id : null);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Loading()
              : _visible.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Aucun ouvrier trouvé',
                      subtitle:
                          'Essaie un autre métier, ou publie une demande : '
                          'les ouvriers viendront à toi.',
                    )
                  : RefreshIndicator(
                      onRefresh: _search,
                      child: ListView.builder(
                        itemCount: _visible.length,
                        itemBuilder: (_, i) => WorkerCard(
                          worker: _visible[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkerDetailPage(
                                workerId: _visible[i].profileId,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
        const AdBannerSlot(placementKey: AdKeys.jobListBanner),
      ]),
    );
  }
}
