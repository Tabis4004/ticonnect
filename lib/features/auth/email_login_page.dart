import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../services/auth_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Connexion par email et mot de passe.
///
/// Réservée au compte administrateur et aux comptes de test : l'inscription
/// normale passe par SMS. Les champs sont pré-remplis depuis `dev.json`
/// (ignoré par Git) quand on lance avec `--dart-define-from-file=dev.json`.
class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key});
  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  late final _email = TextEditingController(text: AppConfig.devEmail);
  late final _password = TextEditingController(text: AppConfig.devPassword);
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      showError(context, 'Entre ton email et ton mot de passe');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.signInWithEmail(_email.text, _password.text);
      if (!mounted) return;
      await context.read<AppSession>().refresh();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion par email')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
          'Accès administrateur et comptes de test. '
          'Les utilisateurs se connectent par SMS.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 28),
        if (_busy)
          const Loading()
        else
          FilledButton(onPressed: _submit, child: const Text('Se connecter')),
        if (AppConfig.hasDevCredentials) ...[
          const SizedBox(height: 20),
          const Text(
            'Identifiants de développement chargés depuis dev.json.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ],
      ]),
    );
  }
}
