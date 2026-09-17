import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../services/realty_service.dart';
import '../../widgets/ad_intro.dart';
import '../../widgets/common.dart';
import 'realty_widgets.dart';

/// Une annonce.
///
/// Tout est visible sauf trois choses : l'adresse exacte, le plan et le
/// numéro du vendeur. Elles ne sont pas seulement masquées à l'écran — le
/// serveur refuse de les rendre tant que l'annonce n'est pas ouverte. Ce
/// qui suit ne fait qu'afficher ce que la base accepte de donner.
class ListingPage extends StatefulWidget {
  const ListingPage({super.key, required this.listingId});

  final String listingId;

  @override
  State<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends State<ListingPage> {
  Listing? _annonce;
  ListingPrivate? _prive;
  String? _planUrl;
  List<String> _photos = [];
  bool _planEnPreparation = false;

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
      _annonce = await RealtyService.byId(widget.listingId);
      if (await RealtyService.isUnlocked(widget.listingId)) {
        await _chargerLePaye();
      } else {
        _prive = null;
      }
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerLePaye() async {
    _prive = await RealtyService.private(widget.listingId);
    try {
      final f = await RealtyService.files(widget.listingId);
      _planUrl = f.plan;
      _photos = f.photos;
      _planEnPreparation = f.planEnPreparation;
    } catch (_) {
      // Les URL signées peuvent échouer sans que le déblocage soit en
      // cause. On garde le contact, qui est le plus utile des trois.
      _planUrl = null;
      _photos = [];
    }
  }

  Future<void> _ouvrir() async {
    setState(() => _busy = true);
    UnlockResult res;

    if (RealtyService.unlockMode == 'video') {
      // L'écran d'introduction n'est pas décoratif : AdMob exige, pour le
      // format récompensé, qu'on annonce la récompense et qu'on laisse
      // refuser. Le retirer met le compte en infraction.
      final accepte =
          await AdIntro.ask(context, AdKeys.realtyUnlockRewarded);
      if (!accepte || !mounted) {
        setState(() => _busy = false);
        return;
      }
      res = await RealtyService.unlockByWatchingAd(widget.listingId);
    } else {
      res = await RealtyService.unlock(widget.listingId);
    }

    if (!mounted) return;
    if (res.ok) {
      await _chargerLePaye();
      if (mounted) {
        setState(() => _busy = false);
        showOk(context, 'Annonce ouverte. Elle le restera pour toi.');
      }
      return;
    }
    setState(() => _busy = false);
    showError(context, res.message ?? 'Réessaie plus tard.');
  }

  Future<void> _appeler(String numero) async {
    final uri = Uri.parse('tel:$numero');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showError(context, "Impossible d'ouvrir le téléphone.");
    }
  }

  Future<void> _whatsapp(String numero) async {
    final propre = numero.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$propre');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showError(context, "Impossible d'ouvrir WhatsApp.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _annonce;
    return Scaffold(
      appBar: AppBar(title: const Text('Annonce')),
      body: _loading
          ? const Loading()
          : l == null
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'Annonce introuvable',
                  subtitle: 'Elle a peut-être été retirée.',
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Text(kOperations[l.deal] ?? l.deal,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                    const Text(' · '),
                    Text(kBiens[l.property] ?? l.property,
                        style: const TextStyle(color: Colors.black54)),
                  ]),
                  const SizedBox(height: 6),
                  Text(l.title,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    [l.neighborhood, l.city].where((x) => x != null).join(', '),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Text(prixLisible(l),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                  if (l.surfaceM2 != null || l.rooms != null) ...[
                    const SizedBox(height: 6),
                    Text([
                      if (l.surfaceM2 != null)
                        '${l.surfaceM2!.toStringAsFixed(0)} m²',
                      if (l.rooms != null) '${l.rooms} pièce(s)',
                    ].join(' · '),
                        style: const TextStyle(color: Colors.black54)),
                  ],

                  if (l.landReference != null && l.landReference!.isNotEmpty)
                    ReferenceFonciere(reference: l.landReference!),

                  if (l.description != null && l.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l.description!, style: const TextStyle(height: 1.5)),
                  ],

                  const SizedBox(height: 20),
                  if (_prive == null) _bloqueFerme() else _blocOuvert(),
                  const SizedBox(height: 32),
                ]),
    );
  }

  /// Ce qu'on voit avant d'ouvrir. Dire exactement ce qu'on obtient : une
  /// promesse vague fait payer pour être déçu, et un déçu ne revient pas.
  Widget _bloqueFerme() {
    final mode = RealtyService.unlockMode;
    final (titre, sousTitre) = switch (mode) {
      'video' => (
          'Regarder une vidéo pour ouvrir',
          'Une courte vidéo, et l\'annonce reste ouverte pour toi.',
        ),
      'payant' => (
          'Ouvrir cette annonce',
          'Les ouvertures payantes ne sont pas encore disponibles.',
        ),
      _ => (
          'Ouvrir cette annonce',
          'Gratuit. L\'annonce restera ouverte pour toi.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ce que l\'ouverture donne',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('• le numéro du vendeur\n'
            '• l\'adresse exacte du bien\n'
            '• les photos en pleine définition\n'
            '• le plan, s\'il y en a un'),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || mode == 'payant') ? null : _ouvrir,
            icon: Icon(mode == 'video'
                ? Icons.play_circle_outline
                : Icons.lock_open_outlined),
            label: Text(_busy ? 'Un instant…' : titre),
          ),
        ),
        const SizedBox(height: 8),
        Text(sousTitre,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }

  Widget _blocOuvert() {
    final p = _prive!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.lock_open, size: 18, color: AppTheme.primary),
        const SizedBox(width: 6),
        const Text('Annonce ouverte',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 12),

      if (p.addressExact != null && p.addressExact!.isNotEmpty) ...[
        const Text('Adresse', style: TextStyle(fontSize: 11, color: Colors.black54)),
        SelectableText(p.addressExact!),
        const SizedBox(height: 12),
      ],

      if (p.phone != null && p.phone!.isNotEmpty) ...[
        const Text('Contact', style: TextStyle(fontSize: 11, color: Colors.black54)),
        SelectableText(p.phone!,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => _appeler(p.phone!),
            icon: const Icon(Icons.call, size: 18),
            label: const Text('Appeler'),
          ),
          const SizedBox(width: 8),
          if (p.whatsapp != null && p.whatsapp!.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _whatsapp(p.whatsapp!),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
        ]),
        const SizedBox(height: 16),
      ],

      if (_photos.isNotEmpty) ...[
        const Text('Photos', style: TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 6),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(_photos[i], fit: BoxFit.cover, width: 260),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],

      if (_planUrl != null) ...[
        const Text('Plan', style: TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(_planUrl!, fit: BoxFit.contain),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cette copie porte ton pseudo et ton numéro. Si elle circule, elle '
          'mène à toi.',
          style: TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ] else if (_planEnPreparation)
        // Distinguer les deux : « en préparation » se règle en attendant,
        // « aucun plan » ne se règle pas du tout.
        Row(children: [
          const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Le plan est en préparation. Reviens dans un instant.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ]),
    ]);
  }
}
