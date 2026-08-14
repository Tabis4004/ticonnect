import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Consultation des données par l'administrateur.
///
/// Les politiques ouvertes par la migration `admin_read_all` donnent accès
/// en lecture à toutes les tables, mais aucun écran ne s'en servait :
/// l'administrateur restait aveugle depuis l'application.
///
/// Lecture stricte. Aucun de ces écrans n'écrit — modifier un message ou
/// une note leur retirerait toute valeur de preuve en cas de litige, et
/// c'est précisément dans ces moments qu'on a besoin d'un historique
/// intact. Les gestes d'administration passent par des fonctions nommées,
/// depuis le tableau de bord.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<Map<String, dynamic>> _rows = [];
  String _filtre = 'tous';
  String _recherche = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await db
          .from('profiles')
          .select('id, username, full_name, role, city, country_code, '
              'is_suspended, created_at, onboarding_seen_at, '
              'contact_details(phone, whatsapp), '
              // Le nom de la contrainte est obligatoire ici. PostgREST voit
              // deux chemins entre `profiles` et `worker_profiles` : la clé
              // étrangère directe, et une relation plusieurs-à-plusieurs
              // déduite de `favorites`, qui pointe vers les deux tables. Sans
              // désignation explicite il refuse la jointure.
              'worker_profiles!worker_profiles_profile_id_fkey('
              'is_listed, availability, rating_avg, '
              'rating_count, jobs_completed, boosted_until)')
          .order('created_at', ascending: false)
          .limit(300));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _recherche.trim().toLowerCase();
    return _rows.where((r) {
      final w = r['worker_profiles'] as Map?;
      final ok = switch (_filtre) {
        'ouvriers' => '${r['role']}' == 'worker' || '${r['role']}' == 'both',
        'clients' => '${r['role']}' == 'client' || '${r['role']}' == 'both',
        'suspendus' => r['is_suspended'] == true,
        'listes' => w != null && w['is_listed'] == true,
        _ => true,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return '${r['username']} ${r['full_name']} ${r['city']}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final v = _visibles;
    return Scaffold(
      appBar: AppBar(title: Text('Comptes (${v.length})')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Pseudo, nom, ville…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (s) => setState(() => _recherche = s),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final f in const [
                ('tous', 'Tous'),
                ('ouvriers', 'Ouvriers'),
                ('clients', 'Clients'),
                ('listes', 'Dans l\'annuaire'),
                ('suspendus', 'Suspendus'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _filtre == f.$1,
                    onSelected: (_) => setState(() => _filtre = f.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Loading()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: v.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ligne(v[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _ligne(Map<String, dynamic> r) {
    final w = r['worker_profiles'] as Map?;
    final c = r['contact_details'] as Map?;
    final suspendu = r['is_suspended'] == true;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: suspendu
            ? Colors.red.shade50
            : AppTheme.primary.withValues(alpha: 0.10),
        child: Text('${r['full_name'] ?? '?'}'.substring(0, 1).toUpperCase(),
            style: TextStyle(
                color: suspendu ? Colors.red : AppTheme.primary)),
      ),
      title: Row(children: [
        Flexible(
          child: Text('${r['full_name'] ?? 'Sans nom'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (suspendu) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4)),
            child: Text('suspendu',
                style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
          ),
        ],
      ]),
      subtitle: Text(
        '@${r['username'] ?? '—'} · ${r['role']} · ${r['city'] ?? '—'}'
        '${c?['phone'] == null ? '' : ' · ${c!['phone']}'}\n'
        '${w == null ? 'Pas de profil ouvrier' : 'annuaire ${w['is_listed'] == true ? 'oui' : 'non'}'
            ' · ${w['availability']} · note ${w['rating_avg']} (${w['rating_count']})'
            ' · ${w['jobs_completed']} mission(s)'}',
        style: const TextStyle(fontSize: 11),
      ),
      isThreeLine: true,
      trailing: Text(
        Fmt.ago(DateTime.tryParse('${r['created_at']}')),
        style: const TextStyle(fontSize: 10, color: Colors.black45),
      ),
    );
  }
}

/// Archive des conversations.
///
/// L'application prévient déjà que les échanges sont surveillés — le
/// déclencheur `flag_contact_in_message` signale les numéros échangés.
/// Cet écran rend cette surveillance effective plutôt que théorique.
///
/// À déclarer dans la politique de confidentialité et dans le formulaire
/// de sécurité des données de la Play Console : accéder aux messages
/// privés sans le mentionner est un manquement au règlement Google.
class AdminConversationsPage extends StatefulWidget {
  const AdminConversationsPage({super.key});
  @override
  State<AdminConversationsPage> createState() =>
      _AdminConversationsPageState();
}

class _AdminConversationsPageState extends State<AdminConversationsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _fuitesSeules = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await db
          .from('conversations')
          .select('id, last_message_at, created_at, job_id, '
              'client:profiles!conversations_client_id_fkey(full_name, username), '
              'worker:profiles!conversations_worker_id_fkey(full_name, username), '
              'job:job_requests(title)')
          .order('last_message_at', ascending: false, nullsFirst: false)
          .limit(200));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Conversations (${_rows.length})'),
        actions: [
          IconButton(
            tooltip: 'Fuites de contact seulement',
            icon: Icon(_fuitesSeules
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            onPressed: () => setState(() => _fuitesSeules = !_fuitesSeules),
          ),
        ],
      ),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  final cl = c['client'] as Map?;
                  final ou = c['worker'] as Map?;
                  final jb = c['job'] as Map?;
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.forum_outlined, size: 20),
                    title: Text(
                      '${cl?['full_name'] ?? '?'} ↔ ${ou?['full_name'] ?? '?'}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${jb?['title'] ?? 'Sans mission'} · '
                      '${Fmt.ago(DateTime.tryParse('${c['last_message_at']}'))}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminMessagesPage(
                          conversationId: '${c['id']}',
                          titre: '${cl?['full_name'] ?? '?'} ↔ '
                              '${ou?['full_name'] ?? '?'}',
                          fuitesSeules: _fuitesSeules,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class AdminMessagesPage extends StatefulWidget {
  final String conversationId;
  final String titre;
  final bool fuitesSeules;
  const AdminMessagesPage({
    super.key,
    required this.conversationId,
    required this.titre,
    this.fuitesSeules = false,
  });

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var q = db
          .from('messages')
          .select('id, body, created_at, contains_contact, '
              'sender:profiles!messages_sender_id_fkey(full_name)')
          .eq('conversation_id', widget.conversationId);
      if (widget.fuitesSeules) q = q.eq('contains_contact', true);
      _rows = List<Map<String, dynamic>>.from(
          await q.order('created_at', ascending: true).limit(500));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre,
            style: const TextStyle(fontSize: 16), maxLines: 1),
      ),
      body: _loading
          ? const Loading()
          : _rows.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Aucun message',
                  subtitle: 'Cette conversation est vide.')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final m = _rows[i];
                    final fuite = m['contains_contact'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // Un message contenant un numéro est signalé : c'est
                        // la mesure de la fuite hors plateforme, celle qui
                        // décide de la viabilité d'une commission un jour.
                        color: fuite ? const Color(0xFFFFF4E5) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: fuite
                                ? const Color(0xFFF2A03D)
                                : const Color(0xFFE6EAE7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('${(m['sender'] as Map?)?['full_name'] ?? '?'}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (fuite)
                              const Text('contact',
                                  style: TextStyle(
                                      fontSize: 10, color: Color(0xFF7A4B00))),
                            const SizedBox(width: 8),
                            Text(
                              Fmt.ago(DateTime.tryParse('${m['created_at']}')),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black45),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text('${m['body'] ?? ''}',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
