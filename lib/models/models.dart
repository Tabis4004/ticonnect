/// Modèles de données — miroir Dart du schéma PostgreSQL.
///
/// Chaque classe correspond à une table ou à une fonction de recherche.
/// Les noms de champs reprennent exactement les colonnes SQL pour qu'une
/// évolution du schéma se répercute sans ambiguïté.
library;

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
int _i(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

// ---------------------------------------------------------------- Profil
class Profile {
  final String id;
  final String fullName;
  final String? username;
  final String role; // client | worker | both
  final String? avatarUrl;
  final String? bio;
  final String countryCode;
  final String? city;
  final String? neighborhood;
  final bool isSuspended;

  /// Code de parrainage, généré à la création du profil. Six caractères,
  /// sans 0/O ni 1/I/L : il se dicte au téléphone et se recopie à la main.
  final String? referralCode;

  Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.countryCode,
    this.username,
    this.avatarUrl,
    this.bio,
    this.city,
    this.neighborhood,
    this.isSuspended = false,
    this.referralCode,
  });

  bool get isWorker => role == 'worker' || role == 'both';
  bool get isClient => role == 'client' || role == 'both';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: m['full_name'] as String? ?? 'Utilisateur',
        username: m['username'] as String?,
        role: m['role'] as String? ?? 'client',
        countryCode: m['country_code'] as String? ?? 'CI',
        avatarUrl: m['avatar_url'] as String?,
        bio: m['bio'] as String?,
        city: m['city'] as String?,
        neighborhood: m['neighborhood'] as String?,
        isSuspended: m['is_suspended'] as bool? ?? false,
        referralCode: m['referral_code'] as String?,
      );
}

// ------------------------------------------------------- Métier / catégorie
class TradeCategory {
  final int id;
  final String slug;
  final String nameFr;
  TradeCategory({required this.id, required this.slug, required this.nameFr});

  factory TradeCategory.fromMap(Map<String, dynamic> m) => TradeCategory(
        id: _i(m['id']),
        slug: m['slug'] as String,
        nameFr: m['name_fr'] as String,
      );
}

class Trade {
  final int id;
  final int categoryId;
  final String slug;
  final String nameFr;
  Trade({
    required this.id,
    required this.categoryId,
    required this.slug,
    required this.nameFr,
  });

  factory Trade.fromMap(Map<String, dynamic> m) => Trade(
        id: _i(m['id']),
        categoryId: _i(m['category_id']),
        slug: m['slug'] as String,
        nameFr: m['name_fr'] as String,
      );
}

// ---------------------------------------------------------- Profil ouvrier
class WorkerProfile {
  final String profileId;
  final String? headline;
  final int? yearsExperience;
  final double? rateMin;
  final double? rateMax;
  final String currency;
  final String pricingUnit;
  final String availability;
  final String verification;
  final double ratingAvg;
  final int ratingCount;
  final int jobsCompleted;
  final bool isListed;
  final DateTime? boostedUntil;
  final int freeUnlocksLeft;

  /// Réactivité, calculée en base à partir des messages — jamais déclarée.
  ///
  /// `responseSample` compte les conversations retenues : sans lui, un taux
  /// de 0 % sur une seule conversation se lirait comme un taux de 0 % sur
  /// cent. Rien n'est affiché tant que l'échantillon est trop mince.
  final double? responseRate;
  final int? responseMedianMinutes;
  final int responseSample;

  WorkerProfile({
    required this.profileId,
    required this.currency,
    required this.pricingUnit,
    required this.availability,
    required this.verification,
    required this.ratingAvg,
    required this.ratingCount,
    required this.jobsCompleted,
    required this.isListed,
    required this.freeUnlocksLeft,
    this.headline,
    this.yearsExperience,
    this.rateMin,
    this.rateMax,
    this.boostedUntil,
    this.responseRate,
    this.responseMedianMinutes,
    this.responseSample = 0,
  });

  bool get isVerified => verification == 'verified';
  bool get isBoosted =>
      boostedUntil != null && boostedUntil!.isAfter(DateTime.now());

