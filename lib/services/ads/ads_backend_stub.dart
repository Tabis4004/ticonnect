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
  Future<void> setTestDevices(List<String> deviceIds) async {}

  @override
  Widget? banner(String adUnitId) => null;

  @override
  Future<void> showInterstitial(String adUnitId) async {}

  @override
  Future<void> showAppOpen(String adUnitId) async {}

  @override
  Future<RewardedOutcome> showRewarded({
    required String adUnitId,
    required String userId,
    required String customData,
  }) async =>
      const RewardedOutcome(
          earned: false, loadError: 'Publicités indisponibles sur le web.');

  @override
  Future<RewardedOutcome> showRewardedInterstitial({
    required String adUnitId,
    required String userId,
    required String customData,
  }) async =>
      const RewardedOutcome(
          earned: false, loadError: 'Publicités indisponibles sur le web.');
}

AdsBackend createAdsBackend() => WebAdsBackend();
