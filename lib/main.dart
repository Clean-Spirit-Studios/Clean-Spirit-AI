// main.dart
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'download_screen.dart';
import 'model_loader.dart';

void main() {
  runApp(const Gpt2ChatApp());
}

class Gpt2ChatApp extends StatelessWidget {
  const Gpt2ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Spirit AI',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const _AppRoot(),
    );
  }
}

/// Decides, on every cold start, whether to show the one-time download
/// flow or go straight to the chat screen. This check is cheap (just a
/// file-existence check on disk) so it's fine to run on every launch
/// rather than caching the result anywhere.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

enum _RootState { checking, needsDownload, ready }

class _AppRootState extends State<_AppRoot> {
  _RootState _state = _RootState.checking;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final downloaded = await ModelLoader.isModelDownloaded();
    if (!mounted) return;
    setState(() {
      _state = downloaded ? _RootState.ready : _RootState.needsDownload;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _RootState.checking:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _RootState.needsDownload:
        return DownloadScreen(
          onDownloadComplete: () {
            setState(() => _state = _RootState.ready);
          },
        );
      case _RootState.ready:
        return const ChatScreen();
    }
  }
}
