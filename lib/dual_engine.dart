// dual_engine.dart
//
// Unified engine that coordinates three model options across two architectures:
//
//   Gemma 4 E2B Instruct (LiteRT-LM)
//     - GPU-accelerated via Google LiteRT
//     - Vision-capable (can read images)
//     - Fast, ideal for everyday chat and multimodal tasks
//
//   Gemma 4 E4B Instruct (LiteRT-LM)
//     - Uses the exact same LiteRT engine/path as E2B
//     - GPU-accelerated and vision-capable
//     - Higher quality, with a higher RAM requirement
//
//   Qwen3 4B Instruct (GGUF / llama_cpp_dart)
//     - CPU-based inference
//     - Strong at detailed reasoning, math, and coding
//     - No vision support
//
// KEY BEHAVIOUR:
//   - initialize() loads ONLY the model that will actually be used on startup
//     (based on saved preference). The other model is loaded lazily on first
//     switch. This keeps startup fast - you don't wait for both 2.5GB models.
//   - Auto mode prefers E4B, then E2B, then Qwen3.
//   - Switching models at runtime loads that model if not yet loaded.

import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'litert_engine.dart';
import 'model_loader.dart';

// ---------------------------------------------------------------------------
// Active model selection
// ---------------------------------------------------------------------------

enum ActiveModel {
  /// Gemma 4 E2B via LiteRT - GPU, fast, vision-capable
  gemma,

  /// Gemma 4 E4B via LiteRT - GPU, higher quality, vision-capable
  gemmaE4b,

  /// Qwen3 4B via GGUF/llama.cpp - CPU, thorough answers
  qwen4b,

  /// Auto: uses E4B, then E2B, then Qwen3 as fallback
  auto,
}

// ---------------------------------------------------------------------------
// System prompts
// ---------------------------------------------------------------------------

const _kGemmaSystemPrompt =
    'You are Clean Spirit AI, a friendly and helpful assistant. '
    'Keep replies concise and conversational - a few sentences is usually enough. '
    'Be warm and natural. '
    'Never use em dashes - use a hyphen or comma instead. '
    'When an image is attached, describe what you see and answer any related question. '
    'Skip unnecessary disclaimers.';

const _kQwenSystemPrompt =
    'You are Clean Spirit AI, a helpful and accurate assistant. '
    'Give thorough, well-reasoned answers. '
    'Never use em dashes - use a hyphen or comma instead. '
    'Skip unnecessary disclaimers.';

// ---------------------------------------------------------------------------
// DualEngine
// ---------------------------------------------------------------------------

class DualEngine {
  // LiteRT engine for Gemma
  final LiteRtEngine _liteRtEngine = LiteRtEngine();

  // GGUF engine for Qwen3 4B
  LlamaEngine? _qwenEngine;
  EngineChat? _qwenChat;

  // Which models are present on disk
  bool _hasGemma = false;
  bool _hasGemmaE4b = false;
  bool _hasQwen4b = false;

  // Which models have been loaded into memory
  bool _gemmaLoaded = false;
  bool _gemmaE4bLoadedAsActive = false;
  bool _qwenLoaded = false;

  ActiveModel _activeModel = ActiveModel.auto;
  ActiveModel get activeModel => _activeModel;

  bool get hasGemma => _hasGemma;
  bool get hasGemmaE4b => _hasGemmaE4b;
  bool get hasQwen4b => _hasQwen4b;
  bool get isReady =>
      _gemmaLoaded || _gemmaE4bLoadedAsActive || _qwenLoaded;

  String get activeModelLabel {
    switch (_activeModel) {
      case ActiveModel.gemma:
        return 'Gemma E2B - LiteRT';
      case ActiveModel.gemmaE4b:
        return 'Gemma E4B - LiteRT';
      case ActiveModel.qwen4b:
        return 'Qwen3 4B - GGUF';
      case ActiveModel.auto:
        return _autoLiteRtLabel();
    }
  }

  String get activeBackendLabel {
    if (_activeModel == ActiveModel.qwen4b) return 'CPU';
    if (_activeModel == ActiveModel.gemma ||
        _activeModel == ActiveModel.gemmaE4b) {
      return _liteRtEngine.activeBackend.toUpperCase();
    }
    // auto
    return (_hasGemmaE4b || _hasGemma)
        ? _liteRtEngine.activeBackend.toUpperCase()
        : 'CPU';
  }

