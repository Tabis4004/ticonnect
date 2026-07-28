import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Tableau de bord administrateur.
///
/// L'accès repose entièrement sur la base : la fonction `is_admin()` et les
/// politiques RLS `*_admin_all` donnent au compte inscrit dans la table
/// `admins` la lecture de toutes les lignes. Aucun contrôle côté application
/// ne peut donc être contourné — masquer ce bouton ne serait qu'un confort.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _leaks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _count(String table) async {
    try {
      final rows = await db.from(table).select('*').count();
      return rows.count;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = {
        'Utilisateurs': await _count('profiles'),
        'Ouvriers': await _count('worker_profiles'),
        'Missions': await _count('job_requests'),
        'Candidatures': await _count('job_applications'),
        'Mises en relation': await _count('contact_unlocks'),
        'Avis': await _count('reviews'),
        'Impressions pub': await _count('ad_impressions'),
      };

      _reports = List<Map<String, dynamic>>.from(await db
          .from('reports')
          .select('*, reported:profiles!reports_reported_profile_id_fkey(full_name)')
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(20));

      // Mesure de la fuite hors plateforme : messages contenant un numéro.
      _leaks = List<Map<String, dynamic>>.from(await db
          .from('messages')
          .select('id, body, created_at')
          .eq('contains_contact', true)
          .order('created_at', ascending: false)
          .limit(20));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.1,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final e in _stats.entries)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE6EAE7)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.value < 0 ? "—" : e.value}',
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary)),
                            Text(e.key,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Signalements ouverts',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_reports.isEmpty)
                  const Text('Aucun signalement en attente.',
                      style: TextStyle(color: Colors.black54))
                else
                  for (final r in _reports)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(r['reason'] as String? ?? ''),
                        subtitle: Text(
                          '${(r['reported'] as Map?)?['full_name'] ?? "?"} · '
                          '${Fmt.ago(DateTime.tryParse(r['created_at'] as String? ?? ""))}',
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                const Text('Fuite hors plateforme',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Messages contenant un numéro de téléphone. Un taux élevé '
                  'signifie que les échanges quittent l\'application dès le '
                  'premier contact.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                if (_leaks.isEmpty)
                  const Text('Aucun message détecté.',
                      style: TextStyle(color: Colors.black54))
                else
                  for (final m in _leaks)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(m['body'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(Fmt.ago(
                            DateTime.tryParse(m['created_at'] as String? ?? ''))),
                      ),
                    ),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }
}
