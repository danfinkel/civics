/// True when built with `--dart-define=EVAL_MODE=true` (e.g. `./scripts/dev_deploy.sh --eval`).
/// Used to show model evidence and confidence on resident-facing screens for eval/debug only.
const bool kEvalMode = bool.fromEnvironment('EVAL_MODE', defaultValue: false);

/// Log OCR sizes, prompt length (before/after clamp), raw LLM text snippet, parse outcome,
/// and **Track B**: per-requirement status/confidence/matched/evidence/notes, slot-alignment
/// strategy (positional vs bucket pool), and `why_not_satisfied` hints when status ≠ satisfied.
/// Does not change behavior.
///
/// ```sh
/// flutter run --dart-define=INFERENCE_DIAGNOSTICS=true
/// ```
const bool kInferenceDiagnostics = bool.fromEnvironment(
  'INFERENCE_DIAGNOSTICS',
  defaultValue: false,
);
