// litert_engine.dart
//
// LiteRT-LM GPU inference engine for Clean Spirit AI.
// Ported from inference_android.dart in cross-platform-llm-client.
//
// Supports:
//   - GPU backend (fast, default) with CPU fallback
//   - GPU crash guard via SharedPreferences (prevents boot loops)
//   - Multimodal generation (image path sent with text prompt)
//   - Streaming token-by-token callbacks
//   - Gemma token garbage sanitization

import 'dart:async';
import 'dart:io';

import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_loader.dart';

// System prompt used for all LiteRT conversations
const _kSystemPrompt =
    'You are Clean Spirit AI, a friendly and helpful assistant. '
    'Keep replies concise and conversational - a few sentences is usually enough. '
    'Be warm and natural. '
    'Never use em dashes - use a hyphen or comma instead. '
    'When an image is attached, describe what you see and answer any related question. '
    'Skip unnecessary disclaimers.';

const _kPrefGpuPending = 'litert_gpu_load_pending';
const _kPrefGpuCrash = 'litert_gpu_crash_detected';
const _kPrefBackendMode = 'litert_backend_mode'; // 'gpu' | 'cpu'

enum LiteRtBackendMode { gpu, cpu }

class LiteRtEngine {
  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;
  StreamSubscription? _subscription;
  Timer? _idleTimer;
  void Function()? _onStop;

  bool _disposed = false;
  bool _hasLoadedModel = false;
  bool _isVisionEnabled = false;

  // Conversation bookkeeping (mirrors inference_android.dart)
  String? _convSystemPrompt;
  double? _convTemperature;
  bool _convHasMessages = false;

  // Exposed state
  bool get isLoaded => _hasLoadedModel;
  bool get isVisionEnabled => _isVisionEnabled;

  String _activeBackend = 'gpu'; // 'gpu' or 'cpu'
  String get activeBackend => _activeBackend;

  // ---------------------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------------------

