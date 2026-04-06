"""
Inference engine for CivicLens web demo.

Handles image preprocessing, Ollama integration with Gemma 4 E4B,
JSON parsing with retry wrapper, and result formatting.
"""

import base64
import io
import json
import re
from pathlib import Path
from typing import Any

import ollama
from PIL import Image

from blur_detector import detect_blur
from prompts import build_track_a_prompt, build_track_b_prompt

# Model configuration
DEFAULT_MODEL = "gemma4:e4b"
DEFAULT_TEMPERATURE = 0.0
DEFAULT_MAX_TOKENS = 2048

# Image preprocessing config
MAX_IMAGE_SIZE = 1024
JPEG_QUALITY = 85
PDF_DPI = 100


def preprocess_image(file_path: Path | str) -> tuple[bytes, dict]:
    """
    Preprocess image for inference.

    - Convert PDF to image if needed
    - Resize to max 1024px longest edge
    - Convert to JPEG at quality 85
    - Strip EXIF data
    - Run blur detection

    Returns:
        Tuple of (jpeg_bytes, metadata_dict)
    """
    file_path = Path(file_path)

    # Load image
    if file_path.suffix.lower() == ".pdf":
        from pdf2image import convert_from_path
        pages = convert_from_path(str(file_path), dpi=PDF_DPI)
        img = pages[0].convert("RGB")
    else:
        img = Image.open(file_path).convert("RGB")

    # Normalize rotation from EXIF
    img = ImageOps.exif_transpose(img)

    # Resize if too large
    max_dim = max(img.size)
    if max_dim > MAX_IMAGE_SIZE:
        ratio = MAX_IMAGE_SIZE / max_dim
        new_size = (int(img.size[0] * ratio), int(img.size[1] * ratio))
        img = img.resize(new_size, Image.Resampling.LANCZOS)

    # Convert to JPEG bytes (strips EXIF)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY)
    jpeg_bytes = buf.getvalue()

    # Run blur detection
    blur_result = detect_blur(jpeg_bytes)

    metadata = {
        "original_size": img.size,
        "blur_score": blur_result.score,
        "is_blurry": blur_result.is_blurry,
        "blur_guidance": blur_result.guidance,
    }

    return jpeg_bytes, metadata


def parse_json_response(raw: str) -> dict | None:
    """
    Parse JSON response with retry logic for Gemma 4 quirks.

    Handles:
    - Direct JSON parsing
    - Markdown code fences
    - Missing outer braces (E4B occasionally omits)
    """
    # First attempt: direct parse
    cleaned = raw.strip()

    # Remove markdown fences if present
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        if lines[0].startswith("```json"):
            lines = lines[1:]
        elif lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()

    # Try direct parse
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    # Try wrapping bare key:value output (E4B occasionally omits braces)
    try:
        return json.loads("{" + cleaned + "}")
    except json.JSONDecodeError:
        pass

    # Try extracting JSON from text
    json_pattern = r'\{[\s\S]*\}'
    match = re.search(json_pattern, cleaned)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    return None


def run_track_a(
    notice_file: Path | str | None,
    doc1: Path | str | None,
    doc2: Path | str | None = None,
    doc3: Path | str | None = None,
    model: str = DEFAULT_MODEL,
    temperature: float = DEFAULT_TEMPERATURE,
) -> dict[str, Any]:
    """
    Run Track A (SNAP Proof-Pack) inference.

    Args:
        notice_file: Path to government notice image/PDF
        doc1: First supporting document
        doc2: Optional second document
        doc3: Optional third document
        model: Ollama model name
        temperature: Sampling temperature

    Returns:
        Dictionary with results, action summary, and metadata
    """
    # Collect all files
    files = []
    if notice_file:
        files.append(("Government Notice", notice_file))
    if doc1:
        files.append(("Document 1", doc1))
    if doc2:
        files.append(("Document 2", doc2))
    if doc3:
        files.append(("Document 3", doc3))

    if not files:
        return {"error": "No documents provided"}

    # Preprocess all images
    images_b64 = []
    blur_warnings = []
    metadata = []

    for label, file_path in files:
        if file_path is None:
            continue
        jpeg_bytes, meta = preprocess_image(file_path)
        images_b64.append(base64.b64encode(jpeg_bytes).decode())
        metadata.append({"label": label, **meta})

        if meta["is_blurry"]:
            blur_warnings.append(f"{label}: {meta['blur_guidance']}")

    # Build prompt
    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_a_prompt(doc_labels)

    # Run inference
    client = ollama.Client()
    response = client.chat(
        model=model,
        messages=[{
            "role": "user",
            "content": prompt,
            "images": images_b64,
        }],
        options={"temperature": temperature},
    )

    raw_response = response.get("message", {}).get("content", "")

    # Parse response
    parsed = parse_json_response(raw_response)

    return {
        "parsed": parsed,
        "raw_response": raw_response,
        "blur_warnings": blur_warnings,
        "metadata": metadata,
        "success": parsed is not None,
    }


def run_track_b(
    doc1: Path | str | None,
    doc2: Path | str | None = None,
    doc3: Path | str | None = None,
    doc4: Path | str | None = None,
    doc5: Path | str | None = None,
    model: str = DEFAULT_MODEL,
    temperature: float = DEFAULT_TEMPERATURE,
) -> dict[str, Any]:
    """
    Run Track B (BPS Packet Checker) inference.

    Args:
        doc1: First document (required)
        doc2-doc5: Optional additional documents
        model: Ollama model name
        temperature: Sampling temperature

    Returns:
        Dictionary with results, family summary, and metadata
    """
    # Collect all files
    files = []
    docs = [doc1, doc2, doc3, doc4, doc5]
    for i, doc in enumerate(docs, 1):
        if doc:
            files.append((f"Document {i}", doc))

    if not files:
        return {"error": "No documents provided"}

    # Preprocess all images
    images_b64 = []
    blur_warnings = []
    metadata = []

    for label, file_path in files:
        jpeg_bytes, meta = preprocess_image(file_path)
        images_b64.append(base64.b64encode(jpeg_bytes).decode())
        metadata.append({"label": label, **meta})

        if meta["is_blurry"]:
            blur_warnings.append(f"{label}: {meta['blur_guidance']}")

    # Build prompt
    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_b_prompt(doc_labels)

    # Run inference
    client = ollama.Client()
    response = client.chat(
        model=model,
        messages=[{
            "role": "user",
            "content": prompt,
            "images": images_b64,
        }],
        options={"temperature": temperature},
    )

    raw_response = response.get("message", {}).get("content", "")

    # Parse response
    parsed = parse_json_response(raw_response)

    return {
        "parsed": parsed,
        "raw_response": raw_response,
        "blur_warnings": blur_warnings,
        "metadata": metadata,
        "success": parsed is not None,
    }


# Import ImageOps for EXIF handling
from PIL import ImageOps
