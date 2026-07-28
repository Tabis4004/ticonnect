import 'package:flutter/widgets.dart';

export 'ads_backend_stub.dart'
    if (dart.library.io) 'ads_backend_mobile.dart';

/// Contrat commun aux deux implémentations publicitaires.
///
/// `google_mobile_ads` ne supporte qu'Android et iOS : sur le web, le simple
/// fait d'importer le paquet fait échouer la compilation. D'où cette
/// interface, résolue à la compilation via `dart.library.io` — l'implémentation
/// réelle sur mobile, une coquille vide sur navigateur.
abstract class AdsBackend {
  /// `false` sur le web : aucun appel publicitaire ne doit être tenté.
  bool get supported;

  Future<void> initialize();

  /// Bannière prête à être insérée dans l'arbre, ou `null` si indisponible.
  Widget? banner(String adUnitId);

  Future<void> showInterstitial(String adUnitId);

  /// Rend `true` si l'utilisateur a regardé la vidéo jusqu'au bout.
  ///
  /// [customData] est transmis à AdMob et revient dans la callback de
  /// vérification serveur : c'est ce qui relie la récompense à la bonne ligne
  /// de `ad_impressions`.
  Future<bool> showRewarded({
    required String adUnitId,
    required String userId,
    required String customData,
  });
}
