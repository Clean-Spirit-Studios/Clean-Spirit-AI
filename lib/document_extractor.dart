// document_extractor.dart
//
// Extracts plain text from document files (PDF, DOCX, and plain text formats)
// so they can be fed into the local LLM as context.
//
// Supported formats:
//   Binary: .pdf (syncfusion_flutter_pdf - full text extraction, no char limit),
//           .docx (archive + xml)
//   Text:   .txt .md .json .csv .log .yaml .yml .xml
//   Code:   .dart .kt .java .js .ts .py
//
// Feature 3: switched from read_pdf_text (3,000 char hard cap) to
// syncfusion_flutter_pdf which returns the full PDF text. The cap is
// raised to 12,000 chars (~3,400 tokens) - safe for Gemma 4 E2B (8k+)
// and Qwen3 4B (32k+) context windows.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

/// Maximum characters returned for any document.
/// At ~3.5 chars per token this is roughly 3,400 tokens - well within
/// both Gemma 4 E2B (8k+ tokens) and Qwen3 4B (32k+ tokens) context windows.
/// Raised from the old 3,000 char cap which was set for a 4,096-token window.
const _kMaxChars = 12000;

class DocumentExtractor {
  /// Extract text from [path] with the given [extension].
  /// Returns at most [_kMaxChars] characters with a friendly truncation notice.
  static Future<String> extractText(String path, String extension) async {
    final raw = await _extractRaw(path, extension);
    if (raw.length <= _kMaxChars) return raw;
    final kilo = _kMaxChars ~/ 1000;
    return '${raw.substring(0, _kMaxChars)}\n\n'
        '[Document is large - showing first ${kilo}k characters. '
        'Ask specific questions for best results.]';
  }

  static Future<String> _extractRaw(String path, String extension) async {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return _extractPdf(path);
      case 'docx':
        return _extractDocx(path);
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'log':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'dart':
      case 'kt':
      case 'java':
      case 'js':
      case 'ts':
      case 'py':
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      default:
        throw UnsupportedError(
          'Document extraction is not supported for .$extension files.',
        );
    }
  }

  /// Extract text from a PDF using syncfusion_flutter_pdf.
  /// Returns the full text of all pages with no artificial character limit.
  /// Scanned/image-only PDFs will return empty text (no text layer present).
  static Future<String> _extractPdf(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      try {
        final extractor = PdfTextExtractor(document);
        final text = extractor.extractText();
        final trimmed = text.trim();
        return trimmed.isEmpty
            ? '[No extractable text found in PDF - the file may be a scanned image]'
            : trimmed;
      } finally {
        document.dispose();
      }
    } catch (e) {
      return '[PDF extraction failed: $e]';
    }
  }

  /// Extract text from a DOCX file using pure Dart (archive + xml).
  /// No native dependency - works offline with no network.
  static Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () =>
          throw Exception('Invalid DOCX: word/document.xml not found'),
    );

    final xmlString = utf8.decode(documentFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    // Preserve paragraph breaks: each <w:p> element is a paragraph.
    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final pText = p.findAllElements('w:t').map((e) => e.value).join();
      if (pText.isNotEmpty) paragraphs.add(pText);
    }

    return paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : document.findAllElements('w:t').map((e) => e.value).join();
  }
}
