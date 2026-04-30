#!/usr/bin/env python3
"""
Rasterize spike clean PDFs to JPEG for eval (variant clean_jpeg).

Writes one image per artifact: spike/artifacts/clean/<ID>-clean-raster.jpg
All PDF pages are stacked vertically at configurable DPI (default 120).

Dependencies: pip install pymupdf pillow
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CLEAN_DIR = REPO_ROOT / "spike" / "artifacts" / "clean"


def pdf_to_stacked_jpeg(
    pdf_path: Path,
    out_path: Path,
    *,
    dpi: float,
    jpeg_quality: int,
) -> None:
    import fitz  # PyMuPDF
    from PIL import Image

    doc = fitz.open(pdf_path)
    scale = dpi / 72.0
    mat = fitz.Matrix(scale, scale)
    images: list[Image.Image] = []
    try:
        for i in range(doc.page_count):
            pix = doc.load_page(i).get_pixmap(matrix=mat, alpha=False)
            mode = "RGB" if pix.n == 3 else "RGBA"
            im = Image.frombytes(mode, (pix.width, pix.height), pix.samples)
            if mode == "RGBA":
                im = im.convert("RGB")
            images.append(im)
    finally:
        doc.close()

    if not images:
        raise RuntimeError(f"No pages in {pdf_path}")

    w = max(im.width for im in images)
    h = sum(im.height for im in images)
    canvas = Image.new("RGB", (w, h), (255, 255, 255))
    y = 0
    for im in images:
        canvas.paste(im, (0, y))
        y += im.height

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "JPEG", quality=jpeg_quality, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--dpi",
        type=float,
        default=120.0,
        help="Rasterization DPI (default: 120)",
    )
    ap.add_argument(
        "--quality",
        type=int,
        default=90,
        help="JPEG quality 1-95 (default: 90)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="List PDFs that would be converted",
    )
    args = ap.parse_args()

    pdfs = sorted(CLEAN_DIR.glob("*-clean.pdf"))
    if not pdfs:
        print(f"No *-clean.pdf under {CLEAN_DIR}", file=sys.stderr)
        return 1

    for pdf in pdfs:
        stem = pdf.stem  # e.g. D01-clean
        out = CLEAN_DIR / f"{stem}-raster.jpg"
        if args.dry_run:
            print(f"{pdf.name} -> {out.name}")
            continue
        try:
            pdf_to_stacked_jpeg(
                pdf, out, dpi=args.dpi, jpeg_quality=min(95, max(1, args.quality))
            )
            print(f"Wrote {out.relative_to(REPO_ROOT)}")
        except Exception as e:
            print(f"ERROR {pdf.name}: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
