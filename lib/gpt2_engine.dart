// gpt2_engine.dart
//
// Thin wrapper around llama_cpp_dart's LlamaEngine + EngineChat.
//
// Auto mode: 1.5B drafts the answer fast. 4B outputs ONLY a compact
// corrections JSON (or "LGTM" if nothing to fix). We patch the draft
// in Dart and yield the final text in one shot - no slow re-generation.

import 'dart:convert';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_loader.dart';

enum ActiveModel { fast, accurate, auto }

bool _isHistoricalOrFactual(String lower) {
  final factualPatterns = [
    RegExp(r'\bwho (made|created|invented|founded|built|wrote|discovered|started|developed)\b'),
    RegExp(r'\bwhen (was|did|were|is)\b'),
    RegExp(r'\bwhat year\b'),
    RegExp(r'\bwhich (is|was) the (first|oldest|largest|smallest|biggest|earliest|last|latest)\b'),
    RegExp(r'\b(history|origin|founded|established|creation) of\b'),
    RegExp(r'\bwho (is|was) the (first|current|former|original|last)\b'),
    RegExp(r'\b(capital|president|prime minister|ceo|founder|author|inventor|director|winner|champion)\b'),
    RegExp(r'\b(19|20)\d{2}\b'),
    RegExp(r'\b(facts? about|tell me about|what do you know about)\b'),
  ];
  for (final p in factualPatterns) {
    if (p.hasMatch(lower)) return true;
  }
  return false;
}

bool _needsAccurateModel(String text) {
  final lower = text.toLowerCase().trim();
  final simplePatterns = [
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
    // Creative - no factual claims to verify
    RegExp(r'\b(write|draft|compose) (a|an|me a|me an)\b'),
    RegExp(r'\b(poem|haiku|story|joke|limerick|song)\b'),
    // Opinion / recommendation - no single correct answer
    RegExp(r'\b(what.*good|recommend|suggest|should i|best.*for me)\b'),
  ];
  for (final p in simplePatterns) {
    if (p.hasMatch(lower)) return false;
  }
  if (_isHistoricalOrFactual(lower)) return true;
  final complexIndicators = [
    RegExp(r'[\d]+\s*[\+\-\*\/\^%=]\s*[\d]+'),
    RegExp(r'\b(calculate|compute|solve|equation|formula|integral|derivative)\b'),
    RegExp(r'\b(explain|describe|summarize|analyze|compare|contrast|difference between)\b'),
    RegExp(r'\b(write|create|generate|draft|compose|code|program|script)\b'),
    RegExp(r'\b(science|math|physics|chemistry|biology|geography|politics)\b'),
    RegExp(r'\b(what (is|are|was|were)|who (is|was|are)|when (did|was|is)|where (is|was|are)|why (is|does|did)|how (do|does|did|can|to))\b'),
    RegExp(r'\b(list|give me|tell me|show me)\b'),
    RegExp(r'\b(translate|language|grammar|spelling)\b'),
    RegExp(r'\b(recipe|ingredient|step[s]?|instruction)\b'),
    RegExp(r'\b(recommend|suggest|advice|best|better|compare)\b'),
  ];
  if (text.split(' ').length > 12) return true;
  for (final p in complexIndicators) {
    if (p.hasMatch(lower)) return true;
  }
  return false;
}

/// Detects when the user is asking for more detail after a brief auto-mode answer.
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

class Gpt2Engine {
  LlamaEngine? _fastEngine;
  EngineChat? _fastChat;
  EngineChat? _autoDraftChat;  // 1.5B brief-draft persona used in auto mode

  LlamaEngine? _accurateEngine;
  EngineChat? _accurateChat;   // natural assistant - used when mode == accurate
  EngineChat? _verifierChat;   // patch-only persona - used exclusively in _dualPassStream

  // Simple in-memory LRU response cache (auto mode)
  final _responseCache = <String, String>{};
  static const _kCacheLimit = 20;

  // Tracks whether the last auto-mode reply ended with "want more detail?"
  // and what the original question was, so we can expand on user confirmation.
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

