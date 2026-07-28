import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/contact_service.dart';
import '../services/session.dart';
import 'common.dart';

/// Carte de contact.
///
/// **La prise de contact est gratuite.** `unlockCost` vaut 0 : on enregistre
/// quand même le déverrouillage, ce qui permet de mesurer les mises en
/// relation réelles — l'indicateur le plus important du produit.
///
/// La branche payante est conservée et s'active toute seule si
/// `job_requests.unlock_cost` repasse au-dessus de zéro en base. Aucune
/// republication de l'application n'est nécessaire pour faire ce choix.
///
/// Conformité AdMob : quand cette branche est active, le bouton « Regarder
/// une vidéo » est un opt-in explicite présenté à chaque fois, avec
/// l'alternative « utiliser un crédit » toujours visible. Un visionnage
/// imposé constituerait une violation « Disallowed Rewarded Implementation ».
class LockedContactCard extends StatefulWidget {
  final String targetProfileId;
  final String targetName;
  final String jobId;
  final int unlockCost;
  final bool initiallyUnlocked;

  const LockedContactCard({
    super.key,
    required this.targetProfileId,
    required this.targetName,
    required this.jobId,
    required this.unlockCost,
    this.initiallyUnlocked = false,
  });

  @override
  State<LockedContactCard> createState() => _LockedContactCardState();
}

class _LockedContactCardState extends State<LockedContactCard> {
  bool _unlocked = false;
  bool _busy = false;
  ContactDetails? _contact;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.initiallyUnlocked;
    if (_unlocked) _loadContact();
  }

  Future<void> _loadContact() async {
    final c = await ContactService.read(widget.targetProfileId);
    if (mounted) setState(() => _contact = c);
  }

  Future<void> _run(Future<UnlockResult> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      setState(() => _unlocked = true);
      await _loadContact();
      if (mounted) {
        await context.read<Session>().refresh();
        showOk(context, 'Contact débloqué');
      }
    } else {
      showError(context, result.message ?? 'Déverrouillage impossible');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return _unlockedView();
    return _lockedView();
  }

  Widget _unlockedView() {
    final phone = _contact?.phone;
    return Card(
      color: AppTheme.primary.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_open_rounded, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Contact de ${widget.targetName}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          if (phone == null)
            const Loading()
          else ...[
            SelectableText(phone,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                  icon: const Icon(Icons.phone),
                  label: const Text('Appeler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r"[^0-9]"), "")}'),
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _freeView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.phone_outlined, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Contacter le client',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Appelle ${widget.targetName} directement pour proposer tes services.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Loading()
          else
            FilledButton.icon(
              onPressed: () => _run(() => ContactService.unlockClientWithCredits(
                    clientId: widget.targetProfileId,
                    jobId: widget.jobId,
                  )),
              icon: const Icon(Icons.phone),
              label: const Text('Voir le numéro (gratuit)'),
            ),
        ]),
      ),
    );
  }

  Widget _lockedView() {
    final session = context.watch<Session>();
    final freeLeft = session.worker?.freeUnlocksLeft ?? 0;
    final credits = session.credits;

    // Cas nominal : la prise de contact ne coûte rien.
    if (widget.unlockCost == 0) return _freeView();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_outline_rounded, color: Colors.black45),
            const SizedBox(width: 8),
            const Text('Contact verrouillé',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Débloque le numéro de ${widget.targetName} pour proposer tes services directement.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Loading()
          else ...[
            if (freeLeft > 0) ...[
              FilledButton.icon(
                onPressed: () => _run(() => ContactService.unlockClientWithCredits(
                      clientId: widget.targetProfileId,
                      jobId: widget.jobId,
                    )),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: Text('Débloquer gratuitement ($freeLeft restant${freeLeft > 1 ? "s" : ""})'),
              ),
            ] else ...[
              // Opt-in publicitaire explicite, jamais automatique.
              FilledButton.icon(
                onPressed: () => _run(() => ContactService.unlockClientWithAd(
                      clientId: widget.targetProfileId,
                      jobId: widget.jobId,
                    )),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Regarder une vidéo pour débloquer'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: credits >= widget.unlockCost
                    ? () => _run(() => ContactService.unlockClientWithCredits(
                          clientId: widget.targetProfileId,
                          jobId: widget.jobId,
                        ))
                    : null,
                icon: const Icon(Icons.toll_outlined),
                label: Text(
                  credits >= widget.unlockCost
                      ? 'Utiliser ${widget.unlockCost} crédit${widget.unlockCost > 1 ? "s" : ""} (solde : $credits)'
                      : 'Crédits insuffisants (solde : $credits)',
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
