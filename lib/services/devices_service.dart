import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/supabase.dart';

/// Enregistrement des appareils pour les notifications push.
///
/// La table `devices` attend des jetons FCM depuis le premier jour. Ce
/// service en est la moitié applicative : il sait enregistrer, rafraîchir
/// et retirer un jeton, quelle qu'en soit la provenance.
///
/// **Ce qui manque encore, et pourquoi ce n'est pas ici.** Obtenir le jeton
/// suppose `firebase_messaging`, qui suppose lui-même un fichier
/// `google-services.json` généré depuis une console Firebase rattachée à ce
/// projet. Ajouter la dépendance sans ce fichier fait échouer la
/// compilation Gradle — l'application ne se lancerait plus du tout. La
/// dépendance est donc laissée de côté volontairement ; voir
/// `docs/push_setup.md` pour les trois étapes à faire une fois la console
/// Firebase créée.
///
/// Sans push, un ouvrier ignore qu'une mission de son métier vient d'être
/// publiée. C'est le cœur de la proposition de valeur, et c'est le
/// chantier à traiter en premier après la mise en service.
class DevicesService {
  /// Enregistre ou met à jour le jeton de cet appareil.
  ///
  /// `fcm_token` porte une contrainte d'unicité : un même téléphone
  /// réutilisé par deux comptes doit basculer, pas dupliquer — sinon
  /// l'ancien propriétaire continue de recevoir les notifications du
  /// nouveau.
  static Future<void> register(String token) async {
    final me = uid;
    if (me == null || token.isEmpty) return;

    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Sans importance : la version d'app n'est qu'une aide au diagnostic.
    }

    try {
      await db.from('devices').upsert({
        'profile_id': me,
        'fcm_token': token,
        'platform': _platform,
        'app_version': version,
        'last_active_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (_) {
      // Hors ligne : le jeton sera réenregistré au prochain démarrage.
    }
  }

  /// À appeler à la déconnexion.
  ///
  /// Un jeton laissé en place enverrait les notifications du compte
  /// précédent à quiconque se connecte ensuite sur ce téléphone — un
  /// partage d'appareil est la norme, pas l'exception, sur ce marché.
  static Future<void> unregister(String token) async {
    if (token.isEmpty) return;
    try {
      await db.from('devices').delete().eq('fcm_token', token);
    } catch (_) {}
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'android';
  }
}