  ModelVariant resolveVariantForMessage(String text) {
    if (_activeModel == ActiveModel.fast) return ModelVariant.fast;
    if (_activeModel == ActiveModel.accurate) return ModelVariant.accurate;
    final needsAccurate = _needsAccurateModel(text);
    if (needsAccurate && _has4b) return ModelVariant.accurate;
    if (!needsAccurate && _has1_5b) return ModelVariant.fast;
    if (_has4b) return ModelVariant.accurate;
    return ModelVariant.fast;
  }

  Future<void> initialize() async {
    _has1_5b = await ModelLoader.isModel1_5bDownloaded();
    _has4b = await ModelLoader.isModel4bDownloaded();

    if (!_has1_5b && !_has4b) {
      throw ModelNotFoundException('No model found on device');
    }

    if (_has1_5b) {
      _fastEngine = await _spawnEngine(ModelVariant.fast);

      // Regular fast-mode chat (1.5B mode - no length constraint)
      _fastChat = await _fastEngine!.createChat();
      _fastChat!.addSystem(
        'You are Clean Spirit AI, a friendly and helpful assistant. '
        'Keep replies short and conversational - a few sentences is usually enough. '
        'Be warm and natural, like texting a knowledgeable friend. '
        'Never use em dashes (use a hyphen or comma instead). '
        'Skip unnecessary disclaimers.',
      );

      // Auto-mode draft chat - brief answers with detail offer
      _autoDraftChat = await _fastEngine!.createChat();
      _autoDraftChat!.addSystem(
        'You are Clean Spirit AI. '
        'Give a SHORT answer - maximum 4 to 5 lines or one paragraph. '
        'Be direct and to the point. '
        'Always end your reply with exactly this line: '
        'Want me to describe this in more detail? '
        'Never use em dashes - use a hyphen or comma instead. '
        'No unnecessary disclaimers.',
      );
    }

    if (_has4b) {
      _accurateEngine = await _spawnEngine(ModelVariant.accurate);

      // Natural assistant chat - used when user explicitly picks 4B mode
      _accurateChat = await _accurateEngine!.createChat();
      _accurateChat!.addSystem(
        'You are Clean Spirit AI, a helpful and accurate assistant. '
        'Give thorough, well-reasoned answers. '
        'Never use em dashes - use a hyphen or comma instead. '
        'Skip unnecessary disclaimers.',
      );

      // Verifier chat - patch-only persona, used exclusively in _dualPassStream
      _verifierChat = await _accurateEngine!.createChat();
      _verifierChat!.addSystem(
        'You are a strict factual error checker. '
        'Your default output is LGTM. '
        'Only output a JSON patch if the draft contains a BLATANT, SIGNIFICANT factual error - '
        'such as a wrong name, wrong date, wrong number, or completely false statement. '
        'Do NOT flag: opinions, style, minor wording differences, missing context, or anything debatable. '
        'If in doubt, output LGTM. '
        'When you do patch, output ONLY a JSON array: [{"find":"...","replace":"..."}] '
        'No explanation, no preamble, no markdown fences.',
      );
    }

    final saved = await _loadModelPref();
    if (saved != null) {
      final valid = switch (saved) {
        ActiveModel.fast     => _has1_5b,
        ActiveModel.accurate => _has4b,
        ActiveModel.auto     => _has1_5b && _has4b,
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
  // Sending messages
  // ---------------------------------------------------------------------------

  (Stream<String>, ModelVariant) sendMessageWithVariant(
    String userText, {
    void Function(int phase)? onPhaseChange,
  }) {
    // Detail expansion: user said yes/more detail after a brief auto reply
    if (_activeModel == ActiveModel.auto && _awaitingDetail &&
        _isDetailRequest(userText) && _lastAutoQuestion.isNotEmpty) {
      _awaitingDetail = false;
      // Ask 4B to give the full detailed answer for the original question
      final detailPrompt =
          'Please explain in full detail: $_lastAutoQuestion';
      _lastAutoQuestion = '';
      final stream = _streamMessage(detailPrompt, ModelVariant.accurate);
      return (stream, ModelVariant.accurate);
    }
    // Any non-detail message resets the awaiting flag
    _awaitingDetail = false;

    // Dual-pass only when auto mode AND the classifier says the message
    // actually needs factual accuracy. Simple greetings/small talk skip
    // straight to 1.5B with no fact-check overhead.
    if (_activeModel == ActiveModel.auto && _has1_5b && _has4b &&
        _needsAccurateModel(userText)) {
      // Cache hit - drip the cached answer instantly
      final cacheKey = userText.trim().toLowerCase();
      if (_responseCache.containsKey(cacheKey)) {
        final cached = _responseCache[cacheKey]!;
        // Still set awaiting so cached answers also support detail expansion
        _awaitingDetail = true;
        _lastAutoQuestion = userText;
        return (_fakeStream(cached), ModelVariant.accurate);
      }
      final stream = _dualPassStream(
        userText,
        onPhaseChange: onPhaseChange,
        cacheKey: cacheKey,
      );
      return (stream, ModelVariant.accurate);
    }
    final variant = resolveVariantForMessage(userText);
    final stream = _streamMessage(userText, variant);
    return (stream, variant);
  }

  Stream<String> sendMessage(String userText) {
    final (stream, _) = sendMessageWithVariant(userText);
    return stream;
  }

  // ---------------------------------------------------------------------------
  // Dual-pass: 1.5B drafts fast, 4B outputs patch JSON only, we apply in Dart
  // ---------------------------------------------------------------------------

  Stream<String> _dualPassStream(
    String userText, {
    void Function(int phase)? onPhaseChange,
    String? cacheKey,
  }) async* {
    if (_autoDraftChat == null) {
      yield* _streamMessage(userText, ModelVariant.accurate);
      return;
    }
    if (_verifierChat == null) {
      yield* _streamMessage(userText, ModelVariant.fast);
      return;
    }

    // --- Phase 1: 1.5B brief draft (silent) ---
    onPhaseChange?.call(1);

    final draftBuffer = StringBuffer();
    _autoDraftChat!.addUser(userText);

    await for (final event in _autoDraftChat!.generate(
      maxTokens: 300, // enforce brevity at token level too
      sampler: const SamplerParams(temperature: 0.7, topP: 0.9),
    )) {
      switch (event) {
        case TokenEvent():
          draftBuffer.write(event.text);
        case ShiftEvent():
          break;
        case DoneEvent():
          break;
      }
    }

    final draftAnswer = _stripThinkingTags(draftBuffer.toString());

    // --- Phase 2: 4B verifier outputs patch JSON only (capped short) ---
    onPhaseChange?.call(2);

    final verifierPrompt =
        'Question: $userText\n\n'
        'Draft:\n$draftAnswer\n\n'
        'Are there any BLATANT factual errors (wrong name, wrong date, completely false fact)? '
        'If not - output LGTM. Only patch if you are certain something is significantly wrong.';

    _verifierChat!.addUser(verifierPrompt);

    final patchBuffer = StringBuffer();
    int verifierTokens = 0;
    const maxVerifierTokens = 128;
    bool patchOverflow = false;

    await for (final event in _verifierChat!.generate(
      maxTokens: maxVerifierTokens,
      // Greedy - structured JSON output needs no sampling
      sampler: const SamplerParams(temperature: 0.0, topP: 1.0),
    )) {
      switch (event) {
        case TokenEvent():
          patchBuffer.write(event.text);
          verifierTokens++;
          // If the verifier is still going at 100 tokens, the draft was too bad
          // to patch cleanly - mark overflow and bail early
          if (verifierTokens >= 100) {
            patchOverflow = true;
          }
        case ShiftEvent():
          break;
        case DoneEvent():
          break;
      }
    }

    // Patch scope limiter: too many corrections = fall back to clean 4B reply
    if (patchOverflow) {
      onPhaseChange?.call(3);
      final fallback = _streamMessage(userText, ModelVariant.accurate);
      yield* fallback;
      return;
    }

    // Apply patches to the draft in Dart
    final finalAnswer = _applyPatches(draftAnswer, patchBuffer.toString().trim());

    // Cache the result
    _storeCached(cacheKey, finalAnswer);

    // Clear phase indicator before dripping - generation is done
    onPhaseChange?.call(3);

    // Fake-stream the patched answer for a smooth reading experience
    yield* _fakeStream(finalAnswer);

    // After dripping, mark that we are waiting for a possible detail request
    _awaitingDetail = true;
    _lastAutoQuestion = userText;
  }

  /// Drip [text] character-group by character-group so the UI animates smoothly.
  /// Adapts speed to answer length so long answers don't feel slow.
  Stream<String> _fakeStream(String text) async* {
    final totalChars = text.length;
    final charsPerChunk = totalChars > 800 ? 6 : totalChars > 300 ? 4 : 3;
    final chunkDelay = Duration(milliseconds: totalChars > 800 ? 25 : 35);

    for (int i = 0; i < totalChars; i += charsPerChunk) {
      final end = (i + charsPerChunk).clamp(0, totalChars);
      yield text.substring(i, end);
      if (end < totalChars) {
        await Future.delayed(chunkDelay);
      }
    }
  }

  void _storeCached(String? key, String answer) {
    if (key == null) return;
    _responseCache[key] = answer;
    if (_responseCache.length > _kCacheLimit) {
      _responseCache.remove(_responseCache.keys.first);
    }
  }

  /// Parses 4B's patch JSON and applies find/replace pairs to [draft].
  /// Falls back to the original draft on any parse error.
  String _applyPatches(String draft, String patchJson) {
    // 4B said everything is fine
    if (patchJson.isEmpty || patchJson.toUpperCase() == 'LGTM') return draft;

    try {
      // Strip any accidental markdown fences like ```json ... ```
      final cleaned = patchJson
          .replaceAll(RegExp(r'```[a-z]*', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      // Extract the JSON array - look for the first [ ... ] block
      final arrayStart = cleaned.indexOf('[');
      final arrayEnd = cleaned.lastIndexOf(']');
      if (arrayStart == -1 || arrayEnd == -1) return draft;

      final jsonStr = cleaned.substring(arrayStart, arrayEnd + 1);
      final patches = jsonDecode(jsonStr) as List<dynamic>;

      var result = draft;
      for (final patch in patches) {
        final find    = patch['find']    as String? ?? '';
        final replace = patch['replace'] as String? ?? '';
        if (find.isEmpty) continue;
        // Only replace the first occurrence to avoid clobbering repeated phrases
        result = result.replaceFirst(find, replace);
      }
      return result;
    } catch (_) {
      // Any JSON error: return original draft untouched
      return draft;
    }
  }

  String _stripThinkingTags(String raw) {
    const open = '<think>';
    const close = '</think>';
    final start = raw.indexOf(open);
    if (start == -1) return raw.trim();
    final after = raw.substring(start + open.length);
    final end = after.indexOf(close);
    if (end == -1) return '';
    return after.substring(end + close.length).trimLeft();
  }

  Stream<String> _streamMessage(String userText, ModelVariant variant) async* {
    final chat = variant == ModelVariant.fast ? _fastChat : _accurateChat;
    if (chat == null) {
      throw StateError('Engine for $variant not initialized.');
    }
    chat.addUser(userText);
    await for (final event in chat.generate(
      maxTokens: 1024,
      sampler: const SamplerParams(temperature: 0.7, topP: 0.9),
    )) {
      switch (event) {
        case TokenEvent():
          yield event.text;
        case ShiftEvent():
          break;
        case DoneEvent():
          return;
      }
    }
  }

  Future<void> dispose() async {
    await _fastEngine?.dispose();
    await _accurateEngine?.dispose();
    _fastEngine = null;
    _fastChat = null;
    _autoDraftChat = null;
    _accurateEngine = null;
    _accurateChat = null;
    _verifierChat = null;
    _responseCache.clear();
    _awaitingDetail = false;
    _lastAutoQuestion = '';
  }
}
