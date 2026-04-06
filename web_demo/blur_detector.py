"""
Blur detection for CivicLens web demo.

Uses Laplacian variance method to detect blurry images before sending to model.
Based on spike findings: the model cannot self-report illegibility and will
hallucinate with high confidence on blurry images.
"""

import io
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


@dataclass
class BlurResult:
    """Result of blur detection."""
    score: float
    is_blurry: bool
    guidance: str


def _convolve2d(image: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """Simple 2D convolution without scipy dependency."""
    from numpy.lib.stride_tricks import sliding_window_view

    kh, kw = kernel.shape
    ih, iw = image.shape

    # Pad the image
    padded = np.pad(image, ((kh//2, kh//2), (kw//2, kw//2)), mode='constant')

    # Create sliding windows
    windows = sliding_window_view(padded, (kh, kw))

    # Reshape for broadcasting with kernel
    output = np.zeros((ih, iw), dtype=np.float32)
    for i in range(ih):
        for j in range(iw):
            output[i, j] = np.sum(windows[i, j] * kernel)

    return output


def compute_blur_score(image_bytes: bytes) -> float:
    """
    Compute blur score using Laplacian variance method.

    Lower variance = blurrier image.
    Thresholds (tuned from spike testing):
    - score < 50: very blurry
    - score 50-100: moderately blurry
    - score > 100: acceptable

    Args:
        image_bytes: JPEG/PNG image bytes

    Returns:
        Laplacian variance score (higher = sharper)
    """
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert('L')  # Grayscale
        img_array = np.array(img, dtype=np.float32)

        # Downsample large images for performance
        max_dim = max(img_array.shape)
        if max_dim > 512:
            scale = 512 / max_dim
            new_h = int(img_array.shape[0] * scale)
            new_w = int(img_array.shape[1] * scale)
            from PIL import Image as PILImage
            img_small = img.resize((new_w, new_h), PILImage.Resampling.LANCZOS)
            img_array = np.array(img_small, dtype=np.float32)

        # Laplacian kernel
        kernel = np.array([[0, 1, 0],
                          [1, -4, 1],
                          [0, 1, 0]], dtype=np.float32)

        # Apply convolution using scipy if available, else fallback
        try:
            from scipy import ndimage
            laplacian = ndimage.convolve(img_array, kernel, mode='constant', cval=0.0)
        except ImportError:
            # Fallback: simple convolution
            laplacian = _convolve2d(img_array, kernel)

        # Compute variance
        variance = np.var(laplacian)

        return float(variance)
    except Exception:
        # If blur detection fails, assume acceptable and let model handle it
        return 150.0


def detect_blur(image_bytes: bytes, threshold: float = 100.0) -> BlurResult:
    """
    Detect if an image is blurry and return guidance.

    Args:
        image_bytes: JPEG/PNG image bytes
        threshold: Minimum acceptable blur score (default 100)

    Returns:
        BlurResult with score, blur status, and guidance text
    """
    score = compute_blur_score(image_bytes)

    if score >= threshold:
        guidance = "Image is clear"
        is_blurry = False
    elif score >= 50:
        guidance = "Try holding your phone steady — image is slightly blurry"
        is_blurry = False  # Allow through but warn
    else:
        guidance = "Move to better lighting and try again — photo is unclear"
        is_blurry = True

    return BlurResult(score=score, is_blurry=is_blurry, guidance=guidance)


def check_image_quality(file_path: Path | str) -> BlurResult:
    """
    Check image quality from a file path.

    Args:
        file_path: Path to image file

    Returns:
        BlurResult with quality assessment
    """
    with open(file_path, 'rb') as f:
        image_bytes = f.read()
    return detect_blur(image_bytes)
