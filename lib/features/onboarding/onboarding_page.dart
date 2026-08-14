import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Une étape de la visite guidée, telle que la base la décrit.
class OnboardingStep {
  final String? icon;
  final String title;
  final String body;

  const OnboardingStep({this.icon, required this.title, required this.body});

  factory OnboardingStep.fromMap(Map<String, dynamic> m) => OnboardingStep(
        icon: m['icon'] as String?,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
      );
}

class OnboardingService {
  /// Étapes correspondant au rôle de l'utilisateur connecté.
  ///
  /// Le filtrage se fait en base : un client n'a que faire d'apprendre à
  /// candidater, et le rôle `both` reçoit les deux parcours.
  static Future<List<OnboardingStep>> mine() async {
    final rows = await db.rpc('onboarding_for_me');
    if (rows is! List) return const [];
    return [
      for (final r in rows) OnboardingStep.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  static Future<void> markSeen() => db.rpc('mark_onboarding_seen');
}

/// Visite guidée de première connexion.
///
/// Présentée une fois, à la première ouverture qui suit l'inscription.
/// L'utilisateur peut avancer librement, mais la sortie n'apparaît qu'à la
/// dernière étape : l'objectif est qu'il ait vu, au minimum, comment
/// l'application se finance.
///
/// Le retour matériel est neutralisé pour la même raison. Ce n'est pas une
/// prison — sept écrans de deux phrases se traversent en vingt secondes —
/// mais un utilisateur qui referme au premier écran ne comprendra ni le
/// boost, ni pourquoi il y a des publicités.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  List<OnboardingStep> _steps = [];
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _steps = await OnboardingService.mine();
    } catch (_) {
      // Hors ligne ou migration non appliquée : on ne bloque pas l'entrée
      // dans l'application pour un écran d'accueil.
      _steps = const [];
    }
    if (mounted) setState(() => _loading = false);
    if (_steps.isEmpty) await _finish();
  }

  Future<void> _finish() async {
    try {
      await OnboardingService.markSeen();
    } catch (_) {
      // L'échec est sans conséquence immédiate : la visite se represente
      // au prochain démarrage, ce qui vaut mieux que de bloquer ici.
    }
    if (mounted) await context.read<AppSession>().refresh();
  }

  /// Les icônes viennent de la base sous forme de nom : on les résout ici
  /// plutôt que d'exposer `IconData` à des données modifiables à distance.
  IconData _icon(String? nom) => switch (nom) {
        'post_add' => Icons.post_add,
        'assignment_turned_in' => Icons.assignment_turned_in_outlined,
        'phone_in_talk' => Icons.phone_in_talk_outlined,
        'work_outline' => Icons.work_outline,
        'forum_outlined' => Icons.forum_outlined,
        'rocket_launch' => Icons.rocket_launch,
        'favorite_outline' => Icons.favorite_outline,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Loading());
    if (_steps.isEmpty) return const Scaffold(body: Loading());

    final dernier = _index >= _steps.length - 1;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final s = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon(s.icon),
                              size: 44, color: AppTheme.primary),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 23, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15, height: 1.5, color: Colors.black87),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Points de progression : sans repère, l'utilisateur ne sait
            // pas s'il lui reste deux écrans ou vingt, et abandonne.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppTheme.primary
                          : Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: dernier
                      ? _finish
                      : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                  child: Text(dernier ? 'Commencer' : 'Suivant'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
