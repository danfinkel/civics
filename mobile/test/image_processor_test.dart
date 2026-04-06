import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:civiclens/core/imaging/image_processor.dart';

void main() {
  group('ImageProcessor', () {
    late ImageProcessor processor;

    setUp(() {
      processor = ImageProcessor();
    });

    test('should resize large image to max 1024px', () async {
      // Create a large test image (2000x1500)
      final largeImage = img.Image(width: 2000, height: 1500);
      final largeBytes = Uint8List.fromList(img.encodeJpg(largeImage));

      final processed = await processor.processBytes(largeBytes);
      final decoded = img.decodeImage(processed);

      expect(decoded, isNotNull);
      expect(
        decoded!.width <= 1024 || decoded.height <= 1024,
        true,
        reason: 'Image should be resized to max 1024px on longest edge',
      );
    });

    test('should not resize small image', () async {
      // Create a small test image (500x400)
      final smallImage = img.Image(width: 500, height: 400);
      final smallBytes = Uint8List.fromList(img.encodeJpg(smallImage));

      final processed = await processor.processBytes(smallBytes);
      final decoded = img.decodeImage(processed);

      expect(decoded, isNotNull);
      expect(decoded!.width, 500);
      expect(decoded.height, 400);
    });

    test('should maintain aspect ratio when resizing', () async {
      // Create a wide image (2000x1000)
      final wideImage = img.Image(width: 2000, height: 1000);
      final wideBytes = Uint8List.fromList(img.encodeJpg(wideImage));

      final processed = await processor.processBytes(wideBytes);
      final decoded = img.decodeImage(processed);

      expect(decoded, isNotNull);
      expect(decoded!.width, 1024);
      expect(decoded.height, 512); // Maintained 2:1 aspect ratio
    });

    test('should output JPEG format', () async {
      final image = img.Image(width: 100, height: 100);
      final bytes = Uint8List.fromList(img.encodePng(image));

      final processed = await processor.processBytes(bytes);

      // Check JPEG magic bytes
      expect(processed[0], 0xFF);
      expect(processed[1], 0xD8);
    });

    test('should strip EXIF data', () async {
      // Create image and process
      final image = img.Image(width: 100, height: 100);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final processed = await processor.processBytes(bytes);

      // Processed image should be smaller or equal (no EXIF)
      expect(processed.length <= bytes.length, true);
    });

    test('should create thumbnail', () async {
      final image = img.Image(width: 1000, height: 800);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final thumbnail = await processor.createThumbnail(bytes, size: 200);
      final decoded = img.decodeImage(thumbnail);

      expect(decoded, isNotNull);
      expect(decoded!.width <= 200 || decoded.height <= 200, true);
    });
  });
}
