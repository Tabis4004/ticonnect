import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'features/auth/auth_pages.dart';
import 'features/auth/forced_password_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/shell/app_shell.dart';
import 'features/update/update_gate.dart';
import 'services/ads_service.dart';
import 'services/push_service.dart';
import 'services/session.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sans cette initialisation, DateFormat('d MMM', 'fr') lève une
  // exception : les symboles de date ne sont pas chargés par défaut.
  await initializeDateFormatting('fr');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );

  // Le SDK publicitaire s'initialise en arrière-plan : on ne bloque pas
  // le premier écran, et une absence de réseau ne fige pas l'application.
  unawaited(AdsService.init());

  // Idem pour les notifications : demander la permission ne doit pas
  // retarder l'affichage, et un refus n'empêche rien d'autre.
  unawaited(PushService.init());

  runApp(const TiconnectApp());
}

class TiconnectApp extends StatefulWidget {
  const TiconnectApp({super.key});

  @override
  State<TiconnectApp> createState() => _TiconnectAppState();
}

class _TiconnectAppState extends State<TiconnectApp>
    with WidgetsBindingObserver {
  /// Le premier passage au premier plan est celui du démarrage. AdMob
  /// interdit d'y afficher une publicité de retour — et la sanctionne.
  bool _firstResume = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final first = _firstResume;
    _firstResume = false;
    // L'emplacement est désactivé par défaut en base : rien ne s'affiche
    // tant qu'un administrateur ne l'active pas, ce qui laisse le temps de
    // juger sur des chiffres réels si la gêne vaut le revenu.
    unawaited(AdsService.maybeShowAppOpen(firstLaunch: first));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppSession(),
      // L'arbre entier se reconstruit au changement de langue : les chaînes
      // sont résolues à la construction, pas mises en cache.
      child: ListenableBuilder(
        listenable: L.instance,
        builder: (context, _) => MaterialApp(
          title: 'Ticonnect',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: Locale(L.instance.lang),
          // Le contrôle de version enveloppe l'aiguillage de session : une
          // version retirée doit être arrêtée avant l'écran de connexion.
          home: const UpdateGate(child: _Gate()),
        ),
      ),
    );
  }
}

/// Aiguillage : écran de connexion ou application selon l'état de session.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    if (session.loading) {
      return const Scaffold(body: Loading());
    }
    if (!session.isSignedIn) return const SignInPage();

    // Mot de passe fixé par un administrateur : tant qu'il n'en a pas
    // choisi un autre, rien ne s'affiche. Devant la visite guidée — un
    // compte dont le mot de passe circule encore ne doit rien pouvoir
    // faire.
    //
    // Visite guidée : une fois, à la première ouverture qui suit
    // l'inscription. Placée ici plutôt que dans AppShell pour qu'elle
    // occupe l'écran entier, sans barre de navigation à contourner.
    return PasswordGate(
      child: (session.profile != null &&
              session.profile!.onboardingSeenAt == null)
          ? const OnboardingPage()
          : const AppShell(),
    );
  }
}
