import 'package:flutter/material.dart';
import '../../core/imaging/document_capture.dart';
import '../../core/models/track_a_notice_preview.dart';
import '../../core/models/track_a_result.dart';
import '../../core/utils/label_formatter.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/prism_tokens.dart';
import '../../shared/theme/prism_typography.dart';
import 'track_a_controller.dart';
import 'widgets/track_a_results_view.dart';

class TrackAScreen extends StatefulWidget {
  const TrackAScreen({super.key});

  @override
  State<TrackAScreen> createState() => _TrackAScreenState();
}

class _TrackAScreenState extends State<TrackAScreen> {
  final TrackAController _controller = TrackAController();
  bool _isAnalyzing = false;
  TrackAResult? _result;
  bool _noticePreviewLoading = false;
  TrackANoticePreview? _noticePreview;

  @override
  void initState() {
    super.initState();
    // Llama may load when a notice is set (background preview) or on "Check my documents".
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onNoticeCaptured(CapturedDocument doc) async {
    setState(() {
      _controller.setNotice(doc);
    });

    if (doc.blurResult.isBlurry && mounted) {
      _showBlurWarning(doc, isNotice: true);
    }

    _scheduleNoticePreview();
  }

  /// Fire-and-forget notice read for step 2; ignores stale results if notice changes.
  void _scheduleNoticePreview() {
    final id = _controller.notice?.id;
    if (id == null) return;

    Future.microtask(() async {
      if (!mounted || _controller.notice?.id != id) return;
      setState(() {
        _noticePreviewLoading = true;
        _noticePreview = null;
      });

      final preview = await _controller.prefetchNoticePreview();

      if (!mounted || _controller.notice?.id != id) return;
      setState(() {
        _noticePreviewLoading = false;
        _noticePreview = preview;
      });
    });
  }

  Future<void> _onDocumentCaptured(int index, CapturedDocument doc) async {
    setState(() {
      _controller.setSupportingDocument(index, doc);
    });

    if (doc.blurResult.isBlurry && mounted) {
      _showBlurWarning(doc);
    }
  }

  void _showBlurWarning(CapturedDocument doc, {bool isNotice = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo May Be Unclear'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber,
              color: AppColors.warning,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(doc.blurResult.guidance),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (isNotice) {
                  final n = _controller.notice;
                  if (n != null) {
                    _controller.setNotice(
                      n.copyWith(acceptedDespiteBlur: true),
                    );
                  }
                } else {
                  final idx = _controller.supportingDocuments
                      .indexWhere((d) => d?.id == doc.id);
                  final d = idx >= 0 ? _controller.supportingDocuments[idx] : null;
                  if (d != null) {
                    _controller.setSupportingDocument(
                      idx,
                      d.copyWith(acceptedDespiteBlur: true),
                    );
                  }
                }
              });
            },
            child: const Text('Use Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (isNotice) {
                  _controller.clearNotice();
                  _noticePreview = null;
                  _noticePreviewLoading = false;
                } else {
                  _controller.clearSupportingDocument(
                    _controller.supportingDocuments.indexWhere(
                      (d) => d?.id == doc.id,
                    ),
                  );
                }
              });
            },
            child: const Text('Retake'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeDocuments() async {
    setState(() => _isAnalyzing = true);

    try {
      final result = await _controller.analyzeDocuments();
      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      }
    }
  }

  void _startOver() {
    setState(() {
      _controller.clearAll();
      _result = null;
      _noticePreview = null;
      _noticePreviewLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('SNAP Document Check'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {},
            ),
        ],
      ),
      body: _result != null
          ? TrackAResultsView(
              result: _result!,
              onStartOver: _startOver,
              onSaveSummary: () {},
            )
          : _buildUploadView(),
    );
  }

  Widget _buildUploadView() {
    return Column(
      children: [
        // Progress indicator
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _controller.notice != null
                      ? AppColors.success
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _controller.notice != null ? 'Step 2 of 2' : 'Step 1 of 2',
                  style: PrismTypography.publicSans(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _controller.notice != null
                    ? 'Upload Your Documents'
                    : 'Upload Your Notice',
                style: PrismTypography.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Notice upload (Step 1)
              if (_controller.notice == null) ...[
                _buildNoticeUpload(),
              ] else ...[
                _buildNoticePreview(),
                const SizedBox(height: 24),
                Text(
                  'Your Documents',
                  style: PrismTypography.spaceGrotesk(fontSize: 18),
                ),
                const SizedBox(height: 12),
                _buildNoticeContextHint(),
                const SizedBox(height: 16),
                // Supporting documents
                ...List.generate(
                  _controller.supportingDocuments.length,
                  (index) => _buildSupportingDocumentSlot(index),
                ),
              ],
            ],
          ),
        ),

        // CTA Button
        if (_controller.notice != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _controller.canAnalyze && !_isAnalyzing
                  ? _analyzeDocuments
                  : null,
              child: _isAnalyzing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Analyzing...',
                          style: PrismTypography.publicSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : const Text('Check My Documents'),
            ),
          ),
      ],
    );
  }

  Widget _buildNoticeUpload() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
        boxShadow: PrismShadows.card(context),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.description,
            size: 48,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Upload Your Government Notice',
            style: PrismTypography.spaceGrotesk(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'This is the letter or notice you received requesting documents',
            textAlign: TextAlign.center,
            style: PrismTypography.publicSans(
              fontSize: 14,
              color: AppColors.neutral,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () async {
                    final capture = DocumentCapture();
                    final doc = await capture.captureFromCamera();
                    if (doc != null) _onNoticeCaptured(doc);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.photo_library,
                  label: 'Photo library',
                  onTap: () async {
                    final capture = DocumentCapture();
                    final doc = await capture.pickFromGallery();
                    if (doc != null) _onNoticeCaptured(doc);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoticePreview() {
    final notice = _controller.notice!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                notice.imageBytes,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Government Notice',
                  style: PrismTypography.publicSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notice.shouldWarnBlur)
                  Text(
                    'Photo unclear — may affect results',
                    style: PrismTypography.publicSans(
                      fontSize: 12,
                      color: AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() {
              _controller.clearNotice();
              _noticePreview = null;
              _noticePreviewLoading = false;
            }),
            color: AppColors.neutral,
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeContextHint() {
    if (_noticePreviewLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reading your notice…',
                style: PrismTypography.publicSans(
                  fontSize: 14,
                  color: AppColors.neutral,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final p = _noticePreview;
    if (p == null || !p.hasAnySignal) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          'Add photos of documents that match what your notice asks for.',
          style: PrismTypography.publicSans(
            fontSize: 14,
            color: AppColors.neutral,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.requestedCategories.isNotEmpty) ...[
            Text(
              'Your notice seems to ask for',
              style: PrismTypography.publicSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.neutral,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.requestedCategories.map((c) {
                final label = LabelFormatter.requirementLabel(c);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: PrismTypography.publicSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (p.deadline.isNotEmpty || p.hint.isNotEmpty)
              const SizedBox(height: 10),
          ],
          if (p.deadline.isNotEmpty)
            Text(
              'Deadline: ${p.deadline}',
              style: PrismTypography.publicSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (p.deadline.isNotEmpty && p.hint.isNotEmpty)
            const SizedBox(height: 6),
          if (p.hint.isNotEmpty)
            Text(
              p.hint,
              style: PrismTypography.publicSans(
                fontSize: 13,
                color: AppColors.neutral,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSupportingDocumentSlot(int index) {
    final doc = _controller.supportingDocuments[index];
    final slotNumber = index + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
        boxShadow: PrismShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: doc != null ? AppColors.success : AppColors.outline,
                  ),
                  color: doc != null ? AppColors.lightGreen : Colors.transparent,
                ),
                child: Center(
                  child: doc != null
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.success,
                        )
                      : Text(
                          '$slotNumber',
                          style: PrismTypography.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: doc != null ? AppColors.success : AppColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Document $slotNumber',
                  style: PrismTypography.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (doc != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(
                      () => _controller.clearSupportingDocument(index)),
                  color: AppColors.neutral,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (doc != null)
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      doc.imageBytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (doc.shouldWarnBlur)
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Photo unclear',
                        style: PrismTypography.publicSans(
                          fontSize: 14,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ready',
                        style: PrismTypography.publicSans(
                          fontSize: 14,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () async {
                      final capture = DocumentCapture();
                      final doc = await capture.captureFromCamera();
                      if (doc != null) _onDocumentCaptured(index, doc);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.photo_library,
                    label: 'Library',
                    onTap: () async {
                      final capture = DocumentCapture();
                      final doc = await capture.pickFromGallery();
                      if (doc != null) _onDocumentCaptured(index, doc);
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PrismTypography.publicSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
