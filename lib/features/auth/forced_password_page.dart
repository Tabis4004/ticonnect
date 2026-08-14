import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Interpose le choix d'un nouveau mot de passe, si un administrateur en a
/// fixé un provisoire.
///
/// C'est ce qui rend la réinitialisation par un administrateur acceptable.
/// Sans cet écran, le mot de passe qu'il a dicté resterait valable
/// indéfiniment : il pourrait se connecter au compte quand il veut, lire
/// les conversations privées de la personne, candidater en son nom. Ici, le
/// mot de passe qu'il connaît meurt à la première connexion de l'intéressé.
///
/// Placé avant la visite guidée : un compte dont le mot de passe circule
/// encore ne doit rien pouvoir faire d'autre.
class PasswordGate extends StatefulWidget {
  const PasswordGate({super.key, required this.child});

  final Widget child;

  @override
  State<PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends State<PasswordGate> {
  /// Nul tant que la réponse n'est pas connue. On affiche l'application
  /// pendant ce temps : bloquer le démarrage sur un appel réseau serait un
  /// écran figé certain contre un cas rare.
  bool? _requis;

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  Future<void> _verifier() async {
    bool requis = false;
    try {
      requis = (await db.rpc('password_change_required') as bool?) ?? false;
    } catch (_) {
      // Hors ligne, ou fonction absente : on n'enferme personne.
      requis = false;
    }
    if (mounted) setState(() => _requis = requis);
  }

  @override
  Widget build(BuildContext context) {
    if (_requis != true) return widget.child;
    return _ChangementForce(onTermine: () => setState(() => _requis = false));
  }
}

class _ChangementForce extends StatefulWidget {
  const _ChangementForce({required this.onTermine});

  final VoidCallback onTermine;

  @override
  State<_ChangementForce> createState() => _ChangementForceState();
}

class _ChangementForceState extends State<_ChangementForce> {
  final _mdp = TextEditingController();
  final _confirmation = TextEditingController();
  bool _masque = true;
  bool _busy = false;
  String? _erreur;

  @override
  void dispose() {
    _mdp.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final mdp = _mdp.text;

    // Huit caractères, contre six imposés par Supabase. Ce mot de passe
    // protège des numéros de téléphone et des conversations.
    if (mdp.length < 8) {
      setState(() => _erreur = 'Au moins 8 caractères.');
      return;
    }
    if (mdp != _confirmation.text) {
      setState(() => _erreur = 'Les deux saisies ne sont pas identiques.');
      return;
    }

    setState(() {
      _busy = true;
      _erreur = null;
    });
    try {
      await db.auth.updateUser(UserAttributes(password: mdp));
      // Ordre important : le marqueur ne se lève qu'une fois le mot de
      // passe réellement changé. Si l'application se ferme entre les deux,
      // l'écran réapparaîtra — un désagrément, pas une faille.
      await db.rpc('clear_must_change_password');
      if (mounted) {
        showOk(context, 'Mot de passe enregistré');
        widget.onTermine();
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = humanError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_reset,
                    size: 56, color: AppTheme.primary.withValues(alpha: 0.85)),
                const SizedBox(height: 20),
                const Text(
                  'Choisis un nouveau mot de passe',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Un administrateur a réinitialisé ton mot de passe. Celui "
                  "qu'on t'a transmis cesse de fonctionner dès que tu en "
                  'choisis un autre — personne d\'autre que toi ne le '
                  'connaîtra.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _mdp,
                  obscureText: _masque,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_masque
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _masque = !_masque),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmation,
                  obscureText: _masque,
                  onSubmitted: (_) => _busy ? null : _enregistrer(),
                  decoration: const InputDecoration(
                    labelText: 'Répète-le',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _enregistrer,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Enregistrer'),
                  ),
                ),
                const SizedBox(height: 8),
                // Une porte de sortie, sinon l'écran est un piège pour
                // quelqu'un qui n'a pas reçu son mot de passe provisoire et
                // se retrouve connecté sur un appareil partagé.
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.read<AppSession>().signOut(),
                  child: const Text('Se déconnecter'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
