/// Configuration de l'application.
///
/// Les valeurs par défaut pointent vers le projet Supabase `Ticonnect 1.0`.
/// La clé ci-dessous est une clé *publiable* : elle est conçue pour vivre dans
/// le code client. Toute la sécurité repose sur les politiques RLS, jamais sur
/// le secret de cette clé.
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
    defaultValue: 'sb_publishable_67hCGFXM9MtHW4tvhwuldA_6ov3luzu',
  );

  /// Pays par défaut. Détermine la devise et le préfixe téléphonique.
  static const defaultCountry = 'CI';
  static const defaultDialCode = '+225';
  static const defaultCurrency = 'XOF';

  /// Mode test AdMob. À passer à false uniquement pour une build de production
  /// avec de vrais identifiants d'unités publicitaires.
  static const adsTestMode = bool.fromEnvironment('ADS_TEST', defaultValue: true);
}
