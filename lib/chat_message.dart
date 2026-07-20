// chat_message.dart

enum ChatRole { user, assistant, system }

class ChatTurn {
  final ChatRole role;
  String text;

  /// The model's reasoning trace (content between <think> and </think>).
  String thinking;

  final bool isStreaming;

  /// Auto dual-pass phase: 1 = 1.5B drafting, 2 = 4B verifying, null = not dual-pass.
  int? autoPhase;

  /// True if this turn was produced by the dual-pass pipeline (1.5B draft + 4B verify).
  bool isDualPass;

  ChatTurn({
    required this.role,
    required this.text,
    this.thinking = '',
    this.isStreaming = false,
    this.autoPhase,
    this.isDualPass = false,
  });
}
