import '../core/supabase.dart';

/// Parrainage de clients par les ouvriers.
///
/// Le sens du parrainage n'est pas neutre : un ouvrier qui amène d'autres
/// ouvriers dilue son propre fil de missions — on ajoute de l'offre à une
/// marketplace qui manque de demande. Un ouvrier qui amène un client
/// apporte du travail dont il profite le premier. L'incitation s'aligne
/// donc d'elle-même, sans qu'il faille l'expliquer.
///
/// La récompense est du **temps de mise en avant**, pas un score de
/// classement. Elle alimente `boosted_until` et passe donc par le plafond
/// de la recherche : au plus un sponsorisé toutes les N positions, jamais
/// sous la note plancher, et les abonnés premium servis en premier. Un
/// score séparé serait non borné et entrerait en concurrence avec la note
/// dans l'ordonnancement.
class ReferralService {
  /// Enregistre le code d'un parrain.
  ///
  /// Toutes les vérifications sont côté base : code inconnu, auto-parrainage,
  /// code déjà réclamé, fenêtre d'inscription dépassée, même appareil. Les
  /// codes d'erreur remontent tels quels et sont traduits par `humanError`.
  static Future<void> claim(String code) async {
    await db.rpc('claim_referral', params: {'p_code': code.trim().toUpperCase()});
  }

  static Future<ReferralStats?> stats() async {
    try {
      final rows = await db.rpc('my_referral_stats');
      final list = rows is List ? rows : [rows];
      if (list.isEmpty || list.first == null) return null;
      return ReferralStats.fromMap(Map<String, dynamic>.from(list.first));
    } catch (_) {
      return null;
    }
  }

  /// Filleuls et leur état, du plus récent au plus ancien.
  static Future<List<ReferralEntry>> mine() async {
    final rows = await db
        .from('referrals')
        .select('id, status, boost_days, qualified_at, created_at, '
            'referee:profiles!referrals_referee_id_fkey(full_name)')
        .eq('referrer_id', uid ?? '')
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final r in rows) ReferralEntry.fromMap(r)];
  }

  /// Message prêt à partager.
  ///
  /// Rédigé pour être envoyé par WhatsApp à un ancien client, pas pour
  /// recruter des ouvriers : c'est tout l'objet du dispositif.
  static String invitation(String code) =>
      "Salut ! J'utilise TiConnect pour recevoir mes chantiers. "
      "Si tu as besoin d'un ouvrier, publie ta demande avec mon code $code "
      "et tu auras des propositions rapidement.";
}

class ReferralStats {
  final String? code;
  final int pending;
  final int qualified;
  final int revoked;
  final int boostDaysTotal;
  final int boostDays30d;
  final int monthlyCap;

  ReferralStats({
    this.code,
    required this.pending,
    required this.qualified,
    required this.revoked,
    required this.boostDaysTotal,
    required this.boostDays30d,
    required this.monthlyCap,
  });

  /// Jours de boost encore atteignables ce mois-ci.
  int get remainingThisMonth => (monthlyCap - boostDays30d).clamp(0, monthlyCap);
  bool get capReached => remainingThisMonth == 0 && monthlyCap > 0;

  static int _i(dynamic v) => v is int ? v : (v as num?)?.toInt() ?? 0;

  factory ReferralStats.fromMap(Map<String, dynamic> m) => ReferralStats(
        code: m['code'] as String?,
        pending: _i(m['pending_count']),
        qualified: _i(m['qualified_count']),
        revoked: _i(m['revoked_count']),
        boostDaysTotal: _i(m['boost_days_total']),
        boostDays30d: _i(m['boost_days_30d']),
        monthlyCap: _i(m['monthly_cap']),
      );
}

class ReferralEntry {
  final String id;
  final String status;
  final int boostDays;
  final String? refereeName;
  final DateTime? createdAt;
  final DateTime? qualifiedAt;

  ReferralEntry({
    required this.id,
    required this.status,
    required this.boostDays,
    this.refereeName,
    this.createdAt,
    this.qualifiedAt,
  });

  bool get isQualified => status == 'qualified';
  bool get isRevoked => status == 'revoked';

  factory ReferralEntry.fromMap(Map<String, dynamic> m) => ReferralEntry(
        id: m['id'] as String,
        status: m['status'] as String,
        boostDays: (m['boost_days'] as num?)?.toInt() ?? 0,
        refereeName: (m['referee'] as Map?)?['full_name'] as String?,
        createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
        qualifiedAt: DateTime.tryParse('${m['qualified_at'] ?? ''}'),
      );
}
