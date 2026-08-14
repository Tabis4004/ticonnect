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

  /// Décode une valeur jsonb, qu'elle arrive déjà désérialisée ou en texte.
  ///
  /// Exposée parce que `SettingDef` en a besoin sur des colonnes qui ne
  /// passent pas par le cache — `value` et `choices` de `editable_settings()`.
  static dynamic decodeJson(dynamic v) {
    if (v is String) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return v;
      }
    }
    return v;
  }

  /// Réglages modifiables, tels que la base les décrit.
  ///
  /// Réservé aux administrateurs : `editable_settings()` filtre elle-même
  /// sur `is_admin()`, donc un autre compte reçoit une liste vide plutôt
  /// qu'une erreur.
  static Future<List<SettingDef>> editable() async {
    final rows = await db.rpc('editable_settings');
    if (rows is! List) return const [];
    return [
      for (final r in rows) SettingDef.fromMap(Map<String, dynamic>.from(r)),
    ];
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

  /// Liste de chaînes stockée en tableau JSON.
  ///
  /// Sert aux identifiants d'appareils de test : les déclarer en base
  /// permet d'enrôler un nouveau téléphone sans republier, ce qui compte
  /// quand la seule alternative est un cycle de plusieurs jours sur la
  /// Play Console.
  static List<String> strings(String key) {
    final v = _raw(key);
    if (v is List) return v.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    return const [];
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

/// Un réglage tel que la base le décrit, prêt à être rendu.
///
/// Le type de contrôle, le libellé, les bornes et les choix viennent de
/// `app_settings` — pas du code. C'est ce qui permet à un réglage ajouté
/// demain d'apparaître dans l'écran d'administration sans une ligne de Dart.
class SettingDef {
  final String key;
  final dynamic value;
  final String control; // switch | number | choice | list | text
  final String? label;
  final String? description;
  final String? group;
  final double? min;
  final double? max;
  final double? step;
  final List<Map<String, dynamic>> choices;
  final String? suffix;

  SettingDef({
    required this.key,
    required this.value,
    required this.control,
    this.label,
    this.description,
    this.group,
    this.min,
    this.max,
    this.step,
    this.choices = const [],
    this.suffix,
  });

  factory SettingDef.fromMap(Map<String, dynamic> m) => SettingDef(
        key: m['key'] as String,
        value: SettingsService.decodeJson(m['value']),
        control: m['control'] as String? ?? 'text',
        label: m['label'] as String?,
        description: m['description'] as String?,
        group: m['group_name'] as String?,
        min: (m['min_value'] as num?)?.toDouble(),
        max: (m['max_value'] as num?)?.toDouble(),
        step: (m['step'] as num?)?.toDouble(),
        choices: switch (SettingsService.decodeJson(m['choices'])) {
          final List l => [
              for (final e in l)
                if (e is Map) Map<String, dynamic>.from(e),
            ],
          _ => const [],
        },
        suffix: m['suffix'] as String?,
      );
}

/// Clés utilisées par l'application, alignées sur le seed de la migration 12.
class SettingKeys {
  /// Abonnements Pro et Premium.
  ///
  /// À `false` : le modèle repose entièrement sur le boost gagné par
  /// visionnage. Toute l'infrastructure d'abonnement reste en place mais
  /// n'est plus proposée — un interrupteur, pas une réécriture.
  static const subscriptionsEnabled = 'subscriptions_enabled';

  /// Durée d'un boost gagné par visionnage, et cumul maximum.
  static const boostDurationHours = 'boost_duration_hours';
  static const boostMaxHours = 'boost_max_hours';

  /// Parrainage de clients par les ouvriers.
  static const referralEnabled = 'referral_enabled';
  /// `before` · `after` · `off` — où afficher l'interstitiel côté client.
  static const clientJobAdPlacement = 'client_job_ad_placement';

  /// Publicité récompensée automatique avant l'envoi d'une candidature.
  static const workerApplyAdEnabled = 'worker_apply_ad_enabled';

  /// `before` · `after` · `rewarded` · `off` — quelle publicité imposer
  /// à l'ouvrier au moment de candidater, et à quel instant.
  static const workerApplyAdPlacement = 'worker_apply_ad_placement';

  /// Au plus un résultat sponsorisé toutes les N positions.
  static const sponsoredSlotRatio = 'sponsored_slot_ratio';

  /// Note minimale pour occuper une position sponsorisée.
  static const sponsoredMinRating = 'sponsored_min_rating';

  /// Délai minimum entre deux interstitiels, tous emplacements confondus.
  static const adMinSecondsBetweenAny = 'ad_min_seconds_between_any';

  /// Identifiants des appareils recevant des publicités de test, même en
  /// mode production. C'est le SEUL moyen sûr de vérifier une intégration
  /// avec de vraies unités : sur un appareil enrôlé, Google sert des
  /// annonces de démonstration, donc les clics ne comptent pas comme du
  /// trafic incorrect.
  static const adTestDeviceIds = 'ad_test_device_ids';
}
