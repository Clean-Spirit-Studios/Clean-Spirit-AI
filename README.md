<div align="center">

# Clean Spirit AI

**A fully offline, privacy-first AI chat app for Android. Three on-device model options, GPU acceleration, image and document understanding - no server, no account, no subscription.**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

</div>

---

## What it does

Clean Spirit AI runs AI language models directly on your phone. Once a model is downloaded, conversations happen entirely on-device. Nothing you type is sent to a server, no API key is required, and the app has no ongoing internet dependency after the model download.

The app currently provides three model options: two Gemma 4 LiteRT models for GPU-accelerated on-device inference and Qwen3 4B through llama.cpp on CPU.

---

## Models

Choose a model from the first-launch download screen or manage models later from **Settings - Models**.

| Model | Engine | Download size | Best for |
|---|---|---:|---|
| Gemma 4 E2B Instruct | LiteRT (GPU with CPU fallback) | ~2.46 GB | Fast everyday chat, image understanding, quick replies |
| Gemma 4 E4B Instruct | LiteRT (GPU with CPU fallback) | ~3.40 GB | Higher-quality answers, complex questions, image understanding |
| Qwen3 4B Instruct | llama.cpp (CPU) | ~2.5 GB | Detailed reasoning, math, coding, long-form answers |

### Gemma 4 E4B

Gemma 4 E4B is the third model option and uses the **same LiteRT pathway as Gemma 4 E2B**. Both models are loaded through the shared `LiteRtEngine`, so E4B does not introduce a second inference backend.

E4B is the larger, higher-quality LiteRT option shown in the app UI. The model card notes that it needs approximately **5 GB RAM**. The download screen and Settings screen surface this requirement alongside the model size.

The configured model file is:

```text
gemma-4-E4B-it.litertlm
```

### LiteRT model switching

Only one LiteRT model can be loaded into the shared engine at a time. If the active LiteRT model changes between E2B and E4B, the app disposes the current LiteRT engine and reloads it with the selected model file.

E2B and E4B can both be downloaded to the device, but they are alternatives at runtime rather than simultaneously loaded models.

### Auto mode

Auto selects the best available model using this priority order:

**Gemma 4 E4B > Gemma 4 E2B > Qwen3 4B**

This means:

- If E4B is downloaded, Auto prefers E4B.
- If E4B is unavailable but E2B is downloaded, Auto uses E2B.
- If neither LiteRT model is available, Auto falls back to Qwen3 4B.
- You can explicitly select E2B, E4B, or Qwen3 4B from the model selector instead of using Auto.

### Lazy loading

Only the active model is loaded into memory. Downloading multiple models does not load them all simultaneously. Switching models loads the selected model on demand.

---

## Features

- **Fully offline** - no internet needed after model download, no telemetry, no accounts
- **GPU acceleration** - Gemma E2B and E4B run through Google LiteRT for on-device inference, with the existing CPU fallback path
- **Three model options** - Gemma 4 E2B, Gemma 4 E4B, and Qwen3 4B
- **Higher-quality LiteRT option** - Gemma 4 E4B is available as a separate downloadable model
- **Image understanding** - attach photos from camera or gallery; supported Gemma models can describe and reason about them
- **Document attachment** - attach PDF, DOCX, or plain text files; extracted text is injected as chat context
- **Conversation history** - past chats are saved automatically and browsable from the drawer
- **Incognito mode** - conversations in incognito are never written to storage
- **Resumable downloads** - model downloads resume from where they left off if interrupted
- **Mobile data warning** - prompts for confirmation before downloading on a mobile data connection
- **Markdown rendering** - assistant replies render headers, bold, code blocks, tables, and lists
- **Settings page** - manage each downloaded model with download, progress, cancel, delete, and disk-size information
- **Dark theme** - Material 3 deep purple, dark throughout

---

## Chat screen

- **Model pill** - tap the model pill below the app title to switch between Gemma E2B, Gemma E4B, Qwen3 4B, or Auto
- **Attach button** - attach an image from camera/gallery or a document such as PDF, DOCX, or TXT
- **Incognito toggle** - tap the ghost icon in the top-right to enable or disable incognito for the current conversation
- **Drawer** - swipe from the left or tap the hamburger menu to browse past conversations, start a new one, or open Settings
- **Copy** - long-press any message bubble to copy its text

### Model selector

The model selector exposes the four runtime choices:

