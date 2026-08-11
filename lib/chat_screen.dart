// chat_screen.dart
//
// Full offline chat UI for Clean Spirit AI.
//
// Features:
//   - Dual engine: Gemma 4 E2B (LiteRT GPU) and Qwen3 4B (GGUF CPU)
//   - Model switcher in AppBar with clear architecture labels
//   - Image attachment (camera / gallery) - LiteRT vision path
//   - Document attachment (PDF / DOCX / text) - extracted and injected as context
//   - Claude-inspired welcome screen with time-of-day greeting
//   - Wider chat bubbles so tables render properly
//   - Em-dash replaced with hyphen in all user-facing text

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'attachment_service.dart';
import 'chat_message.dart';
import 'document_extractor.dart';
import 'dual_engine.dart';
import 'litert_engine.dart';
import 'markdown_renderer.dart';
import 'model_loader.dart';

// ---------------------------------------------------------------------------
// App logo
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
// Model switcher - shows both engines with architecture labels
// ---------------------------------------------------------------------------

class _ModelSwitcher extends StatelessWidget {
  final ActiveModel current;
  final bool hasGemma;
  final bool hasQwen4b;
  final bool isReloading;
  final String activeBackendLabel; // 'GPU' | 'CPU'
  final ValueChanged<ActiveModel> onModelChanged;
  final VoidCallback onSwitchBackend;

  const _ModelSwitcher({
    required this.current,
    required this.hasGemma,
    required this.hasQwen4b,
    required this.isReloading,
    required this.activeBackendLabel,
    required this.onModelChanged,
    required this.onSwitchBackend,
  });

  String get _pillLabel {
    switch (current) {
      case ActiveModel.gemma:
        return 'Gemma E2B';
      case ActiveModel.qwen4b:
        return 'Qwen3 4B';
      case ActiveModel.auto:
        return 'Auto';
    }
  }

  String get _backendSuffix {
    if (current == ActiveModel.qwen4b) return 'CPU';
    return activeBackendLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    if (isReloading) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Switch model or backend',
        onSelected: (value) {
          if (value == 'switch_backend') {
            onSwitchBackend();
          } else {
            final model = switch (value) {
              'gemma' => ActiveModel.gemma,
              'qwen4b' => ActiveModel.qwen4b,
              _ => ActiveModel.auto,
            };
            onModelChanged(model);
          }
        },
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String>>[];

          if (hasGemma) {
            items.add(PopupMenuItem(
              value: 'gemma',
              child: _ModelMenuItem(
                label: 'Gemma 4 E2B - LiteRT',
                subtitle: 'GPU-accelerated - vision-capable - fast',
                archBadge: 'LiteRT',
                archColor: Colors.tealAccent.shade400,
                icon: Icons.bolt,
                selected: current == ActiveModel.gemma,
              ),
            ));
          }

          if (hasQwen4b) {
            items.add(PopupMenuItem(
              value: 'qwen4b',
              child: _ModelMenuItem(
                label: 'Qwen3 4B - GGUF',
                subtitle: 'CPU-based - thorough reasoning',
                archBadge: 'GGUF',
                archColor: Colors.orangeAccent.shade400,
                icon: Icons.psychology,
                selected: current == ActiveModel.qwen4b,
              ),
            ));
          }

          if (hasGemma && hasQwen4b) {
            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(
              value: 'auto',
              child: _ModelMenuItem(
                label: 'Auto',
                subtitle: 'Defaults to Gemma (LiteRT GPU)',
                archBadge: 'Auto',
                archColor: accent,
                icon: Icons.swap_horiz,
                selected: current == ActiveModel.auto,
              ),
            ));
          }

