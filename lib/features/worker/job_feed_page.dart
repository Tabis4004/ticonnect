import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/catalog_service.dart';
import '../../services/jobs_service.dart';
import '../../services/notifications_service.dart';
import '../../widgets/common.dart';
import 'job_detail_page.dart';
import 'notifications_page.dart';

/// Fil des missions disponibles — écran d'accueil côté ouvrier.
class JobFeedPage extends StatefulWidget {
  const JobFeedPage({super.key});
  @override
  State<JobFeedPage> createState() => _JobFeedPageState();
}

class _JobFeedPageState extends State<JobFeedPage> {
  List<JobSearchResult> _jobs = [];
  List<Trade> _myTrades = [];
  bool _loading = true;
  bool _onlyMyTrades = true;
  String? _urgency;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Par défaut on ne montre que les métiers déclarés par l'ouvrier :
      // un maçon n'a rien à faire d'une annonce de coiffure.
      if (_myTrades.isEmpty) {
        final rows = await db
            .from('worker_trades')
            .select('trade:trades(*)')
            .eq('worker_id', uid!);
        _myTrades = rows
            .map<Trade>((e) => Trade.fromMap(e['trade'] as Map<String, dynamic>))
            .toList();
      }

      final ids = _onlyMyTrades && _myTrades.isNotEmpty
          ? _myTrades.map((t) => t.id).toList()
          : null;

      final r = await JobsService.search(tradeIds: ids, urgency: _urgency);
      final unread = await NotificationsService.unreadCount();
      if (mounted) setState(() {
        _jobs = r;
        _unread = unread;
      });
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Missions disponibles'),
        actions: [
          Stack(alignment: Alignment.center, children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Alertes',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                );
                _load();
              },
            ),
            if (_unread > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC0392B),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ]),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            FilterChip(
              label: const Text('Mes métiers'),
              selected: _onlyMyTrades,
              onSelected: (v) {
                setState(() => _onlyMyTrades = v);
                _load();
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Urgent'),
              selected: _urgency == 'immediate',
              onSelected: (v) {
                setState(() => _urgency = v ? 'immediate' : null);
                _load();
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Cette semaine'),
              selected: _urgency == 'this_week',
              onSelected: (v) {
                setState(() => _urgency = v ? 'this_week' : null);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Loading()
              : _jobs.isEmpty
                  ? EmptyState(
                      icon: Icons.work_outline_rounded,
                      title: 'Aucune mission pour le moment',
                      subtitle: _onlyMyTrades
                          ? 'Élargis la recherche à tous les métiers, ou reviens '
                              'plus tard : de nouvelles demandes arrivent chaque jour.'
                          : 'Reviens plus tard, de nouvelles demandes arrivent '
                              'chaque jour.',
                      action: _onlyMyTrades
                          ? OutlinedButton(
                              onPressed: () {
                                setState(() => _onlyMyTrades = false);
                                _load();
                              },
                              child: const Text('Voir tous les métiers'),
                            )
                          : null,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _jobs.length,
                        itemBuilder: (_, i) => JobCard(
                          job: _jobs[i],
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JobDetailPage(job: _jobs[i]),
                              ),
                            );
                            _load();
                          },
                        ),
                      ),
                    ),
        ),
        const AdBannerSlot(placementKey: AdKeys.jobListBanner),
      ]),
    );
  }
}
