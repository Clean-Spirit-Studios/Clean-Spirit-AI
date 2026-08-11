# Clean Spirit AI - LiteRT Upgrade Setup Guide

This package contains all modified and new Dart/config files for the
Gemma 4 E2B (LiteRT GPU) + Qwen3 4B (GGUF CPU) dual-engine upgrade.

---

## What Changed

| File | Status | What it does |
|---|---|---|
| `lib/main.dart` | Modified | Uses `isAnyModelDownloaded()` instead of old method |
| `lib/model_loader.dart` | Rewritten | Gemma (LiteRT) + Qwen3 4B (GGUF) constants and download |
| `lib/litert_engine.dart` | New | LiteRT-LM GPU engine with crash guard, vision, Gemma cleanup |
| `lib/dual_engine.dart` | New | Coordinates both engines - loads only the startup model |
| `lib/chat_message.dart` | Updated | Added `imagePath`, `documentName`, `modelLabel` fields |
| `lib/chat_screen.dart` | Rewritten | Dual model switcher, attachment UI, architecture labels |
| `lib/download_screen.dart` | Rewritten | Shows both models with LiteRT vs GGUF architecture info |
| `lib/attachment_service.dart` | New | Image picker (gallery/camera) and file picker |
| `lib/document_extractor.dart` | New | PDF and DOCX text extraction for context injection |
| `lib/markdown_renderer.dart` | Unchanged | Copied as-is |
| `pubspec.yaml` | Updated | Added LiteRT, image_picker, file_picker, archive, xml, syncfusion_flutter_pdf |
| `android/app/build.gradle.kts` | Updated | NDK 27 for LiteRT native layer |
| `android/app/src/main/AndroidManifest.xml` | Updated | Camera + media permissions |

---

## Step 1 - Copy the Local Plugins

The `flutter_litert_lm` plugin is not on pub.dev. Copy it from the
cross-platform-llm-client project:

```
cross-platform-llm-client-main/local_plugins/flutter_litert_lm/
  -> your-project/local_plugins/flutter_litert_lm/
```

Also copy the OpenMP native library (required by LiteRT):

```
cross-platform-llm-client-main/android/app/src/main/jniLibs/arm64-v8a/libomp.so
  -> your-project/android/app/src/main/jniLibs/arm64-v8a/libomp.so
```

The `llama-cpp-dart.aar` file stays in `android/app/libs/` as before -
it is still needed for Qwen3 4B on the GGUF path.

---

## Step 2 - Replace Files in Your Project

Copy all files from this package's `lib/` folder into your project's `lib/`.

Copy:
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `pubspec.yaml`

Delete from your project (no longer needed):
- `lib/gpt2_engine.dart`

---

## Step 3 - Run pub get

```bash
flutter pub get
```

---

## Step 4 - Model Download URLs

The models will be downloaded on first launch. URLs are in `model_loader.dart`:

- **Gemma 4 E2B (LiteRT):** `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/...`
- **Qwen3 4B (GGUF):** `https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/...`

---

## How the Dual Engine Works

### Startup behaviour
`dual_engine.dart` loads **only the model that will be used** based on the
saved preference (or the best default). It does NOT load both models at once.
Loading 2x 2.5 GB models simultaneously would take minutes and use excessive RAM.

- Default (no saved preference + both downloaded): **Auto** mode = loads Gemma (LiteRT)
- If only Gemma is downloaded: loads Gemma
- If only Qwen3 is downloaded: loads Qwen3

### Switching models at runtime
When the user switches from Gemma to Qwen3 (or vice versa) in the AppBar
model switcher, `switchToModel()` is called. If the target model is already
in memory, the switch is instant. If not, it loads it - showing a small
spinner in the AppBar.

### Auto mode
Auto always routes to Gemma (LiteRT GPU) when it is loaded. Qwen3 is
only used in Auto if Gemma failed to load.

---

## GPU Crash Guard

The first time Gemma loads on GPU, the LiteRT runtime compiles XNNPack
kernels - this can take 30-60 seconds and the process may be killed by
Android's OOM killer on low-memory devices.

`litert_engine.dart` handles this automatically:
1. Sets a `litert_gpu_load_pending = true` flag in SharedPreferences before load
2. On success: clears the flag
3. On next launch: if the flag is still set (crash detected), falls back to CPU
   automatically and sets `litert_gpu_crash_detected = true`

The user can manually switch back to GPU from the AppBar model switcher
("Switch Gemma to GPU") - this clears the crash flag and retries.

---

## Architecture Summary

```
AppBar pill:  [⚡ Gemma E2B - GPU]  or  [🧠 Qwen3 4B - CPU]  or  [Auto - GPU]

Model chooser popup:
  Gemma 4 E2B - LiteRT   [LiteRT badge - teal]   GPU-accelerated - vision-capable - fast
  Qwen3 4B - GGUF        [GGUF badge - orange]   CPU-based - thorough reasoning
  ─────────────────────
  Auto                   [Auto badge]             Defaults to Gemma (LiteRT GPU)
  ─────────────────────
  Switch Gemma to CPU (safe)  /  Switch Gemma to GPU (fast)

Download screen:
  Gemma 4 E2B - GPU (LiteRT)   ~2.46 GB   [Recommended]
  Qwen3 4B - CPU (GGUF)        ~2.5 GB
  Download Both                ~5 GB       (enables Auto mode)
```

---

## Key Design Decisions

- **No model is pre-loaded unless selected** - startup loads one model only
- **Auto defaults to Gemma** - it is faster and GPU-accelerated
- **Vision only on Gemma/LiteRT** - sending an image to Qwen3 shows a snackbar
- **Document context** - any attached doc text is injected as a prompt prefix,
  truncated to 3000 chars with a snackbar warning if trimmed
- **Architecture labels everywhere** - download screen, model switcher pill,
  bubble footer label all show LiteRT vs GGUF so users always know which engine ran
- **No em dashes** - all user-facing strings use hyphens or commas
