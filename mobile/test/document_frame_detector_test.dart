import 'dart:typed_data';

import 'package:civiclens/core/imaging/document_frame_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('DocumentFrameResult.shouldBlock', () {
    test('only distance (white) gate blocks; lab entropy does not', () {
      const r = DocumentFrameResult(
        histogramEntropy: 6.0,
        whiteRegionRatio: 0.5,
        frameAspectRatio: 0.5,
        gateEntropy: true,
        gateWhite: false,
        gateAspect: false,
        meanLuminance: 120,
        borderMeanLuminance: 115,
      );
      expect(r.shouldBlock, isFalse);
    });

    test('gateWhite still blocks', () {
      const r = DocumentFrameResult(
        histogramEntropy: 3.0,
        whiteRegionRatio: 0.02,
        frameAspectRatio: 0.5,
        gateEntropy: false,
        gateWhite: true,
        gateAspect: false,
        meanLuminance: 40,
        borderMeanLuminance: 35,
      );
      expect(r.shouldBlock, isTrue);
    });
  });

  group('DocumentFrameDetector', () {
    late DocumentFrameDetector detector;

    setUp(() {
      detector = DocumentFrameDetector();
    });

    test('nearly all-white page yields high white_region_ratio, no white gate', () {
      final im = img.Image(width: 200, height: 240);
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          im.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(im));
      final r = detector.analyzeBytes(bytes);
      expect(r.whiteRegionRatio, greaterThan(0.9));
      expect(r.gateWhite, isFalse);
      expect(r.frameAspectRatio, closeTo(200 / 240, 0.01));
    });

    test('nearly all-dark frame yields low white_region_ratio, may gate', () {
      final im = img.Image(width: 200, height: 240);
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          im.setPixelRgb(x, y, 10, 10, 10);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(im));
      final r = detector.analyzeBytes(bytes);
      expect(r.gateWhite, isTrue);
      expect(r.meanLuminance, lessThan(40.0));
    });

    test('portrait frame ratio is not a block (gateAspect off)', () {
      final im = img.Image(width: 200, height: 480);
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          im.setPixelRgb(x, y, 240, 240, 240);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(im));
      final r = detector.analyzeBytes(bytes);
      expect(r.frameAspectRatio, lessThan(0.74));
      expect(r.gateAspect, isFalse);
    });

    test('small bright page on dark border still gates (table halo)', () {
      final im = img.Image(width: 120, height: 140);
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          im.setPixelRgb(x, y, 25, 25, 25);
        }
      }
      const x0 = 30;
      const y0 = 35;
      const x1 = 90;
      const y1 = 105;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          im.setPixelRgb(x, y, 250, 250, 250);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(im));
      final r = detector.analyzeBytes(bytes);
      expect(r.gateWhite, isTrue);
      expect(r.borderMeanLuminance, lessThan(r.meanLuminance));
    });

    test('high mean luma suppresses spurious small largest-white CC (zoom / JPEG)', () {
      // One bright patch (L≥180) in the center; everything else is just below
      // [whiteBinaryLuminance] so the largest "white" CC is small, but the frame
      // is still uniformly “paper” at the edges (no dark table) — should not gate.
      final im = img.Image(width: 200, height: 240);
      const paper = 175;
      const spec = 200;
      const bw = 60;
      const bh = 96;
      final x0 = (im.width - bw) ~/ 2;
      final y0 = (im.height - bh) ~/ 2;
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          final inPatch = x >= x0 && x < x0 + bw && y >= y0 && y < y0 + bh;
          final v = inPatch ? spec : paper;
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(im));
      final r = detector.analyzeBytes(bytes);
      expect(r.meanLuminance, greaterThan(92.0));
      expect(r.gateWhite, isFalse);
    });
  });
}
