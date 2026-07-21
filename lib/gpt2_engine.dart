// gpt2_engine.dart
//
// Thin wrapper around llama_cpp_dart's LlamaEngine + EngineChat.
//
// Auto mode:
//   - Simple / conversational questions  → 1.5B, full stream (fast)
//   - Factual / complex questions        → 4B capped at 100 tokens, real stream
//                                          then offers "Want more detail?"
//   - User confirms detail               → 4B uncapped, full answer

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_loader.dart';

enum ActiveModel { fast, accurate, auto }

// ---------------------------------------------------------------------------
// Classifiers
// ---------------------------------------------------------------------------

bool _isSimpleConversational(String text) {
  final lower = text.toLowerCase().trim();
  final patterns = [
    RegExp(r'^(hi|hey|hello|hiya|howdy)[!?.,\s]*$'),
    RegExp(r'^how are you[?!.,\s]*$'),
    RegExp(r"^(i'm |i am )?(fine|good|great|okay|ok|doing well)[!.,\s]*$"),
    RegExp(r'^(thanks|thank you|thx|ty)[!.,\s]*$'),
    RegExp(r'^(yes|no|yeah|nah|yep|nope)[!?,.\s]*$'),
    RegExp(r'^(good (morning|afternoon|evening|night))[!.,\s]*$'),
    RegExp(r"^what('s| is) (your name|up)[?!.,\s]*$"),
    RegExp(r'^(bye|goodbye|see you|cya)[!.,\s]*$'),
    RegExp(r'^(lol|haha|hehe|lmao)[!.,\s]*$'),
    RegExp(r'^(ok|okay|got it|sure|alright)[!.,\s]*$'),
    // Creative - opinion-based, no facts to verify
    RegExp(r'\b(write|draft|compose) (a|an|me a|me an)\b'),
    RegExp(r'\b(poem|haiku|story|joke|limerick|song)\b'),
    RegExp(r'\b(what.*good|recommend|suggest|should i|best.*for me)\b'),
  ];
  for (final p in patterns) {
    if (p.hasMatch(lower)) return true;
  }
  return false;
}

