"""
degrade.py — Simulate phone-photo degradation for spike artifacts.

Produces three output variants per input PDF page:
  - D0X-degraded.jpg   slight angle, blur, JPEG compression
  - D0X-blurry.jpg     more aggressive degradation + bottom third obscured
                       (for abstention experiments W3 / B6)

Usage:
    pip install pillow pdf2image
    # Also requires poppler:
    #   Mac:     brew install poppler
    #   Ubuntu:  sudo apt-get install poppler-utils
    #   Windows: https://github.com/oschwartz10612/poppler-windows/releases

    python degrade.py D01-clean.pdf D03-clean.pdf

Output files are written to the same directory as the input PDFs.
"""

import sys
import os
import random
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Missing dependency: pip install pillow")

try:
    from pdf2image import convert_from_path
except ImportError:
    sys.exit("Missing dependency: pip install pdf2image  (also needs poppler — see script header)")


# ── Tunable parameters ────────────────────────────────────────────────────────

DEGRADED = {
    "rotation_deg":       (4, 9),      # range: random angle in this range
    "blur_radius":        (1.0, 1.5),  # Gaussian blur sigma
    "jpeg_quality":       (72, 80),    # JPEG compression quality
    "perspective_shift":  0.012,       # fraction of image width for corner shift
    "dpi":                150,         # render DPI — matches typical phone photo resolution
}

BLURRY = {
    "rotation_deg":       (6, 14),
    "blur_radius":        (2.0, 3.0),
    "jpeg_quality":       (60, 72),
    "perspective_shift":  0.022,
    "dpi":                150,
    "obscure_fraction":   0.28,        # fraction of image height to darken at bottom
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def rand(lo, hi):
    return random.uniform(lo, hi)

def apply_perspective(img, shift_fraction):
    """Very mild perspective warp using an affine-style crop + resize trick."""
    w, h = img.size
    s = int(w * shift_fraction)
    # Randomly shift one corner inward
    corners = [
        (s, s, w - s, h - s),       # slight crop all sides
        (s*2, s, w - s, h - s*2),   # more top-left bias
        (s, s*2, w - s*2, h - s),   # more bottom-right bias
    ]
    box = random.choice(corners)
    return img.crop(box).resize((w, h), Image.LANCZOS)

def obscure_bottom(img, fraction):
    """Darken the bottom `fraction` of the image — simulates thumb or cut-off."""
    import PIL.ImageDraw as ImageDraw
    img = img.copy()
    draw = ImageDraw.Draw(img)
    w, h = img.size
    top = int(h * (1 - fraction))
    # Gradient-ish shadow — two overlapping semi-transparent rects
    draw.rectangle([0, top, w, h], fill=(30, 25, 20))
    return img

def add_noise(img, amount=6):
    """Add very subtle luminance noise to simulate sensor grain."""
    import PIL.ImageChops as ImageChops
    import PIL.ImageFilter as ImageFilter
    noise = Image.effect_noise(img.size, amount)
    noise = noise.convert("RGB")
    return ImageChops.add(img, noise, scale=2.5, offset=-amount // 2)

def degrade_image(img, params, add_obscure=False):
    """Apply the full degradation pipeline to a PIL Image."""
    # 1. Slight perspective warp
    img = apply_perspective(img, params["perspective_shift"])

    # 2. Rotation with white fill (document on white background)
    angle = rand(*params["rotation_deg"]) * random.choice([-1, 1])
    img = img.rotate(angle, expand=False, fillcolor=(248, 246, 242), resample=Image.BICUBIC)

    # 3. Gaussian blur
    radius = rand(*params["blur_radius"])
    img = img.filter(ImageFilter.GaussianBlur(radius=radius))

    # 4. Subtle noise
    img = add_noise(img, amount=5)

    # 5. Optionally obscure bottom (for abstention/blurry variant)
    if add_obscure:
        img = obscure_bottom(img, params["obscure_fraction"])

    return img

def process_pdf(pdf_path: Path):
    print(f"\nProcessing: {pdf_path.name}")
    stem = pdf_path.stem  # e.g. "D01-clean"
    base = stem.replace("-clean", "")  # e.g. "D01"
    out_dir = pdf_path.parent

    # Render PDF to image (first page only — all our docs are single-page)
    print("  Rendering PDF → image...")
    pages = convert_from_path(str(pdf_path), dpi=DEGRADED["dpi"])
    if not pages:
        print(f"  ERROR: no pages found in {pdf_path.name}")
        return
    page = pages[0].convert("RGB")
    print(f"  Rendered at {page.size[0]}×{page.size[1]}px")

    # ── Degraded variant ──────────────────────────────────────────────────────
    random.seed(42)  # reproducible — change seed for different results
    degraded = degrade_image(page.copy(), DEGRADED, add_obscure=False)
    degraded_path = out_dir / f"{base}-degraded.jpg"
    quality = int(rand(*DEGRADED["jpeg_quality"]))
    degraded.save(str(degraded_path), "JPEG", quality=quality)
    print(f"  ✓ {degraded_path.name}  (rotation={round(quality)}%, quality={quality})")

    # ── Blurry/partial variant ────────────────────────────────────────────────
    random.seed(99)
    blurry = degrade_image(page.copy(), BLURRY, add_obscure=True)
    blurry_path = out_dir / f"{base}-blurry.jpg"
    quality_b = int(rand(*BLURRY["jpeg_quality"]))
    blurry.save(str(blurry_path), "JPEG", quality=quality_b)
    print(f"  ✓ {blurry_path.name}  (quality={quality_b}, bottom {int(BLURRY['obscure_fraction']*100)}% obscured)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: python degrade.py <pdf_file> [<pdf_file> ...]")
        print("Example: python degrade.py D01-clean.pdf D03-clean.pdf")
        sys.exit(1)

    for arg in sys.argv[1:]:
        path = Path(arg)
        if not path.exists():
            print(f"File not found: {path}")
            continue
        if path.suffix.lower() != ".pdf":
            print(f"Skipping non-PDF file: {path}")
            continue
        process_pdf(path)

    print("\nDone. Check your folder for -degraded.jpg and -blurry.jpg files.")
    print("Tip: open them at 100% zoom to judge whether they look realistic.")
    print("     If they look too clean, lower DEGRADED['jpeg_quality'] or increase blur_radius.")
    print("     If the blurry variant is unreadable, reduce BLURRY['blur_radius'] slightly.")


if __name__ == "__main__":
    main()