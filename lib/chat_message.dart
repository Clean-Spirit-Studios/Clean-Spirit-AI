// chat_message.dart

enum ChatRole { user, assistant, system }

class ChatTurn {
  final ChatRole role;
  String text;

  /// The model's reasoning trace (content between <think> and </think>).
  String thinking;

  final bool isStreaming;

  /// Local file path of an attached image (user turns only).
  /// Null when no image was attached.
  final String? imagePath;

  /// Display name of an attached document (user turns only).
  /// Null when no document was attached.
  final String? documentName;

  /// Which model/architecture produced this turn (assistant turns only).
  /// Used for the small label under the last assistant bubble.
  final String? modelLabel;

  ChatTurn({
    required this.role,
    required this.text,
    this.thinking = '',
    this.isStreaming = false,
    this.imagePath,
    this.documentName,
    this.modelLabel,
  });
}
