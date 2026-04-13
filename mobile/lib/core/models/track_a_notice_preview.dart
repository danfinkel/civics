/// Lightweight notice-only read for Track A step 2 hints (not a legal outcome).
class TrackANoticePreview {
  final List<String> requestedCategories;
  final String deadline;
  final String hint;

  const TrackANoticePreview({
    required this.requestedCategories,
    required this.deadline,
    required this.hint,
  });

  bool get hasAnySignal =>
      requestedCategories.isNotEmpty ||
      deadline.trim().isNotEmpty ||
      hint.trim().isNotEmpty;

  factory TrackANoticePreview.fromJson(Map<String, dynamic> json) {
    final cats = json['requested_categories'];
    return TrackANoticePreview(
      requestedCategories: cats is List
          ? cats.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
          : const [],
      deadline: (json['deadline'] ?? '').toString().trim(),
      hint: (json['hint'] ?? '').toString().trim(),
    );
  }
}
