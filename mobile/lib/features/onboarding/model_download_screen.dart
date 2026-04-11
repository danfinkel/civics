import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/inference/model_manager.dart' as mgr;
import '../../shared/navigation/prism_page_routes.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/prism_typography.dart';
import '../track_b/track_b_screen.dart';

enum DownloadState {
  notStarted,
  downloading,
  ready,
  error,
}

const String _prefsKey = 'model_download_complete';

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback? onContinue;
  final VoidCallback? onCloudMode;

  const ModelDownloadScreen({
    super.key,
    this.onContinue,
    this.onCloudMode,
  });

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();

  /// True when the GGUF exists in app Documents and is full-sized (not prefs-only).
  static Future<bool> isModelDownloaded() async {
    final manager = mgr.ModelManager();
    try {
      final available = await manager.isModelAvailable();
      final prefs = await SharedPreferences.getInstance();
      final flagged = prefs.getBool(_prefsKey) ?? false;
      if (available) {
        return true;
      }
      if (flagged) {
        await prefs.remove(_prefsKey);
      }
      return false;
    } finally {
      manager.dispose();
    }
  }

  /// Mark model as downloaded
  static Future<void> markDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  DownloadState _state = DownloadState.notStarted;
  double _progress = 0.0;
  String? _errorMessage;
  mgr.ModelManager? _downloadManager;

  @override
  void dispose() {
    _downloadManager?.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    _downloadManager?.dispose();
    _downloadManager = mgr.ModelManager();

    setState(() {
      _state = DownloadState.downloading;
      _progress = 0.0;
      _errorMessage = null;
    });

    final result = await _downloadManager!.downloadModel(
      onProgress: (progress, _, __) {
        if (!mounted) return;
        setState(() => _progress = progress.clamp(0.0, 1.0));
      },
    );

    if (!mounted) return;

    if (result.success && result.modelPath != null) {
      await ModelDownloadScreen.markDownloaded();
      setState(() => _state = DownloadState.ready);
    } else {
      setState(() {
        _state = DownloadState.error;
        _errorMessage = result.errorMessage ??
            'Download failed. Use the same Wi‑Fi as your Mac, set MODEL_SERVER_URL '
            'to your Mac’s IP (not localhost), run scripts/serve_model.sh, then try again.';
      });
    }
  }

  void _continueToApp() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.pushReplacement(
        context,
        PrismPageRoutes.fadeReplace<void>(
          const TrackBScreen(),
          name: 'TrackB',
        ),
      );
    }
  }

  void _useCloudMode() {
    if (widget.onCloudMode != null) {
      widget.onCloudMode!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Set Up CivicLens',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              _buildContent(),
              const Spacer(),
              _buildBottomSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case DownloadState.notStarted:
        return _buildNotStartedContent();
      case DownloadState.downloading:
        return _buildDownloadingContent();
      case DownloadState.ready:
        return _buildReadyContent();
      case DownloadState.error:
        return _buildErrorContent();
    }
  }

  Widget _buildNotStartedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 64,
          color: AppColors.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'CivicLens uses AI to analyze your documents privately on your device.',
          style: PrismTypography.publicSans(
            fontSize: 16,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.lightAmber,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi,
                color: Color(0xFF92400E),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This requires a one-time download of ~2.9GB from the URL in '
                  'lib/core/config/model_config.dart (set by scripts/dev_deploy.sh). '
                  'On a physical iPhone, that URL must use your Mac\'s LAN IP while '
                  'scripts/serve_model.sh is running — not localhost. Wi‑Fi recommended.',
                  style: PrismTypography.publicSans(
                    fontSize: 14,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingContent() {
    final percent = (_progress * 100).round();
    final totalMb = (mgr.ModelManager.modelSizeBytes / (1024 * 1024)).round();
    final mbDownloaded = (_progress * totalMb).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: _progress,
              strokeWidth: 8,
              backgroundColor: AppColors.surfaceContainer,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'Downloading... $percent%',
            style: PrismTypography.spaceGrotesk(fontSize: 20),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '$mbDownloaded MB of $totalMb MB',
            style: PrismTypography.publicSans(
              fontSize: 14,
              color: AppColors.neutral,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'This may take a few minutes. Please keep the app open.',
            textAlign: TextAlign.center,
            style: PrismTypography.publicSans(
              fontSize: 14,
              color: AppColors.neutral,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Center(
          child: Icon(
            Icons.check_circle,
            size: 80,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'Ready',
            style: PrismTypography.spaceGrotesk(fontSize: 24),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 20,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                'Your documents stay on your device',
                style: PrismTypography.publicSans(
                  fontSize: 16,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Center(
          child: Icon(
            Icons.error_outline,
            size: 80,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            _errorMessage ?? 'Download failed',
            textAlign: TextAlign.center,
            style: PrismTypography.publicSans(
              fontSize: 16,
              color: AppColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSection() {
    switch (_state) {
      case DownloadState.notStarted:
        return Column(
          children: [
            ElevatedButton(
              onPressed: _startDownload,
              child: const Text('Download Now'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _useCloudMode,
              child: const Text('Use Cloud Mode Instead'),
            ),
          ],
        );
      case DownloadState.downloading:
        return const SizedBox.shrink(); // No buttons while downloading
      case DownloadState.ready:
        return ElevatedButton(
          onPressed: _continueToApp,
          child: const Text('Continue'),
        );
      case DownloadState.error:
        return Column(
          children: [
            ElevatedButton(
              onPressed: _startDownload,
              child: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _useCloudMode,
              child: const Text('Use Cloud Mode Instead'),
            ),
          ],
        );
    }
  }
}
