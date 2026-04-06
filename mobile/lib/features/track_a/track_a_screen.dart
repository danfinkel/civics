import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/imaging/document_capture.dart';
import '../../core/models/track_a_result.dart';
import '../../shared/theme/app_theme.dart';
import 'track_a_controller.dart';
import '../track_b/widgets/document_slot.dart';
import '../track_b/widgets/confidence_badge.dart';

class TrackAScreen extends StatefulWidget {
  const TrackAScreen({super.key});

  @override
  State<TrackAScreen> createState() => _TrackAScreenState();
}

class _TrackAScreenState extends State<TrackAScreen> {
  final TrackAController _controller = TrackAController();
  bool _isAnalyzing = false;
  TrackAResult? _result;

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
            onPressed: () => Navigator.pop(context),
            child: const Text('Use Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (isNotice) {
                  _controller.clearNotice();
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
      body: _result != null ? _buildResultsView() : _buildUploadView(),
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
                  style: const TextStyle(
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
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
                const Text(
                  'Your Documents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Analyzing...'),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: const Color(0xFFC3C6CF).withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.description,
            size: 48,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Upload Your Government Notice',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is the letter or notice you received requesting documents',
            textAlign: TextAlign.center,
            style: TextStyle(
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
                  label: 'Take Photo',
                  onTap: () async {
                    final capture = DocumentCapture();
                    final doc = await capture.captureFromCamera();
                    if (doc != null) _onNoticeCaptured(doc);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ActionButton(
                  icon: Icons.photo_library,
                  label: 'Choose from Library',
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
                const Text(
                  'Government Notice',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (notice.blurResult.isBlurry)
                  Text(
                    'Photo unclear — may affect results',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _controller.clearNotice()),
            color: AppColors.neutral,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: const Color(0xFFC3C6CF).withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(4),
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
                          style: TextStyle(
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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
                if (doc.blurResult.isBlurry)
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
                        style: TextStyle(
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
                      const Text(
                        'Ready',
                        style: TextStyle(
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

  Widget _buildResultsView() {
    final result = _result!;

    return Column(
      children: [
        // Deadline banner
        if (!result.noticeSummary.isUncertain) ...[
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.lightAmber,
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: Color(0xFF92400E),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Response Deadline',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      Text(
                        result.noticeSummary.deadline,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Uncertainty warning
        if (result.noticeSummary.isUncertain) ...[
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.lightRed,
            child: const Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Notice unclear — please contact DTA at (617) 348-8400',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Proof pack
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Your Proof Pack',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...result.proofPack.map((item) => _buildProofPackItem(item)),
              const SizedBox(height: 24),
              // Action summary
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What to do next',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      result.actionSummary,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom actions
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _startOver,
                  child: const Text('Start Over'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Save Summary'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProofPackItem(ProofPackItem item) {
    final (statusColor, statusBg, statusText) = _getAssessmentStyles(item.assessment);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: const Color(0xFFC3C6CF).withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.category,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.isMissing ? 'MISSING' : item.matchedDocument,
            style: TextStyle(
              fontSize: 14,
              color: item.isMissing ? AppColors.error : AppColors.neutral,
            ),
          ),
          if (item.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.evidence,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.neutral,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (item.caveats.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.lightAmber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.caveats,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ConfidenceBadge(level: item.confidence),
        ],
      ),
    );
  }

  (Color, Color, String) _getAssessmentStyles(AssessmentLabel assessment) {
    switch (assessment) {
      case AssessmentLabel.likelySatisfies:
        return (AppColors.success, AppColors.lightGreen, 'Likely satisfies');
      case AssessmentLabel.likelyDoesNotSatisfy:
        return (
          const Color(0xFF92400E),
          AppColors.lightAmber,
          'Does not satisfy'
        );
      case AssessmentLabel.missing:
        return (AppColors.error, AppColors.lightRed, 'Missing');
      case AssessmentLabel.uncertain:
        return (AppColors.neutral, AppColors.surfaceContainerLow, 'Uncertain');
    }
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
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
