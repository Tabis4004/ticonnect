import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/contact_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Portefeuille de crédits.
///
/// La prise de contact étant gratuite, les crédits servent désormais aux
/// options : mise en avant du profil, et les services payants à venir.
///
/// Le solde et l'historique sont en lecture seule : côté base, aucune
/// politique RLS n'autorise le client à écrire dans `credit_wallets` ni
/// `credit_transactions`. Tout mouvement passe par une fonction serveur.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  List<CreditTransaction> _history = [];
  bool _loading = true;
  bool _watchingAd = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _history = await WalletService.history();
      if (mounted) await context.read<AppSession>().refresh();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Gagner un crédit en regardant une vidéo — opt-in explicite.
  Future<void> _earnCredit() async {
    setState(() => _watchingAd = true);
    final id = await AdsService.showRewarded(AdKeys.unlockRewarded);
    if (!mounted) return;
    setState(() => _watchingAd = false);

    if (id == null) {
      showError(context,
          "La récompense n'a pas pu être validée. Réessaie dans un moment.");
    } else {
      showOk(context, 'Crédit ajouté');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes crédits')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Text('Solde disponible',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text('${session.credits}',
                  style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Text('crédits', style: TextStyle(color: Colors.white70)),
              if ((session.worker?.freeUnlocksLeft ?? 0) > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '+ ${session.worker!.freeUnlocksLeft} déverrouillage(s) offert(s)',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              if (_watchingAd)
                const Loading()
              else
                FilledButton.icon(
                  onPressed: _earnCredit,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text('Regarder une vidéo (+1 crédit)'),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Bientôt disponible'),
                    content: Text(
                      'Le paiement par Mobile Money (Orange Money, MTN MoMo, Wave) '
                      'arrive prochainement.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.phone_android),
                label: const Text('Acheter des crédits (Mobile Money)'),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Historique',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          if (_loading)
            const Loading()
          else if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun mouvement pour le moment.',
                  style: TextStyle(color: Colors.black54)),
            )
          else
            for (final t in _history)
              ListTile(
                leading: Icon(
                  t.amount > 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: t.amount > 0 ? AppTheme.primary : Colors.black45,
                ),
                title: Text(t.description ?? _label(t.type)),
                subtitle: Text(Fmt.ago(t.createdAt)),
                trailing: Text(
                  '${t.amount > 0 ? "+" : ""}${t.amount}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: t.amount > 0 ? AppTheme.primary : Colors.black87,
                  ),
                ),
              ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  static String _label(String type) => switch (type) {
        'purchase' => 'Achat de crédits',
        'ad_reward' => 'Vidéo regardée',
        'spend_unlock' => 'Contact débloqué',
        'spend_boost' => 'Mise en avant',
        'refund' => 'Remboursement',
        'bonus' => 'Bonus',
        _ => type,
      };
}
