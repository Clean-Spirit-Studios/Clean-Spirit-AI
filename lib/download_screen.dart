// download_screen.dart
//
// Shown on first app launch (or any launch where the model hasn't finished
// downloading yet) before the chat screen. Handles:
//   - warning the user if they're on mobile data before a ~1.1GB download
//   - showing live progress (percentage bar, MB downloaded / total if known)
//   - resuming automatically if a previous download was interrupted
//     (ModelLoader.downloadModel() / resumable_downloader handles this
//     transparently via HTTP Range requests)
//   - surfacing a clear retry option on failure
//
// This is the ONLY screen in the app that touches the network. Once the
// model file exists on disk, every other screen (chat_screen.dart) is
// 100% offline, exactly as before.

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'model_loader.dart';

class DownloadScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;
  const DownloadScreen({super.key, required this.onDownloadComplete});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

enum _Stage { checkingConnection, confirmingMobileData, downloading, error }

class _DownloadScreenState extends State<DownloadScreen> {
  _Stage _stage = _Stage.checkingConnection;
  double _fraction = 0.0;
  int? _totalBytes; // null until the HEAD request resolves, may stay null
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _checkConnectionThenStart();
    // Fire-and-forget — purely cosmetic (lets us show "X MB / Y MB"
    // instead of just a percentage). Download proceeds regardless of
    // whether this resolves.
    ModelLoader.fetchTotalSizeBytes().then((bytes) {
      if (mounted && bytes != null) {
        setState(() => _totalBytes = bytes);
      }
    });
  }

  Future<void> _checkConnectionThenStart() async {
    setState(() => _stage = _Stage.checkingConnection);

    final connectivity = await Connectivity().checkConnectivity();
    final hasWifi = connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
    final hasMobile = connectivity.contains(ConnectivityResult.mobile);
    final hasNone = connectivity.contains(ConnectivityResult.none) ||
        connectivity.isEmpty;

    if (hasNone) {
      setState(() {
        _stage = _Stage.error;
        _errorText =
            'No internet connection detected. The AI model (~1.1GB) needs '
            'to be downloaded once before the app can be used offline. '
            'Connect to the internet and try again.';
      });
      return;
    }

    if (hasMobile && !hasWifi) {
      // Mobile data only — warn before starting, per the user's choice to
      // allow any connection but flag it first rather than block outright.
      setState(() => _stage = _Stage.confirmingMobileData);
      return;
    }

    _startDownload();
  }

  void _startDownload() {
    setState(() {
      _stage = _Stage.downloading;
      _errorText = null;
    });

    ModelLoader.downloadModel(
      onProgress: (fraction) {
        if (!mounted) return;
        setState(() => _fraction = fraction);
      },
    ).then((_) {
      if (!mounted) return;
      widget.onDownloadComplete();
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorText = 'Download failed: $e';
      });
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: _buildContent()),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_stage) {
      case _Stage.checkingConnection:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking connection…'),
          ],
        );

      case _Stage.confirmingMobileData:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_cellular_alt, size: 40),
            const SizedBox(height: 16),
            const Text(
              "You're on mobile data",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'The AI model is about 1.1GB. Downloading over mobile data '
              'may use a large chunk of your data plan. This only happens '
              'once — after this, the app works fully offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _checkConnectionThenStart,
                  child: const Text('Wait for Wi-Fi'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _startDownload,
                  child: const Text('Download anyway'),
                ),
              ],
            ),
          ],
        );

      case _Stage.downloading:
        final received =
            _totalBytes != null ? (_fraction * _totalBytes!).round() : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Downloading AI model…',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'One-time download — the app works fully offline after this.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _fraction, minHeight: 10),
            ),
            const SizedBox(height: 12),
            Text(
              _totalBytes != null
                  ? '${_formatBytes(received!)} / ${_formatBytes(_totalBytes!)}  (${(_fraction * 100).toStringAsFixed(0)}%)'
                  : '${(_fraction * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () async {
                await ModelLoader.cancelDownload();
                if (mounted) {
                  setState(() => _stage = _Stage.error);
                }
              },
              child: const Text('Cancel'),
            ),
          ],
        );

      case _Stage.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _errorText ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_fraction > 0)
              const Text(
                'Don\'t worry — what\'s already downloaded will resume from '
                'where it left off.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _checkConnectionThenStart,
              child: const Text('Retry'),
            ),
          ],
        );
    }
  }
}
