// model_loader.dart
//
// Manages two models across two architectures:
//
//   Gemma 4 E2B Instruct (LiteRT-LM)  - GPU-accelerated, vision-capable, fast
//     File: gemma-4-E2B-it.litertlm (~2.46 GB)
//
//   Gemma 4 E4B Instruct (LiteRT-LM)  - GPU-accelerated, vision-capable, higher quality
//     File: gemma-4-E4B-it.litertlm (~3.40 GB)
//
//   Qwen3 4B Instruct (GGUF)           - CPU-based, thorough, accurate
//     File: Qwen3-4B-Instruct-2507-Q4_K_M.gguf (~2.5 GB)
//
// Models are downloaded into app-private storage on first launch.
// After download the app is fully offline.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:resumable_downloader/resumable_downloader.dart';

// ---------------------------------------------------------------------------
// Gemma 4 E2B Instruct (LiteRT-LM)
// ---------------------------------------------------------------------------

const String kGemmaFileName = 'gemma-4-E2B-it.litertlm';
const String kGemmaDownloadUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
    '/resolve/main/gemma-4-E2B-it.litertlm?download=true';
const String kGemmaSizeLabel = '2.46 GB';

// ---------------------------------------------------------------------------
// Gemma 4 E4B Instruct (LiteRT-LM) - higher quality, more RAM
// ---------------------------------------------------------------------------

const String kGemmaE4bFileName = 'gemma-4-E4B-it.litertlm';
const String kGemmaE4bDownloadUrl =
    'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm'
    '/resolve/main/gemma-4-E4B-it.litertlm?download=true';
const String kGemmaE4bSizeLabel = '3.40 GB';

// ---------------------------------------------------------------------------
// Qwen3 4B Instruct (GGUF)
// ---------------------------------------------------------------------------

const String kQwen4bFileName = 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf';
const String kQwen4bDownloadUrl =
    'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/'
    'Qwen3-4B-Instruct-2507-Q4_K_M.gguf?download=true';
const String kQwen4bSizeLabel = '2.5 GB';

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

enum ModelVariant {
  /// Gemma 4 E2B Instruct via LiteRT - GPU-accelerated, vision-capable
  gemma,

  /// Gemma 4 E4B Instruct via LiteRT - higher quality, GPU-accelerated, vision-capable
  gemmaE4b,

  /// Qwen3 4B Instruct via GGUF/llama_cpp_dart - CPU, thorough answers
  qwen4b,
}

// ---------------------------------------------------------------------------
// ModelLoader
// ---------------------------------------------------------------------------

class ModelLoader {
  static DownloadManager? _downloadManager;

  static Future<DownloadManager> _manager() async {
    if (_downloadManager != null) return _downloadManager!;
    _downloadManager = DownloadManager(
      subDir: 'models',
      fileExistsStrategy: FileExistsStrategy.resume,
      baseDirectory: await getApplicationDocumentsDirectory(),
      maxConcurrentDownloads: 1,
      maxRetries: 3,
    );
    return _downloadManager!;
  }

  // ---- existence checks ---------------------------------------------------

  static Future<bool> isGemmaDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/models/$kGemmaFileName').exists();
  }

  static Future<bool> isGemmaE4bDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/models/$kGemmaE4bFileName').exists();
  }

  static Future<bool> isQwen4bDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/models/$kQwen4bFileName').exists();
  }

  /// True when at least one model is present (enough to show the chat screen).
  static Future<bool> isAnyModelDownloaded() async {
    return await isGemmaDownloaded() ||
        await isGemmaE4bDownloaded() ||
        await isQwen4bDownloaded();
  }

  // ---- path resolution ----------------------------------------------------

  static Future<String> resolveGemmaPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$kGemmaFileName');
    if (await file.exists()) return file.path;
    throw ModelNotFoundException(file.path);
  }

  static Future<String> resolveGemmaE4bPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$kGemmaE4bFileName');
    if (await file.exists()) return file.path;
    throw ModelNotFoundException(file.path);
  }

  static Future<String> resolveQwen4bPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$kQwen4bFileName');
    if (await file.exists()) return file.path;
    throw ModelNotFoundException(file.path);
  }

  static Future<String> resolveModelPath(ModelVariant variant) async {
    return switch (variant) {
      ModelVariant.gemma => resolveGemmaPath(),
      ModelVariant.gemmaE4b => resolveGemmaE4bPath(),
      ModelVariant.qwen4b => resolveQwen4bPath(),
    };
  }

  // ---- size queries -------------------------------------------------------

  static Future<int?> fetchTotalSizeBytes(ModelVariant variant) async {
    try {
      final url = switch (variant) {
        ModelVariant.gemma => kGemmaDownloadUrl,
        ModelVariant.gemmaE4b => kGemmaE4bDownloadUrl,
        ModelVariant.qwen4b => kQwen4bDownloadUrl,
      };
      final dio = Dio();
      final response = await dio.head(url);
      final lengthHeader = response.headers.value('content-length');
      if (lengthHeader == null) return null;
      return int.tryParse(lengthHeader);
    } catch (_) {
      return null;
    }
  }

  // ---- downloads ----------------------------------------------------------

  static Future<void> downloadModel({
    required ModelVariant variant,
    required void Function(double fraction) onProgress,
  }) async {
    final manager = await _manager();
    final url = switch (variant) {
      ModelVariant.gemma => kGemmaDownloadUrl,
      ModelVariant.gemmaE4b => kGemmaE4bDownloadUrl,
      ModelVariant.qwen4b => kQwen4bDownloadUrl,
    };
    final fileName = switch (variant) {
      ModelVariant.gemma => kGemmaFileName,
      ModelVariant.gemmaE4b => kGemmaE4bFileName,
      ModelVariant.qwen4b => kQwen4bFileName,
    };

    await manager.getFile(
      QueueItem(
        url: url,
        fileName: fileName,
        progressCallback: (progress) {
          onProgress(progress.progress);
        },
      ),
    );
  }

  static Future<void> cancelDownload() async {
    final manager = await _manager();
    manager.cancelAll();
  }

  // ---- Android native library ---------------------------------------------

  static String androidLibraryBasename() => 'libllama.so';
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class ModelNotFoundException implements Exception {
  final String expectedPath;
  ModelNotFoundException(this.expectedPath);

  @override
  String toString() =>
      'AI model file not found at $expectedPath. '
      'It needs to be downloaded first via ModelLoader.downloadModel().';
}
