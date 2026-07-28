import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/countries.dart';
import '../../core/l10n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';
import '../../widgets/country_picker.dart';

/// Connexion : pseudo (ou email, pour les comptes admin) et mot de passe.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final _identifier = TextEditingController(text: AppConfig.devEmail);
  late final _password = TextEditingController(text: AppConfig.devPassword);
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) {
      showError(context, 'Entre ton pseudo et ton mot de passe'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.signIn(_identifier.text, _password.text);
      if (!mounted) return;
      await context.read<AppSession>().refresh();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) showError(context, 'Pseudo ou mot de passe incorrect'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 32),
          const Icon(Icons.handyman_rounded, size: 56, color: AppTheme.primary),
          const SizedBox(height: 20),
          const Text('Ticonnect',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Trouve un ouvrier près de chez toi, ou trouve du travail.'.tr,
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _identifier,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Pseudo'.tr,
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'Mot de passe'.tr,
              prefixIcon: const Icon(Icons.lock_outline),
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
            FilledButton(onPressed: _submit, child: Text('Se connecter'.tr)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpPage()),
            ),
            child: Text('Créer un compte'.tr),
          ),
        ]),
      ),
    );
  }
}

/// Inscription : pseudo, mot de passe, et le minimum vital.
///
/// Le téléphone est demandé mais **non vérifié** : c'est la coordonnée que
/// l'autre partie utilisera pour appeler, pas un identifiant de connexion.
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();

  Country _country = Countries.byCode(AppConfig.defaultCountry);
  String _role = 'client';
  bool _busy = false;
  bool _hide = true;
  String? _usernameError;
  bool? _usernameFree;

  @override
  void dispose() {
    for (final c in [_username, _password, _fullName, _phone, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkUsername() async {
    final v = _username.text.trim().toLowerCase();
    final formatError = AuthService.validateUsername(v);
    if (formatError != null) {
      setState(() {
        _usernameError = formatError;
        _usernameFree = null;
      });
      return;
    }
    final free = await AuthService.usernameAvailable(v);
    if (!mounted) return;
    setState(() {
      _usernameFree = free;
      _usernameError = free ? null : 'Ce pseudo est déjà pris';
    });
  }

  Future<void> _submit() async {
    final v = _username.text.trim().toLowerCase();
    final formatError = AuthService.validateUsername(v);
    if (formatError != null) {
      showError(context, formatError);
      return;
    }
    if (_password.text.length < 6) {
      showError(context, 'Mot de passe : 6 caractères minimum'.tr);
      return;
    }
    if (_fullName.text.trim().length < 2) {
      showError(context, 'Entre ton nom'.tr);
      return;
    }
    if (_phone.text.trim().length < 6) {
      showError(context, 'Entre ton numéro de téléphone');
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await AuthService.usernameAvailable(v)) {
        if (mounted) showError(context, 'Ce pseudo est déjà pris'.tr);
        return;
      }
      await AuthService.signUp(
        username: v,
        password: _password.text,
        fullName: _fullName.text,
        phone: _phone.text,
        country: _country,
        role: _role,
        city: _city.text,
      );
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
      appBar: AppBar(title: Text('Créer un compte'.tr)),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
          controller: _username,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
          ],
          decoration: InputDecoration(
            labelText: 'Pseudo'.tr,
            hintText: 'ibrahim.macon',
            prefixIcon: const Icon(Icons.person_outline),
            errorText: _usernameError,
            suffixIcon: _usernameFree == true
                ? const Icon(Icons.check_circle, color: AppTheme.primary)
                : null,
          ),
          onChanged: (_) => setState(() {
            _usernameFree = null;
            _usernameError = null;
          }),
          onEditingComplete: _checkUsername,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          decoration: InputDecoration(
            labelText: 'Mot de passe'.tr,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Ton nom'.tr,
            hintText: 'Ibrahim Traoré',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Ton numéro de téléphone',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          CountryPickerButton(
            selected: _country,
            onChanged: (c) => setState(() => _country = c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
              ],
              decoration: const InputDecoration(hintText: '07 58 22 91 40'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Ce numéro reste privé. Il ne sera visible que par les personnes '
          'avec qui tu choisis de travailler.',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Ta ville',
            hintText: 'Abidjan',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 24),
        Text('Ton pays'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          "Détermine la langue de l'application et l'indicatif téléphonique.".tr,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: CountryPickerButton(
            selected: _country,
            showName: true,
            onChanged: (c) {
              setState(() => _country = c);
              // Aperçu immédiat : l'écran bascule dans la langue du pays.
              L.instance.setLanguage(c.lang);
            },
          ),
        ),
        const SizedBox(height: 24),
        Text('Tu viens pour…'.tr,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _RoleTile(
          icon: Icons.search_rounded,
          title: 'Trouver un ouvrier'.tr,
          subtitle: "Chercher dans l'annuaire, publier des demandes. Gratuit.".tr,
          selected: _role == 'client',
          onTap: () => setState(() => _role = 'client'),
        ),
        const SizedBox(height: 10),
        _RoleTile(
          icon: Icons.construction_rounded,
          title: 'Trouver du travail'.tr,
          subtitle: 'Être alerté des missions près de chez toi.'.tr,
          selected: _role == 'worker',
          onTap: () => setState(() => _role = 'worker'),
        ),
        const SizedBox(height: 28),
        if (_busy)
          const Loading()
        else
          FilledButton(
              onPressed: _submit, child: Text('Créer mon compte'.tr)),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFDDE2DE),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? AppTheme.primary : Colors.black45),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
          if (selected) const Icon(Icons.check_circle, color: AppTheme.primary),
        ]),
      ),
    );
  }
}
