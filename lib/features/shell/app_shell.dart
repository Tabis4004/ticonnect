import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../services/session.dart';
import '../../widgets/pastel_nav_bar.dart';
import '../chat/chat_pages.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';

/// Navigation principale.
///
/// Trois entrées, pas six. Les fonctions métier — missions, recherche,
/// demandes, immobilier — vivent en tuiles sur l'accueil, où chacune a la
/// place de dire ce qu'elle fait. Une barre à six onglets sur un écran de
/// téléphone donne des cibles de la largeur d'un ongle et des libellés
/// tronqués ; on y perd ce qu'on croyait gagner en raccourcis.
///
/// Ne restent en bas que les trois destinations où l'on va sans savoir ce
/// qu'on y cherche : l'accueil, les messages, le compte.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Lu pour que la barre se reconstruise au changement de rôle ou de
    // profil, comme le faisait l'ancienne version.
    context.watch<AppSession>();

    final pages = <Widget>[
      const HomePage(),
      const ConversationsPage(),
      const ProfilePage(),
    ];

    final destinations = <PastelNavItem>[
      PastelNavItem(
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view,
          label: 'Accueil'.tr,
          tint: NavTints.missions.tint,
          ink: NavTints.missions.ink),
      PastelNavItem(
          icon: Icons.forum_outlined,
          selectedIcon: Icons.forum,
          label: 'Messages'.tr,
          tint: NavTints.messages.tint,
          ink: NavTints.messages.ink),
      PastelNavItem(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: 'Compte'.tr,
          tint: NavTints.compte.tint,
          ink: NavTints.compte.ink),
    ];

    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: PastelNavBar(
        items: destinations,
        index: safeIndex,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
