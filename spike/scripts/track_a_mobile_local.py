#!/usr/bin/env python3
"""
Local Track A pipeline — mirrors the *mobile* OCR → prompt → JSON path for visibility.

Mobile reference:
  mobile/lib/core/inference/inference_service.dart  (analyzeTrackAWithOcr, _formatOcrResults, _clampPromptForLocalLlm)
  mobile/lib/core/inference/prompt_templates.dart  (trackAOcrOnly)

This script does **not** run on-device ML Kit OCR; it uses **Tesseract** (same idea as
spike/scripts/ocr_test.py). If Tesseract OCR is much worse than ML Kit, you will see
UNCERTAIN / empty proof_pack here while a device might differ — compare shapes.

Requires (repo root):
  uv sync --group dev
  brew install tesseract   # macOS

Examples:
  cd /path/to/civics
  uv run --group dev python spike/scripts/track_a_mobile_local.py \\
    spike/artifacts/degraded/D01-degraded.jpg \\
    spike/artifacts/degraded/D03-degraded.jpg

  # Prompt only (no Ollama):
  uv run --group dev python spike/scripts/track_a_mobile_local.py --no-llm \\
    spike/artifacts/degraded/D01-degraded.jpg \\
    spike/artifacts/degraded/D03-degraded.jpg \\
    spike/artifacts/degraded/D06-degraded.jpg

  # Save prompt + JSON (same image paths — must exist on disk):
  uv run --group dev python spike/scripts/track_a_mobile_local.py \\
    --dump-prompt /tmp/ta_prompt.txt --json-out /tmp/ta_out.json \\
    spike/artifacts/degraded/D01-degraded.jpg \\
    spike/artifacts/degraded/D03-degraded.jpg
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

import httpx
import ollama
import pytesseract
from PIL import Image

# --- Match mobile inference_service.dart ---
_MAX_LOCAL_LLM_PROMPT_CHARS = 5600
_MAX_CHARS_PER_SECTION = 800
_MAX_TOTAL_OCR_CHARS = 2400
_TRACK_A_NOTICE_MAX = 2000
_TRACK_A_SUPPORTING_MAX = 1100
_TRACK_A_OCR_TOTAL_MAX = 4200

_IMPORTANT_OCR_BLOCK = (
    "IMPORTANT: No images are attached. Base your analysis only on this "
    "OCR output (errors and gaps are possible).\n"
    'If a section ends with the line "[... text truncated for model limits ...]", '
    "only part of the extracted text was included in this prompt — that is not a "
    'problem with the resident photo. Do not say their upload or document image '
    'is \"truncated\"; use caveats only for real gaps in the OCR text.'
)


def track_a_ocr_only_preamble(*, document_labels: list[str]) -> str:
    """Mirror PromptTemplates.trackAOcrOnly (mobile)."""
    list_lines = "\n".join(
        f"{i + 1}. {label}" for i, label in enumerate(document_labels)
    )
    return (
        "You help a resident with a government benefit notice and proof "
        "documents (e.g. SNAP verification). Only OCR text is below; it may "
        "contain errors.\n\n"
        f"Supporting docs (labels):\n{list_lines}\n\n"
        "Steps: (1) Read the notice — requested proof categories, deadline, "
        "consequence. (2) Map each document to a category; use likely_satisfies / "
        "likely_does_not_satisfy / missing / uncertain. (3) Return ONLY valid JSON "
        "(no markdown).\n\n"
        '{"notice_summary":{"requested_categories":[],"deadline":"","consequence":""},'
        '"proof_pack":[{"category":"","matched_document":"[name or MISSING]",'
        '"assessment":"likely_satisfies|likely_does_not_satisfy|missing|uncertain",'
        '"confidence":"high|medium|low","evidence":"","caveats":""}],'
        '"action_summary":""}\n\n'
        "action_summary: 2–4 sentences, concrete next steps.\n\n"
        "Never imply the agency accepted documents. If the notice is unreadable, "
        "use UNCERTAIN in notice fields; do not guess.\n\n"
        "Reply with only the JSON object. No markdown fences, no commentary before "
        "or after. Escape any line breaks inside string values as \\n."
    )


def format_ocr_results(
    results: dict[int, str],
    descriptions: list[str],
    *,
    max_chars_per_section: int = _MAX_CHARS_PER_SECTION,
    max_total_chars: int = _MAX_TOTAL_OCR_CHARS,
) -> str:
    """Mirror InferenceService._formatOcrResults."""
    buffer_parts: list[str] = []
    total = 0
    indices = sorted(results.keys())
    for i in indices:
        desc = descriptions[i] if i < len(descriptions) else f"Document {i + 1}"
        body = results.get(i) or ""
        if len(body) > max_chars_per_section:
            body = (
                body[:max_chars_per_section]
                + "\n[... text truncated for model limits ...]"
            )
        header = f"--- {desc} ---\n"
        section = f"{header}{body}\n\n"
        if total + len(section) > max_total_chars:
            remaining = max_total_chars - total - len(header)
            if remaining > 200:
                buffer_parts.append(header)
                end = max(0, min(len(body), remaining))
                buffer_parts.append(body[:end])
                buffer_parts.append(
                    "\n[... document truncated; later pages omitted ...]\n"
                )
            break
        buffer_parts.append(section)
        total += len(section)
    return "".join(buffer_parts)


def clamp_prompt_for_local_llm(prompt: str, max_chars: int = _MAX_LOCAL_LLM_PROMPT_CHARS) -> str:
    """Mirror InferenceService._clampPromptForLocalLlm."""
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


def build_gemma_track_a_prompt(
    *,
    supporting_labels: list[str],
    extracted_text: str,
) -> str:
    """Full user block + Gemma turn markers (mobile llama_client)."""
    preamble = track_a_ocr_only_preamble(document_labels=supporting_labels)
    user_block = f"{preamble}\n\n{_IMPORTANT_OCR_BLOCK}\n\n{extracted_text}"
    if "<start_of_turn>" in user_block:
        return user_block
    return (
        f"<start_of_turn>user\n{user_block}\n<end_of_turn>\n<start_of_turn>model\n"
    )


def load_image_rgb(path: Path) -> Image.Image:
    path = path.expanduser().resolve()
    if path.suffix.lower() == ".pdf":
        try:
            from pdf2image import convert_from_path
        except ImportError as e:
            raise SystemExit(
                "PDF input requires pdf2image. Run: uv sync --group dev"
            ) from e
        pages = convert_from_path(str(path), dpi=100)
        return pages[0].convert("RGB")
    return Image.open(path).convert("RGB")


def ocr_image(path: Path) -> str:
    try:
        img = load_image_rgb(path)
    except Exception as e:
        raise SystemExit(f"Failed to open {path}: {e}") from e
    try:
        return pytesseract.image_to_string(img)
    except pytesseract.TesseractNotFoundError:
        raise SystemExit(
            "Tesseract not found. Install: brew install tesseract (macOS)"
        ) from None


def parse_track_a_json(raw: str) -> dict[str, Any] | None:
    """Lightweight JSON extraction (mobile ResponseParser is stricter)."""
    cleaned = (raw or "").strip()
    if not cleaned:
        return None
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        if lines[-1].strip() == "```":
            cleaned = "\n".join(lines[1:-1])
        else:
            cleaned = "\n".join(lines[1:])
    cleaned = cleaned.strip()
    try:
        out = json.loads(cleaned)
        return out if isinstance(out, dict) else None
    except json.JSONDecodeError:
        pass
    m = re.search(r"\{[\s\S]*\}\s*$", cleaned)
    if m:
        try:
            out = json.loads(m.group(0))
            return out if isinstance(out, dict) else None
        except json.JSONDecodeError:
            pass
    return None


def summarize_parsed(parsed: dict[str, Any] | None) -> dict[str, Any]:
    if not parsed:
        return {"parse_ok": False}
    ns = parsed.get("notice_summary") or {}
    deadline = ns.get("deadline", "")
    cats = ns.get("requested_categories") or []
    pack = parsed.get("proof_pack") or []
    uncertain = str(deadline).strip().upper() == "UNCERTAIN"
    return {
        "parse_ok": True,
        "notice_deadline": deadline,
        "notice_categories_count": len(cats) if isinstance(cats, list) else 0,
        "notice_is_uncertain_ui": uncertain,
        "proof_pack_items": len(pack) if isinstance(pack, list) else 0,
        "action_summary_len": len(str(parsed.get("action_summary", "") or "")),
    }


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Local mirror of mobile Track A: Tesseract OCR + same prompt caps + Ollama text-only."
    )
    ap.add_argument(
        "images",
        nargs="+",
        type=Path,
        help="First image/PDF = government notice; rest = supporting documents (order matches mobile).",
    )
    ap.add_argument(
        "--labels",
        type=str,
        default="",
        help="Comma-separated labels for supporting docs only (default: Document 1, Document 2, …).",
    )
    ap.add_argument("--model", default="gemma4:e2b", help="Ollama model (text chat).")
    ap.add_argument("--temp", type=float, default=0.0)
    ap.add_argument("--max-tokens", type=int, default=1400, help="Match mobile chat maxTokens.")
    ap.add_argument("--http-timeout", type=float, default=900.0)
    ap.add_argument(
        "--no-llm",
        action="store_true",
        help="Stop after building prompt (OCR + formatting + clamp).",
    )
    ap.add_argument("--dump-prompt", type=Path, default=None, help="Write final prompt to this file.")
    ap.add_argument("--json-out", type=Path, default=None, help="Write JSON diagnostics to this file.")
    args = ap.parse_args()

    paths = [p.expanduser().resolve() for p in args.images]
    for p in paths:
        if not p.is_file():
            print(f"ERROR: not a file: {p}", file=sys.stderr)
            print(
                "  Hint: pass real paths from the repo root. First image = government "
                "notice; the rest = supporting docs. Example:\n"
                "    spike/artifacts/degraded/D01-degraded.jpg "
                "spike/artifacts/degraded/D03-degraded.jpg",
                file=sys.stderr,
            )
            sys.exit(1)

    if args.labels.strip():
        supporting_labels = [s.strip() for s in args.labels.split(",") if s.strip()]
    else:
        supporting_labels = [f"Document {i + 1}" for i in range(len(paths) - 1)]

    if len(supporting_labels) != len(paths) - 1:
        print(
            f"ERROR: expected {len(paths) - 1} supporting labels, got {len(supporting_labels)} "
            "(use --labels a,b,c matching supporting images after the notice).",
            file=sys.stderr,
        )
        sys.exit(1)

    descriptions = ["Government notice", *supporting_labels]

    print("=" * 72)
    print("Track A local pipeline (mobile OCR-text path mirror)")
    print("=" * 72)

    ocr_by_index: dict[int, str] = {}
    for i, p in enumerate(paths):
        label = descriptions[i]
        print(f"\n--- OCR: {label} ({p.name}) ---", flush=True)
        text = ocr_image(p)
        ocr_by_index[i] = text
        t = text.strip()
        print(f"  chars (raw): {len(text)}  (trimmed): {len(t)}")
        preview = text[:600].replace("\n", "\\n")
        print(f"  preview: {preview!r}{'...' if len(text) > 600 else ''}")

    has_any = any((ocr_by_index[i] or "").strip() for i in ocr_by_index)
    if not has_any:
        print("\nERROR: No OCR text from any document (mobile would fail here).", file=sys.stderr)
        sys.exit(2)

    extracted = format_ocr_results_track_a(ocr_by_index, descriptions)
    prompt = build_gemma_track_a_prompt(
        supporting_labels=supporting_labels,
        extracted_text=extracted,
    )
    prompt_before_clamp = prompt
    prompt = clamp_prompt_for_local_llm(prompt)

    print("\n--- Prompt sizing ---")
    print(f"  OCR formatted block length: {len(extracted)}")
    print(f"  Prompt length (before clamp): {len(prompt_before_clamp)}")
    print(f"  Prompt length (after clamp):  {len(prompt)}")
    if len(prompt) < len(prompt_before_clamp):
        print("  NOTE: clamp reduced prompt (same as on-device).")

    if args.dump_prompt:
        args.dump_prompt.parent.mkdir(parents=True, exist_ok=True)
        args.dump_prompt.write_text(prompt, encoding="utf-8")
        print(f"  Wrote prompt → {args.dump_prompt}")

    if args.no_llm:
        print("\n--no-llm: skipping Ollama.")
        return

    client = ollama.Client(timeout=httpx.Timeout(args.http_timeout))
    print(f"\n--- Ollama chat (text-only), model={args.model!r} ---", flush=True)
    t0 = time.time()
    try:
        r = client.chat(
            model=args.model,
            messages=[{"role": "user", "content": prompt}],
            options={"temperature": args.temp, "num_predict": args.max_tokens},
        )
    except Exception as e:
        print(f"ERROR: Ollama chat failed: {e}", file=sys.stderr)
        sys.exit(3)
    elapsed = time.time() - t0
    raw = r.get("message", {}).get("content") or ""
    print(f"  elapsed_s: {elapsed:.2f}")
    print("\n--- Raw model output ---")
    print(raw if raw.strip() else "(empty)")

    parsed = parse_track_a_json(raw)
    summary = summarize_parsed(parsed)

    print("\n--- Parse / UI-shaped summary ---")
    for k, v in summary.items():
        print(f"  {k}: {v}")
    if parsed:
        print("\n--- Parsed notice_summary ---")
        print(json.dumps(parsed.get("notice_summary"), indent=2, ensure_ascii=False))
        print("\n--- Parsed proof_pack (count) ---")
        pp = parsed.get("proof_pack")
        if isinstance(pp, list):
            print(f"  items: {len(pp)}")
            for j, item in enumerate(pp[:12]):
                print(f"  [{j}] {json.dumps(item, ensure_ascii=False)[:200]}...")
            if len(pp) > 12:
                print(f"  ... ({len(pp) - 12} more)")

    if args.json_out:
        out = {
            "paths": [str(p) for p in paths],
            "descriptions": descriptions,
            "ocr_char_counts": {i: len(ocr_by_index[i]) for i in ocr_by_index},
            "extracted_text_len": len(extracted),
            "prompt_len_after_clamp": len(prompt),
            "model": args.model,
            "elapsed_s": round(elapsed, 2),
            "raw_response": raw,
            "parsed": parsed,
            "summary": summary,
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"\nWrote JSON → {args.json_out}")

    print("\nDone.")


if __name__ == "__main__":
    main()
