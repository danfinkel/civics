import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/imaging/document_capture.dart';
import '../../core/models/track_b_result.dart';
import '../../shared/theme/app_theme.dart';
import 'track_b_controller.dart';
import 'widgets/document_slot.dart';
import 'widgets/requirement_row.dart';
import 'widgets/confidence_badge.dart';

class TrackBScreen extends StatefulWidget {
  const TrackBScreen({super.key});

  @override
  State<TrackBScreen> createState() => _TrackBScreenState();
}

class _TrackBScreenState extends State<TrackBScreen> {
  final TrackBController _controller = TrackBController();
  bool _isAnalyzing = false;
  TrackBResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDocumentCaptured(int slotIndex, CapturedDocument doc) async {
    setState(() {
      _controller.setDocument(slotIndex, doc);
    });

    // Show blur warning if needed
    if (doc.blurResult.isBlurry && mounted) {
      _showBlurWarning(doc);
    }
  }

  void _showBlurWarning(CapturedDocument doc) {
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
            const SizedBox(height: 8),
            Text(
              'Blur score: ${doc.blurResult.score.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.neutral,
              ),
            ),
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
              // Clear the blurry document
              setState(() {
                _controller.clearDocument(
                  _controller.slots.indexWhere(
                    (s) => s.document?.id == doc.id,
                  ),
                );
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
        title: const Text('School Enrollment Packet'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                // TODO: Implement share functionality
              },
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
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Step 1 of 2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Upload Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Document slots
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _controller.slots.length,
            itemBuilder: (context, index) {
              final slot = _controller.slots[index];
              return DocumentSlot(
                index: index,
                slot: slot,
                onDocumentCaptured: (doc) => _onDocumentCaptured(index, doc),
                onClear: () => setState(() => _controller.clearDocument(index)),
              );
            },
          ),
        ),

        // CTA Button
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
                : const Text('Check My Packet'),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    final result = _result!;

    return Column(
      children: [
        // Subtitle
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surfaceContainerLow,
          child: const Row(
            children: [
              Text(
                'Boston Public Schools Registration',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Requirements checklist
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Requirements
              ...result.requirements.map((req) => RequirementRow(
                    requirement: req,
                  )),

              // Duplicate category warning
              if (result.duplicateCategoryFlag) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lightAmber,
                    border: const Border(
                      left: BorderSide(
                        color: AppColors.warning,
                        width: 4,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          result.duplicateCategoryExplanation.isNotEmpty
                              ? result.duplicateCategoryExplanation
                              : 'Two leases count as one proof — you need a second document type from a different category',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action summary card
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
                      'What to bring to registration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      result.familySummary,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Overall confidence
              Row(
                children: [
                  const Text(
                    'Overall confidence: ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.neutral,
                    ),
                  ),
                  ConfidenceBadge(level: result.overallConfidence),
                ],
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
                  onPressed: () {
                    // TODO: Save summary
                  },
                  child: const Text('Save Summary'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
