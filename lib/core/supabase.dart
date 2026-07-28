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
