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
        'Could not parse JSON from the model. Try again; if it keeps failing, use clearer photos or shorter documents.',
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
        'Could not parse JSON from the model. Try again; if it keeps failing, use clearer photos or shorter documents.',
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

  /// Try multiple parsing strategies (direct, fences, balanced brace/array,
  /// trailing-comma repair, root-level requirements array).
  static Map<String, dynamic>? _parseWithRetry(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
    final fromMarkdown = _extractJsonFromMarkdown(raw);
    final bases = <String>[
      trimmed,
      _stripMarkdownFences(trimmed),
      if (fromMarkdown != null) fromMarkdown,
    ];

    for (final b in bases) {
      final t = b.trim();
      if (t.isEmpty) continue;

      // 1. Whole string (fixes valid JSON; try before balanced slices so we
      //    don't grab the first `{` inside a "requirements" array).
      var map = _decodeToObjectMap(t);
      if (map != null) return map;

      // 2. E4B-style: `"requirements": [...], ...` with outer `{` `}` omitted
      if (!t.startsWith('{')) {
        map = _decodeToObjectMap('{$t}');
        if (map != null) return map;
      }

      // 3. Balanced object / array slices (prose + JSON, or truncated output)
      final obj = _extractBalancedJsonObject(t);
      if (obj != null) {
        map = _decodeToObjectMap(obj);
        if (map != null) return map;
      }
      final arr = _extractBalancedJsonArray(t);
      if (arr != null) {
        map = _decodeToObjectMap(arr);
        if (map != null) return map;
      }
    }

    return null;
  }

  /// Decode JSON to a map Track B / Track A can consume (object or requirements-only array).
  static Map<String, dynamic>? _decodeToObjectMap(String s) {
    dynamic decoded;
    try {
      decoded = json.decode(s);
    } catch (_) {
      try {
        decoded = json.decode(_removeTrailingCommas(s));
      } catch (_) {
        return null;
      }
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    if (decoded is List) {
      return _tryWrapRequirementsList(decoded);
    }
    return null;
  }

  static String _removeTrailingCommas(String json) {
    return json.replaceAllMapped(
      RegExp(r',(\s*[\]}])'),
      (m) => m.group(1)!,
    );
  }

  /// If the model returns only the requirements array, normalize to full Track B shape.
  static Map<String, dynamic>? _tryWrapRequirementsList(List<dynamic> decoded) {
    if (decoded.isEmpty) {
      return {
        'requirements': <dynamic>[],
        'duplicate_category_flag': false,
        'duplicate_category_explanation': '',
        'family_summary': '',
      };
    }
    final first = decoded.first;
    if (first is! Map) return null;
    final keys = first.keys.map((k) => k.toString().toLowerCase()).toSet();
    if (keys.contains('requirement') ||
        keys.contains('status') ||
        keys.contains('matched_document')) {
      return {
        'requirements': decoded,
        'duplicate_category_flag': false,
        'duplicate_category_explanation': '',
        'family_summary': '',
      };
    }
    return null;
  }

  /// First `{` … matching `}` with string/escape awareness (fixes `}` inside evidence strings).
  static String? _extractBalancedJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (inString) {
        if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  /// First `[` … matching `]` with string/escape awareness.
  static String? _extractBalancedJsonArray(String text) {
    final start = text.indexOf('[');
    if (start == -1) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (inString) {
        if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
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
