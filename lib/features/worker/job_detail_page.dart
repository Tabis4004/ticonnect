import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/jobs_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/ad_intro.dart';
import '../../widgets/common.dart';
import '../../widgets/locked_contact.dart';

/// Détail d'une mission côté ouvrier.
///
/// Deux façons d'entrer en relation, volontairement distinctes :
///  - **candidater**, gratuit, qui passe par la messagerie interne ;
///  - **débloquer le contact**, payant, pour appeler directement.
///
/// Garder la candidature gratuite préserve la liquidité de la marketplace :
/// un ouvrier sans crédit peut quand même décrocher du travail.
class JobDetailPage extends StatefulWidget {
  final JobSearchResult job;
  const JobDetailPage({super.key, required this.job});

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  late bool _applied;
  bool _busy = false;
  String? _clientId;

  @override
  void initState() {
    super.initState();
    _applied = widget.job.hasApplied;
    _loadClient();
  }

  Future<void> _loadClient() async {
    try {
      final j = await JobsService.byId(widget.job.id);
      if (mounted) setState(() => _clientId = j.clientId);
    } catch (_) {}
  }

  Future<void> _apply() async {
    final message = TextEditingController();
    final price = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proposer mes services'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Ton prix', suffixText: 'XOF'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: message,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Explique pourquoi tu es la bonne personne',
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Envoyer')),
        ],
      ),
    );

    if (send == true) {
      // La publicité se joue ici, entre la validation du formulaire et
      // l'envoi : c'est le moment où l'ouvrier reçoit la valeur, et où le
      // volume d'impressions suit l'activité réelle de la marketplace
      // plutôt que le seul nombre d'inscrits.
      //
      // Elle ne bloque jamais la candidature : inventaire vide, refus de
      // l'utilisateur ou plafond atteint, l'envoi se fait quand même.
      // Faire dépendre le gagne-pain d'un ouvrier de la disponibilité
      // d'une vidéo serait à la fois cruel et mauvais pour la liquidité.
      if (mounted && SettingsService.boolean(SettingKeys.workerApplyAdEnabled, true)) {
        final accepted =
            await AdIntro.ask(context, AdKeys.applyRewardedInterstitial);
        if (accepted) {
          await AdsService.showRewardedInterstitial(
              AdKeys.applyRewardedInterstitial);
        }
      }

      if (!mounted) {
        message.dispose();
        price.dispose();
        return;
      }

      setState(() => _busy = true);
      try {
        await ApplicationsService.apply(
          jobId: widget.job.id,
          message: message.text.trim().isEmpty ? null : message.text.trim(),
          proposedPrice: double.tryParse(price.text.trim()),
        );
        if (mounted) {
          setState(() => _applied = true);
          showOk(context, 'Candidature envoyée');
        }
      } catch (e) {
        if (mounted) showError(context, humanError(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    message.dispose();
    price.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;

    return Scaffold(
      appBar: AppBar(title: const Text('Mission')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text(j.tradeName)),
                Chip(label: Text(Fmt.urgency(j.urgency))),
                Chip(
                    label: Text(j.neighborhood == null
                        ? j.city
                        : '${j.neighborhood}, ${j.city}')),
              ]),
              const SizedBox(height: 14),
              Text(j.description, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${Fmt.range(j.budgetMin, j.budgetMax, j.currency)} ${Fmt.unit(j.pricingUnit)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Publié ${Fmt.ago(j.createdAt)} · ${j.applicationsCount} candidature(s)',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _busy
              ? const Loading()
              : _applied
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check),
                      label: const Text('Candidature envoyée'),
                    )
                  : FilledButton.icon(
                      onPressed: _apply,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Proposer mes services (gratuit)'),
                    ),
        ),
        const SizedBox(height: 8),
        if (_clientId != null)
          LockedContactCard(
            targetProfileId: _clientId!,
            targetName: j.clientName,
            jobId: j.id,
            unlockCost: j.unlockCost,
            initiallyUnlocked: j.isUnlocked,
          ),
      ]),
    );
  }
}
