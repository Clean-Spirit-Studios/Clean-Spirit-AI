# Clean Spirit AI

Privacy-focused offline AI chat for Flutter, powered by a locally-run Qwen2.5 LLM.

## What this app does

Clean Spirit AI is a chat app that runs an AI language model directly on
your phone. Once the model is downloaded, every conversation happens
entirely on-device. Nothing you type is sent to a server, no API key is
required, and the app has no ongoing internet dependency after setup.

## Why it's different

Most AI chat apps send every message to a company's server to be
processed. This app doesn't. The model (Qwen2.5-1.5B-Instruct) runs
locally using `llama.cpp`, so your conversations stay on your device.

- **Private by design.** Your messages never leave your phone after the
  model is downloaded.
- **Works offline.** No internet connection is needed once setup is done,
  useful for travel, poor signal areas, or just peace of mind.
- **No subscriptions, no API keys.** There's no account to create and
  nothing to pay for ongoing use.
- **One-time download.** The model downloads once on first launch and is
  reused for every conversation after that.

## Honest expectations

This app runs a small (1.5B parameter) model so it can fit and run on a
phone. It's genuinely capable of holding a coherent conversation, but it's
not as capable as large cloud-based models like ChatGPT or Claude. Think
of it as a private, offline assistant rather than a replacement for those.

- Storage: about 1.1GB for the model itself, downloaded separately from
  the app.
- RAM: a few GB of free RAM is recommended for smooth performance.
- Speed: a few tokens per second on a mid-range phone. Faster on more
  recent devices.

## How to install

### 1. Download the APK

Go to the [Releases](../../releases) page (or the Packages section) of
this repository and download the latest `.apk` file to your Android
device.

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

### 3. Open the app and download the model

On first launch, the app will show a download screen instead of going
straight to chat. This is expected, it's pulling down the 1.5B parameter
model (about 1.1GB) it needs to run.

- Make sure you're connected to the internet, ideally Wi-Fi since this is
  a large download.
- The app will warn you if you're on mobile data instead of Wi-Fi.
- If the download is interrupted (app closed, connection drops), just
  reopen the app and it will resume from where it left off rather than
  starting over.

### 4. Start chatting

Once the model finishes downloading, you're taken straight to the chat
screen. From this point on, the app works fully offline, no internet is
needed for any future conversation or app launch.

## License

MIT, see [LICENSE](LICENSE). Free to use, modify, and share.
