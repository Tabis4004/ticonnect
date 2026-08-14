import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/supabase.dart';
import '../core/theme.dart';
import '../features/chat/chat_page.dart';
import '../models/models.dart';
import '../services/chat_service.dart';
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
  bool _contactLoaded = false;
  ContactDetails? _contact;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.initiallyUnlocked;
    if (_unlocked) _loadContact();
  }

  Future<void> _loadContact() async {
    ContactDetails? c;
    try {
      c = await ContactService.read(widget.targetProfileId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _contact = c;
        _contactLoaded = true;
      });
    }
  }

  /// Ouvre la conversation liée à cette mission.
  ///
  /// Cette carte n'est montrée qu'à l'ouvrier : `targetProfileId` est donc
  /// le client, et `uid` l'ouvrier. Passer `jobId` rattache l'échange à la
  /// mission — sans lui, `openWith` retrouverait ou créerait la
  /// conversation générale entre les deux comptes, et deux missions
  /// distinctes se mélangeraient dans le même fil.
  Future<void> _ouvrirMessagerie() async {
    setState(() => _busy = true);
    try {
      final id = await ChatService.openWith(
        clientId: widget.targetProfileId,
        workerId: uid!,
        jobId: widget.jobId,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatPage(conversationId: id, title: widget.targetName),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _run(Future<UnlockResult> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      setState(() => _unlocked = true);
      await _loadContact();
      if (!mounted) return;

      // On capture la session avant l'await : réutiliser `context` de l'autre
      // côté d'une frontière asynchrone est une source classique de crash
      // quand l'utilisateur quitte l'écran entre-temps.
      final session = context.read<AppSession>();
      await session.refresh();
      if (!mounted) return;
      showOk(context, 'Contact débloqué');
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
      color: AppTheme.primary.withValues(alpha: 0.06),
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
          if (!_contactLoaded)
            const Loading()
          else if (phone == null) ...[
            const Text(
              "Cette personne n'a pas encore renseigné son numéro. "
              'Passe par la messagerie en attendant.',
              style: TextStyle(color: Colors.black54),
            ),
          ] else ...[
            SelectableText(phone,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Un seul chemin, et il passe par l'application.
            //
            // « Appeler » et « WhatsApp » ouvraient une autre application :
            // l'échange sortait de la plateforme au premier geste, et plus
            // rien n'en était mesurable. Le taux de réponse d'un ouvrier, le
            // délai avant sa première réponse, le taux de fuite — tous les
            // indicateurs du tableau de bord ne voyaient que la fraction des
            // conversations restées ici.
            //
            // Le numéro reste affiché : il est ce que le déverrouillage a
            // accordé, et le masquer changerait la nature du produit. Tant
            // qu'il est lisible, la mesure reste partielle — mais elle
            // cesse d'être contournée par défaut.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _ouvrirMessagerie,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Envoyer un message'),
              ),
            ),
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
          const Row(children: [
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
    final session = context.watch<AppSession>();
    final freeLeft = session.worker?.freeUnlocksLeft ?? 0;
    final credits = session.credits;

    // Cas nominal : la prise de contact ne coûte rien.
    if (widget.unlockCost == 0) return _freeView();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_outline_rounded, color: Colors.black45),
            SizedBox(width: 8),
            Text('Contact verrouillé',
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
