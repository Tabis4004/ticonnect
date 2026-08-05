import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/ads_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/common.dart';
import 'settings_page.dart';

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
  List<Map<String, dynamic>> _adDiag = [];
  List<Map<String, dynamic>> _jobs = [];
  Map<String, dynamic>? _ssvHealth;
  bool _isSuper = false;
  bool _busyJobs = false;
  bool _loading = true;
  bool _savingSetting = false;

  /// Part des conversations dont le premier échange contient déjà un
  /// numéro. C'est l'indicateur qui décide de tout : au-delà d'un certain
  /// seuil, une commission ne sera jamais collectable, et l'abonnement
  /// reste le seul modèle tenable.
  double? _leakRate;

  /// Réactivité mesurée sur la messagerie interne — et sur elle seule.
  ///
  /// Ce que ces chiffres ne voient pas : tout ce qui se passe sur WhatsApp,
  /// par appel ou par SMS. Un ouvrier peut répondre à tous ses clients en
  /// dix minutes hors de l'application et afficher 0 % ici. À lire en
  /// regard du taux de fuite, jamais isolément.
  Map<String, dynamic>? _response;

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

      // Agrégat de réactivité. Ne porte que sur la messagerie interne.
      final workers = List<Map<String, dynamic>>.from(await db
          .from('worker_profiles')
          .select('response_rate, response_median_minutes, response_sample')
          .gt('response_sample', 0));

      if (workers.isNotEmpty) {
        final rates = [
          for (final w in workers) (w['response_rate'] as num?)?.toDouble() ?? 0
        ];
        final delays = [
          for (final w in workers)
            if (w['response_median_minutes'] != null)
              (w['response_median_minutes'] as num).toDouble()
        ]..sort();

        _response = {
          'ouvriers': workers.length,
          'taux': rates.reduce((a, b) => a + b) / rates.length,
          'delai': delays.isEmpty ? null : delays[delays.length ~/ 2],
          'echantillon': workers.fold<int>(
              0, (s, w) => s + ((w['response_sample'] as num?)?.toInt() ?? 0)),
        };
      } else {
        _response = null;
      }

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
      try {
        _adDiag = List<Map<String, dynamic>>.from(
            await db.rpc('ad_diagnostics', params: {'p_limit': 15}));
      } catch (_) {
        _adDiag = [];
      }
      try {
        _isSuper = (await db.rpc('is_superadmin') as bool?) ?? false;
      } catch (_) {
        _isSuper = false;
      }
      try {
        _jobs = List<Map<String, dynamic>>.from(await db
            .from('job_requests')
            .select('id, title, city, status, created_at, '
                'client:profiles!job_requests_client_id_fkey(username, full_name)')
            .order('created_at', ascending: false)
            .limit(30));
      } catch (_) {
        _jobs = [];
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
        actions: [
          // Tous les réglages de la plateforme, générés depuis la base.
          // Onze d'entre eux n'étaient jusqu'ici modifiables que depuis
          // l'éditeur SQL de Supabase.
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              if (mounted) await _load();
            },
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
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
                _jobsCard(),
                const SizedBox(height: 24),
                _adDiagnosticsCard(),
                const SizedBox(height: 24),
                _adRevenueCard(),
                const SizedBox(height: 24),
                _responseCard(),
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

  /// Une étape de l'entonnoir publicitaire.
  ///
  /// Séparer les trois n'est pas un raffinement d'affichage : ce sont trois
  /// problèmes différents, avec trois responsables différents. Un
  /// remplissage bas relève d'AdMob et de la maturité du compte ; une
  /// complétion basse relève du produit et du placement ; seule une
  /// vérification basse met en cause le code.
  static Widget _funnel(String label, double? ratio, String hint) => Expanded(
        child: Tooltip(
          message: hint,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(0)} %',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      );

  /// Réactivité des ouvriers, mesurée sur la messagerie interne.
  ///
  /// La réserve affichée en bas de la carte n'est pas une précaution de
  /// style : sans elle, ces chiffres se lisent comme une mesure de la
  /// qualité des ouvriers, alors qu'ils mesurent surtout combien d'échanges
  /// sont restés dans l'application.
  Widget _responseCard() {
    final r = _response;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Réactivité',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Part des premiers messages clients auxquels l\'ouvrier a répondu, '
          'et délai médian de cette première réponse.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (r == null)
          const Text(
            'Pas encore de données. Une conversation compte à partir du '
            'moment où un client a écrit et où le délai de patience est '
            'écoulé.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          )
        else
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(r['taux'] as double).toStringAsFixed(0)} %',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary)),
                const Text('répondent',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_delay(r['delai'] as double?),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary)),
                const Text('délai médian',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['ouvriers']}',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary)),
                Text('ouvriers · ${r['echantillon']} conv.',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            ),
          ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6E5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Mesuré sur la messagerie interne uniquement. Les échanges partis '
            'sur WhatsApp, en appel ou par SMS sont invisibles : un ouvrier '
            'très réactif hors de l\'application apparaîtra ici comme muet. '
            'À lire en regard du taux de fuite ci-dessous.',
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ]),
    );
  }

  static String _delay(double? minutes) {
    if (minutes == null) return '—';
    if (minutes < 60) return '${minutes.round()} min';
    if (minutes < 60 * 24) return '${(minutes / 60).round()} h';
    return '${(minutes / 1440).round()} j';
  }

  /// Bascule du placement publicitaire côté client.
  ///
  /// Le débat « avant ou après la saisie du besoin » ne se tranche pas en
  /// réunion : il se tranche sur le taux d'abandon du formulaire. D'où ce
  /// bouton, plutôt qu'une valeur figée dans le code.
  Future<void> _createJob() async {
    setState(() => _busyJobs = true);
    try {
      await db.rpc('admin_create_job', params: {
        'p_title': 'Demande de test ${DateTime.now().toString().substring(11, 16)}',
      });
      if (mounted) showOk(context, 'Demande créée.');
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busyJobs = false);
  }

  Future<void> _deleteJob(String id, String titre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette demande ?'),
        content: Text('« $titre » et ses candidatures seront effacées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyJobs = true);
    try {
      await db.rpc('admin_delete_job', params: {'p_job_id': id});
      if (mounted) showOk(context, 'Demande supprimée.');
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busyJobs = false);
  }

  /// Purge totale.
  ///
  /// La confirmation par saisie n'est pas de la cérémonie : la suppression
  /// cascade sur les candidatures et les conversations, et rien ne permet
  /// de revenir en arrière. Un simple bouton « Oui » se clique par
  /// réflexe, taper un mot demande d'y penser.
  Future<void> _purgeJobs() async {
    final saisie = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vider toutes les demandes ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Irréversible. Les candidatures et les conversations liées '
            'disparaissent aussi.\n\nTape VIDER pour confirmer.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: saisie,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'VIDER'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, saisie.text.trim() == 'VIDER'),
            child: const Text('Tout vider'),
          ),
        ],
      ),
    );
    saisie.dispose();
    if (ok != true) return;

    setState(() => _busyJobs = true);
    try {
      final n = await db.rpc('admin_purge_jobs', params: {'p_confirm': 'VIDER'});
      if (mounted) showOk(context, '$n demande(s) supprimée(s).');
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busyJobs = false);
  }

  /// Gestion des demandes.
  ///
  /// Un compte au rôle ouvrier ne voit ni l'onglet « Demandes » ni le
  /// bouton de publication — c'est le parcours client. Tester le fil des
  /// missions imposait donc de jongler entre deux comptes. Cette section
  /// permet de fabriquer une demande sans changer d'identité.
  Widget _jobsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Demandes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          if (_busyJobs)
            const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            TextButton.icon(
              onPressed: _createJob,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
            ),
        ]),
        const Text(
          'Créer une demande de test sans passer par un compte client.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        if (_jobs.isEmpty)
          const Text('Aucune demande.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          for (final j in _jobs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${j['title']}',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${j['city']} · ${j['status']} · '
                '${(j['client'] as Map?)?['username'] ?? "?"} · '
                '${Fmt.ago(DateTime.tryParse(j['created_at'] as String? ?? ""))}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                onPressed: _busyJobs
                    ? null
                    : () => _deleteJob('${j['id']}', '${j['title']}'),
              ),
            ),
        // Réservé au superadministrateur, et masqué aux autres plutôt que
        // grisé : un bouton visible mais inopérant invite à insister.
        if (_isSuper) ...[
          const Divider(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busyJobs ? null : _purgeJobs,
              icon: Icon(Icons.delete_sweep_outlined,
                  size: 18, color: Colors.red.shade700),
              label: Text('Vider toutes les demandes',
                  style: TextStyle(color: Colors.red.shade700)),
            ),
          ),
        ],
      ]),
    );
  }

  /// Diagnostic de la chaîne de récompense.
  ///
  /// Vérifier qu'un boost a fonctionné demandait cinq requêtes SQL et la
  /// connaissance de subtilités invisibles : qu'une unité de démonstration
  /// ne déclenche jamais de rappel, ou qu'un profil sous la note plancher
  /// reste au classement organique même boosté. Les deux se manifestent
  /// par « rien ne se passe ».
  ///
  /// Chaque ligne dit où la chaîne s'est arrêtée, et pourquoi.
  Widget _adDiagnosticsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAE7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Diagnostic publicitaire',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Les derniers visionnages, étape par étape : affichée, vérifiée '
          'par Google, échangée contre une mise en avant, boost actif.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (_adDiag.isEmpty)
          const Text('Aucune impression enregistrée.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          for (final d in _adDiag) ...[
            _diagRow(d),
            const Divider(height: 18),
          ],
      ]),
    );
  }

  Widget _diagRow(Map<String, dynamic> d) {
    final etape = '${d['etape']}';
    final mode = '${d['mode']}';
    final blocage = d['blocage'] as String?;
    final reste = '${d['boost_restant']}';

    // Vert seulement au bout de la chaîne : tant qu'un boost n'est pas
    // actif, rien n'a produit d'effet visible pour l'ouvrier.
    final abouti = etape.startsWith('4/4');
    final couleur = abouti
        ? AppTheme.primary
        : (mode == 'TEST' ? Colors.orange.shade700 : Colors.red.shade600);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(abouti ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16, color: couleur),
        const SizedBox(width: 6),
        Expanded(
          child: Text(etape,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: couleur)),
        ),
        if (reste != '—')
          Text('reste $reste',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
      const SizedBox(height: 2),
      Text(
        '${d['emplacement']} · ${d['ouvrier'] ?? "?"} · mode $mode'
        '${d['note'] == null ? "" : " · note ${d['note']}"}'
        '${d['sponsorisable'] == true ? " · sponsorisable" : ""}',
        style: const TextStyle(fontSize: 11, color: Colors.black45),
      ),
      if (blocage != null) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(blocage,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7A4B00))),
        ),
      ],
    ]);
  }

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
    // Trois taux distincts, et un seul qui met en cause `admob-ssv`.
    //
    // L'ancienne version divisait les vérifiées par toutes les tentatives et
    // attribuait l'écart à l'Edge Function. Sur 21 tentatives : 9 n'avaient
    // jamais chargé, 10 avaient été abandonnées en cours de vidéo, 2 avaient
    // été récompensées — et vérifiées toutes les deux. La fonction traitait
    // 100 % de ce qui lui arrivait ; l'alerte envoyait chercher une panne
    // là où il n'y en avait pas.
    final h = _ssvHealth;
    final attempts = (h?['attempts'] as num?)?.toInt() ?? 0;
    final earned = (h?['earned'] as num?)?.toInt() ?? 0;
    final fill = (h?['fill_ratio'] as num?)?.toDouble();
    final completion = (h?['completion_ratio'] as num?)?.toDouble();
    final ratio = (h?['verified_ratio'] as num?)?.toDouble();

    // On n'accuse la callback que si des récompenses ont réellement été
    // gagnées sans être confirmées. Aucun visionnage complet : rien à dire.
    final alert = earned > 0 && (ratio ?? 1) < 0.5;

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
        if (attempts == 0)
          const Text('Aucune vidéo récompensée demandée sur les dernières 24 h.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else ...[
          Row(children: [
            _funnel('Remplissage', fill,
                'annonces servies par AdMob sur les demandes'),
            _funnel('Complétion', completion,
                'vidéos regardées jusqu\'au bout'),
            _funnel('Vérification', ratio,
                'récompenses confirmées par la callback'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(alert ? Icons.error_outline : Icons.verified_outlined,
                size: 18, color: alert ? Colors.red : AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                alert
                    ? 'Des récompenses gagnées ne sont pas confirmées : '
                        'vérifie que l\'URL de vérification serveur est bien '
                        'déclarée dans la console AdMob.'
                    : earned == 0
                        ? 'Aucun visionnage mené à son terme en 24 h — rien à '
                            'vérifier côté serveur. Un remplissage ou une '
                            'complétion bas ne relèvent pas de l\'Edge Function.'
                        : 'Callback de vérification saine sur $earned '
                            'récompense(s) gagnée(s).',
                style: TextStyle(
                  fontSize: 11.5,
                  color: alert ? Colors.red : Colors.black54,
                  fontWeight: alert ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ]),
        ],
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
