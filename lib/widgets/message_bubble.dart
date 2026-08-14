import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../chat_message.dart';
import '../markdown_renderer.dart';

class MessageBubble extends StatefulWidget {
  final ChatTurn turn;
  final bool isLast;

  const MessageBubble({required this.turn, required this.isLast});

  @override
  State<MessageBubble> createState() => MessageBubbleState();
}

class MessageBubbleState extends State<MessageBubble> {
  bool _justCopied = false;

  Future<void> _copy(BuildContext context) async {
    if (widget.turn.text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: widget.turn.text));
    if (!mounted) return;

    setState(() => _justCopied = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _justCopied = false);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final isUser = turn.role == ChatRole.user;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    final isThinking =
        turn.isStreaming && turn.text.isEmpty && turn.thinking.isNotEmpty;
    final hasThinking = turn.thinking.isNotEmpty;
    final showPlaceholder = turn.text.isEmpty && turn.thinking.isEmpty;

    final maxWidth = screenWidth * (isUser ? 0.88 : 0.94);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _copy(context),
            onLongPress: () => _copy(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 3),
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: _justCopied
                    ? (isUser
                        ? theme.colorScheme.primary.withValues(alpha: 0.7)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.7))
                    : (isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUser && turn.imagePath != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                      child: Image.file(
                        File(turn.imagePath!),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUser && turn.imagePath != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.shade400
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.tealAccent.shade400
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.visibility_outlined,
                                    size: 10,
                                    color: Colors.tealAccent.shade400),
                                const SizedBox(width: 4),
                                Text(
                                  'VISION',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.tealAccent.shade400,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (isUser && turn.documentName != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 13,
                                color: theme.colorScheme.onPrimary
                                    .withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  turn.documentName!.length > 28
                                      ? '${turn.documentName!.substring(0, 25)}...'
                                      : turn.documentName!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onPrimary
                                        .withValues(alpha: 0.8),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (hasThinking)
                          ThinkingPanel(
                            thinking: turn.thinking,
                            isThinking: isThinking,
                          ),
                        if (showPlaceholder || turn.text.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: showPlaceholder
                                    ? Text(
                                        'Thinking...',
                                        style: TextStyle(
                                          color: isUser
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      )
                                    : isUser
                                        ? Text(
                                            turn.text,
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                            ),
                                          )
                                        : ChatMarkdown(
                                            data: turn.text,
                                            textColor:
                                                theme.colorScheme.onSurface,
                                          ),
                              ),
                              if (_justCopied) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: isUser
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isUser &&
              widget.isLast &&
              turn.text.isNotEmpty &&
              turn.modelLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                turn.modelLabel!,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking panel (unchanged from original)
// ---------------------------------------------------------------------------

class ThinkingPanel extends StatefulWidget {
  final String thinking;
  final bool isThinking;

  const ThinkingPanel({required this.thinking, required this.isThinking});

  @override
  State<ThinkingPanel> createState() => ThinkingPanelState();
}

class ThinkingPanelState extends State<ThinkingPanel> {
  late bool _expanded = widget.isThinking;
  bool _manuallyToggled = false;

  @override
  void didUpdateWidget(covariant ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isThinking && !widget.isThinking && !_manuallyToggled) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _expanded = !_expanded;
            _manuallyToggled = true;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: widget.isThinking
                      ? CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: mutedColor,
                        )
                      : Icon(
                          Icons.psychology_outlined,
                          size: 13,
                          color: mutedColor,
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.isThinking ? 'Thinking...' : 'Thought process',
                  style: TextStyle(
                    fontSize: 12,
                    color: mutedColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: mutedColor,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6, top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: mutedColor, width: 2)),
            ),
            child: Text(
              widget.thinking,
              style: TextStyle(
                fontSize: 12.5,
                color: mutedColor,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 150),
        ),
      ],
    );
  }
}
