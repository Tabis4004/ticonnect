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
}
