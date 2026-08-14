import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/catalog_service.dart';
import '../../services/session.dart';
import '../../services/settings_service.dart';
import '../../services/workers_service.dart';
import '../../widgets/ad_intro.dart';
import '../../widgets/common.dart';
import 'trade_picker_page.dart';
import '../worker/wallet_page.dart';
import 'admin_page.dart';
import 'contact_page.dart';
import 'referral_page.dart';
import 'subscription_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _switching = false;
  bool _boosting = false;

  /// Mise en avant contre visionnage.
  ///
  /// L'écran d'introduction n'est pas décoratif : il annonce la
  /// récompense et laisse une porte de sortie, ce qu'AdMob exige des
  /// formats récompensés. Le retirer met le compte en infraction.
  Future<void> _boost() async {
    if (_boosting) return;

    final blocage = await AdsService.blockReason(AdKeys.boostRewarded);
    if (blocage != null) {
      if (mounted) showError(context, blocage);
      return;
    }
    if (!mounted) return;

    final accepted = await AdIntro.ask(context, AdKeys.boostRewarded);
    if (!accepted || !mounted) return;

    setState(() => _boosting = true);
    final res = await WorkersService.boostByWatchingAd();
    if (!mounted) return;
    setState(() => _boosting = false);

    if (res.ok) {
      await context.read<AppSession>().refresh();
      if (!mounted) return;
      final until = res.boostedUntil;
      showOk(
        context,
        until == null
            ? 'Ton profil remonte dans les résultats'
            : 'En tête jusqu\'à ${Fmt.time(until)}',
      );
    } else {
      showError(context, res.message ?? 'Réessaie plus tard.');
    }
  }

  /// Disponibilité : c'est ce drapeau qui décide si l'ouvrier remonte dans
  /// l'annuaire et s'il reçoit les alertes de nouvelles missions.
  Future<void> _toggleAvailability(bool available) async {
    setState(() => _switching = true);
    try {
      await WorkersService.setAvailability(available ? 'available' : 'unavailable');
      if (mounted) await context.read<AppSession>().refresh();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _switching = false);
  }

  /// Ajoute ou retire le versant client.
  ///
  /// Méthode de l'État plutôt que fermeture posée dans `onChanged` : dans
  /// une fermeture, `mounted` est capturé et l'analyseur ne peut plus le
  /// relier au `BuildContext` utilisé après l'await. Le code fonctionnait,
  /// mais `use_build_context_synchronously` le signalait — à juste titre,
  /// puisque rien ne garantissait la relation.
  Future<void> _toggleAlsoClient(bool aussiClient) async {
    setState(() => _switching = true);
    try {
      await WorkersService.setAlsoClient(aussiClient);
      if (mounted) await context.read<AppSession>().refresh();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _switching = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final p = session.profile;
    if (p == null) return const Scaffold(body: Loading());
    final available = session.worker?.availability == 'available';
    final boosted = session.worker?.isBoosted ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('Mon compte'.tr)),
      body: ListView(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Text(p.fullName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ),
            const SizedBox(height: 12),
            Text(p.fullName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              p.username != null ? '@${p.username}' : (p.isWorker ? 'Ouvrier' : 'Client'),
              style: const TextStyle(color: Colors.black54),
            ),
            if (session.worker != null) ...[
              const SizedBox(height: 8),
              RatingStars(
                rating: session.worker!.ratingAvg,
                count: session.worker!.ratingCount,
                size: 18,
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text('Langue'.tr),
          trailing: DropdownButton<String>(
            value: L.instance.lang,
            underline: const SizedBox.shrink(),
            items: [
              for (final e in L.supported.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) context.read<AppSession>().setLanguage(v);
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.contact_phone_outlined),
          title: Text('Mes coordonnées'.tr),
          subtitle: Text('Téléphone, WhatsApp, email, position'.tr),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactPage()),
            );
            if (context.mounted) await context.read<AppSession>().refresh();
          },
        ),
        const Divider(height: 1),
        // Un ouvrier sans métier déclaré n'existe pour personne : il ne
        // sort d'aucune recherche et ne reçoit aucune alerte de mission.
        // La base l'exclut désormais de l'annuaire — encore faut-il le lui
        // dire, sinon il attend un travail qui ne peut pas arriver.
        //
        // `is_listed` vaut exactement « a déclaré un métier » depuis la
        // migration : aucune requête supplémentaire n'est nécessaire.
        if (p.isWorker && session.worker?.isListed == false)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.visibility_off_outlined,
                    size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Ton profil n\'est pas visible',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Choisis au moins un métier pour apparaître dans les '
                'recherches et recevoir les missions près de chez toi. '
                'Sans métier, personne ne peut te trouver.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WorkerSetupPage()),
                    );
                    if (context.mounted) {
                      await context.read<AppSession>().refresh();
                    }
                  },
                  child: const Text('Choisir mon métier'),
                ),
              ),
            ]),
          ),
        if (p.isWorker) ...[
          SwitchListTile(
            secondary: Icon(
              available ? Icons.podcasts_rounded : Icons.pause_circle_outline,
              color: available ? AppTheme.primary : Colors.black45,
            ),
            title: Text(available ? 'Disponible'.tr : 'Indisponible'.tr),
            subtitle: Text(
              available
                  ? 'Tu apparais dans l\'annuaire et reçois les alertes.'
                  : 'Masqué de l\'annuaire, aucune alerte.',
              style: const TextStyle(fontSize: 12),
            ),
            value: available,
            onChanged: _switching ? null : _toggleAvailability,
          ),
          const Divider(height: 1),
          // Le geste qui finance l'application. Volontairement placé juste
          // sous la disponibilité : ce sont les deux leviers quotidiens de
          // l'ouvrier sur sa propre visibilité.
          ListTile(
            leading: _boosting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    boosted ? Icons.rocket_launch : Icons.rocket_launch_outlined,
                    color: boosted ? AppTheme.accent : null,
                  ),
            title: Text(boosted ? 'Tu es en tête'.tr : 'Passer en tête'.tr),
            subtitle: Text(
              boosted
                  ? 'Jusqu\'à ${Fmt.time(session.worker!.boostedUntil!)} — '
                      'regarde une autre vidéo pour prolonger'
                  : 'Regarde une courte vidéo, ton profil remonte dans les '
                      'résultats de recherche',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.play_circle_outline,
                color: Colors.black38),
            onTap: _boosting ? null : _boost,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.toll_outlined),
            title: Text('Mes crédits'.tr),
            trailing: Text('${session.credits}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
          ),
          const Divider(height: 1),
          // Un ouvrier a lui aussi des besoins : faire réparer sa moto,
          // repeindre sa boutique. Le rôle `both` existait en base depuis
          // l'origine sans aucun moyen de l'atteindre depuis l'interface.
          SwitchListTile(
            secondary: const Icon(Icons.swap_horiz),
            title: Text('J\'ai aussi des besoins'.tr),
            subtitle: Text(
              session.profile!.isClient
                  ? 'Tu peux chercher un ouvrier et publier des demandes.'
                  : 'Active pour chercher un ouvrier et publier tes propres '
                      'demandes, sans quitter ton profil ouvrier.',
              style: const TextStyle(fontSize: 12),
            ),
            value: session.profile!.isClient,
            onChanged: _switching ? null : _toggleAlsoClient,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: Text('Mon profil ouvrier'.tr),
            subtitle: Text('Métiers, tarifs, disponibilité'.tr),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkerSetupPage()),
            ),
          ),
          // Abonnements : masqués tant que le réglage est à faux. Le modèle
          // repose sur le boost gagné par visionnage, mais tout le code de
          // souscription reste en place derrière cet interrupteur.
          //
          // Un abonné existant garde l'accès à son abonnement en cours : le
          // couper sans prévenir quelqu'un qui a payé serait indéfendable.
          if (SettingsService.boolean(SettingKeys.subscriptionsEnabled, false) ||
              session.isPro) ...[
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              session.isPremium
                  ? Icons.workspace_premium
                  : Icons.trending_up_outlined,
              color: session.isPro ? AppTheme.accent : null,
            ),
            title: Text(session.isPro ? 'Mon abonnement'.tr : 'Être vu davantage'.tr),
            subtitle: Text(
              switch (session.plan) {
                'premium' => 'Premium — position sponsorisée active',
                'pro' => 'Pro — profil mis en avant',
                _ => 'Aucune commission sur ton travail, jamais',
              },
              style: const TextStyle(fontSize: 12),
            ),
            trailing: session.isPro
                ? null
                : const Icon(Icons.chevron_right, color: Colors.black38),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionPage()),
              );
              if (context.mounted) await context.read<AppSession>().refresh();
            },
          ),
          ],
          const Divider(height: 1),
          // Parrainage de CLIENTS, jamais d'ouvriers. Faire venir d'autres
          // ouvriers diluerait son propre fil de missions ; faire venir des
          // clients apporte du travail dont il profite le premier.
          //
          // Dans un modèle sans abonnement, c'est la seule source de boost
          // corrélée au fait d'amener de la demande réelle plutôt qu'au
          // temps libre disponible pour regarder des vidéos.
          if (SettingsService.boolean(SettingKeys.referralEnabled, true))
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text('Inviter mes clients'.tr),
            subtitle: const Text(
              'Ils publient une mission, ton profil remonte',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black38),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReferralPage()),
              );
              if (context.mounted) await context.read<AppSession>().refresh();
            },
          ),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.construction_outlined),
            title: Text('Devenir ouvrier'.tr),
            subtitle: const Text('Recevoir des missions près de chez toi'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkerSetupPage()),
            ),
          ),
          const Divider(height: 1),
          // Côté client, le parrainage ne rapporte rien à celui qui saisit
          // le code — c'est son ouvrier qui gagne de la visibilité. Le dire
          // ainsi vaut mieux qu'inventer un avantage qui n'existe pas.
          ListTile(
            leading: const Icon(Icons.card_giftcard_outlined),
            title: Text('J\'ai un code d\'invitation'.tr),
            subtitle: const Text(
              'Un ouvrier t\'a recommandé l\'application ? Aide-le à être vu',
              style: TextStyle(fontSize: 12),
            ),
            onTap: () async {
              final ok = await ReferralClaimSheet.show(context);
              if (ok && context.mounted) {
                showOk(context, 'Code enregistré. Merci !');
              }
            },
          ),
        ],
        if (session.isAdmin) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: AppTheme.primary),
            title: Text('Administration'.tr),
            subtitle: const Text('Statistiques, signalements, fuite de contacts'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminPage()),
            ),
          ),
        ],
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: AppTheme.danger),
          title: Text('Se déconnecter'.tr,
              style: const TextStyle(color: AppTheme.danger)),
          onTap: () => context.read<AppSession>().signOut(),
        ),
      ]),
    );
  }
}

