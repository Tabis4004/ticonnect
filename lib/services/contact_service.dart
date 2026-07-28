import '../core/supabase.dart';
import '../models/models.dart';
import 'ads_service.dart';

/// Résultat d'une tentative de déverrouillage.
enum UnlockOutcome { success, cancelled, notVerified, noCredits, error }

class UnlockResult {
  final UnlockOutcome outcome;
  final String? message;
  const UnlockResult(this.outcome, [this.message]);
  bool get ok => outcome == UnlockOutcome.success;
}

/// Accès aux coordonnées — le geste central du produit.
///
/// Règle appliquée côté base : le demandeur ne paie jamais. Un client qui
/// consulte le numéro d'un ouvrier passe par la voie gratuite ; un ouvrier
/// qui veut joindre un client ayant publié une mission consomme un crédit,
/// une pub récompensée, ou son quota offert.
class ContactService {
  static Future<ContactDetails?> read(String profileId) async {
    final row = await db
        .from('contact_details')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    return row == null ? null : ContactDetails.fromMap(row);
  }

  static Future<bool> isUnlocked(String profileId) async {
    final row = await db
        .from('contact_unlocks')
        .select('id')
        .eq('unlocker_id', uid!)
        .eq('target_profile_id', profileId)
        .maybeSingle();
    return row != null;
  }

  /// Déverrouillage gratuit : un client consulte le contact d'un ouvrier.
  static Future<UnlockResult> unlockWorker(String workerId) async {
    try {
      await db.rpc('unlock_contact', params: {
        'p_target_profile_id': workerId,
      });
      return const UnlockResult(UnlockOutcome.success);
    } catch (e) {
      return UnlockResult(UnlockOutcome.error, humanError(e));
    }
  }

  /// Déverrouillage payant : un ouvrier accède au contact d'un client.
  /// Consomme d'abord le quota offert, puis les crédits.
  static Future<UnlockResult> unlockClientWithCredits({
    required String clientId,
    required String jobId,
  }) async {
    try {
      await db.rpc('unlock_contact', params: {
        'p_target_profile_id': clientId,
        'p_job_id': jobId,
      });
      return const UnlockResult(UnlockOutcome.success);
    } catch (e) {
      final msg = humanError(e);
      if (msg.contains('crédits')) {
        return UnlockResult(UnlockOutcome.noCredits, msg);
      }
      return UnlockResult(UnlockOutcome.error, msg);
    }
  }

  /// Déverrouillage par publicité récompensée.
  ///
  /// À n'appeler qu'après un geste explicite de l'utilisateur. La récompense
  /// n'est acceptée que si AdMob l'a vérifiée côté serveur.
  static Future<UnlockResult> unlockClientWithAd({
    required String clientId,
    required String jobId,
  }) async {
    final impressionId = await AdsService.showRewarded(AdKeys.unlockRewarded);
    if (impressionId == null) {
      return const UnlockResult(
        UnlockOutcome.notVerified,
        "La vidéo n'a pas pu être validée. Réessaie ou utilise un crédit.",
      );
    }

    try {
      await db.rpc('unlock_contact', params: {
        'p_target_profile_id': clientId,
        'p_job_id': jobId,
        'p_ad_impression_id': impressionId,
      });
      return const UnlockResult(UnlockOutcome.success);
    } catch (e) {
      return UnlockResult(UnlockOutcome.error, humanError(e));
    }
  }
}

class WalletService {
  static Future<Wallet?> mine() async {
    final row = await db
        .from('credit_wallets')
        .select()
        .eq('profile_id', uid!)
        .maybeSingle();
    return row == null ? null : Wallet.fromMap(row);
  }

  static Future<List<CreditTransaction>> history({int limit = 50}) async {
    final rows = await db
        .from('credit_transactions')
        .select()
        .eq('profile_id', uid!)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map<CreditTransaction>((e) => CreditTransaction.fromMap(e)).toList();
  }
}
