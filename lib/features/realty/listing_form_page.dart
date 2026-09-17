import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/realty_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import 'realty_widgets.dart';

/// Dépôt ou modification d'une annonce.
///
/// L'annonce naît en brouillon et ne se publie qu'au dernier geste. Publier
/// à la création ferait apparaître dans la liste, le temps que le vendeur
/// choisisse ses photos, une annonce sans image — la pire première
/// impression pour quelqu'un qui découvre la rubrique.
class ListingFormPage extends StatefulWidget {
  const ListingFormPage({super.key, this.existante});

  final Listing? existante;

  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  final _titre = TextEditingController();
  final _description = TextEditingController();
  final _ville = TextEditingController();
  final _quartier = TextEditingController();
  final _adresse = TextEditingController();
  final _telephone = TextEditingController();
  final _prix = TextEditingController();
  final _surface = TextEditingController();
  final _pieces = TextEditingController();
  final _reference = TextEditingController();

  String _deal = 'vente';
  String _bien = 'terrain';
  String _periode = 'mois';

  final _photos = <XFile>[];
  XFile? _plan;

  bool _busy = false;
  String? _id;

  @override
  void initState() {
    super.initState();
    final l = widget.existante;
    if (l != null) {
      _id = l.id;
      _titre.text = l.title;
      _description.text = l.description ?? '';
      _ville.text = l.city;
      _quartier.text = l.neighborhood ?? '';
      _prix.text = l.price.toStringAsFixed(0);
      _surface.text = l.surfaceM2?.toStringAsFixed(0) ?? '';
      _pieces.text = l.rooms?.toString() ?? '';
      _reference.text = l.landReference ?? '';
      _deal = l.deal;
      _bien = l.property;
      _periode = l.pricePeriod ?? 'mois';
    }
  }

