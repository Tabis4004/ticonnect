import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/realty_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import 'listing_form_page.dart';
import 'listing_page.dart';
import 'realty_widgets.dart';

/// Les annonces immobilières.
///
/// Filtrée par défaut sur le pays de l'utilisateur : un acheteur à Lomé
/// n'a rien à faire d'un terrain à Abidjan, et les deux marchés n'ont ni
/// les mêmes prix ni le même registre foncier.
class RealtyListPage extends StatefulWidget {
  const RealtyListPage({super.key});

  @override
  State<RealtyListPage> createState() => _RealtyListPageState();
}

class _RealtyListPageState extends State<RealtyListPage> {
  final _recherche = TextEditingController();
  List<Listing> _annonces = [];
  bool _loading = true;
  String? _erreur;

  String? _deal;
  String? _bien;
  bool _toutPays = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erreur = null;
    });
    try {
      final pays = context.read<AppSession>().profile?.countryCode;
      _annonces = await RealtyService.browse(
        countryCode: _toutPays ? null : pays,
        deal: _deal,
        property: _bien,
        recherche: _recherche.text,
      );
    } catch (e) {
      _erreur = humanError(e);
      _annonces = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deposer() async {
    final cree = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ListingFormPage()),
    );
    if (cree == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Immobilier'),
        actions: [
          IconButton(
            tooltip: 'Mes annonces',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyListingsPage()),
              );
              if (mounted) await _load();
            },
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _deposer,
        icon: const Icon(Icons.add),
        label: const Text('Déposer'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _recherche,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Quartier, ville, référence…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _load,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final e in kOperations.entries)
                _filtre(e.value, _deal == e.key,
                    () => setState(() => _deal = _deal == e.key ? null : e.key)),
              const SizedBox(width: 8),
              for (final e in kBiens.entries)
                _filtre(e.value, _bien == e.key,
                    () => setState(() => _bien = _bien == e.key ? null : e.key)),
              const SizedBox(width: 8),
              _filtre('Tous les pays', _toutPays,
                  () => setState(() => _toutPays = !_toutPays)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Loading()
              : _erreur != null
                  ? _vueErreur()
                  : _annonces.isEmpty
                      ? const EmptyState(
                          icon: Icons.home_work_outlined,
                          title: 'Aucune annonce',
                          subtitle: 'Change de filtre, ou dépose la tienne.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _annonces.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => ListingCard(
                              listing: _annonces[i],
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ListingPage(listingId: _annonces[i].id),
                                  ),
                                );
                                if (mounted) await _load();
                              },
                            ),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _filtre(String texte, bool actif, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(texte, style: const TextStyle(fontSize: 12)),
          selected: actif,
          onSelected: (_) {
            onTap();
            _load();
          },
        ),
      );

  Widget _vueErreur() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
          ]),
        ),
      );
}

/// Les annonces déposées par l'utilisateur, brouillons compris.
///
/// Un brouillon invisible ailleurs doit être retrouvable ici, sinon une
/// annonce commencée puis abandonnée disparaît sans que son auteur puisse
/// la finir ni la supprimer.
class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  List<Listing> _annonces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _annonces = await RealtyService.mine();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mes annonces (${_annonces.length})')),
      body: _loading
          ? const Loading()
          : _annonces.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open_outlined,
                  title: 'Aucune annonce',
                  subtitle: 'Les annonces que tu déposes apparaîtront ici.',
                )
              : ListView.separated(
                  itemCount: _annonces.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = _annonces[i];
                    return ListTile(
                      title: Text(l.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${kOperations[l.deal]} · ${kBiens[l.property]} · '
                        '${prixLisible(l)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _etat(l.status),
                          if (l.unlocksCount > 0)
                            Text('${l.unlocksCount} ouverture(s)',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black45)),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ListingFormPage(existante: l),
                          ),
                        );
                        if (mounted) await _load();
                      },
                    );
                  },
                ),
    );
  }

  Widget _etat(String status) {
    final (texte, couleur) = switch (status) {
      'publiee' => ('En ligne', AppTheme.primary),
      'brouillon' => ('Brouillon', Colors.orange.shade700),
      'suspendue' => ('Suspendue', Colors.red.shade700),
      'conclue' => ('Conclue', Colors.black45),
      _ => ('Expirée', Colors.black45),
    };
    return Text(texte,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: couleur));
  }
}
