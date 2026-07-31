import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/ads_service.dart';

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.black26),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

class RatingStars extends StatelessWidget {
  final double rating;
  final int count;
  final double size;
  const RatingStars({super.key, required this.rating, this.count = 0, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text('Nouveau', style: TextStyle(fontSize: size - 2, color: Colors.black54));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: size, color: AppTheme.accent),
      const SizedBox(width: 3),
      Text(rating.toStringAsFixed(1),
          style: TextStyle(fontSize: size - 2, fontWeight: FontWeight.w600)),
      const SizedBox(width: 3),
      Text('($count)', style: TextStyle(fontSize: size - 3, color: Colors.black54)),
    ]);
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});
  @override
  Widget build(BuildContext context) => const Tooltip(
        message: 'Identité vérifiée',
        child: Icon(Icons.verified_rounded, size: 16, color: AppTheme.primary),
      );
}

/// Bannière publicitaire pilotée par la table `ad_placements`.
///
/// Rend un espace nul tant qu'aucune publicité n'est disponible — ce qui est
/// le cas permanent sur le web, où AdMob n'existe pas.
class AdBannerSlot extends StatefulWidget {
  final String placementKey;
  const AdBannerSlot({super.key, required this.placementKey});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  Widget? _banner;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (!AdsService.supported) return;
    // La configuration vient de la base : il faut qu'elle soit chargée avant
    // de savoir si l'emplacement est actif et quel identifiant d'unité utiliser.
    await AdsService.init();
    if (!mounted) return;
    setState(() => _banner = AdsService.bannerWidget(widget.placementKey));
  }

  @override
  Widget build(BuildContext context) => _banner ?? const SizedBox.shrink();
}

class WorkerCard extends StatelessWidget {
  final WorkerSearchResult worker;
  final VoidCallback onTap;
  const WorkerCard({super.key, required this.worker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              backgroundImage:
                  worker.avatarUrl != null ? NetworkImage(worker.avatarUrl!) : null,
              child: worker.avatarUrl == null
                  ? Text(
                      worker.fullName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(worker.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    if (worker.isVerified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(),
                    ],
                    // Position payante, annoncée comme telle. Un client qui
                    // découvre par lui-même que les premiers résultats sont
                    // achetés cesse de faire confiance à toute la recherche ;
                    // le dire franchement coûte beaucoup moins cher.
                    if (worker.isBoosted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('SPONSORISÉ',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  if (worker.headline != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(worker.headline!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    RatingStars(rating: worker.ratingAvg, count: worker.ratingCount),
                    const SizedBox(width: 10),
                    if (worker.jobsCompleted > 0)
                      Text('${worker.jobsCompleted} mission${worker.jobsCompleted > 1 ? "s" : ""}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '${Fmt.range(worker.rateMin, worker.rateMax, worker.currency)} ${Fmt.unit(worker.pricingUnit)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (worker.distanceKm != null)
              Text(Fmt.distance(worker.distanceKm),
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ]),
        ),
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final JobSearchResult job;
  final VoidCallback onTap;
  const JobCard({super.key, required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final urgent = job.urgency == 'immediate';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (urgent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('URGENT',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.danger)),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip(Icons.handyman_outlined, job.tradeName),
                _chip(Icons.place_outlined,
                    job.neighborhood == null ? job.city : '${job.neighborhood}, ${job.city}'),
                _chip(Icons.payments_outlined,
                    Fmt.range(job.budgetMin, job.budgetMax, job.currency)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Icon(
                  job.isUnlocked ? Icons.phone_in_talk_rounded : Icons.phone_outlined,
                  size: 15,
                  color: job.isUnlocked ? AppTheme.primary : Colors.black45,
                ),
                const SizedBox(width: 5),
                Text(
                  job.isUnlocked ? 'Contact obtenu' : 'Contact gratuit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: job.isUnlocked ? AppTheme.primary : Colors.black45,
                  ),
                ),
                const Spacer(),
                if (job.hasApplied)
                  const Text('Déjà postulé',
                      style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                const SizedBox(width: 8),
                Text(Fmt.ago(job.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.black38)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3F1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.black54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ]),
      );
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
  );
}

void showOk(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.primary),
  );
}
