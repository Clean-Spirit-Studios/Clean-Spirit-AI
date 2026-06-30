# Clean Spirit AI

A Flutter app that runs a real LLM (Qwen2.5-1.5B-Instruct) **entirely
on-device**. It downloads the model once on first launch, then every
conversation after that runs locally via `llama.cpp`. No API key, no
server, no ongoing network calls.

This is a portfolio project demonstrating on-device LLM inference on
mobile: model lifecycle management, resumable large-file downloads, and
wiring Dart/Flutter to a native C++ inference engine via FFI.

## Why this exists

Most "AI chat app" tutorials just call OpenAI's API. That's a few lines of
code and doesn't say much about what you can actually build. This project
instead tackles the harder, more interesting problem: getting a real
language model to run *on the phone itself*, with everything that implies
- managing a multi-gigabyte model file on constrained mobile storage,
resuming interrupted downloads over flaky connections, and bridging Dart
to compiled native inference code.

## Architecture

The project went through a few real iterations, kept here for context:

1. Started out running GPT-2, bundled directly inside the APK.
2. Swapped to Qwen2.5-1.5B-Instruct, still bundled inside the APK.
3. **Current version**: Qwen2.5-1.5B-Instruct, downloaded at runtime on
   first launch instead of bundled, keeps the installable app small and
   means app updates don't force re-downloading the model.

Some filenames (`gpt2_engine.dart`) are leftovers from step 1 and don't
reflect what's actually running anymore, see the note at the top of that
file.

```
First launch, no model on disk yet:

  main.dart checks ModelLoader.isModelDownloaded()
        │ false
        ▼
  DownloadScreen (download_screen.dart)
        │  checks Wi-Fi vs mobile data, warns if mobile-only
        │  ModelLoader.downloadModel(), resumable_downloader package,
        │  HTTP Range-based resume if interrupted
        ▼
  qwen2.5-1.5b-instruct-q4_k_m.gguf saved to app-private storage
        │
        ▼
  ChatScreen, same as every subsequent launch from here on


Every launch after that (model already on disk):

  main.dart checks ModelLoader.isModelDownloaded()
        │ true, skips DownloadScreen entirely, zero network calls
        ▼
  ChatScreen (chat_screen.dart)
        │
        ▼
  Gpt2Engine (gpt2_engine.dart)        ← thin wrapper, no UI knowledge
        │
        ▼
  llama_cpp_dart (LlamaEngine / EngineChat)   ← Dart FFI bindings
        │
        ▼
  libllama.so / llama.xcframework      ← compiled llama.cpp, runs the
                                          actual matrix math on CPU
```

The **only** network activity anywhere in this app is the one-time model
download. Every chat message after that is 100% local CPU inference.

## What model this uses, and why

**Qwen2.5-1.5B-Instruct**, from the official `Qwen` org on Hugging Face
(Alibaba). 1.5B parameters, genuinely coherent multi-turn conversation,
real instruction-following, 32,768-token context (this app uses a more
modest 4096 to keep RAM use phone-friendly, see `gpt2_engine.dart`). Ships
with a proper embedded chat template in its GGUF metadata, so the app uses
the simpler, intended `EngineChat` API rather than hand-building prompt
strings.

GGUF source (official Qwen release):
https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF

| Quant | Size | Notes |
|---|---|---|
| Q2_K | 753 MB | smallest, noticeably worse |
| Q4_K_M | 1.12 GB | **what this app downloads by default** |
| Q5_K_M | 1.29 GB | slightly better quality, slightly slower |
| Q8_0 | 1.89 GB | best quality, still fast |

To change the quant, update both `kModelFileName` *and*
`kModelDownloadUrl` in `lib/model_loader.dart`, they need to stay in sync
since the URL is built from the filename.

## Setup

### 1. Get the Flutter project building

```bash
flutter pub get
```

`pubspec.yaml` pins a few packages to specific versions rather than loose
ranges, worth knowing why, since this has bitten this project before:

