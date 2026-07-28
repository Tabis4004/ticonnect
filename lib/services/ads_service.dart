import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/config.dart';
import '../core/supabase.dart';
import '../models/models.dart';

/// Service publicitaire.
///
/// Trois principes tenus par ce fichier :
///
/// 1. **Conformité AdMob.** Les formats « rewarded » ne sont jamais lancés
///    sans un geste explicite de l'utilisateur, à chaque fois. Forcer le
///    visionnage déclenche la violation « Disallowed Rewarded Implementation »
///    et peut faire suspendre le compte AdMob.
///
/// 2. **Configuration côté base.** La fréquence, les plafonds et les
///    identifiants d'unités viennent de la table `ad_placements`. On ajuste
///    l'agressivité publicitaire sans republier sur le Play Store.
///
/// 3. **Récompense vérifiée côté serveur.** Un crédit n'est accordé que si
///    AdMob a confirmé le visionnage via sa callback SSV. Le client ne peut
///    pas s'auto-créditer : la politique RLS lui interdit d'écrire
///    `ssv_verified` ou `reward_credits`.
class AdsService {
  static final Map<String, AdPlacement> _placements = {};
  static final Map<String, DateTime> _lastShown = {};
  static bool _initialized = false;

  /// Identifiants de TEST officiels Google. Ne jamais publier avec ceux-ci,
  /// et ne jamais tester avec les vrais : cliquer sur ses propres publicités
  /// fait suspendre le compte AdMob.
  static const _testUnits = {
    'banner': {
      'android': 'ca-app-pub-3940256099942544/6300978111',
      'ios': 'ca-app-pub-3940256099942544/2934735716',
    },
    'interstitial': {
      'android': 'ca-app-pub-3940256099942544/1033173712',
      'ios': 'ca-app-pub-3940256099942544/4411468910',
    },
    'rewarded': {
      'android': 'ca-app-pub-3940256099942544/5224354917',
      'ios': 'ca-app-pub-3940256099942544/1712485313',
    },
  };

