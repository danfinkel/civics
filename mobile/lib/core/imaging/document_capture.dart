import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../shared/theme/prism_typography.dart';
import 'blur_detector.dart';
import 'image_processor.dart';

/// Represents a captured document with metadata
class CapturedDocument {
  final String id;
  final Uint8List imageBytes;
  final BlurResult blurResult;
  final DateTime capturedAt;
  final String? source; // 'camera' or 'gallery'

  /// User chose "Use anyway" after a blur warning; hide aggressive blur UX but keep score.
  final bool acceptedDespiteBlur;

  const CapturedDocument({
    required this.id,
    required this.imageBytes,
    required this.blurResult,
    required this.capturedAt,
    this.source,
    this.acceptedDespiteBlur = false,
  });

  bool get isClear => !blurResult.isBlurry || acceptedDespiteBlur;

  /// Show thumbnail treatment / retake nudge when the image is blurry and not overridden.
  bool get shouldWarnBlur => blurResult.isBlurry && !acceptedDespiteBlur;

  CapturedDocument copyWith({
    String? id,
    Uint8List? imageBytes,
    BlurResult? blurResult,
    DateTime? capturedAt,
    String? source,
    bool? acceptedDespiteBlur,
  }) {
    return CapturedDocument(
      id: id ?? this.id,
      imageBytes: imageBytes ?? this.imageBytes,
      blurResult: blurResult ?? this.blurResult,
      capturedAt: capturedAt ?? this.capturedAt,
      source: source ?? this.source,
      acceptedDespiteBlur: acceptedDespiteBlur ?? this.acceptedDespiteBlur,
    );
  }
}

/// Handles document capture from camera or gallery
class DocumentCapture {
  final ImagePicker _picker = ImagePicker();
  final BlurDetector _blurDetector = BlurDetector();
  final ImageProcessor _imageProcessor = ImageProcessor();

  /// Capture a document using the camera
  Future<CapturedDocument?> captureFromCamera() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );

    if (photo == null) return null;

    return _processCapturedFile(photo, 'camera');
  }

  /// Select a document from the gallery
  Future<CapturedDocument?> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );

    if (image == null) return null;

    return _processCapturedFile(image, 'gallery');
  }

  /// Process a captured file through blur detection and image processing
  Future<CapturedDocument> _processCapturedFile(
    XFile file,
    String source,
  ) async {
    final bytes = await file.readAsBytes();

    // Run blur detection on original
    final blurResult = _blurDetector.analyzeBytes(bytes);

    // Process image for storage/use
    final processedBytes = await _imageProcessor.processBytes(bytes);

    return CapturedDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageBytes: processedBytes,
      blurResult: blurResult,
      capturedAt: DateTime.now(),
      source: source,
    );
  }

  /// Re-analyze blur on an existing image (e.g., after retake)
  Future<BlurResult> reanalyzeBlur(Uint8List imageBytes) async {
    return _blurDetector.analyzeBytes(imageBytes);
  }
}

/// Widget for document capture with blur detection
class DocumentCaptureWidget extends StatefulWidget {
  final Function(CapturedDocument) onDocumentCaptured;
  final VoidCallback? onCancel;

  const DocumentCaptureWidget({
    super.key,
    required this.onDocumentCaptured,
    this.onCancel,
  });

  @override
  State<DocumentCaptureWidget> createState() => _DocumentCaptureWidgetState();
}

class _DocumentCaptureWidgetState extends State<DocumentCaptureWidget> {
  final DocumentCapture _capture = DocumentCapture();
  bool _isProcessing = false;

  Future<void> _captureFromCamera() async {
    setState(() => _isProcessing = true);
    try {
      final doc = await _capture.captureFromCamera();
      if (doc != null && mounted) {
        widget.onDocumentCaptured(doc);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _isProcessing = true);
    try {
      final doc = await _capture.pickFromGallery();
      if (doc != null && mounted) {
        widget.onDocumentCaptured(doc);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Add Document',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          if (_isProcessing)
            const CircularProgressIndicator()
          else
            Row(
              children: [
                Expanded(
                  child: _CaptureButton(
                    icon: Icons.camera_alt,
                    label: 'Take Photo',
                    onTap: _captureFromCamera,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CaptureButton(
                    icon: Icons.photo_library,
                    label: 'Choose from Library',
                    onTap: _pickFromGallery,
                  ),
                ),
              ],
            ),
          if (widget.onCancel != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CaptureButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFC3C6CF)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: const Color(0xFF002444)),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: PrismTypography.publicSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
