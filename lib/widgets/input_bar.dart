import 'dart:io';
import 'package:flutter/material.dart';

class InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final bool isModelLoading;
  final VoidCallback onSend;
  final VoidCallback onAttachTap;
  final String? pendingImagePath;
  final String? pendingDocName;
  final VoidCallback onClearAttachment;

  const InputBar({
    required this.controller,
    required this.isGenerating,
    required this.isModelLoading,
    required this.onSend,
    required this.onAttachTap,
    required this.pendingImagePath,
    required this.pendingDocName,
    required this.onClearAttachment,
  });

  bool get _hasAttachment => pendingImagePath != null || pendingDocName != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasAttachment)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: AttachmentChip(
                imagePath: pendingImagePath,
                docName: pendingDocName,
                onDismiss: onClearAttachment,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IconButton(
                    onPressed: (isGenerating || isModelLoading) ? null : onAttachTap,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    tooltip: 'Attach image or document',
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !isGenerating && !isModelLoading,
                    maxLines: 6,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message Clean Spirit AI...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IconButton.filled(
                    onPressed: (isGenerating || isModelLoading) ? null : onSend,
                    icon: (isGenerating || isModelLoading)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachment preview chip (unchanged)
// ---------------------------------------------------------------------------

class AttachmentChip extends StatelessWidget {
  final String? imagePath;
  final String? docName;
  final VoidCallback onDismiss;

  const AttachmentChip({
    required this.imagePath,
    required this.docName,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(imagePath!),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Image attached',
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (docName != null) ...[
              Icon(Icons.description_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  docName!.length > 24
                      ? '${docName!.substring(0, 21)}...'
                      : docName!,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main chat screen
// ---------------------------------------------------------------------------

