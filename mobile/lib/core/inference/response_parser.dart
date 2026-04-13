/// Response parser for Gemma 4 inference results
///
/// Handles JSON extraction with retry logic based on spike Day 1 findings.
/// The E4B model occasionally omits braces or outputs bare key:value pairs.
///
/// Spike finding: Day 1 experiments showed ~5% of E4B responses had malformed
/// JSON (missing braces, markdown fences). A retry wrapper that tries multiple
/// parsing strategies achieved 100% parseability.

import 'dart:convert';
import '../models/track_a_notice_preview.dart';
import '../models/track_a_result.dart';
import '../models/track_b_result.dart';
import '../utils/label_formatter.dart';

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
    final trimmed = raw.trim();
    final jsonResult =
        _parseWithRetry(_repairTrackAGemmaJson(trimmed)) ?? _parseWithRetry(trimmed);

    if (jsonResult == null) {
      return ParseResult.failure(
        'Could not parse JSON from the model. Try again; if it keeps failing, use clearer photos or shorter documents.',
        raw,
      );
    }

    try {
      var result = TrackAResult.fromJson(jsonResult);
      if (result.actionSummary.trim().isEmpty) {
        result = TrackAResult(
          noticeSummary: result.noticeSummary,
          proofPack: result.proofPack,
          actionSummary: LabelFormatter.synthesizeTrackAActionSummary(result),
        );
      }
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

  /// Parse Track A notice-only preview JSON (step 2 hint card).
  static ParseResult<TrackANoticePreview> parseTrackANoticePreview(String raw) {
    final trimmed = raw.trim();
    final jsonResult =
        _parseWithRetry(_repairTrackAGemmaJson(trimmed)) ?? _parseWithRetry(trimmed);

    if (jsonResult == null) {
      return ParseResult.failure(
        'Could not parse notice preview JSON',
        raw,
      );
    }

    try {
      final result = TrackANoticePreview.fromJson(
        Map<String, dynamic>.from(jsonResult),
      );
      return ParseResult.success(result, raw, 'track_a_notice_preview');
    } catch (e) {
      return ParseResult.failure(
        'Invalid notice preview structure: $e',
        raw,
      );
    }
  }

  /// Gemma on-device sometimes emits invalid JSON: after a period inside
  /// `caveats` it may output `."","}` instead of `.}"}` before `],"`.
  static String _repairTrackAGemmaJson(String s) {
    var o = s.trim();
    // `...caveats":"...sentence.","}],"` → `...sentence."}],"`
    o = o.replaceAll(RegExp(r'\.","\}'), '.}"}');
    // Gemma: extra `"` before a key — `],""deadline"` → `],"deadline"`
    o = o.replaceAllMapped(
      RegExp(r',\s*""(\w+)"'),
      (m) => ',"${m[1]}"',
    );
    o = o.replaceAll('"deadline":"[Not specified"', '"deadline":"UNCERTAIN"');
    o = o.replaceAll('"deadline":"[Not specified]"', '"deadline":"UNCERTAIN"');
    o = o.replaceAll('"consequence":"[Not specified]"', '"consequence":"UNCERTAIN"');
    o = o.replaceAll('"consequence":"[Not specified"', '"consequence":"UNCERTAIN"');
    // Prose after closing `}`: `}\naction_summary:...` → valid JSON field
    final asTail = RegExp(
      r'\}\s*\r?\n\s*action_summary\s*:',
      caseSensitive: false,
    );
    final tailMatches = asTail.allMatches(o).toList();
    if (tailMatches.isNotEmpty) {
      final m = tailMatches.last;
      final prefix = o.substring(0, m.start);
      final prose = o.substring(m.end).trim();
      if (prose.isNotEmpty) {
        o = '$prefix,"action_summary":${jsonEncode(prose)}}';
      }
    }
    return o;
  }

  /// Try multiple parsing strategies (direct, fences, balanced brace/array,
  /// trailing-comma repair, root-level requirements array).
  static Map<String, dynamic>? _parseWithRetry(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
    final fromMarkdown = _extractJsonFromMarkdown(raw);
    final openFence = _extractOpenMarkdownFence(trimmed);
    final bases = <String>{
      trimmed,
      _stripMarkdownFences(trimmed),
      if (fromMarkdown != null) fromMarkdown,
      if (openFence != null && openFence.isNotEmpty) openFence,
      _escapeNewlinesInsideJsonStrings(trimmed),
      if (openFence != null && openFence.isNotEmpty)
        _escapeNewlinesInsideJsonStrings(openFence),
    }.where((s) => s.trim().isNotEmpty).toList();

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
      var obj = _extractBalancedJsonObject(t);
      if (obj != null) {
        map = _decodeToObjectMap(obj);
        if (map != null) return map;
        map = _decodeToObjectMap(_escapeNewlinesInsideJsonStrings(obj));
        if (map != null) return map;
      }
      final arr = _extractBalancedJsonArray(t);
      if (arr != null) {
        map = _decodeToObjectMap(arr);
        if (map != null) return map;
      }
    }

    // 4. Truncated / sloppy output: try slices ending at each `}` (prose after JSON).
    for (final b in bases) {
      final t = b.trim();
      if (t.isEmpty) continue;
      final map = _decodeByScanningClosingBraces(t);
      if (map != null) return map;
    }

    // 5. Unterminated object/array: close strings + brackets (llm hit token limit).
    for (final b in bases) {
      final t = b.trim();
      if (t.isEmpty) continue;
      final closed = _autoCloseTruncatedJson(t);
      if (closed != null) {
        var map = _decodeToObjectMap(closed);
        map ??= _decodeToObjectMap(_removeTrailingCommas(closed));
        map ??= _decodeToObjectMap(
          _removeTrailingCommas(_escapeNewlinesInsideJsonStrings(closed)),
        );
        if (map != null) return map;
      }
    }

    // 6. Model echoed preamble before JSON: try every `{` as object start.
    for (final b in bases) {
      final map = _decodeByTryingEachObjectStart(b);
      if (map != null) return map;
    }

    return null;
  }

  /// Opening ```json … without closing ``` (common when output is truncated).
  static String? _extractOpenMarkdownFence(String text) {
    final m = RegExp(
      r'```(?:json)?\s*',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    final rest = text.substring(m.end).trim();
    if (rest.isEmpty) return null;
    return rest;
  }

  /// LLMs often emit raw line breaks inside "evidence" / summaries — invalid JSON.
  static String _escapeNewlinesInsideJsonStrings(String s) {
    final buf = StringBuffer();
    var inString = false;
    var escape = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (escape) {
        buf.write(ch);
        escape = false;
        continue;
      }
      if (inString) {
        if (ch == r'\') {
          buf.write(ch);
          escape = true;
        } else if (ch == '"') {
          buf.write(ch);
          inString = false;
        } else if (ch == '\n') {
          buf.write(r'\n');
        } else if (ch == '\r') {
          buf.write(r'\n');
          if (i + 1 < s.length && s[i + 1] == '\n') {
            i++;
          }
        } else {
          buf.write(ch);
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  /// Walk each `{` and attempt balanced-object extraction + decode.
  static Map<String, dynamic>? _decodeByTryingEachObjectStart(String text) {
    var searchStart = 0;
    Map<String, dynamic>? fallback;
    while (true) {
      final idx = text.indexOf('{', searchStart);
      if (idx < 0) return fallback;
      final obj = _extractBalancedJsonObject(text, startIndex: idx);
      if (obj != null) {
        var map = _decodeToObjectMap(obj);
        map ??= _decodeToObjectMap(_escapeNewlinesInsideJsonStrings(obj));
        if (map != null) {
          if (_looksLikeTrackAOrBPayload(map)) return map;
          fallback ??= map;
        }
        final closed = _autoCloseTruncatedJson(text.substring(idx));
        if (closed != null) {
          map = _decodeToObjectMap(closed);
          map ??= _decodeToObjectMap(
            _removeTrailingCommas(_escapeNewlinesInsideJsonStrings(closed)),
          );
          if (map != null) {
            if (_looksLikeTrackAOrBPayload(map)) return map;
            fallback ??= map;
          }
        }
      }
      searchStart = idx + 1;
    }
  }

  static bool _looksLikeTrackAOrBPayload(Map<String, dynamic> m) {
    return m.containsKey('proof_pack') ||
        m.containsKey('notice_summary') ||
        m.containsKey('requirements') ||
        m.containsKey('family_summary');
  }

  /// Try substrings from first `{` to each `}` from the end (inner `}` first breaks decode).
  static Map<String, dynamic>? _decodeByScanningClosingBraces(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var end = text.lastIndexOf('}');
    while (end > start) {
      final slice = text.substring(start, end + 1);
      final map = _decodeToObjectMap(slice);
      if (map != null) return map;
      end = text.lastIndexOf('}', end - 1);
    }
    return null;
  }

  /// Append `"` if inside a string, then `]` / `}` to empty the bracket stack.
  static String? _autoCloseTruncatedJson(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var s = text.substring(start);
    final stack = <String>[];
    var inString = false;
    var escape = false;

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
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
        stack.add('}');
      } else if (ch == '[') {
        stack.add(']');
      } else if (ch == '}') {
        if (stack.isNotEmpty && stack.last == '}') {
          stack.removeLast();
        }
      } else if (ch == ']') {
        if (stack.isNotEmpty && stack.last == ']') {
          stack.removeLast();
        }
      }
    }

    if (inString) {
      s = '$s"';
    }
    if (stack.isEmpty) return s;
    final tail = stack.reversed.join();
    return s + tail;
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
        try {
          decoded = json.decode(
            _removeTrailingCommas(_escapeNewlinesInsideJsonStrings(s)),
          );
        } catch (_) {
          return null;
        }
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
  static String? _extractBalancedJsonObject(
    String text, {
    int startIndex = -1,
  }) {
    final start = startIndex >= 0 ? startIndex : text.indexOf('{');
    if (start == -1 || start >= text.length) return null;
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
