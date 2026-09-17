import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../services/realty_service.dart';

/// Libellés des deux axes. Un pays, un type de bien ou une opération
/// s'ajoutent ici et nulle part ailleurs.
const kOperations = <String, String>{
  'vente': 'Vente',
  'location': 'Location',
};

const kBiens = <String, String>{
  'terrain': 'Terrain',
  'maison': 'Maison',
  'appartement': 'Appartement',
  'chambre': 'Chambre',
  'local': 'Local commercial',
};

const kPeriodes = <String, String>{
  'jour': 'par jour',
  'mois': 'par mois',
  'an': 'par an',
};

String prixLisible(Listing l) {
  final montant = Fmt.money(l.price, l.currency);
  if (l.pricePeriod == null) return montant;
  return '$montant ${kPeriodes[l.pricePeriod] ?? ''}'.trim();
}

/// La référence foncière, mise en évidence, avec son avertissement.
///
/// Elle est gratuite et volontairement bien visible : c'est ce qui permet
/// à un acheteur de vérifier le titre AVANT de payer quoi que ce soit.
/// C'est l'argument du produit, pas une mention légale.
///
/// Pas de rouge. Le rouge signale une erreur, et répété sur chaque annonce
/// il cesse d'être lu en deux jours. L'ambre dit « attention » sans crier.
class ReferenceFonciere extends StatelessWidget {
  const ReferenceFonciere({super.key, required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8C98A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Référence foncière',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 6),
        SelectableText(
          reference,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Selon le pays, ce numéro permet de vérifier le titre de propriété '
          'auprès du service foncier. Ticonnect ne procède à aucune '
          'vérification. Nous recommandons à tout acheteur de faire les '
          'vérifications d\'usage avant tout versement.',
          style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF6B5836)),
        ),
      ]),
    );
  }
}

/// Une annonce dans la liste.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final lieu = [l.neighborhood, l.city].where((x) => x != null && x.isNotEmpty);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // L'aperçu fait quelques kilo-octets : c'est une image minuscule
          // agrandie, le flou vient de là et non d'un filtre.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 96,
              height: 76,
              child: l.previewUrl == null
                  ? Container(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      child: const Icon(Icons.home_work_outlined,
                          color: AppTheme.primary),
                    )
                  : Image.network(
                      l.previewUrl!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        child: const Icon(Icons.image_not_supported_outlined,
                            size: 18, color: Colors.black26),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _puce(kOperations[l.deal] ?? l.deal),
                const SizedBox(width: 6),
                _puce(kBiens[l.property] ?? l.property, doux: true),
              ]),
              const SizedBox(height: 6),
              Text(l.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(lieu.join(', '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Row(children: [
                Text(prixLisible(l),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.primary)),
                const Spacer(),
                if (l.surfaceM2 != null)
                  Text('${l.surfaceM2!.toStringAsFixed(0)} m²',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
              // La présence d'une référence se voit dès la liste : c'est ce
              // qui distingue une annonce vérifiable d'une promesse.
              if (l.landReference != null && l.landReference!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.description_outlined,
                      size: 13, color: Color(0xFF8A6D3B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Réf. ${l.landReference}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8A6D3B))),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _puce(String texte, {bool doux = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: doux
              ? Colors.black.withValues(alpha: 0.05)
              : AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(texte,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: doux ? Colors.black54 : AppTheme.primary)),
      );
}
