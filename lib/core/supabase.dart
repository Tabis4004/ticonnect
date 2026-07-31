import 'package:supabase_flutter/supabase_flutter.dart';

/// Raccourcis vers le client Supabase.
SupabaseClient get db => Supabase.instance.client;

/// Identifiant de l'utilisateur connecté, ou null.
String? get uid => Supabase.instance.client.auth.currentUser?.id;

/// Traduit les erreurs Postgres en messages lisibles.
///
/// Les exceptions levées par nos fonctions SQL (crédits insuffisants,
/// récompense publicitaire déjà utilisée) remontent ici telles quelles.
String humanError(Object error) {
  if (error is PostgrestException) {
    final msg = error.message;
    if (msg.contains('Credits insuffisants') || msg.contains('Crédits insuffisants')) {
      return "Tu n'as plus de crédits. Regarde une vidéo ou recharge ton compte.";
    }
    if (msg.contains('Recompense publicitaire') || msg.contains('Récompense publicitaire')) {
      return "Cette récompense n'est plus valable. Réessaie avec une nouvelle vidéo.";
    }
    // Identité progressive : le numéro n'est exigé qu'au premier acte
    // engageant, et le message doit dire où le renseigner.
    if (msg.contains('PHONE_REQUIRED')) {
      return "Renseigne ton numéro dans Mon compte avant de continuer. "
          "Il ne sera visible que par les personnes avec qui tu échanges.";
    }
    if (msg.contains('PHONE_BANNED')) {
      return "Ce numéro est rattaché à un compte suspendu. "
          "Contacte le support si tu penses qu'il s'agit d'une erreur.";
    }
    if (msg.contains('ACCOUNT_SUSPENDED')) {
      return "Ton compte est suspendu. Contacte le support.";
    }
    if (msg.contains('contact_details_phone_key')) {
      return "Ce numéro est déjà utilisé par un autre compte.";
    }

    // Parrainage. Chaque refus dit ce qui s'est passé : un message vague
    // sur un code invalide donne l'impression d'un bug.
    if (msg.contains('REFERRAL_CODE_UNKNOWN')) {
      return "Ce code n'existe pas. Vérifie les caractères — il n'y a ni "
          "zéro ni lettre O, ni un ni lettre I.";
    }
    if (msg.contains('REFERRAL_SELF')) {
      return "Tu ne peux pas utiliser ton propre code.";
    }
    if (msg.contains('REFERRAL_ALREADY_CLAIMED')) {
      return "Tu as déjà été parrainé. Un seul code par compte.";
    }
    if (msg.contains('REFERRAL_WINDOW_CLOSED')) {
      return "Ton compte est trop ancien pour saisir un code d'invitation.";
    }
    if (msg.contains('REFERRAL_SAME_DEVICE')) {
      return "Ce code a déjà été utilisé depuis cet appareil.";
    }
    if (msg.contains('REFERRAL_DISABLED')) {
      return "Le parrainage n'est pas actif pour le moment.";
    }
    if (msg.contains('referrals_referee_key')) {
      return "Tu as déjà été parrainé. Un seul code par compte.";
    }
    if (msg.contains('duplicate key')) {
      return 'Cette action a déjà été effectuée.';
    }
    if (error.code == '42501') {
      return "Tu n'as pas les droits pour cette action.";
    }
    return msg;
  }
  if (error is AuthException) return error.message;
  return "Une erreur est survenue. Vérifie ta connexion.";
}
