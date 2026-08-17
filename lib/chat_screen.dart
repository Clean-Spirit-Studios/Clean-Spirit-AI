// chat_screen.dart
//
// Full offline chat UI for Clean Spirit AI.
//
// Features:
//   - Dual engine: Gemma 4 E2B/E4B (LiteRT GPU) and Qwen3 4B (GGUF CPU)
//   - Redesigned AppBar: centered title, hamburger drawer (left), ghost incognito (right)
//   - Model selector pill below the title in the AppBar
//   - History drawer with persistent past conversations (SharedPreferences)
//   - Incognito mode - conversations in this mode are never saved
//   - Background model loading with an interactive chat UI from first frame
//   - Image attachment (camera / gallery) - LiteRT vision path
//   - Document attachment (PDF / DOCX / text) - extracted and injected as context
//   - Claude-inspired welcome screen with time-of-day greeting
//   - Wider chat bubbles so tables render properly
//   - Hyphens instead of em dashes in all user-facing text

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'attachment_service.dart';
import 'chat_message.dart';
import 'conversation_store.dart';
import 'document_extractor.dart';
import 'dual_engine.dart';
import 'litert_engine.dart';
import 'model_loader.dart';
import 'settings_screen.dart';
import 'widgets/app_logo.dart';
import 'widgets/ghost_icon.dart';
import 'widgets/model_switcher.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/welcome_view.dart';
import 'widgets/history_drawer.dart';
import 'widgets/raptor_loading_screen.dart';
import 'utils/text_utils.dart';

