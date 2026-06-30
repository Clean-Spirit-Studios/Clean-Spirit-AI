// model_loader.dart
//
// Responsible for getting the GGUF model file onto the device and giving
// back a plain filesystem path llama_cpp_dart's LlamaEngine can open.
//
// UNLIKE earlier versions of this app, the model is NOT bundled inside the
// APK/IPA anymore — it's downloaded once, on first launch, directly into
// app-private storage. This keeps the installable app small (~10-20MB
// instead of 1GB+) at the cost of needing a real internet connection the
// very first time the app runs. After that first successful download,
// the app is offline-capable exactly as before — every subsequent launch
// reads the local file and touches the network for nothing.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:resumable_downloader/resumable_downloader.dart';

/// Name of the GGUF file we expect. Change this if you pick a different
/// quant (e.g. 'qwen2.5-1.5b-instruct-q5_k_m.gguf' for higher quality, or
/// 'qwen2.5-1.5b-instruct-q3_k_m.gguf' for a smaller footprint) — make sure
/// kModelDownloadUrl below points at the matching file.
const String kModelFileName = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';

/// Direct download URL for the model file. This is the official Qwen GGUF
/// repo on Hugging Face. If you change kModelFileName above, update this
/// to match — Hugging Face's "download" link format is:
/// https://huggingface.co/<org>/<repo>/resolve/main/<filename>?download=true
const String kModelDownloadUrl =
    'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/$kModelFileName?download=true';

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

  /// True if the model file is already fully downloaded and ready to load
  /// — i.e. no network needed. Check this before deciding whether to show
  /// the download screen or go straight to the chat screen.
  static Future<bool> isModelDownloaded() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$kModelFileName');
    return file.exists();
  }

  /// Returns the absolute on-device path to the GGUF model file. Throws
  /// [ModelNotFoundException] if it hasn't been downloaded yet — callers
  /// should check [isModelDownloaded] (or catch this) and route to the
  /// download flow in download_screen.dart first.
  static Future<String> resolveModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$kModelFileName');
    if (await file.exists()) {
      return file.path;
    }
    throw ModelNotFoundException(file.path);
  }

  /// Looks up the model file's total size via an HTTP HEAD request, purely
  /// for display purposes (showing "X MB / Y MB" during download). Returns
  /// null if the server doesn't report Content-Length or the request
  /// fails — the download itself doesn't depend on this succeeding.
  static Future<int?> fetchTotalSizeBytes() async {
    try {
      final dio = Dio();
      final response = await dio.head(kModelDownloadUrl);
      final lengthHeader = response.headers.value('content-length');
      if (lengthHeader == null) return null;
      return int.tryParse(lengthHeader);
    } catch (_) {
      return null;
    }
  }

  /// Downloads the model with progress reporting and resume-on-failure
  /// support (HTTP Range requests — if the app is killed or loses
  /// connectivity partway through, calling this again continues from
  /// where it left off rather than restarting).
  ///
  /// [onProgress] receives a fraction from 0.0 to 1.0, matching what
  /// resumable_downloader's QueueItem.progressCallback documents.
  static Future<void> downloadModel({
    required void Function(double fraction) onProgress,
  }) async {
    final manager = await _manager();
    await manager.getFile(
      QueueItem(
        url: kModelDownloadUrl,
        fileName: kModelFileName,
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

  /// Resolves the path/basename to pass to [LlamaEngine.spawn] for the
  /// native llama.cpp shared library on this platform.
  ///
  /// - Android: pass the basename; the AAR's .so is unpacked into the APK's
  ///   native lib dir automatically and Android's loader resolves it.
  /// - iOS/macOS: if you embedded llama.xcframework in Xcode, symbols are
  ///   already in-process — use LlamaEngine.spawnFromProcess() instead of
  ///   this path entirely (see gpt2_engine.dart).
  static String androidLibraryBasename() => 'libllama.so';
}

class ModelNotFoundException implements Exception {
  final String expectedPath;
  ModelNotFoundException(this.expectedPath);

  @override
  String toString() =>
      'AI model file not found at $expectedPath — it needs to be '
      'downloaded first via ModelLoader.downloadModel().';
}
