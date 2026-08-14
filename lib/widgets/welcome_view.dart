import 'package:flutter/material.dart';
import 'app_logo.dart';
import 'ghost_icon.dart';
import 'input_bar.dart';

class WelcomeView extends StatelessWidget {
  final bool isGenerating;
  final bool isModelLoading;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onAttachTap;
  final String? pendingImagePath;
  final String? pendingDocName;
  final VoidCallback onClearAttachment;

  const WelcomeView({
    required this.isGenerating,
    required this.isModelLoading,
    required this.inputController,
    required this.onSend,
    required this.onAttachTap,
    required this.pendingImagePath,
    required this.pendingDocName,
    required this.onClearAttachment,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _suggestions = [
    ('Explain quantum entanglement simply', Icons.science_outlined),
    ('Write a haiku about rain', Icons.edit_outlined),
    ('What is 17 x 34?', Icons.calculate_outlined),
    ('Tips for better sleep', Icons.bedtime_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting.',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'How can I help you today?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'TRY ASKING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _suggestions.map((s) {
                    final (label, icon) = s;
                    return Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          inputController.text = label;
                          onSend();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16, color: accent),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, size: 13, color: Colors.green),
                          SizedBox(width: 5),
                          Text(
                            '100% on-device - no data sent anywhere',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        InputBar(
          controller: inputController,
          isGenerating: isGenerating,
          isModelLoading: isModelLoading,
          onSend: onSend,
          onAttachTap: onAttachTap,
          pendingImagePath: pendingImagePath,
          pendingDocName: pendingDocName,
          onClearAttachment: onClearAttachment,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar with attachment support (unchanged)
// ---------------------------------------------------------------------------

