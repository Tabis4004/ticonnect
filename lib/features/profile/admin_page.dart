import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/common.dart';

/// Tableau de bord administrateur.
///
/// L'accès repose entièrement sur la base : la fonction `is_admin()` et les
/// politiques RLS `*_admin_all` donnent au compte inscrit dans la table
/// `admins` la lecture de toutes les lignes. Aucun contrôle côté application
/// ne peut donc être contourné — masquer ce bouton ne serait qu'un confort.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _leaks = [];
  List<Map<String, dynamic>> _adRevenue = [];
  Map<String, dynamic>? _ssvHealth;
  bool _loading = true;
  bool _savingSetting = false;

  /// Part des conversations dont le premier échange contient déjà un
  /// numéro. C'est l'indicateur qui décide de tout : au-delà d'un certain
  /// seuil, une commission ne sera jamais collectable, et l'abonnement
  /// reste le seul modèle tenable.
  double? _leakRate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _count(String table) async {
    try {
      final rows = await db.from(table).select('*').count();
      return rows.count;
    } catch (_) {
      return -1;
    }
  }

  Future<int> _countWhere(String table, String column, Object value) async {
    try {
      final rows = await db.from(table).select('*').eq(column, value).count();
      return rows.count;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _setPlacement(String mode) async {
    setState(() => _savingSetting = true);
    try {
      await SettingsService.set(SettingKeys.clientJobAdPlacement, mode);
      // Les emplacements portent aussi un drapeau d'activation : on aligne
      // les deux, sinon un réglage dirait « avant » pendant que la table
      // garderait l'emplacement désactivé.
      await db.from('ad_placements').update({'is_enabled': mode == 'before'})
          .eq('key', AdKeys.jobPostBefore);
      await db.from('ad_placements').update({'is_enabled': mode == 'after'})
          .eq('key', AdKeys.jobPostAfter);
      await AdsService.loadPlacements();
      if (mounted) showOk(context, 'Placement mis à jour.');
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _savingSetting = false);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = {
        'Utilisateurs': await _count('profiles'),
        'Ouvriers': await _count('worker_profiles'),
        'Missions': await _count('job_requests'),
        'Candidatures': await _count('job_applications'),
        'Mises en relation': await _count('contact_unlocks'),
        'Avis': await _count('reviews'),
        'Impressions pub': await _count('ad_impressions'),
        'Abonnements actifs': await _countWhere('subscriptions', 'status', 'active'),
      };

      final messages = await _count('messages');
      final leaking = await _countWhere('messages', 'contains_contact', true);
      _leakRate = messages > 0 ? leaking / messages : null;

      await SettingsService.load();

      // Deux appels tolérants à l'échec : tant que les migrations `ad_rewards` et `ad_revenue_reporting`
      // ne sont pas appliquées, ces fonctions n'existent pas et le reste
      // du tableau de bord doit continuer à s'afficher.
      try {
        _adRevenue = List<Map<String, dynamic>>.from(
            await db.rpc('ad_revenue_summary', params: {'p_days': 14}));
      } catch (_) {
        _adRevenue = [];
      }
      try {
        final rows = List<Map<String, dynamic>>.from(
            await db.rpc('ad_ssv_health'));
        _ssvHealth = rows.isEmpty ? null : rows.first;
      } catch (_) {
        _ssvHealth = null;
      }

      _reports = List<Map<String, dynamic>>.from(await db
          .from('reports')
          .select('*, reported:profiles!reports_reported_profile_id_fkey(full_name)')
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(20));

      // Mesure de la fuite hors plateforme : messages contenant un numéro.
      _leaks = List<Map<String, dynamic>>.from(await db
          .from('messages')
          .select('id, body, created_at')
          .eq('contains_contact', true)
          .order('created_at', ascending: false)
          .limit(20));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.1,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final e in _stats.entries)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE6EAE7)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.value < 0 ? "—" : e.value}',
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary)),
                            Text(e.key,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _adRevenueCard(),
                const SizedBox(height: 24),
                _adPlacementCard(),
                const SizedBox(height: 24),
                const Text('Signalements ouverts',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_reports.isEmpty)
                  const Text('Aucun signalement en attente.',
                      style: TextStyle(color: Colors.black54))
                else
                  for (final r in _reports)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(r['reason'] as String? ?? ''),
                        subtitle: Text(
                          '${(r['reported'] as Map?)?['full_name'] ?? "?"} · '
                          '${Fmt.ago(DateTime.tryParse(r['created_at'] as String? ?? ""))}',
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                const Text('Fuite hors plateforme',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Messages contenant un numéro de téléphone. Un taux élevé '
                  'signifie que les échanges quittent l\'application dès le '
                  'premier contact — et qu\'une commission ne serait jamais '
                  'collectable ici.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (_leakRate != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(
                      '${(_leakRate! * 100).toStringAsFixed(1)} %',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _leakRate! > 0.6
                            ? AppTheme.danger
                            : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _leakRate! > 0.6
                            ? 'Au-dessus de 60 % : rester sur l\'abonnement, '
                                'la commission serait déclarative.'
                            : 'Sous 60 % : une commission sur prestation '
                                'encaissée resterait envisageable plus tard.',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                if (_leaks.isEmpty)
                  const Text('Aucun message détecté.',
                      style: TextStyle(color: Colors.black54))
                else
                  for (final m in _leaks)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(m['body'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(Fmt.ago(
                            DateTime.tryParse(m['created_at'] as String? ?? ''))),
                      ),
                    ),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }

  /// Bascule du placement publicitaire côté client.
  ///
  /// Le débat « avant ou après la saisie du besoin » ne se tranche pas en
  /// réunion : il se tranche sur le taux d'abandon du formulaire. D'où ce
  /// bouton, plutôt qu'une valeur figée dans le code.
  /// Revenu publicitaire et santé de la vérification serveur.
  ///
  /// Toutes les projections du modèle reposent sur un eCPM estimé, faute
  /// de donnée publique pour la région. Ce tableau le remplace par le
  /// chiffre réel — le seul qui dise si le modèle tient.
  ///
  /// Le taux de vérification est l'autre indicateur critique : s'il
  /// s'effondre, les ouvriers regardent des vidéos sans jamais obtenir
  /// leur mise en avant. On encaisse la gêne sans livrer la contrepartie,
  /// et c'est invisible depuis la console AdMob.
  Widget _adRevenueCard() {
    final ratio = (_ssvHealth?['verified_ratio'] as num?)?.toDouble();
    final rewarded = (_ssvHealth?['rewarded_impressions'] as num?)?.toInt() ?? 0;
    final alert = rewarded > 0 && (ratio ?? 0) < 0.5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: alert ? Colors.red.shade200 : const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Revenu publicitaire — 14 jours',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (rewarded == 0)
          const Text('Aucune vidéo récompensée sur les dernières 24 h.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          Row(children: [
            Icon(alert ? Icons.error_outline : Icons.verified_outlined,
                size: 18, color: alert ? Colors.red : AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Vérification serveur : '
                '${((ratio ?? 0) * 100).toStringAsFixed(0)} % '
                'sur $rewarded visionnage(s) en 24 h'
                '${alert ? " — vérifie que l'Edge Function admob-ssv est déployée" : ""}',
                style: TextStyle(
                  fontSize: 12,
                  color: alert ? Colors.red : Colors.black54,
                  fontWeight: alert ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ]),
        const SizedBox(height: 12),
        if (_adRevenue.isEmpty)
          const Text('Aucune impression enregistrée sur la période.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 38,
              columns: const [
                DataColumn(label: Text('Jour', style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text('Emplacement', style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text('Impr.', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text('Vérif.', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text('Revenu', style: TextStyle(fontSize: 12)),
                    numeric: true),
              ],
              rows: [
                for (final r in _adRevenue.take(40))
                  DataRow(cells: [
                    DataCell(Text('${r['day']}'.substring(5),
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text('${r['placement_key']}',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text('${r['impressions']}',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text('${r['verified']}',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(
                        '${(r['estimated_revenue'] as num? ?? 0).toStringAsFixed(4)} \$',
                        style: const TextStyle(fontSize: 12))),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'La colonne Revenu n\'est alimentée que si l\'API de reporting '
          'AdMob est branchée. Sans elle, croise le nombre d\'impressions '
          'avec le revenu de la console AdMob pour obtenir ton eCPM réel '
          'par emplacement.',
          style: TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ]),
    );
  }

  Widget _adPlacementCard() {
    final mode = SettingsService.string(
        SettingKeys.clientJobAdPlacement, 'after');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Publicité côté client',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Où afficher l\'interstitiel lors de la publication d\'un besoin. '
          '« Après » est recommandé : la friction tombe une fois l\'engagement '
          'acquis. « Avant » garantit l\'affichage mais expose à l\'abandon du '
          'formulaire. Surveille le nombre de missions publiées après chaque '
          'bascule.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (_savingSetting)
          const Loading()
        else
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'before', label: Text('Avant')),
              ButtonSegment(value: 'after', label: Text('Après')),
              ButtonSegment(value: 'off', label: Text('Aucune')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => _setPlacement(s.first),
          ),
        const SizedBox(height: 10),
        Text(
          'Publicité à la candidature (ouvrier) : '
          '${SettingsService.boolean(SettingKeys.workerApplyAdEnabled, true) ? "activée" : "désactivée"} · '
          'Un résultat sponsorisé sur '
          '${SettingsService.integer(SettingKeys.sponsoredSlotRatio, 4)} · '
          'Note plancher '
          '${SettingsService.decimal(SettingKeys.sponsoredMinRating, 3.5)}',
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ]),
    );
  }
}
