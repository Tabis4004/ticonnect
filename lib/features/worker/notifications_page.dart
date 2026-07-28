import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/jobs_service.dart';
import '../../services/notifications_service.dart';
import '../../widgets/common.dart';
import 'job_detail_page.dart';

/// Alertes de mission.
///
/// Alimentées par un trigger en base : dès qu'un client publie, les ouvriers
/// du bon métier, disponibles et dans la bonne ville sont notifiés. Le même
/// mécanisme enverra des push le jour où les jetons FCM seront collectés —
/// la logique de ciblage n'aura pas à être réécrite.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await NotificationsService.list();
      await NotificationsService.markAllRead();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final payload = n['payload'] as Map<String, dynamic>? ?? const {};
    final jobId = payload['job_id'] as String?;
    if (jobId == null) return;
    try {
      final jobs = await JobsService.search(limit: 100);
      final match = jobs.where((j) => j.id == jobId).toList();
      if (!mounted) return;
      if (match.isEmpty) {
        showError(context, "Cette mission n'est plus disponible");
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobDetailPage(job: match.first)),
      );
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertes')),
      body: _loading
          ? const Loading()
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Aucune alerte',
                  subtitle:
                      'Tu seras prévenu dès qu\'une mission de ton métier est '
                      'publiée dans ta ville. Reste en « disponible » pour '
                      'les recevoir.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final unread = n['read_at'] == null;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: unread
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.work_outline,
                            color: unread ? Colors.white : AppTheme.primary,
                          ),
                        ),
                        title: Text(
                          n['title'] as String? ?? '',
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(n['body'] as String? ?? ''),
                        trailing: Text(
                          Fmt.ago(DateTime.tryParse(
                              n['created_at'] as String? ?? '')),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black45),
                        ),
                        onTap: () => _open(n),
                      );
                    },
                  ),
                ),
    );
  }
}
