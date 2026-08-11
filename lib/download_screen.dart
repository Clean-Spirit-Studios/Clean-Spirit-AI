// download_screen.dart
//
// Shown on first app launch before the chat screen.
//
// Step 1: user picks which model(s) to download - with clear architecture info.
// Step 2: connectivity check (warn on mobile data).
// Step 3: download with live progress bar.
//
// Option 1 - Gemma 4 E2B (LiteRT - GPU - fast, vision-capable)     ~2.46 GB
// Option 2 - Qwen3 4B    (GGUF - CPU - thorough reasoning)          ~2.5 GB
// Option 3 - Download Both                                           ~5 GB

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

  List<ModelVariant>? _modelsToDownload;
  int _currentDownloadIndex = 0;

  String get _currentVariantLabel {
    if (_modelsToDownload == null) return '';
    final v = _modelsToDownload![_currentDownloadIndex];
    return v == ModelVariant.gemma ? 'Gemma 4 E2B (LiteRT)' : 'Qwen3 4B (GGUF)';
  }

  String get _sizeWarningText {
    if (_modelsToDownload == null) return '';
    if (_modelsToDownload!.length == 2) return 'approximately 5 GB combined';
    return _modelsToDownload!.first == ModelVariant.gemma
        ? 'approximately 2.46 GB'
        : 'approximately 2.5 GB';
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

    WakelockPlus.enable();
    _fetchSizeAndDownloadNext();
  }

  Future<void> _fetchSizeAndDownloadNext() async {
    if (_modelsToDownload == null ||
        _currentDownloadIndex >= _modelsToDownload!.length) return;

    final variant = _modelsToDownload![_currentDownloadIndex];

    ModelLoader.fetchTotalSizeBytes(variant).then((bytes) {
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

  String get _downloadingStepLabel {
    if (_modelsToDownload == null) return '';
    final total = _modelsToDownload!.length;
    return total > 1
        ? 'Model ${_currentDownloadIndex + 1} of $total'
        : 'One-time download';
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
              'The selected model is $_sizeWarningText. '
              'Downloading over mobile data may use a large chunk of your data plan. '
              'This only happens once - after this, the app works fully offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _stage = _Stage.choosingModel),
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
        final received = _totalBytes != null
            ? (_fraction * _totalBytes!).round()
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 40),
            const SizedBox(height: 16),
            Text(
              'Downloading $_currentVariantLabel...',
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _stage = _Stage.choosingModel),
              child: const Text('Back to model selection'),
            ),
          ],
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 1: model chooser - architecture is clearly explained
// ---------------------------------------------------------------------------

class _ModelChooser extends StatelessWidget {
  final void Function(List<ModelVariant> variants) onChosen;

  const _ModelChooser({required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.smart_toy_outlined, size: 52, color: accent),
          const SizedBox(height: 16),
          const Text(
            'Welcome to Clean Spirit AI',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which AI model to download. Both run fully offline '
            'on your device after the one-time download.',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Gemma - LiteRT
          _OptionCard(
            archBadge: 'LiteRT',
            archColor: Colors.tealAccent.shade400,
            icon: Icons.bolt,
            title: 'Gemma 4 E2B - GPU (LiteRT)',
            sizeLabel: '~2.46 GB',
            subtitle:
                'Google\'s model running on your phone\'s GPU via the LiteRT engine. '
                'Fast, vision-capable (understands images), and ideal for everyday chat.',
            highlight: true,
            badge: 'Recommended',
            onTap: () => onChosen([ModelVariant.gemma]),
          ),
          const SizedBox(height: 12),

          // Qwen3 4B - GGUF
          _OptionCard(
            archBadge: 'GGUF',
            archColor: Colors.orangeAccent.shade400,
            icon: Icons.psychology,
            title: 'Qwen3 4B - CPU (GGUF)',
            sizeLabel: '~2.5 GB',
            subtitle:
                'Alibaba\'s Qwen3 4B model running on your CPU via the GGUF/llama.cpp engine. '
                'Slower but strong at detailed reasoning, math, and coding.',
            onTap: () => onChosen([ModelVariant.qwen4b]),
          ),
          const SizedBox(height: 12),

          // Both
          _OptionCard(
            archBadge: 'Both',
            archColor: accent,
            icon: Icons.swap_horiz,
            title: 'Download Both',
            sizeLabel: '~5 GB',
            subtitle:
                'Enables Auto mode - defaults to Gemma (LiteRT GPU) for speed, '
                'with Qwen3 4B (GGUF CPU) available for heavy reasoning tasks.',
            onTap: () =>
                onChosen([ModelVariant.gemma, ModelVariant.qwen4b]),
          ),

          const SizedBox(height: 24),
          Text(
            'You can download the other model later from within the app.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String archBadge;
  final Color archColor;
  final IconData icon;
  final String title;
  final String sizeLabel;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;
  final String? badge;

  const _OptionCard({
    required this.archBadge,
    required this.archColor,
    required this.icon,
    required this.title,
    required this.sizeLabel,
    required this.subtitle,
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
              // Arch badge circle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: archColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: archColor.withValues(alpha: 0.35), width: 1),
                ),
                child: Center(
                  child: Icon(icon, size: 20, color: archColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: archColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            archBadge,
                            style: TextStyle(
                              fontSize: 9,
                              color: archColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
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
                    const SizedBox(height: 2),
                    // Size label
                    Text(
                      sizeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: archColor.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
