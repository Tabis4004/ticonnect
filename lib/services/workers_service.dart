import '../core/config.dart';
import '../core/supabase.dart';
import '../models/models.dart';

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