- `llama_cpp_dart: 0.9.0-dev.9`, exact version, not `^0.9.0`. Pub's caret
  ranges don't match prerelease versions under semver rules, so a caret
  range here fails to resolve entirely ("version solving failed"). If a
  newer `0.9.0-dev.N` comes out, bump by hand and re-check the API still
  matches `gpt2_engine.dart`, this package is pre-1.0 and explicitly
  warns its API "may break once more."
- `resumable_downloader: ^0.0.38`, also pre-1.0; check pub.dev for the
  current version before assuming a newer release is API-compatible.

### 2. Native library setup (required - not automatic)

`llama_cpp_dart` ships native binaries **outside** the pub package. Download
once per machine/project from:
https://github.com/netdur/llama_cpp_dart/releases

**Android:**
- Download the **CPU AAR** (`llama-cpp-dart.aar`, not the Hexagon/NPU one).
- Put it at `android/app/libs/llama-cpp-dart.aar`
- Add `implementation(files("libs/llama-cpp-dart.aar"))` to the
  `dependencies { }` block in `android/app/build.gradle.kts` (or
  `build.gradle` if you're on Groovy DSL).
- Make sure `minSdk` is at least 24.

**iOS / macOS:**
- Download `llama.xcframework`, embed it in Xcode with **Embed & Sign**.
- `gpt2_engine.dart` already calls `LlamaEngine.spawnFromProcess()` on
  iOS/macOS for this.

### 3. Model download - nothing to set up

The app downloads the model itself on first launch (see "Architecture"
above). Just make sure the device running the app has internet access the
first time it's opened.

If you'd rather pre-seed the model file for faster first-run testing
during development, you can `adb push` it directly to the path
`ModelLoader.resolveModelPath()` expects
(`<app documents dir>/models/qwen2.5-1.5b-instruct-q4_k_m.gguf`) and the
app will detect it's already present and skip straight to the chat screen.

### 4. Run it

```bash
flutter run
```

On a fresh install, expect to see the download screen first, progress
bar, MB downloaded / total, and a warning if you're on mobile data instead
of Wi-Fi. Once it finishes, every subsequent launch goes straight to chat.

## Honest expectations

- **First-launch network requirement**: the very first launch needs
  internet to fetch the model. Every launch after that is fully offline.
- **Download resilience**: `resumable_downloader` uses HTTP Range requests,
  so if the download is interrupted (app killed, connection drops, user
  backgrounds the app), reopening the app and retrying resumes from where
  it left off rather than restarting the full 1.1GB transfer.
- **Speed**: a few tokens/sec on a mid-range Android phone, faster on
  recent iPhones (Metal acceleration via `gpuLayers: 99` on iOS/macOS).
  Android currently runs CPU-only (`gpuLayers: 0`).
- **Quality**: a 1.5B model is genuinely capable of coherent multi-turn
  conversation and basic reasoning, but it's a small model, not a
  GPT-3.5/4-class one. The point of this project is the on-device
  inference pipeline, not chatbot quality.
- **Storage**: ~1.1GB on-device once downloaded, separate from the app's
  own install size (small, since the model isn't bundled). The target
  device should have a few GB of free RAM too, 1.5B at Q4 needs roughly
  1.5–2GB to load comfortably.

## Ideas to extend

- **Checksum verification**: after download completes, optionally compare
  against the GGUF's published SHA256 (visible on its Hugging Face file
  page) before treating it as valid, catches the rare case of a corrupted
  download that happens to land on the right byte count.
- **Background/notification download**: currently the download only runs
  while `DownloadScreen` is mounted. A true background download with a
  persistent Android notification is a separate piece of
  platform-specific work.
- **Persist conversations**: `llama_cpp_dart` supports `session.saveState()`
  / `loadState()` to a file, wire that into `Gpt2Engine` to survive app
  restarts.
- **Delete/re-download model**: add a settings option to delete the local
  GGUF (freeing ~1.1GB) and re-trigger the download flow, useful for
  switching quants or models without reinstalling the app.
- **Benchmark across devices**: log tokens/sec and load time across a
  range of phones, and compare quants (Q4_K_M vs Q5_K_M vs Q8_0) on
  quality vs speed.

## License

MIT, see [LICENSE](LICENSE). Use it, fork it, learn from it.
