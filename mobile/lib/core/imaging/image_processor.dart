import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

/// Processes images for document analysis
class ImageProcessor {
  // Maximum dimension for processed images
  static const int _maxDimension = 1024;
  // JPEG quality for output
  static const int _jpegQuality = 85;

  /// Process an image file for inference
  /// Returns JPEG bytes with max 1024px longest edge, quality 85
  /// Strips EXIF data for privacy
  Future<Uint8List> processFile(File file) async {
    final bytes = await file.readAsBytes();
    return processBytes(bytes);
  }

  /// Process image bytes for inference
  Future<Uint8List> processBytes(Uint8List bytes) async {
    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }

    // Normalize rotation from EXIF orientation
    final normalized = img.bakeOrientation(image);

    // Resize if needed
    img.Image resized = normalized;
    if (normalized.width > _maxDimension ||
        normalized.height > _maxDimension) {
      resized = img.copyResize(
        normalized,
        width: normalized.width > normalized.height ? _maxDimension : null,
        height: normalized.height >= normalized.width ? _maxDimension : null,
      );
    }

    // Encode as JPEG (strips EXIF data)
    final jpegBytes = img.encodeJpg(resized, quality: _jpegQuality);

    return Uint8List.fromList(jpegBytes);
  }

  /// Process multiple image files
  Future<List<Uint8List>> processFiles(List<File> files) async {
    final results = <Uint8List>[];
    for (final file in files) {
      results.add(await processFile(file));
    }
    return results;
  }

  /// Get image dimensions without full processing
  Future<(int width, int height)> getDimensions(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }
    return (image.width, image.height);
  }

  /// Create a thumbnail for preview
  Future<Uint8List> createThumbnail(
    Uint8List imageBytes, {
    int size = 200,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }

    final thumbnail = img.copyResize(
      image,
      width: image.width > image.height ? size : null,
      height: image.height >= image.width ? size : null,
    );

    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 70));
  }
}
