import 'dart:async';

import 'package:flutter/material.dart';

class RaptorLoadingScreen extends StatefulWidget {
  final String? statusMessage;
  final double? progress;

  const RaptorLoadingScreen({
    super.key,
    this.statusMessage,
    this.progress,
  });

  @override
  State<RaptorLoadingScreen> createState() => _RaptorLoadingScreenState();
}

class _RaptorLoadingScreenState extends State<RaptorLoadingScreen> {
  static const _frames = [
    'assets/raptor/frame_01.jpg',
    'assets/raptor/frame_02.jpg',
    'assets/raptor/frame_03.jpg',
    'assets/raptor/frame_04.jpg',
    'assets/raptor/frame_05.jpg',
    'assets/raptor/frame_06.jpg',
    'assets/raptor/frame_07.jpg',
  ];

  int _currentFrame = 0;
  Timer? _frameTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final path in _frames) {
        precacheImage(AssetImage(path), context);
      }
    });

    _frameTimer = Timer.periodic(const Duration(milliseconds: 111), (_) {
      if (!mounted) return;
      setState(() {
        _currentFrame = (_currentFrame + 1) % _frames.length;
      });
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // Fill more of the screen so the raptor feels intentional, not floating
    final imageSize = isLandscape
        ? (size.height * 0.50).clamp(0.0, 280.0)
        : (size.width * 0.52).clamp(0.0, 260.0);

    return Scaffold(
      // Pure black so the raptor's black background is seamless
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: imageSize,
          height: imageSize,
          child: Image.asset(
            _frames[_currentFrame],
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
