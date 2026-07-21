// chat_message.dart

enum ChatRole { user, assistant, system }

class ChatTurn {
  final ChatRole role;
  String text;

  /// The model's reasoning trace (content between <think> and </think>).
  String thinking;

  final bool isStreaming;

  ChatTurn({
    required this.role,
    required this.text,
    this.thinking = '',
    this.isStreaming = false,
  });
}
