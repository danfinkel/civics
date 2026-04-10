/// Model download and management for Gemma 4 E2B
///
/// Handles downloading the 2.5GB model with resume support,
/// checksum verification, and progress reporting.
///
/// Model source: Hugging Face or Google AI Edge
/// Expected size: ~2.5GB (2,684,354,560 bytes)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Download state
enum DownloadState {
  notStarted,
  checking,
  downloading,
  paused,
  completed,
  error,
}

/// Download result
class DownloadResult {
  final bool success;
  final String? errorMessage;
  final String? modelPath;
  final Duration elapsed;

  const DownloadResult({
    required this.success,
    this.errorMessage,
    this.modelPath,
    required this.elapsed,
  });

  factory DownloadResult.success(String path, Duration elapsed) {
    return DownloadResult(
      success: true,
      modelPath: path,
      elapsed: elapsed,
    );
  }

  factory DownloadResult.failure(String error, Duration elapsed) {
    return DownloadResult(
      success: false,
      errorMessage: error,
      elapsed: elapsed,
    );
  }
}

/// Progress callback
typedef DownloadProgressCallback = void Function(
  double progress,
  int bytesDownloaded,
  int totalBytes,
);

/// Manages Gemma 4 E2B model download and verification
class ModelManager {
  // Model configuration
  // Using Hugging Face as primary source (more reliable for hackathon)
  static const String _hfModelUrl =
      'https://huggingface.co/google/gemma-2b-it/resolve/main/gemma-2b-it.q4_0.gguf';

  // Alternative: Google AI Edge (when Gemma 4 E2B is available)
  static const String _googleAiEdgeUrl =
      'https://storage.googleapis.com/mediapipe-models/gemma/...'; // TODO: Update when available

  // Model metadata
  static const int modelSizeBytes = 2986344448; // ~2.9 GB (gemma-4-E2B-it-Q4_K_M.gguf)
  static const String expectedChecksum =
      '...'; // TODO: Update with actual SHA256
  static const String modelFilename = 'gemma-4-E2B-it-Q4_K_M.gguf';

