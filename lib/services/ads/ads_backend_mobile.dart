import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_backend.dart';

/// Implémentation Android et iOS, adossée au SDK Google Mobile Ads.
class MobileAdsBackend implements AdsBackend {
  @override
  bool get supported => true;

  @override
  Future<void> initialize() => MobileAds.instance.initialize();

  @override
  Future<void> setTestDevices(List<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: deviceIds),
    );
  }

  @override
  Widget? banner(String adUnitId) => _BannerHost(adUnitId: adUnitId);

  @override
  Future<void> showInterstitial(String adUnitId) {
    final done = Completer<void>();
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!done.isCompleted) done.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!done.isCompleted) done.complete();
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (_) {
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    return done.future;
  }

  @override
  Future<void> showAppOpen(String adUnitId) {
    final done = Completer<void>();
    AppOpenAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!done.isCompleted) done.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!done.isCompleted) done.complete();
            },
          );
          ad.show();
        },
        // Un échec de chargement est silencieux : l'utilisateur revient
        // dans l'application, il ne doit rien voir d'anormal.
        onAdFailedToLoad: (_) {
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    return done.future;
  }

  @override
  Future<RewardedOutcome> showRewarded({
    required String adUnitId,
    required String userId,
    required String customData,
  }) {
    final done = Completer<RewardedOutcome>();
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // L'identifiant d'impression part avec la publicité et nous revient
          // dans la callback de vérification serveur d'AdMob.
          ad.setServerSideOptions(
            ServerSideVerificationOptions(userId: userId, customData: customData),
          );

          var earned = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!done.isCompleted) {
                done.complete(RewardedOutcome(earned: earned));
              }
            },
            onAdFailedToShowFullScreenContent: (a, e) {
              a.dispose();
              if (!done.isCompleted) {
                done.complete(RewardedOutcome(
                    earned: false, loadError: 'Affichage : ${e.code} ${e.message}'));
              }
            },
          );
          ad.show(onUserEarnedReward: (_, __) => earned = true);
        },
        // Le code et le message du SDK sont conservés tels quels : le
        // code 3 signale « no fill », c'est-à-dire aucun annonceur
        // disponible, ce qui n'a rien à voir avec un abandon.
        onAdFailedToLoad: (e) {
          if (!done.isCompleted) {
            done.complete(RewardedOutcome(
                earned: false, loadError: 'Chargement : ${e.code} ${e.message}'));
          }
        },
      ),
    );
    return done.future;
  }

  @override
  Future<RewardedOutcome> showRewardedInterstitial({
    required String adUnitId,
    required String userId,
    required String customData,
  }) {
    final done = Completer<RewardedOutcome>();
    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.setServerSideOptions(
            ServerSideVerificationOptions(userId: userId, customData: customData),
          );

          var earned = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!done.isCompleted) {
                done.complete(RewardedOutcome(earned: earned));
              }
            },
            onAdFailedToShowFullScreenContent: (a, e) {
              a.dispose();
              if (!done.isCompleted) {
                done.complete(RewardedOutcome(
                    earned: false, loadError: 'Affichage : ${e.code} ${e.message}'));
              }
            },
          );
          ad.show(onUserEarnedReward: (_, __) => earned = true);
        },
        onAdFailedToLoad: (e) {
          // Inventaire vide : on n'a pas le droit de bloquer l'utilisateur
          // pour autant. L'appelant poursuit son action, mais la cause est
          // désormais consignée au lieu d'être confondue avec un abandon.
          if (!done.isCompleted) {
            done.complete(RewardedOutcome(
                earned: false, loadError: 'Chargement : ${e.code} ${e.message}'));
          }
        },
      ),
    );
    return done.future;
  }
}

AdsBackend createAdsBackend() => MobileAdsBackend();

/// Bannière qui n'occupe de la place qu'une fois réellement chargée.
///
/// Sur ce marché l'inventaire publicitaire est souvent vide : réserver
/// l'espace à l'avance laisserait un bandeau blanc en bas de l'écran.
class _BannerHost extends StatefulWidget {
  final String adUnitId;
  const _BannerHost({required this.adUnitId});

  @override
  State<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<_BannerHost> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
