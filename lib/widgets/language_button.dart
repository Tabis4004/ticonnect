import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// Sélecteur de langue pour les écrans d'authentification.
///
/// Avant login il n'y a pas de profil où mémoriser le choix : on écrit
/// directement dans [L], et l'arbre entier se reconstruit (voir main.dart).
/// Une fois connecté, c'est « Compte → Langue » qui prend le relais et
/// persiste la préférence sur le profil.
///
/// Volontairement limité à [L.supported] : proposer un arabe non traduit
/// donnerait une interface à moitié en français.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.translate),
      tooltip: 'Langue'.tr,
      initialValue: L.instance.lang,
      onSelected: L.instance.setLanguage,
      itemBuilder: (_) => [
        for (final e in L.supported.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(children: [
              SizedBox(
                width: 28,
                child: e.key == L.instance.lang
                    ? const Icon(Icons.check, size: 18)
                    : null,
              ),
              Text(e.value),
            ]),
          ),
      ],
    );
  }
}
