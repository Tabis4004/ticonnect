import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/auth_pages.dart';
import 'features/shell/app_shell.dart';
import 'services/ads_service.dart';
import 'services/session.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sans cette initialisation, DateFormat('d MMM', 'fr') lève une
  // exception : les symboles de date ne sont pas chargés par défaut.
  await initializeDateFormatting('fr');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseKey,
  );

  // Le SDK publicitaire s'initialise en arrière-plan : on ne bloque pas
  // le premier écran, et une absence de réseau ne fige pas l'application.
  unawaited(AdsService.init());

  runApp(const TiconnectApp());
}

class TiconnectApp extends StatelessWidget {
  const TiconnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session(),
      child: MaterialApp(
        title: 'Ticonnect',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _Gate(),
      ),
    );
  }
}

/// Aiguillage : écran de connexion ou application selon l'état de session.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (session.loading) {
      return const Scaffold(body: Loading());
    }
    if (!session.isSignedIn) return const PhoneInputPage();
    return const AppShell();
  }
}
