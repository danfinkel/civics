/// Inference module for CivicLens
///
/// This module provides document analysis using Gemma 4.
/// Pipeline: Image → OCR → llama.cpp → JSON (all on-device)

export 'llama_client.dart';
export 'ocr_service.dart';
export 'inference_service.dart';
export 'response_parser.dart';
export 'model_manager.dart';
export 'performance_metrics.dart';
export '../models/track_a_notice_preview.dart';
export '../models/track_a_result.dart';
export '../models/track_b_result.dart';
