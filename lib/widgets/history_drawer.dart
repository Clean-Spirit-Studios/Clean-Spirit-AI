import 'package:flutter/material.dart';

import '../chat_message.dart';
import '../conversation_store.dart';
import 'app_logo.dart';

class HistoryDrawer extends StatelessWidget {
  final VoidCallback onNewConversation;
  final void Function(String sessionId, List<ChatTurn> turns) onLoadSession;
  final Future<void> Function(String sessionId) onDeleteSession;
  final VoidCallback onOpenSettings;

  const HistoryDrawer({
    super.key,
    required this.onNewConversation,
    required this.onLoadSession,
    required this.onDeleteSession,
    required this.onOpenSettings,
  });

  static String formatRelativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const AppLogo(),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Past conversations',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<SessionSummary>>(
                future: ConversationStore.listSessions(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final sessions = snap.data!;
                  if (sessions.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 36,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No saved conversations yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start chatting and your conversations will appear here',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final session = sessions[i];
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.fromLTRB(20, 2, 8, 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: accent,
                          ),
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          formatRelativeDate(session.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.35),
                          ),
                          onPressed: () => onDeleteSession(session.id),
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          final turns =
                              await ConversationStore.loadSession(session.id);
                          if (turns != null) {
                            onLoadSession(session.id, turns);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.add_rounded, size: 20, color: accent),
              ),
              title: Text(
                'New conversation',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                onNewConversation();
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                onOpenSettings();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