/// Création ou édition du profil ouvrier.
class WorkerSetupPage extends StatefulWidget {
  const WorkerSetupPage({super.key});
  @override
  State<WorkerSetupPage> createState() => _WorkerSetupPageState();
}

class _WorkerSetupPageState extends State<WorkerSetupPage> {
  final _headline = TextEditingController();
  final _years = TextEditingController();
  final _rateMin = TextEditingController();
  final _rateMax = TextEditingController();

  // Le catalogue reste chargé ici pour afficher le nom des métiers retenus :
  // `worker_trades` ne stocke que des identifiants, et l'écran de choix
  // rend lui aussi des identifiants.
  List<Trade> _trades = [];
  final Set<int> _selected = {};

  /// Les métiers retenus, dans l'ordre du catalogue plutôt que dans celui
  /// des clics : deux ouvertures de l'écran donneraient sinon deux ordres
  /// différents pour la même sélection.
  List<Trade> get _selectedTrades =>
      _trades.where((t) => _selected.contains(t.id)).toList();

  Future<void> _pickTrades() async {
    final r = await Navigator.push<Set<int>>(
      context,
      MaterialPageRoute(builder: (_) => TradePickerPage(initial: _selected)),
    );
    if (r == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(r);
    });
  }
  String _pricingUnit = 'day';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _trades = await CatalogService.trades();

    // Le catalogue vient du réseau : l'écran peut avoir été quitté entre
    // temps, et lire le contexte après un `await` sans ce garde-fou est
    // exactement ce que signale `use_build_context_synchronously`.
    if (!mounted) return;

    final session = context.read<AppSession>();
    final w = session.worker;
    if (w != null) {
      _headline.text = w.headline ?? '';
      _years.text = w.yearsExperience?.toString() ?? '';
      _rateMin.text = w.rateMin?.toStringAsFixed(0) ?? '';
      _rateMax.text = w.rateMax?.toStringAsFixed(0) ?? '';
      _pricingUnit = w.pricingUnit;
      final mine = await WorkersService.tradesOf(w.profileId);
      _selected.addAll(mine.map((t) => t.id));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_headline, _years, _rateMin, _rateMax]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      showError(context, 'Choisis au moins un métier');
      return;
    }
    setState(() => _busy = true);
    try {
      await WorkersService.upsertMine(
        headline: _headline.text.trim().isEmpty ? null : _headline.text.trim(),
        yearsExperience: int.tryParse(_years.text.trim()),
        rateMin: double.tryParse(_rateMin.text.trim()),
        rateMax: double.tryParse(_rateMax.text.trim()),
        pricingUnit: _pricingUnit,
      );
      await WorkersService.setTrades(_selected.toList());
      if (!mounted) return;
      await context.read<AppSession>().refresh();
      if (mounted) {
        showOk(context, 'Profil enregistré');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mon profil ouvrier'.tr)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _headline,
          decoration: const InputDecoration(
            labelText: 'Une phrase sur toi',
            hintText: 'Maçon, 12 ans de chantier',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _years,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Années d'expérience"),
        ),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(
            child: Text('Tes métiers',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          // « Modifier » plutôt que « Choisir » une fois la sélection faite :
          // le libellé dit ce que le geste change, pas ce qu'il ouvre.
          TextButton.icon(
            onPressed: _pickTrades,
            icon: Icon(_selected.isEmpty ? Icons.add : Icons.edit_outlined,
                size: 18),
            label: Text(_selected.isEmpty ? 'Choisir' : 'Modifier'),
          ),
        ]),
        const SizedBox(height: 4),

        // Seuls les métiers retenus sont affichés. Le catalogue entier a
        // migré vers un écran dédié : le garder ici obligeait à parcourir
        // les catégories pour relire son propre choix, et un métier coché
        // dans une catégorie devenait invisible dès qu'on en ouvrait une
        // autre.
        if (_selected.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6EAE7)),
            ),
            child: const Text(
              'Aucun métier choisi. Sans métier, ton profil ne remonte dans '
              'aucune recherche et tu ne reçois aucune mission.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _selectedTrades)
              Chip(
                label: Text(t.nameFr),
                backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
                side: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.25)),
                labelStyle: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600),
              ),
          ]),
        const SizedBox(height: 20),
        const Text('Ton tarif', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _rateMin,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'De', suffixText: 'XOF'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _rateMax,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'À', suffixText: 'XOF'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'hour', label: Text('Par heure')),
            ButtonSegment(value: 'day', label: Text('Par jour')),
            ButtonSegment(value: 'project', label: Text('Forfait')),
          ],
          selected: {_pricingUnit},
          onSelectionChanged: (s) => setState(() => _pricingUnit = s.first),
        ),
        const SizedBox(height: 28),
        if (_busy)
          const Loading()
        else
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        const SizedBox(height: 16),
      ]),
    );
  }
}