  /// Load the Gemma model.
  ///
  /// Returns a record with [success], [message], and [backend] ('gpu'/'cpu').
  /// Handles the GPU crash-guard pattern so a crashed GPU load auto-falls
  /// back to CPU on the next launch.
  Future<({bool success, String message, String backend})> load({
    String? modelPath,
    int contextSize = 4096,
    LiteRtBackendMode? performanceMode,
    bool clearCache = false,
    bool enableVision = true,
    void Function(double)? onProgress,
  }) async {
    _disposed = false;

    final prefs = await SharedPreferences.getInstance();

    // --- GPU crash guard: detect previous crashed GPU load ---
    final hadPending = prefs.getBool(_kPrefGpuPending) ?? false;
    if (hadPending) {
      await prefs.setBool(_kPrefGpuPending, false);
      await prefs.setBool(_kPrefGpuCrash, true);
    }
    final crashDetected = prefs.getBool(_kPrefGpuCrash) ?? false;

    // --- Resolve backend mode ---
    LiteRtBackendMode resolvedMode;
    if (performanceMode != null) {
      resolvedMode = performanceMode;
    } else {
      final saved = prefs.getString(_kPrefBackendMode);
      resolvedMode = (saved == 'cpu' || crashDetected)
          ? LiteRtBackendMode.cpu
          : LiteRtBackendMode.gpu;
    }

    final liteRtBackend = resolvedMode == LiteRtBackendMode.gpu
        ? LiteLmBackend.gpu
        : LiteLmBackend.cpu;
    final backendLabel = liteRtBackend == LiteLmBackend.gpu ? 'GPU' : 'CPU';

    // --- Resolve model path ---
    final path = modelPath ?? await ModelLoader.resolveGemmaPath();

    // --- Load ---
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/litert_cache');

      onProgress?.call(0.05);

      if (clearCache && await cacheDir.exists()) {
        try {
          await cacheDir.delete(recursive: true);
        } catch (_) {}
      }
      await cacheDir.create(recursive: true);

      onProgress?.call(0.18);

      // Set GPU load pending flag BEFORE creating engine (crash guard)
      if (liteRtBackend == LiteLmBackend.gpu) {
        await prefs.setBool(_kPrefGpuPending, true);
      }

      _engine = await _createEngine(
        modelPath: path,
        contextSize: contextSize,
        cacheDir: cacheDir.path,
        backend: liteRtBackend,
        enableVision: enableVision,
      );
      _isVisionEnabled = enableVision;

      // GPU load succeeded - clear crash guard
      await prefs.setBool(_kPrefGpuPending, false);
      await prefs.setBool(_kPrefGpuCrash, false);

      _hasLoadedModel = true;
      _activeBackend = liteRtBackend == LiteLmBackend.gpu ? 'gpu' : 'cpu';
      onProgress?.call(0.95);

      print(
          '[LiteRtEngine] Loaded with $backendLabel backend, ctx=$contextSize, vision=$enableVision');

      return (
        success: true,
        message: 'Model loaded ($backendLabel backend).',
        backend: _activeBackend,
      );
    } catch (error) {
      await prefs.setBool(_kPrefGpuPending, false);
      print('[LiteRtEngine] Load failed: $error');

      final errorStr = error.toString();

      // Vision encoder signature mismatch - retry text-only
      if (enableVision && errorStr.contains('exactly one signature but got')) {
        print('[LiteRtEngine] Vision signature mismatch - retrying text-only');
        try {
          final tempDir = await getTemporaryDirectory();
          final cacheDir = Directory('${tempDir.path}/litert_cache');
          _engine = await _createEngine(
            modelPath: path,
            contextSize: contextSize,
            cacheDir: cacheDir.path,
            backend: liteRtBackend,
            enableVision: false,
          );
          _isVisionEnabled = false;
          _hasLoadedModel = true;
          _activeBackend =
              liteRtBackend == LiteLmBackend.gpu ? 'gpu' : 'cpu';
          onProgress?.call(0.95);
          return (
            success: true,
            message:
                'Model loaded (text-only - vision not supported by this file).',
            backend: _activeBackend,
          );
        } catch (fallback) {
          return (
            success: false,
            message: 'LiteRT load failed: $fallback',
            backend: '',
          );
        }
      }

      return (
        success: false,
        message: 'LiteRT load failed: $error',
        backend: '',
      );
    }
  }

  Future<LiteLmEngine> _createEngine({
    required String modelPath,
    required int contextSize,
    required String cacheDir,
    required LiteLmBackend backend,
    required bool enableVision,
  }) {
    return LiteLmEngine.create(
      LiteLmEngineConfig(
        modelPath: modelPath,
        backend: backend,
        cacheDir: cacheDir,
        visionBackend: enableVision ? LiteLmBackend.cpu : null,
        audioBackend: null,
        maxNumTokens: contextSize,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Generate
  // ---------------------------------------------------------------------------

  /// Generate a streaming response.
  ///
  /// [imagePath] - optional - triggers multimodal path.
  /// [onToken] - called for each streamed token chunk.
  /// Returns the complete response string.
  Future<String> generate({
    required String prompt,
    required List<Map<String, String>> history,
    String systemPrompt = _kSystemPrompt,
    int maxTokens = 1024,
    double temperature = 0.7,
    String? imagePath,
    void Function(String)? onToken,
  }) async {
    if (_engine == null) throw Exception('No LiteRT model loaded');

    await _subscription?.cancel();
    await _ensureConversation(
      prompt: prompt,
      history: history,
      systemPrompt: systemPrompt,
      temperature: temperature,
    );

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;
    bool hasVisibleOutput = false;
    var tokenCount = 0;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () => finish(buffer.toString());

    final hasImage = imagePath != null && imagePath.isNotEmpty;

    void handleDelta(String raw) {
      var text = _cleanChunk(raw);
      if (text.isEmpty) return;

      if (!hasVisibleOutput) {
        if (!_hasPrintableText(text)) return;
        text = text.trimLeft();
        hasVisibleOutput = true;
      }

      if (tokenCount == 0) {
        print(
            '[LiteRtEngine] ${hasImage ? "Multimodal" : "Text"} FIRST TOKEN received');
      }
      _convHasMessages = true;
      tokenCount++;
      buffer.write(text);
      onToken?.call(text);

      _idleTimer?.cancel();
      _idleTimer = Timer(
        Duration(seconds: hasImage ? 8 : 5),
        () {
          print('[LiteRtEngine] Idle timeout - $tokenCount chunks');
          finish(buffer.toString());
        },
      );
    }

    void handleError(Object error) {
      print('[LiteRtEngine] Stream error: $error');
      finish('ERROR: Generation failed - $error');
    }

    void handleDone() {
      _convHasMessages = true;
      print('[LiteRtEngine] Stream done - $tokenCount chunks');
      finish(buffer.toString());
    }

    if (hasImage) {
      final contents = <LiteLmContent>[
        LiteLmContent.text(prompt),
        LiteLmContent.imageFile(imagePath),
      ];
      _subscription = _conversation!
          .sendMultimodalMessageStream(contents)
          .listen(
            (delta) => handleDelta(delta.text),
            onError: handleError,
            onDone: handleDone,
          );

      // Prefill timeout (multimodal is slower)
      _idleTimer = Timer(const Duration(seconds: 90), () {
        if (tokenCount == 0) finish('ERROR: Model did not respond to image.');
      });
      Future.delayed(const Duration(seconds: 240), () {
        if (!completed) {
          final partial = buffer.toString();
          finish(partial.isEmpty ? 'ERROR: Generation timed out.' : partial);
        }
      });
    } else {
      _subscription = _conversation!.sendMessageStream(prompt).listen(
            (delta) => handleDelta(delta.text),
            onError: handleError,
            onDone: handleDone,
          );

      // Prefill timeout
      _idleTimer = Timer(const Duration(seconds: 60), () {
        if (tokenCount == 0) finish('ERROR: Model did not respond.');
      });
      Future.delayed(const Duration(seconds: 180), () {
        if (!completed) {
          final partial = buffer.toString();
          finish(partial.isEmpty ? 'ERROR: Generation timed out.' : partial);
        }
      });
    }

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Conversation management
  // ---------------------------------------------------------------------------

  Future<void> _ensureConversation({
    required String prompt,
    required List<Map<String, String>> history,
    required String systemPrompt,
    required double temperature,
  }) async {
    final hasHistory =
        history.any((m) => (m['content'] ?? '').isNotEmpty);

    final shouldReset = _conversation == null ||
        _convSystemPrompt != systemPrompt ||
        _convTemperature != temperature ||
        (_convHasMessages && !hasHistory);

    if (!shouldReset) return;

    try {
      await _conversation?.dispose();
    } catch (_) {}

    _conversation = await _engine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: systemPrompt,
        initialMessages: _buildInitialMessages(prompt, history),
        samplerConfig: LiteLmSamplerConfig(
          temperature: temperature,
          topK: 64,
          topP: 0.95,
        ),
      ),
    );

    _convSystemPrompt = systemPrompt;
    _convTemperature = temperature;
    _convHasMessages = hasHistory;
  }

  List<LiteLmMessage> _buildInitialMessages(
    String currentPrompt,
    List<Map<String, String>> history,
  ) {
    if (history.isEmpty) return const [];

    // Keep last 16 turns, exclude the current user prompt if it's the last
    var recent = history.length > 16
        ? history.sublist(history.length - 16)
        : List<Map<String, String>>.from(history);

    if (recent.isNotEmpty &&
        recent.last['role'] == 'user' &&
        recent.last['content'] == currentPrompt) {
      recent = recent.sublist(0, recent.length - 1);
    }

    return recent
        .where((m) => (m['content'] ?? '').trim().isNotEmpty)
        .map((m) {
      final content = m['content'] ?? '';
      return m['role'] == 'assistant'
          ? LiteLmMessage.model(content)
          : LiteLmMessage.user(content);
    }).toList();
  }

  Future<void> resetConversation() async {
    try {
      await _conversation?.dispose();
    } catch (_) {}
    _conversation = null;
    _convSystemPrompt = null;
    _convTemperature = null;
    _convHasMessages = false;
  }

  // ---------------------------------------------------------------------------
  // Stop / dispose
  // ---------------------------------------------------------------------------

  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCb = _onStop;
    _onStop = null;
    stopCb?.call();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _convHasMessages = true; // partial output counts
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    try {
      await _conversation?.dispose();
    } catch (_) {}
    try {
      if (_hasLoadedModel) await _engine?.dispose();
    } catch (_) {}
    _conversation = null;
    _engine = null;
    _hasLoadedModel = false;
    _convSystemPrompt = null;
    _convTemperature = null;
    _convHasMessages = false;
  }

  // ---------------------------------------------------------------------------
  // Backend persistence
  // ---------------------------------------------------------------------------

  /// Save the chosen backend mode to SharedPreferences so it survives restarts.
  static Future<void> saveBackendMode(LiteRtBackendMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPrefBackendMode, mode == LiteRtBackendMode.gpu ? 'gpu' : 'cpu');
    // Clear crash flag when user explicitly picks a backend
    if (mode == LiteRtBackendMode.gpu) {
      await prefs.setBool(_kPrefGpuCrash, false);
    }
  }

  static Future<LiteRtBackendMode> loadSavedBackendMode() async {
    final prefs = await SharedPreferences.getInstance();
    final crashDetected = prefs.getBool(_kPrefGpuCrash) ?? false;
    if (crashDetected) return LiteRtBackendMode.cpu;
    final saved = prefs.getString(_kPrefBackendMode);
    return saved == 'cpu' ? LiteRtBackendMode.cpu : LiteRtBackendMode.gpu;
  }

  // ---------------------------------------------------------------------------
  // Token cleanup helpers (ported verbatim from inference_android.dart)
  // ---------------------------------------------------------------------------

  String _cleanChunk(String text) {
    return _sanitizeGemmaGarbage(
      text
          .replaceAll(
              RegExp(
                  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
              '')
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .replaceAll('\uFFFD', '')
          .replaceAll('<|endoftext|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|end|>', ''),
    );
  }

  /// Strip Gemma garbage tokens that leak when Q4_K_M dequant is corrupt
  /// on Google Tensor SoC. Harmless on devices that don't produce them.
  /// NOTE: Do NOT trim() - SentencePiece tokens rely on leading spaces.
  String _sanitizeGemmaGarbage(String text) {
    return text
        .replaceAll(RegExp(r'<unused\d+>'), '')
        .replaceAll(RegExp(r'\[@BOS@\]'), '')
        .replaceAll('<bos>', '')
        .replaceAll('<mask>', '')
        .replaceAll('<pad>', '')
        .replaceAll('<unk>', '')
        .replaceAll('<s>', '')
        .replaceAll('</s>', '');
  }

  bool _hasPrintableText(String text) {
    for (final rune in text.runes) {
      if (rune > 32 &&
          rune != 0x7F &&
          rune != 0x200B &&
          rune != 0x200C &&
          rune != 0x200D &&
          rune != 0xFEFF &&
          rune != 0xFFFD) {
        return true;
      }
    }
    return false;
  }
}
