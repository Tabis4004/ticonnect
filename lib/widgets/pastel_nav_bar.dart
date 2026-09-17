import 'package:flutter/material.dart';

/// Un onglet de la barre du bas.
///
/// Chaque onglet porte sa propre teinte. Ce n'est pas décoratif : sur une
/// barre à six entrées, la couleur devient le repère qu'on reconnaît du
/// coin de l'œil, avant même d'avoir lu l'étiquette. C'est ce qui permet
/// de garder des libellés très petits sans rendre la navigation pénible.
class PastelNavItem {
  const PastelNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tint,
    required this.ink,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Le fond du bloc. Assez clair pour qu'un texte sombre reste lisible.
  final Color tint;

  /// L'icône et l'étiquette. Toujours plus sombre que `tint`, sinon le
  /// contraste tombe sous le seuil de lisibilité en plein soleil — et
  /// c'est dans ces conditions-là que l'application sera utilisée.
  final Color ink;
}

/// Barre de navigation en blocs pastel.
///
/// Remplace `NavigationBar`, dont l'indicateur unique ne distingue pas les
/// onglets entre eux. Ici chaque entrée est un bloc coloré en permanence ;
/// l'onglet courant est simplement plus appuyé — teinte pleine, libellé en
/// gras, légère ombre. On voit donc à la fois où l'on est et ce qui existe
/// à côté.
class PastelNavBar extends StatelessWidget {
  const PastelNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<PastelNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6EAE7))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _bloc(items[i], i == index, () => onTap(i))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bloc(PastelNavItem item, bool actif, VoidCallback onTap) {
    // L'onglet inactif garde sa couleur, en beaucoup plus pâle. La faire
    // disparaître entièrement rendrait la barre grise dès qu'on quitte un
    // onglet, et on perdrait le repère qui justifie ces couleurs.
    final fond = actif ? item.tint : Color.alphaBlend(
        item.tint.withValues(alpha: 0.35), Colors.white);
    final encre = actif ? item.ink : item.ink.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: fond,
              borderRadius: BorderRadius.circular(14),
              boxShadow: actif
                  ? [
                      BoxShadow(
                        color: item.ink.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(actif ? item.selectedIcon : item.icon,
                    size: 21, color: encre),
                const SizedBox(height: 3),
                // `FittedBox` plutôt qu'une coupure : « Immobilier » ne
                // tient pas dans un sixième d'un écran étroit, et
                // « Immobil… » est illisible. Mieux vaut rétrécir.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      color: encre,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La palette de la barre.
///
/// Six teintes distinctes mais de même famille : elles doivent se
/// différencier sans que la barre ressemble à un jeu de cubes. Le vert de
/// « Missions » reprend la couleur de marque ; les autres s'en éloignent
/// par étapes régulières sur le cercle chromatique.
class NavTints {
  static const missions = (tint: Color(0xFFD9EDE1), ink: Color(0xFF1B5E3F));
  static const recherche = (tint: Color(0xFFDCE8F7), ink: Color(0xFF1F4E79));
  static const demandes = (tint: Color(0xFFFBEBD2), ink: Color(0xFF8A5A12));
  static const immobilier = (tint: Color(0xFFF7E0D6), ink: Color(0xFF8C4A2F));
  static const messages = (tint: Color(0xFFE6E1F5), ink: Color(0xFF4B3E8C));
  static const compte = (tint: Color(0xFFE4E8E6), ink: Color(0xFF3F4A44));
}