  factory WorkerProfile.fromMap(Map<String, dynamic> m) => WorkerProfile(
        profileId: m['profile_id'] as String,
        headline: m['headline'] as String?,
        yearsExperience: (m['years_experience'] as num?)?.toInt(),
        rateMin: _d(m['rate_min']),
        rateMax: _d(m['rate_max']),
        currency: m['currency'] as String? ?? 'XOF',
        pricingUnit: m['pricing_unit'] as String? ?? 'day',
        availability: m['availability'] as String? ?? 'available',
        verification: m['verification'] as String? ?? 'unverified',
        ratingAvg: _d(m['rating_avg']) ?? 0,
        ratingCount: _i(m['rating_count']),
        jobsCompleted: _i(m['jobs_completed']),
        isListed: m['is_listed'] as bool? ?? true,
        boostedUntil: _dt(m['boosted_until']),
        freeUnlocksLeft: _i(m['free_unlocks_left']),
        // Les colonnes de réactivité n'existent pas encore sur toutes les
        // bases : `_d` et `_i` rendent null et zéro sur une clé absente,
        // et `responseSample` à zéro fait taire l'affichage — ce qui est
        // exactement le comportement voulu tant qu'on ne mesure rien.
        responseRate: _d(m['response_rate']),
        responseMedianMinutes: (m['response_median_minutes'] as num?)?.toInt(),
        responseSample: _i(m['response_sample']),
      );
}

/// Résultat de la fonction SQL `search_workers`.
class WorkerSearchResult {
  final String profileId;
  final String fullName;
  final String? avatarUrl;
  final String? headline;
  final String? city;
  final String? neighborhood;
  final double ratingAvg;
  final int ratingCount;
  final int jobsCompleted;
  final String verification;
  final String availability;
  final double? rateMin;
  final double? rateMax;
  final String currency;
  final String pricingUnit;
  final bool isBoosted;
  final double? distanceKm;

  WorkerSearchResult({
    required this.profileId,
    required this.fullName,
    required this.ratingAvg,
    required this.ratingCount,
    required this.jobsCompleted,
    required this.verification,
    required this.availability,
    required this.currency,
    required this.pricingUnit,
    required this.isBoosted,
    this.avatarUrl,
    this.headline,
    this.city,
    this.neighborhood,
    this.rateMin,
    this.rateMax,
    this.distanceKm,
  });

  bool get isVerified => verification == 'verified';

  factory WorkerSearchResult.fromMap(Map<String, dynamic> m) =>
      WorkerSearchResult(
        profileId: m['profile_id'] as String,
        fullName: m['full_name'] as String? ?? 'Ouvrier',
        avatarUrl: m['avatar_url'] as String?,
        headline: m['headline'] as String?,
        city: m['city'] as String?,
        neighborhood: m['neighborhood'] as String?,
        ratingAvg: _d(m['rating_avg']) ?? 0,
        ratingCount: _i(m['rating_count']),
        jobsCompleted: _i(m['jobs_completed']),
        verification: m['verification'] as String? ?? 'unverified',
        availability: m['availability'] as String? ?? 'available',
        rateMin: _d(m['rate_min']),
        rateMax: _d(m['rate_max']),
        currency: m['currency'] as String? ?? 'XOF',
        pricingUnit: m['pricing_unit'] as String? ?? 'day',
        isBoosted: m['is_boosted'] as bool? ?? false,
        distanceKm: _d(m['distance_km']),
      );
}

// -------------------------------------------------------------- Demandes
class JobRequest {
  final String id;
  final String clientId;
  final int tradeId;
  final String title;
  final String description;
  final List<String> photos;
  final String city;
  final String? neighborhood;
  final double? budgetMin;
  final double? budgetMax;
  final String currency;
  final String pricingUnit;
  final String urgency;
  final String status;
  final String? assignedWorkerId;
  final int unlockCost;
  final int applicationsCount;
  final DateTime? createdAt;

  JobRequest({
    required this.id,
    required this.clientId,
    required this.tradeId,
    required this.title,
    required this.description,
    required this.city,
    required this.currency,
    required this.pricingUnit,
    required this.urgency,
    required this.status,
    required this.unlockCost,
    required this.applicationsCount,
    this.photos = const [],
    this.neighborhood,
    this.budgetMin,
    this.budgetMax,
    this.assignedWorkerId,
    this.createdAt,
  });

  bool get isOpen => status == 'open';
  bool get isCompleted => status == 'completed';

  factory JobRequest.fromMap(Map<String, dynamic> m) => JobRequest(
        id: m['id'] as String,
        clientId: m['client_id'] as String? ?? '',
        tradeId: _i(m['trade_id']),
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        photos: (m['photos'] as List?)?.cast<String>() ?? const [],
        city: m['city'] as String? ?? '',
        neighborhood: m['neighborhood'] as String?,
        budgetMin: _d(m['budget_min']),
        budgetMax: _d(m['budget_max']),
        currency: m['currency'] as String? ?? 'XOF',
        pricingUnit: m['pricing_unit'] as String? ?? 'day',
        urgency: m['urgency'] as String? ?? 'flexible',
        status: m['status'] as String? ?? 'open',
        assignedWorkerId: m['assigned_worker_id'] as String?,
        unlockCost: _i(m['unlock_cost'], 1),
        applicationsCount: _i(m['applications_count']),
        createdAt: _dt(m['created_at']),
      );
}

