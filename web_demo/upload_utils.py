"""
Normalize Gradio File upload values to local paths.

Gradio 4/5 may hand the callback a str, Path, dict with `path`, list of one
file, or a thin wrapper object — HF Spaces and local dev differ slightly.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Optional


def gradio_upload_to_path(value: Any) -> Optional[Path]:
    """Return a filesystem path the rest of the pipeline can open, or None."""
    if value is None:
        return None

    if isinstance(value, (list, tuple)) and len(value) > 0:
        value = value[0]
    # Occasionally double-wrapped
    if isinstance(value, (list, tuple)) and len(value) > 0:
        value = value[0]

    if isinstance(value, Path):
        return value

    if isinstance(value, str):
        return Path(value)

    if isinstance(value, dict):
        cand = (
            value.get("path")
            or value.get("file_path")
            or value.get("file")
            or value.get("temp_path")
            or value.get("temp_file_path")
            or value.get("name")
        )
        if cand is None:
            return None
        return Path(cand) if not isinstance(cand, Path) else cand

    # Gradio file wrapper / UploadedFile-like
    for attr in ("path", "name", "_path", "file"):
        cand = getattr(value, attr, None)
        if cand is not None:
            return Path(str(cand))

    return None


def coerce_track_a_files(
    notice: Any,
    doc1: Any,
    doc2: Any,
    doc3: Any,
) -> tuple[Optional[Path], Optional[Path], Optional[Path], Optional[Path]]:
    return (
        gradio_upload_to_path(notice),
        gradio_upload_to_path(doc1),
        gradio_upload_to_path(doc2),
        gradio_upload_to_path(doc3),
    )


def coerce_track_b_files(
    d1: Any,
    d2: Any,
    d3: Any,
    d4: Any,
    d5: Any,
) -> tuple[Optional[Path], Optional[Path], Optional[Path], Optional[Path], Optional[Path]]:
    return (
        gradio_upload_to_path(d1),
        gradio_upload_to_path(d2),
        gradio_upload_to_path(d3),
        gradio_upload_to_path(d4),
        gradio_upload_to_path(d5),
    )
