"""
Prompt shaping that mirrors the **on-device eval** HTTP path (`mobile/lib/eval/eval_server.dart`
→ `InferenceService.inferRaw` / `inferRawWithNoticePreview`).

The notebook’s default Ollama pipeline sends a **vision** request (pixels in `images[]`).
Production on-device eval runs **text-only** Gemma chat: OCR text is appended, then the
prompt is clamped (`_clampPromptForLocalLlm`), and generation stops at `maxTokens`
(`llama_client.dart`).

OCR here uses **Tesseract** (optional); ML Kit on phones will differ — use this for
**structural** parity (caps, markers, output token limit), not bit-identical OCR.
"""

from __future__ import annotations

from pathlib import Path

# InferenceService — keep in sync with mobile/lib/core/inference/inference_service.dart
MAX_LOCAL_LLM_PROMPT_CHARS = 5600
# _formatOcrResultsTrackA (first document = notice)
TRACK_A_NOTICE_OCR_CAP = 2000

DEFAULT_DEVICE_OUTPUT_MAX_TOKENS = 2048


def clamp_prompt_for_local_llm(
    prompt: str, max_chars: int = MAX_LOCAL_LLM_PROMPT_CHARS
) -> str:
    """Mirror `_clampPromptForLocalLlm` (inference_service.dart)."""
    if len(prompt) <= max_chars:
        return prompt

    end_turn = "<end_of_turn>"
    end_idx = prompt.rfind(end_turn)
    if end_idx < 0:
        return f"{prompt[: max_chars - 40]}\n\n[Truncated]"

    tail = prompt[end_idx:]
    head_budget = max_chars - len(tail) - 60
    if head_budget < 200:
        return f"{prompt[: max_chars - 40]}\n\n[Truncated]"

    head = prompt[:end_idx]
    if len(head) > head_budget:
        head = f"{head[:head_budget]}\n\n[Body truncated for on-device limits.]"
    return f"{head}{tail}"


def wrap_gemma_chat_template(user_content: str) -> str:
    """Mirror `inferRaw` turn wrapping when the prompt has no `<start_of_turn>`."""
    t = user_content.strip()
    if "<start_of_turn>" in t:
        return t
    return (
        f"<start_of_turn>user\n{t}\n<end_of_turn>\n<start_of_turn>model\n"
    )


def append_extracted_ocr_block(prompt: str, ocr_text: str) -> str:
    """Mirror `inferRaw` OCR append before clamp (plain string, no per-field cap)."""
    ocr_text = (ocr_text or "").strip()
    if not ocr_text:
        return prompt.strip()
    return f"{prompt.strip()}\n\n--- Extracted document text (OCR) ---\n{ocr_text}"


def format_track_a_notice_ocr_section(ocr_text: str, cap: int = TRACK_A_NOTICE_OCR_CAP) -> str:
    """
    First-document branch of `_formatOcrResultsTrackA` (notice cap + truncation marker).

    Use this to reproduce the literal ``[... text truncated for model limits ...]`` line
    that appears when long notice OCR hits the on-device per-section budget (e.g. preview
    or multi-pass flows that run through the Track A formatter).
    """
    body = ocr_text or ""
    if len(body) > cap:
        body = f"{body[:cap]}\n[... text truncated for model limits ...]"
    return f"--- Government notice ---\n{body}\n\n"


def build_device_style_user_prompt(
    extraction_prompt: str,
    ocr_text: str,
    *,
    ocr_mode: str = "infer_raw",
) -> str:
    """
    Build pre-turn-markers user content.

    ocr_mode:
      - ``infer_raw`` — matches eval ``/infer`` with ``notice_preview_first=false``:
        full OCR string, no per-section cap (only the global clamp may cut it).
      - ``track_a_notice_cap`` — OCR run through the notice formatter (2000-char cap);
        still prepends ``--- Extracted document text (OCR) ---`` like the extract pass
        in ``inferRawWithNoticePreview``.
    """
    ext = extraction_prompt.strip()
    if ocr_mode == "infer_raw":
        body = (ocr_text or "").strip()
    elif ocr_mode == "track_a_notice_cap":
        body = format_track_a_notice_ocr_section(ocr_text).strip()
    else:
        raise ValueError(f"Unknown ocr_mode: {ocr_mode!r}")
    return append_extracted_ocr_block(ext, body)


def finalize_device_style_prompt(
    extraction_prompt: str,
    ocr_text: str,
    *,
    ocr_mode: str = "infer_raw",
) -> str:
    """User block + Gemma markers + char clamp (full on-device input shaping)."""
    user = build_device_style_user_prompt(
        extraction_prompt, ocr_text, ocr_mode=ocr_mode
    )
    return clamp_prompt_for_local_llm(wrap_gemma_chat_template(user))


def ocr_image_tesseract(image_path: str | Path) -> str:
    """Best-effort OCR for desktop parity tests (install: ``brew install tesseract``)."""
    try:
        import pytesseract
        from PIL import Image
    except ImportError as e:
        raise ImportError(
            "device_eval_mirror OCR needs pytesseract + Pillow. "
            "Install: brew install tesseract && pip install pytesseract pillow"
        ) from e

    p = Path(image_path)
    img = Image.open(p).convert("RGB")
    return pytesseract.image_to_string(img)
