import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/referral_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Parrainage : l'ouvrier invite ses clients.
///
/// L'écran ne parle jamais de « points » ni de « score », et ce n'est pas
/// une question de vocabulaire. La récompense est du temps de mise en
/// avant, plafonné et soumis aux mêmes règles que le reste : promettre un
/// classement qu'on ne peut pas tenir se retourne au premier client déçu.
class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});
  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  ReferralStats? _stats;
  List<ReferralEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ReferralService.stats(),
        ReferralService.mine(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as ReferralStats?;
        _entries = results[1] as List<ReferralEntry>;
      });
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showOk(context, 'Code copié');
  }

  Future<void> _share(String code) async {
    final text = Uri.encodeComponent(ReferralService.invitation(code));
    final uri = Uri.parse('https://wa.me/?text=$text');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception();
    } catch (_) {
      // WhatsApp absent : le presse-papier fait le travail, l'ouvrier
      // collera où il veut.
      await Clipboard.setData(
          ClipboardData(text: ReferralService.invitation(code)));
      if (mounted) showOk(context, 'Message copié, colle-le où tu veux');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final code = _stats?.code ?? session.profile?.referralCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Inviter mes clients')),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                  'Fais venir tes clients, remonte dans les résultats',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Envoie ton code à tes anciens clients. Quand l\'un d\'eux '
                  'publie une mission et reçoit une première proposition, ton '
                  'profil est mis en avant plusieurs jours dans la recherche.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                if (code != null) _codeCard(code),
                const SizedBox(height: 20),
                _statsRow(),
                const SizedBox(height: 8),
                _rulesCard(),
                const SizedBox(height: 24),
                const Text('Mes invitations',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  const Text(
                    'Personne pour le moment. Commence par tes trois derniers '
                    'clients : ce sont eux qui reviendront le plus vite.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  )
                else
                  for (final e in _entries) _entryTile(e),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }

  Widget _codeCard(String code) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          const Text('Ton code',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(
            code,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copy(code),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copier'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _share(code),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Partager'),
              ),
            ),
          ]),
        ]),
      );

  Widget _statsRow() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();
    return Row(children: [
      _stat('${s.qualified}', 'validés'),
      _stat('${s.pending}', 'en attente'),
      _stat('${s.boostDaysTotal}', 'jours gagnés'),
    ]);
  }

  Widget _stat(String value, String label) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6EAE7)),
          ),
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: AppTheme.primary)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      );

  /// Les règles sont annoncées, y compris le plafond.
  ///
  /// Un ouvrier qui découvre après coup qu'il ne gagne plus rien se sent
  /// floué — et le dit autour de lui, sur un marché où le bouche-à-oreille
  /// entre gens de métier fait la réputation d'une application.
  Widget _rulesCard() {
    final s = _stats;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Comment ça marche',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _rule('Ton client publie une mission et reçoit une première '
            'proposition — c\'est là que l\'invitation compte. Une simple '
            'inscription ne suffit pas.'),
        _rule('Le premier client invité rapporte 7 jours de mise en avant, '
            'le deuxième 5, le troisième 3, puis 1 jour chacun.'),
        if (s != null)
          _rule('Maximum ${s.monthlyCap} jours par mois. '
              '${s.capReached ? "Plafond atteint pour ce mois-ci." : "Il te reste ${s.remainingThisMonth} jours à gagner."}'),
        _rule('Les places mises en avant sont limitées et réservées aux '
            'profils bien notés. Les abonnés Premium y passent d\'abord : '
            'la recherche doit rester utile au client.'),
      ]),
    );
  }

  Widget _rule(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('· ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ]),
      );

  Widget _entryTile(ReferralEntry e) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          dense: true,
          leading: Icon(
            e.isQualified
                ? Icons.check_circle
                : e.isRevoked
                    ? Icons.block
                    : Icons.hourglass_empty,
            color: e.isQualified
                ? AppTheme.primary
                : e.isRevoked
                    ? AppTheme.danger
                    : Colors.black38,
          ),
          title: Text(e.refereeName ?? 'Invitation'),
          subtitle: Text(
            e.isQualified
                ? '+${e.boostDays} jour(s) · ${Fmt.ago(e.qualifiedAt)}'
                : e.isRevoked
                    ? 'Annulée'
                    : 'En attente d\'une première mission · ${Fmt.ago(e.createdAt)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
}

/// Saisie d'un code, côté filleul.
///
/// Proposée au client après son inscription. La fenêtre de réclamation est
/// limitée côté base : au-delà, il ne s'agit plus d'acquisition.
class ReferralClaimSheet {
  static Future<bool> show(BuildContext context) async {
    final controller = TextEditingController();
    var busy = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tu as un code d\'invitation ?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Si un ouvrier t\'a donné son code, saisis-le ici. Cela l\'aide '
              'à être vu davantage, et ne te coûte rien.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 6),
              decoration: const InputDecoration(
                hintText: 'ABC123',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            if (busy)
              const Loading()
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final code = controller.text.trim();
                    if (code.length < 4) return;
                    setSheetState(() => busy = true);
                    try {
                      await ReferralService.claim(code);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setSheetState(() => busy = false);
                      if (ctx.mounted) showError(ctx, humanError(e));
                    }
                  },
                  child: const Text('Valider'),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Je n\'en ai pas'),
            ),
          ]),
        ),
      ),
    );

    controller.dispose();
    return ok == true;
  }
}
