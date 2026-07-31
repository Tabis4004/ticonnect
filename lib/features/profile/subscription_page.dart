import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/billing_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Souscription à un abonnement.
///
/// Le mensuel est mis en avant, l'annuel proposé comme remise. Ce n'est pas
/// une préférence esthétique : le mobile money ouest-africain est une
/// culture de petits montants fréquents, et demander une année d'avance à
/// un artisan du secteur informel écarte la majorité de la cible. L'annuel
/// se vend par l'économie qu'il représente, jamais par l'obligation.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  List<PlanPrice> _prices = [];
  Subscription? _current;
  String _plan = 'free';
  bool _annual = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = context.read<AppSession>();
      final country = session.profile?.countryCode ?? 'CI';
      final results = await Future.wait([
        BillingService.prices(country),
        BillingService.currentPlan(),
        BillingService.current(),
      ]);
      if (!mounted) return;
      setState(() {
        _prices = results[0] as List<PlanPrice>;
        _plan = results[1] as String;
        _current = results[2] as Subscription?;
      });
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  PlanPrice? _priceFor(String plan) =>
      _find(plan, _annual ? 'annual' : 'monthly');

  PlanPrice? _find(String plan, String period) {
    for (final p in _prices) {
      if (p.plan == plan && p.billingPeriod == period) return p;
    }
    return null;
  }

  /// Économie réalisée sur l'annuel, exprimée en mois offerts.
  ///
  /// Calculée depuis la grille plutôt que codée en dur : le jour où un
  /// tarif change en base, l'argument commercial suit tout seul.
  int _monthsSaved(String plan) {
    final monthly = _find(plan, 'monthly');
    final annual = _find(plan, 'annual');
    if (monthly == null || annual == null || monthly.amount <= 0) return 0;
    final equivalent = annual.amount / monthly.amount;
    return (12 - equivalent).round().clamp(0, 11);
  }

  Future<void> _subscribe(String plan) async {
    final price = _priceFor(plan);
    if (price == null) {
      showError(context, 'Aucun tarif disponible pour ton pays.');
      return;
    }

    final provider = await _chooseProvider();
    if (provider == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final session = await BillingService.subscribe(
        plan: plan,
        billingPeriod: _annual ? 'annual' : 'monthly',
        provider: provider,
      );

      final opened = await launchUrl(
        Uri.parse(session.checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('Impossible d\'ouvrir la page de paiement.');

      if (!mounted) return;
      await _awaitConfirmation(session);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _chooseProvider() => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Comment veux-tu payer ?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Mobile Money et carte'),
              subtitle: const Text('Wave, Orange, MTN, Moov, carte bancaire'),
              onTap: () => Navigator.pop(ctx, 'geniuspay'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: const Text('FedaPay'),
              subtitle: const Text('Mobile Money et carte'),
              onTap: () => Navigator.pop(ctx, 'fedapay'),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      );

  /// Le règlement se termine hors de l'application ; au retour, il faut
  /// savoir si le webhook est passé. Un paiement mobile money se confirme
  /// en quelques secondes, rarement instantanément — d'où l'attente
  /// active, plutôt qu'une lecture unique qui afficherait « échec » à tort.
  Future<void> _awaitConfirmation(CheckoutSession session) async {
    var confirmed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        () async {
          for (var i = 0; i < 40; i++) {
            await Future.delayed(const Duration(seconds: 3));
            final status = await BillingService.paymentStatus(session.reference);
            if (status == 'success') {
              confirmed = true;
              break;
            }
            if (status == 'failed') break;
            if (!ctx.mounted) return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }();

        return AlertDialog(
          title: const Text('Paiement en cours'),
          content: const Column(mainAxisSize: MainAxisSize.min, children: [
            Loading(),
            SizedBox(height: 14),
            Text(
              'Termine le paiement dans la fenêtre qui vient de s\'ouvrir. '
              'Cet écran se met à jour tout seul.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (confirmed) {
      showOk(context, 'Abonnement activé.');
      await context.read<AppSession>().refresh();
      await _load();
    } else {
      showOk(context,
          'Paiement non confirmé pour le moment. Si tu as payé, ton '
          'abonnement s\'activera dans quelques instants.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement')),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_current != null && _current!.isActive) _currentCard(),
                  const Text(
                    'Plus de visibilité, plus de chantiers',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'TiConnect ne prend aucune commission sur ton travail. '
                    'Tu factures et tu encaisses directement, comme d\'habitude. '
                    'L\'abonnement achète de la visibilité, rien d\'autre.',
                    style: TextStyle(fontSize: 13, height: 1.45, color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(value: false, label: Text('Mensuel')),
                      ButtonSegment(
                        value: true,
                        label: Text(_monthsSaved('pro') > 0
                            ? 'Annuel · ${_monthsSaved('pro')} mois offerts'
                            : 'Annuel'),
                      ),
                    ],
                    selected: {_annual},
                    onSelectionChanged: (s) => setState(() => _annual = s.first),
                  ),
                  const SizedBox(height: 18),
                  _planCard(
                    plan: 'pro',
                    title: 'Pro',
                    tagline: 'Pour être vu par plus de clients',
                    features: const [
                      'Candidatures illimitées',
                      'Profil mis en avant dans ta ville',
                      'Statistiques de vues et de contacts',
                      'Jusqu\'à 10 annonces actives',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _planCard(
                    plan: 'premium',
                    title: 'Premium',
                    tagline: 'Position sponsorisée dans les résultats',
                    highlight: true,
                    features: const [
                      'Tout le plan Pro',
                      'Position sponsorisée dans la recherche de ton métier',
                      'Badge Premium sur ton profil',
                      'Support prioritaire',
                    ],
                    footnote:
                        'Les places sponsorisées sont limitées et réservées aux '
                        'profils bien notés : la recherche doit rester utile au '
                        'client, sinon plus personne ne l\'utilise.',
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Paiement par Mobile Money ou carte. Sans engagement : '
                    'l\'abonnement s\'arrête à l\'échéance si tu ne le renouvelles pas.',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _currentCard() => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.verified_outlined, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Abonnement ${_current!.plan == 'premium' ? 'Premium' : 'Pro'} actif',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_current!.expiresAt != null)
                Text(
                  'Jusqu\'au ${_current!.expiresAt!.day}/${_current!.expiresAt!.month}/${_current!.expiresAt!.year}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ]),
          ),
        ]),
      );

  Widget _planCard({
    required String plan,
    required String title,
    required String tagline,
    required List<String> features,
    bool highlight = false,
    String? footnote,
  }) {
    final price = _priceFor(plan);
    final isCurrent = _plan == plan;
    final saved = _annual ? _monthsSaved(plan) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? AppTheme.accent : const Color(0xFFE6EAE7),
          width: highlight ? 1.6 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (price != null)
            Text(
              Fmt.money(price.amount, price.currency),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
        ]),
        Row(children: [
          Text(tagline,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const Spacer(),
          Text(_annual ? '/ an' : '/ mois',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        if (saved > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$saved mois offerts',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 14),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        if (footnote != null) ...[
          const SizedBox(height: 6),
          Text(footnote,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _busy
              ? const Loading()
              : isCurrent
                  ? const OutlinedButton(
                      onPressed: null, child: Text('Ton plan actuel'))
                  : FilledButton(
                      onPressed: price == null ? null : () => _subscribe(plan),
                      child: Text(price == null
                          ? 'Indisponible'
                          : 'Choisir $title'),
                    ),
        ),
      ]),
    );
  }
}
