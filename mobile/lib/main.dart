import 'dart:async';
import 'package:flutter/material.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/model_download_screen.dart';
import 'features/splash/civic_lens_splash_screen.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    ErrorWidget.builder = (details) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ERROR:\n${details.exception}\n\n${details.stack}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    };

    runApp(const CivicLensApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class CivicLensApp extends StatelessWidget {
  const CivicLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CivicLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppEntryPoint(),
    );
  }
}

class _BootstrapData {
  final bool modelDownloaded;

  const _BootstrapData(this.modelDownloaded);
}

/// Splash + model check; minimum splash dwell so the brand isn’t a flash frame.
class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  static const _minSplash = Duration(milliseconds: 3000);

  late final Future<_BootstrapData> _bootstrap = _runBootstrap();

  static Future<_BootstrapData> _runBootstrap() async {
    final sw = Stopwatch()..start();
    final downloaded = await ModelDownloadScreen.isModelDownloaded();
    final remaining = _minSplash - sw.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    return _BootstrapData(downloaded);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const CivicLensSplashScreen();
        }
        if (snapshot.data!.modelDownloaded) {
          return const HomeScreen();
        }
        return const ModelDownloadScreen();
      },
    );
  }
}
