// chat_message.dart
//
// Simple local message model for the chat transcript. Nothing here is
// persisted to disk yet (see README "Ideas to extend" for adding
// session.saveState() / loadState() persistence).

enum ChatRole { user, assistant, system }

class ChatTurn {
  final ChatRole role;
  String text;
  final bool isStreaming;

  ChatTurn({
    required this.role,
    required this.text,
    this.isStreaming = false,
  });
}
