import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/prism_tokens.dart';

/// Reliability / transparency (`prism_migration_spec.md` + design spec).
class ModelTransparencyScreen extends StatelessWidget {
  const ModelTransparencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final h2 = Theme.of(context).textTheme.headlineMedium;
    final body = Theme.of(context).textTheme.bodyLarge;

    Widget section(String title, String text) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: prismCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: h2),
            const SizedBox(height: 10),
            Text(text, style: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('How this works'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            'On your device',
            'CivicLens reads text from your photos on this phone (OCR), then runs a small language model to match what you uploaded to BPS registration requirements. By default, nothing is sent to the cloud unless you choose cloud mode.',
          ),
          section(
            'Confidence labels',
            'Green, amber, and red badges describe how confident the model is—not a legal guarantee. School districts can ask for different or additional documents. Always confirm requirements with Boston Public Schools.',
          ),
          section(
            'Photo quality',
            'Blur, glare, and shadows make text harder to read. If you see a warning, retaking the photo usually helps accuracy.',
          ),
          section(
            'Your documents',
            'Images you capture stay on this device unless you explicitly use a cloud option. You can delete them anytime by clearing slots or removing the app.',
          ),
          const Divider(height: 32),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final p = snapshot.data!;
              return Text(
                'App version ${p.version} (${p.buildNumber})',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.neutral,
                    ),
              );
            },
          ),
        ],
      ),
    );
  }
}
