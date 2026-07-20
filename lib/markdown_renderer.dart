// markdown_renderer.dart
//
// Thin wrapper around flutter_markdown that applies the app's theme colors
// to markdown output in assistant chat bubbles.
//
// Handles: ## headers, **bold**, *italic*, `code`, ``` code blocks,
//          pipe tables, bullet/numbered lists, blockquotes.
//
// Usage:
//   ChatMarkdown(data: turn.text, textColor: bubbleTextColor)

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class ChatMarkdown extends StatelessWidget {
  final String data;
  final Color textColor;

  const ChatMarkdown({super.key, required this.data, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MarkdownBody(
      data: data,
      selectable: true,
      extensionSet: md.ExtensionSet(
        // Enable GitHub-flavored tables and other block extensions
        [...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
        md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      ),
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: textColor, fontSize: 14, height: 1.45),
        h1: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h2: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h3: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        strong: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
        code: TextStyle(
          color: textColor,
          fontFamily: 'monospace',
          fontSize: 12.5,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.4),
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        tableBorder: TableBorder.all(
          color: textColor.withValues(alpha: 0.25),
          width: 1,
          borderRadius: BorderRadius.circular(4),
        ),
        tableHead: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        tableBody: TextStyle(color: textColor, fontSize: 13),
        tableHeadAlign: TextAlign.left,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 5,
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: textColor.withValues(alpha: 0.4),
              width: 3,
            ),
          ),
        ),
        listBullet: TextStyle(color: textColor, fontSize: 14),
        listIndent: 16,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: textColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
