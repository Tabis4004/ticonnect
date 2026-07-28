import 'package:flutter/widgets.dart';

import 'ads_backend.dart';

/// Implémentation web : aucune publicité.
///
/// AdMob n'existe pas sur navigateur. Plutôt que de faire échouer les appels,
/// on répond poliment que rien n'est disponible — le reste de l'application
/// fonctionne à l'identique.
class WebAdsBackend implements AdsBackend {
  @override
  bool get supported => false;

  @override
  Future<void> initialize() async {}

  @override
  Widget? banner(String adUnitId) => null;

  @override
  Future<void> showInterstitial(String adUnitId) async {}

  @override
  Future<bool> showRewarded({
    required String adUnitId,
    required String userId,
    required String customData,
  }) async =>
      false;
}

AdsBackend createAdsBackend() => WebAdsBackend();
