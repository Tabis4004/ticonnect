import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../../services/session.dart';
import '../../services/workers_service.dart';
import '../../widgets/common.dart';
import '../worker/wallet_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final p = session.profile;
    if (p == null) return const Scaffold(body: Loading());

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.primary.withOpacity(0.12),
              child: Text(p.fullName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ),
            const SizedBox(height: 12),
            Text(p.fullName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(p.isWorker ? 'Ouvrier' : 'Client',
                style: const TextStyle(color: Colors.black54)),
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
        if (p.isWorker) ...[
          ListTile(
            leading: const Icon(Icons.toll_outlined),
            title: const Text('Mes crédits'),
            trailing: Text('${session.credits}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: const Text('Mon profil ouvrier'),
            subtitle: const Text('Métiers, tarifs, disponibilité'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkerSetupPage()),
            ),
          ),
        ] else
          ListTile(
            leading: const Icon(Icons.construction_outlined),
            title: const Text('Devenir ouvrier'),
            subtitle: const Text('Recevoir des missions près de chez toi'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkerSetupPage()),
            ),
          ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: AppTheme.danger),
          title: const Text('Se déconnecter',
              style: TextStyle(color: AppTheme.danger)),
          onTap: () => context.read<Session>().signOut(),
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

  List<TradeCategory> _categories = [];
  List<Trade> _trades = [];
  final Set<int> _selected = {};
  int? _categoryId;
  String _pricingUnit = 'day';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _categories = await CatalogService.categories();
    _trades = await CatalogService.trades();

    final session = context.read<Session>();
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
      await context.read<Session>().refresh();
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
    final visible = _trades.where((t) => t.categoryId == _categoryId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil ouvrier')),
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
        const Text('Tes métiers', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            ChoiceChip(
              label: Text(c.nameFr),
              selected: _categoryId == c.id,
              onSelected: (v) => setState(() => _categoryId = v ? c.id : null),
            ),
        ]),
        if (visible.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in visible)
              FilterChip(
                label: Text(t.nameFr),
                selected: _selected.contains(t.id),
                onSelected: (v) => setState(() {
                  v ? _selected.add(t.id) : _selected.remove(t.id);
                }),
              ),
          ]),
        ],
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('${_selected.length} métier(s) sélectionné(s)',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
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
