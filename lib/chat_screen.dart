// chat_screen.dart
//
// Full offline chat UI with:
//   - Claude-inspired welcome screen on first open (time-of-day greeting)
//   - Model switcher in AppBar (1.5B / 4B / Auto Switch)
//   - Wider chat bubbles so tables render properly
//   - Em-dash replaced with hyphen in all user-facing text

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:wakelock_plus/wakelock_plus.dart';

import 'chat_message.dart';
import 'gpt2_engine.dart';
import 'markdown_renderer.dart';
import 'model_loader.dart';

// ---------------------------------------------------------------------------
// App logo (header wordmark)
// ---------------------------------------------------------------------------

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: onSurface,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Clean Spirit ',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: 'AI',
                style: TextStyle(
                  color: accent,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Model switcher (AppBar action)
// ---------------------------------------------------------------------------

class _ModelSwitcher extends StatelessWidget {
  final ActiveModel current;
  final bool has1_5b;
  final bool has4b;
  final ValueChanged<ActiveModel> onChanged;

  const _ModelSwitcher({
    required this.current,
    required this.has1_5b,
    required this.has4b,
    required this.onChanged,
  });

  String get _label {
    switch (current) {
      case ActiveModel.fast:
        return '1.5B';
      case ActiveModel.accurate:
        return '4B';
      case ActiveModel.auto:
        return 'Auto';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<ActiveModel>(
        tooltip: 'Switch model',
        initialValue: current,
        onSelected: onChanged,
        itemBuilder: (context) {
          final items = <PopupMenuEntry<ActiveModel>>[];

          if (has1_5b) {
            items.add(PopupMenuItem(
              value: ActiveModel.fast,
              child: _ModelMenuItem(
                label: 'QWEN2.5 1.5B',
                subtitle: 'Faster, Less Accurate',
                icon: Icons.bolt,
                selected: current == ActiveModel.fast,
              ),
            ));
          }

          if (has4b) {
            items.add(PopupMenuItem(
              value: ActiveModel.accurate,
              child: _ModelMenuItem(
                label: 'QWEN3 4B',
                subtitle: 'Slower, More Accurate',
                icon: Icons.psychology,
                selected: current == ActiveModel.accurate,
              ),
            ));
          }

          if (has1_5b && has4b) {
            if (items.isNotEmpty) items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(
              value: ActiveModel.auto,
              child: _ModelMenuItem(
                label: 'Auto Switch',
                subtitle: '1.5B drafts, 4B patches facts',
                icon: Icons.swap_horiz,
                selected: current == ActiveModel.auto,
              ),
            ));
          }

          return items;
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.memory, size: 14, color: accent),
              const SizedBox(width: 4),
              Text(
                _label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 14, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelMenuItem extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;

  const _ModelMenuItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Row(
      children: [
        Icon(icon, size: 20, color: selected ? accent : null),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : null,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        if (selected) Icon(Icons.check, size: 16, color: accent),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome screen (shown when chat is empty)
// ---------------------------------------------------------------------------

class _WelcomeView extends StatelessWidget {
  final bool isGenerating;
  final TextEditingController inputController;
  final VoidCallback onSend;

  const _WelcomeView({
    required this.isGenerating,
    required this.inputController,
    required this.onSend,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening'; // covers 17:00 onwards and late night
  }

  static const _suggestions = [
    ('Explain quantum entanglement simply', Icons.science_outlined),
    ('Write a haiku about rain', Icons.edit_outlined),
    ('What is 17 x 34?', Icons.calculate_outlined),
    ('Tips for better sleep', Icons.bedtime_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting
                Text(
                  '$_greeting.',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'How can I help you today?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 40),

                // Suggestion chips
                Text(
                  'Try asking',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _suggestions.map((s) {
                    final (label, icon) = s;
                    return Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          inputController.text = label;
                          onSend();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16, color: accent),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),

                // Offline badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, size: 13, color: Colors.green),
                          SizedBox(width: 5),
                          Text(
                            '100% on-device - no data sent anywhere',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _InputBar(
          controller: inputController,
          isGenerating: isGenerating,
          onSend: onSend,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar (shared between welcome and chat)
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.isGenerating,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isGenerating,
                maxLines: 6,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message Clean Spirit AI...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton.filled(
                onPressed: isGenerating ? null : onSend,
                icon: isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main chat screen
// ---------------------------------------------------------------------------

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _LoadState { loading, ready, error }

class _ChatScreenState extends State<ChatScreen> {
  final _engine = Gpt2Engine();
  final _messages = <ChatTurn>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  _LoadState _loadState = _LoadState.loading;
  String? _errorText;
  bool _isGenerating = false;

  // Track which model ran the last response (for auto-switch display)
  ModelVariant? _lastUsedVariant;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _engine.initialize();
      setState(() => _loadState = _LoadState.ready);
    } catch (e) {
      setState(() {
        _loadState = _LoadState.error;
        _errorText = e is ModelNotFoundException
            ? e.toString()
            : 'Failed to load the model: $e';
      });
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    final (stream, variant) = _engine.sendMessageWithVariant(text);

    setState(() {
      _messages.add(ChatTurn(role: ChatRole.user, text: text));
      _messages.add(ChatTurn(
        role: ChatRole.assistant,
        text: '',
        isStreaming: true,
      ));
      _isGenerating = true;
      _lastUsedVariant = variant;
    });
    _inputController.clear();
    _scrollToBottom();

    // Keep screen on for the full generation - can take 30-90s on 4B
    await WakelockPlus.enable();

    var raw = '';

    try {
      await for (final token in stream) {
        raw += token;
        final cleaned = raw
            .replaceAll('\u2014', ' - ')  // em dash
            .replaceAll('\u2013', ' - '); // en dash
        final split = _splitThinking(cleaned);
        setState(() {
          _messages.last.thinking = split.thinking;
          _messages.last.text = split.answer;
          // keep raw in sync for final capture (em dashes already cleaned)
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _messages.last.text = 'Error generating reply: $e');
    } finally {
      setState(() {
        _messages.last = ChatTurn(
          role: ChatRole.assistant,
          text: _messages.last.text,
          thinking: _messages.last.thinking,
        );
        _isGenerating = false;
      });
      // Release wakelock - response is done
      WakelockPlus.disable();
    }
  }

  ({String thinking, String answer}) _splitThinking(String raw) {
    const openTag = '<think>';
    const closeTag = '</think>';

    final start = raw.indexOf(openTag);
    if (start == -1) return (thinking: '', answer: raw);

    final afterOpen = raw.substring(start + openTag.length);
    final end = afterOpen.indexOf(closeTag);
    if (end == -1) return (thinking: afterOpen.trimLeft(), answer: '');

    final thinking = afterOpen.substring(0, end).trim();
    final answer = afterOpen.substring(end + closeTag.length).trimLeft();
    return (thinking: thinking, answer: answer);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // safety release if widget destroyed mid-generation
    _engine.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _AppLogo(),
        actions: [
          if (_loadState == _LoadState.ready)
            _ModelSwitcher(
              current: _engine.activeModel,
              has1_5b: true, // always show; engine handles availability
              has4b: true,
              onChanged: (v) => setState(() => _engine.activeModel = v),
            ),
        ],
      ),
      body: switch (_loadState) {
        _LoadState.loading => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading model into memory...'),
              ],
            ),
          ),
        _LoadState.error => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 40, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(_errorText ?? 'Unknown error',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _loadState = _LoadState.loading);
                      _boot();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        _LoadState.ready => _buildChat(),
      },
    );
  }

  Widget _buildChat() {
    if (_messages.isEmpty) {
      return _WelcomeView(
        isGenerating: _isGenerating,
        inputController: _inputController,
        onSend: _send,
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            itemCount: _messages.length,
            itemBuilder: (context, i) => _MessageBubble(
              turn: _messages[i],
              isLast: i == _messages.length - 1,
              lastVariant: i == _messages.length - 1 ? _lastUsedVariant : null,
            ),
          ),
        ),
        _InputBar(
          controller: _inputController,
          isGenerating: _isGenerating,
          onSend: _send,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatefulWidget {
  final ChatTurn turn;
  final bool isLast;
  final ModelVariant? lastVariant;

  const _MessageBubble({
    required this.turn,
    required this.isLast,
    this.lastVariant,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
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

    // Wider bubbles: user 88%, assistant 94% of screen width
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  if (hasThinking)
                    _ThinkingPanel(
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
                                  // User bubbles: plain text
                                  ? Text(
                                      turn.text,
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    )
                                  // Assistant bubbles: full markdown
                                  : ChatMarkdown(
                                      data: turn.text,
                                      textColor: theme.colorScheme.onSurface,
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
          ),
          // Model label below the last assistant bubble
          if (!isUser &&
              widget.lastVariant != null &&
              widget.isLast &&
              turn.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                widget.lastVariant == ModelVariant.fast
                    ? 'QWEN2.5 1.5B'
                    : 'QWEN3 4B',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
// Thinking panel
// ---------------------------------------------------------------------------

class _ThinkingPanel extends StatefulWidget {
  final String thinking;
  final bool isThinking;

  const _ThinkingPanel({required this.thinking, required this.isThinking});

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  late bool _expanded = widget.isThinking;
  bool _manuallyToggled = false;

  @override
  void didUpdateWidget(covariant _ThinkingPanel oldWidget) {
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
