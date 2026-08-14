import 'package:package_info_plus/package_info_plus.dart';

import 'settings_service.dart';

/// Ce que l'application doit faire de la version installée.
enum UpdateStatus {
  /// À jour, ou rien de comparable : on ne dérange pas.
  none,

  /// Une version plus récente est conseillée. Refusable.
  suggested,

  /// La version installée est en dessous du plancher. Bloquant.
  required,
}

/// Comparaison de la version installée avec ce que dit `app_settings`.
///
/// Le choix de la base plutôt que de l'API Google (In-App Updates) tient à
/// un cas que l'API ne couvre pas : retirer une version cassée des mains
/// des utilisateurs sans attendre que Google constate qu'une plus récente
/// existe, et sans attendre que l'utilisateur veuille bien mettre à jour.
/// La contrepartie est qu'il faut penser à remonter le plancher — d'où sa
/// place dans l'écran de réglages, à côté des autres.
class UpdateService {
  static UpdateStatus _status = UpdateStatus.none;
  static String _installed = '';
  static String _target = '';

  static UpdateStatus get status => _status;

  /// Version installée, telle que le paquet la déclare. Vide avant le
  /// premier appel à `check()`.
  static String get installedVersion => _installed;

  /// Version à atteindre — le plancher si le blocage s'applique, la
  /// version conseillée sinon.
  static String get targetVersion => _target;

  static String get storeUrl => SettingsService.string(
      'store_url',
      'https://play.google.com/store/apps/details?id=com.ticonnect.app');

  /// L'invitation refusable ne se montre qu'une fois par ouverture de
  /// l'application. Reproposée à chaque lancement, elle deviendrait le
  /// genre de fenêtre qu'on ferme sans lire.
  static bool suggestionShown = false;

  static Future<UpdateStatus> check() async {
    try {
      if (!SettingsService.isLoaded) await SettingsService.load();

      final info = await PackageInfo.fromPlatform();
      _installed = info.version;

      final min = SettingsService.string('min_supported_version', '0.0.0');
      final recommended = SettingsService.string('recommended_version', '0.0.0');

      if (compare(_installed, min) < 0) {
        _target = min;
        _status = UpdateStatus.required;
      } else if (compare(_installed, recommended) < 0) {
        _target = recommended;
        _status = UpdateStatus.suggested;
      } else {
        _status = UpdateStatus.none;
      }
    } catch (_) {
      // Hors ligne, réglage illisible, version au format inattendu : on ne
      // bloque pas. Une erreur de lecture ne doit jamais fermer
      // l'application à quelqu'un qui vient de l'installer.
      _status = UpdateStatus.none;
    }
    return _status;
  }

  /// Compare deux versions « 2.0.6 ». Rend un nombre négatif si `a` est
  /// antérieure à `b`, zéro si elles sont équivalentes.
  ///
  /// Tolérante par construction : un segment illisible vaut zéro, et un
  /// numéro de build (`2.0.6+8`) est ignoré — c'est la version visible qui
  /// fait foi, celle que l'utilisateur lit sur la fiche du store.
  static int compare(String a, String b) {
    final sa = _segments(a);
    final sb = _segments(b);
    final n = sa.length > sb.length ? sa.length : sb.length;
    for (var i = 0; i < n; i++) {
      final va = i < sa.length ? sa[i] : 0;
      final vb = i < sb.length ? sb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  static List<int> _segments(String v) {
    final visible = v.split('+').first.trim();
    return [
      for (final part in visible.split('.')) int.tryParse(part.trim()) ?? 0,
    ];
  }
}