// ---------------------------------------------------------------------------
// App logo (unchanged)
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
  bool get _isModelLoading => _loadState == _LoadState.loading;
  bool _isReloadingBackend = false;
  String? _loadStatusMessage;
  DateTime? _loadStartedAt;

  // Attachment state
  String? _pendingImagePath;
  String? _pendingDocText;
  String? _pendingDocName;

  // Conversation history (role/content pairs for LiteRT context)
  final List<Map<String, String>> _history = [];

  // Feature 2 - incognito mode and session persistence
  bool _isIncognito = false;
  String _currentSessionId = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (mounted) {
      setState(() {
        _loadState = _LoadState.loading;
        _errorText = null;
        _loadStatusMessage = 'Loading model...';
        _loadStartedAt = DateTime.now();
      });
    }

    try {
      await _engine.initialize(
        onProgress: (progress) {
          if (!mounted) return;
          final percent = (progress * 100).round().clamp(0, 100);
          setState(() => _loadStatusMessage = 'Loading model - $percent%');
        },
        onStatusMessage: (message) {
          if (!mounted) return;
          setState(() => _loadStatusMessage = message);
        },
      );
      // Let the raptor complete at least one full 7-frame cycle before
      // transitioning, even when the model initializes very quickly.
      final startedAt = _loadStartedAt;
      if (startedAt != null) {
        const minimumAnimation = Duration(milliseconds: 777);
        final elapsed = DateTime.now().difference(startedAt);
        final remaining = minimumAnimation - elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }

      if (mounted) {
        setState(() {
          _loadState = _LoadState.ready;
          _loadStatusMessage = null;
          _loadStartedAt = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadState = _LoadState.error;
          _loadStatusMessage = null;
          _errorText = e is ModelNotFoundException
              ? e.toString()
              : 'Failed to load the model: $e';
        });
      }
    }
  }

  double? get _parsedProgress {
    final msg = _loadStatusMessage;
    if (msg == null) return null;
    final match = RegExp(r'(\d+)%').firstMatch(msg);
    if (match == null) return null;
    return int.parse(match.group(1)!) / 100.0;
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating || _isModelLoading) return;

    final imagePath = _pendingImagePath;
    final docText = _pendingDocText;
    final docName = _pendingDocName;

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
        final split = splitThinking(cleaned);
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

        // Feature 2 - persist conversation (skip in incognito mode)
        if (!_isIncognito) {
          if (_currentSessionId.isEmpty) {
            _currentSessionId =
                DateTime.now().millisecondsSinceEpoch.toString();
          }
          final firstUserMsg = _messages
              .firstWhere(
                (m) => m.role == ChatRole.user,
                orElse: () => ChatTurn(role: ChatRole.user, text: 'Chat'),
              )
              .text;
          final title = firstUserMsg.substring(
            0,
            firstUserMsg.length.clamp(0, 60),
          );
          await ConversationStore.saveSession(
            id: _currentSessionId,
            title: title,
            turns: List.from(_messages),
          );
        }
      }
      WakelockPlus.disable();
    }
  }

  // ---------------------------------------------------------------------------
  // Feature 2 - incognito toggle
  // ---------------------------------------------------------------------------

  void _toggleIncognito() {
    setState(() => _isIncognito = !_isIncognito);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isIncognito
              ? 'Incognito on - this conversation won\'t be saved'
              : 'Incognito off - conversations will be saved',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Feature 2 - history drawer
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Attachment handling
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
                  leading: Icon(Icons.photo_library_outlined, color: accent),
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
                  leading: Icon(Icons.description_outlined, color: accent),
                  title: const Text('Document'),
                  subtitle: const Text('PDF, DOCX, TXT, and more'),
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
          // Feature 3 - show a friendlier truncation notice
          if (raw.contains('[Document is large')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Large document - showing first 12k characters. Ask specific questions for best results.',
                ),
                duration: Duration(seconds: 4),
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

    setState(() {
      _isReloadingBackend = true;
      _loadStatusMessage = 'Switching Gemma backend...';
    });

    try {
      await _engine.switchLiteRtBackend(
        newMode,
        onStatus: (message) {
          if (!mounted) return;
          setState(() => _loadStatusMessage = message);
        },
        onProgress: (progress) {
          if (!mounted) return;
          final percent = (progress * 100).round().clamp(0, 100);
          setState(() => _loadStatusMessage = 'Reloading backend - $percent%');
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched Gemma to $newLabel backend.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backend switch failed - $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReloadingBackend = false;
          _loadStatusMessage = null;
        });
      }
    }
  }

  Future<void> _onModelChanged(ActiveModel model) async {
    if (model == _engine.activeModel) return;

    setState(() {
      _isReloadingBackend = true;
      _loadStatusMessage = 'Switching model...';
    });

    try {
      final ok = await _engine.switchToModel(
        model,
        onStatus: (message) {
          if (!mounted) return;
          setState(() => _loadStatusMessage = message);
        },
        onProgress: (progress) {
          if (!mounted) return;
          final percent = (progress * 100).round().clamp(0, 100);
          setState(() => _loadStatusMessage = 'Switching model - $percent%');
        },
      );

      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model switch failed. Using previous model.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model switch failed - $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReloadingBackend = false;
          _loadStatusMessage = null;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  void _newConversation() {
    setState(() {
      _messages.clear();
      _history.clear();
      _currentSessionId = '';
      _isIncognito = false;
    });
  }

  void _loadSession(String sessionId, List<ChatTurn> turns) {
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(turns);
      _currentSessionId = sessionId;
      _history
        ..clear()
        ..addAll(turns.map((t) => {
          'role': t.role.name,
          'content': t.text,
        }));
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    await ConversationStore.deleteSession(sessionId);
    if (mounted) setState(() {});
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      // Feature 2 - hamburger drawer with past conversations
      drawer: HistoryDrawer(
        onNewConversation: _newConversation,
        onLoadSession: _loadSession,
        onDeleteSession: _deleteSession,
        onOpenSettings: _openSettings,
      ),

      appBar: AppBar(
        // Feature 2 - hamburger on left (auto-inserted by Scaffold when drawer
        // is set), centered title column, ghost icon on right
        centerTitle: true,
        toolbarHeight: 72,
        // Override leading to keep default hamburger style consistent
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Past conversations',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(),
            if (_isReloadingBackend)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                    if (_loadStatusMessage != null) ...[
                      const SizedBox(width: 7),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          _loadStatusMessage!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else if (_loadState == _LoadState.ready) ...[
              const SizedBox(height: 4),
              ModelSwitcher(
                current: _engine.activeModel,
                hasGemma: _engine.hasGemma,
                hasGemmaE4b: _engine.hasGemmaE4b,
                hasQwen4b: _engine.hasQwen4b,
                isReloading: _isReloadingBackend,
                activeBackendLabel: _engine.activeBackendLabel,
                onModelChanged: _onModelChanged,
                onSwitchBackend: _switchBackend,
              ),
            ],
          ],
          ),
        ),
        actions: [
          // Feature 2 - ghost icon for incognito mode
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: _isIncognito ? 'Incognito - on' : 'Incognito - off',
              onPressed: _toggleIncognito,
              icon: GhostIcon(
                size: 22,
                color: _isIncognito
                    ? accent
                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),

      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _loadState == _LoadState.loading
            ? RaptorLoadingScreen(
                key: const ValueKey('raptor_loading'),
                statusMessage: _loadStatusMessage,
                progress: _parsedProgress,
              )
            : Column(
                key: const ValueKey('chat_body'),
                children: [
                  if (_loadState == _LoadState.error && _errorText != null)
                    _buildErrorBanner(),
                  Expanded(child: _buildChat()),
                ],
              ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return MaterialBanner(
      content: Text(_errorText ?? 'Failed to load model - tap to retry.'),
      leading: const Icon(Icons.error_outline),
      actions: [
        TextButton(
          onPressed: _boot,
          child: const Text('Retry'),
        ),
        TextButton(
          onPressed: () => setState(() => _errorText = null),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildChat() {
    if (_messages.isEmpty) {
      return WelcomeView(
        isGenerating: _isGenerating,
        isModelLoading: _isModelLoading,
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
        // Incognito banner
        if (_isIncognito)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GhostIcon(
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Incognito - this conversation won\'t be saved',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            itemCount: _messages.length,
            itemBuilder: (context, i) => MessageBubble(
              turn: _messages[i],
              isLast: i == _messages.length - 1,
            ),
          ),
        ),
        InputBar(
          controller: _inputController,
          isGenerating: _isGenerating,
          isModelLoading: _isModelLoading,
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

