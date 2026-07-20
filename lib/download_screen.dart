// download_screen.dart
//
// Shown on first app launch before the chat screen.
// Step 1: user picks which model(s) to download.
// Step 2: connectivity check (warn on mobile data).
// Step 3: download with live progress bar.
//
// Option 1 - 1.5B (Faster, Less Accurate)  ~900 MB
// Option 2 - 4B   (Slower, More Accurate)  ~2.5 GB
// Option 3 - Download both

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'model_loader.dart';

class DownloadScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;
  const DownloadScreen({super.key, required this.onDownloadComplete});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

enum _Stage {
  choosingModel,
  checkingConnection,
  confirmingMobileData,
  downloading,
  error,
}

class _DownloadScreenState extends State<DownloadScreen> {
  _Stage _stage = _Stage.choosingModel;
  double _fraction = 0.0;
  int? _totalBytes;
  String? _errorText;

  // Which models the user chose to download (null = not yet chosen)
  List<ModelVariant>? _modelsToDownload;
  int _currentDownloadIndex = 0;

  String get _choiceLabel {
    if (_modelsToDownload == null) return '';
    if (_modelsToDownload!.length == 2) return 'Both models';
    return _modelsToDownload!.first == ModelVariant.fast
        ? 'QWEN2.5 1.5B'
        : 'QWEN3 4B';
  }

  void _onModelChosen(List<ModelVariant> variants) {
    _modelsToDownload = variants;
    _checkConnectionThenStart();
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
            'No internet connection detected. The AI model needs to be '
            'downloaded once before the app can be used offline. '
            'Connect to the internet and try again.';
      });
      return;
    }

    if (hasMobile && !hasWifi) {
      setState(() => _stage = _Stage.confirmingMobileData);
      return;
    }

    _startDownload();
  }

  void _startDownload() {
    _currentDownloadIndex = 0;
    setState(() {
      _stage = _Stage.downloading;
      _fraction = 0.0;
      _errorText = null;
    });

    // Keep screen on for the duration of the download - it can take several
    // minutes on a slow connection and we don't want it interrupted by sleep.
    WakelockPlus.enable();

    _fetchSizeAndDownloadNext();
  }

  Future<void> _fetchSizeAndDownloadNext() async {
    if (_modelsToDownload == null ||
        _currentDownloadIndex >= _modelsToDownload!.length) return;

    final variant = _modelsToDownload![_currentDownloadIndex];

    // Fire-and-forget size fetch for display
    ModelLoader.fetchTotalSizeBytes(variant: variant).then((bytes) {
      if (mounted && bytes != null) {
        setState(() => _totalBytes = bytes);
      }
    });

    ModelLoader.downloadModel(
      variant: variant,
      onProgress: (fraction) {
        if (!mounted) return;
        setState(() => _fraction = fraction);
      },
    ).then((_) {
      if (!mounted) return;
      _currentDownloadIndex++;
      if (_currentDownloadIndex < (_modelsToDownload?.length ?? 0)) {
        // Start next model
        setState(() {
          _fraction = 0.0;
          _totalBytes = null;
        });
        _fetchSizeAndDownloadNext();
      } else {
        WakelockPlus.disable();
        widget.onDownloadComplete();
      }
    }).catchError((e) {
      if (!mounted) return;
      WakelockPlus.disable();
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

  String get _downloadingTitle {
    if (_modelsToDownload == null) return '';
    final current = _modelsToDownload![_currentDownloadIndex];
    final label = current == ModelVariant.fast ? 'QWEN2.5 1.5B' : 'QWEN3 4B';
    return 'Downloading $label...';
  }

  String get _downloadingStepLabel {
    if (_modelsToDownload == null) return '';
    final total = _modelsToDownload!.length;
    return 'Step ${_currentDownloadIndex + 1} of $total';
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
      case _Stage.choosingModel:
        return _ModelChooser(onChosen: _onModelChosen);

      case _Stage.checkingConnection:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking connection...'),
          ],
        );

      case _Stage.confirmingMobileData:
        final isLarge = _modelsToDownload?.length == 2 ||
            _modelsToDownload?.first == ModelVariant.accurate;
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
            Text(
              'The ${isLarge ? "selected models are" : "selected model is"} '
              '${_modelsToDownload?.length == 2 ? "~3.5GB combined" : _modelsToDownload?.first == ModelVariant.accurate ? "~2.5GB" : "~900MB"}. '
              'Downloading over mobile data may use a large chunk of your data plan. '
              'This only happens once - after this, the app works fully offline.',
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
        final theme = Theme.of(context);
        final received =
            _totalBytes != null ? (_fraction * _totalBytes!).round() : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 40),
            const SizedBox(height: 16),
            Text(
              _downloadingTitle,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              _downloadingStepLabel,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'One-time download - the app works fully offline after this.',
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
                WakelockPlus.disable();
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
                "Don't worry - what's already downloaded will resume from "
                "where it left off.",
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

/// Step 1: let the user pick which model to download.
class _ModelChooser extends StatelessWidget {
  final void Function(List<ModelVariant> variants) onChosen;

  const _ModelChooser({required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon + heading
        Icon(Icons.smart_toy_outlined, size: 52, color: accent),
        const SizedBox(height: 16),
        const Text(
          'Welcome to Clean Spirit AI',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose which AI model to download. Once downloaded, '
          'everything runs fully offline on your device.',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Option 1
        _OptionCard(
          number: '1',
          title: '1.5B (Faster, Less Accurate)',
          subtitle: 'Great for quick chats, simple questions, and everyday '
              'conversations. Uses less storage (~900MB).',
          icon: Icons.bolt,
          onTap: () => onChosen([ModelVariant.fast]),
        ),
        const SizedBox(height: 12),

        // Option 2
        _OptionCard(
          number: '2',
          title: '4B (Slower, More Accurate)',
          subtitle: 'Better for detailed explanations, math, coding, and '
              'factual tasks. Requires more storage (~2.5GB).',
          icon: Icons.psychology,
          onTap: () => onChosen([ModelVariant.accurate]),
        ),
        const SizedBox(height: 12),

        // Option 3
        _OptionCard(
          number: '3',
          title: 'Download Both',
          subtitle: 'Enables Auto Switch - the app automatically picks the '
              'right model for each message. Requires ~3.5GB storage.',
          icon: Icons.swap_horiz,
          highlight: true,
          badge: 'Recommended',
          onTap: () => onChosen([ModelVariant.fast, ModelVariant.accurate]),
        ),

        const SizedBox(height: 24),
        Text(
          'You can download the other model later from settings.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  final String? badge;

  const _OptionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlight = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Material(
      color: highlight
          ? accent.withValues(alpha: 0.12)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Number badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: highlight ? accent : theme.colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number,
                    style: TextStyle(
                      color:
                          highlight ? theme.colorScheme.onPrimary : accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
