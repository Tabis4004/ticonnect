import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_service.dart';
import '../../services/jobs_service.dart';
import '../../services/workers_service.dart';
import '../../widgets/common.dart';
import '../chat/chat_page.dart';
import '../workers/worker_detail_page.dart';

/// Candidatures reçues sur une demande, et cycle de vie de la mission.
class JobApplicationsPage extends StatefulWidget {
  final JobRequest job;
  const JobApplicationsPage({super.key, required this.job});

  @override
  State<JobApplicationsPage> createState() => _JobApplicationsPageState();
}

class _JobApplicationsPageState extends State<JobApplicationsPage> {
  late JobRequest _job;
  List<JobApplication> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _job = await JobsService.byId(_job.id);
      _apps = await ApplicationsService.forJob(_job.id);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _accept(JobApplication a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer'),
        content: Text(
          'Attribuer cette mission à ${a.workerName ?? "cet ouvrier"} ? '
          'Les autres candidatures seront automatiquement refusées.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Attribuer')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApplicationsService.accept(a.id);
      if (mounted) showOk(context, 'Mission attribuée');
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
  }

  Future<void> _complete() async {
    try {
      await JobsService.complete(_job.id);
      await _load();
      if (mounted) _askReview();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
  }

  Future<void> _askReview() async {
    if (_job.assignedWorkerId == null) return;
    if (await ReviewsService.alreadyReviewed(_job.id)) return;
    if (!mounted) return;

    var rating = 5;
    final comment = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Noter l\'ouvrier'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setSt(() => rating = i),
                    icon: Icon(
                      i <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: AppTheme.accent,
                      size: 32,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: comment,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Ton commentaire (facultatif)'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Plus tard')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Envoyer')),
          ],
        ),
      ),
    );

    if (sent == true) {
      try {
        await ReviewsService.submit(
          jobId: _job.id,
          revieweeId: _job.assignedWorkerId!,
          rating: rating,
          comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
        );
        if (mounted) showOk(context, 'Merci pour ton avis');
      } catch (e) {
        if (mounted) showError(context, humanError(e));
      }
    }
    comment.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_job.title)),
      body: _loading
          ? const Loading()
          : ListView(children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_job.description),
                    const SizedBox(height: 10),
                    Text(
                      '${Fmt.range(_job.budgetMin, _job.budgetMax, _job.currency)} '
                      '${Fmt.unit(_job.pricingUnit)} · ${Fmt.urgency(_job.urgency)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
              if (_job.status == 'assigned' || _job.status == 'in_progress')
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _complete,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Marquer la mission terminée'),
                  ),
                ),
              if (_job.status == 'completed')
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: _askReview,
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Noter l\'ouvrier'),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Candidatures',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              if (_apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Personne n\'a encore postulé. Les demandes urgentes reçoivent '
                    'généralement des réponses plus vite.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              for (final a in _apps)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(a.workerName ?? 'Ouvrier',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        if (a.workerRating != null)
                          RatingStars(rating: a.workerRating!, count: 1),
                      ]),
                      if (a.proposedPrice != null) ...[
                        const SizedBox(height: 4),
                        Text('Propose ${Fmt.money(a.proposedPrice, a.currency)}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                      if (a.message != null) ...[
                        const SizedBox(height: 6),
                        Text(a.message!, style: const TextStyle(color: Colors.black87)),
                      ],
                      const SizedBox(height: 10),
                      Row(children: [
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkerDetailPage(workerId: a.workerId),
                            ),
                          ),
                          child: const Text('Voir le profil'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final id = await ChatService.openWith(
                              clientId: uid!,
                              workerId: a.workerId,
                              jobId: _job.id,
                            );
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                    conversationId: id,
                                    title: a.workerName ?? 'Ouvrier'),
                              ),
                            );
                          },
                          child: const Text('Message'),
                        ),
                        const Spacer(),
                        if (a.status == 'pending' && _job.isOpen)
                          FilledButton(
                            onPressed: () => _accept(a),
                            child: const Text('Choisir'),
                          )
                        else
                          Text(
                            switch (a.status) {
                              'accepted' => 'Retenu',
                              'rejected' => 'Refusé',
                              'withdrawn' => 'Retiré',
                              _ => '',
                            },
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ]),
                    ]),
                  ),
                ),
              const SizedBox(height: 24),
            ]),
    );
  }
}
