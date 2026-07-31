import '../core/config.dart';
import '../core/supabase.dart';
import '../models/models.dart';
import 'ads_service.dart';

/// Issue d'une tentative de mise en avant par visionnage.
///
/// Trois cas se distinguent à l'usage : la vidéo n'était pas disponible
/// (plafond journalier, hors ligne, inventaire vide), l'utilisateur a
/// abandonné en cours de route, ou le serveur a refusé. Les confondre
/// donnerait un message d'erreur générique là où l'ouvrier a besoin de
/// savoir s'il doit réessayer plus tard ou tout de suite.
enum BoostOutcome { success, unavailable, notVerified, error }

class BoostResult {
  final BoostOutcome outcome;
  final DateTime? boostedUntil;
  final String? message;
  const BoostResult(this.outcome, {this.boostedUntil, this.message});
  bool get ok => outcome == BoostOutcome.success;
}

class WorkersService {
  /// Recherche d'ouvriers (fonction SQL `search_workers`).
  /// Les profils boostés et vérifiés remontent en tête, côté base.
  static Future<List<WorkerSearchResult>> search({
    int? tradeId,
    String? city,
    String? query,
    double? lat,
    double? lon,
    double radiusKm = 25,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await db.rpc('search_workers', params: {
      'p_trade_id': tradeId,
      'p_country_code': AppConfig.defaultCountry,
      'p_city': city,
      'p_lat': lat,
      'p_lon': lon,
      'p_radius_km': radiusKm,
      'p_query': query,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List)
        .map((e) => WorkerSearchResult.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<WorkerProfile?> profile(String profileId) async {
    final row = await db
        .from('worker_profiles')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    return row == null ? null : WorkerProfile.fromMap(row);
  }

  static Future<Profile> publicProfile(String profileId) async {
    final row = await db.from('profiles').select().eq('id', profileId).single();
    return Profile.fromMap(row);
  }

  static Future<List<Trade>> tradesOf(String workerId) async {
    final rows = await db
        .from('worker_trades')
        .select('trade:trades(*)')
        .eq('worker_id', workerId);
    return rows
        .map<Trade>((e) => Trade.fromMap(e['trade'] as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Review>> reviewsOf(String profileId) async {
    final rows = await db
        .from('reviews')
        .select('*, reviewer:profiles!reviews_reviewer_id_fkey(full_name)')
        .eq('reviewee_id', profileId)
        .eq('is_hidden', false)
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map<Review>((e) => Review.fromMap(e)).toList();
  }

  /// Crée ou met à jour le profil ouvrier de l'utilisateur connecté.
  static Future<void> upsertMine({
    String? headline,
    int? yearsExperience,
    double? rateMin,
    double? rateMax,
    String pricingUnit = 'day',
    String? availability,
  }) async {
    await db.from('worker_profiles').upsert({
      'profile_id': uid,
      'headline': headline,
      'years_experience': yearsExperience,
      'rate_min': rateMin,
      'rate_max': rateMax,
      'currency': AppConfig.defaultCurrency,
      'pricing_unit': pricingUnit,
      if (availability != null) 'availability': availability,
    });
    await db.from('profiles').update({'role': 'worker'}).eq('id', uid!);
  }

  static Future<void> setTrades(List<int> tradeIds, {int? primaryId}) async {
    await db.from('worker_trades').delete().eq('worker_id', uid!);
    if (tradeIds.isEmpty) return;
    await db.from('worker_trades').insert([
      for (final id in tradeIds)
        {
          'worker_id': uid,
          'trade_id': id,
          'is_primary': id == (primaryId ?? tradeIds.first),
        }
    ]);
  }

  static Future<void> setAvailability(String value) async {
    await db
        .from('worker_profiles')
        .update({'availability': value}).eq('profile_id', uid!);
  }

  /// Mise en avant gagnée en regardant une vidéo jusqu'au bout.
  ///
  /// C'est le geste central du modèle : l'ouvrier n'achète pas sa
  /// visibilité, il l'échange contre l'attention qui finance
  /// l'application. Aucun paiement n'intervient, donc aucune contrainte
  /// de facturation Google ni de moyen de paiement local.
  ///
  /// À n'appeler qu'après un geste explicite — c'est la condition de
  /// conformité du format récompensé. `boosted_until` n'est plus
  /// accessible en écriture directe depuis `column_privileges` : seul
  /// `grant_boost`, qui exige une impression vérifiée par Google, peut
  /// accorder la mise en avant.
  static Future<BoostResult> boostByWatchingAd() async {
    if (!await AdsService.canShow(AdKeys.boostRewarded)) {
      return const BoostResult(
        BoostOutcome.unavailable,
        message: 'Aucune vidéo disponible pour le moment. Réessaie plus tard.',
      );
    }

    final impressionId = await AdsService.showRewarded(AdKeys.boostRewarded);
    if (impressionId == null) {
      return const BoostResult(
        BoostOutcome.notVerified,
        message: "La vidéo n'a pas été validée. Regarde-la jusqu'au bout "
            'pour être mis en avant.',
      );
    }

    try {
      final until = await db.rpc('grant_boost', params: {
        'p_ad_impression_id': impressionId,
      });
      return BoostResult(
        BoostOutcome.success,
        boostedUntil:
            until == null ? null : DateTime.parse(until as String).toLocal(),
      );
    } catch (e) {
      return BoostResult(BoostOutcome.error, message: humanError(e));
    }
  }
}

class ReviewsService {
  static Future<void> submit({
    required String jobId,
    required String revieweeId,
    required int rating,
    String? comment,
    int? quality,
    int? punctuality,
    int? price,
  }) async {
    await db.from('reviews').insert({
      'job_id': jobId,
      'reviewer_id': uid,
      'reviewee_id': revieweeId,
      'rating': rating,
      'comment': comment,
      'quality_rating': quality,
      'punctuality_rating': punctuality,
      'price_rating': price,
    });
  }

  /// Un avis n'est possible qu'une fois par mission et par personne.
  static Future<bool> alreadyReviewed(String jobId) async {
    final row = await db
        .from('reviews')
        .select('id')
        .eq('job_id', jobId)
        .eq('reviewer_id', uid!)
        .maybeSingle();
    return row != null;
  }
}