/// Résultat de la fonction SQL `search_jobs`, côté ouvrier.
///
/// `isUnlocked` dit si le contact du client est déjà accessible : c'est ce
/// champ qui décide d'afficher le numéro ou le bouton « Regarder une vidéo ».
class JobSearchResult {
  final String id;
  final String title;
  final String description;
  final int tradeId;
  final String tradeName;
  final String city;
  final String? neighborhood;
  final double? budgetMin;
  final double? budgetMax;
  final String currency;
  final String pricingUnit;
  final String urgency;
  final int unlockCost;
  final int applicationsCount;
  final String clientName;
  final bool isUnlocked;
  final bool hasApplied;
  final DateTime? createdAt;

  JobSearchResult({
    required this.id,
    required this.title,
    required this.description,
    required this.tradeId,
    required this.tradeName,
    required this.city,
    required this.currency,
    required this.pricingUnit,
    required this.urgency,
    required this.unlockCost,
    required this.applicationsCount,
    required this.clientName,
    required this.isUnlocked,
    required this.hasApplied,
    this.neighborhood,
    this.budgetMin,
    this.budgetMax,
    this.createdAt,
  });

  factory JobSearchResult.fromMap(Map<String, dynamic> m) => JobSearchResult(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        tradeId: _i(m['trade_id']),
        tradeName: m['trade_name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        neighborhood: m['neighborhood'] as String?,
        budgetMin: _d(m['budget_min']),
        budgetMax: _d(m['budget_max']),
        currency: m['currency'] as String? ?? 'XOF',
        pricingUnit: m['pricing_unit'] as String? ?? 'day',
        urgency: m['urgency'] as String? ?? 'flexible',
        unlockCost: _i(m['unlock_cost'], 1),
        applicationsCount: _i(m['applications_count']),
        clientName: m['client_name'] as String? ?? 'Client',
        isUnlocked: m['is_unlocked'] as bool? ?? false,
        hasApplied: m['has_applied'] as bool? ?? false,
        createdAt: _dt(m['created_at']),
      );
}

class JobApplication {
  final String id;
  final String jobId;
  final String workerId;
  final String? message;
  final double? proposedPrice;
  final String currency;
  final String status;
  final DateTime? createdAt;
  final String? workerName;
  final double? workerRating;

  JobApplication({
    required this.id,
    required this.jobId,
    required this.workerId,
    required this.currency,
    required this.status,
    this.message,
    this.proposedPrice,
    this.createdAt,
    this.workerName,
    this.workerRating,
  });

  factory JobApplication.fromMap(Map<String, dynamic> m) {
    final worker = m['worker'] as Map<String, dynamic>?;
    return JobApplication(
      id: m['id'] as String,
      jobId: m['job_id'] as String,
      workerId: m['worker_id'] as String,
      message: m['message'] as String?,
      proposedPrice: _d(m['proposed_price']),
      currency: m['currency'] as String? ?? 'XOF',
      status: m['status'] as String? ?? 'pending',
      createdAt: _dt(m['created_at']),
      workerName: worker?['full_name'] as String?,
      workerRating: _d((worker?['worker_profiles'] as Map?)?['rating_avg']),
    );
  }
}

// ------------------------------------------------------------- Messagerie
class Conversation {
  final String id;
  final String? jobId;
  final String clientId;
  final String workerId;
  final DateTime? lastMessageAt;
  final int clientUnread;
  final int workerUnread;
  final String? otherName;
  final String? otherAvatar;
  final String? jobTitle;

  Conversation({
    required this.id,
    required this.clientId,
    required this.workerId,
    required this.clientUnread,
    required this.workerUnread,
    this.jobId,
    this.lastMessageAt,
    this.otherName,
    this.otherAvatar,
    this.jobTitle,
  });

  String otherId(String me) => me == clientId ? workerId : clientId;
  int unreadFor(String me) => me == clientId ? clientUnread : workerUnread;

