import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/catalog_service.dart';
import '../../services/workers_service.dart';
import '../../widgets/common.dart';
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

  @override
  void initState() {
    super.initState();
    _init();
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
        query: _query.text.trim().isEmpty ? null : _query.text.trim(),
      );
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
              : _results.isEmpty
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
                        itemCount: _results.length,
                        itemBuilder: (_, i) => WorkerCard(
                          worker: _results[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkerDetailPage(
                                workerId: _results[i].profileId,
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