| Selection | Runtime behavior |
|---|---|
| Gemma 4 E2B | Loads the E2B `.litertlm` model through `LiteRtEngine` |
| Gemma 4 E4B | Loads the E4B `.litertlm` model through the same `LiteRtEngine` |
| Qwen3 4B | Loads the Qwen3 GGUF model through llama.cpp |
| Auto | Chooses E4B, then E2B, then Qwen3 based on downloaded models |

Switching between E2B and E4B reloads the shared LiteRT engine. The existing chat loading overlay is used while the model changes.

---

## Download screen

The first-launch download flow offers the model choices as cards using the existing app theme.

### Gemma 4 E2B

- LiteRT badge
- GPU - LiteRT label
- Approximately 2.46 GB
- Recommended treatment in the chooser
- Fast, vision-capable everyday model

### Gemma 4 E4B

- LiteRT badge using the same engine-family accent as E2B
- GPU - LiteRT label
- Approximately 3.40 GB
- **Best quality** badge
- Higher-quality Gemma option
- Inline warning that approximately 5 GB RAM is needed

### Qwen3 4B

- GGUF badge
- CPU / llama.cpp path
- Approximately 2.5 GB
- Intended for detailed reasoning, math, coding, and long-form responses

### Download Both

The existing **Download Both** option remains E2B + Qwen3 4B for compatibility with the previous two-model flow.

It does not automatically include E4B. E4B can be downloaded separately from its model card.

---

## Settings

Accessible from the hamburger drawer.

### Models

- See which models are downloaded and their size on disk
- Download E2B, E4B, or Qwen3 4B directly from Settings
- View live download progress
- Cancel an active download
- Delete a downloaded model to free storage
- E4B shows its approximately 5 GB RAM requirement directly on the model card

Downloading E4B does not automatically make it the active model. Select E4B from the model selector when you want to switch to it. Auto mode will prefer E4B when it is available.

### Chat behaviour

- Start new conversations in incognito mode by default
- Send on Enter toggle
- Response font size - small / medium / large

---

## Quick setup

### Prerequisites

```text
Flutter SDK 3.x  (flutter.dev/docs/get-started/install)
Android Studio with Android NDK (for native llama.cpp build)
```

### 1. Get dependencies

```bash
flutter pub get
```

### 2. Run on device

```bash
flutter run
```

### 3. Build release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Installing the APK

1. Download the `.apk` from the [Releases](../../releases) page to your Android device.
2. Open the file. Android will block it by default since it is not from the Play Store.
3. Tap **Settings** on the warning screen and enable **Allow from this source** for your browser or file manager.
4. Go back and tap **Install**.

On first launch the app shows the model download screen. Pick a model, connect to Wi-Fi, and wait for the download to complete. The screen stays on automatically during the download so it is not interrupted. If the download is cut short, reopen the app and the resumable downloader continues from where it left off.

---

## Download screen stages

| Stage | What is shown |
|---|---|
| Choosing model | Branded hero, E2B, E4B, Qwen3, and Download Both cards with size labels and feature descriptions |
| Checking connection | Brief network check before starting |
| Confirming mobile data | Orange warning card if not on Wi-Fi |
| Downloading | Circular progress ring with byte counter |
| Error | Red icon with resume notice |

---

## Dependencies

| Package | Purpose |
|---|---|
| `flutter_litert_lm` | LiteRT-LM inference for Gemma E2B and E4B (local plugin) |
| `llama_cpp_dart` | llama.cpp CPU inference for Qwen3 4B (GGUF) |
| `resumable_downloader` | Resumable HTTP downloads for model files |
| `dio` | HTTP client - HEAD requests for download size |
| `connectivity_plus` | Detects mobile data before download |
| `wakelock_plus` | Keeps screen on during model download |
| `path_provider` | Resolves app-private storage paths |
| `shared_preferences` | Persists conversation history, model preference, and settings |
| `flutter_markdown` | Markdown rendering in chat bubbles |
| `image_picker` | Camera and gallery image picker |
| `file_picker` | Document file picker |
| `permission_handler` | Runtime camera and storage permissions |
| `syncfusion_flutter_pdf` | PDF text extraction (no char limit) |
| `archive` + `xml` | DOCX text extraction (pure Dart) |
| `lottie` | Animated loading screen while model initialises |
| `flutter_svg` | Ghost icon for incognito mode |

No additional dependency is required for Gemma 4 E4B. It uses the existing LiteRT integration.

