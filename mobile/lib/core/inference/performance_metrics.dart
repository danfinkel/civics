/// Performance metrics collection for CivicLens inference
///
/// Tracks timing, memory usage, and success rates for model operations.
/// Used to generate PERFORMANCE.md report and identify bottlenecks.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Individual metric record
class MetricRecord {
  final String operation;
  final DateTime timestamp;
  final Duration elapsed;
  final bool success;
  final int? documentCount;
  final int? memoryBytesBefore;
  final int? memoryBytesAfter;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  const MetricRecord({
    required this.operation,
    required this.timestamp,
    required this.elapsed,
    required this.success,
    this.documentCount,
    this.memoryBytesBefore,
    this.memoryBytesAfter,
    this.errorMessage,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'operation': operation,
        'timestamp': timestamp.toIso8601String(),
        'elapsed_ms': elapsed.inMilliseconds,
        'success': success,
        'document_count': documentCount,
        'memory_bytes_before': memoryBytesBefore,
        'memory_bytes_after': memoryBytesAfter,
        'error_message': errorMessage,
        'metadata': metadata,
      };

  factory MetricRecord.fromJson(Map<String, dynamic> json) {
    return MetricRecord(
      operation: json['operation'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      elapsed: Duration(milliseconds: json['elapsed_ms'] as int),
      success: json['success'] as bool,
      documentCount: json['document_count'] as int?,
      memoryBytesBefore: json['memory_bytes_before'] as int?,
      memoryBytesAfter: json['memory_bytes_after'] as int?,
      errorMessage: json['error_message'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Performance metrics collector
class PerformanceMetrics {
  static final List<MetricRecord> _records = [];
  static bool _enabled = true;
  static int _maxRecords = 1000;

  /// Enable/disable metrics collection
  static set enabled(bool value) => _enabled = value;

  /// Maximum records to keep in memory
  static set maxRecords(int value) => _maxRecords = value;

  /// Log an inference operation
  static void logInference({
    required int documentCount,
    required Duration elapsed,
    required bool success,
    int? memoryBytesBefore,
    int? memoryBytesAfter,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    if (!_enabled) return;

    final record = MetricRecord(
      operation: 'inference',
      timestamp: DateTime.now(),
      elapsed: elapsed,
      success: success,
      documentCount: documentCount,
      memoryBytesBefore: memoryBytesBefore,
      memoryBytesAfter: memoryBytesAfter,
      errorMessage: errorMessage,
      metadata: metadata,
    );

    _addRecord(record);
  }

  /// Log model initialization
  static void logInitialization({
    required Duration elapsed,
    required bool success,
    String? errorMessage,
  }) {
    if (!_enabled) return;

    final record = MetricRecord(
      operation: 'initialization',
      timestamp: DateTime.now(),
      elapsed: elapsed,
      success: success,
      errorMessage: errorMessage,
    );

    _addRecord(record);
  }

  /// Log model download
  static void logDownload({
    required Duration elapsed,
    required bool success,
    required int bytesDownloaded,
    String? errorMessage,
  }) {
    if (!_enabled) return;

    final record = MetricRecord(
      operation: 'download',
      timestamp: DateTime.now(),
      elapsed: elapsed,
      success: success,
      metadata: {'bytes_downloaded': bytesDownloaded},
      errorMessage: errorMessage,
    );

    _addRecord(record);
  }

  static void _addRecord(MetricRecord record) {
    _records.add(record);

    // Keep only recent records
    if (_records.length > _maxRecords) {
      _records.removeAt(0);
    }
  }

  /// Get all records
  static List<MetricRecord> get records => List.unmodifiable(_records);

  /// Get records for a specific operation
  static List<MetricRecord> getRecordsFor(String operation) {
    return _records.where((r) => r.operation == operation).toList();
  }

  /// Calculate average inference time
  static Duration get averageInferenceTime {
    final inferenceRecords = getRecordsFor('inference').where((r) => r.success);
    if (inferenceRecords.isEmpty) return Duration.zero;

    final totalMs = inferenceRecords.fold<int>(
      0,
      (sum, r) => sum + r.elapsed.inMilliseconds,
    );

    return Duration(milliseconds: totalMs ~/ inferenceRecords.length);
  }

  /// Get success rate for an operation
  static double getSuccessRate(String operation) {
    final records = getRecordsFor(operation);
    if (records.isEmpty) return 0.0;

    final successful = records.where((r) => r.success).length;
    return successful / records.length;
  }

  /// Get inference time by document count
  static Map<int, Duration> getInferenceTimeByDocumentCount() {
    final result = <int, List<Duration>>{};

    for (final record in getRecordsFor('inference')) {
      if (!record.success || record.documentCount == null) continue;

      final count = record.documentCount!;
      result.putIfAbsent(count, () => []);
      result[count]!.add(record.elapsed);
    }

    return result.map((count, durations) {
      final avgMs = durations.fold<int>(0, (s, d) => s + d.inMilliseconds) ~/
          durations.length;
      return MapEntry(count, Duration(milliseconds: avgMs));
    });
  }

  /// Generate performance report
  static Map<String, dynamic> generateReport() {
    final inferenceByDocCount = getInferenceTimeByDocumentCount();

    return {
      'generated_at': DateTime.now().toIso8601String(),
      'total_records': _records.length,
      'initialization': {
        'attempts': getRecordsFor('initialization').length,
        'success_rate': getSuccessRate('initialization'),
        'average_time_ms': _averageTimeFor('initialization')?.inMilliseconds,
      },
      'inference': {
        'attempts': getRecordsFor('inference').length,
        'success_rate': getSuccessRate('inference'),
        'average_time_ms': averageInferenceTime.inMilliseconds,
        'by_document_count': inferenceByDocCount.map(
          (k, v) => MapEntry(k.toString(), v.inMilliseconds),
        ),
      },
      'download': {
        'attempts': getRecordsFor('download').length,
        'success_rate': getSuccessRate('download'),
        'average_time_ms': _averageTimeFor('download')?.inMilliseconds,
      },
    };
  }

  static Duration? _averageTimeFor(String operation) {
    final records =
        getRecordsFor(operation).where((r) => r.success).toList();
    if (records.isEmpty) return null;

    final totalMs = records.fold<int>(
      0,
      (sum, r) => sum + r.elapsed.inMilliseconds,
    );

    return Duration(milliseconds: totalMs ~/ records.length);
  }

  /// Save metrics to file
  static Future<void> saveToFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/performance_metrics.json');

    final data = {
      'records': _records.map((r) => r.toJson()).toList(),
      'report': generateReport(),
    };

    await file.writeAsString(jsonEncode(data));
  }

  /// Load metrics from file
  static Future<void> loadFromFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/performance_metrics.json');

      if (!await file.exists()) return;

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final records = (json['records'] as List)
          .map((r) => MetricRecord.fromJson(r as Map<String, dynamic>))
          .toList();

      _records.clear();
      _records.addAll(records);
    } catch (e) {
      print('Failed to load metrics: $e');
    }
  }

  /// Clear all records
  static void clear() {
    _records.clear();
  }

  /// Print report to console (for debugging)
  static void printReport() {
    final report = generateReport();
    const encoder = JsonEncoder.withIndent('  ');
    print(encoder.convert(report));
  }
}

/// Mixin for adding performance tracking to a class
mixin PerformanceTracking {
  final Map<String, Stopwatch> _stopwatches = {};

  void startTimer(String operation) {
    _stopwatches[operation] = Stopwatch()..start();
  }

  Duration? stopTimer(String operation) {
    final sw = _stopwatches[operation];
    if (sw == null) return null;

    sw.stop();
    return sw.elapsed;
  }

  void logOperation({
    required String operation,
    required Duration elapsed,
    required bool success,
    int? documentCount,
    String? errorMessage,
  }) {
    PerformanceMetrics.logInference(
      documentCount: documentCount ?? 0,
      elapsed: elapsed,
      success: success,
      errorMessage: errorMessage,
    );
  }
}
