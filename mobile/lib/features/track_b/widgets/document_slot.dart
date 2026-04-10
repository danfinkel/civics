import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../../core/imaging/document_capture.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/prism_tokens.dart';
import '../../../shared/widgets/prism/prism_slot_step.dart';

class DocumentSlot extends StatefulWidget {
  final int index;
  final dynamic slot; // DocumentSlot from controller
  final Function(CapturedDocument) onDocumentCaptured;
  final VoidCallback onClear;

  const DocumentSlot({
    super.key,
    required this.index,
    required this.slot,
    required this.onDocumentCaptured,
    required this.onClear,
  });

  @override
  State<DocumentSlot> createState() => _DocumentSlotState();
}

class _DocumentSlotState extends State<DocumentSlot> {
  bool _capturing = false;

  dynamic get slot => widget.slot;

  @override
  Widget build(BuildContext context) {
    final isFilled = slot.isFilled;
    final doc = slot.document;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: prismCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PrismSlotStep(
                stepNumber: widget.index + 1,
                complete: isFilled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slot.required ? 'Required' : 'Optional',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: slot.required
                                ? AppColors.error
                                : AppColors.neutral,
                          ),
                    ),
                  ],
                ),
              ),
              if (isFilled)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClear,
                  color: AppColors.neutral,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_capturing)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: isFilled && doc != null
                ? KeyedSubtree(
                    key: ValueKey(doc.id),
                    child: _buildDocumentPreview(context, doc),
                  )
                : KeyedSubtree(
                    key: const ValueKey('actions'),
                    child: _buildActionButtons(context),
                  ),
          ),
        ],
      ),
    );
  }

  /// Design spec: 48×48 thumbnail, check overlay when verified; blur + retake when unclear.
  Widget _buildDocumentPreview(BuildContext context, CapturedDocument doc) {
    final hasBlurWarning = doc.blurResult.isBlurry;
    const thumb = 48.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: thumb,
          height: thumb,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PrismRadii.sm),
                child: SizedBox(
                  width: thumb,
                  height: thumb,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasBlurWarning
                          ? ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Image.memory(
                                doc.imageBytes,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.memory(
                              doc.imageBytes,
                              fit: BoxFit.cover,
                            ),
                      if (!hasBlurWarning)
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.38),
                                    Colors.white.withValues(alpha: 0.06),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!hasBlurWarning)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.lightGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBlurWarning) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Photo unclear — retake?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  doc.blurResult.guidance,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Retake'),
                  ),
                ),
              ] else ...[
                Text(
                  'Document Verified',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready for analysis',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.camera_alt,
            label: 'Camera',
            onTap: () => _showCaptureOptions(context, useCamera: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.photo_library,
            label: 'Library',
            onTap: () => _showCaptureOptions(context, useCamera: false),
          ),
        ),
      ],
    );
  }

  Future<void> _showCaptureOptions(
    BuildContext context, {
    required bool useCamera,
  }) async {
    setState(() => _capturing = true);
    final capture = DocumentCapture();
    CapturedDocument? doc;

    try {
      if (useCamera) {
        doc = await capture.captureFromCamera();
      } else {
        doc = await capture.pickFromGallery();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }

    if (doc != null) {
      widget.onDocumentCaptured(doc);
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(PrismRadii.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
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
