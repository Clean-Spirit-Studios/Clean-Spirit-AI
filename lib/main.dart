// main.dart
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'download_screen.dart';
import 'model_loader.dart';

void main() {
  runApp(const CleanSpiritApp());
}

class CleanSpiritApp extends StatelessWidget {
  const CleanSpiritApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Spirit AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const _AppRoot(),
    );
  }
}

/// Decides on every cold start whether to show the one-time download flow
/// or go straight to the chat screen. At least one model must be present
/// to skip the download flow.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool? _hasModel;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (var i = 1; i <= 7; i++) {
      precacheImage(
        AssetImage('assets/raptor/frame_0$i.jpg'),
        context,
      );
    }
  }

  Future<void> _check() async {
    final downloaded = await ModelLoader.isAnyModelDownloaded();
    if (!mounted) return;
    setState(() => _hasModel = downloaded);
  }

  @override
  Widget build(BuildContext context) {
    // Never block the first frame on model discovery. ChatScreen immediately
    // renders its welcome UI and starts model initialization in the background.
    // If this is the first launch with no model on disk, the fast presence
    // check switches to the existing download flow.
    if (_hasModel == null) {
      // Keep the first frame model-free. ChatScreen must not initialize the
      // engine until we know a model exists, otherwise first launch briefly
      // shows a ModelNotFoundException before DownloadScreen appears.
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_hasModel == false) {
      return DownloadScreen(
        onDownloadComplete: () {
          setState(() => _hasModel = true);
        },
      );
    }

    return const ChatScreen();
  }
}