---

## Project structure

```text
lib/
  main.dart                  - Entry point, decides download vs chat on cold start
  chat_screen.dart           - Full chat UI, drawer, incognito, model selector
  download_screen.dart       - First-launch model download flow and model cards
  dual_engine.dart           - Coordinates Gemma E2B/E4B LiteRT and Qwen3 GGUF engines
  litert_engine.dart         - Shared LiteRT-LM wrapper for Gemma inference
  model_loader.dart          - Download, existence checks, path resolution for all models
  conversation_store.dart    - SharedPreferences-backed conversation history
  attachment_service.dart    - Image and document picker
  document_extractor.dart    - PDF, DOCX, and plain text extraction
  markdown_renderer.dart     - flutter_markdown wrapper themed to chat bubbles
  chat_message.dart          - ChatTurn model (role, text, attachments)
  settings_screen.dart       - Model management and chat preferences

assets/
  animations/
    model_loading.json       - Lottie animation shown while model initialises
  icons/
    ghost.svg                - Ghost icon for incognito toggle

local_plugins/
  flutter_litert_lm/         - Local LiteRT-LM plugin (not on pub.dev)
```

---

## Android permissions

| Permission | Why |
|---|---|
| `INTERNET` | Model download on first launch |
| `ACCESS_NETWORK_STATE` | Detect Wi-Fi vs mobile data before download |
| `CAMERA` | Image attachment via camera |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Image attachment from gallery |
| `WAKE_LOCK` | Keep screen on during model download |

---

## Model storage and RAM expectations

Approximate model storage requirements:

| Installed model(s) | Approximate storage |
|---|---:|
| Gemma 4 E2B only | ~2.46 GB |
| Gemma 4 E4B only | ~3.40 GB |
| Qwen3 4B only | ~2.5 GB |
| E2B + Qwen3 4B | ~5 GB |
| E4B + Qwen3 4B | ~5.9 GB |
| E2B + E4B | ~5.86 GB |
| E2B + E4B + Qwen3 4B | ~8.36 GB |

These are model download/storage figures, not a guarantee of runtime memory usage.

Gemma 4 E4B is the higher-quality LiteRT option and its model card calls for approximately **5 GB RAM**. Devices with limited available RAM may experience slower loading or may rely on the existing LiteRT CPU fallback if GPU loading cannot be used.

Because E2B and E4B share one `LiteRtEngine`, only one of the two LiteRT models is resident in memory at a time.

---

## LiteRT architecture

The LiteRT model path is shared between Gemma E2B and E4B:

```text
Gemma 4 E2B .litertlm ─┐
                       ├─> LiteRtEngine ─> GPU / CPU fallback ─> Chat
Gemma 4 E4B .litertlm ─┘

Qwen3 4B .gguf ─────────> llama.cpp ─────────────────────────> Chat
```

The E4B integration adds model selection, downloading, persistence, and UI handling without introducing a new inference engine.

The LiteRT engine's existing GPU crash guard remains model-agnostic. If GPU loading falls back to CPU, the same backend behavior is available to both E2B and E4B.

---

## Model download source

Gemma 4 E4B is configured to download the LiteRT-LM model from the `litert-community` Hugging Face repository using:

```text
https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
```

Configured file:

```text
gemma-4-E4B-it.litertlm
```

The app displays the requested approximate size of **3.40 GB** in its model cards. Actual network download size can differ from the UI estimate as the hosted model artifact changes.

---

## Version

Current application version: **0.3.0**

The 0.3.0 update adds Gemma 4 E4B as the third model option while retaining the existing E2B and Qwen3 flows.

---

## Honest expectations

These are compact on-device models designed to fit and run on phones. They can hold coherent conversations and handle a wide range of everyday tasks, but they are not as capable as large cloud-based models. Think of Clean Spirit AI as a private, always-available offline assistant rather than a replacement for large hosted models.

- **Storage** - model files require several GB depending on which options you download
- **RAM** - E4B's model card calls for approximately 5 GB RAM; available device memory also affects runtime behavior
- **Speed** - Gemma uses the LiteRT path and can use GPU acceleration; Qwen3 runs through llama.cpp on CPU
- **Quality** - E4B is positioned as the higher-quality Gemma option, while E2B favors speed and Qwen3 provides a separate CPU reasoning path

---

## License

MIT - see [LICENSE](LICENSE). Free to use, modify, and distribute.
