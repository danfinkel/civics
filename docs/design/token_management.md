# Token Management Design

> Last updated: May 2026  
> Covers the on-device (llama.cpp / Gemma 2B GGUF) inference path only.  
> The Ollama/Gemma 4 eval path has no meaningful token constraints.

---

## Overview

On-device inference runs a 2-bit quantized Gemma 2B GGUF model via `llama.cpp`. The
model has a fixed context window of **4096 tokens**. Every character of prompt text and
every token of model output must fit inside that window simultaneously. To prevent
truncation, hangs, and silent failures we manage budget across three nested layers:

```
┌─────────────────────────────────────────────────────────────────┐
│  Model context window:  4096 tokens  (~14,300 chars total)       │
│                                                                   │
│  ┌───────────────────────────────────┐  ┌─────────────────────┐  │
│  │  Prompt budget                    │  │  Output budget       │  │
│  │  _kMaxLocalLlmPromptChars = 8000  │  │  maxTokens = 2048    │  │
│  │  chars (~2,300 tokens)            │  │  (~7,000 chars)      │  │
│  └───────────────────────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

In practice, Track A prompts are ~1,800–2,500 tokens and Track A responses are
~300–600 tokens, leaving comfortable headroom on both sides.

---

## Layer 1 — Image Resolution (`ImageProcessor`)

**File:** `mobile/lib/core/imaging/image_processor.dart`

Before OCR runs, every image is downscaled so its longest edge is at most
`_maxDimension = 2048 px`. This serves two purposes:

1. **OCR quality vs. speed:** ML Kit OCR accuracy does not improve meaningfully above
   ~2048 px but processing time grows. Full-resolution HEIC captures from iPhone 15
   cameras can be 4284 × 5712 px — roughly 4× more pixels than needed.
2. **OCR text volume control:** Higher resolution images produce significantly more OCR
   characters (whitespace, artifacts, repeated text). Downscaling to 2048 px brings OCR
   output into the range that fits within the prompt budget.

> **Note:** The eval server's `/infer_track_a` endpoint applies the same
> `ImageProcessor.processBytes()` step before running OCR, so eval and production
> results are directly comparable.

---

## Layer 2 — OCR Text Budget (`_formatOcrResultsTrackA`)

**File:** `mobile/lib/core/inference/inference_service.dart`

Raw ML Kit OCR output can be thousands of characters per document. Before the LLM
sees any text, `_formatOcrResultsTrackA` enforces per-document and total caps:

| Constant | Value | Purpose |
|---|---|---|
| `noticeMax` | 3,500 chars | Maximum OCR text from the government notice |
| `supportingMax` | 1,100 chars | Maximum OCR text per supporting document |
| `maxTotalChars` | 5,800 chars | Hard cap on the entire OCR block across all documents |

When a document's OCR text exceeds its cap, the tail is dropped and a marker
`[... text truncated for model limits ...]` is appended. This marker is intentional —
it signals to the model that information was cut, so the model should respond with
`uncertain` rather than hallucinating.

**Why these numbers:** A typical NYC benefits notice has ~2,000–3,000 OCR chars at
2048 px. The 3,500 char `noticeMax` covers the 99th-percentile notice with margin.
The 5,800 char total budget comfortably fits notice + two supporting documents while
staying well under the 8,000 char prompt cap.

---

## Layer 3 — Prompt Character Cap (`_clampPrompt`)

**File:** `mobile/lib/core/inference/inference_service.dart`

```dart
const int _kMaxLocalLlmPromptChars = 8000;
```

After the full prompt is assembled (system instructions + OCR block + output schema),
`_clampPrompt` checks the total character count. If it exceeds 8,000 chars:

1. It first tries to preserve a meaningful tail (closing schema instructions) and truncate
   the middle of the OCR section.
2. If that still doesn't fit, it hard-truncates at the limit with a `[Truncated]` suffix.

At ~3.5 chars/token this cap is roughly 2,285 tokens — leaving ~1,800 tokens of context
space for the 2,048-token output budget, with ~8 tokens of slack. In practice the prompt
never reaches 8,000 chars because the OCR budget (Layer 2) is the binding constraint.

---

## Layer 4 — Output Token Cap (`maxTokens`)

**File:** `mobile/lib/core/inference/llama_client.dart` (enforced in generation loop)

```dart
maxTokens: 2048   // Track A and Track B main inference
maxTokens: 380    // Track B preview / lightweight calls
```

`maxTokens` is the iteration limit on the token generation loop. The model will stop
at the earlier of:

- **Natural EOS:** The model emits an end-of-sequence token (normal, clean completion).
- **`maxTokens` limit:** The loop counter hits the cap (safety net).
- **Context exhaustion:** `nCtx − prompt_tokens` remaining slots are filled.

For a complete Track A response (JSON with `notice_summary`, `proof_pack` rows, and
`action_summary`), empirical output size is **300–600 tokens**. The 2,048 cap is ~4×
the realistic maximum and exists primarily to prevent infinite generation if the model
enters a confused repetition loop on a malformed prompt.

---

## Data Flow Summary

```
HEIC/JPEG from camera
        │
        ▼
ImageProcessor.processBytes()
  max 2048 px longest edge
        │
        ▼
ML Kit OCR  →  raw text (can be 3,000–8,000+ chars at full res)
        │
        ▼
_formatOcrResultsTrackA()
  noticeMax=3500, supportingMax=1100, maxTotalChars=5800
        │
        ▼
Prompt assembly
  instructions + OCR block + output schema
        │
        ▼
_clampPrompt()
  hard cap at 8,000 chars
        │
        ▼
llama.cpp  (nCtx=4096 tokens)
  maxTokens=2048
        │
        ▼
JSON response → ResponseParser → TrackAResult
```

---

## Failure Modes and Mitigations

| Failure | Symptom | Mitigation |
|---|---|---|
| Notice OCR exceeds `noticeMax` | Deadline or consequence truncated from LLM input; model outputs `uncertain` or echoes truncation marker | Increase `noticeMax`; improve image resolution; use multi-pass OCR on key regions |
| Prompt exceeds `_kMaxLocalLlmPromptChars` | Middle of OCR block silently removed | Increase cap (bounded by `nCtx`); trim low-value prompt boilerplate |
| LLM output exceeds `maxTokens` | JSON cut mid-field; parse failure | Cap is already 4× realistic max; if hit, indicates model repetition loop — increase or add repetition penalty |
| Context window exhausted | llama.cpp exception or silent truncation | Unlikely with current caps; detectable by tracking `prompt_tokens + response_tokens < 4096` |

---

## Current Constants (quick reference)

| Constant | Value | Location |
|---|---|---|
| `_maxDimension` | 2048 px | `image_processor.dart` |
| `noticeMax` | 3,500 chars | `inference_service.dart` |
| `supportingMax` | 1,100 chars | `inference_service.dart` |
| `maxTotalChars` | 5,800 chars | `inference_service.dart` |
| `_kMaxLocalLlmPromptChars` | 8,000 chars | `inference_service.dart` |
| `nCtx` | 4,096 tokens | `llama_client.dart` |
| `maxTokens` (Track A/B) | 2,048 tokens | `inference_service.dart` |
| `maxTokens` (preview) | 380 tokens | `inference_service.dart` |
