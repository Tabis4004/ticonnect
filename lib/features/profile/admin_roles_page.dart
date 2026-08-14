import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Nomination des administrateurs.
///
/// Réservé au superadministrateur — la vérification est en base
/// (`set_admin_role` lève `FORBIDDEN`, et la politique `admins_super_write`
/// refuse l'écriture directe). Masquer l'écran n'est qu'un confort.
class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});
  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

/// Ce que chaque rôle ouvre, dit dans les termes de l'application et non
/// dans ceux des politiques RLS. Un superadministrateur qui nomme quelqu'un
/// doit pouvoir décider sans lire le schéma.
const _roles = <String, ({String titre, String detail})>{
  'superadmin': (
    titre: 'Superadministrateur',
    detail: 'Tout, y compris les réglages, les tarifs par pays, '
        'le catalogue des métiers et la nomination des administrateurs.',
  ),
  'moderateur': (
    titre: 'Modérateur',
    detail: 'Signalements, profils, missions et avis. '
        'Ne touche ni aux réglages, ni aux tarifs, ni au catalogue.',
  ),
  'lecteur': (
    titre: 'Lecteur',
    detail: 'Consulte le tableau de bord et les statistiques. '
        "N'écrit rien.",
  ),
};

class _AdminRolesPageState extends State<AdminRolesPage> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _admins = List<Map<String, dynamic>>.from(await db.rpc('list_admins'));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _apply(String username, String role) async {
    setState(() => _busy = true);
    try {
      await db.rpc('set_admin_role',
          params: {'p_username': username, 'p_role': role});
      if (mounted) showOk(context, '$username · ${_roles[role]!.titre}');
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _revoke(String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retirer les droits ?'),
        content: Text("$username perdra tout accès à l'administration. "
            'Son compte utilisateur, lui, reste intact.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Retirer', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await db.rpc('revoke_admin', params: {'p_username': username});
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Choix du compte dans la liste, puis choix du rôle.
  ///
  /// Le compte se choisit et ne se tape pas : le superadmin ne connaît pas
  /// par cœur les pseudos, et une faute de frappe se soldait par « aucun
  /// compte ne porte ce pseudo » sans rien pour s'orienter.
  ///
  /// Le rôle est demandé en second et sans valeur par défaut : proposer
  /// « Superadministrateur » présélectionné ferait du droit le plus large
  /// le résultat d'une validation distraite.
  Future<void> _nommer() async {
    final username = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ChoixCompte()),
    );
    if (username == null || !mounted) return;

    final role = await _choisirRole(titre: 'Quel accès pour $username ?');
    if (role != null) await _apply(username, role);
  }

  Future<String?> _choisirRole({required String titre, String? actuel}) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(titre,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final e in _roles.entries)
            ListTile(
              title: Text(e.value.titre),
              subtitle: Text(e.value.detail,
                  style: const TextStyle(fontSize: 12)),
              trailing: e.key == actuel
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(c, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrateurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _nommer,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nommer'),
      ),
      body: _loading
          ? const Loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const Text(
                    'Les trois niveaux se distinguent par ce qu’ils peuvent '
                    'écrire, jamais par ce qu’ils voient : tous les trois '
                    'consultent le tableau de bord complet.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  for (final a in _admins) _ligne(a),
                ],
              ),
            ),
    );
  }

  Widget _ligne(Map<String, dynamic> a) {
    final role = '${a['role']}';
    final username = '${a['username']}';
    final info = _roles[role];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6EAE7)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: role == 'superadmin'
              ? AppTheme.primary
              : AppTheme.primary.withValues(alpha: 0.12),
          child: Icon(
            role == 'lecteur' ? Icons.visibility_outlined : Icons.shield_outlined,
            size: 18,
            color: role == 'superadmin' ? Colors.white : AppTheme.primary,
          ),
        ),
        title: Text(username,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${info?.titre ?? role}'
          '${a['full_name'] == null ? '' : ' · ${a['full_name']}'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _busy
            ? null
            : PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'role', child: Text('Changer le rôle')),
                  PopupMenuItem(
                      value: 'revoke', child: Text('Retirer les droits')),
                ],
                onSelected: (v) async {
                  if (v == 'revoke') {
                    await _revoke(username);
                  } else {
                    final r = await _choisirRole(
                        titre: 'Accès de $username', actuel: role);
                    if (r != null && r != role) await _apply(username, r);
                  }
                },
              ),
      ),
    );
  }
}

/// Liste des comptes, avec recherche.
///
/// Rend le pseudo choisi. La recherche part vide et affiche les
/// administrateurs en tête : ouvrir cet écran sert aussi bien à en nommer un
/// nouveau qu'à retrouver celui dont on veut changer le rôle.
class _ChoixCompte extends StatefulWidget {
  const _ChoixCompte();
  @override
  State<_ChoixCompte> createState() => _ChoixCompteState();
}

class _ChoixCompteState extends State<_ChoixCompte> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      _rows = List<Map<String, dynamic>>.from(await db.rpc(
        'search_profiles_for_admin',
        params: {'p_query': q, 'p_limit': 50},
      ));
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un compte')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Pseudo ou nom',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: () => _search(_ctrl.text),
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Loading()
              : _rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Aucun compte',
                      subtitle: 'Essaie une autre orthographe.',
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final role = r['role'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              '${r['username'] ?? '?'}'
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(color: AppTheme.primary),
                            ),
                          ),
                          title: Text('${r['username']}'),
                          subtitle: Text(
                            role == null
                                ? (r['full_name'] as String? ?? '—')
                                : 'Déjà ${_roles[role]?.titre ?? role}',
                            style: TextStyle(
                              fontSize: 12,
                              color: role == null
                                  ? Colors.black54
                                  : AppTheme.primary,
                            ),
                          ),
                          onTap: () =>
                              Navigator.pop(context, '${r['username']}'),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
