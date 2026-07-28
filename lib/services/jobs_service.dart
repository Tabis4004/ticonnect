import '../core/config.dart';
import '../core/supabase.dart';
import '../models/models.dart';

class JobsService {
  /// Recherche de missions côté ouvrier (fonction SQL `search_jobs`).
  static Future<List<JobSearchResult>> search({
    List<int>? tradeIds,
    String? city,
    String? urgency,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await db.rpc('search_jobs', params: {
      'p_trade_ids': tradeIds,
      'p_country_code': AppConfig.defaultCountry,
      'p_city': city,
      'p_urgency': urgency,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List)
        .map((e) => JobSearchResult.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<JobRequest> byId(String id) async {
    final row = await db.from('job_requests').select().eq('id', id).single();
    return JobRequest.fromMap(row);
  }

  /// Missions publiées par le client connecté.
  static Future<List<JobRequest>> mine() async {
    final rows = await db
        .from('job_requests')
        .select()
        .eq('client_id', uid!)
        .order('created_at', ascending: false);
    return rows.map<JobRequest>((e) => JobRequest.fromMap(e)).toList();
  }

  /// Missions attribuées à l'ouvrier connecté.
  static Future<List<JobRequest>> assignedToMe() async {
    final rows = await db
        .from('job_requests')
        .select()
        .eq('assigned_worker_id', uid!)
        .order('created_at', ascending: false);
    return rows.map<JobRequest>((e) => JobRequest.fromMap(e)).toList();
  }

  static Future<JobRequest> create({
    required int tradeId,
    required String title,
    required String description,
    required String city,
    String? neighborhood,
    double? budgetMin,
    double? budgetMax,
    String urgency = 'flexible',
    String pricingUnit = 'day',
    List<String> photos = const [],
  }) async {
    final row = await db
        .from('job_requests')
        .insert({
          'client_id': uid,
          'trade_id': tradeId,
          'title': title,
          'description': description,
          'city': city,
          'neighborhood': neighborhood,
          'budget_min': budgetMin,
          'budget_max': budgetMax,
          'currency': AppConfig.defaultCurrency,
          'pricing_unit': pricingUnit,
          'urgency': urgency,
          'country_code': AppConfig.defaultCountry,
          'photos': photos,
        })
        .select()
        .single();
    return JobRequest.fromMap(row);
  }

  static Future<void> updateStatus(String jobId, String status) async {
    await db.from('job_requests').update({'status': status}).eq('id', jobId);
  }

  static Future<void> cancel(String jobId) => updateStatus(jobId, 'cancelled');

  /// Marque la mission terminée. Déclenche côté base l'incrément du compteur
  /// de missions de l'ouvrier et l'ouverture du droit à déposer un avis.
  static Future<void> complete(String jobId) => updateStatus(jobId, 'completed');
}

class ApplicationsService {
  /// Candidatures reçues sur une mission (vue client).
  static Future<List<JobApplication>> forJob(String jobId) async {
    final rows = await db
        .from('job_applications')
        .select('*, worker:profiles!job_applications_worker_id_fkey('
            'full_name, avatar_url, worker_profiles(rating_avg, rating_count))')
        .eq('job_id', jobId)
        .order('created_at', ascending: false);
    return rows.map<JobApplication>((e) => JobApplication.fromMap(e)).toList();
  }

  /// Candidatures envoyées par l'ouvrier connecté.
  static Future<List<JobApplication>> mine() async {
    final rows = await db
        .from('job_applications')
        .select()
        .eq('worker_id', uid!)
        .order('created_at', ascending: false);
    return rows.map<JobApplication>((e) => JobApplication.fromMap(e)).toList();
  }

  static Future<void> apply({
    required String jobId,
    String? message,
    double? proposedPrice,
  }) async {
    await db.from('job_applications').insert({
      'job_id': jobId,
      'worker_id': uid,
      'message': message,
      'proposed_price': proposedPrice,
      'currency': AppConfig.defaultCurrency,
    });
  }

  /// Accepter une candidature. Le trigger SQL affecte l'ouvrier à la mission
  /// et rejette automatiquement les autres candidatures.
  static Future<void> accept(String applicationId) async {
    await db
        .from('job_applications')
        .update({'status': 'accepted'}).eq('id', applicationId);
  }

  static Future<void> reject(String applicationId) async {
    await db
        .from('job_applications')
        .update({'status': 'rejected'}).eq('id', applicationId);
  }
}
