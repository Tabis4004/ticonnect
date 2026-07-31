import 'dart:convert';

import '../core/supabase.dart';

/// Réglages applicatifs lus dans `app_settings`.
///
/// Même principe que `ad_placements` : ce qui doit s'arbitrer après le
/// lancement, sur des chiffres réels, ne doit pas exiger une republication
/// sur le Play Store. Basculer la publicité client d'« avant la saisie du
/// besoin » à « après validation » se fait alors depuis le tableau de bord
/// admin, en une seconde, et se réverte aussi vite.
class SettingsService {
  static final Map<String, dynamic> _cache = {};
  static bool _loaded = false;

  /// Chargé une fois au démarrage, en même temps que les emplacements
  /// publicitaires. Un échec n'est pas bloquant : chaque accesseur porte
  /// sa propre valeur de repli.
  static Future<void> load() async {
    try {
      final rows = await db.from('app_settings').select('key, value');
      _cache.clear();
      for (final r in rows) {
        _cache[r['key'] as String] = r['value'];
      }
      _loaded = true;
    } catch (_) {
      // Hors ligne : on garde ce qu'on avait, ou les valeurs par défaut.
    }
  }

  static bool get isLoaded => _loaded;

  static dynamic _raw(String key) {
    final v = _cache[key];
    // Selon le pilote, une valeur jsonb peut revenir décodée ou en texte.
    if (v is String) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return v;
      }
    }
    return v;
  }

  static String string(String key, String fallback) {
    final v = _raw(key);
    return v is String ? v : fallback;
  }

  static bool boolean(String key, bool fallback) {
    final v = _raw(key);
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  static int integer(String key, int fallback) {
    final v = _raw(key);
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  static double decimal(String key, double fallback) {
    final v = _raw(key);
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  /// Écriture réservée aux administrateurs — la politique RLS
  /// `app_settings_admin_write` s'en assure côté base, l'appel échouera
  /// pour tout autre compte.
  static Future<void> set(String key, dynamic value) async {
    await db.from('app_settings').update({
      'value': value,
      'updated_by': uid,
    }).eq('key', key);
    _cache[key] = value;
  }
}

/// Clés utilisées par l'application, alignées sur le seed de la migration 12.
class SettingKeys {
  /// `before` · `after` · `off` — où afficher l'interstitiel côté client.
  static const clientJobAdPlacement = 'client_job_ad_placement';

  /// Publicité récompensée automatique avant l'envoi d'une candidature.
  static const workerApplyAdEnabled = 'worker_apply_ad_enabled';

  /// Au plus un résultat sponsorisé toutes les N positions.
  static const sponsoredSlotRatio = 'sponsored_slot_ratio';

  /// Note minimale pour occuper une position sponsorisée.
  static const sponsoredMinRating = 'sponsored_min_rating';

  /// Délai minimum entre deux interstitiels, tous emplacements confondus.
  static const adMinSecondsBetweenAny = 'ad_min_seconds_between_any';
}
