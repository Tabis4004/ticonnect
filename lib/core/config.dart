/// Configuration de l'application.
///
/// Les valeurs par défaut pointent vers le projet Supabase `Ticonnect 1.0`.
/// La clé ci-dessous est la clé *anon publique* du projet : elle est faite
/// pour vivre dans le code client et peut donc être committée sans risque.
/// Toute la sécurité repose sur les politiques RLS, jamais sur son secret.
///
/// C'est la forme JWT historique, retenue plutôt que le format récent
/// `sb_publishable_...` : elle est acceptée par toutes les versions du SDK,
/// y compris la contrainte `supabase_flutter: ^2.5.0` de ce projet.
///
/// Ne jamais mettre ici la clé `service_role` : elle contourne la RLS et
/// donnerait à quiconque lit l'APK un accès total à la base.
///
/// Pour cibler un autre environnement :
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://feawmdvwzrbajuxtuzyf.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYXdtZHZ3enJiYWp1eHR1enlmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyMzQ5MTYsImV4cCI6MjEwMDgxMDkxNn0.Nnyqj_TFFsYndpTBSIPLlIsy9yHOZ29wh38cZogKPgM',
  );

  /// Pays par défaut. Détermine la devise et le préfixe téléphonique.
  static const defaultCountry = 'CI';
  static const defaultDialCode = '+225';
  static const defaultCurrency = 'XOF';

  /// Identifiants de développement, injectés au lancement :
  ///   flutter run --dart-define-from-file=dev.json
  ///
  /// Volontairement vides par défaut : `dev.json` est ignoré par Git.
  /// Le dépôt étant public, un mot de passe committé donnerait à n'importe
  /// qui l'accès superadmin à la base de production.
  static const devEmail = String.fromEnvironment('DEV_EMAIL');
  static const devPassword = String.fromEnvironment('DEV_PASSWORD');
  static bool get hasDevCredentials => devEmail.isNotEmpty;

  /// Mode test AdMob. À passer à false uniquement pour une build de production
  /// avec de vrais identifiants d'unités publicitaires.
  static const adsTestMode = bool.fromEnvironment('ADS_TEST', defaultValue: true);
}
