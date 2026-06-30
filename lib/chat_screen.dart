// chat_screen.dart
//
// Minimal offline chat UI. Three states: loading the model, ready to chat,
// or failed to load (most commonly: the .gguf file hasn't been added yet —
// see README.md "Adding the model").

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'chat_message.dart';
import 'gpt2_engine.dart';
import 'model_loader.dart';

/// Bold, stylish wordmark for the app header — used instead of a plain
/// Text widget. Built entirely from Flutter styling (no image asset),
/// so it stays crisp at any size/density and needs no extra asset
/// pipeline. The small rounded-square accent mark nods at the "screen
/// eye" detail on the app's launcher icon (a black-and-white smiling
/// robot face) for a little visual continuity between launcher and
/// in-app branding.
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
        // Small accent mark — two rounded squares stacked to suggest the
        // robot-face "eyes" motif from the app icon, in miniature.
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

    setState(() {
      _messages.add(ChatTurn(role: ChatRole.user, text: text));
      _messages.add(ChatTurn(role: ChatRole.assistant, text: '', isStreaming: true));
      _isGenerating = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await for (final token in _engine.sendMessage(text)) {
        setState(() => _messages.last.text += token);
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _messages.last.text = 'Error generating reply: $e');
    } finally {
      setState(() {
        _messages.last = ChatTurn(
          role: ChatRole.assistant,
          text: _messages.last.text,
        );
        _isGenerating = false;
      });
    }
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
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 16),
                    SizedBox(width: 4),
                    Text('On-device', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
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
                Text('Loading model into memory…'),
              ],
            ),
          ),
        _LoadState.error => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(_errorText ?? 'Unknown error', textAlign: TextAlign.center),
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
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, i) => _MessageBubble(turn: _messages[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_isGenerating,
                    decoration: const InputDecoration(
                      hintText: 'Message Clean Spirit AI…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isGenerating ? null : _send,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A chat message bubble that copies its text to the clipboard when
/// tapped. Briefly shows a checkmark over the bubble and a snackbar as
/// feedback so the tap doesn't feel like it did nothing. Empty/streaming
/// bubbles (still showing "…") are not copyable, since there's nothing
/// useful to copy yet.
class _MessageBubble extends StatefulWidget {
  final ChatTurn turn;
  const _MessageBubble({required this.turn});

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _copy(context),
        // Long-press also works (and feels more natural to anyone used to
        // the OS-standard "press and hold to copy" gesture), in addition
        // to the simple tap this was asked for.
        onLongPress: () => _copy(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: _justCopied
                ? (isUser
                    ? theme.colorScheme.primary.withValues(alpha: 0.7)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.7))
                : (isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  turn.text.isEmpty ? '…' : turn.text,
                  style: TextStyle(
                    color: isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
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
        ),
      ),
    );
  }
}
