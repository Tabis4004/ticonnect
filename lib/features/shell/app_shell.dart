import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../services/realty_service.dart';
import '../../services/session.dart';
import '../../widgets/pastel_nav_bar.dart';
import '../chat/chat_pages.dart';
import '../jobs/my_jobs_page.dart';
import '../profile/profile_page.dart';
import '../realty/realty_list_page.dart';
import '../worker/job_feed_page.dart';
import '../workers/worker_search_page.dart';

/// Navigation principale. Les onglets diffèrent selon le rôle : un ouvrier
/// ne cherche pas d'ouvriers, un client ne consulte pas le fil des missions.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final isWorker = session.isWorker;
    final isClient = session.isClient;

    // Le rôle `both` existait en base et dans le modèle, mais la
    // navigation ne connaissait que deux cas : `isWorker` l'emportait, et
    // un ouvrier qui a lui aussi des besoins se retrouvait sans onglet
    // pour chercher un artisan ni publier une demande. Un maçon qui doit
    // faire réparer sa moto est pourtant le cas le plus banal ici.
    final missions = <Widget>[if (isWorker) const JobFeedPage()];
    final cherche = <Widget>[if (isClient) const WorkerSearchPage()];
    final demandes = <Widget>[if (isClient) const MyJobsPage()];

    // Le module immobilier n'apparaît que si un administrateur l'a allumé.
    // Une rubrique vide donne l'impression d'un produit mort, et c'est la
    // première chose que verrait quelqu'un qui découvre l'application.
    final immobilier = <Widget>[
      if (RealtyService.enabled) const RealtyListPage(),
    ];

    final pages = <Widget>[
      ...missions,
      ...cherche,
      ...demandes,
      ...immobilier,
      const ConversationsPage(),
      const ProfilePage(),
    ];

    // Une entrée par page, dans le même ordre : la barre et l'IndexedStack
    // se lisent sur le même index, et un décalage entre les deux enverrait
    // sur le mauvais écran.
    final destinations = <PastelNavItem>[
      if (isWorker)
        PastelNavItem(
            icon: Icons.work_outline,
            selectedIcon: Icons.work,
            label: 'Missions'.tr,
            tint: NavTints.missions.tint,
            ink: NavTints.missions.ink),
      if (isClient)
        PastelNavItem(
            icon: Icons.search,
            selectedIcon: Icons.search,
            label: 'Chercher'.tr,
            tint: NavTints.recherche.tint,
            ink: NavTints.recherche.ink),
      if (isClient)
        PastelNavItem(
            icon: Icons.assignment_outlined,
            selectedIcon: Icons.assignment,
            label: 'Demandes'.tr,
            tint: NavTints.demandes.tint,
            ink: NavTints.demandes.ink),
      if (RealtyService.enabled)
        PastelNavItem(
            icon: Icons.home_work_outlined,
            selectedIcon: Icons.home_work,
            label: 'Immobilier'.tr,
            tint: NavTints.immobilier.tint,
            ink: NavTints.immobilier.ink),
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
