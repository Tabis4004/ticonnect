import '../core/config.dart';
import '../core/supabase.dart';
import 'session.dart';
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
  /// [countryCode] : pays où se trouve le CHANTIER, pas l'utilisateur.
  ///
  /// Par défaut celui du profil, mais modifiable depuis l'écran : ouvrir
  /// son compte à Lomé et chercher un ouvrier pour un chantier à Abidjan
  /// est courant — diaspora, commerçants, familles réparties sur deux
  /// pays. Enfermer la recherche dans le pays de résidence rendait ces
  /// utilisateurs incapables de trouver qui que ce soit.
  static Future<List<WorkerSearchResult>> search({
    int? tradeId,
    String? city,
    String? query,
    String? countryCode,
    double? lat,
    double? lon,
    double radiusKm = 25,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await db.rpc('search_workers', params: {
      'p_trade_id': tradeId,
      'p_country_code': countryCode ?? AppSession.currentCountry,
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
    // Un client qui se déclare ouvrier garde ses besoins : il devient
    // `both`, pas `worker`. L'écraser en `worker` lui retirait les onglets
    // « Chercher » et « Demandes » sans prévenir, et il perdait l'accès à
    // ses propres demandes en cours.
    final actuel = await db
        .from('profiles')
        .select('role')
        .eq('id', uid!)
        .maybeSingle();
    final role = (actuel?['role'] as String?) == 'client' ? 'both' : 'worker';
    await db.from('profiles').update({'role': role}).eq('id', uid!);
  }

  /// Ajoute ou retire le versant client d'un ouvrier.
  ///
  /// Un maçon qui doit faire réparer sa moto est le cas le plus banal du
  /// marché visé. Le rôle `both` existait depuis l'origine en base, sans
  /// aucun chemin dans l'interface pour l'atteindre.
  static Future<void> setAlsoClient(bool aussiClient) async {
    await db
        .from('profiles')
        .update({'role': aussiClient ? 'both' : 'worker'}).eq('id', uid!);
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

  /// Disponibilité de l'ouvrier.
  ///
  /// `upsert` et non `update` : un compte inscrit comme ouvrier a bien
  /// `profiles.role = 'worker'`, mais sa ligne `worker_profiles` n'existe
  /// qu'après le premier enregistrement du profil métier. Un `update`
  /// touchait alors zéro ligne — PostgREST répond succès, l'interrupteur
  /// revenait à sa position d'origine, et aucune erreur ne s'affichait.
  ///
  /// L'upsert crée la ligne au besoin. Si le numéro de téléphone manque,
  /// le garde-fou d'identité progressive lève PHONE_REQUIRED et l'erreur
  /// remonte enfin à l'utilisateur, qui sait alors quoi faire.
  static Future<void> setAvailability(String value) async {
    await db.from('worker_profiles').upsert(
      {'profile_id': uid, 'availability': value},
      onConflict: 'profile_id',
    );
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
    final blocage = await AdsService.blockReason(AdKeys.boostRewarded);
    if (blocage != null) {
      return BoostResult(BoostOutcome.unavailable, message: blocage);
    }

    final impressionId = await AdsService.showRewarded(AdKeys.boostRewarded);
    if (impressionId == null) {
      // Distinguer les deux échecs : reprocher un abandon à quelqu'un qui
      // n'a jamais vu la moindre vidéo est faux et décourageant.
      final erreur = AdsService.lastLoadError;
      return BoostResult(
        erreur == null ? BoostOutcome.notVerified : BoostOutcome.unavailable,
        message: erreur == null
            ? "La vidéo n'a pas été validée. Regarde-la jusqu'au bout pour "
                'être mis en avant.'
            : 'Aucune annonce disponible pour le moment. Réessaie plus tard.',
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