  // Download configuration
  static const int _chunkSize = 1024 * 1024; // 1MB chunks
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);

  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  bool _isPaused = false;
  bool _isCancelled = false;

  /// Current download state
  DownloadState _state = DownloadState.notStarted;
  DownloadState get state => _state;

  /// Get the model directory path (Documents/ to match Agent 2's test setup)
  Future<Directory> get _modelDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    // Use Documents/ directly (not Documents/models/) to match Agent 2's working setup
    return appDir;
  }

  /// Get the full model file path
  Future<String> get modelPath async {
    final dir = await _modelDirectory;
    return '${dir.path}/$modelFilename';
  }

  /// Get the partial download file path (for resume)
  Future<String> get _partialPath async {
    final dir = await _modelDirectory;
    return '${dir.path}/$modelFilename.partial';
  }

  /// Check if model is already downloaded and valid
  Future<bool> isModelAvailable() async {
    final path = await modelPath;
    final file = File(path);

    if (!await file.exists()) {
      return false;
    }

    // Check file size
    final size = await file.length();
    if (size < modelSizeBytes * 0.99) {
      // Allow 1% tolerance
      return false;
    }

    // TODO: Verify checksum if available
    // if (expectedChecksum != '...') {
    //   final actualChecksum = await _calculateChecksum(path);
    //   return actualChecksum == expectedChecksum;
    // }

    return true;
  }

  /// Get download progress if resuming
  Future<int> get _resumePosition async {
    final partialPath = await _partialPath;
    final partialFile = File(partialPath);

    if (await partialFile.exists()) {
      return await partialFile.length();
    }

    return 0;
  }

  /// Download the model with resume support
  ///
  /// [onProgress] - Called with (progress 0.0-1.0, bytesDownloaded, totalBytes)
  /// [onStateChange] - Called when download state changes
  Future<DownloadResult> downloadModel({
    DownloadProgressCallback? onProgress,
    void Function(DownloadState)? onStateChange,
    String? sourceUrl,
  }) async {
    final stopwatch = Stopwatch()..start();
    _state = DownloadState.checking;
    onStateChange?.call(_state);

    // Check if already downloaded
    if (await isModelAvailable()) {
      _state = DownloadState.completed;
      onStateChange?.call(_state);
      stopwatch.stop();
      final path = await modelPath;
      return DownloadResult.success(path, stopwatch.elapsed);
    }

    _state = DownloadState.downloading;
    onStateChange?.call(_state);

    final url = sourceUrl ?? _hfModelUrl;
    final partialPath = await _partialPath;
    final finalPath = await modelPath;
    final resumePosition = await _resumePosition;

    _client?.close();
    _client = http.Client();

    int bytesDownloaded = resumePosition;
    int retries = 0;

    while (retries < _maxRetries) {
      try {
        // Create request with range header for resume
        final request = http.Request('GET', Uri.parse(url));
        if (resumePosition > 0) {
          request.headers['Range'] = 'bytes=$resumePosition-';
        }

        final response = await _client!.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(url),
          );
        }

        // Get total size from headers
        final contentLength = response.contentLength ?? modelSizeBytes;
        final totalBytes = resumePosition + contentLength;

        // Open file for append (resume) or create new
        final file = File(partialPath);
        final sink = file.openWrite(
          mode: resumePosition > 0 ? FileMode.append : FileMode.write,
        );

        // Download chunks
        await for (final chunk in response.stream) {
          if (_isCancelled) {
            await sink.close();
            throw Exception('Download cancelled');
          }

          while (_isPaused) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

          sink.add(chunk);
          bytesDownloaded += chunk.length;

          final progress = bytesDownloaded / totalBytes;
          onProgress?.call(progress.clamp(0.0, 1.0), bytesDownloaded, totalBytes);
        }

        await sink.close();

        // Verify download
        if (bytesDownloaded < totalBytes * 0.99) {
          throw Exception(
            'Incomplete download: $bytesDownloaded / $totalBytes bytes',
          );
        }

        // Move partial file to final location
        await file.rename(finalPath);

        // Verify checksum if available
        if (expectedChecksum != '...') {
          _state = DownloadState.checking;
          onStateChange?.call(_state);

          final actualChecksum = await _calculateChecksum(finalPath);
          if (actualChecksum != expectedChecksum) {
            await File(finalPath).delete();
            throw Exception('Checksum mismatch - download corrupted');
          }
        }

        _state = DownloadState.completed;
        onStateChange?.call(_state);
        stopwatch.stop();

        return DownloadResult.success(finalPath, stopwatch.elapsed);
      } catch (e) {
        retries++;

        if (retries >= _maxRetries) {
          _state = DownloadState.error;
          onStateChange?.call(_state);
          stopwatch.stop();
          return DownloadResult.failure(
            'Download failed after $_maxRetries attempts: $e',
            stopwatch.elapsed,
          );
        }

        // Wait before retry
        await Future.delayed(_retryDelay * retries);
      }
    }

    _state = DownloadState.error;
    onStateChange?.call(_state);
    stopwatch.stop();
    return DownloadResult.failure(
      'Download failed - max retries exceeded',
      stopwatch.elapsed,
    );
  }

  /// Pause the current download
  void pause() {
    _isPaused = true;
    if (_state == DownloadState.downloading) {
      _state = DownloadState.paused;
    }
  }

  /// Resume a paused download
  void resume() {
    _isPaused = false;
    if (_state == DownloadState.paused) {
      _state = DownloadState.downloading;
    }
  }

  /// Cancel the current download
  Future<void> cancel() async {
    _isCancelled = true;
    await _subscription?.cancel();
    _client?.close();
    _client = null;
  }

  /// Delete the downloaded model
  Future<void> deleteModel() async {
    await cancel();

    final path = await modelPath;
    final partialPath = await _partialPath;

    final file = File(path);
    final partialFile = File(partialPath);

    if (await file.exists()) {
      await file.delete();
    }

    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    _state = DownloadState.notStarted;
  }

  /// Calculate SHA256 checksum of a file
  Future<String> _calculateChecksum(String filePath) async {
    final file = File(filePath);
    final stream = file.openRead();
    final hash = await stream.transform(sha256).first;
    return base64Encode(hash.bytes);
  }

  /// Get download status for UI display
  Future<Map<String, dynamic>> getStatus() async {
    final available = await isModelAvailable();
    final path = await modelPath;
    final partial = await _partialPath;

    int downloadedBytes = 0;
    if (await File(partial).exists()) {
      downloadedBytes = await File(partial).length();
    } else if (available) {
      downloadedBytes = modelSizeBytes;
    }

    return {
      'state': _state.toString(),
      'isAvailable': available,
      'modelPath': path,
      'downloadedBytes': downloadedBytes,
      'totalBytes': modelSizeBytes,
      'progress': downloadedBytes / modelSizeBytes,
    };
  }

  /// Dispose resources
  void dispose() {
    cancel();
  }
}

/// Extension for DownloadState
extension DownloadStateExtension on DownloadState {
  String get displayName {
    switch (this) {
      case DownloadState.notStarted:
        return 'Not started';
      case DownloadState.checking:
        return 'Checking...';
      case DownloadState.downloading:
        return 'Downloading...';
      case DownloadState.paused:
        return 'Paused';
      case DownloadState.completed:
        return 'Ready';
      case DownloadState.error:
        return 'Error';
    }
  }

  bool get isActive =>
      this == DownloadState.downloading || this == DownloadState.checking;

  bool get isComplete => this == DownloadState.completed;

  bool get hasError => this == DownloadState.error;
}