  factory Conversation.fromMap(Map<String, dynamic> m, String me) {
    final client = m['client'] as Map<String, dynamic>?;
    final worker = m['worker'] as Map<String, dynamic>?;
    final isClient = m['client_id'] == me;
    final other = isClient ? worker : client;
    return Conversation(
      id: m['id'] as String,
      jobId: m['job_id'] as String?,
      clientId: m['client_id'] as String,
      workerId: m['worker_id'] as String,
      lastMessageAt: _dt(m['last_message_at']),
      clientUnread: _i(m['client_unread']),
      workerUnread: _i(m['worker_unread']),
      otherName: other?['full_name'] as String?,
      otherAvatar: other?['avatar_url'] as String?,
      jobTitle: (m['job'] as Map<String, dynamic>?)?['title'] as String?,
    );
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final String? attachmentUrl;
  final bool containsContact;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    required this.containsContact,
    this.body,
    this.attachmentUrl,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String?,
        attachmentUrl: m['attachment_url'] as String?,
        containsContact: m['contains_contact'] as bool? ?? false,
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
      );
}

// ------------------------------------------------------------------ Avis
class Review {
  final String id;
  final String jobId;
  final String reviewerId;
  final String revieweeId;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final String? reviewerName;

  Review({
    required this.id,
    required this.jobId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    this.comment,
    this.createdAt,
    this.reviewerName,
  });

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] as String,
        jobId: m['job_id'] as String,
        reviewerId: m['reviewer_id'] as String,
        revieweeId: m['reviewee_id'] as String,
        rating: _i(m['rating']),
        comment: m['comment'] as String?,
        createdAt: _dt(m['created_at']),
        reviewerName:
            (m['reviewer'] as Map<String, dynamic>?)?['full_name'] as String?,
      );
}

// ---------------------------------------------------- Portefeuille / pubs
class Wallet {
  final int balance;
  final int lifetimeEarned;
  final int lifetimeSpent;

  Wallet({
    required this.balance,
    required this.lifetimeEarned,
    required this.lifetimeSpent,
  });

  factory Wallet.fromMap(Map<String, dynamic> m) => Wallet(
        balance: _i(m['balance']),
        lifetimeEarned: _i(m['lifetime_earned']),
        lifetimeSpent: _i(m['lifetime_spent']),
      );
}

class CreditTransaction {
  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final String? description;
  final DateTime? createdAt;

  CreditTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.createdAt,
  });

  factory CreditTransaction.fromMap(Map<String, dynamic> m) =>
      CreditTransaction(
        id: m['id'] as String,
        type: m['type'] as String,
        amount: _i(m['amount']),
        balanceAfter: _i(m['balance_after']),
        description: m['description'] as String?,
        createdAt: _dt(m['created_at']),
      );
}

/// Configuration d'un emplacement publicitaire, pilotée depuis la base.
///
/// Permet d'ajuster la fréquence des pubs sans republier l'application.
class AdPlacement {
  final String key;
  final String format;
  final String? adUnitAndroid;
  final String? adUnitIos;
  final bool isEnabled;
  final int rewardCredits;
  final int? dailyCapPerUser;
  final int minSecondsBetween;

  /// Écran d'introduction des formats récompensés. Pour
  /// `rewarded_interstitial`, l'annonce de la récompense et la porte de
  /// sortie ne sont pas décoratives : c'est ce qui rend l'affichage
  /// automatique conforme aux règles AdMob.
  final String? introTitle;
  final String? introBody;
  final String? introCta;
  final String? skipLabel;

  AdPlacement({
    required this.key,
    required this.format,
    required this.isEnabled,
    required this.rewardCredits,
    required this.minSecondsBetween,
    this.adUnitAndroid,
    this.adUnitIos,
    this.dailyCapPerUser,
    this.introTitle,
    this.introBody,
    this.introCta,
    this.skipLabel,
  });

  factory AdPlacement.fromMap(Map<String, dynamic> m) => AdPlacement(
        key: m['key'] as String,
        format: m['format'] as String,
        adUnitAndroid: m['ad_unit_android'] as String?,
        adUnitIos: m['ad_unit_ios'] as String?,
        isEnabled: m['is_enabled'] as bool? ?? false,
        rewardCredits: _i(m['reward_credits']),
        dailyCapPerUser: (m['daily_cap_per_user'] as num?)?.toInt(),
        minSecondsBetween: _i(m['min_seconds_between'], 60),
        introTitle: m['intro_title'] as String?,
        introBody: m['intro_body'] as String?,
        introCta: m['intro_cta'] as String?,
        skipLabel: m['skip_label'] as String?,
      );
}

class ContactDetails {
  final String phone;
  final String? whatsapp;
  final String? email;
  ContactDetails({required this.phone, this.whatsapp, this.email});

  factory ContactDetails.fromMap(Map<String, dynamic> m) => ContactDetails(
        phone: m['phone'] as String,
        whatsapp: m['whatsapp'] as String?,
        email: m['email'] as String?,
      );
}
