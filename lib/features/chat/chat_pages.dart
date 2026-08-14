import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, RealtimeChannel;

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_service.dart';
import '../../widgets/common.dart';
import '../worker/notifications_page.dart';
import 'chat_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});
  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage>
    with WidgetsBindingObserver {
  List<Conversation> _items = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listen();
  }

  /// Recharge au retour au premier plan.
  ///
  /// Le temps réel ne rejoue pas ce qui s'est passé pendant une coupure :
  /// changement de réseau, mise en veille, application en arrière-plan, et
  /// le WebSocket tombe. Le client se reconnecte, mais les événements
  /// manqués sont perdus — la liste resterait figée jusqu'au prochain
  /// message.
  ///
  /// Sur un téléphone qui passe la nuit en veille, c'est la différence
  /// entre voir ses messages au réveil et ne jamais les voir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  /// Recharge la liste dès qu'une conversation bouge.
  ///
  /// Le shell utilise un `IndexedStack` : les cinq onglets sont construits
  /// une seule fois et gardés en vie. `initState` ne tourne donc qu'au
  /// démarrage de l'application, et revenir sur l'onglet Messages
  /// n'actualisait rien — la liste restait figée sur l'état du lancement.
  /// Un message reçu, ou même envoyé, n'apparaissait qu'après avoir tué et
  /// relancé l'application.
  ///
  /// Le trigger `sync_conversation_on_message` met à jour `last_message_at`
  /// à chaque message : écouter la table `conversations` suffit donc à
  /// couvrir aussi bien les nouvelles discussions que les nouveaux
  /// messages dans une discussion existante.
  void _listen() {
    final me = uid;
    if (me == null) return;

    _channel = db.channel('conversations:$me')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversations',
        callback: (_) {
          if (mounted) _load();
        },
      )
      ..subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final c = _channel;
    if (c != null) db.removeChannel(c);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ChatService.conversations();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) showError(context, humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = uid;
    return Scaffold(
      // L'écran « Alertes » n'était atteignable que depuis le fil des
      // missions — donc réservé aux ouvriers. Un client ne pouvait ni
      // consulter ses notifications, ni les marquer comme lues, ce qui
      // suffisait à le priver définitivement de toute alerte ultérieure.
      // « Messages » est l'onglet commun aux deux rôles.
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Alertes',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Loading()
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Aucune conversation',
                  subtitle: 'Tes échanges avec les clients et les ouvriers '
                      'apparaîtront ici.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      final unread = me == null ? 0 : c.unreadFor(me);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                          backgroundImage: c.otherAvatar != null
                              ? NetworkImage(c.otherAvatar!)
                              : null,
                          child: c.otherAvatar == null
                              ? Text(
                                  (c.otherName ?? '?').substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: AppTheme.primary))
                              : null,
                        ),
                        title: Text(c.otherName ?? 'Utilisateur',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.jobTitle ?? 'Discussion',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Fmt.ago(c.lastMessageAt),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black45)),
                            if (unread > 0) ...[
                              const SizedBox(height: 4),
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: AppTheme.primary,
                                child: Text('$unread',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                        onTap: () async {
                          await ChatService.markRead(c);
                          if (!context.mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                conversationId: c.id,
                                title: c.otherName ?? 'Discussion',
                              ),
                            ),
                          );
                          _load();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
