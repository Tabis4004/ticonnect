import '../core/supabase.dart';
import '../models/models.dart';

class ChatService {
  static Future<List<Conversation>> conversations() async {
    final me = uid!;
    final rows = await db
        .from('conversations')
        .select('*, '
            'client:profiles!conversations_client_id_fkey(full_name, avatar_url), '
            'worker:profiles!conversations_worker_id_fkey(full_name, avatar_url), '
            'job:job_requests(title)')
        .or('client_id.eq.$me,worker_id.eq.$me')
        .order('last_message_at', ascending: false, nullsFirst: false);
    return rows.map<Conversation>((e) => Conversation.fromMap(e, me)).toList();
  }

  /// Retrouve la conversation existante ou la crée.
  static Future<String> openWith({
    required String clientId,
    required String workerId,
    String? jobId,
  }) async {
    var query = db
        .from('conversations')
        .select('id')
        .eq('client_id', clientId)
        .eq('worker_id', workerId);
    query = jobId == null ? query.isFilter('job_id', null) : query.eq('job_id', jobId);

    final existing = await query.maybeSingle();
    if (existing != null) return existing['id'] as String;

    final row = await db
        .from('conversations')
        .insert({
          'client_id': clientId,
          'worker_id': workerId,
          'job_id': jobId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<List<Message>> messages(String conversationId) async {
    final rows = await db
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.map<Message>((e) => Message.fromMap(e)).toList();
  }

  /// Flux temps réel des messages d'une conversation.
  static Stream<List<Message>> stream(String conversationId) {
    return db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map((e) => Message.fromMap(e)).toList());
  }

  static Future<void> send(String conversationId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': text,
    });
  }

  /// Remet à zéro le compteur de non-lus du côté de l'utilisateur courant.
  static Future<void> markRead(Conversation c) async {
    final me = uid!;
    final field = me == c.clientId ? 'client_unread' : 'worker_unread';
    await db.from('conversations').update({field: 0}).eq('id', c.id);
  }
}
