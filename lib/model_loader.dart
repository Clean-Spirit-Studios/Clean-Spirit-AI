// model_loader.dart
//
// Responsible for getting the GGUF model files onto the device and giving
// back plain filesystem paths llama_cpp_dart's LlamaEngine can open.
//
// Supports two models:
//   - QWEN2.5 1.5B: faster, less accurate - for simple conversational tasks
//   - QWEN3 4B:     slower, more accurate - for complex tasks, facts, math
//
// Models are downloaded into app-private storage on first launch.
// After download the app is fully offline.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:resumable_downloader/resumable_downloader.dart';

// ---- 1.5B model (QWEN2.5) ------------------------------------------------
// NOTE: The official Qwen/Qwen2.5-1.5B-Instruct-GGUF repo uses Xet storage
// which resumable_downloader cannot handle (stalls at 0%). The bartowski
// mirror serves the identical file as a plain HTTP download.
const String kModel1_5bFileName = 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';
const String kModel1_5bDownloadUrl =
    'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/$kModel1_5bFileName?download=true';

// ---- 4B model (QWEN3) -----------------------------------------------------
const String kModel4bFileName = 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf';
const String kModel4bDownloadUrl =
    'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/$kModel4bFileName?download=true';

// Legacy alias so gpt2_engine.dart compiles without changes.
const String kModelFileName = kModel4bFileName;

enum ModelVariant { fast, accurate }

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

  static Future<bool> isModel1_5bDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/models/$kModel1_5bFileName').exists();
  }

  static Future<bool> isModel4bDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/models/$kModel4bFileName').exists();
  }

  /// True when at least one model is present (enough to show the chat screen).
  static Future<bool> isModelDownloaded() async {
    return await isModel1_5bDownloaded() || await isModel4bDownloaded();
  }

  // ---- path resolution ----------------------------------------------------

  static Future<String> resolveModelPath({
    ModelVariant variant = ModelVariant.accurate,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();

    if (variant == ModelVariant.fast) {
      final file = File('${appDir.path}/models/$kModel1_5bFileName');
      if (await file.exists()) return file.path;
      // Fall back to the 4B model if the 1.5B hasn't been downloaded.
      final fallback = File('${appDir.path}/models/$kModel4bFileName');
      if (await fallback.exists()) return fallback.path;
      throw ModelNotFoundException(file.path);
    } else {
      final file = File('${appDir.path}/models/$kModel4bFileName');
      if (await file.exists()) return file.path;
      // Fall back to the 1.5B model if the 4B hasn't been downloaded.
      final fallback = File('${appDir.path}/models/$kModel1_5bFileName');
      if (await fallback.exists()) return fallback.path;
      throw ModelNotFoundException(file.path);
    }
  }

  // ---- size queries (cosmetic only) ---------------------------------------

  static Future<int?> fetchTotalSizeBytes({
    ModelVariant variant = ModelVariant.accurate,
  }) async {
    try {
      final url = variant == ModelVariant.fast
          ? kModel1_5bDownloadUrl
          : kModel4bDownloadUrl;
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
    required void Function(double fraction) onProgress,
    ModelVariant variant = ModelVariant.accurate,
  }) async {
    final manager = await _manager();
    final url = variant == ModelVariant.fast
        ? kModel1_5bDownloadUrl
        : kModel4bDownloadUrl;
    final fileName = variant == ModelVariant.fast
        ? kModel1_5bFileName
        : kModel4bFileName;

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

  static String androidLibraryBasename() => 'libllama.so';
}

class ModelNotFoundException implements Exception {
  final String expectedPath;
  ModelNotFoundException(this.expectedPath);

  @override
  String toString() =>
      'AI model file not found at $expectedPath - it needs to be '
      'downloaded first via ModelLoader.downloadModel().';
}
