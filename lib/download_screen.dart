// download_screen.dart
//
// Shown on first app launch before the chat screen.
// Feature 4 - full visual redesign with modern card layout, circular progress
// ring, and polished state treatment for all 5 stages.
//
// Stage 1: choosingModel   - branded hero + model cards
// Stage 2: checkingConnection
// Stage 3: confirmingMobileData - orange-bordered warning card
// Stage 4: downloading      - circular progress ring + byte counter
// Stage 5: error            - red icon + resume notice

import 'dart:math' as math;

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
    final hasNone =
        connectivity.contains(ConnectivityResult.none) || connectivity.isEmpty;

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
      if (mounted && bytes != null) setState(() => _totalBytes = bytes);
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
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Center(child: _buildContent()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_stage) {
      case _Stage.choosingModel:
        return _ModelChooser(onChosen: _onModelChosen);

      case _Stage.checkingConnection:
        return _buildCheckingConnection();

      case _Stage.confirmingMobileData:
        return _buildMobileDataCard();

      case _Stage.downloading:
        return _buildDownloadingState();

      case _Stage.error:
        return _buildErrorState();
    }
  }

  // ---------------------------------------------------------------------------
  // Checking connection state
  // ---------------------------------------------------------------------------

  Widget _buildCheckingConnection() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3, color: accent),
        ),
        const SizedBox(height: 20),
        Text(
          'Checking connection...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile data warning card
  // ---------------------------------------------------------------------------

  Widget _buildMobileDataCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.signal_cellular_alt_rounded,
              size: 30,
              color: Colors.orangeAccent.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Mobile data detected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'The selected model is $_sizeWarningText. '
            'After this one-time download, the app works fully offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() => _stage = _Stage.choosingModel),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Wait for Wi-Fi'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _startDownload,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Download anyway'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Downloading state - circular progress ring
  // ---------------------------------------------------------------------------

  Widget _buildDownloadingState() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final received = _totalBytes != null
        ? (_fraction * _totalBytes!).round()
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Circular progress ring with percentage
        SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track ring
              SizedBox.expand(
                child: Transform.rotate(
                  angle: -math.pi / 2,
                  child: CircularProgressIndicator(
                    value: _fraction > 0 ? _fraction : null,
                    strokeWidth: 7,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    color: accent,
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ),
              // Percentage label
              Text(
                '${(_fraction * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Downloading $_currentVariantLabel',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          _downloadingStepLabel,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        if (received != null && _totalBytes != null) ...[
          const SizedBox(height: 6),
          Text(
            '${_formatBytes(received)} of ${_formatBytes(_totalBytes!)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Keep the app open - one-time download only.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Linear bar as secondary indicator
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _fraction > 0 ? _fraction : null,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: accent,
          ),
        ),
        const SizedBox(height: 28),
        TextButton(
          onPressed: () async {
            await ModelLoader.cancelDownload();
            WakelockPlus.disable();
            if (mounted) setState(() => _stage = _Stage.error);
          },
          child: Text(
            'Cancel',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _errorText ?? 'An unknown error occurred.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (_fraction > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.save_alt_rounded,
                      size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Progress saved - download will resume from ${(_fraction * 100).toStringAsFixed(0)}%.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.green),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              onPressed: _checkConnectionThenStart,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _stage = _Stage.choosingModel),
            child: const Text('Back to model selection'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: model chooser - redesigned with hero section
// ---------------------------------------------------------------------------

class _ModelChooser extends StatelessWidget {
  final void Function(List<ModelVariant> variants) onChosen;

  const _ModelChooser({required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero section - app logo + tagline
        const SizedBox(height: 16),
        Center(child: _AppLogo()),

        const SizedBox(height: 10),
        Center(
          child: Text(
            'Private AI, on your device.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Choose a model to download. Both run fully offline after the\none-time download.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),

        // Gemma - LiteRT
        _ModelCard(
          archBadge: 'LiteRT',
          archColor: Colors.tealAccent.shade400,
          icon: Icons.bolt,
          title: 'Gemma 4 E2B',
          engineLabel: 'GPU - LiteRT',
          sizeLabel: '~2.46 GB',
          subtitle:
              'Google\'s model on your phone\'s GPU. Fast, vision-capable, and great for everyday chat.',
          highlight: true,
          badge: 'Recommended',
          onTap: () => onChosen([ModelVariant.gemma]),
        ),
        const SizedBox(height: 12),

        // Qwen3 4B - GGUF
        _ModelCard(
          archBadge: 'GGUF',
          archColor: Colors.orangeAccent.shade400,
          icon: Icons.psychology,
          title: 'Qwen3 4B',
          engineLabel: 'CPU - GGUF',
          sizeLabel: '~2.5 GB',
          subtitle:
              'Alibaba\'s Qwen3 4B via llama.cpp. Slower but strong at reasoning, math, and coding.',
          onTap: () => onChosen([ModelVariant.qwen4b]),
        ),
        const SizedBox(height: 12),

        // Both
        _ModelCard(
          archBadge: 'Both',
          archColor: Theme.of(context).colorScheme.primary,
          icon: Icons.swap_horiz,
          title: 'Download Both',
          engineLabel: 'GPU + CPU',
          sizeLabel: '~5 GB',
          subtitle:
              'Enables Auto mode - defaults to Gemma (GPU) for speed, with Qwen3 4B (CPU) for heavy reasoning.',
          onTap: () => onChosen([ModelVariant.gemma, ModelVariant.qwen4b]),
        ),

        const SizedBox(height: 24),
        Center(
          child: Text(
            'You can download the other model later from within the app.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Model card - redesigned with vertical layout and overlaid badge
// ---------------------------------------------------------------------------

class _ModelCard extends StatelessWidget {
  final String archBadge;
  final Color archColor;
  final IconData icon;
  final String title;
  final String engineLabel;
  final String sizeLabel;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;
  final String? badge;

  const _ModelCard({
    required this.archBadge,
    required this.archColor,
    required this.icon,
    required this.title,
    required this.engineLabel,
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
          ? accent.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: icon circle + recommended badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: archColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: archColor.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Center(
                      child: Icon(icon, size: 22, color: archColor),
                    ),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Title + arch badge
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                ],
              ),
              const SizedBox(height: 6),
              // Description
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 14),
              // Footer row: engine tag + size
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: archColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: archColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      engineLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: archColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    sizeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// App logo widget (shared between download_screen and chat_screen)
// ---------------------------------------------------------------------------

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: onSurface,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Clean Spirit ',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: 'AI',
                style: TextStyle(
                  color: accent,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