  bool get isVisionAvailable {
    final useLiteRt = _activeModel == ActiveModel.gemma ||
        _activeModel == ActiveModel.gemmaE4b ||
        (_activeModel == ActiveModel.auto && (_hasGemma || _hasGemmaE4b));
    return useLiteRt && _liteRtEngine.isVisionEnabled;
  }

  String _autoLiteRtLabel() {
    if (_hasGemmaE4b) return 'Gemma E4B - LiteRT';
    if (_hasGemma) return 'Gemma E2B - LiteRT';
    return 'Qwen3 4B - GGUF';
  }

  static const _kPrefModel = 'selected_model_v2';

  // -------------------------------------------------------------------------
  // Initialise - loads ONLY the model selected (or auto-selected) on startup
  // -------------------------------------------------------------------------

  /// [onProgress] receives a value 0.0-1.0 during model loading.
  /// [onStatusMessage] receives status strings like "Loading Gemma on GPU..."
  Future<void> initialize({
    void Function(double)? onProgress,
    void Function(String)? onStatusMessage,
  }) async {
    _hasGemma = await ModelLoader.isGemmaDownloaded();
    _hasGemmaE4b = await ModelLoader.isGemmaE4bDownloaded();
    _hasQwen4b = await ModelLoader.isQwen4bDownloaded();

    if (!_hasGemma && !_hasGemmaE4b && !_hasQwen4b) {
      throw ModelNotFoundException('No model found on device');
    }

    // Restore saved preference (or pick the best default)
    final saved = await _loadSavedModel();
    if (saved != null) {
      final valid = switch (saved) {
        ActiveModel.gemma => _hasGemma,
        ActiveModel.gemmaE4b => _hasGemmaE4b,
        ActiveModel.qwen4b => _hasQwen4b,
        ActiveModel.auto => true,
      };
      _activeModel = valid ? saved : _defaultModel();
    } else {
      _activeModel = _defaultModel();
    }

    final liteRtVariant = _resolveLiteRtVariant();
    final shouldLoadLiteRt = liteRtVariant != null;
    final shouldLoadQwen = _hasQwen4b &&
        (_activeModel == ActiveModel.qwen4b ||
            (_activeModel == ActiveModel.auto && liteRtVariant == null));

    if (shouldLoadLiteRt) {
      final backendMode = await LiteRtEngine.loadSavedBackendMode();
      final backendLabel =
          backendMode == LiteRtBackendMode.gpu ? 'GPU' : 'CPU';
      onStatusMessage?.call(
        'Loading ${_liteRtVariantLabel(liteRtVariant!)} on $backendLabel...',
      );

      final modelPath = await ModelLoader.resolveModelPath(liteRtVariant);
      final result = await _liteRtEngine.load(
        modelPath: modelPath,
        performanceMode: backendMode,
        enableVision: true,
        onProgress: (p) => onProgress?.call(p),
      );

      if (result.success) {
        _setLiteRtLoadedVariant(liteRtVariant);
        print(
          '[DualEngine] ${_liteRtVariantLabel(liteRtVariant)} ready on '
          '${result.backend.toUpperCase()}',
        );
      } else {
        print(
          '[DualEngine] ${_liteRtVariantLabel(liteRtVariant)} load failed: '
          '${result.message}',
        );
        _clearLiteRtPresence(liteRtVariant);

        // Auto mode can fall back from E4B to E2B before trying Qwen.
        if (_activeModel == ActiveModel.auto &&
            liteRtVariant == ModelVariant.gemmaE4b &&
            _hasGemma) {
          final fallbackPath =
              await ModelLoader.resolveGemmaPath();
          onStatusMessage?.call(
            'Loading Gemma 4 E2B on $backendLabel...',
          );
          final fallback = await _liteRtEngine.load(
            modelPath: fallbackPath,
            performanceMode: backendMode,
            enableVision: true,
            onProgress: (p) => onProgress?.call(p),
          );
          if (fallback.success) {
            _setLiteRtLoadedVariant(ModelVariant.gemma);
          }
        }
      }
    }

    // Load Qwen3 4B if explicitly selected, if Auto has no working LiteRT
    // model, or as the existing fallback when the selected LiteRT model fails.
    if (shouldLoadQwen || (!_liteRtModelLoaded && _hasQwen4b)) {
      onStatusMessage?.call('Loading Qwen3 4B...');
      try {
        _qwenEngine = await _spawnQwenEngine();
        _qwenChat = await _qwenEngine!.createChat();
        _qwenChat!.addSystem(_kQwenSystemPrompt);
        _qwenLoaded = true;
        print('[DualEngine] Qwen3 4B ready');
      } catch (e) {
        print('[DualEngine] Qwen load failed: $e');
        _qwenLoaded = false;
      }

      if (!_liteRtModelLoaded && _qwenLoaded) {
        _activeModel = ActiveModel.qwen4b;
      }
    }

    if (!_liteRtModelLoaded && !_qwenLoaded) {
      throw ModelNotFoundException('All models failed to load');
    }

    onProgress?.call(1.0);
  }

