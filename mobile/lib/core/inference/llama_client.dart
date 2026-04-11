/// llama.cpp-based on-device inference client for CivicLens
///
/// Uses llama_cpp_dart package for Flutter bindings.
/// Runs model loading in a background isolate to avoid iOS watchdog kills.
/// Model format: GGUF

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'gemma_client.dart';

export 'gemma_client.dart' show GemmaResponse;

/// Isolate entry point: loads model and runs inference commands via ports
void _llamaIsolateEntry(List<dynamic> args) {
  final SendPort mainPort = args[0];
  final String modelPath = args[1];
  final String? libraryPath = args[2];

  final recvPort = ReceivePort();
  Llama? llama;

  try {
    Llama.libraryPath = libraryPath;

    final mp = ModelParams();
    // iOS: offload all layers to Metal — this is what gave ~12s LLM / ~15s B1 end-to-end.
    // CPU-only (nGpuLayers=0) was a speculative workaround for load issues; it makes
    // large-prompt prefill take minutes. Android: CPU until we validate a GPU backend.
    mp.nGpuLayers = Platform.isIOS ? 99 : 0;
    mp.useMemorymap = true;
    mp.useMemoryLock = false;

    // nBatch 4096 doubled native decode buffers and caused jetsam on some phones.
    // Stay at 2048; InferenceService clamps prompts so token count stays below that.
    final cp = ContextParams();
    cp.nCtx = 4096;
    cp.nBatch = 2048;
    cp.nUbatch = 2048;

    final sp = SamplerParams();
    sp.greedy = true;

    llama = Llama(
      modelPath,
      modelParams: mp,
      contextParams: cp,
      samplerParams: sp,
      verbose: true,
    );

    mainPort.send({'status': 'ready', 'port': recvPort.sendPort});
  } catch (e) {
    mainPort.send({'status': 'error', 'error': e.toString()});
    return;
  }

  recvPort.listen((message) {
    if (message is Map) {
      final cmd = message['cmd'] as String;
      final replyPort = message['replyPort'] as SendPort;

      if (cmd == 'chat') {
        try {
          final prompt = message['prompt'] as String;
          final maxTokens = message['maxTokens'] as int;

          replyPort.send({
            'progress': 0.0,
            'phase':
                'Starting inference…',
          });

          // Each chat is a fresh turn. Without clear(), _nPos and KV cache stay
          // filled from the last run → second "Check documents" hits context limit.
          llama!.clear();

          // Rough token estimate (~4 chars/token for English; conservative for JSON/OCR)
          final estPromptTokens = (prompt.length / 4).ceil().clamp(1, 100000);
          llama!.setPrompt(prompt);

          replyPort.send({
            'progress': 0.0,
            'phase':
                'Prefill: running one big CPU pass over ~$estPromptTokens prompt tokens '
                '(often 3–12 min on iPhone CPU). Percent stays at 0% until the first output token.',
          });

          final buffer = StringBuffer();
          int count = 0;
          bool done = false;
          var lastProgressBucket = -1;
          var reportedGenerating = false;

          while (!done) {
            final (text, isDone) = llama!.getNext();
            if (text.isNotEmpty) {
              buffer.write(text);
            }
            if (isDone) {
              done = true;
            } else {
              count++;
              if (count >= maxTokens) done = true;
            }
            if (!reportedGenerating && count > 0) {
              reportedGenerating = true;
              replyPort.send({
                'progress': (count / maxTokens).clamp(0.0, 1.0),
                'phase': 'Generating output tokens…',
              });
            }
            // Throttle to ~1% steps during output (more updates than before)
            if (maxTokens > 0) {
              final pct = (count / maxTokens).clamp(0.0, 1.0);
              final bucket = (pct * 100).floor();
              if (bucket != lastProgressBucket) {
                lastProgressBucket = bucket;
                replyPort.send({
                  'progress': pct,
                  if (reportedGenerating) 'phase': 'Generating output tokens…',
                });
              }
            }
          }

          replyPort.send({'result': buffer.toString()});
        } catch (e) {
          replyPort.send({'error': 'Inference failed: $e'});
        }
      } else if (cmd == 'dispose') {
        llama?.dispose();
        llama = null;
        recvPort.close();
        replyPort.send({'done': true});
      }
    }
  });
}

/// Client for on-device inference using llama.cpp
///
/// Uses a static isolate so only one model is loaded app-wide.
/// This prevents memory leaks when navigating between screens.
class LlamaClient {
  static Isolate? _isolate;
  static SendPort? _isolatePort;
  static bool _isInitialized = false;
  static String? _loadedModelPath;
  String? lastError;

  bool get isInitialized => _isInitialized;

