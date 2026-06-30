// gpt2_engine.dart
//
// Thin wrapper around llama_cpp_dart's LlamaEngine + EngineChat.
//
// NOTE ON THE FILENAME: this file is still called gpt2_engine.dart for
// historical reasons (the app started out running GPT-2), but as of this
// version it runs Qwen2.5-1.5B-Instruct instead. Feel free to rename
// the file; nothing outside this file depends on its name.
//
// IMPORTANT — platform-specific library loading:
// llama_cpp_dart ships native binaries OUTSIDE the pub package (see
// README.md "Native library setup"). On Android you give LlamaEngine.spawn
// a basename ('libllama.so') and Android's loader resolves it from the AAR
// you dropped into android/app/libs/. On iOS/macOS with the xcframework
// embedded via Xcode ("Embed & Sign"), symbols are already loaded into the
// process at launch — use spawnFromProcess() instead, no path needed.
//
// WHY THIS VERSION IS SIMPLER THAN THE GPT-2 ONE:
// The GPT-2 fine-tune we used before (ChatGPT-2.V2) shipped a GGUF with no
// embedded Jinja chat template, which forced us to hand-build ChatML-style
// prompt strings ourselves via EngineSession. Qwen2.5-Instruct's official
// GGUF DOES carry a proper chat template, so llama_chat_apply_template has
// something to work with — we can go back to the simpler, intended
// EngineChat API and let the package render turns for us.
//
// Everything below after the engine is spawned runs with zero network
// access. Generation is 100% local CPU inference.

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import 'model_loader.dart';

class Gpt2Engine {
  LlamaEngine? _engine;
  EngineChat? _chat;

  bool get isReady => _chat != null;

  /// Boots the engine and creates a chat session with a short system
  /// prompt. Call once at app startup (or lazily before the first message
  /// is sent).
  Future<void> initialize() async {
    final modelPath = await ModelLoader.resolveModelPath();

    // Qwen2.5-1.5B-Instruct supports up to 32,768 tokens of context per its
    // model card. 4096 is a comfortable middle ground for a phone — enough
    // for a long conversation without an oversized KV cache eating RAM.
    // Raise this if you want longer history and have headroom; this 1.5B
    // model is light on RAM (roughly 1.5-2GB to load), so there's room to
    // grow if needed.
    const contextSize = 4096;

    if (Platform.isIOS || Platform.isMacOS) {
      // Native symbols are already in-process via the embedded xcframework.
      _engine = await LlamaEngine.spawnFromProcess(
        modelParams: ModelParams(path: modelPath, gpuLayers: 99),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    } else {
      // Android: basename resolves via the bundled AAR's jniLibs.
      _engine = await LlamaEngine.spawn(
        libraryPath: ModelLoader.androidLibraryBasename(),
        modelParams: ModelParams(path: modelPath, gpuLayers: 0),
        contextParams: const ContextParams(nCtx: contextSize),
      );
    }

    _chat = await _engine!.createChat();
    _chat!.addSystem(
      'You are a helpful, concise assistant. Answer briefly and directly.',
    );
  }

  /// Streams the assistant's reply token-by-token. The caller is
  /// responsible for appending the streamed text to its own UI state —
  /// this class holds no UI state itself; EngineChat tracks message
  /// history internally.
  Stream<String> sendMessage(String userText) async* {
    if (_chat == null) {
      throw StateError('Gpt2Engine.initialize() must complete before use.');
    }

    _chat!.addUser(userText);

    await for (final event in _chat!.generate(
      maxTokens: 512,
      sampler: const SamplerParams(temperature: 0.7, topP: 0.9),
    )) {
      switch (event) {
        case TokenEvent():
          yield event.text;
        case ShiftEvent():
          // Context window slid to make room — no user-visible action.
          break;
        case DoneEvent():
          return;
      }
    }
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _chat = null;
  }
}
