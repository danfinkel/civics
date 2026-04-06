/// Response parser for Gemma 4 inference results
///
/// Handles JSON extraction with retry logic based on spike Day 1 findings.
/// The E4B model occasionally omits braces or outputs bare key:value pairs.
///
/// Spike finding: Day 1 experiments showed ~5% of E4B responses had malformed
/// JSON (missing braces, markdown fences). A retry wrapper that tries multiple
/// parsing strategies achieved 100% parseability.

import 'dart:convert';
import '../models/track_a_result.dart';
import '../models/track_b_result.dart';

/// Result of parsing a response
class ParseResult<T> {
  /// The parsed result, or null if parsing failed
  final T? data;

  /// Whether parsing was successful
  final bool isSuccess;

  /// Error message if parsing failed
  final String? errorMessage;

  /// The raw text that was parsed
  final String rawText;

  /// Which parsing strategy succeeded (for debugging)
  final String? strategyUsed;

  const ParseResult({
    this.data,
    required this.isSuccess,
    this.errorMessage,
    required this.rawText,
    this.strategyUsed,
  });

  factory ParseResult.success(T data, String rawText, String strategy) {
    return ParseResult(
      data: data,
      isSuccess: true,
      rawText: rawText,
      strategyUsed: strategy,
    );
  }

  factory ParseResult.failure(String error, String rawText) {
    return ParseResult(
      isSuccess: false,
      errorMessage: error,
      rawText: rawText,
    );
  }
}

/// Parser for Gemma 4 responses
///
/// Implements the retry wrapper from spike Day 1:
/// 1. Try direct JSON parsing
/// 2. Try wrapping bare output in braces
/// 3. Try stripping markdown fences
/// 4. Return null if all fail (trigger error state in UI)
class ResponseParser {
  /// Parse Track A response
  ///
  /// Returns a [ParseResult] containing [TrackAResult] or error info
  static ParseResult<TrackAResult> parseTrackA(String raw) {
    final jsonResult = _parseWithRetry(raw);

    if (jsonResult == null) {
      return ParseResult.failure(
        'Failed to parse JSON after all retry strategies',
        raw,
      );
    }

    try {
      final result = TrackAResult.fromJson(jsonResult);
      return ParseResult.success(result, raw, 'track_a');
    } catch (e) {
      return ParseResult.failure(
        'JSON parsed but invalid Track A structure: $e',
        raw,
      );
    }
  }

  /// Parse Track B response
  ///
  /// Returns a [ParseResult] containing [TrackBResult] or error info
  static ParseResult<TrackBResult> parseTrackB(String raw) {
    final jsonResult = _parseWithRetry(raw);

    if (jsonResult == null) {
      return ParseResult.failure(
        'Failed to parse JSON after all retry strategies',
        raw,
      );
    }

    try {
      final result = TrackBResult.fromJson(jsonResult);
      return ParseResult.success(result, raw, 'track_b');
    } catch (e) {
      return ParseResult.failure(
        'JSON parsed but invalid Track B structure: $e',
        raw,
      );
    }
  }

  /// Try multiple parsing strategies
  /// 1. Direct JSON parse
  /// 2. Wrap in braces if missing
  /// 3. Strip markdown fences
  static Map<String, dynamic>? _parseWithRetry(String raw) {
    // Strategy 1: Direct parse
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {}

    // Strategy 2: Try wrapping bare key:value in braces
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) {
      try {
        return json.decode('{$trimmed}') as Map<String, dynamic>;
      } catch (_) {}
    }

    // Strategy 3: Strip markdown fences and retry
    final withoutFences = _stripMarkdownFences(trimmed);
    if (withoutFences != trimmed) {
      try {
        return json.decode(withoutFences) as Map<String, dynamic>;
      } catch (_) {}

      // Try with braces if still failing
      if (!withoutFences.startsWith('{')) {
        try {
          return json.decode('{$withoutFences}') as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    // Strategy 4: Extract JSON from text
    final extracted = _extractJsonFromText(raw);
    if (extracted != null) {
      return extracted;
    }

    // Strategy 5: Extract JSON from markdown code block
    final markdownExtracted = _extractJsonFromMarkdown(raw);
    if (markdownExtracted != null) {
      try {
        return json.decode(markdownExtracted) as Map<String, dynamic>;
      } catch (_) {}
    }

    return null;
  }

  /// Remove markdown code fences
  static String _stripMarkdownFences(String text) {
    var result = text;

    // Remove opening fence
    final fencePattern = RegExp(r'^```(?:json)?\s*', caseSensitive: false);
    result = result.replaceFirst(fencePattern, '');

    // Remove closing fence
    result = result.replaceFirst(RegExp(r'\s*```\s*$'), '');

    return result.trim();
  }

  /// Try to extract JSON object from surrounding text
  static Map<String, dynamic>? _extractJsonFromText(String text) {
    // Find the first { and last }
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');

    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      final jsonText = text.substring(startIndex, endIndex + 1);
      try {
        return json.decode(jsonText) as Map<String, dynamic>;
      } catch (_) {}
    }

    return null;
  }

  /// Extract JSON content from markdown code block
  static String? _extractJsonFromMarkdown(String text) {
    final codeBlockPattern = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = codeBlockPattern.firstMatch(text);

    if (match != null) {
      return match.group(1)?.trim();
    }

    return null;
  }

  /// Validate that a response contains expected Track A fields
  static bool isValidTrackAResponse(Map<String, dynamic> json) {
    return json.containsKey('notice_summary') &&
        json.containsKey('proof_pack') &&
        json.containsKey('action_summary');
  }

  /// Validate that a response contains expected Track B fields
  static bool isValidTrackBResponse(Map<String, dynamic> json) {
    return json.containsKey('requirements') &&
        json.containsKey('family_summary');
  }

  /// Extract confidence level from raw response text
  ///
  /// This is a fallback if JSON parsing fails but we still want
  /// to show some confidence indication to the user
  static ConfidenceLevel extractConfidenceFallback(String raw) {
    final lower = raw.toLowerCase();

    if (lower.contains('"confidence": "high"') ||
        lower.contains('"confidence": "high"')) {
      return ConfidenceLevel.high;
    }

    if (lower.contains('"confidence": "medium"') ||
        lower.contains('"confidence": "medium"')) {
      return ConfidenceLevel.medium;
    }

    if (lower.contains('"confidence": "low"') ||
        lower.contains('"confidence": "low"')) {
      return ConfidenceLevel.low;
    }

    return ConfidenceLevel.uncertain;
  }
}

/// Extension methods for parsing results
extension ParseResultExtension<T> on ParseResult<T> {
  /// Get the data or throw an exception
  T getOrThrow() {
    if (!isSuccess || data == null) {
      throw Exception(errorMessage ?? 'Parsing failed');
    }
    return data!;
  }

  /// Get the data or return a default value
  T? getOrNull() => data;

  /// Map the result to a different type if successful
  ParseResult<R> map<R>(R Function(T) transform) {
    if (!isSuccess || data == null) {
      return ParseResult<R>(
        isSuccess: false,
        errorMessage: errorMessage,
        rawText: rawText,
      );
    }

    try {
      return ParseResult<R>.success(
        transform(data as T),
        rawText,
        strategyUsed ?? 'mapped',
      );
    } catch (e) {
      return ParseResult<R>(
        isSuccess: false,
        errorMessage: 'Map failed: $e',
        rawText: rawText,
      );
    }
  }
}
