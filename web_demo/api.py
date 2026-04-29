"""
Cloud Fallback API for CivicLens Mobile App

FastAPI endpoints for Agent 2's mobile cloud fallback mode.
Provides HTTP API for document analysis when on-device inference fails.
"""

import base64
import io
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

from fastapi import FastAPI, HTTPException, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from inference_backend import run_track_a, run_track_b

app = FastAPI(
    title="CivicLens Cloud API",
    description="Cloud fallback API for CivicLens mobile app",
    version="1.0.0",
)

# CORS configuration for mobile app access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict to mobile app domain in production
    allow_credentials=True,
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


class AnalyzeRequest(BaseModel):
    """Request model for document analysis."""
    track: str  # "a" or "b"
    prompt: Optional[str] = None  # Optional custom prompt
    images_base64: List[str]  # Base64 encoded images
    document_labels: Optional[List[str]] = None  # Labels for each document


class AnalyzeResponse(BaseModel):
    """Response model for document analysis."""
    success: bool
    parsed: Optional[dict] = None
    raw_response: str
    blur_warnings: List[str]
    error: Optional[str] = None
    processing_time_ms: Optional[int] = None


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    version: str
    timestamp: str


def save_base64_to_temp(base64_string: str) -> Path:
    """Save base64 encoded image to temporary file."""
    # Decode base64
    image_data = base64.b64decode(base64_string)

    # Create temp file
    suffix = ".jpg"  # Assume JPEG
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(image_data)
        return Path(tmp.name)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint (used by keep-warm and monitoring)."""
    return HealthResponse(
        status="ok",
        version="1.0.0",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze_documents(request: AnalyzeRequest):
    """
    Analyze documents via cloud API for mobile fallback.

    - track: "a" for SNAP, "b" for School Enrollment
    - images_base64: List of base64-encoded images
    - document_labels: Optional labels for each document
    """
    import time
    start_time = time.time()

    try:
        # Validate track
        if request.track.lower() not in ["a", "b"]:
            raise HTTPException(
                status_code=400,
                detail="Invalid track. Use 'a' for SNAP or 'b' for School Enrollment"
            )

        # Validate images
        if not request.images_base64:
            raise HTTPException(
                status_code=400,
                detail="No images provided"
            )

        if len(request.images_base64) > 5:
            raise HTTPException(
                status_code=400,
                detail="Maximum 5 images allowed"
            )

        # Save base64 images to temp files
        temp_files = []
        try:
            for img_b64 in request.images_base64:
                temp_path = save_base64_to_temp(img_b64)
                temp_files.append(temp_path)

            # Run inference based on track
            if request.track.lower() == "a":
                # Track A: SNAP - first image is notice, rest are documents
                notice = temp_files[0] if len(temp_files) > 0 else None
                doc1 = temp_files[1] if len(temp_files) > 1 else None
                doc2 = temp_files[2] if len(temp_files) > 2 else None
                doc3 = temp_files[3] if len(temp_files) > 3 else None

                if notice is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Track A requires at least a government notice"
                    )

                result = run_track_a(notice, doc1, doc2, doc3)
            else:
                # Track B: School Enrollment - all images are documents
                doc1 = temp_files[0] if len(temp_files) > 0 else None
                doc2 = temp_files[1] if len(temp_files) > 1 else None
                doc3 = temp_files[2] if len(temp_files) > 2 else None
                doc4 = temp_files[3] if len(temp_files) > 3 else None
                doc5 = temp_files[4] if len(temp_files) > 4 else None

                if doc1 is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Track B requires at least one document"
                    )

                result = run_track_b(doc1, doc2, doc3, doc4, doc5)

            processing_time = int((time.time() - start_time) * 1000)

            return AnalyzeResponse(
                success=result.get("success", False),
                parsed=result.get("parsed"),
                raw_response=result.get("raw_response", ""),
                blur_warnings=result.get("blur_warnings", []),
                error=result.get("error"),
                processing_time_ms=processing_time,
            )

        finally:
            # Clean up temp files
            for temp_file in temp_files:
                try:
                    temp_file.unlink()
                except Exception:
                    pass

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze/form")
async def analyze_documents_form(
    track: str = Form(...),
    images: List[UploadFile] = File(...),
):
    """
    Analyze documents using multipart/form-data (alternative to JSON).
    Useful for direct mobile app uploads.
    """
    import time
    start_time = time.time()

    try:
        # Validate track
        if track.lower() not in ["a", "b"]:
            raise HTTPException(
                status_code=400,
                detail="Invalid track. Use 'a' for SNAP or 'b' for School Enrollment"
            )

        if not images:
            raise HTTPException(status_code=400, detail="No images provided")

        if len(images) > 5:
            raise HTTPException(status_code=400, detail="Maximum 5 images allowed")

        # Save uploaded files to temp
        temp_files = []
        try:
            for upload_file in images:
                suffix = Path(upload_file.filename).suffix or ".jpg"
                with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                    content = await upload_file.read()
                    tmp.write(content)
                    temp_files.append(Path(tmp.name))

            # Run inference
            if track.lower() == "a":
                notice = temp_files[0] if len(temp_files) > 0 else None
                doc1 = temp_files[1] if len(temp_files) > 1 else None
                doc2 = temp_files[2] if len(temp_files) > 2 else None
                doc3 = temp_files[3] if len(temp_files) > 3 else None

                if notice is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Track A requires at least a government notice"
                    )

                result = run_track_a(notice, doc1, doc2, doc3)
            else:
                doc1 = temp_files[0] if len(temp_files) > 0 else None
                doc2 = temp_files[1] if len(temp_files) > 1 else None
                doc3 = temp_files[2] if len(temp_files) > 2 else None
                doc4 = temp_files[3] if len(temp_files) > 3 else None
                doc5 = temp_files[4] if len(temp_files) > 4 else None

                if doc1 is None:
                    raise HTTPException(
                        status_code=400,
                        detail="Track B requires at least one document"
                    )

                result = run_track_b(doc1, doc2, doc3, doc4, doc5)

            processing_time = int((time.time() - start_time) * 1000)

            return {
                "success": result.get("success", False),
                "parsed": result.get("parsed"),
                "raw_response": result.get("raw_response", ""),
                "blur_warnings": result.get("blur_warnings", []),
                "error": result.get("error"),
                "processing_time_ms": processing_time,
            }

        finally:
            for temp_file in temp_files:
                try:
                    temp_file.unlink()
                except Exception:
                    pass

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Mount Gradio web demo at root (`demo.launch()` never runs here — uvicorn serves FastAPI).
import gradio as gr
from gradio.utils import get_theme as gradio_resolve_theme

from app import CUSTOM_CSS, civic_gradio_theme, demo as gradio_demo

_theme = civic_gradio_theme()
# Workaround Gradio ≥6 ordering bug in mount_gradio_app(): it calls blocks.get_config_file() BEFORE
# applying theme/css, so `/config` and the SPA used to ship with default styling. Hydrate Blocks first,
# regenerate config — then mount applies the same theme/css again (harmless duplicates).
gradio_demo.theme = gradio_resolve_theme(_theme)
gradio_demo.css = CUSTOM_CSS
gradio_demo.js = gradio_demo.js or ""
gradio_demo.head = gradio_demo.head or ""
gradio_demo.head_paths = []
gradio_demo.css_paths = []
gradio_demo._set_html_css_theme_variables()
gradio_demo.config = gradio_demo.get_config_file()


@app.get("/debug/civic_style")
def civic_style_debug():
    """Verify custom theme/CSS landed in Blocks config (helps diagnose HF Space build/cache issues)."""
    cfg = gradio_demo.config or {}
    css = cfg.get("css") or ""
    return {
        "config_css_chars": len(css),
        "theme_name": getattr(gradio_demo.theme, "name", None),
        "theme_hash": getattr(gradio_demo, "theme_hash", None),
        "theme_css_chars": len(getattr(gradio_demo, "theme_css", "") or ""),
        "looks_like_civic_lens": ".civiclens-hero" in css and "#002444" in css,
    }


app = gr.mount_gradio_app(
    app,
    gradio_demo,
    path="/",
    theme=_theme,
    css=CUSTOM_CSS,
)

# mount_gradio_app snapshots config mid-flight; refresh after hooks + transpile finalize.
gradio_demo._set_html_css_theme_variables()
gradio_demo.config = gradio_demo.get_config_file()

print(
    "[civic_lens] Mounted Gradio demo; config css chars:",
    len((gradio_demo.config or {}).get("css") or ""),
)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