          // Backend toggle for Gemma - only when Gemma is active
          if (hasGemma &&
              (current == ActiveModel.gemma ||
                  current == ActiveModel.auto)) {
            items.add(const PopupMenuDivider());
            final isGpu = activeBackendLabel == 'GPU';
            items.add(PopupMenuItem(
              value: 'switch_backend',
              child: _ModelMenuItem(
                label: isGpu
                    ? 'Switch Gemma to CPU (safe)'
                    : 'Switch Gemma to GPU (fast)',
                subtitle: isGpu
                    ? 'Currently GPU - tap to use CPU instead'
                    : 'Currently CPU - tap to use GPU instead',
                archBadge: activeBackendLabel,
                archColor: isGpu
                    ? Colors.greenAccent.shade400
                    : Colors.grey.shade400,
                icon:
                    isGpu ? Icons.memory : Icons.developer_board,
                selected: false,
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
                _pillLabel,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '- $_backendSuffix',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
  final String archBadge;
  final Color archColor;
  final IconData icon;
  final bool selected;

  const _ModelMenuItem({
    required this.label,
    required this.subtitle,
    required this.archBadge,
    required this.archColor,
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? accent : null,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: archColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      archBadge,
                      style: TextStyle(
                        fontSize: 9,
                        color: archColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
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
// Welcome screen
// ---------------------------------------------------------------------------

class _WelcomeView extends StatelessWidget {
  final bool isGenerating;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onAttachTap;
  final String? pendingImagePath;
  final String? pendingDocName;
  final VoidCallback onClearAttachment;

  const _WelcomeView({
    required this.isGenerating,
    required this.inputController,
    required this.onSend,
    required this.onAttachTap,
    required this.pendingImagePath,
    required this.pendingDocName,
    required this.onClearAttachment,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
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
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'TRY ASKING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 1.0,
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
                          Icon(Icons.wifi_off,
                              size: 13, color: Colors.green),
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
          onAttachTap: onAttachTap,
          pendingImagePath: pendingImagePath,
          pendingDocName: pendingDocName,
          onClearAttachment: onClearAttachment,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar with attachment support
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onAttachTap;
  final String? pendingImagePath;
  final String? pendingDocName;
  final VoidCallback onClearAttachment;

  const _InputBar({
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    required this.onAttachTap,
    required this.pendingImagePath,
    required this.pendingDocName,
    required this.onClearAttachment,
  });

  bool get _hasAttachment =>
      pendingImagePath != null || pendingDocName != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attachment preview chip
          if (_hasAttachment)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: _AttachmentChip(
                imagePath: pendingImagePath,
                docName: pendingDocName,
                onDismiss: onClearAttachment,
              ),
            ),

          // Input row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attach button
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IconButton(
                    onPressed: isGenerating ? null : onAttachTap,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                    tooltip: 'Attach image or document',
                  ),
                ),
                const SizedBox(width: 4),
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachment preview chip
// ---------------------------------------------------------------------------

class _AttachmentChip extends StatelessWidget {
  final String? imagePath;
  final String? docName;
  final VoidCallback onDismiss;

  const _AttachmentChip({
    required this.imagePath,
    required this.docName,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(imagePath!),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Image attached',
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (docName != null) ...[
              Icon(Icons.description_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  docName!.length > 24
                      ? '${docName!.substring(0, 21)}...'
                      : docName!,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: accent),
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
  final _engine = DualEngine();
  final _messages = <ChatTurn>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  _LoadState _loadState = _LoadState.loading;
  String? _errorText;
  bool _isGenerating = false;
  bool _isReloadingBackend = false;
  double _loadProgress = 0.0;
  String _loadStatusMessage = 'Starting up...';

  // Attachment state
  String? _pendingImagePath;
  String? _pendingDocText;
  String? _pendingDocName;

  // Conversation history (role/content pairs for LiteRT context)
  final List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loadState = _LoadState.loading;
      _loadProgress = 0.0;
      _loadStatusMessage = 'Starting up...';
    });

    try {
      await _engine.initialize(
        onProgress: (p) {
          if (mounted) setState(() => _loadProgress = p);
        },
        onStatusMessage: (msg) {
          if (mounted) setState(() => _loadStatusMessage = msg);
        },
      );
      if (mounted) setState(() => _loadState = _LoadState.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadState = _LoadState.error;
          _errorText = e is ModelNotFoundException
              ? e.toString()
              : 'Failed to load the model: $e';
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    final imagePath = _pendingImagePath;
    final docText = _pendingDocText;
    final docName = _pendingDocName;

    // Vision guard: warn if user tries image on GGUF model
    if (imagePath != null && !_engine.isVisionAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Image understanding needs Gemma (LiteRT). Switch to Gemma or Auto.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final (stream, modelLabel) = _engine.sendMessageWithLabel(
      text,
      imagePath: imagePath,
      docText: docText,
      history: List.from(_history),
    );

    // Add user turn to history
    _history.add({'role': 'user', 'content': text});

    setState(() {
      _messages.add(ChatTurn(
        role: ChatRole.user,
        text: text,
        imagePath: imagePath,
        documentName: docName,
      ));
      _messages.add(ChatTurn(
        role: ChatRole.assistant,
        text: '',
        isStreaming: true,
        modelLabel: modelLabel,
      ));
      _isGenerating = true;
      _pendingImagePath = null;
      _pendingDocText = null;
      _pendingDocName = null;
    });
    _inputController.clear();
    _scrollToBottom();

    await WakelockPlus.enable();

    var raw = '';

    try {
      await for (final token in stream) {
        raw += token;
        final cleaned = raw
            .replaceAll('\u2014', ' - ')
            .replaceAll('\u2013', ' - ');
        final split = _splitThinking(cleaned);
        if (mounted) {
          setState(() {
            _messages.last.thinking = split.thinking;
            _messages.last.text = split.answer;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.last.text = 'Error generating reply: $e');
      }
    } finally {
      if (mounted) {
        // Add assistant turn to history
        _history.add({
          'role': 'assistant',
          'content': _messages.last.text,
        });

        setState(() {
          _messages.last = ChatTurn(
            role: ChatRole.assistant,
            text: _messages.last.text,
            thinking: _messages.last.thinking,
            modelLabel: modelLabel,
          );
          _isGenerating = false;
        });
      }
      WakelockPlus.disable();
    }
  }

  // ---------------------------------------------------------------------------
  // Attachment handling - bottom sheet routes to correct picker
  // ---------------------------------------------------------------------------

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final accent = Theme.of(ctx).colorScheme.primary;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    'Attach to message',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      Icon(Icons.photo_library_outlined, color: accent),
                  title: const Text('Gallery'),
                  subtitle: const Text('Pick an image from your photos'),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleAttachAction('gallery');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt_outlined, color: accent),
                  title: const Text('Camera'),
                  subtitle: const Text('Take a photo'),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleAttachAction('camera');
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.description_outlined, color: accent),
                  title: const Text('Document'),
                  subtitle:
                      const Text('PDF, DOCX, TXT, and more'),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleAttachAction('document');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAttachAction(String type) async {
    if (type == 'gallery') {
      final path = await AttachmentService.pickImageFromGallery();
      if (path != null && mounted) {
        setState(() {
          _pendingImagePath = path;
          _pendingDocText = null;
          _pendingDocName = null;
        });
      }
    } else if (type == 'camera') {
      final path = await AttachmentService.pickImageFromCamera();
      if (path != null && mounted) {
        setState(() {
          _pendingImagePath = path;
          _pendingDocText = null;
          _pendingDocName = null;
        });
      }
    } else if (type == 'document') {
      final picked = await AttachmentService.pickDocument();
      if (picked == null) return;

      try {
        final raw =
            await DocumentExtractor.extractText(picked.path, picked.ext);
        if (mounted) {
          setState(() {
            _pendingDocText = raw;
            _pendingDocName = picked.name;
            _pendingImagePath = null;
          });
          if (raw.contains('[Document trimmed')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Document trimmed to first 3000 characters to fit context.'),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not read document: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Backend / model switching
  // ---------------------------------------------------------------------------

  Future<void> _switchBackend() async {
    if (!_engine.hasGemma) return;

    final current = _engine.activeBackendLabel;
    final newMode = current == 'GPU'
        ? LiteRtBackendMode.cpu
        : LiteRtBackendMode.gpu;
    final newLabel = newMode == LiteRtBackendMode.gpu ? 'GPU' : 'CPU';

    setState(() => _isReloadingBackend = true);

    await _engine.switchLiteRtBackend(
      newMode,
      onStatus: (s) {
        if (mounted) setState(() => _loadStatusMessage = s);
      },
    );

    if (mounted) {
      setState(() => _isReloadingBackend = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched Gemma to $newLabel backend.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onModelChanged(ActiveModel model) async {
    if (model == _engine.activeModel) return;

    setState(() {
      _isReloadingBackend = true;
      _loadStatusMessage = 'Switching model...';
    });

    final ok = await _engine.switchToModel(
      model,
      onStatus: (s) {
        if (mounted) setState(() => _loadStatusMessage = s);
      },
    );

    if (mounted) {
      setState(() => _isReloadingBackend = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model switch failed. Using previous model.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  void _clearAttachment() {
    setState(() {
      _pendingImagePath = null;
      _pendingDocText = null;
      _pendingDocName = null;
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _engine.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _AppLogo(),
        actions: [
          if (_loadState == _LoadState.ready)
            _ModelSwitcher(
              current: _engine.activeModel,
              hasGemma: _engine.hasGemma,
              hasQwen4b: _engine.hasQwen4b,
              isReloading: _isReloadingBackend,
              activeBackendLabel: _engine.activeBackendLabel,
              onModelChanged: _onModelChanged,
              onSwitchBackend: _switchBackend,
            ),
        ],
      ),
      body: switch (_loadState) {
        _LoadState.loading => _buildLoadingState(),
        _LoadState.error => _buildErrorState(),
        _LoadState.ready => _buildChat(),
      },
    );
  }

  Widget _buildLoadingState() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _loadStatusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            if (_loadProgress > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _loadProgress,
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  color: accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_loadProgress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
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
              onPressed: _boot,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat() {
    if (_messages.isEmpty) {
      return _WelcomeView(
        isGenerating: _isGenerating,
        inputController: _inputController,
        onSend: _send,
        onAttachTap: _showAttachSheet,
        pendingImagePath: _pendingImagePath,
        pendingDocName: _pendingDocName,
        onClearAttachment: _clearAttachment,
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
            ),
          ),
        ),
        _InputBar(
          controller: _inputController,
          isGenerating: _isGenerating,
          onSend: _send,
          onAttachTap: _showAttachSheet,
          pendingImagePath: _pendingImagePath,
          pendingDocName: _pendingDocName,
          onClearAttachment: _clearAttachment,
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

  const _MessageBubble({required this.turn, required this.isLast});

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
                  // Image thumbnail (user bubble - at top, rounded corners)
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
                        // Vision badge
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

                        // Document chip
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

                        // Thinking panel (assistant)
                        if (hasThinking)
                          _ThinkingPanel(
                            thinking: turn.thinking,
                            isThinking: isThinking,
                          ),

                        // Main text
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
                                              ? theme
                                                  .colorScheme.onPrimary
                                              : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      )
                                    : isUser
                                        ? Text(
                                            turn.text,
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme.onPrimary,
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

          // Model label under last assistant bubble
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
              border: Border(
                  left: BorderSide(color: mutedColor, width: 2)),
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