  /// Ensures any previous model is fully cleaned up before proceeding.
  static Future<void> ensureCleanup() async {
    if (_isolatePort != null) {
      try {
        final replyPort = ReceivePort();
        _isolatePort!.send({'cmd': 'dispose', 'replyPort': replyPort.sendPort});
        await replyPort.first.timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    _isolate?.kill();
    _isolate = null;
    _isolatePort = null;
    _isInitialized = false;
    _loadedModelPath = null;
  }

  Future<bool> initialize({
    required String modelPath,
    void Function(double progress)? onProgress,
  }) async {
    // If same model is already loaded, reuse it
    if (_isInitialized && _loadedModelPath == modelPath && _isolatePort != null) {
      onProgress?.call(1.0);
      return true;
    }

    // Clean up any previous instance
    await ensureCleanup();

    final info = StringBuffer();

    try {
      onProgress?.call(0.0);

      final file = File(modelPath);
      if (!await file.exists()) {
        lastError = 'Model file not found: $modelPath';
        return false;
      }

      final fileSize = await file.length();
      info.writeln('Model: ${(fileSize / 1024 / 1024).toStringAsFixed(0)} MB');

      final handle = await file.open();
      final magic = await handle.read(4);
      await handle.close();
      if (String.fromCharCodes(magic) != 'GGUF') {
        lastError = '${info}Not a valid GGUF file.';
        return false;
      }

      onProgress?.call(0.1);

      String? libraryPath;
      if (Platform.isAndroid) {
        libraryPath = 'libmtmd.so';
      } else if (Platform.isIOS) {
        final execPath = Platform.resolvedExecutable;
        final bundlePath = execPath.substring(0, execPath.lastIndexOf('/'));
        libraryPath = '$bundlePath/Frameworks/libllama.dylib';
      }
      info.writeln('Library: ${libraryPath ?? "process"}');

      onProgress?.call(0.2);

      final recvPort = ReceivePort();
      _isolate = await Isolate.spawn(
        _llamaIsolateEntry,
        [recvPort.sendPort, modelPath, libraryPath],
      );

      onProgress?.call(0.3);
      info.writeln('Loading model in background...');

      final response = await recvPort.first.timeout(
        const Duration(seconds: 180),
        onTimeout: () => {'status': 'error', 'error': 'Timed out after 180s'},
      ) as Map;

      if (response['status'] == 'ready') {
        _isolatePort = response['port'] as SendPort;
        _isInitialized = true;
        _loadedModelPath = modelPath;
        onProgress?.call(1.0);
        return true;
      } else {
        lastError = '${info}Load failed: ${response['error']}';
        _isolate?.kill();
        _isolate = null;
        return false;
      }
    } catch (e, stackTrace) {
      _isInitialized = false;
      lastError = '${info}Init failed: $e\n$stackTrace';
      return false;
    }
  }

  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    double temperature = 0.0,
    int maxTokens = 2048,
    void Function(double progress, {String? phase})? onProgress,
  }) async {
    if (!_isInitialized || _isolatePort == null) {
      return GemmaResponse.error('Not initialized.');
    }

    final stopwatch = Stopwatch()..start();

    final replyPort = ReceivePort();
    var lastProgress = 0.0;
    String? lastPhase;
    Timer? heartbeat;
    if (onProgress != null) {
      heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
        onProgress(lastProgress, phase: lastPhase);
      });
    }
    try {
      _isolatePort!.send({
        'cmd': 'chat',
        'prompt': prompt,
        'maxTokens': maxTokens,
        'replyPort': replyPort.sendPort,
      });

      Map<String, dynamic>? finalMessage;
      await for (final raw in replyPort.timeout(
        const Duration(seconds: 1800),
        onTimeout: (s) => s.close(),
      )) {
        final msg = Map<String, dynamic>.from(raw as Map);
        if (msg.containsKey('progress')) {
          lastProgress = (msg['progress'] as num).toDouble();
          if (msg.containsKey('phase')) {
            lastPhase = msg['phase'] as String?;
          }
          onProgress?.call(lastProgress, phase: lastPhase);
        } else if (msg.containsKey('result') || msg.containsKey('error')) {
          finalMessage = msg;
          break;
        }
      }

      stopwatch.stop();
      heartbeat?.cancel();
      heartbeat = null;

      if (finalMessage == null) {
        return GemmaResponse.error(
          'Inference stalled (no progress for 30 minutes).',
          elapsed: stopwatch.elapsed,
        );
      }

      if (finalMessage.containsKey('result')) {
        onProgress?.call(1.0, phase: 'Done');
        return GemmaResponse(
          rawText: finalMessage['result'] as String,
          elapsed: stopwatch.elapsed,
        );
      }
      return GemmaResponse.error(
        finalMessage['error'] as String,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return GemmaResponse.error('Inference failed: $e', elapsed: stopwatch.elapsed);
    } finally {
      heartbeat?.cancel();
      replyPort.close();
    }
  }

  Future<GemmaResponse> chatWithImages({
    required String prompt,
    required List<Uint8List> images,
    double temperature = 0.0,
    int maxTokens = 2048,
  }) async {
    return chat(prompt: prompt, temperature: temperature, maxTokens: maxTokens);
  }

  Future<void> dispose() async {
    await ensureCleanup();
  }
}

/// Model converter helper
class ModelConverter {
  static Future<bool> isValidGguf(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.openRead(0, 4).first;
      final magic = String.fromCharCodes(bytes);
      return magic == 'GGUF';
    } catch (e) {
      return false;
    }
  }
}
