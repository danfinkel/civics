import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Tuned to [research/eval/synthetic_threshold_validator.py] (D01) where applicable.
/// Some lab thresholds (raw frame w/h) do not port 1:1 to phone EXIF; see [DocumentFrameDetector].
/// Rotation / `rotation_angle` gates are not applied in the app yet.
class DocumentFrameThresholds {
  static const double entropy = 5.15;

  /// Largest L≥[whiteBinaryLuminance] connected region must cover at least this fraction
  /// of the frame, else we warn — tuned above research 0.13 for device “too far / small” shots.
  static const double whiteMin = 0.16;

  /// OpenCV in research uses 200; phone JPEGs often show paper in ~160–210 — strict 200
  /// shatters “paper” into small CCs, false‑triggering the distance gate on good zooms.
  static const int whiteBinaryLuminance = 180;

  /// [meanLum] at or above this + other suppress rules only apply (see [DocumentFrameDetector]).
  static const double meanLuminanceSuppressMin = 91.0;

  /// “Zoomed / texty” false positives: largest bright CC can look small, but the frame
  /// is still uniformly document‑ish (no much darker table at the edges). Suppress
  /// only in that case — do **not** use mean alone; pair with [borderFrameDeltaMax].
  /// Kept low so very fragmented CC (&lt; ~0.06) still counts as “too small” distance.
  static const double whiteRatioSuppressMin = 0.055;

  /// If (mean − borderMean) is above this, edges are not uniform with center (e.g. desk
  /// around a page) and we do **not** apply fragmentation suppression; table gate may apply.
  static const double borderFrameDeltaMax = 24.0;

  /// Border (outer band) much darker than center + small [whiteRegionRatio] → small page
  /// on a surface, even if largest‑CC is not otherwise below [whiteMin].
  /// Dimmer border than this, with [borderDelta], suggests desk/surface (not just shadow).
  static const double tableBorderLumaMax = 82.0;
  static const double tableCenterDeltaMin = 16.0;

  /// “Table halo” only when largest CC is in the \([whiteMin], …\) range — not tiny CC.
  static const double tableVisibleWhiteMax = 0.27;

  /// Downscale for connected-components + histogram (matches mobile blur memory budget).
  static const int analysisMaxEdge = 512;
}

/// Document framing / pre-screen metrics (distance, busyness, frame shape) — not blur.
class DocumentFrameResult {
  final double histogramEntropy;
  final double whiteRegionRatio;
  final double frameAspectRatio;

  /// `histogram_entropy` ≥ 5.15 in validation (very busy / flat histograms).
  final bool gateEntropy;

  /// Distance / zoom: see [DocumentFrameThresholds] and [DocumentFrameDetector].
  final bool gateWhite;

  /// False for now: full‑frame w/h in portrait is usually &lt; 0.74 (e.g. 0.5), so the
  /// research crop metric does not map to “bad framing” for normal phone capture.
  final bool gateAspect;

  /// Mean luma of the analysis view (0–255).
  final double meanLuminance;

  /// Mean luma in a thin border band; center − border is used to spot table around a small page.
  final double borderMeanLuminance;

  const DocumentFrameResult({
    required this.histogramEntropy,
    required this.whiteRegionRatio,
    required this.frameAspectRatio,
    required this.gateEntropy,
    required this.gateWhite,
    required this.gateAspect,
    required this.meanLuminance,
    required this.borderMeanLuminance,
  });

  /// User-visible “framing” pre-screen. Only the **distance** ([gateWhite]) gate
  /// is used on device. [gateEntropy] and [gateAspect] match lab / research
  /// definitions but false-positive constantly on real phone photos (tight text
  /// zooms, portrait aspect, busy halftone/JPEG) — they are still computed for
  /// logging / future tuning but do not block the flow.
  bool get shouldBlock => gateWhite;

  /// One-line copy when [shouldBlock] (distance gate only; see [shouldBlock]).
  String get userMessage {
    if (gateWhite) {
      return 'The notice is too small in the frame. Move closer or make the page fill the screen.';
    }
    if (gateAspect) {
      return 'The full page is hard to read at this shape. Step back and capture a wider view of the whole page.';
    }
    if (gateEntropy) {
      return 'The photo may be too busy or unevenly lit. A plain background and even lighting work best.';
    }
    return '';
  }

  @override
  String toString() => 'DocumentFrameResult(ent=$histogramEntropy, white=$whiteRegionRatio, '
      'w/h=$frameAspectRatio, meanL=$meanLuminance, borderL=$borderMeanLuminance, '
      'gates: e=$gateEntropy w=$gateWhite a=$gateAspect)';
}

