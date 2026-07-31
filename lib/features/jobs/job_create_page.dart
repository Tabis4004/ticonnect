import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../models/models.dart';
import '../../services/ads_service.dart';
import '../../services/catalog_service.dart';
import '../../services/jobs_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/common.dart';

/// Publication d'une demande. Entièrement gratuit pour le client :
/// c'est lui qui alimente la marketplace en travail.
///
/// La publicité côté client est un point d'équilibre délicat. Le côté rare
/// d'une marketplace de services n'est pas l'ouvrier — ils sont nombreux et
/// tolèrent beaucoup, puisqu'ils cherchent un revenu — mais le client qui a
/// un vrai chantier. Lui imposer une vidéo avant même qu'il puisse décrire
/// son problème ajoute de la friction à l'instant précis où son intention
/// est maximale et son engagement envers l'application encore nul.
///
/// Les deux placements existent donc, et `app_settings.client_job_ad_placement`
/// arbitre : « after » par défaut, « before » si les chiffres d'abandon
/// donnent tort à ce raisonnement. La bascule se fait depuis le tableau de
/// bord admin, sans republier.
class JobCreatePage extends StatefulWidget {
  const JobCreatePage({super.key});
  @override
  State<JobCreatePage> createState() => _JobCreatePageState();
}

class _JobCreatePageState extends State<JobCreatePage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _neighborhood = TextEditingController();
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();

  List<TradeCategory> _categories = [];
  List<Trade> _trades = [];
  int? _categoryId;
  int? _tradeId;
  String _urgency = 'flexible';
  String _pricingUnit = 'day';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CatalogService.categories().then((c) async {
      final t = await CatalogService.trades();
      if (mounted) {
        setState(() {
          _categories = c;
          _trades = t;
        });
      }
    });
    _maybeShowEntryAd();
  }

  /// Interstitiel « avant la saisie », si l'administrateur l'a activé.
  ///
  /// Affiché après le premier rendu plutôt que dans `initState` : un plein
  /// écran lancé pendant une transition de navigation est exactement ce
  /// qu'AdMob proscrit, et ce qui provoque les clics accidentels.
  Future<void> _maybeShowEntryAd() async {
    final mode = SettingsService.string(
        SettingKeys.clientJobAdPlacement, 'after');
    if (mode != 'before') return;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await AdsService.maybeShowInterstitial(AdKeys.jobPostBefore);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _city, _neighborhood, _budgetMin, _budgetMax]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_tradeId == null) {
      showError(context, 'Choisis un métier');
      return;
    }
    if (_title.text.trim().length < 5) {
      showError(context, 'Donne un titre plus explicite (5 caractères minimum)');
      return;
    }
    if (_description.text.trim().length < 10) {
      showError(context, 'Décris le travail en quelques mots');
      return;
    }
    if (_city.text.trim().isEmpty) {
      showError(context, 'Indique la ville');
      return;
    }

    setState(() => _busy = true);
    try {
      await JobsService.create(
        tradeId: _tradeId!,
        title: _title.text.trim(),
        description: _description.text.trim(),
        city: _city.text.trim(),
        neighborhood:
            _neighborhood.text.trim().isEmpty ? null : _neighborhood.text.trim(),
        budgetMin: double.tryParse(_budgetMin.text.trim()),
        budgetMax: double.tryParse(_budgetMax.text.trim()),
        urgency: _urgency,
        pricingUnit: _pricingUnit,
      );
      if (!mounted) return;
      showOk(context, 'Demande publiée. Les ouvriers vont la voir.');

      // Interstitiel « après validation » : l'engagement est acquis, la
      // demande est enregistrée. Si la publicité ne charge pas ou que le
      // plafond est atteint, on sort simplement de l'écran.
      final mode = SettingsService.string(
          SettingKeys.clientJobAdPlacement, 'after');
      if (mode == 'after') {
        await AdsService.maybeShowInterstitial(AdKeys.jobPostAfter);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTrades =
        _trades.where((t) => t.categoryId == _categoryId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Publier une demande')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Quel métier ?', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            ChoiceChip(
              label: Text(c.nameFr),
              selected: _categoryId == c.id,
              onSelected: (v) => setState(() {
                _categoryId = v ? c.id : null;
                _tradeId = null;
              }),
            ),
        ]),
        if (visibleTrades.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in visibleTrades)
              FilterChip(
                label: Text(t.nameFr),
                selected: _tradeId == t.id,
                onSelected: (v) => setState(() => _tradeId = v ? t.id : null),
              ),
          ]),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Titre',
            hintText: 'Construction mur de clôture',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Explique ce qu\'il y a à faire, les matériaux, la durée…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Ville'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _neighborhood,
              decoration: const InputDecoration(labelText: 'Quartier'),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Budget indicatif', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _budgetMin,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Minimum', suffixText: AppConfig.defaultCurrency),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _budgetMax,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Maximum', suffixText: AppConfig.defaultCurrency),
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
        const SizedBox(height: 20),
        const Text('Quand ?', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'immediate', label: Text('Urgent')),
            ButtonSegment(value: 'this_week', label: Text('Cette semaine')),
            ButtonSegment(value: 'flexible', label: Text('Flexible')),
          ],
          selected: {_urgency},
          onSelectionChanged: (s) => setState(() => _urgency = s.first),
        ),
        const SizedBox(height: 28),
        if (_busy)
          const Loading()
        else
          FilledButton(onPressed: _submit, child: const Text('Publier')),
        const SizedBox(height: 16),
      ]),
    );
  }
}
