import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Utilisateurs et droits d'administration, sur une seule page.
///
/// La version précédente listait les seuls administrateurs et cachait les
/// utilisateurs derrière un écran de recherche. Deux défauts : la page était
/// vide tant que personne n'avait été nommé — donc au moment précis où l'on
/// vient pour nommer quelqu'un — et rien ne montrait qui existait.
///
/// Ici tout le monde est listé, chacun avec son niveau, et le niveau se
/// change en touchant la ligne.
///
/// Réservé au superadministrateur. La vérification est en base :
/// `search_profiles_for_admin` et `set_admin_role` refusent tout autre
/// appelant, et la politique `admins_super_write` refuse l'écriture directe.
/// Masquer l'écran n'est qu'un confort.
class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});
  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

/// Ce que chaque niveau ouvre, dit dans les termes de l'application et non
/// dans ceux des politiques RLS : on doit pouvoir décider sans lire le schéma.
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
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _busy = false;

  /// Affichée dans le corps de la page, et non dans un message éphémère.
  ///
  /// Une erreur montrée en snackbar disparaît en quatre secondes et laisse
  /// une liste vide derrière elle : impossible de distinguer « la requête a
  /// échoué » de « il n'y a personne ». C'est exactement ce qui s'est
  /// produit sur la version précédente de cet écran.
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Le niveau de l'utilisateur courant. Décide de ce que la feuille
  /// d'actions propose : un modérateur dépanne un mot de passe, il ne
  /// nomme personne.
  bool _isSuper = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erreur = null;
    });
    try {
      try {
        _isSuper = (await db.rpc('is_superadmin') as bool?) ?? false;
      } catch (_) {
        _isSuper = false;
      }
      _users = List<Map<String, dynamic>>.from(await db.rpc(
        'search_profiles_for_admin',
        params: {'p_query': _search.text.trim(), 'p_limit': 100},
      ));
    } catch (e) {
      _erreur = humanError(e);
      _users = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _apply(String username, String? role) async {
    setState(() => _busy = true);
    try {
      if (role == null) {
        await db.rpc('revoke_admin', params: {'p_username': username});
      } else {
        await db.rpc('set_admin_role',
            params: {'p_username': username, 'p_role': role});
      }
      if (mounted) {
        showOk(context,
            role == null ? '$username · accès retiré' : '$username · ${_roles[role]!.titre}');
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Ce qu'on peut faire d'un compte. Deux gestes de portée très
  /// différente, donc un choix explicite entre les deux plutôt qu'un accès
  /// direct à l'un d'eux.
  Future<void> _actions(Map<String, dynamic> u) async {
    final username = '${u['username'] ?? '?'}';
    final role = u['role'] as String?;
    final cibleEstAdmin = role != null;

    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text('@$username',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (_isSuper)
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text("Changer le niveau d'accès"),
              subtitle: Text(
                role == null ? 'Aucun accès' : _roles[role]?.titre ?? role,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(c);
                _choisirRole(username, role);
              },
            ),
          ListTile(
            leading: Icon(Icons.key_outlined,
                color: (cibleEstAdmin && !_isSuper) ? Colors.black26 : null),
            title: const Text('Réinitialiser le mot de passe'),
            subtitle: Text(
              cibleEstAdmin && !_isSuper
                  // Dit franchement plutôt que masqué : un bouton qui
                  // disparaît fait douter de ses propres droits.
                  ? 'Réservé au superadministrateur pour un compte qui a déjà '
                      'un accès.'
                  : "Fixe un mot de passe provisoire. L'utilisateur devra en "
                      'choisir un autre à sa prochaine connexion.',
              style: const TextStyle(fontSize: 12),
            ),
            enabled: !(cibleEstAdmin && !_isSuper),
            onTap: () {
              Navigator.pop(c);
              _reinitialiser(u);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Réinitialisation.
  ///
  /// Le mot de passe est fabriqué ici plutôt que saisi par l'administrateur :
  /// celui qui doit le dicter au téléphone choisirait quelque chose de court
  /// et de devinable, et le réutiliserait d'un compte à l'autre.
  Future<void> _reinitialiser(Map<String, dynamic> u) async {
    final username = '${u['username'] ?? '?'}';
    final id = '${u['id']}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Réinitialiser le mot de passe de @$username ?'),
        content: const Text(
          "Son mot de passe actuel cessera immédiatement de fonctionner. "
          "Tu obtiendras un mot de passe provisoire à lui transmettre, et il "
          "devra en choisir un autre dès sa connexion suivante.\n\n"
          "L'opération est enregistrée avec ton nom.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Réinitialiser',
                style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final motDePasse = _motDePasseProvisoire();
    setState(() => _busy = true);
    try {
      final res = await db.functions.invoke(
        'admin-reset-password',
        body: {'profile_id': id, 'password': motDePasse},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception('${data['error']}');
      }
      if (mounted) await _afficherMotDePasse(username, motDePasse);
    } catch (e) {
      if (mounted) showError(context, _messageReinit(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Affiché une seule fois, sans possibilité de le retrouver ensuite : il
  /// n'est stocké nulle part en clair, pas même côté serveur.
  Future<void> _afficherMotDePasse(String username, String motDePasse) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Mot de passe provisoire'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('À transmettre à @$username, puis à oublier.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          SelectableText(
            motDePasse,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 16),
          const Text(
            "Il ne sera plus affiché. S'il est perdu, refais une "
            'réinitialisation.',
            style: TextStyle(fontSize: 11, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: motDePasse));
              if (c.mounted) Navigator.pop(c);
              if (mounted) showOk(context, 'Copié');
            },
            child: const Text('Copier et fermer'),
          ),
        ],
      ),
    );
  }

  /// Douze caractères, sans les couples qu'on confond en les dictant :
  /// ni O ni 0, ni I ni l ni 1. Le mot de passe passera par la voix ou par
  /// un SMS, pas par un copier-coller.
  String _motDePasseProvisoire() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => alphabet[rnd.nextInt(alphabet.length)])
        .join();
  }

  String _messageReinit(Object e) {
    final s = '$e';
    if (s.contains('RESET_ADMIN_FORBIDDEN')) {
      return "Ce compte a déjà un accès d'administration. Seul un "
          'superadministrateur peut réinitialiser son mot de passe.';
    }
    if (s.contains('RESET_SELF')) {
      return 'Pour ton propre mot de passe, passe par Mon compte.';
    }
    if (s.contains('FORBIDDEN')) {
      return "Tu n'as pas les droits pour cette action.";
    }
    if (s.contains('USER_UNKNOWN')) {
      return "Ce compte n'existe plus. Actualise la liste.";
    }
    if (s.contains('PASSWORD_TOO_SHORT')) {
      return 'Mot de passe trop court — signale-le, c\'est un défaut du code.';
    }
    return humanError(e);
  }

  /// Le niveau actuel porte une coche ; aucun n'est présélectionné pour un
  /// compte ordinaire. Proposer « Superadministrateur » par défaut ferait du
  /// droit le plus large le résultat d'une validation distraite.
  Future<void> _choisirRole(String username, String? actuel) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text('Accès de $username',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final e in _roles.entries)
              ListTile(
                title: Text(e.value.titre),
                subtitle:
                    Text(e.value.detail, style: const TextStyle(fontSize: 12)),
                trailing: e.key == actuel
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () => Navigator.pop(c, e.key),
              ),
            const Divider(height: 1),
            ListTile(
              title: Text('Aucun accès',
                  style: TextStyle(
                      color: actuel == null ? null : Colors.red.shade700)),
              subtitle: const Text(
                  'Utilisateur ordinaire. Son compte reste intact.',
                  style: TextStyle(fontSize: 12)),
              trailing: actuel == null
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(c, '_aucun'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );

    if (choix == null || !mounted) return;
    final vise = choix == '_aucun' ? null : choix;
    if (vise == actuel) return;

    // Retirer un accès se confirme ; en accorder un se fait d'un geste. Le
    // premier casse quelque chose qui fonctionnait, le second non.
    if (vise == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Retirer les droits ?'),
          content: Text("$username perdra tout accès à l'administration."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuler')),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  Text('Retirer', style: TextStyle(color: Colors.red.shade700)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    await _apply(username, vise);
  }

  @override
  Widget build(BuildContext context) {
    final admins = _users.where((u) => u['role'] != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs et droits'),
        actions: [
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Pseudo ou nom',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _load,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _loading
                  ? ''
                  : '${_users.length} compte(s) · $admins avec un accès · '
                      'touche une ligne pour agir dessus',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Loading()
              : _erreur != null
                  ? _erreurView()
                  : _users.isEmpty
                      ? const EmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'Aucun compte',
                          subtitle: 'Essaie une autre orthographe.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _ligne(_users[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _erreurView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(_erreur!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
        ]),
      ),
    );
  }

  Widget _ligne(Map<String, dynamic> u) {
    final role = u['role'] as String?;
    final username = '${u['username'] ?? '?'}';
    final nom = u['full_name'] as String?;

    return ListTile(
      enabled: !_busy,
      leading: CircleAvatar(
        backgroundColor: role == 'superadmin'
            ? AppTheme.primary
            : AppTheme.primary.withValues(alpha: 0.12),
        child: role == null
            ? Text(username.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: AppTheme.primary))
            : Icon(
                role == 'lecteur'
                    ? Icons.visibility_outlined
                    : Icons.shield_outlined,
                size: 18,
                color: role == 'superadmin' ? Colors.white : AppTheme.primary,
              ),
      ),
      title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(nom == null || nom.isEmpty ? '—' : nom,
          style: const TextStyle(fontSize: 12), maxLines: 1),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (role != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_roles[role]?.titre ?? role,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        const Icon(Icons.chevron_right, color: Colors.black26),
      ]),
      onTap: _busy ? null : () => _actions(u),
    );
  }
}
