import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/imaging/document_capture.dart';
import '../../../shared/theme/app_theme.dart';

class DocumentSlot extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isFilled = slot.isFilled;
    final doc = slot.document;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              // Number indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isFilled ? AppColors.success : AppColors.outline,
                  ),
                  color: isFilled ? AppColors.lightGreen : Colors.transparent,
                ),
                child: Center(
                  child: isFilled
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.success,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isFilled ? AppColors.success : AppColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title and required label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slot.required ? 'Required' : 'Optional',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: slot.required ? AppColors.error : AppColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              // Clear button if filled
              if (isFilled)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClear,
                  color: AppColors.neutral,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Document preview or action buttons
          if (isFilled && doc != null)
            _buildDocumentPreview(doc)
          else
            _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildDocumentPreview(CapturedDocument doc) {
    final hasBlurWarning = doc.blurResult.isBlurry;

    return Row(
      children: [
        // Thumbnail
        Container(
          width: 64,
          height: 64,
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
        // Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBlurWarning) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Photo unclear — retake?',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  doc.blurResult.guidance,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutral,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Document captured',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready for analysis',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutral,
                  ),
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

  Future<void> _showCaptureOptions(BuildContext context, {required bool useCamera}) async {
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
    }

    if (doc != null) {
      onDocumentCaptured(doc);
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
          borderRadius: BorderRadius.circular(4),
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