  @override
  void dispose() {
    for (final c in [_titre, _description, _ville, _quartier, _adresse,
                     _telephone, _prix, _surface, _pieces, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  /// La référence n'est exigée qu'en vente. Un loueur de chambre n'a pas le
  /// titre foncier entre les mains, et l'exiger de lui viderait la
  /// catégorie qui fera le volume.
  bool get _referenceExigee => _deal == 'vente';

  /// Un terrain ne se loue pas dans ce module : la base le refuse, autant
  /// que le formulaire ne le propose pas.
  List<MapEntry<String, String>> get _biensPossibles => [
        for (final e in kBiens.entries)
          if (!(e.key == 'terrain' && _deal == 'location')) e,
      ];

  Future<void> _choisirPhotos() async {
    // `maxWidth` et `imageQuality` font le redimensionnement et le
    // réencodage JPEG dans le sélecteur : pas besoin d'une bibliothèque de
    // traitement d'image de plusieurs mégaoctets pour un cadrage.
    final choisies = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (choisies.isEmpty) return;
    setState(() => _photos.addAll(choisies.take(8 - _photos.length)));
  }

  Future<void> _choisirPlan() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (x != null) setState(() => _plan = x);
  }

  String? _valider() {
    if (_titre.text.trim().length < 5) return 'Donne un titre plus précis.';
    if (_ville.text.trim().isEmpty) return 'Indique la ville.';
    final prix = num.tryParse(_prix.text.replaceAll(RegExp(r'\s'), ''));
    if (prix == null || prix <= 0) return 'Indique un prix.';
    if (_referenceExigee && _reference.text.trim().length < 4) {
      return 'La référence foncière est obligatoire pour une vente.';
    }
    if (_telephone.text.trim().isEmpty && widget.existante == null) {
      return 'Indique le numéro à joindre.';
    }
    return null;
  }

  Future<void> _enregistrer({required bool publier}) async {
    final faute = _valider();
    if (faute != null) {
      showError(context, faute);
      return;
    }
    setState(() => _busy = true);

    try {
      final pays = context.read<AppSession>().profile?.countryCode ?? 'TG';
      final valeurs = <String, dynamic>{
        'deal': _deal,
        'property': _bien,
        'title': _titre.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'country_code': pays,
        'city': _ville.text.trim(),
        'neighborhood':
            _quartier.text.trim().isEmpty ? null : _quartier.text.trim(),
        'address_exact':
            _adresse.text.trim().isEmpty ? null : _adresse.text.trim(),
        'contact_phone':
            _telephone.text.trim().isEmpty ? null : _telephone.text.trim(),
        'price': num.parse(_prix.text.replaceAll(RegExp(r'\s'), '')),
        'price_period': _deal == 'location' ? _periode : null,
        'surface_m2': num.tryParse(_surface.text.trim()),
        'rooms': int.tryParse(_pieces.text.trim()),
        'land_reference':
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      };

      _id ??= await RealtyService.create(valeurs);
      if (widget.existante != null) {
        await RealtyService.update(_id!, valeurs);
      }

      for (var i = 0; i < _photos.length; i++) {
        await RealtyService.addMedia(
          listingId: _id!,
          fichier: _photos[i],
          kind: 'photo',
          sortOrder: i,
        );
      }
      if (_plan != null) {
        await RealtyService.addMedia(
          listingId: _id!,
          fichier: _plan!,
          kind: 'plan',
        );
      }

      if (publier) await RealtyService.publish(_id!);

      if (mounted) {
        showOk(context, publier ? 'Annonce en ligne' : 'Brouillon enregistré');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette annonce ?'),
        content: const Text(
            'Elle disparaîtra pour tout le monde, y compris pour ceux qui '
            "l'avaient ouverte."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Supprimer',
                style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || _id == null) return;
    try {
      await RealtyService.remove(_id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existante == null ? 'Déposer une annonce' : 'Modifier'),
        actions: [
          if (_id != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _supprimer,
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _segments(
          valeurs: kOperations,
          actuel: _deal,
          onChange: (v) => setState(() {
            _deal = v;
            if (v == 'location' && _bien == 'terrain') _bien = 'chambre';
          }),
        ),
        const SizedBox(height: 10),
        _selecteur(
          label: 'Type de bien',
          valeur: kBiens[_bien] ?? _bien,
          options: {for (final e in _biensPossibles) e.key: e.value},
          onChange: (v) => setState(() => _bien = v),
        ),
        const SizedBox(height: 12),
        _champ(_titre, 'Titre', hint: 'Terrain 600 m² viabilisé, Agoè'),
        _champ(_description, 'Description', lignes: 4),
        Row(children: [
          Expanded(child: _champ(_ville, 'Ville')),
          const SizedBox(width: 10),
          Expanded(child: _champ(_quartier, 'Quartier')),
        ]),
        Row(children: [
          Expanded(
            child: _champ(_prix, 'Prix', clavier: TextInputType.number),
          ),
          if (_deal == 'location') ...[
            const SizedBox(width: 10),
            Expanded(
              child: _selecteur(
                label: 'Période',
                valeur: kPeriodes[_periode] ?? _periode,
                options: kPeriodes,
                onChange: (v) => setState(() => _periode = v),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _champ(_surface, 'Surface (m²)',
                  clavier: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(
              child:
                  _champ(_pieces, 'Pièces', clavier: TextInputType.number)),
        ]),

        _champ(_reference,
            _referenceExigee
                ? 'Référence foncière (obligatoire)'
                : 'Référence foncière (facultative)',
            hint: 'Au Togo : le NUP'),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            _referenceExigee
                ? 'Elle sera affichée en clair sur ton annonce. C\'est elle '
                    'qui permet à un acheteur de vérifier le titre — une '
                    'annonce sans référence inspire peu confiance.'
                : 'Facultative pour une location. Si tu l\'as, indique-la : '
                    'elle rassure.',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),

        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Ce qui ne s\'ouvre qu\'après déblocage',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        _champ(_adresse, 'Adresse exacte'),
        _champ(_telephone, 'Numéro à joindre',
            clavier: TextInputType.phone,
            hint: 'Laisse vide pour utiliser ton numéro de compte'),

        const SizedBox(height: 8),
        _blocFichiers(),

        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _enregistrer(publier: false),
              child: const Text('Brouillon'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _enregistrer(publier: true),
              child: Text(_busy ? 'Un instant…' : 'Publier'),
            ),
          ),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _blocFichiers() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _choisirPhotos,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text('Photos (${_photos.length})'),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _choisirPlan,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: Text(_plan == null ? 'Plan' : 'Plan choisi'),
        ),
      ]),
      const SizedBox(height: 8),
      const Text(
        'Une vignette floutée de chaque photo sera visible de tous ; les '
        'photos en pleine définition et le plan ne s\'ouvrent qu\'après '
        'déblocage. Chaque copie du plan porte le nom de celui qui l\'a '
        'ouverte.',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      const SizedBox(height: 6),
      const Text(
        'Images uniquement pour le moment — photographie ton plan plutôt '
        'que de déposer un PDF.',
        style: TextStyle(fontSize: 11, color: AppTheme.accent),
      ),
    ]);
  }

  /// Un sélecteur qui ouvre une feuille, plutôt qu'un `DropdownButtonFormField`.
  ///
  /// Ce n'est pas un choix esthétique : le paramètre de valeur initiale de
  /// ce composant a changé de nom entre deux versions de Flutter, et se
  /// tromper ne donne pas un avertissement mais une erreur de compilation.
  /// La feuille modale, elle, est celle qu'on utilise déjà pour les niveaux
  /// d'accès, et elle laisse de la place pour des libellés longs.
  Widget _selecteur({
    required String label,
    required String valeur,
    required Map<String, String> options,
    required ValueChanged<String> onChange,
  }) =>
      InkWell(
        onTap: _busy
            ? null
            : () async {
                final choix = await showModalBottomSheet<String>(
                  context: context,
                  builder: (c) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      for (final e in options.entries)
                        ListTile(
                          title: Text(e.value),
                          trailing: e.value == valeur
                              ? const Icon(Icons.check,
                                  color: AppTheme.primary)
                              : null,
                          onTap: () => Navigator.pop(c, e.key),
                        ),
                      const SizedBox(height: 8),
                    ]),
                  ),
                );
                if (choix != null) onChange(choix);
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Row(children: [
            Expanded(child: Text(valeur)),
            const Icon(Icons.arrow_drop_down, color: Colors.black45),
          ]),
        ),
      );

  Widget _segments({
    required Map<String, String> valeurs,
    required String actuel,
    required ValueChanged<String> onChange,
  }) =>
      SegmentedButton<String>(
        segments: [
          for (final e in valeurs.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {actuel},
        onSelectionChanged: (s) => onChange(s.first),
      );

  Widget _champ(TextEditingController c, String label,
          {String? hint, int lignes = 1, TextInputType? clavier}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lignes,
          keyboardType: clavier,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}