  bool get _liteRtModelLoaded =>
      _gemmaLoaded || _gemmaE4bLoadedAsActive;

  ModelVariant? _resolveLiteRtVariant() {
    if (_activeModel == ActiveModel.auto) {
      if (_hasGemmaE4b) return ModelVariant.gemmaE4b;
      if (_hasGemma) return ModelVariant.gemma;
      return null;
    }

    if (_activeModel == ActiveModel.gemmaE4b && _hasGemmaE4b) {
      return ModelVariant.gemmaE4b;
    }
    if (_activeModel == ActiveModel.gemma && _hasGemma) {
      return ModelVariant.gemma;
    }
    return null;
  }

  ModelVariant? _resolveLiteRtVariantForModel(ActiveModel model) {
    if (model == ActiveModel.gemmaE4b && _hasGemmaE4b) {
      return ModelVariant.gemmaE4b;
    }
    if (model == ActiveModel.gemma && _hasGemma) {
      return ModelVariant.gemma;
    }
    if (model == ActiveModel.auto) {
      return _resolveLiteRtVariant();
    }
    return null;
  }

  String _liteRtVariantLabel(ModelVariant variant) {
    return variant == ModelVariant.gemmaE4b ? 'Gemma 4 E4B' : 'Gemma 4 E2B';
  }

  void _setLiteRtLoadedVariant(ModelVariant variant) {
    _gemmaLoaded = variant == ModelVariant.gemma;
    _gemmaE4bLoadedAsActive = variant == ModelVariant.gemmaE4b;
  }

  void _clearLiteRtPresence(ModelVariant variant) {
    if (variant == ModelVariant.gemma) {
      _hasGemma = false;
      _gemmaLoaded = false;
    } else {
      _hasGemmaE4b = false;
      _gemmaE4bLoadedAsActive = false;
    }
  }

  ActiveModel _defaultModel() {
    // Auto prefers E4B, then E2B, then Qwen3.
    if (_hasGemmaE4b || _hasGemma) return ActiveModel.auto;
    if (_hasQwen4b) return ActiveModel.qwen4b;
    return ActiveModel.auto;
  }

