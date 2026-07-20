# Clean Spirit AI

Privacy-focused offline AI chat for Flutter, powered by locally-run Qwen LLMs.

## What this app does

Clean Spirit AI is a chat app that runs an AI language model directly on
your phone. Once the model is downloaded, every conversation happens
entirely on-device. Nothing you type is sent to a server, no API key is
required, and the app has no ongoing internet dependency after setup.

## Why it's different

Most AI chat apps send every message to a company's server to be
processed. This app doesn't. Models run locally using `llama.cpp`, so
your conversations stay on your device.

- **Private by design.** Your messages never leave your phone after the
  model is downloaded.
- **Works offline.** No internet connection is needed once setup is done,
  useful for travel, poor signal areas, or just peace of mind.
- **No subscriptions, no API keys.** There's no account to create and
  nothing to pay for ongoing use.
- **One-time download.** The model downloads once on first launch and is
  reused for every conversation after that.

## Models

The app supports two models. You choose which to download on first launch.

| Option | Model | Size | Best for |
|--------|-------|------|----------|
| 1 - Faster, Less Accurate | QWEN2.5 1.5B | ~900MB | Quick chats, simple questions, everyday conversation |
| 2 - Slower, More Accurate | QWEN3 4B | ~2.5GB | Math, coding, factual questions, detailed explanations |
| 3 - Download Both | Both models | ~3.5GB | Auto Switch mode (recommended) |

### Auto Switch

If both models are downloaded, the app defaults to **Auto Switch** mode.
It classifies each message automatically and routes it to the right model:

- Short greetings, small talk, and simple questions go to the 1.5B model
  for a faster response.
- Longer messages, factual queries, calculations, and anything requiring
  more reasoning go to the 4B model for a more accurate answer.

You can override Auto Switch at any time using the model switcher in the
top-right corner of the chat screen.

## Honest expectations

This app runs small models so they can fit and run on a phone. They're
genuinely capable of holding a coherent conversation, but they're not as
capable as large cloud-based models like ChatGPT or Claude. Think of it as
a private, offline assistant rather than a replacement for those.

- **Storage:** ~900MB for 1.5B only, ~2.5GB for 4B only, ~3.5GB for both.
- **RAM:** a few GB of free RAM is recommended for smooth performance.
- **Speed:** a few tokens per second on a mid-range phone. Faster on more
  recent devices.

## How to install

### 1. Download the APK

Go to the [Releases](../../releases) page of this repository and download
the latest `.apk` file to your Android device.

### 2. Allow installs from outside the Play Store

Since this isn't distributed through the Play Store, Android will block
the install by default. To allow it:

1. Open the downloaded APK file.
2. If prompted, tap **Settings** on the warning screen.
3. Enable **Allow from this source** for the app you used to download the
   file (e.g. your browser or file manager).
4. Go back and tap **Install**.

Exact wording varies slightly by Android version and manufacturer, but
the flow is the same: Android will ask you to explicitly allow the
install source, then let you proceed.

### 3. Choose a model and download it

On first launch, the app shows a model selection screen with three options.
Pick whichever suits your storage and use case (see the table above).
Downloading Both is recommended if you have the space - it enables Auto
Switch so the app picks the right model for each message automatically.

- Use Wi-Fi if possible - the downloads are large (up to ~3.5GB combined).
- The app will warn you if you're on mobile data instead of Wi-Fi.
- The screen stays on automatically during the download so it isn't
  interrupted by your device going to sleep.
- If the download is interrupted (app closed, connection drops), just
  reopen the app and it will resume from where it left off rather than
  starting over.

### 4. Start chatting

Once the model finishes downloading, you're taken straight to the chat
screen. From this point on, the app works fully offline - no internet is
needed for any future conversation or app launch.

## Chat screen

- **Model switcher** - tap the pill in the top-right corner to switch
  between QWEN2.5 1.5B, QWEN3 4B, or Auto Switch. Only models you have
  downloaded are shown.
- **Auto Switch label** - in Auto mode, a small label beneath each
  assistant reply shows which model handled it.
- **Thinking panel** - the 4B model shows its reasoning trace in a
  collapsible "Thought process" panel above each reply. It expands
  automatically while the model is thinking and collapses once the answer
  arrives.
- **Copy** - tap or long-press any message bubble to copy its text.

## Dependencies

| Package | Purpose |
|---------|---------|
| `llama_cpp_dart` | On-device LLM inference via llama.cpp |
| `resumable_downloader` | Resumable HTTP downloads for the model files |
| `dio` | HTTP client (HEAD requests for download size display) |
| `connectivity_plus` | Detects mobile-data-only connections before download |
| `wakelock_plus` | Keeps the screen on during model download |
| `path_provider` | Resolves app-private storage paths |

## License

MIT, see [LICENSE](LICENSE). Free to use, modify, and share.
