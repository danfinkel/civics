import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/inference/gemma_client.dart';
import '../../shared/theme/app_theme.dart';
import '../track_b/track_b_screen.dart';

enum DownloadState {
  notStarted,
  downloading,
  ready,
  error,
}

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
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  DownloadState _state = DownloadState.notStarted;
  double _progress = 0.0;
  String? _errorMessage;

  static const String _prefsKey = 'model_download_complete';

  /// Check if model has been downloaded
  static Future<bool> isModelDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Mark model as downloaded
  static Future<void> markDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = DownloadState.downloading;
      _progress = 0.0;
    });

    final client = GemmaClient();

    await client.initialize(
      modelPath: '/path/to/gemma4-e2b', // TODO: Agent 2 to provide actual path
      onProgress: (progress) {
        setState(() => _progress = progress);
      },
      onStateChange: (state) {
        switch (state) {
          case ModelDownloadState.ready:
            setState(() => _state = DownloadState.ready);
            markDownloaded();
            break;
          case ModelDownloadState.error:
            setState(() {
              _state = DownloadState.error;
              _errorMessage = 'Download failed. Please try again.';
            });
            break;
          default:
            break;
        }
      },
    );
  }

  void _continueToApp() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TrackBScreen()),
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
        const Text(
          'CivicLens uses AI to analyze your documents privately on your device.',
          style: TextStyle(
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
                  'This requires a one-time download of 2.5GB. Connect to WiFi recommended.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF92400E),
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
    final mbDownloaded = (_progress * 2.5 * 1024).round();
    final totalMb = (2.5 * 1024).round();

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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '$mbDownloaded MB of $totalMb MB',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.neutral,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'This may take a few minutes. Please keep the app open.',
            textAlign: TextAlign.center,
            style: TextStyle(
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
        const Center(
          child: Text(
            'Ready',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: AppColors.success,
              ),
              SizedBox(width: 8),
              Text(
                'Your documents stay on your device',
                style: TextStyle(
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
            style: const TextStyle(
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
