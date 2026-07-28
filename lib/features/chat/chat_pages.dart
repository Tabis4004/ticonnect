import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chat_service.dart';
import '../../widgets/common.dart';
import 'chat_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});
  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  List<Conversation> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      appBar: AppBar(title: const Text('Messages')),
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
                          backgroundColor: AppTheme.primary.withOpacity(0.12),
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