bool _isDetailRequest(String text) {
  final lower = text.toLowerCase().trim();
  final patterns = [
    RegExp(r'^(yes|yeah|yep|yup|sure|ok|okay|go ahead|please)[!.,\s]*$'),
    RegExp(r'\b(more detail|more details|elaborate|expand|explain more|tell me more|in depth|deeper|full explanation|describe in detail)\b'),
    RegExp(r'^(yes[,.]?\s*(please|do it|go on|continue|tell me))[!.,\s]*$'),
  ];
  for (final p in patterns) {
    if (p.hasMatch(lower)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class Gpt2Engine {
  LlamaEngine? _fastEngine;
  EngineChat? _fastChat;       // 1.5B - conversational / fast mode

  LlamaEngine? _accurateEngine;
  EngineChat? _accurateChat;   // 4B - accurate mode + auto factual answers + detail expansions
  EngineChat? _autoBriefChat;  // 4B - capped brief persona for auto factual answers

  // Response cache (auto brief answers)
  final _responseCache = <String, String>{};
  static const _kCacheLimit = 20;

  // Detail expansion state
  bool _awaitingDetail = false;
  String _lastAutoQuestion = '';

  bool _has1_5b = false;
  bool _has4b = false;

  ActiveModel _activeModel = ActiveModel.auto;
  ActiveModel get activeModel => _activeModel;
  bool get has1_5b => _has1_5b;
  bool get has4b => _has4b;
  bool get isReady => _fastChat != null || _accurateChat != null;

  static const _kModelPrefKey = 'selected_model';

  set activeModel(ActiveModel v) {
    _activeModel = v;
    _saveModelPref(v);
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  static Future<ActiveModel?> _loadModelPref() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kModelPrefKey);
    switch (raw) {
      case 'fast':     return ActiveModel.fast;
      case 'accurate': return ActiveModel.accurate;
      case 'auto':     return ActiveModel.auto;
      default:         return null;
    }
  }

  static Future<void> _saveModelPref(ActiveModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (model) {
      ActiveModel.fast     => 'fast',
      ActiveModel.accurate => 'accurate',
      ActiveModel.auto     => 'auto',
    };
    await prefs.setString(_kModelPrefKey, raw);
  }

  ActiveModel _defaultModel() {
    if (_has1_5b && _has4b) return ActiveModel.auto;
    if (_has4b) return ActiveModel.accurate;
    return ActiveModel.fast;
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    _has1_5b = await ModelLoader.isModel1_5bDownloaded();
    _has4b = await ModelLoader.isModel4bDownloaded();

    if (!_has1_5b && !_has4b) {
      throw ModelNotFoundException('No model found on device');
    }

    if (_has1_5b) {
      _fastEngine = await _spawnEngine(ModelVariant.fast);
      _fastChat = await _fastEngine!.createChat();
      _fastChat!.addSystem(
        'You are Clean Spirit AI, a friendly and helpful assistant. '
        'Keep replies short and conversational - a few sentences is usually enough. '
        'Be warm and natural, like texting a knowledgeable friend. '
        'Never use em dashes - use a hyphen or comma instead. '
        'Skip unnecessary disclaimers.',
      );
    }

    if (_has4b) {
      _accurateEngine = await _spawnEngine(ModelVariant.accurate);

      // Full 4B chat - used in accurate mode and detail expansions
      _accurateChat = await _accurateEngine!.createChat();
      _accurateChat!.addSystem(
        'You are Clean Spirit AI, a helpful and accurate assistant. '
        'Give thorough, well-reasoned answers. '
        'Never use em dashes - use a hyphen or comma instead. '
        'Skip unnecessary disclaimers.',
      );

      // Brief 4B chat - used in auto mode for factual questions
      // Token cap enforced at generation time (100 tokens)
      _autoBriefChat = await _accurateEngine!.createChat();
      _autoBriefChat!.addSystem(
        'You are Clean Spirit AI, a helpful and accurate assistant. '
        'Give a SHORT answer - maximum 4 to 5 lines or one short paragraph. '
        'Be direct and accurate. '
        'Always end your reply with exactly: Want me to describe this in more detail? '
        'Never use em dashes - use a hyphen or comma instead. '
        'No unnecessary disclaimers.',
      );
    }

    final saved = await _loadModelPref();
    if (saved != null) {
      final valid = switch (saved) {
        ActiveModel.fast     => _has1_5b,
        ActiveModel.accurate => _has4b,
        ActiveModel.auto     => true, // works with either model
      };
      _activeModel = valid ? saved : _defaultModel();
    } else {
      _activeModel = _defaultModel();
    }
  }

  Future<LlamaEngine> _spawnEngine(ModelVariant variant) async {
    const contextSize = 4096;
    final modelPath = await ModelLoader.resolveModelPath(variant: variant);

    if (Platform.isIOS || Platform.isMacOS) {
      return await LlamaEngine.spawnFromProcess(
        modelParams: ModelParams(path: modelPath, gpuLayers: 99),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    } else {
      return await LlamaEngine.spawn(
        libraryPath: ModelLoader.androidLibraryBasename(),
        modelParams: ModelParams(path: modelPath, gpuLayers: 0),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  (Stream<String>, ModelVariant) sendMessageWithVariant(
    String userText, {
    void Function(int phase)? onPhaseChange,
  }) {
    // --- Detail expansion ---
    if (_activeModel == ActiveModel.auto &&
        _awaitingDetail &&
        _isDetailRequest(userText) &&
        _lastAutoQuestion.isNotEmpty) {
      _awaitingDetail = false;
      final question = _lastAutoQuestion;
      _lastAutoQuestion = '';
      // Full 4B answer, no cap, real streaming
      final stream = _streamMessage(
        'Please explain in full detail: $question',
        ModelVariant.accurate,
        maxTokens: 1024,
      );
      return (stream, ModelVariant.accurate);
    }

    // Any new question resets detail state
    _awaitingDetail = false;

    if (_activeModel == ActiveModel.auto) {
      // Simple / conversational → 1.5B (fast, no cap)
      if (_isSimpleConversational(userText)) {
        final chat = _has1_5b ? ModelVariant.fast : ModelVariant.accurate;
        return (_streamMessage(userText, chat), chat);
      }

      // Factual / complex → 4B capped brief, then offer detail
      if (_has4b) {
        final cacheKey = userText.trim().toLowerCase();
        if (_responseCache.containsKey(cacheKey)) {
          _awaitingDetail = true;
          _lastAutoQuestion = userText;
          return (_fakeStream(_responseCache[cacheKey]!), ModelVariant.accurate);
        }
        final stream = _autoBriefStream(userText, cacheKey: cacheKey);
        return (stream, ModelVariant.accurate);
      }

      // No 4B available - fall back to 1.5B
      return (_streamMessage(userText, ModelVariant.fast), ModelVariant.fast);
    }

    // Explicit fast or accurate mode - straightforward
    if (_activeModel == ActiveModel.fast) {
      return (_streamMessage(userText, ModelVariant.fast), ModelVariant.fast);
    }
    return (_streamMessage(userText, ModelVariant.accurate, maxTokens: 1024), ModelVariant.accurate);
  }

  Stream<String> sendMessage(String userText) {
    final (stream, _) = sendMessageWithVariant(userText);
    return stream;
  }

  // ---------------------------------------------------------------------------
  // Auto brief: 4B capped at 100 tokens, real streaming
  // ---------------------------------------------------------------------------

  Stream<String> _autoBriefStream(
    String userText, {
    String? cacheKey,
  }) async* {
    if (_autoBriefChat == null) {
      // No 4B - fall back to 1.5B full stream
      yield* _streamMessage(userText, ModelVariant.fast);
      return;
    }

    _autoBriefChat!.addUser(userText);

    final buffer = StringBuffer();

    await for (final event in _autoBriefChat!.generate(
      maxTokens: 100,
      sampler: const SamplerParams(temperature: 0.7, topP: 0.9),
    )) {
      switch (event) {
        case TokenEvent():
          final text = event.text
              .replaceAll('\u2014', ' - ')
              .replaceAll('\u2013', ' - ');
          buffer.write(text);
          yield text;
        case ShiftEvent():
          break;
        case DoneEvent():
          break;
      }
    }

    // Cache and arm detail expansion
    _storeCached(cacheKey, buffer.toString());
    _awaitingDetail = true;
    _lastAutoQuestion = userText;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Stream<String> _streamMessage(
    String userText,
    ModelVariant variant, {
    int maxTokens = 1024,
  }) async* {
    final chat = variant == ModelVariant.fast ? _fastChat : _accurateChat;
    if (chat == null) {
      throw StateError('Engine for $variant not initialized.');
    }
    chat.addUser(userText);
    await for (final event in chat.generate(
      maxTokens: maxTokens,
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

  Stream<String> _fakeStream(String text) async* {
    final totalChars = text.length;
    final charsPerChunk = totalChars > 800 ? 6 : totalChars > 300 ? 4 : 3;
    final chunkDelay = Duration(milliseconds: totalChars > 800 ? 25 : 35);
    for (int i = 0; i < totalChars; i += charsPerChunk) {
      final end = (i + charsPerChunk).clamp(0, totalChars);
      yield text.substring(i, end);
      if (end < totalChars) await Future.delayed(chunkDelay);
    }
  }

  void _storeCached(String? key, String answer) {
    if (key == null) return;
    _responseCache[key] = answer;
    if (_responseCache.length > _kCacheLimit) {
      _responseCache.remove(_responseCache.keys.first);
    }
  }

  Future<void> dispose() async {
    await _fastEngine?.dispose();
    await _accurateEngine?.dispose();
    _fastEngine = null;
    _fastChat = null;
    _accurateEngine = null;
    _accurateChat = null;
    _autoBriefChat = null;
    _responseCache.clear();
    _awaitingDetail = false;
    _lastAutoQuestion = '';
  }
}
