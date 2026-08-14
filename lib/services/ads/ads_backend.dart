import 'package:flutter/widgets.dart';

export 'ads_backend_stub.dart'
    if (dart.library.io) 'ads_backend_mobile.dart';

/// Issue de l'affichage d'une publicité récompensée.
///
/// Un simple booléen confondait trois situations que l'utilisateur vit
/// très différemment : aucune annonce à servir, annonce interrompue, et
/// récompense obtenue. On lui affichait « regarde jusqu'au bout » alors
/// qu'aucune vidéo ne s'était chargée — message faux et culpabilisant,
/// qui a coûté plusieurs séances de diagnostic.
class RewardedOutcome {
  /// Vrai si l'utilisateur a regardé jusqu'au bout.
  final bool earned;

  /// Renseigné quand l'annonce n'a même pas pu être chargée ou affichée.
  /// Contient le code et le message du SDK, tels quels.
  final String? loadError;

  const RewardedOutcome({required this.earned, this.loadError});

  /// L'annonce s'est bien affichée, quoi qu'il soit advenu ensuite.
  bool get displayed => loadError == null;
}

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

  /// Déclare les appareils qui recevront des publicités de test.
  ///
  /// Le seul moyen sûr de vérifier une intégration avec de vraies unités
  /// publicitaires. Sur un appareil enrôlé, Google sert des annonces de
  /// démonstration : les impressions et les clics ne comptent pas comme du
  /// trafic incorrect, ce qui est le motif de suspension le plus courant.
  ///
  /// L'identifiant d'un appareil s'obtient en lançant l'application une
  /// fois et en lisant le journal : le SDK y écrit une ligne
  /// « Use RequestConfiguration.Builder().setTestDeviceIds(...) ».
  Future<void> setTestDevices(List<String> deviceIds);

  /// Bannière prête à être insérée dans l'arbre, ou `null` si indisponible.
  Widget? banner(String adUnitId);

  Future<void> showInterstitial(String adUnitId);

  /// Publicité de retour dans l'application.
  ///
  /// Le seul format conçu pour des sessions rares et courtes, donc le seul
  /// qui monétise raisonnablement le côté client — un demandeur ouvre
  /// l'application quand il a un besoin, pas tous les jours.
  ///
  /// AdMob interdit de l'afficher au tout premier lancement et pendant un
  /// chargement : elle ne doit apparaître qu'au retour d'une application
  /// déjà utilisée, sur un écran prêt.
  Future<void> showAppOpen(String adUnitId);

  /// Décrit ce qui s'est réellement passé : chargement impossible,
  /// abandon, ou récompense obtenue.
  ///
  /// [customData] est transmis à AdMob et revient dans la callback de
  /// vérification serveur : c'est ce qui relie la récompense à la bonne ligne
  /// de `ad_impressions`.
  Future<RewardedOutcome> showRewarded({
    required String adUnitId,
    required String userId,
    required String customData,
  });

  /// Interstitiel récompensé.
  ///
  /// Seul format récompensé qu'AdMob autorise à lancer sans opt-in
  /// publicité par publicité — à condition qu'un écran d'introduction
  /// annonce la récompense et laisse la possibilité de passer. C'est cet
  /// écran, côté application, qui rend l'automatisme légal : sans lui, on
  /// retombe sur la violation « Disallowed Rewarded Implementation ».
  Future<RewardedOutcome> showRewardedInterstitial({
    required String adUnitId,
    required String userId,
    required String customData,
  });
}
