import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

import '../core/config.dart';
import '../core/supabase.dart';
import '../models/models.dart';
import 'ads/ads_backend.dart';
import 'settings_service.dart';

/// Service publicitaire.
///
/// Trois principes tenus par ce fichier :
///
/// 1. **Conformité AdMob.** Le format `rewarded` n'est jamais lancé sans un
///    geste explicite de l'utilisateur, à chaque fois. Forcer son visionnage
///    déclenche la violation « Disallowed Rewarded Implementation » et peut
///    faire suspendre le compte.
///
///    Pour un affichage quasi systématique, deux voies légales existent et
///    sont les seules employées ici :
///      · `interstitial` — imposable, sans skip, entre deux écrans ;
///      · `rewarded_interstitial` — automatique et sans opt-in, à condition
///        d'un écran d'introduction annonçant la récompense et proposant de
///        passer (voir `AdIntro` dans widgets/ad_intro.dart).
///
/// 2. **Configuration côté base.** La fréquence, les plafonds et les
///    identifiants d'unités viennent de la table `ad_placements`. On ajuste
///    l'agressivité publicitaire sans republier sur le Play Store.
///
/// 3. **Récompense vérifiée côté serveur.** Un crédit n'est accordé que si
///    AdMob a confirmé le visionnage via sa callback SSV. Le client ne peut
///    pas s'auto-créditer : la politique RLS lui interdit d'écrire
///    `ssv_verified` ou `reward_credits`.
///
/// Le SDK AdMob n'existe que sur Android et iOS. Il est isolé derrière
/// [AdsBackend], résolu à la compilation : sur le web, aucune ligne de
/// `google_mobile_ads` n'est compilée et le service se contente de ne rien
/// afficher.
class AdsService {
  static final AdsBackend _backend = createAdsBackend();
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
    'app_open': {
      'android': 'ca-app-pub-3940256099942544/9257395921',
      'ios': 'ca-app-pub-3940256099942544/5575463023',
    },
    'rewarded_interstitial': {
      'android': 'ca-app-pub-3940256099942544/5354046379',
      'ios': 'ca-app-pub-3940256099942544/6978759866',
    },
  };

  static bool get supported => _backend.supported;

  /// Dernier plein écran affiché, tous emplacements confondus.
  ///
  /// Les plafonds par emplacement ne suffisent pas : trois emplacements
  /// distincts peuvent s'enchaîner en dix secondes et donner à
  /// l'utilisateur le sentiment d'une publicité à chaque geste — ce
  /// qu'AdMob sanctionne autant que les utilisateurs.
  static DateTime? _lastFullScreen;

  /// Cause du dernier échec d'affichage, à l'usage de l'appelant.
  ///
  /// `showRewarded` rend `null` dans trois cas très différents : annonce
  /// introuvable, abandon en cours de vidéo, vérification serveur non
  /// reçue. L'appelant n'avait aucun moyen de les distinguer et affichait
  /// « regarde jusqu'au bout » même quand aucune vidéo ne s'était chargée.
  static String? lastLoadError;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Les réglages d'abord, car la liste des appareils de test en vient —
    // et cette liste doit être posée AVANT `initialize()`. Le SDK fige sa
    // configuration de requête au démarrage : déclarée après, elle ne
    // s'applique qu'aux requêtes suivantes, et l'appareil reçoit de
    // vraies annonces en attendant. C'était l'ordre précédent, et il
    // faisait qu'un appareil pourtant enregistré ne voyait rien.
    await SettingsService.load();
    await _backend.setTestDevices(
      SettingsService.strings(SettingKeys.adTestDeviceIds),
    );

    await _backend.initialize();
    await loadPlacements();
  }

  /// Recharge la configuration depuis la base.
  static Future<void> loadPlacements() async {
    try {
      final rows = await db.from('ad_placements').select();
      _placements.clear();
      for (final r in rows) {
        final p = AdPlacement.fromMap(r);
        _placements[p.key] = p;
      }
    } catch (_) {
      // Hors ligne : on reste sans publicité plutôt que d'en afficher au hasard.
    }
  }

  static AdPlacement? placement(String key) => _placements[key];

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String? _unitFor(AdPlacement p) {
    if (!_backend.supported) return null;
    if (AppConfig.adsTestMode) {
      final byPlatform = _testUnits[p.format];
      if (byPlatform == null) return null;
      return _isIos ? byPlatform['ios'] : byPlatform['android'];
    }
    return _isIos ? p.adUnitIos : p.adUnitAndroid;
  }

  static bool _isFullScreen(String format) =>
      format == 'interstitial' ||
      format == 'rewarded' ||
      format == 'rewarded_interstitial' ||
      format == 'app_open';

  /// Un emplacement est jouable si : activé, délai minimum écoulé depuis la
  /// dernière fois, plafond journalier non atteint, et — pour les formats
  /// plein écran — délai global respecté depuis n'importe quelle autre
  /// publicité plein écran.
  static Future<bool> canShow(String key) async {
    if (!_backend.supported) return false;
    final p = _placements[key];
    if (p == null || !p.isEnabled) return false;
    if (_unitFor(p) == null) return false;

    final last = _lastShown[key];
    if (last != null &&
        DateTime.now().difference(last).inSeconds < p.minSecondsBetween) {
      return false;
    }

    if (_isFullScreen(p.format) && _lastFullScreen != null) {
      final floor = SettingsService.integer(
          SettingKeys.adMinSecondsBetweenAny, 45);
      if (DateTime.now().difference(_lastFullScreen!).inSeconds < floor) {
        return false;
      }
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

  /// Pourquoi un emplacement n'est pas jouable, en français.
  ///
  /// `canShow` rend un booléen, ce qui suffit au code mais pas à
  /// l'utilisateur : « aucune vidéo disponible » alors que le plafond
  /// journalier est simplement atteint envoie chercher une panne qui
  /// n'existe pas. Rend `null` quand l'emplacement est jouable.
  static Future<String?> blockReason(String key) async {
    if (!_backend.supported) {
      return 'Les publicités ne sont pas disponibles sur cette plateforme.';
    }
    final p = _placements[key];
    if (p == null) return 'Emplacement inconnu.';
    if (!p.isEnabled) return 'Emplacement désactivé par l\'administrateur.';
    if (_unitFor(p) == null) return 'Aucune unité publicitaire configurée.';

    final last = _lastShown[key];
    if (last != null) {
      final reste = p.minSecondsBetween - DateTime.now().difference(last).inSeconds;
      if (reste > 0) return 'Patiente encore $reste secondes.';
    }

    if (_isFullScreen(p.format) && _lastFullScreen != null) {
      final floor =
          SettingsService.integer(SettingKeys.adMinSecondsBetweenAny, 45);
      final reste = floor - DateTime.now().difference(_lastFullScreen!).inSeconds;
      if (reste > 0) return 'Patiente encore $reste secondes.';
    }

    if (p.dailyCapPerUser != null && uid != null) {
      final since = DateTime.now().subtract(const Duration(hours: 24));
      final rows = await db
          .from('ad_impressions')
          .select('id')
          .eq('profile_id', uid!)
          .eq('placement_key', key)
          .gte('created_at', since.toIso8601String());
      if (rows.length >= p.dailyCapPerUser!) {
        return 'Limite atteinte : ${p.dailyCapPerUser} vidéos par 24 heures. '
            'Reviens demain.';
      }
    }
    return null;
  }

  // ------------------------------------------------------------- Bannière
  /// Widget de bannière, ou `null` s'il n'y a rien à afficher.
  static Widget? bannerWidget(String key) {
    final p = _placements[key];
    if (p == null || !p.isEnabled) return null;
    final unit = _unitFor(p);
    if (unit == null) return null;
    _lastShown[key] = DateTime.now();
    return _backend.banner(unit);
  }

  // --------------------------------------------------------- Interstitiel
  /// À n'appeler qu'entre deux écrans, jamais pendant une action de
  /// l'utilisateur ni au lancement de l'application.
  static Future<void> maybeShowInterstitial(String key) async {
    if (!await canShow(key)) return;
    final p = _placements[key]!;
    final unit = _unitFor(p)!;
    _lastShown[key] = DateTime.now();
    _lastFullScreen = DateTime.now();
    unawaited(_log(key, p.format, unit));
    await _backend.showInterstitial(unit);
  }

  // ------------------------------------------------------ Retour dans l'app
  /// Publicité de retour, à n'appeler que depuis le cycle de vie.
  ///
  /// C'est le seul format qui monétise correctement un utilisateur qui
  /// ouvre l'application rarement — le profil exact du demandeur, qui
  /// vient quand il a un besoin et repart.
  ///
  /// [firstLaunch] doit valoir `true` au tout premier passage au premier
  /// plan de la session : AdMob interdit d'afficher ce format au
  /// démarrage, et le sanctionne. Le plafond journalier et le délai
  /// minimum de `ad_placements` s'appliquent en plus, comme partout.
  static Future<void> maybeShowAppOpen({bool firstLaunch = false}) async {
    if (firstLaunch) return;
    if (!await canShow(AdKeys.appOpen)) return;
    final p = _placements[AdKeys.appOpen]!;
    final unit = _unitFor(p)!;
    _lastShown[AdKeys.appOpen] = DateTime.now();
    _lastFullScreen = DateTime.now();
    unawaited(_log(AdKeys.appOpen, p.format, unit));
    await _backend.showAppOpen(unit);
  }

  // --------------------------------------------- Interstitiel récompensé
  /// Affiche un interstitiel récompensé et rend l'identifiant d'impression
  /// une fois la récompense validée côté serveur, ou `null`.
  ///
  /// L'appelant DOIT avoir présenté l'écran d'introduction au préalable
  /// (`AdIntro.ask`) : c'est cet écran, avec son bouton pour passer, qui
  /// rend le format automatique conforme. Le lancer directement remettrait
  /// le compte AdMob en infraction.
  ///
  /// Rend `null` sans bruit quand l'inventaire est vide — un ouvrier ne
  /// doit jamais être empêché de candidater parce qu'aucune publicité
  /// n'était disponible.
  static Future<String?> showRewardedInterstitial(String key) async {
    if (!await canShow(key)) return null;
    final p = _placements[key]!;
    final unit = _unitFor(p)!;
    final me = uid;
    if (me == null) return null;

    final impressionId = await _openImpression(key, p.format, adUnitId: unit);
    if (impressionId == null) return null;

    _lastShown[key] = DateTime.now();
    _lastFullScreen = DateTime.now();

    final issue = await _backend.showRewardedInterstitial(
      adUnitId: unit,
      userId: me,
      customData: impressionId,
    );
    if (issue.loadError != null) {
      lastLoadError = issue.loadError;
      unawaited(_noteLoadError(impressionId, issue.loadError!));
      return null;
    }
    lastLoadError = null;
    if (!issue.earned) return null;

    // La vidéo est allée à son terme : à partir d'ici, et seulement ici,
    // AdMob s'engage à envoyer une callback de vérification. C'est donc le
    // seul dénominateur honnête pour juger de la santé de `admob-ssv`.
    unawaited(_noteEarned(impressionId));

    // Pas de récompense en crédits sur cet emplacement : inutile
    // d'immobiliser l'utilisateur douze secondes en attendant la callback.
    if (p.rewardCredits == 0) return impressionId;

    final verified = await _waitForVerification(impressionId);
    return verified ? impressionId : null;
  }

  /// Ouvre une ligne d'impression avant l'affichage.
  ///
  /// La RLS impose `ssv_verified = false` et `reward_credits = 0` : c'est la
  /// callback serveur d'AdMob qui validera, jamais le téléphone.
  static Future<String?> _openImpression(
    String key,
    String format, {
    String? adUnitId,
  }) async {
    final me = uid;
    if (me == null) return null;
    try {
      final row = await db
          .from('ad_impressions')
          .insert({
            'profile_id': me,
            'placement_key': key,
            'format': format,
            'ssv_verified': false,
            'reward_credits': 0,
            'country_code': AppConfig.defaultCountry,
            // Trace du mode réel : une unité ca-app-pub-3940256099942544
            // signale les publicités de démonstration, pour lesquelles
            // aucune vérification serveur ne peut aboutir.
            'ad_unit_id': adUnitId,
          })
          .select('id')
          .single();
      return row['id'] as String;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------- Pub récompensée
  /// Affiche une vidéo récompensée et rend l'identifiant de l'impression
  /// **une fois qu'AdMob l'a validée côté serveur**.
  ///
  /// Rend `null` si l'utilisateur abandonne, si la publicité ne charge pas,
  /// ou si la vérification serveur n'arrive pas à temps.
  ///
  /// Ne doit être appelée qu'après un geste explicite de l'utilisateur.
  static Future<String?> showRewarded(String key) async {
    if (!await canShow(key)) return null;
    final p = _placements[key]!;
    final unit = _unitFor(p)!;
    final me = uid;
    if (me == null) return null;

    // 1. On journalise l'impression AVANT l'affichage.
    final impressionId = await _openImpression(key, p.format, adUnitId: unit);
    if (impressionId == null) return null;

    _lastShown[key] = DateTime.now();
    _lastFullScreen = DateTime.now();
    final issue = await _backend.showRewarded(
      adUnitId: unit,
      userId: me,
      customData: impressionId,
    );

    // La cause d'échec est consignée sur l'impression : c'est elle qui
    // distingue « aucun annonceur disponible » d'« abandon en cours de
    // route », deux situations que l'utilisateur vit différemment et
    // qu'un simple booléen confondait.
    if (issue.loadError != null) {
      lastLoadError = issue.loadError;
      unawaited(_noteLoadError(impressionId, issue.loadError!));
      return null;
    }
    lastLoadError = null;
    if (!issue.earned) return null;

    // La vidéo est allée à son terme : à partir d'ici, et seulement ici,
    // AdMob s'engage à envoyer une callback de vérification. C'est donc le
    // seul dénominateur honnête pour juger de la santé de `admob-ssv`.
    unawaited(_noteEarned(impressionId));

    // 2. La callback SSV d'AdMob arrive de façon asynchrone.
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

  /// Consigne l'échec sur l'impression déjà ouverte.
  ///
  /// Silencieux en cas d'erreur : un diagnostic qui casse le parcours
  /// serait pire que l'absence de diagnostic.
  static Future<void> _noteLoadError(String impressionId, String message) async {
    try {
      await db
          .from('ad_impressions')
          .update({'load_error': message}).eq('id', impressionId);
    } catch (_) {}
  }

  /// Marque la récompense comme gagnée, côté application.
  ///
  /// Sans ce repère, une vidéo abandonnée à mi-parcours et une callback de
  /// vérification perdue produisent exactement la même ligne : chargée,
  /// non vérifiée. Le tableau de bord confondait les deux et accusait
  /// l'Edge Function d'une désaffection des utilisateurs.
  ///
  /// N'accorde évidemment aucun droit : `grant_boost()` exige
  /// `ssv_verified`, que seul le serveur peut écrire. Ce champ ne sert
  /// qu'à la mesure.
  static Future<void> _noteEarned(String impressionId) async {
    try {
      await db.from('ad_impressions').update(
          {'earned_at': DateTime.now().toIso8601String()}).eq('id', impressionId);
    } catch (_) {}
  }

  static Future<void> _log(String key, String format, [String? adUnitId]) async {
    if (uid == null) return;
    try {
      await db.from('ad_impressions').insert({
        'profile_id': uid,
        'placement_key': key,
        'format': format,
        'ssv_verified': false,
        'reward_credits': 0,
        'country_code': AppConfig.defaultCountry,
        'ad_unit_id': adUnitId,
      });
    } catch (_) {}
  }
}

/// Clés des emplacements, alignées sur la table `ad_placements`.
class AdKeys {
  // Opt-in explicite : conformes tels quels, déclenchés par un bouton.
  static const unlockRewarded = 'unlock_contact_rewarded';
  static const boostRewarded = 'boost_profile_rewarded';

  static const jobListBanner = 'job_list_banner';

  /// Client, bas de la fiche d'un ouvrier. Le seul écran où un demandeur
  /// s'attarde vraiment.
  static const workerDetailBanner = 'worker_detail_banner';
  static const profileInterstitial = 'profile_view_interstitial';
  static const appOpen = 'app_open';

  /// Ouvrier, avant l'envoi d'une candidature. Le format récompensé
  /// automatique — précédé de son écran d'introduction.
  static const applyRewardedInterstitial = 'apply_rewarded_interstitial';

  /// Interstitiels imposés à la candidature. Un seul des deux est actif,
  /// selon `worker_apply_ad_placement`. Sans écran d'introduction ni
  /// sortie de notre fait : le format l'autorise, contrairement au
  /// récompensé.
  static const applyBeforeInterstitial = 'apply_before_interstitial';
  static const applyAfterInterstitial  = 'apply_after_interstitial';

  /// Client, avant la saisie du besoin. Désactivé par défaut.
  static const jobPostBefore = 'job_post_before_interstitial';

  /// Client, après validation du besoin. Actif par défaut.
  static const jobPostAfter = 'job_post_after_interstitial';

  /// Variante automatique du déverrouillage, pour le jour où
  /// `unlock_cost` repassera au-dessus de zéro.
  static const unlockRewardedInterstitial = 'unlock_rewarded_interstitial';
}
