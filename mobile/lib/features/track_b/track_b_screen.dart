import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/imaging/document_capture.dart';
import '../../core/models/track_b_result.dart';
import '../../shared/navigation/prism_page_routes.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/prism_tokens.dart';
import '../../shared/widgets/prism/prism_shimmer.dart';
import 'track_b_controller.dart' hide DocumentSlot;
import 'widgets/document_slot.dart';
import 'widgets/requirement_row.dart';
import 'widgets/packet_status_hero.dart';
import 'widgets/packet_status_stat_cards.dart';
import 'model_transparency_screen.dart';

class TrackBScreen extends StatefulWidget {
  const TrackBScreen({super.key});

  @override
  State<TrackBScreen> createState() => _TrackBScreenState();
}

class _TrackBScreenState extends State<TrackBScreen> {
  final TrackBController _controller = TrackBController();

  @override
  void initState() {
    super.initState();
    // Initialize service on startup
    _initializeService();
    // Set up progress callback
    _controller.onProgress = (_) => setState(() {});
  }

  Future<void> _initializeService() async {
    await _controller.initializeService();
  }

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
    await _controller.analyzeDocuments();
    setState(() {}); // Refresh UI based on controller state

    // Show error dialog if failed
    if (_controller.state == TrackBViewState.error && mounted) {
      _showErrorDialog(_controller.errorMessage ?? 'Analysis failed');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analysis Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.retryAnalysis();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _startOver() {
    setState(() {
      _controller.clearAll();
    });
  }

  Future<void> _sharePacketSummary(TrackBResult result) async {
    final text = result.toShareableText();
    await Share.share(
      text,
      subject: 'BPS registration packet — CivicLens',
    );
  }

  String _nextStepsLead(String summary) {
    const max = 220;
    final t = summary.trim();
    if (t.isEmpty) {
      return 'Bring the documents from your checklist when you visit registration. '
          'This review ran entirely on your device.';
    }
    if (t.length <= max) return t;
    return '${t.substring(0, max).trim()}… See “What to bring” below for the full list.';
  }

  Future<void> _copySummaryToClipboard(TrackBResult result) async {
    await Clipboard.setData(ClipboardData(text: result.toShareableText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Summary copied — paste into Notes, Mail, or Messages'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResults = _controller.state == TrackBViewState.success;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        // Leave horizontal room for trailing actions (theme uses centerTitle: true).
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isResults ? 'Packet Status' : 'School Enrollment Packet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How this works',
            onPressed: () {
              Navigator.push<void>(
                context,
                PrismPageRoutes.push<void>(
                  const ModelTransparencyScreen(),
                  name: 'ModelTransparency',
                ),
              );
            },
          ),
          if (isResults)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share summary',
              onPressed: () => _sharePacketSummary(_controller.result!),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_controller.state) {
      case TrackBViewState.idle:
      case TrackBViewState.error:
        return _buildUploadView();
      case TrackBViewState.loading:
        return _buildLoadingView();
      case TrackBViewState.success:
        return _buildResultsView();
    }
  }

  Widget _buildUploadView() {
    return Column(
      children: [
        // Progress indicator (Prism elevated card)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: prismCardDecoration(
              context,
              color: AppColors.surfaceContainerLow,
              strong: true,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
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
                    const Expanded(
                      child: Text(
                        'Upload Documents',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final label = snap.hasData
                        ? 'App build ${snap.data!.version} (${snap.data!.buildNumber})'
                        : 'App build …';
                    return Text(
                      '$label · Info button (top right) for details',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.neutral,
                            fontSize: 12,
                          ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Optional grade slot
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: prismCardDecoration(context),
              child: SwitchListTile(
              title: const Text('Grade placement document'),
              subtitle: Text(
                'Optional — report card or transcript if applicable',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.neutral,
                    ),
              ),
              value: _controller.includeGradeIndicator,
              onChanged: (v) {
                setState(() => _controller.setIncludeGradeIndicator(v));
              },
            ),
            ),
          ),
        ),

        // Document slots
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _controller.visibleSlotIndices.length,
            itemBuilder: (context, listIndex) {
              final slotIndex = _controller.visibleSlotIndices[listIndex];
              final slot = _controller.slots[slotIndex];
              return DocumentSlot(
                index: slotIndex,
                slot: slot,
                onDocumentCaptured: (doc) =>
                    _onDocumentCaptured(slotIndex, doc),
                onClear: () =>
                    setState(() => _controller.clearDocument(slotIndex)),
              );
            },
          ),
        ),

        // CTA Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _controller.canAnalyze
                ? _analyzeDocuments
                : null,
            child: const Text('Check My Packet'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    final progress = _controller.progress;
    final percent = (progress.percent * 100).round();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PrismShimmer(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: prismCardDecoration(context, strong: true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceContainer
                              .withValues(alpha: 0.95),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: progress.percent > 0 ? progress.percent : null,
                          strokeWidth: 8,
                          backgroundColor: AppColors.surfaceContainer,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              Text(
                progress.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$percent% complete',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.neutral,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'On-device analysis is usually under a minute on recent iPhones.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.neutral.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  _controller.switchToCloudAndRetry();
                },
                child: const Text('Taking too long? Switch to Cloud Mode'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    final result = _controller.result!;
    final theme = Theme.of(context).textTheme;
    final total = result.requirements.length;
    final sat = result.satisfiedCount;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              PacketStatusHero(result: result),
              PacketStatusStatCards(
                result: result,
                completedAt: _controller.analysisCompletedAt,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Documentation checklist',
                        style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Text(
                      '$sat OF $total SATISFIED',
                      style: theme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              ...result.requirements.map(
                (req) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RequirementRow(requirement: req),
                ),
              ),
              if (result.duplicateCategoryFlag) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.lightAmber,
                      borderRadius: BorderRadius.circular(PrismRadii.md),
                      boxShadow: PrismShadows.card(context),
                      border: const Border(
                        left: BorderSide(
                          color: AppColors.warning,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: AppColors.warning,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            result.duplicateCategoryExplanation.isNotEmpty
                                ? result.duplicateCategoryExplanation
                                : 'Two leases count as one proof — you need a second document type from a different category',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next steps',
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _nextStepsLead(result.familySummary),
                      style: theme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _PrismSummaryCard(
                  title: 'What to bring to registration',
                  body: result.familySummary,
                  theme: theme,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'CivicLens reviews documents on your phone. Official decisions '
                  'are made by BPS staff.',
                  textAlign: TextAlign.center,
                  style: theme.bodySmall?.copyWith(
                    color: AppColors.neutral,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Clear documents and run a new packet review',
                  child: OutlinedButton(
                    onPressed: _startOver,
                    child: const Text(
                      'Start Over',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Share checklist and summary',
                  child: OutlinedButton.icon(
                    onPressed: () => _sharePacketSummary(result),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text(
                      'Share',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Copy summary to clipboard',
                  child: ElevatedButton(
                    onPressed: () => _copySummaryToClipboard(result),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Save Summary',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Prism glass-style summary (`prism_migration_spec.md`).
class _PrismSummaryCard extends StatelessWidget {
  final String title;
  final String body;
  final TextTheme theme;

  const _PrismSummaryCard({
    required this.title,
    required this.body,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: prismCardDecoration(
        context,
        color: AppColors.lightBlue,
        strong: true,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PrismRadii.md),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(body, style: theme.bodyLarge),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
