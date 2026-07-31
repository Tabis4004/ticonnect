import '../core/supabase.dart';

/// Abonnements : grille tarifaire, souscription, état courant.
///
/// Deux règles structurent ce service, et aucune n'est négociable :
///
/// 1. **Le prix n'est jamais transmis par le téléphone.** Il est relu dans
///    `plan_prices` par l'Edge Function `create-payment`. Une requête
///    modifiée achèterait sinon un premium annuel pour un franc.
///
/// 2. **L'application n'active jamais un abonnement.** Seul le webhook de
///    paiement le fait, avec la clé `service_role`. La fonction
///    `activate_subscription()` a son droit d'exécution révoqué pour
///    `anon` et `authenticated` : un APK décompilé ne peut rien en tirer.
class BillingService {
  /// Tarifs disponibles pour le pays du profil connecté.
  static Future<List<PlanPrice>> prices(String countryCode) async {
    final rows = await db
        .from('plan_prices')
        .select('plan, billing_period, amount, currency, country_code')
        .inFilter('country_code', [countryCode.toUpperCase(), 'XX'])
        .eq('is_active', true);

    // Le pays réel prime sur le repli « XX » quand les deux existent.
    final byKey = <String, PlanPrice>{};
    for (final r in rows) {
      final p = PlanPrice.fromMap(r);
      final key = '${p.plan}|${p.billingPeriod}';
      final existing = byKey[key];
      if (existing == null || existing.countryCode == 'XX') {
        byKey[key] = p;
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) {
        final rank = {'pro': 0, 'premium': 1};
        final c = (rank[a.plan] ?? 9).compareTo(rank[b.plan] ?? 9);
        return c != 0 ? c : a.billingPeriod.compareTo(b.billingPeriod);
      });
    return list;
  }

  /// Plan actif : `free`, `pro` ou `premium`.
  ///
  /// La date d'expiration fait foi, pas le statut — sinon une tâche
  /// planifiée en panne offrirait du premium à vie.
  static Future<String> currentPlan() async {
    try {
      final v = await db.rpc('my_plan');
      return (v as String?) ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  static Future<Subscription?> current() async {
    final row = await db
        .from('subscriptions')
        .select()
        .eq('profile_id', uid ?? '')
        .eq('status', 'active')
        .maybeSingle();
    return row == null ? null : Subscription.fromMap(row);
  }

  /// Initie un paiement et rend l'URL de règlement à ouvrir.
  ///
  /// [provider] : `geniuspay` (page de checkout multi-opérateurs) ou
  /// `fedapay`. Laisser GeniusPay par défaut évite d'imposer un opérateur
  /// à un utilisateur qui n'en a pas de compte.
  static Future<CheckoutSession> subscribe({
    required String plan,
    required String billingPeriod,
    String provider = 'geniuspay',
  }) async {
    final res = await db.functions.invoke('create-payment', body: {
      'plan': plan,
      'billing_period': billingPeriod,
      'provider': provider,
    });

    final data = res.data;
    if (data is Map && data['checkout_url'] != null) {
      return CheckoutSession(
        reference: '${data['reference']}',
        checkoutUrl: '${data['checkout_url']}',
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        currency: '${data['currency'] ?? 'XOF'}',
      );
    }
    throw Exception(
      data is Map && data['error'] != null
          ? '${data['error']}'
          : "Le paiement n'a pas pu être initié.",
    );
  }

  /// Interroge l'état d'un paiement.
  ///
  /// Le règlement se termine hors de l'application : au retour, il faut
  /// savoir si le webhook est déjà passé. Un paiement mobile money met
  /// souvent quelques secondes à se confirmer, d'où l'appel répété côté
  /// écran plutôt qu'une lecture unique.
  static Future<String?> paymentStatus(String reference) async {
    final row = await db
        .from('payments')
        .select('status')
        .eq('provider_ref', reference)
        .maybeSingle();
    return row?['status'] as String?;
  }
}

class PlanPrice {
  final String plan;
  final String billingPeriod;
  final double amount;
  final String currency;
  final String countryCode;

  PlanPrice({
    required this.plan,
    required this.billingPeriod,
    required this.amount,
    required this.currency,
    required this.countryCode,
  });

  bool get isAnnual => billingPeriod == 'annual';

  factory PlanPrice.fromMap(Map<String, dynamic> m) => PlanPrice(
        plan: m['plan'] as String,
        billingPeriod: m['billing_period'] as String,
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String? ?? 'XOF',
        countryCode: m['country_code'] as String? ?? 'XX',
      );
}

class Subscription {
  final String id;
  final String plan;
  final String status;
  final String billingPeriod;
  final DateTime? expiresAt;

  Subscription({
    required this.id,
    required this.plan,
    required this.status,
    required this.billingPeriod,
    this.expiresAt,
  });

  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory Subscription.fromMap(Map<String, dynamic> m) => Subscription(
        id: m['id'] as String,
        plan: m['plan'] as String,
        status: m['status'] as String,
        billingPeriod: m['billing_period'] as String? ?? 'monthly',
        expiresAt: DateTime.tryParse('${m['expires_at'] ?? ''}'),
      );
}

class CheckoutSession {
  final String reference;
  final String checkoutUrl;
  final double amount;
  final String currency;

  CheckoutSession({
    required this.reference,
    required this.checkoutUrl,
    required this.amount,
    required this.currency,
  });
}