  static Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    await loadPlacements();
  }

  /// Recharge la configuration depuis la base.
  static Future<void> loadPlacements() async {
    try {
      final rows = await db.from('ad_placements').select();
      _placements.clear();
      for (final r in rows) {
        final p = AdPlacement.fromMap(r as Map<String, dynamic>);
        _placements[p.key] = p;
      }
    } catch (_) {
      // Hors ligne : on reste sans publicité plutôt que d'en afficher au hasard.
    }
  }

  static AdPlacement? placement(String key) => _placements[key];

  static String? _unitFor(AdPlacement p) {
    if (AppConfig.adsTestMode) {
      final byPlatform = _testUnits[p.format];
      if (byPlatform == null) return null;
      return Platform.isIOS ? byPlatform['ios'] : byPlatform['android'];
    }
    return Platform.isIOS ? p.adUnitIos : p.adUnitAndroid;
  }

  /// Un emplacement est jouable si : activé, délai minimum écoulé depuis la
  /// dernière fois, et plafond journalier non atteint.
  static Future<bool> canShow(String key) async {
    final p = _placements[key];
    if (p == null || !p.isEnabled) return false;
    if (_unitFor(p) == null) return false;

    final last = _lastShown[key];
    if (last != null &&
        DateTime.now().difference(last).inSeconds < p.minSecondsBetween) {
      return false;
    }

    if (p.dailyCapPerUser != null && uid != null) {
      final since = DateTime.now().subtract(const Duration(hours: 24));
      final rows = await db
          .from('ad_impressions')
          .select('id')
          .eq('profile_id', uid!)
          .eq('placement_key', key)
          .gte('created_at', since.toIso8601String());
      if (rows.length >= p.dailyCapPerUser!) return false;
    }
    return true;
  }

  // ------------------------------------------------------------- Bannière
  static BannerAd? createBanner(String key, {AdSize size = AdSize.banner}) {
    final p = _placements[key];
    if (p == null || !p.isEnabled) return null;
    final unit = _unitFor(p);
    if (unit == null) return null;

    return BannerAd(
      adUnitId: unit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _lastShown[key] = DateTime.now(),
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  // --------------------------------------------------------- Interstitiel
  /// À n'appeler qu'entre deux écrans, jamais pendant une action de
  /// l'utilisateur ni au lancement de l'application.
  static Future<void> maybeShowInterstitial(String key) async {
    if (!await canShow(key)) return;
    final p = _placements[key]!;
    final unit = _unitFor(p)!;

    final completer = Completer<void>();
    InterstitialAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _lastShown[key] = DateTime.now();
          _log(key, p.format);
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!completer.isCompleted) completer.complete();
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    return completer.future;
  }

  // ----------------------------------------------------- Pub récompensée
  /// Affiche une vidéo récompensée et rend l'identifiant de l'impression
  /// **une fois qu'AdMob l'a validée côté serveur**.
  ///
  /// Rend `null` si l'utilisateur abandonne, si la publicité ne charge pas,
  /// ou si la vérification serveur n'arrive pas à temps.
  ///
  /// Cette méthode ne doit être appelée qu'après un geste explicite de
  /// l'utilisateur (bouton « Regarder une vidéo »).
  static Future<String?> showRewarded(String key) async {
    if (!await canShow(key)) return null;
    final p = _placements[key]!;
    final unit = _unitFor(p)!;
    final me = uid;
    if (me == null) return null;

    // 1. On journalise l'impression AVANT l'affichage. La RLS impose
    //    ssv_verified = false et reward_credits = 0 : c'est la callback
    //    serveur d'AdMob qui validera, jamais le téléphone.
    final row = await db
        .from('ad_impressions')
        .insert({
          'profile_id': me,
          'placement_key': key,
          'format': p.format,
          'ssv_verified': false,
          'reward_credits': 0,
          'country_code': AppConfig.defaultCountry,
        })
        .select('id')
        .single();
    final impressionId = row['id'] as String;

    final completer = Completer<bool>();
    RewardedAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // 2. On transmet l'identifiant d'impression à AdMob. Il nous
          //    reviendra dans la callback SSV et permettra de relier la
          //    récompense à la bonne ligne.
          ad.setServerSideOptions(
            ServerSideVerificationOptions(userId: me, customData: impressionId),
          );

          var earned = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (!completer.isCompleted) completer.complete(earned);
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );

          _lastShown[key] = DateTime.now();
          ad.show(onUserEarnedReward: (_, __) => earned = true);
        },
        onAdFailedToLoad: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    final earned = await completer.future;
    if (!earned) return null;

    // 3. La callback SSV d'AdMob arrive de façon asynchrone. On attend
    //    qu'elle ait marqué la ligne comme vérifiée.
    final verified = await _waitForVerification(impressionId);
    return verified ? impressionId : null;
  }

  /// Interroge la base jusqu'à ce que la récompense soit validée.
  ///
  /// Tant que l'Edge Function `admob-ssv` n'est pas déployée, cette attente
  /// expire toujours — c'est volontaire : mieux vaut ne rien accorder que
  /// d'accorder un crédit non vérifiable.
  static Future<bool> _waitForVerification(
    String impressionId, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 900));
      try {
        final row = await db
            .from('ad_impressions')
            .select('ssv_verified')
            .eq('id', impressionId)
            .maybeSingle();
        if (row != null && row['ssv_verified'] == true) return true;
      } catch (_) {
        // On retente jusqu'à l'échéance.
      }
    }
    return false;
  }

  static Future<void> _log(String key, String format) async {
    if (uid == null) return;
    try {
      await db.from('ad_impressions').insert({
        'profile_id': uid,
        'placement_key': key,
        'format': format,
        'ssv_verified': false,
        'reward_credits': 0,
        'country_code': AppConfig.defaultCountry,
      });
    } catch (_) {}
  }
}

/// Clés des emplacements, alignées sur la table `ad_placements`.
class AdKeys {
  static const unlockRewarded = 'unlock_contact_rewarded';
  static const boostRewarded = 'boost_profile_rewarded';
  static const jobListBanner = 'job_list_banner';
  static const profileInterstitial = 'profile_view_interstitial';
  static const appOpen = 'app_open';
}
