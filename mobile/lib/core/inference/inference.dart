/// Inference module for CivicLens
///
/// This module provides document analysis using Gemma 4.
/// Pipeline: Image → OCR → llama.cpp → JSON (all on-device)
///
/// Exports:
/// - [LlamaClient] - On-device LLM inference (llama.cpp)
/// - [OcrService] - On-device OCR (ML Kit)
/// - [InferenceService] - High-level service with OCR+LLM pipeline
/// - [PromptTemplates] - Prompt templates for SNAP and BPS tracks
/// - [ResponseParser] - JSON parsing with retry wrapper
/// - [ModelManager] - Model download and management
/// - [PerformanceMetrics] - Performance tracking
/// - Result models from [track_a_result.dart] and [track_b_result.dart]

export 'llama_client.dart';
export 'ocr_service.dart';
export 'gemma_client.dart';
export 'inference_service.dart';
export 'prompt_templates.dart';
export 'response_parser.dart';
export 'model_manager.dart';
export 'cloud_fallback_client.dart';
export 'performance_metrics.dart';
export '../models/track_a_result.dart';
export '../models/track_b_result.dart';