  Future<LlamaEngine> _spawnQwenEngine() async {
    const contextSize = 4096;
    final modelPath = await ModelLoader.resolveQwen4bPath();

    if (Platform.isIOS || Platform.isMacOS) {
      return LlamaEngine.spawnFromProcess(
        modelParams: ModelParams(path: modelPath, gpuLayers: 99),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    } else {
      return LlamaEngine.spawn(
        libraryPath: ModelLoader.androidLibraryBasename(),
        modelParams: ModelParams(path: modelPath, gpuLayers: 0),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Model switching - lazy-loads the target model if needed
  // -------------------------------------------------------------------------

  set activeModel(ActiveModel v) {
    _activeModel = v;
    _saveModel(v);
  }

  /// Switch to a model, loading it if it hasn't been loaded yet.
  /// Returns true if the switch succeeded.
  Future<bool> switchToModel(
    ActiveModel model, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    _activeModel = model;
    _saveModel(model);

    final targetVariant = _resolveLiteRtVariantForModel(model);

    if (targetVariant != null) {
      final alreadyLoaded =
          (targetVariant == ModelVariant.gemma && _gemmaLoaded) ||
          (targetVariant == ModelVariant.gemmaE4b &&
              _gemmaE4bLoadedAsActive);

      if (!alreadyLoaded) {
        // LiteRT holds one .litertlm file at a time. Dispose the current
        // model before loading the selected E2B or E4B file.
        await _liteRtEngine.dispose();
        _gemmaLoaded = false;
        _gemmaE4bLoadedAsActive = false;

        final modelPath = await ModelLoader.resolveModelPath(targetVariant);
        final backendMode = await LiteRtEngine.loadSavedBackendMode();
        onStatus?.call(
          'Loading ${_liteRtVariantLabel(targetVariant)} on '
          '${backendMode == LiteRtBackendMode.gpu ? 'GPU' : 'CPU'}...',
        );
        final result = await _liteRtEngine.load(
          modelPath: modelPath,
          performanceMode: backendMode,
          enableVision: true,
          onProgress: onProgress,
        );
        _setLiteRtLoadedVariant(
          result.success ? targetVariant : ModelVariant.gemma,
        );
        if (!result.success) {
          _gemmaLoaded = false;
          _gemmaE4bLoadedAsActive = false;
        }
        return result.success;
      }
      return true;
    }

    // Qwen path - unchanged from existing logic.
    if (model == ActiveModel.qwen4b && _hasQwen4b) {
      if (!_qwenLoaded) {
        onStatus?.call('Loading Qwen3 4B...');
        try {
          _qwenEngine ??= await _spawnQwenEngine();
          _qwenChat = await _qwenEngine!.createChat();
          _qwenChat!.addSystem(_kQwenSystemPrompt);
          _qwenLoaded = true;
          return true;
        } catch (e) {
          print('[DualEngine] Lazy Qwen load failed: $e');
          return false;
        }
      }
      return true;
    }

    // Auto can fall back to Qwen when no LiteRT model is available.
    if (model == ActiveModel.auto && _hasQwen4b) {
      if (!_qwenLoaded) {
        onStatus?.call('Loading Qwen3 4B...');
        try {
          _qwenEngine ??= await _spawnQwenEngine();
          _qwenChat = await _qwenEngine!.createChat();
          _qwenChat!.addSystem(_kQwenSystemPrompt);
          _qwenLoaded = true;
        } catch (e) {
          print('[DualEngine] Lazy Qwen load failed: $e');
          return false;
        }
      }
      return true;
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // Switch LiteRT backend (GPU <-> CPU) at runtime
  // -------------------------------------------------------------------------

  /// Reload Gemma with a different backend (GPU or CPU).
  /// Returns the new backend string ('gpu' or 'cpu').
  Future<String> switchLiteRtBackend(
    LiteRtBackendMode mode, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    if (!_liteRtModelLoaded) return '';

    await LiteRtEngine.saveBackendMode(mode);
    final currentVariant =
        _gemmaE4bLoadedAsActive ? ModelVariant.gemmaE4b : ModelVariant.gemma;

    await _liteRtEngine.dispose();
    _gemmaLoaded = false;
    _gemmaE4bLoadedAsActive = false;

    final label = mode == LiteRtBackendMode.gpu ? 'GPU' : 'CPU';
    onStatus?.call('Reloading ${_liteRtVariantLabel(currentVariant)} on $label...');

    final modelPath = await ModelLoader.resolveModelPath(currentVariant);
    final result = await _liteRtEngine.load(
      modelPath: modelPath,
      performanceMode: mode,
      enableVision: true,
      onProgress: onProgress,
    );

    if (!result.success && mode == LiteRtBackendMode.gpu) {
      await LiteRtEngine.saveBackendMode(LiteRtBackendMode.cpu);
      final cpuResult = await _liteRtEngine.load(
        modelPath: modelPath,
        performanceMode: LiteRtBackendMode.cpu,
        enableVision: true,
        onProgress: onProgress,
      );
      _setLiteRtLoadedVariant(
        cpuResult.success ? currentVariant : ModelVariant.gemma,
      );
      if (!cpuResult.success) {
        _gemmaLoaded = false;
        _gemmaE4bLoadedAsActive = false;
      }
      return cpuResult.backend;
    }

    _setLiteRtLoadedVariant(
      result.success ? currentVariant : ModelVariant.gemma,
    );
    if (!result.success) {
      _gemmaLoaded = false;
      _gemmaE4bLoadedAsActive = false;
    }
    return result.backend;
  }

  // -------------------------------------------------------------------------
  // Message sending
  // -------------------------------------------------------------------------

  /// Sends a message and returns a stream of token chunks plus the model label.
  /// [imagePath] - only works when Gemma/LiteRT is active.
  /// [docText] - prepended to the prompt as document context.
  (Stream<String>, String) sendMessageWithLabel(
    String userText, {
    String? imagePath,
    String? docText,
    List<Map<String, String>> history = const [],
  }) {
    final shouldUseLiteRt = _activeModel == ActiveModel.gemma ||
        _activeModel == ActiveModel.gemmaE4b ||
        (_activeModel == ActiveModel.auto && (_hasGemma || _hasGemmaE4b));

    if (shouldUseLiteRt && _liteRtModelLoaded) {
      final prompt = _buildPrompt(userText, docText);
      final stream = _streamFromLiteRt(
        prompt: prompt,
        history: history,
        imagePath: imagePath,
      );
      final modelName =
          _gemmaE4bLoadedAsActive ? 'Gemma E4B' : 'Gemma E2B';
      final label =
          '$modelName - LiteRT ${_liteRtEngine.activeBackend.toUpperCase()}';
      return (stream, label);
    }

    // GGUF / Qwen3 4B path
    if (_qwenLoaded && _qwenChat != null) {
      final prompt = _buildPrompt(userText, docText);
      final stream = _streamFromQwen(prompt);
      return (stream, 'Qwen3 4B - GGUF CPU');
    }

    // No engine available
    final ctrl = StreamController<String>();
    ctrl.add('ERROR: No model loaded. Please restart the app.');
    ctrl.close();
    return (ctrl.stream, '');
  }

  Stream<String> _streamFromLiteRt({
    required String prompt,
    required List<Map<String, String>> history,
    String? imagePath,
  }) async* {
    final ctrl = StreamController<String>();

    _liteRtEngine
        .generate(
          prompt: prompt,
          history: history,
          systemPrompt: _kGemmaSystemPrompt,
          maxTokens: 1024,
          temperature: 0.7,
          imagePath: imagePath,
          onToken: ctrl.add,
        )
        .then((_) => ctrl.close())
        .catchError((e) {
      ctrl.addError(e);
      ctrl.close();
    });

    yield* ctrl.stream;
  }

  Stream<String> _streamFromQwen(String userText) async* {
    if (_qwenChat == null) {
      yield 'ERROR: Qwen3 4B is not loaded.';
      return;
    }

    _qwenChat!.addUser(userText);

    await for (final event in _qwenChat!.generate(
      maxTokens: 1024,
      sampler: const SamplerParams(temperature: 0.7, topP: 0.9),
    )) {
      switch (event) {
        case TokenEvent():
          yield event.text
              .replaceAll('\u2014', ' - ')
              .replaceAll('\u2013', ' - ');
        case ShiftEvent():
          break;
        case DoneEvent():
          return;
      }
    }
  }

  String _buildPrompt(String userText, String? docText) {
    if (docText == null || docText.isEmpty) return userText;
    return '[Attached document]\n$docText\n\nUser question: $userText';
  }

  // -------------------------------------------------------------------------
  // Stop generation
  // -------------------------------------------------------------------------

  Future<void> stop() async {
    await _liteRtEngine.stop();
    // Qwen3/GGUF is stateless per-call - no stop needed
  }

  // -------------------------------------------------------------------------
  // Reset conversation context
  // -------------------------------------------------------------------------

  Future<void> resetConversation() async {
    await _liteRtEngine.resetConversation();
    if (_qwenLoaded && _qwenEngine != null) {
      try {
        await _qwenChat?.dispose();
      } catch (_) {}
      _qwenChat = await _qwenEngine!.createChat();
      _qwenChat!.addSystem(_kQwenSystemPrompt);
    }
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    await _liteRtEngine.dispose();
    try {
      await _qwenEngine?.dispose();
    } catch (_) {}
    _qwenEngine = null;
    _qwenChat = null;
    _gemmaLoaded = false;
    _gemmaE4bLoadedAsActive = false;
    _qwenLoaded = false;
  }

  // -------------------------------------------------------------------------
  // Persistence helpers
  // -------------------------------------------------------------------------

  static Future<ActiveModel?> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefModel);
    switch (raw) {
      case 'gemma':
        return ActiveModel.gemma;
      case 'gemmaE4b':
        return ActiveModel.gemmaE4b;
      case 'qwen4b':
        return ActiveModel.qwen4b;
      case 'auto':
        return ActiveModel.auto;
      default:
        return null;
    }
  }

  static Future<void> _saveModel(ActiveModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (model) {
      ActiveModel.gemma => 'gemma',
      ActiveModel.gemmaE4b => 'gemmaE4b',
      ActiveModel.qwen4b => 'qwen4b',
      ActiveModel.auto => 'auto',
    };
    await prefs.setString(_kPrefModel, raw);
  }
}
