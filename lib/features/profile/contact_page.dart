import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/countries.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/contact_service.dart';
import '../../services/location_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import '../../widgets/country_picker.dart';
import '../../widgets/location_map.dart';

/// Coordonnées et position, renseignées après l'inscription.
///
/// Séparer ça du formulaire d'inscription est délibéré : demander un numéro
/// à quelqu'un qui n'a pas encore vu le produit, c'est le perdre. Ici, la
/// personne a parcouru l'annuaire et comprend à quoi ça sert.
///
/// Seul le téléphone est obligatoire — c'est par lui que la mise en relation
/// se fait. L'email et la position sont facultatifs.
class ContactPage extends StatefulWidget {
  const ContactPage({super.key});
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _neighborhood = TextEditingController();

  Country _country = Countries.byCode(AppConfig.defaultCountry);
  ({double lat, double lon})? _position;
  bool _loading = true;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_phone, _whatsapp, _email, _city, _neighborhood]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = context.read<AppSession>().profile;
    if (p != null) {
      _city.text = p.city ?? '';
      _neighborhood.text = p.neighborhood ?? '';
      _country = Countries.byCode(p.countryCode);
    }
    try {
      final c = await ContactService.read(uid!);
      if (c != null) {
        _phone.text = c.phone;
        _whatsapp.text = c.whatsapp ?? '';
        _email.text = c.email ?? '';
      }
    } catch (_) {
      // Pas encore de coordonnées : champs vides, cas normal après inscription.
    }
    _position = await LocationService.saved();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final pos = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) _position = pos;
    });
    if (pos == null && mounted) {
      showError(context,
          "Position indisponible. Vérifie que le GPS est activé et l'autorisation accordée.");
    }
  }

  Future<void> _clearPosition() async {
    setState(() => _position = null);
    try {
      await LocationService.clear();
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_phone.text.trim().length < 6) {
      showError(context, 'Entre un numéro valide');
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showError(context, 'Adresse email invalide');
      return;
    }

    setState(() => _busy = true);
    try {
      await ContactService.saveMine(
        phone: AuthService.normalizePhone(_phone.text, dialCode: _country.dialCode),
        whatsapp: _whatsapp.text.trim().isEmpty
            ? null
            : AuthService.normalizePhone(_whatsapp.text, dialCode: _country.dialCode),
        email: email.isEmpty ? null : email,
      );

      await db.from('profiles').update({
        'country_code': _country.code,
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'neighborhood':
            _neighborhood.text.trim().isEmpty ? null : _neighborhood.text.trim(),
      }).eq('id', uid!);

      if (_position != null) {
        await LocationService.save(_position!.lat, _position!.lon);
      }

      if (!mounted) return;
      await context.read<AppSession>().refresh();
      if (mounted) {
        showOk(context, 'Coordonnées enregistrées');
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
    if (_loading) return const Scaffold(body: Loading());

    return Scaffold(
      appBar: AppBar(title: const Text('Mes coordonnées')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
          "Ton numéro reste privé. Il n'apparaît que pour les personnes avec "
          'qui tu choisis de travailler, jamais dans les résultats de recherche.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 24),

        const Text('Téléphone', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          CountryPickerButton(
            selected: _country,
            onChanged: (c) => setState(() => _country = c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
              ],
              decoration: const InputDecoration(hintText: '07 58 22 91 40'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
          ],
          decoration: const InputDecoration(
            labelText: 'WhatsApp (facultatif, si différent)',
            prefixIcon: Icon(Icons.chat_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email (facultatif)',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),

        const SizedBox(height: 28),
        const Text('Où tu te trouves',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ville'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _neighborhood,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Quartier'),
            ),
          ),
        ]),

        const SizedBox(height: 24),
        const Row(children: [
          Expanded(
            child: Text('Ma position sur la carte',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text('Facultatif',
              style: TextStyle(fontSize: 12, color: Colors.black45)),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Permet de te proposer en priorité aux personnes les plus proches. '
          'Seule une distance en kilomètres est montrée aux autres, jamais '
          'ton adresse exacte.',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 12),

        if (_position != null) ...[
          LocationMap(
            lat: _position!.lat,
            lon: _position!.lon,
            onMoved: (p) => setState(() => _position = p),
          ),
          const SizedBox(height: 6),
          const Text(
            'Touche la carte pour corriger le point si le GPS est imprécis.',
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _locate,
                icon: const Icon(Icons.my_location),
                label: const Text('Actualiser'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _clearPosition,
                icon: const Icon(Icons.location_off_outlined,
                    color: AppTheme.danger),
                label: const Text('Retirer',
                    style: TextStyle(color: AppTheme.danger)),
              ),
            ),
          ]),
        ] else if (_locating)
          const Loading()
        else
          OutlinedButton.icon(
            onPressed: _locate,
            icon: const Icon(Icons.my_location),
            label: const Text('Utiliser ma position'),
          ),

        const SizedBox(height: 32),
        if (_busy)
          const Loading()
        else
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        const SizedBox(height: 16),
      ]),
    );
  }
}
