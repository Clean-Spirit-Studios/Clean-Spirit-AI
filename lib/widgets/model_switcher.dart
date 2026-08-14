import 'package:flutter/material.dart';
import '../dual_engine.dart';

class ModelSwitcher extends StatelessWidget {
  final ActiveModel current;
  final bool hasGemma;
  final bool hasGemmaE4b;
  final bool hasQwen4b;
  final bool isReloading;
  final String activeBackendLabel;
  final ValueChanged<ActiveModel> onModelChanged;
  final VoidCallback onSwitchBackend;

  const ModelSwitcher({
    required this.current,
    required this.hasGemma,
    required this.hasGemmaE4b,
    required this.hasQwen4b,
    required this.isReloading,
    required this.activeBackendLabel,
    required this.onModelChanged,
    required this.onSwitchBackend,
  });

  String get _pillLabel {
    switch (current) {
      case ActiveModel.gemma:
        return 'Gemma E2B';
      case ActiveModel.gemmaE4b:
        return 'Gemma E4B';
      case ActiveModel.qwen4b:
        return 'Qwen3 4B';
      case ActiveModel.auto:
        return 'Auto';
    }
  }

  String get _backendSuffix {
    if (current == ActiveModel.qwen4b) return 'CPU';
    return activeBackendLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    if (isReloading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Switch model or backend',
      onSelected: (value) {
        if (value == 'switch_backend') {
          onSwitchBackend();
        } else {
          final model = switch (value) {
            'gemma' => ActiveModel.gemma,
            'gemmaE4b' => ActiveModel.gemmaE4b,
            'qwen4b' => ActiveModel.qwen4b,
            _ => ActiveModel.auto,
          };
          onModelChanged(model);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        if (hasGemma) {
          items.add(PopupMenuItem(
            value: 'gemma',
            child: ModelMenuItem(
              label: 'Gemma 4 E2B - LiteRT',
              subtitle: 'GPU-accelerated - vision-capable - fast',
              archBadge: 'LiteRT',
              archColor: Colors.tealAccent.shade400,
              icon: Icons.bolt,
              selected: current == ActiveModel.gemma,
            ),
          ));
        }

        if (hasGemmaE4b) {
          items.add(PopupMenuItem(
            value: 'gemmaE4b',
            child: ModelMenuItem(
              label: 'Gemma 4 E4B - LiteRT',
              subtitle: 'GPU-accelerated - vision-capable - best quality - ~5 GB RAM',
              archBadge: 'LiteRT',
              archColor: Colors.tealAccent.shade400,
              icon: Icons.auto_awesome_rounded,
              selected: current == ActiveModel.gemmaE4b,
            ),
          ));
        }

        if (hasQwen4b) {
          items.add(PopupMenuItem(
            value: 'qwen4b',
            child: ModelMenuItem(
              label: 'Qwen3 4B - GGUF',
              subtitle: 'CPU-based - thorough reasoning',
              archBadge: 'GGUF',
              archColor: Colors.orangeAccent.shade400,
              icon: Icons.psychology,
              selected: current == ActiveModel.qwen4b,
            ),
          ));
        }

        if ((hasGemma || hasGemmaE4b) && hasQwen4b) {
          items.add(const PopupMenuDivider());
          items.add(PopupMenuItem(
            value: 'auto',
            child: ModelMenuItem(
              label: 'Auto',
              subtitle: 'Prefers E4B, then E2B (LiteRT GPU)',
              archBadge: 'Auto',
              archColor: accent,
              icon: Icons.swap_horiz,
              selected: current == ActiveModel.auto,
            ),
          ));
        }

        if ((hasGemma || hasGemmaE4b) &&
            (current == ActiveModel.gemma ||
                current == ActiveModel.gemmaE4b ||
                current == ActiveModel.auto)) {
          items.add(const PopupMenuDivider());
          final isGpu = activeBackendLabel == 'GPU';
          items.add(PopupMenuItem(
            value: 'switch_backend',
            child: ModelMenuItem(
              label: isGpu
                  ? 'Switch Gemma to CPU (safe)'
                  : 'Switch Gemma to GPU (fast)',
              subtitle: isGpu
                  ? 'Currently GPU - tap to use CPU instead'
                  : 'Currently CPU - tap to use GPU instead',
              archBadge: activeBackendLabel,
              archColor: isGpu
                  ? Colors.greenAccent.shade400
                  : Colors.grey.shade400,
              icon: isGpu ? Icons.memory : Icons.developer_board,
              selected: false,
            ),
          ));
        }

        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 14, color: accent),
            const SizedBox(width: 4),
            Text(
              _pillLabel,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '- $_backendSuffix',
              style: TextStyle(
                color: accent.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 14, color: accent),
          ],
        ),
      ),
    );
  }
}

class ModelMenuItem extends StatelessWidget {
  final String label;
  final String subtitle;
  final String archBadge;
  final Color archColor;
  final IconData icon;
  final bool selected;

  const ModelMenuItem({
    required this.label,
    required this.subtitle,
    required this.archBadge,
    required this.archColor,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Row(
      children: [
        Icon(icon, size: 20, color: selected ? accent : null),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? accent : null,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        if (selected) Icon(Icons.check, size: 16, color: accent),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome screen (unchanged from original)
// ---------------------------------------------------------------------------

