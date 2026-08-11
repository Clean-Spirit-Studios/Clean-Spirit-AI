// document_extractor.dart
//
// Extracts plain text from document files (PDF, DOCX, and plain text formats)
// so they can be fed into the local LLM as context.
//
// Ported from DocumentExtractorService in cross-platform-llm-client.
//
// Supported formats:
//   Binary: .pdf (Syncfusion), .docx (archive + xml)
//   Text:   .txt .md .json .csv .log .yaml .yml .xml
//   Code:   .dart .kt .java .js .ts .py
//
// Note: Syncfusion Flutter PDF is community-licensed (free for revenue < $1M).
// No license key or network call is needed for local text extraction.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/syncfusion_flutter_pdf.dart';
import 'package:xml/xml.dart';

/// Maximum characters returned for any document.
/// At ~4 chars per token this is roughly 750 tokens - leaves room
/// in the 4096-token context for the conversation and response.
const _kMaxChars = 3000;

class DocumentExtractor {
  /// Extract text from [path] with the given [extension].
  /// Returns at most [_kMaxChars] characters.
  static Future<String> extractText(String path, String extension) async {
    final raw = await _extractRaw(path, extension);
    if (raw.length <= _kMaxChars) return raw;
    return '${raw.substring(0, _kMaxChars)}...\n[Document trimmed to first $_kMaxChars characters]';
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

  /// Extract text from a PDF file using Syncfusion PDF.
  static Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document.dispose();
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
