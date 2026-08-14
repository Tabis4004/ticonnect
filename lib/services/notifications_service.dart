import '../core/supabase.dart';

/// Notifications in-app.
///
/// Alimentées par le trigger SQL `notify_matching_workers` : dès qu'un client
/// publie une mission, les ouvriers du bon métier, disponibles et dans la
/// bonne ville reçoivent une ligne ici — sans qu'aucun code applicatif ne
/// s'exécute. Le jour où les jetons FCM seront collectés, la même logique
/// enverra une notification push.
class NotificationsService {
  static Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    final rows = await db
        .from('notifications')
        .select()
        .eq('profile_id', uid!)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<int> unreadCount() async {
    try {
      final rows = await db
          .from('notifications')
          .select('id')
          .eq('profile_id', uid!)
          .isFilter('read_at', null);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markAllRead() async {
    await db
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('profile_id', uid!)
        .isFilter('read_at', null);
  }

  /// Solde les notifications d'une conversation à son ouverture.
  ///
  /// `notify_on_message` ne crée qu'une notification non lue par
  /// conversation, pour ne pas harceler à chaque message. La contrepartie
  /// est brutale : tant que celle-ci n'est pas soldée, plus aucune n'est
  /// créée pour cette conversation — donc plus aucun push.
  ///
  /// Le marquage était laissé à l'écran « Alertes », que seul un ouvrier
  /// peut atteindre. Un client ne pouvait donc jamais solder la sienne et
  /// cessait définitivement d'être prévenu, sans rien avoir fait de mal.
  /// Lier le marquage à l'ouverture de la conversation ne dépend d'aucun
  /// écran que l'utilisateur doit penser à visiter.
  static Future<void> markReadForConversation(String conversationId) async {
    final me = uid;
    if (me == null) return;
    try {
      await db
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('profile_id', me)
          .eq('kind', 'message')
          .filter('payload->>conversation_id', 'eq', conversationId)
          .isFilter('read_at', null);
    } catch (_) {
      // Silencieux : rater ce marquage ne doit pas empêcher de lire ses
      // messages. Au pire la notification reste non lue.
    }
  }
}
