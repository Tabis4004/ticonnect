import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Saisie du numéro de téléphone.
///
/// Pas d'email, pas de mot de passe : sur ce marché le numéro est l'identité
/// de fait, et il sert ensuite de coordonnée de contact monétisable.
class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});
  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _phone.text.trim();
    if (raw.length < 8) {
      showError(context, 'Entre un numéro valide');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.sendCode(raw);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpPage(phone: raw)),
      );
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.handyman_rounded, size: 56, color: AppTheme.primary),
              const SizedBox(height: 20),
              const Text('Ticonnect',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Trouve un ouvrier près de chez toi, ou trouve du travail.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              const Text('Ton numéro de téléphone',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
                ],
                decoration: const InputDecoration(
                  prefixText: '${AppConfig.defaultDialCode}  ',
                  hintText: '07 58 22 91 40',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu recevras un code par SMS. Ton numéro reste privé : il ne sera '
                'visible que par les personnes avec qui tu choisis de travailler.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const Spacer(),
              if (_busy)
                const Loading()
              else
                FilledButton(onPressed: _submit, child: const Text('Continuer')),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saisie du code SMS et création du profil.
class OtpPage extends StatefulWidget {
  final String phone;
  const OtpPage({super.key, required this.phone});
  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _role = 'client';
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().length < 4) {
      showError(context, 'Entre le code reçu par SMS');
      return;
    }
    if (_name.text.trim().length < 2) {
      showError(context, 'Entre ton nom');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.verifyCode(
        phone: widget.phone,
        code: _code.text.trim(),
        fullName: _name.text.trim(),
        role: _role,
      );
      if (!mounted) return;
      await context.read<Session>().refresh();
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
      appBar: AppBar(title: const Text('Vérification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code envoyé au ${widget.phone}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(hintText: '000000', counterText: ''),
            ),
            const SizedBox(height: 20),
            const Text('Ton nom', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Ibrahim Traoré'),
            ),
            const SizedBox(height: 24),
            const Text('Tu viens pour…', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _RoleTile(
              icon: Icons.search_rounded,
              title: 'Trouver un ouvrier',
              subtitle: 'Publier des demandes, contacter des artisans. Gratuit.',
              selected: _role == 'client',
              onTap: () => setState(() => _role = 'client'),
            ),
            const SizedBox(height: 10),
            _RoleTile(
              icon: Icons.construction_rounded,
              title: 'Trouver du travail',
              subtitle: 'Recevoir des missions près de chez toi.',
              selected: _role == 'worker',
              onTap: () => setState(() => _role = 'worker'),
            ),
            const SizedBox(height: 32),
            if (_busy)
              const Loading()
            else
              FilledButton(onPressed: _submit, child: const Text('Valider')),
          ],
        ),
      ),
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
          color: selected ? AppTheme.primary.withOpacity(0.08) : Colors.white,
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
