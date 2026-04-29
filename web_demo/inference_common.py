"""
Shared preprocessing and JSON parsing for HF local (`inference_hf`) and Hub API (`inference_hf_api`) backends.

No Torch/Transformers — safe to import on CPU-only Spaces.
"""

from __future__ import annotations

import io
import json
import os
import re
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

from blur_detector import detect_blur

# Module defaults (mirror inference_hf historically)
JPEG_QUALITY = 85
PDF_DPI = 100


def max_new_tokens(hub_api: bool = False) -> int:
    """
    Max decoding length.

    Hosted Hub VLMs (`inference_hf_api`) use a higher default when `CIVICLENS_MAX_NEW_TOKENS` is unset:
    providers often consume the whole budget on internal reasoning/tool traces before filling `content`.
    """
    fb = 2048 if hub_api else 512
    raw = os.environ.get("CIVICLENS_MAX_NEW_TOKENS")
    if raw is None:
        return max(128, min(4096, fb))
    try:
        return max(128, min(4096, int(raw)))
    except ValueError:
        return max(128, min(4096, fb))


def max_image_side() -> int:
    """Longest image edge after resize; lower = less upstream vision cost."""
    raw = os.environ.get("CIVICLENS_MAX_IMAGE_SIZE", "768")
    try:
        return max(384, min(1280, int(raw)))
    except ValueError:
        return 768


def max_input_images() -> int:
    raw = os.environ.get("CIVICLENS_MAX_INPUT_IMAGES", "4")
    try:
        return max(1, min(8, int(raw)))
    except ValueError:
        return 4


def preprocess_image(file_path: Path | str) -> tuple[bytes, dict]:
    """
    Preprocess image for inference.

    - Convert PDF to image if needed
    - Resize long edge to env CIVICLENS_MAX_IMAGE_SIZE (default 768)
    - Convert to JPEG at quality 85
    - Strip EXIF data (via JPEG re-encode)
    - Run blur detection
    """
    file_path = Path(file_path)

    if file_path.suffix.lower() == ".pdf":
        from pdf2image import convert_from_path

        pages = convert_from_path(str(file_path), dpi=PDF_DPI)
        img = pages[0].convert("RGB")
    else:
        img = Image.open(file_path).convert("RGB")

    img = ImageOps.exif_transpose(img)

    ms = max_image_side()
    max_dim = max(img.size)
    if max_dim > ms:
        ratio = ms / max_dim
        new_size = (int(img.size[0] * ratio), int(img.size[1] * ratio))
        img = img.resize(new_size, Image.Resampling.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY)
    jpeg_bytes = buf.getvalue()

    blur_result = detect_blur(jpeg_bytes)

    metadata = {
        "original_size": img.size,
        "blur_score": blur_result.score,
        "is_blurry": blur_result.is_blurry,
        "blur_guidance": blur_result.guidance,
    }

    return jpeg_bytes, metadata


def _unwrap_nested_json(obj: dict) -> dict:
    """Hoist common wrappers (answer/result/…) so checklist keys appear at top level."""
    track_a = frozenset({"notice_summary", "proof_pack", "action_summary"})
    track_b = frozenset({"requirements", "family_summary", "duplicate_category_flag"})

    def has_track_keys(d: dict) -> bool:
        k = set(d.keys())
        return bool(k & track_a or k & track_b)

    if has_track_keys(obj):
        return obj

    for nested_key in (
        "answer",
        "result",
        "parsed",
        "data",
        "output",
        "response",
        "assistant_message",
        "json",
    ):
        inner = obj.get(nested_key)
        if isinstance(inner, dict) and has_track_keys(inner):
            return inner
        if isinstance(inner, str) and inner.strip():
            try:
                sub = json.loads(inner.strip())
                if isinstance(sub, dict) and has_track_keys(sub):
                    return sub
            except json.JSONDecodeError:
                continue

    return obj


def _normalize_parsed_structure(obj: Any) -> dict | None:
    """If the model returns a bare JSON list, wrap into the dict our UI expects."""
    if isinstance(obj, dict):
        obj = _unwrap_nested_json(obj)
        if not obj:
            return None
        return obj
    if isinstance(obj, list) and obj and isinstance(obj[0], dict):
        row = obj[0]
        keys = row.keys()
        if "requirement" in keys:
            return {"requirements": obj}
        if "category" in keys and "assessment" in keys:
            return {"proof_pack": obj}
    return None


def parse_json_response(raw: str) -> dict | None:
    """
    Parse JSON response with retry logic for model quirks.
    Finds the first well-formed `{...}` object when the reply includes chatter or echo.
    """
    cleaned = raw.strip()
    cleaned = re.sub(
        r"<(?:think|thinking|reflection|analysis)[^>]*>[\s\S]*?</(?:think|thinking|reflection|analysis)>",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )

    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        if lines[0].startswith("```json"):
            lines = lines[1:]
        elif lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()

    decoder = json.JSONDecoder()

    for slab in (cleaned,):
        try:
            obj = json.loads(slab)
            norm = _normalize_parsed_structure(obj)
            if norm is not None:
                return norm
        except json.JSONDecodeError:
            pass

    i = 0
    while i < len(cleaned):
        j = cleaned.find("{", i)
        if j < 0:
            break
        try:
            obj, _end = decoder.raw_decode(cleaned[j:])
            norm = _normalize_parsed_structure(obj)
            if norm is not None:
                return norm
        except json.JSONDecodeError:
            pass
        i = j + 1

    i = 0
    while i < len(cleaned):
        j = cleaned.find("[", i)
        if j < 0:
            break
        try:
            obj, _end = decoder.raw_decode(cleaned[j:])
            norm = _normalize_parsed_structure(obj)
            if norm is not None:
                return norm
        except json.JSONDecodeError:
            pass
        i = j + 1

    try:
        wrapped = json.loads("{" + cleaned + "}")
        norm = _normalize_parsed_structure(wrapped)
        if norm is not None:
            return norm
    except json.JSONDecodeError:
        pass

    json_pattern = r"\{[\s\S]*\}"
    match = re.search(json_pattern, cleaned)
    if match:
        try:
            obj = json.loads(match.group(0))
            norm = _normalize_parsed_structure(obj)
            if norm is not None:
                return norm
        except json.JSONDecodeError:
            pass

    return None
