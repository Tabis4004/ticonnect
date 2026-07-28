import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/jobs_service.dart';
import '../../widgets/common.dart';
import 'job_applications_page.dart';
import 'job_create_page.dart';

/// Mes demandes — vue client.
class MyJobsPage extends StatefulWidget {
  const MyJobsPage({super.key});
  @override
  State<MyJobsPage> createState() => _MyJobsPageState();
}

class _MyJobsPageState extends State<MyJobsPage> {
  List<JobRequest> _jobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await JobsService.mine();
      if (mounted) setState(() => _jobs = r);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const JobCreatePage()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes demandes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Publier'),
      ),
      body: _loading
          ? const Loading()
          : _jobs.isEmpty
              ? EmptyState(
                  icon: Icons.post_add_rounded,
                  title: 'Aucune demande publiée',
                  subtitle:
                      'Décris ce que tu cherches. Les ouvriers du quartier '
                      'te contacteront.',
                  action: FilledButton(
                    onPressed: _create,
                    child: const Text('Publier une demande'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _jobs.length,
                    itemBuilder: (_, i) {
                      final j = _jobs[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(j.title,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${Fmt.range(j.budgetMin, j.budgetMax, j.currency)} · ${Fmt.urgency(j.urgency)}'),
                                const SizedBox(height: 6),
                                Row(children: [
                                  _statusChip(j.status),
                                  const SizedBox(width: 8),
                                  Text('${j.applicationsCount} candidature(s)',
                                      style: const TextStyle(fontSize: 12)),
                                ]),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JobApplicationsPage(job: j),
                              ),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  static Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'open' => ('Ouverte', AppTheme.primary),
      'assigned' => ('Attribuée', AppTheme.accent),
      'in_progress' => ('En cours', AppTheme.accent),
      'completed' => ('Terminée', Colors.black54),
      'cancelled' => ('Annulée', AppTheme.danger),
      'expired' => ('Expirée', Colors.black38),
      _ => (status, Colors.black54),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
