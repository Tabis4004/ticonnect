import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../chat/chat_pages.dart';
import '../jobs/my_jobs_page.dart';
import '../profile/profile_page.dart';
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
    final isWorker = context.watch<Session>().isWorker;

    final pages = isWorker
        ? const [JobFeedPage(), ConversationsPage(), ProfilePage()]
        : const [WorkerSearchPage(), MyJobsPage(), ConversationsPage(), ProfilePage()];

    final destinations = isWorker
        ? const [
            NavigationDestination(
                icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Missions'),
            NavigationDestination(
                icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Messages'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Compte'),
          ]
        : const [
            NavigationDestination(
                icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Chercher'),
            NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Demandes'),
            NavigationDestination(
                icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Messages'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Compte'),
          ];

    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
