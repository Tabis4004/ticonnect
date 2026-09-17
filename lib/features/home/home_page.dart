import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../services/realty_service.dart';
import '../../services/session.dart';
import '../../widgets/pastel_nav_bar.dart';
import '../jobs/my_jobs_page.dart';
import '../profile/admin_page.dart';
import '../realty/realty_list_page.dart';
import '../worker/job_feed_page.dart';
import '../workers/worker_search_page.dart';

/// Une tuile de l'accueil.
class _Service {
  const _Service({
    required this.icon,
    required this.label,
    required this.detail,
    required this.tint,
    required this.ink,
    required this.page,
  });

  final IconData icon;
  final String label;

  /// Une ligne sous le titre. Une tuile muette oblige à entrer pour savoir
  /// ce qu'elle contient ; cette ligne évite le détour.
  final String detail;

  final Color tint;
  final Color ink;
  final Widget Function() page;
}

/// L'accueil : une tuile par fonction, et rien d'autre.
///
/// La barre du bas ne garde que trois entrées — accueil, messages, compte.
/// Empiler six onglets dans une barre de téléphone donne des cibles de la
/// largeur d'un ongle et des libellés tronqués ; ici chaque fonction a la
/// place de dire ce qu'elle fait.
///
/// Les tuiles dépendent du rôle : un ouvrier ne cherche pas d'ouvriers, un
/// client ne consulte pas le fil des missions. C'est la même règle que
/// celle de l'ancienne barre, appliquée à une grille.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final p = session.profile;

    final services = <_Service>[
      if (session.isWorker)
        _Service(
          icon: Icons.work_outline,
          label: 'Missions'.tr,
          detail: 'Les chantiers ouverts près de toi',
          tint: NavTints.missions.tint,
          ink: NavTints.missions.ink,
          page: () => const JobFeedPage(),
        ),
      if (session.isClient)
        _Service(
          icon: Icons.search,
          label: 'Chercher'.tr,
          detail: 'Trouver un ouvrier par métier',
          tint: NavTints.recherche.tint,
          ink: NavTints.recherche.ink,
          page: () => const WorkerSearchPage(),
        ),
      if (session.isClient)
        _Service(
          icon: Icons.assignment_outlined,
          label: 'Demandes'.tr,
          detail: 'Tes demandes et les candidatures',
          tint: NavTints.demandes.tint,
          ink: NavTints.demandes.ink,
          page: () => const MyJobsPage(),
        ),
      if (RealtyService.enabled)
        _Service(
          icon: Icons.home_work_outlined,
          label: 'Immobilier',
          detail: 'Terrains, maisons, locations',
          tint: NavTints.immobilier.tint,
          ink: NavTints.immobilier.ink,
          page: () => const RealtyListPage(),
        ),
      if (session.isAdmin)
        _Service(
          icon: Icons.shield_outlined,
          label: 'Administration'.tr,
          detail: 'Statistiques, signalements, réglages',
          tint: const Color(0xFFD7E6DE),
          ink: AppTheme.primaryDark,
          page: () => const AdminPage(),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
          children: [
            Text(
              p == null ? 'Ticonnect' : 'Bonjour ${p.username ?? p.fullName}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              [p?.neighborhood, p?.city].where((x) => x != null && x.isNotEmpty)
                  .join(', '),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 22),

            // Deux colonnes : au-delà, l'icône et le libellé deviennent
            // trop petits sur un téléphone, et c'est justement la taille
            // des tuiles qui rend cet écran plus lisible qu'une barre.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.98,
              children: [
                for (final s in services) _tuile(context, s),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tuile(BuildContext context, _Service s) {
    return Material(
      color: s.tint,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => s.page()),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: s.ink.withValues(alpha: 0.22)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // La pastille ronde : elle détache l'icône du fond, qui est
              // de la même famille de couleur.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: Icon(s.icon, size: 26, color: s.ink),
              ),
              const SizedBox(height: 12),
              Text(
                s.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: s.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.detail,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: s.ink.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
