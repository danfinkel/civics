/// Inference module for CivicLens
///
/// This module provides on-device document analysis using Gemma 4 E2B.
/// All inference runs locally - documents never leave the device.
///
/// Exports:
/// - [GemmaClient] - Low-level MediaPipe inference client
/// - [InferenceService] - High-level service for Track A/B analysis
/// - [PromptTemplates] - Prompt templates for SNAP and BPS tracks
/// - [ResponseParser] - JSON parsing with retry wrapper
/// - Result models from [track_a_result.dart] and [track_b_result.dart]

export 'gemma_client.dart';
export 'inference_service.dart';
export 'prompt_templates.dart';
export 'response_parser.dart';
export '../models/track_a_result.dart';
export '../models/track_b_result.dart';