/// Lightweight port of [research/eval/real_photo_characterizer] metrics for on-device gating.
class DocumentFrameDetector {
  /// Analyzes [bytes] the same way as [BlurDetector]: EXIF orientation is baked in first.
  DocumentFrameResult analyzeBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }
    return analyzeImage(img.bakeOrientation(image));
  }

  DocumentFrameResult analyzeImage(img.Image oriented) {
    final w0 = oriented.width;
    final h0 = oriented.height;
    if (h0 <= 0 || w0 <= 0) {
      throw ArgumentError('Invalid image size');
    }

    final frameAspect = w0 / h0;

    var work = oriented;
    const maxE = DocumentFrameThresholds.analysisMaxEdge;
    if (work.width > maxE || work.height > maxE) {
      work = img.copyResize(
        work,
        width: work.width > work.height ? maxE : null,
        height: work.height >= work.width ? maxE : null,
      );
    }
    final gray = img.grayscale(work);
    final gw = gray.width;
    final gh = gray.height;

    final hist = List<int>.filled(256, 0);
    var sumL = 0;
    for (int y = 0; y < gh; y++) {
      for (int x = 0; x < gw; x++) {
        final l = img.getLuminance(gray.getPixel(x, y)).round().clamp(0, 255);
        sumL += l;
        hist[l]++;
      }
    }

    final nPix = gw * gh;
    final meanLum = sumL / nPix;
    final borderMean = _borderMeanLuminance(gray);
    final borderDelta = meanLum - borderMean;
    double histEntropy;
    {
      var sumPLogP = 0.0;
      for (var i = 0; i < 256; i++) {
        if (hist[i] == 0) continue;
        final p = hist[i] / nPix;
        sumPLogP += p * math.log(p);
      }
      histEntropy = -sumPLogP;
    }

    final whiteRatio = _largestBinaryRegionRatio(
      gray,
      DocumentFrameThresholds.whiteBinaryLuminance,
    );

    // Entropy: same rule as research.
    final ge = histEntropy >= DocumentFrameThresholds.entropy;
    // Distance / zoom: primary = largest white CC; suppress only when the frame is
    // “uniformly bright” (text fragmentation), not when edges are much darker (table + small page).
    final primaryTooSmall = whiteRatio < DocumentFrameThresholds.whiteMin;
    final uniformBrightFragmentation =
        borderDelta < DocumentFrameThresholds.borderFrameDeltaMax;
    final suppressDistance =
        meanLum >= DocumentFrameThresholds.meanLuminanceSuppressMin &&
        whiteRatio >= DocumentFrameThresholds.whiteRatioSuppressMin &&
        uniformBrightFragmentation;
    final byLargest = primaryTooSmall && !suppressDistance;

    // Subjects who are not “too far” in CC terms can still have a small page in frame with
    // a visible surface at the edges (e.g. largest bright blob ≥ whiteMin from highlights).
    final tableHalo = whiteRatio >= DocumentFrameThresholds.whiteMin &&
        whiteRatio < DocumentFrameThresholds.tableVisibleWhiteMax &&
        borderMean < DocumentFrameThresholds.tableBorderLumaMax &&
        borderDelta > DocumentFrameThresholds.tableCenterDeltaMin;

    final gwB = byLargest || tableHalo;
    // [aspect] from research targeted crop ablations; raw phone w/h is not used here.
    const ga = false;

    return DocumentFrameResult(
      histogramEntropy: histEntropy,
      whiteRegionRatio: whiteRatio,
      frameAspectRatio: frameAspect,
      gateEntropy: ge,
      gateWhite: gwB,
      gateAspect: ga,
      meanLuminance: meanLum,
      borderMeanLuminance: borderMean,
    );
  }

  /// Mean luminance in an outer band (~5% of the shorter side, min 2 px) for “table at edges”.
  static double _borderMeanLuminance(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final t = math.max(2, (math.min(w, h) * 0.05).round());
    var sum = 0;
    var n = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (x < t || x >= w - t || y < t || y >= h - t) {
          sum += img.getLuminance(gray.getPixel(x, y)).round();
          n++;
        }
      }
    }
    return n == 0 ? 0.0 : sum / n;
  }

  /// Binary: luminance ≥ [threshold] is “white” (document paper); largest 8-connected region / frame.
  static double _largestBinaryRegionRatio(
    img.Image gray,
    int threshold,
  ) {
    final w = gray.width;
    final h = gray.height;
    final n = w * h;
    final white = List<bool>.filled(n, false);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (img.getLuminance(gray.getPixel(x, y)) >= threshold) {
          white[y * w + x] = true;
        }
      }
    }

    final visited = List<bool>.filled(n, false);
    var maxA = 0;
    for (int i = 0; i < n; i++) {
      if (!white[i] || visited[i]) continue;
      var size = 0;
      var qI = 0;
      final q = <int>[i];
      visited[i] = true;
      while (qI < q.length) {
        final c = q[qI++];
        size++;
        final cx = c % w;
        final cy = c ~/ w;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx;
            final ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (white[ni] && !visited[ni]) {
              visited[ni] = true;
              q.add(ni);
            }
          }
        }
      }
      if (size > maxA) maxA = size;
    }
    return maxA / n;
  }
}
