import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../core/imaging/image_processor.dart';
import '../core/inference/inference_service.dart';

/// HTTP server for on-device eval (Monte Carlo harness). Started only when
/// `kEvalMode` is true; must not affect normal app flows.
class EvalServer {
  EvalServer(this._inference);

  final InferenceService _inference;
  HttpServer? _server;
  int _inferenceCount = 0;
  int _lastInferenceMs = 0;

  Future<void> start({int port = 8080}) async {
    final router = Router();

    router.get('/health', (Request req) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'model': 'gemma4-e2b',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/infer', (Request req) async {
      Map<String, dynamic> body;
      try {
        final raw = await req.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          return Response.badRequest(
            body: jsonEncode({'error': 'JSON object body required'}),
            headers: {'content-type': 'application/json'},
          );
        }
        body = Map<String, dynamic>.from(decoded);
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON: $e'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final imageB64 = body['image'] as String?;
      final prompt = body['prompt'] as String?;
      if (imageB64 == null || prompt == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields: image, prompt'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.0;
      final tokenBudget = (body['token_budget'] as num?)?.toInt();
      final noticePreviewFirst = body['notice_preview_first'] == true ||
          body['notice_preview_first'] == 'true';
      final includeOcrDiag = body['include_ocr_diag'] == true ||
          body['include_ocr_diag'] == 'true';

      late final List<int> rawBytes;
      try {
        rawBytes = base64Decode(imageB64);
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid base64 image: $e'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final sw = Stopwatch()..start();
      String? rawResponse;
      String? ocrText;
      int? ocrElapsedMs;
      int? llmElapsedMs;
      int? previewMs;
      int? extractMs;
      try {
        if (noticePreviewFirst) {
          final r = await _inference.inferRawWithNoticePreview(
            imageBytes: Uint8List.fromList(rawBytes),
            extractionPrompt: prompt,
            temperature: temperature,
            tokenBudget: tokenBudget,
          );
          rawResponse = r.rawText;
          previewMs = r.previewElapsedMs;
          extractMs = r.extractElapsedMs;
          _inferenceCount += 2;
        } else if (includeOcrDiag) {
          final r = await _inference.inferRawWithOcr(
            imageBytes: Uint8List.fromList(rawBytes),
            prompt: prompt,
            temperature: temperature,
            tokenBudget: tokenBudget,
          );
          rawResponse = r.rawText;
          ocrText = r.ocrText;
          ocrElapsedMs = r.ocrElapsedMs;
          llmElapsedMs = r.llmElapsedMs;
          _inferenceCount++;
        } else {
          rawResponse = await _inference.inferRaw(
            imageBytes: Uint8List.fromList(rawBytes),
            prompt: prompt,
            temperature: temperature,
            tokenBudget: tokenBudget,
          );
          _inferenceCount++;
        }
      } catch (e, st) {
        debugPrint('Eval /infer error: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
      sw.stop();
      _lastInferenceMs = sw.elapsedMilliseconds;

      final text = rawResponse ?? '';
      final bodyOut = <String, dynamic>{
        'response': text,
        'elapsed_ms': sw.elapsedMilliseconds,
        'parse_ok': text.isNotEmpty,
        'notice_preview_first': noticePreviewFirst,
      };
      if (previewMs != null) {
        bodyOut['preview_elapsed_ms'] = previewMs;
        bodyOut['extract_elapsed_ms'] = extractMs;
      }
      if (ocrText != null) {
        bodyOut['ocr_text'] = ocrText;
        bodyOut['ocr_elapsed_ms'] = ocrElapsedMs;
        bodyOut['llm_elapsed_ms'] = llmElapsedMs;
      }
      return Response.ok(
        jsonEncode(bodyOut),
        headers: {'content-type': 'application/json'},
      );
    });

    /// Production-accurate Track A endpoint.
    ///
    /// Calls [InferenceService.analyzeTrackAWithOcr] — the exact same method the
    /// production app uses — with the [PromptTemplates.trackAOcrOnly] prompt,
    /// [_formatOcrResultsTrackA] OCR formatting, and maxTokens 2048.
    ///
    /// Request body (JSON):
    ///   image           — base64-encoded notice JPEG (required)
    ///   supporting_labels — JSON array of strings, e.g. ["Pay Stub"] (default [])
    ///
    /// Response body (JSON):
    ///   response        — raw LLM text
    ///   notice_summary  — {deadline, requested_categories, consequence} (parsed)
    ///   proof_pack      — array of proof-pack rows from TrackAResult
    ///   action_summary  — string
    ///   ocr_chars       — length of raw ML Kit OCR text for the notice
    ///   elapsed_ms      — total wall time
    ///   parse_ok        — true if TrackAResult parsed successfully
    router.post('/infer_track_a', (Request req) async {
      Map<String, dynamic> body;
      try {
        final raw = await req.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          return Response.badRequest(
            body: jsonEncode({'error': 'JSON object body required'}),
            headers: {'content-type': 'application/json'},
          );
        }
        body = Map<String, dynamic>.from(decoded);
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid JSON: $e'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final imageB64 = body['image'] as String?;
      if (imageB64 == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required field: image'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final supportingLabels = (body['supporting_labels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];

      late final List<int> rawBytes;
      try {
        rawBytes = base64Decode(imageB64);
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid base64 image: $e'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final sw = Stopwatch()..start();
      try {
        // Mirror the production image-processing pipeline exactly:
        // DocumentCapture._processCapturedFile calls ImageProcessor.processBytes
        // (max 2048px, JPEG quality 85) before passing to analyzeTrackAWithOcr.
        // Applying the same step here ensures eval OCR output matches production.
        final processedBytes = await ImageProcessor().processBytes(
          Uint8List.fromList(rawBytes),
        );

        // Run ML Kit OCR first to capture char count, then run the full
        // production inference (which internally runs OCR again via analyzeTrackAWithOcr).
        // The extra OCR call is eval-only overhead; it gives us the raw char count for
        // comparison and debugging without plumbing ocrChars into InferenceResult<T>.
        final ocrText = await _inference.extractOcrText(processedBytes);
        final ocrChars = ocrText.length;

        final result = await _inference.analyzeTrackAWithOcr(
          documents: [processedBytes],
          supportingDocumentLabels: supportingLabels,
        );
        sw.stop();
        _inferenceCount++;
        _lastInferenceMs = sw.elapsedMilliseconds;

        final noticeSummaryMap = result.isSuccess && result.data != null
            ? {
                'deadline': result.data!.noticeSummary.deadline,
                'requested_categories':
                    result.data!.noticeSummary.requestedCategories,
                'consequence': result.data!.noticeSummary.consequence,
              }
            : null;

        final proofPackList = result.isSuccess && result.data != null
            ? result.data!.proofPack
                .map((p) => {
                      'category': p.category,
                      'matched_document': p.matchedDocument,
                      'assessment': p.assessment.name,
                      'confidence': p.confidence.name,
                      'evidence': p.evidence,
                      'caveats': p.caveats,
                    })
                .toList()
            : null;

        final bodyOut = <String, dynamic>{
          'response': result.rawResponse ?? '',
          'elapsed_ms': sw.elapsedMilliseconds,
          'parse_ok': result.isSuccess,
          'ocr_chars': ocrChars,
        };
        if (noticeSummaryMap != null) bodyOut['notice_summary'] = noticeSummaryMap;
        if (proofPackList != null) bodyOut['proof_pack'] = proofPackList;
        if (result.isSuccess && result.data != null) {
          bodyOut['action_summary'] = result.data!.actionSummary;
        }
        if (!result.isSuccess) {
          bodyOut['error'] = result.errorMessage ?? 'Inference failed';
        }

        return Response.ok(
          jsonEncode(bodyOut),
          headers: {'content-type': 'application/json'},
        );
      } catch (e, st) {
        sw.stop();
        debugPrint('Eval /infer_track_a error: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.get('/device', (Request req) {
      return Response.ok(
        jsonEncode({
          'platform': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'processors': Platform.numberOfProcessors,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/metrics', (Request req) {
      int? rssMb;
      try {
        rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
      } catch (_) {
        rssMb = null;
      }
      return Response.ok(
        jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'memory_used_mb': rssMb,
          'inference_count': _inferenceCount,
          'last_inference_ms': _lastInferenceMs,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    debugPrint('Eval server running on port $port');
    debugPrint('Eval server listening on 0.0.0.0:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
