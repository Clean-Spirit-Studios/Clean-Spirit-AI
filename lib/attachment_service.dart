// attachment_service.dart
//
// Handles picking images (camera / gallery) and documents (PDF, DOCX, text).
// All methods return null on cancellation or permission denial.
//
// Uses file_picker ^11.x API - FilePicker static methods (no .platform getter).

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class AttachmentService {
  static final _picker = ImagePicker();

  // ---------------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------------

  /// Pick an image from the device gallery.
  /// Returns the local file path or null if cancelled.
  static Future<String?> pickImageFromGallery() async {
    final ok = await _ensureImagePermission();
    if (!ok) return null;

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // reduce file size for faster LiteRT encoding
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  /// Pick an image from the camera.
  /// Returns the local file path or null if cancelled.
  static Future<String?> pickImageFromCamera() async {
    final ok = await _ensureCameraPermission();
    if (!ok) return null;

    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------------

  /// Pick a document file.
  /// Returns a record with the file path, display name, and extension,
  /// or null if cancelled.
  ///
  /// file_picker v11 removed the .platform getter - use FilePicker.pickFiles()
  /// directly as a static method. FilePickerResult is still returned the same way.
  static Future<({String path, String name, String ext})?> pickDocument() async {
    try {
      // file_picker ^11: call FilePicker.pickFiles() directly (no .platform).
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'docx',
          'txt',
          'md',
          'csv',
          'json',
          'log',
          'yaml',
          'yml',
          'xml',
          'dart',
          'kt',
          'java',
          'js',
          'ts',
          'py',
        ],
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      if (file.path == null) return null;

      // Explicit typed record to avoid Dart inference issues with named fields.
      final String filePath = file.path!;
      final String fileName = file.name;
      final String fileExt = (file.extension ?? 'txt').toLowerCase();

      return (path: filePath, name: fileName, ext: fileExt);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Permission helpers
  // ---------------------------------------------------------------------------

  static Future<bool> _ensureImagePermission() async {
    // Android 13+ uses READ_MEDIA_IMAGES; older versions use READ_EXTERNAL_STORAGE.
    // image_picker handles the actual dialog; we just need to check the result.
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;

    // Fallback for Android < 13
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  static Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }
}
