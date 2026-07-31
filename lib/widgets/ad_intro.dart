import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/ads_service.dart';

/// Écran d'introduction d'une publicité récompensée.
///
/// AdMob autorise l'interstitiel récompensé à se lancer automatiquement,
/// sans opt-in publicité par publicité — mais seulement s'il est précédé
/// d'un écran qui annonce clairement la récompense et laisse la
/// possibilité de passer. Cet écran est donc une pièce de conformité, pas
/// un habillage : le supprimer, ou masquer le bouton « passer », remet le
/// compte AdMob en infraction et l'expose à une suspension.
///
/// Le libellé du bouton de sortie vient de la base (`ad_placements`), ce
/// qui permet de le formuler différemment selon l'emplacement sans
/// republier l'application.
class AdIntro {
  /// Présente l'écran et rend `true` si l'utilisateur accepte de regarder.
  ///
  /// Rend `false` s'il choisit de passer, s'il ferme la feuille, ou si
  /// l'emplacement n'est pas jouable — l'appelant poursuit alors son action
  /// normalement. Une publicité indisponible ne doit jamais bloquer un
  /// ouvrier qui veut candidater.
  static Future<bool> ask(BuildContext context, String placementKey) async {
    if (!AdsService.supported) return false;
    if (!await AdsService.canShow(placementKey)) return false;

    final p = AdsService.placement(placementKey);
    if (p == null) return false;
    if (!context.mounted) return false;

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      builder: (ctx) => _AdIntroSheet(placement: p),
    );
    return accepted == true;
  }
}

class _AdIntroSheet extends StatelessWidget {
  final AdPlacement placement;
  const _AdIntroSheet({required this.placement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = placement.introTitle ?? 'Une courte publicité';
    final body = placement.introBody ??
        'Regarde une courte vidéo : elle finance l\'application et permet '
            'de garder le service gratuit.';
    final cta = placement.introCta ?? 'Regarder la vidéo';
    final skip = placement.skipLabel ?? 'Passer';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Icon(Icons.play_circle_outline,
                size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.45)),
            if (placement.rewardCredits > 0) ...[
              const SizedBox(height: 12),
              Text(
                placement.rewardCredits == 1
                    ? 'Récompense : 1 crédit'
                    : 'Récompense : ${placement.rewardCredits} crédits',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(cta),
            ),
            const SizedBox(height: 6),
            // Toujours visible, jamais grisé, jamais masqué derrière un
            // compte à rebours : c'est la condition de conformité.
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(skip),
            ),
          ],
        ),
      ),
    );
  }
}
