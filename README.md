<div align="center">



# Clean Spirit AI

**A fully offline, privacy-first AI chat app for Android. Two on-device models, GPU acceleration, image and document understanding - no server, no account, no subscription.**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

</div>

---

## What it does

Clean Spirit AI runs AI language models directly on your phone. Once a model is downloaded, every conversation happens entirely on-device. Nothing you type is sent to a server, no API key is required, and the app has no ongoing internet dependency after setup.

---

## Models

Two models are available. Download either or both from the download screen on first launch, or from **Settings - Models** at any time.

| Model | Engine | Size | Best for |
|---|---|---|---|
| Gemma 4 E2B Instruct | LiteRT (GPU) | ~2.46 GB | Everyday chat, image understanding, fast replies |
| Qwen3 4B Instruct | llama.cpp (CPU) | ~2.5 GB | Detailed reasoning, math, coding, long-form answers |

### Auto mode

When both models are downloaded the model selector defaults to **Auto**. Auto always routes to Gemma (LiteRT GPU) for its speed advantage. You can override it at any time by tapping the model pill in the app bar.

### Lazy loading

Only the active model is loaded into memory at startup. Switching models loads the other one on demand. This keeps startup fast regardless of how many models are installed.

---

## Features

- **Fully offline** - no internet needed after model download, no telemetry, no accounts
- **GPU acceleration** - Gemma runs via Google LiteRT for fast on-device inference
- **Image understanding** - attach photos from camera or gallery; Gemma describes and reasons about them
- **Document attachment** - attach PDF, DOCX, or plain text files; extracted text is injected as chat context
- **Conversation history** - past chats are saved automatically and browsable from the drawer
- **Incognito mode** - conversations in incognito are never written to storage
- **Resumable downloads** - model downloads resume from where they left off if interrupted
- **Mobile data warning** - prompts for confirmation before downloading on a mobile data connection
- **Markdown rendering** - assistant replies render headers, bold, code blocks, tables, and lists
- **Settings page** - manage downloaded models (download, delete, check size on disk), plus chat preferences
- **Dark theme** - Material 3 deep purple, dark throughout

---

## Chat screen

- **Model pill** - tap the pill below the app title to switch between Gemma, Qwen3 4B, or Auto
- **Attach button** - attach an image (camera or gallery) or a document (PDF, DOCX, TXT and more)
- **Incognito toggle** - tap the ghost icon in the top-right to enable or disable incognito for the current conversation
- **Drawer** - swipe from the left or tap the hamburger menu to browse past conversations, start a new one, or open Settings
- **Copy** - long-press any message bubble to copy its text

---

## Settings

Accessible from the hamburger drawer.

### Models
- See which models are downloaded and their size on disk
- Download a model directly from Settings with a live progress bar and cancel option
- Delete a downloaded model to free up storage

### Chat behaviour
- Start new conversations in incognito mode by default
- Send on Enter toggle
- Response font size (small / medium / large)

---

## Quick setup

### Prerequisites

```
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

On first launch the app shows the model download screen. Pick a model, connect to Wi-Fi, and wait for the download to complete. The screen stays on automatically during the download so it is not interrupted. If the download is cut short, just reopen the app - it resumes where it left off.

---

## Download screen stages

| Stage | What is shown |
|---|---|
| Choosing model | Branded hero, model cards with size labels and feature descriptions |
| Checking connection | Brief network check before starting |
| Confirming mobile data | Orange warning card if not on Wi-Fi |
| Downloading | Circular progress ring with byte counter |
| Error | Red icon with resume notice |

---

## Dependencies

| Package | Purpose |
|---|---|
| `flutter_litert_lm` | LiteRT-LM GPU inference for Gemma (local plugin) |
| `llama_cpp_dart` | llama.cpp CPU inference for Qwen3 4B (GGUF) |
| `resumable_downloader` | Resumable HTTP downloads for model files |
| `dio` | HTTP client - HEAD requests for download size |
| `connectivity_plus` | Detects mobile data before download |
| `wakelock_plus` | Keeps screen on during model download |
| `path_provider` | Resolves app-private storage paths |
| `shared_preferences` | Persists conversation history and settings |
| `flutter_markdown` | Markdown rendering in chat bubbles |
| `image_picker` | Camera and gallery image picker |
| `file_picker` | Document file picker |
| `permission_handler` | Runtime camera and storage permissions |
| `syncfusion_flutter_pdf` | PDF text extraction (no char limit) |
| `archive` + `xml` | DOCX text extraction (pure Dart) |
| `lottie` | Animated loading screen while model initialises |
| `flutter_svg` | Ghost icon for incognito mode |

---

## Project structure

```
lib/
  main.dart                  - Entry point, decides download vs chat on cold start
  chat_screen.dart           - Full chat UI, drawer, incognito, model switcher
  download_screen.dart       - First-launch model download flow (5 stages)
  dual_engine.dart           - Coordinates Gemma (LiteRT) and Qwen3 (GGUF) engines
  litert_engine.dart         - LiteRT-LM wrapper for Gemma GPU inference
  model_loader.dart          - Download, existence checks, path resolution for both models
  conversation_store.dart    - SharedPreferences-backed conversation history
  attachment_service.dart    - Image (camera/gallery) and document picker
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

## Honest expectations

These are small models designed to fit and run on a phone. They hold coherent conversations and handle a wide range of everyday tasks, but they are not as capable as large cloud-based models. Think of it as a private, always-available offline assistant rather than a replacement for ChatGPT or Claude.

- **Storage** - ~2.46 GB for Gemma only, ~2.5 GB for Qwen3 only, ~5 GB for both
- **RAM** - a few GB of free RAM recommended for smooth performance
- **Speed** - Gemma runs on the GPU and is noticeably faster; Qwen3 runs on CPU and is slower but more thorough

---

## License

MIT - see [LICENSE](LICENSE). Free to use, modify, and distribute.
