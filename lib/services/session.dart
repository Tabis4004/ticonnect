import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/supabase.dart';
import '../models/models.dart';
import 'auth_service.dart';
import 'push_service.dart';

/// État de session : utilisateur connecté, profil, profil ouvrier, crédits.
///
/// Un seul objet observable pour toute l'app, exposé via Provider. Évite
/// d'aller relire la base à chaque écran pour savoir qui est connecté.
class AppSession extends ChangeNotifier {
  /// Pays de l'utilisateur connecté, accessible depuis les services.
  ///
  /// `AppConfig.defaultCountry` est une constante de compilation figée à
  /// « CI ». Elle servait de pays à la recherche d'ouvriers, à la recherche
  /// de missions ET à l'enregistrement des missions publiées — si bien
  /// qu'un client de Lomé publiait une demande étiquetée ivoirienne,
  /// invisible pour les ouvriers togolais et proposée à des ouvriers
  /// d'Abidjan.
  ///
  /// Cette valeur suit désormais le profil. La constante ne sert plus que
  /// de repli, avant que le profil ne soit chargé.
  static String currentCountry = AppConfig.defaultCountry;
  Profile? profile;
  WorkerProfile? worker;
  Wallet? wallet;
  bool isAdmin = false;
  bool loading = true;

  /// `free`, `pro` ou `premium`. Calculé en base par `my_plan()`, où la
  /// date d'expiration fait foi : un statut resté à « active » après
  /// l'échéance ne donne aucun droit.
  String plan = 'free';

  /// Le numéro conditionne les actes engageants — publier un besoin, se
  /// déclarer ouvrier. Connu à l'avance, l'application peut le demander au
  /// bon moment plutôt qu'échouer après un formulaire rempli.
  bool hasPhone = false;

  AppSession() {
    db.auth.onAuthStateChange.listen((_) => refresh());
    refresh();
  }

  bool get isSignedIn => db.auth.currentUser != null;
  bool get needsProfile => isSignedIn && profile == null;
  bool get isWorker => profile?.isWorker ?? false;

  /// Les deux versants ne s'excluent pas : le rôle `both` rend `isWorker`
  /// et `isClient` vrais en même temps. Un ouvrier a lui aussi des besoins,
  /// et la navigation compose alors les onglets des deux parcours.
  ///
  /// Par défaut vrai quand le profil n'est pas encore chargé : mieux vaut
  /// afficher la recherche d'ouvriers une seconde de trop que priver un
  /// client de son écran principal au démarrage.
  bool get isClient => profile?.isClient ?? true;
  int get credits => wallet?.balance ?? 0;
  bool get isPro => plan == 'pro' || plan == 'premium';
  bool get isPremium => plan == 'premium';

  Future<void> refresh() async {
    final id = uid;
    if (id == null) {
      profile = null;
      worker = null;
      wallet = null;
      isAdmin = false;
      plan = 'free';
      hasPhone = false;
      loading = false;
      notifyListeners();
      return;
    }

    try {
      final rows = await Future.wait([
        db.from('profiles').select().eq('id', id).maybeSingle(),
        db.from('worker_profiles').select().eq('profile_id', id).maybeSingle(),
        db.from('credit_wallets').select().eq('profile_id', id).maybeSingle(),
      ]);

      profile = rows[0] == null
          ? null
          : Profile.fromMap(rows[0] as Map<String, dynamic>);

      // Les services lisent cette valeur sans passer par Provider.
      currentCountry = profile?.countryCode ?? AppConfig.defaultCountry;

      worker = rows[1] == null
          ? null
          : WorkerProfile.fromMap(rows[1] as Map<String, dynamic>);
      wallet = rows[2] == null
          ? null
          : Wallet.fromMap(rows[2] as Map<String, dynamic>);

      isAdmin = await AuthService.isAdmin();

      // Deux appels tolérants à l'échec : hors ligne, mieux vaut un plan
      // « free » temporaire qu'un écran de compte vide.
      try {
        plan = (await db.rpc('my_plan') as String?) ?? 'free';
      } catch (_) {
        plan = 'free';
      }
      try {
        hasPhone = (await db.rpc('has_phone') as bool?) ?? false;
      } catch (_) {
        hasPhone = false;
      }

      // La langue de l'interface suit le profil, lui-même initialisé depuis
      // le pays choisi à l'inscription.
      L.instance.setLanguage(rows[0]?['preferred_language'] as String?);
    } catch (_) {
      // Hors ligne : on garde l'état précédent plutôt que de vider l'écran.
    }

    loading = false;
    notifyListeners();
  }

  /// Change la langue et la mémorise sur le profil.
  Future<void> setLanguage(String code) async {
    L.instance.setLanguage(code);
    if (uid != null) {
      await db.from('profiles').update({'preferred_language': code}).eq('id', uid!);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    // Avant la déconnexion, tant que la session permet encore d'écrire :
    // un jeton laissé en place enverrait les messages du compte précédent
    // à quiconque se connecte ensuite sur ce téléphone. Le partage
    // d'appareil est la norme sur ce marché, pas l'exception.
    await PushService.forget();

    await db.auth.signOut();
    profile = null;
    worker = null;
    wallet = null;
    isAdmin = false;
    notifyListeners();
  }
}
