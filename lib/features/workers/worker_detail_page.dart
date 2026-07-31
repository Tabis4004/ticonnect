import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/chat_service.dart';
import '../../services/contact_service.dart';
import '../../services/workers_service.dart';
import '../../widgets/common.dart';
import '../chat/chat_page.dart';

/// Fiche ouvrier vue par un client.
///
/// Le contact est gratuit pour le client — c'est la ressource rare de la
/// marketplace, on ne lui met aucune friction. On enregistre quand même le
/// déverrouillage pour mesurer les mises en relation.
class WorkerDetailPage extends StatefulWidget {
  final String workerId;
  const WorkerDetailPage({super.key, required this.workerId});

  @override
  State<WorkerDetailPage> createState() => _WorkerDetailPageState();
}

class _WorkerDetailPageState extends State<WorkerDetailPage> {
  Profile? _profile;
  WorkerProfile? _worker;
  List<Trade> _trades = [];
  List<Review> _reviews = [];
  ContactDetails? _contact;
  bool _loading = true;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Interstitiel autorisé ici : transition entre deux écrans, jamais
    // pendant une action de l'utilisateur.
    AdsService.maybeShowInterstitial(AdKeys.profileInterstitial);
  }

  Future<void> _load() async {
    try {
      _profile = await WorkersService.publicProfile(widget.workerId);
      _worker = await WorkersService.profile(widget.workerId);
      _trades = await WorkersService.tradesOf(widget.workerId);
      _reviews = await WorkersService.reviewsOf(widget.workerId);
      if (await ContactService.isUnlocked(widget.workerId)) {
        _contact = await ContactService.read(widget.workerId);
      }
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reveal() async {
    setState(() => _unlocking = true);
    final r = await ContactService.unlockWorker(widget.workerId);
    if (r.ok) {
      _contact = await ContactService.read(widget.workerId);
      if (_contact == null && mounted) {
        showError(context,
            "Cet ouvrier n'a pas encore renseigné son numéro. Écris-lui.");
      }
    } else if (mounted) {
      showError(context, r.message ?? 'Impossible pour le moment');
    }
    if (mounted) setState(() => _unlocking = false);
  }

  Future<void> _message() async {
    final id = await ChatService.openWith(
      clientId: uid!,
      workerId: widget.workerId,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(conversationId: id, title: _profile!.fullName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Loading());
    }
    final p = _profile!;
    final w = _worker;

    return Scaffold(
      appBar: AppBar(title: Text(p.fullName)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
              child: p.avatarUrl == null
                  ? Text(p.fullName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary))
                  : null,
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(p.fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (w?.isVerified ?? false) ...[
                const SizedBox(width: 6),
                const VerifiedBadge(),
              ],
            ]),
            if (w?.headline != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w!.headline!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
              ),
            const SizedBox(height: 10),
            if (w != null)
              RatingStars(rating: w.ratingAvg, count: w.ratingCount, size: 18),
            const SizedBox(height: 14),
            if (w != null)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _stat('${w.jobsCompleted}', 'missions'),
                _stat('${w.yearsExperience ?? 0} ans', 'expérience'),
                _stat(Fmt.range(w.rateMin, w.rateMax, w.currency), Fmt.unit(w.pricingUnit)),
              ]),
          ]),
        ),
        if (_trades.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in _trades) Chip(label: Text(t.nameFr))],
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            if (_contact != null) ...[
              Card(
                color: AppTheme.primary.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    SelectableText(_contact!.phone,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              launchUrl(Uri.parse('tel:${_contact!.phone}')),
                          icon: const Icon(Icons.phone),
                          label: const Text('Appeler'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _message,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Message'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ] else if (_unlocking)
              const Loading()
            else
              FilledButton.icon(
                onPressed: _reveal,
                icon: const Icon(Icons.phone),
                label: const Text('Voir le numéro (gratuit)'),
              ),
          ]),
        ),
        if (_reviews.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Avis',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          for (final r in _reviews)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    RatingStars(rating: r.rating.toDouble(), count: 1),
                    const Spacer(),
                    Text(Fmt.ago(r.createdAt),
                        style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  ]),
                  if (r.comment != null) ...[
                    const SizedBox(height: 6),
                    Text(r.comment!),
                  ],
                  const SizedBox(height: 4),
                  Text(r.reviewerName ?? 'Client',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ),
        ],
        // Le client passe l'essentiel de son temps ici, à comparer des
        // profils — c'est le seul écran de son parcours où une bannière a
        // un volume réel. En bas de page : elle ne recouvre aucune action
        // et ne participe pas à la décision de contacter.
        const SizedBox(height: 8),
        const AdBannerSlot(placementKey: AdKeys.workerDetailBanner),
      ]),
    );
  }

  static Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}
