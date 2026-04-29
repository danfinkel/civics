#!/usr/bin/env python3
"""
Generate synthetic D01 variants, extract image attributes, validate four pre-screen
gates, and write plots + reports (no LLM inference).
"""

from __future__ import annotations

import argparse
import sys
import random
from pathlib import Path
from collections.abc import Iterable

import numpy as np
import pandas as pd

_EVAL_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _EVAL_DIR.parents[1]
if str(_EVAL_DIR) not in sys.path:
    sys.path.insert(0, str(_EVAL_DIR))

from real_photo_characterizer import extract_attributes
from PIL import Image, ImageDraw, ImageFilter

# --- Four-rule detector thresholds (calibrated on 34 real photos) ---
THR_ENTROPY = 5.15
# White region: flag when `white_region_ratio` is below this (document too small in frame).
# 0.10 was tight; 0.13 (lower end of 0.13–0.15) un-flags typical scale≈0.55 rows (~0.135 white);
# 0.14–0.15 would still flag those — use 0.13–0.15 only if you want stricter minimum coverage.
THR_WHITE = 0.13
THR_ASPECT = 0.74
# Rotation: only |angle| > THR_ROTATION_RETAKE blocks (any_gate / “retake”).
# Between THR_ROTATION_SOFT and retake: non-blocking soft warning (see ROTATION_SOFT_MESSAGE).
THR_ROTATION_SOFT = 25.0
THR_ROTATION_RETAKE = 50.0
ROTATION_SOFT_MESSAGE = (
    "try to hold your phone more directly above the document."
)

try:
    from scipy import ndimage

    _HAS_NDIMAGE = True
except ImportError:
    _HAS_NDIMAGE = False


# ---------------------------------------------------------------------------
# Gate evaluation
# ---------------------------------------------------------------------------


def evaluate_gates(a: dict) -> dict[str, bool]:
    he = float(a.get("histogram_entropy", 0) or 0)
    ra = float(a.get("rotation_angle", 0) or 0)
    far = float(a.get("frame_aspect_ratio", 1) or 1)
    wr = float(a.get("white_region_ratio", 0) or 0)
    ara = abs(ra)
    # Hard rotation gate: retake only when severely tilted (does not set any_gate in soft band).
    gate_rotation = ara > THR_ROTATION_RETAKE
    rotation_soft_warning = (THR_ROTATION_SOFT < ara <= THR_ROTATION_RETAKE) and not gate_rotation
    return {
        "gate_entropy": he >= THR_ENTROPY,
        "gate_rotation": gate_rotation,
        "rotation_soft_warning": rotation_soft_warning,
        "gate_aspect": far < THR_ASPECT,
        "gate_white": wr < THR_WHITE,
    }


def any_gate_fired(g: dict[str, bool]) -> bool:
    return any(
        g[k] for k in ("gate_entropy", "gate_rotation", "gate_aspect", "gate_white")
    )


def _relpo(p: Path) -> str:
    try:
        return str(p.resolve().relative_to(_REPO_ROOT))
    except ValueError:
        return str(p.resolve())


def base_passes_gates(a: dict) -> tuple[bool, list[str]]:
    g = evaluate_gates(a)
    bad = [k for k, v in g.items() if v]
    return len(bad) == 0, bad


# ---------------------------------------------------------------------------
# Image helpers (PIL)
# ---------------------------------------------------------------------------


def _make_solid_background(size: tuple[int, int], color: int = 180) -> Image.Image:
    return Image.new("RGB", size, (color, color, color))


def _make_noise_background(
    size: tuple[int, int], base_luminance: int = 160, noise_std: float = 20.0, seed: int = 42
) -> Image.Image:
    w, h = size
    rng = np.random.default_rng(seed)
    noise = rng.normal(float(base_luminance), noise_std, (h, w))
    noise = np.clip(noise, 0, 255).astype(np.uint8)
    return Image.fromarray(noise, mode="L").convert("RGB")


def _make_cluttered_background(size: tuple[int, int], seed: int = 42) -> Image.Image:
    w, h = size[0], size[1]
    rng = random.Random(seed)
    bg = Image.new("RGB", (w, h), (160, 155, 150))
    draw = ImageDraw.Draw(bg)
    for _ in range(40):
        x1 = rng.randint(0, max(0, w - 1))
        y1 = rng.randint(0, max(0, h - 1))
        x2 = min(w, x1 + rng.randint(50, 300))
        y2 = min(h, y1 + rng.randint(30, 200))
        color = tuple(rng.randint(80, 220) for _ in range(3))
        draw.rectangle([x1, y1, x2, y2], fill=color)
    for _ in range(20):
        x, y = rng.randint(0, max(0, w - 1)), rng.randint(0, max(0, h - 1))
        r = rng.randint(20, 100)
        color = tuple(rng.randint(80, 220) for _ in range(3))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return bg


def _composite_onto(
    base_rgb: Image.Image, background: Image.Image, scale: float
) -> Image.Image:
    doc_w = max(1, int(base_rgb.width * scale))
    doc_h = max(1, int(base_rgb.height * scale))
    doc_resized = base_rgb.resize((doc_w, doc_h), Image.Resampling.LANCZOS)
    bg = background.resize(base_rgb.size, Image.Resampling.BICUBIC).convert("RGB")
    x = (bg.width - doc_w) // 2
    y = (bg.height - doc_h) // 2
    bg.paste(doc_resized, (x, y))
    return bg


def _rotate_with_background(
    img: Image.Image, angle: float, bg_color: tuple[int, int, int] = (200, 200, 200)
) -> Image.Image:
    img = img.convert("RGB")
    diagonal = int(np.sqrt(img.width**2 + img.height**2)) + 20
    canvas = Image.new("RGB", (diagonal, diagonal), bg_color)
    x = (diagonal - img.width) // 2
    y = (diagonal - img.height) // 2
    canvas.paste(img, (x, y))
    rotated = canvas.rotate(angle, expand=False, resample=Image.BICUBIC, fillcolor=bg_color)
    left = (rotated.width - img.width) // 2
    top = (rotated.height - img.height) // 2
    return rotated.crop((left, top, left + img.width, top + img.height))


def _crop_bottom(img: Image.Image, keep_fraction: float) -> Image.Image:
    keep_height = max(1, int(img.height * keep_fraction))
    return img.crop((0, 0, img.width, keep_height))


def _crop_left(img: Image.Image, keep_fraction: float) -> Image.Image:
    keep_width = max(1, int(img.width * keep_fraction))
    return img.crop((img.width - keep_width, 0, img.width, img.height))


def _motion_blur(img: Image.Image, length: int, angle_deg: float) -> Image.Image:
    if length < 1 or not _HAS_NDIMAGE:
        return img.copy()
    k = max(3, int(length) | 1)
    kernel = np.zeros((k, k), dtype=np.float64)
    ang = np.radians(angle_deg)
    c = k // 2
    for t in range(-c, c + 1):
        xi = int(round(c + t * np.cos(ang + np.pi / 2)))
        yi = int(round(c + t * np.sin(ang + np.pi / 2)))
        if 0 <= xi < k and 0 <= yi < k:
            kernel[yi, xi] = 1.0
    s = kernel.sum()
    if s < 1e-9:
        kernel[c, c] = 1.0
    else:
        kernel /= s
    arr = np.asarray(img.convert("RGB"), dtype=np.float64)
    out = np.empty_like(arr)
    for ch in range(3):
        out[:, :, ch] = ndimage.convolve(arr[:, :, ch], kernel, mode="nearest")
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------


def generate_distance_variants(
    base_img: Image.Image, out_dir: Path, rows: list[dict]
) -> None:
    sub = out_dir / "distance"
    sub.mkdir(parents=True, exist_ok=True)
    scales = [1.0, 0.85, 0.70, 0.55, 0.45, 0.35, 0.25, 0.20, 0.15]
    size = base_img.size
    rgb = base_img.convert("RGB")
    bgs: list[tuple[str, Image.Image]] = [
        ("solid_gray", _make_solid_background(size, 180)),
        ("desk_texture", _make_noise_background(size, 160, 20)),
        ("cluttered", _make_cluttered_background(size, 42)),
    ]
    for bg_name, bg in bgs:
        for sc in scales:
            comp = _composite_onto(rgb, bg, sc)
            fn = f"distance_{bg_name}_{sc:.2f}.jpg"
            p = sub / fn
            comp.save(p, quality=95)
            a = extract_attributes(p)
            g = evaluate_gates(a)
            rows.append(
                {
                    "family": "distance",
                    "background": bg_name,
                    "scale": sc,
                    "param": "scale",
                    "param_value": sc,
                    "path": _relpo(p),
                    "filename": fn,
                    **a,
                    **{k: v for k, v in g.items()},
                    "any_gate": any_gate_fired(g),
                }
            )


def generate_rotation_variants(
    base_img: Image.Image, out_dir: Path, rows: list[dict]
) -> None:
    sub = out_dir / "rotation"
    sub.mkdir(parents=True, exist_ok=True)
    angles: list[float] = sorted(
        {
            0.0,
            5, -5, 10, -10, 15, -15, 20, -20, 25, -25, 30, -30, 35, -35, 40, -40,
            45, 55, 65, 75, 90, -50, -60,
        }
    )
    rgb = base_img.convert("RGB")
    for ang in angles:
        out = _rotate_with_background(rgb, float(ang), (200, 200, 200))
        fn = f"rotation_{int(round(ang)):+04d}deg.jpg"
        p = sub / fn
        out.save(p, quality=95)
        a = extract_attributes(p)
        g = evaluate_gates(a)
        rows.append(
            {
                "family": "rotation",
                "input_angle_deg": ang,
                "param": "input_angle_deg",
                "param_value": ang,
                "path": _relpo(p),
                "filename": fn,
                **a,
                **{k: v for k, v in g.items()},
                "any_gate": any_gate_fired(g),
            }
        )


def generate_crop_variants(base_img: Image.Image, out_dir: Path, rows: list[dict]) -> None:
    sub = out_dir / "crop"
    sub.mkdir(parents=True, exist_ok=True)
    keep_fractions = [1.0, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.60, 0.50, 0.40]
    rgb = base_img.convert("RGB")
    for kf in keep_fractions:
        if kf >= 0.999:
            p = sub / f"crop_bottom_{kf:.2f}.jpg"
            rgb.save(p, quality=95)
        else:
            c = _crop_bottom(rgb, kf)
            fn = f"crop_bottom_{kf:.2f}.jpg"
            p = sub / fn
            c.save(p, quality=95)
        a = extract_attributes(p)
        g = evaluate_gates(a)
        rows.append(
            {
                "family": "crop_bottom",
                "keep_fraction": kf,
                "param": "keep_fraction",
                "param_value": kf,
                "path": _relpo(p),
                "filename": p.name,
                **a,
                **{k: v for k, v in g.items()},
                "any_gate": any_gate_fired(g),
            }
        )
    for kf in keep_fractions:
        if kf >= 0.999:
            continue
        c = _crop_left(rgb, kf)
        fn = f"crop_left_{kf:.2f}.jpg"
        p = sub / fn
        c.save(p, quality=95)
        a = extract_attributes(p)
        g = evaluate_gates(a)
        rows.append(
            {
                "family": "crop_left",
                "keep_fraction": kf,
                "param": "keep_fraction",
                "param_value": kf,
                "path": _relpo(p),
                "filename": fn,
                **a,
                **{k: v for k, v in g.items()},
                "any_gate": any_gate_fired(g),
            }
        )


def generate_blur_variants(
    base_img: Image.Image, out_dir: Path, rows: list[dict]
) -> None:
    sub = out_dir / "blur"
    sub.mkdir(parents=True, exist_ok=True)
    rgb = base_img.convert("RGB")
    gaussian_sigmas = [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 7.0]
    for s in gaussian_sigmas:
        if s <= 0:
            p = sub / f"blur_gaussian_s{float(s):.1f}.jpg"
            rgb.save(p, quality=95)
        else:
            blurred = rgb.filter(ImageFilter.GaussianBlur(radius=s))
            fn = f"blur_gaussian_s{float(s):.1f}.jpg"
            p = sub / fn
            blurred.save(p, quality=95)
        a = extract_attributes(p)
        g = evaluate_gates(a)
        rows.append(
            {
                "family": "blur_gaussian",
                "sigma": s,
                "param": "sigma",
                "param_value": s,
                "path": _relpo(p),
                "filename": p.name,
                **a,
                **{k: v for k, v in g.items()},
                "any_gate": any_gate_fired(g),
            }
        )
    if not _HAS_NDIMAGE:
        return
    motion_lengths = [0, 5, 10, 15, 20, 30, 40]
    motion_angles = [0, 45, 90]
    for L in motion_lengths:
        for ang in motion_angles:
            if L < 1:
                outi = rgb.copy()
            else:
                outi = _motion_blur(rgb, L, float(ang))
            fn = f"blur_motion_l{int(L)}_a{int(ang)}.jpg"
            p = sub / fn
            outi.save(p, quality=95)
            a = extract_attributes(p)
            g = evaluate_gates(a)
            rows.append(
                {
                    "family": "blur_motion",
                    "motion_length": L,
                    "motion_angle": ang,
                    "param": "motion_length",
                    "param_value": L,
                    "path": _relpo(p),
                    "filename": fn,
                    **a,
                    **{k: v for k, v in g.items()},
                    "any_gate": any_gate_fired(g),
                }
            )


# ---------------------------------------------------------------------------
# Analysis & outputs
# ---------------------------------------------------------------------------


import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def _first_fire(
    df: pd.DataFrame, param_col: str, gate_col: str, sort_asc: bool = True
) -> float | None:
    s = df.sort_values(param_col, ascending=sort_asc)
    fired = s[s[gate_col] == True]  # noqa: E712
    if len(fired) == 0:
        return None
    return float(fired.iloc[0][param_col])


def write_plots(df: pd.DataFrame, plot_dir: Path) -> None:
    plot_dir.mkdir(parents=True, exist_ok=True)
    d1 = df[df["family"] == "distance"].copy()
    if len(d1):
        fig, axes = plt.subplots(1, 2, figsize=(12, 4))
        for bg in d1["background"].dropna().unique():
            sub = d1[d1["background"] == bg].sort_values("scale")
            axes[0].plot(
                sub["scale"],
                sub["histogram_entropy"],
                marker="o",
                label=bg,
            )
            axes[1].plot(
                sub["scale"],
                sub["white_region_ratio"],
                marker="o",
                label=bg,
            )
        axes[0].axhline(THR_ENTROPY, color="r", ls="--", label=f"entropy ≥ {THR_ENTROPY}")
        axes[0].set_xlabel("Document scale (fraction of long side)")
        axes[0].set_ylabel("histogram_entropy")
        axes[0].set_title("Entropy vs scale (Family 1)")
        axes[0].legend(fontsize=7)
        axes[1].axhline(THR_WHITE, color="r", ls="--", label=f"white < {THR_WHITE} flags")
        axes[1].set_xlabel("Document scale")
        axes[1].set_ylabel("white_region_ratio")
        axes[1].set_title("White region ratio vs scale")
        axes[1].legend(fontsize=7)
        fig.tight_layout()
        fig.savefig(plot_dir / "family1_distance.png", dpi=150)
        plt.close(fig)

    r = df[df["family"] == "rotation"].copy()
    if len(r):
        r = r.sort_values("input_angle_deg")
        fig, ax = plt.subplots(figsize=(7, 4))
        ax.plot(
            r["input_angle_deg"],
            r["rotation_angle"],
            "o-",
            label="extracted rotation_angle (Hough)",
        )
        ax.plot(
            r["input_angle_deg"],
            r["input_angle_deg"],
            "k--",
            alpha=0.3,
            label="y = x (ideal)",
        )
        ax.axhline(
            THR_ROTATION_RETAKE,
            color="r",
            ls="--",
            label=f"±{THR_ROTATION_RETAKE}° retake (|angle|> {THR_ROTATION_RETAKE}°)",
        )
        ax.axhline(-THR_ROTATION_RETAKE, color="r", ls="--")
        ax.axhline(
            THR_ROTATION_SOFT,
            color="darkorange",
            ls=":",
            label=f"±{THR_ROTATION_SOFT}° soft lower",
        )
        ax.axhline(-THR_ROTATION_SOFT, color="darkorange", ls=":")
        ax.set_xlabel("Input angle (°)")
        ax.set_ylabel("rotation_angle (extracted)")
        ax.set_title("Family 2: extracted angle vs input")
        ax.legend()
        fig.tight_layout()
        fig.savefig(plot_dir / "family2_rotation.png", dpi=150)
        plt.close(fig)

        fig2, ax2 = plt.subplots(figsize=(7, 4))
        ax2.plot(
            r["input_angle_deg"],
            r["rotation_angle"].abs(),
            "o-",
        )
        ax2.set_title("Abs extracted vs input (same row order as left)")
        ax2.axhline(
            THR_ROTATION_RETAKE,
            color="r",
            ls="--",
            label=f"retake if |angle| > {THR_ROTATION_RETAKE}°",
        )
        ax2.axhline(
            THR_ROTATION_SOFT,
            color="darkorange",
            ls=":",
            label=f"soft: ({THR_ROTATION_SOFT}°, {THR_ROTATION_RETAKE}°]",
        )
        ax2.set_xlabel("Input angle (°)")
        ax2.set_ylabel("|rotation_angle|")
        ax2.legend()
        fig2.tight_layout()
        fig2.savefig(plot_dir / "family2_rotation_abs.png", dpi=150)
        plt.close(fig2)

    c = df[df["family"] == "crop_bottom"].copy()
    if len(c):
        fig, axes = plt.subplots(1, 2, figsize=(11, 4))
        c = c.sort_values("keep_fraction", ascending=False)
        axes[0].plot(
            c["keep_fraction"],
            c["frame_aspect_ratio"],
            "o-",
        )
        axes[0].axhline(THR_ASPECT, color="r", ls="--", label=f"aspect < {THR_ASPECT} flags")
        axes[0].set_xlabel("keep_fraction (from top)")
        axes[0].set_ylabel("frame_aspect_ratio (w/h)")
        axes[0].set_title("Crop bottom: aspect vs keep")
        axes[0].legend()
        axes[1].plot(
            c["keep_fraction"],
            c["document_touches_edge"],
            "o-",
        )
        axes[1].set_xlabel("keep_fraction")
        axes[1].set_ylabel("document_touches_edge")
        fig.tight_layout()
        fig.savefig(plot_dir / "family3_crop_bottom.png", dpi=150)
        plt.close(fig)

    g = df[df["family"] == "blur_gaussian"].copy()
    if len(g):
        g = g.sort_values("sigma")
        fig, axes = plt.subplots(1, 2, figsize=(11, 4))
        axes[0].plot(g["sigma"], g["laplacian_variance"], "o-")
        axes[0].set_xlabel("Gaussian σ")
        axes[0].set_ylabel("laplacian_variance")
        axes[0].set_title("Blur family: sharpness drop")
        any_g = g["any_gate"]
        axes[1].bar(range(len(g)), any_g.astype(int), tick_label=[f"{s}" for s in g["sigma"]])
        axes[1].set_xlabel("σ")
        axes[1].set_ylabel("any four-rule gate fired")
        fig.tight_layout()
        fig.savefig(plot_dir / "family4_blur_gaussian.png", dpi=150)
        plt.close(fig)


def write_false_positive_report(df: pd.DataFrame, path: Path) -> None:
    b = df[df["family"].isin(["blur_gaussian", "blur_motion"])].copy()
    bad = b[b["any_gate"] == True]  # noqa: E712
    lines = [
        "False-positive check: four-rule detector on blur-only variants",
        f"Total blur rows: {len(b)}",
        f"Rows with any gate fired: {len(bad)}",
        "",
    ]
    gsv = df[df["family"] == "blur_gaussian"]
    for cap in (2.5, 3.0):
        sub = gsv[gsv["sigma"] <= cap]
        bad_sub = sub[sub["any_gate"] == True]  # noqa: E712
        lines.append(
            f"Gaussian blur σ ≤ {cap} (spike 'blurry' regime): "
            f"{'FAIL' if len(bad_sub) else 'OK — no four-rule gate'} "
            f"({len(bad_sub)} variant(s) with any gate)"
        )
    lines.append("")
    if len(bad) == 0:
        lines.append("No spurious flags — OK for this sweep.")
    else:
        lines.append("The following variants triggered at least one gate (review thresholds):")
        for _, r in bad.iterrows():
            gates = [k for k in ("gate_entropy", "gate_rotation", "gate_aspect", "gate_white") if r.get(k)]
            lines.append(f"  {r.get('filename')}  gates={gates}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _param_range_when(
    sub: pd.DataFrame, param: str, gate: str
) -> tuple[float | None, float | None]:
    t = sub[sub[gate] == True]  # noqa: E712
    if len(t) == 0:
        return None, None
    return float(t[param].min()), float(t[param].max())


def write_summary(df: pd.DataFrame, path: Path, base_ok: bool) -> None:
    lines: list[str] = [
        "# Synthetic threshold validation",
        "",
        f"Base image passed gate self-check: **{base_ok}**",
        "",
        "Thresholds:",
        f"- `histogram_entropy` ≥ {THR_ENTROPY}  → flag (blocks)",
        f"- `|rotation_angle|` > {THR_ROTATION_RETAKE}  → retake (hard gate, blocks)",
        f"- (non-blocking) {THR_ROTATION_SOFT}° < `|rotation_angle|` ≤ {THR_ROTATION_RETAKE}°  → "
        f'soft message: “{ROTATION_SOFT_MESSAGE}”  (`rotation_soft_warning` in CSV)',
        f"- `frame_aspect_ratio` < {THR_ASPECT}  → flag (blocks)",
        f"- `white_region_ratio` < {THR_WHITE}  → flag (blocks, document too small in frame)",
        "",
        "## Summary table",
        "",
        "| Family | Parameter | Threshold | First fire (approx.) | Notes |",
        "|--------|-----------|-----------|----------------------|-------|",
    ]
    for fam, pcol, gcol, note in [
        ("distance", "scale", "gate_entropy", "per background in detail below"),
        ("distance", "scale", "gate_white", "per background"),
        ("rotation", "input_angle_deg", "gate_rotation", "Hough vs applied angle"),
        ("crop_bottom", "keep_fraction", "gate_aspect", "w/h after bottom crop"),
        ("blur_gaussian", "sigma", "any_gate", "should stay false — negative control"),
    ]:
        sub = df[df["family"] == fam] if fam != "distance" else df[df["family"] == "distance"]
        if fam == "distance":
            ff = "see below"
        elif fam == "rotation" and len(sub):
            sub = sub.assign(_a=sub["input_angle_deg"].abs()).sort_values("_a")
            fr = sub[sub[gcol] == True]  # noqa: E712
            ff = f"{fr.iloc[0][pcol]}" if len(fr) else "—"
        elif len(sub):
            if fam == "crop_bottom":
                s2 = sub.sort_values(pcol, ascending=False)
            elif fam == "blur_gaussian":
                s2 = sub.sort_values("sigma", ascending=True)
            else:
                s2 = sub.sort_values(pcol, ascending=False)
            fr = s2[s2[gcol] == True]  # noqa: E712
            ff = f"{fr.iloc[0][pcol]}" if len(fr) else "—"
        else:
            ff = "—"
        thr = (
            f"entropy≥{THR_ENTROPY}"
            if gcol == "gate_entropy"
            else (
                f"abs(rot)>{THR_ROTATION_RETAKE}"
                if gcol == "gate_rotation"
                else (
                    f"aspect<{THR_ASPECT}"
                    if gcol == "gate_aspect"
                    else (f"white<{THR_WHITE}" if gcol == "gate_white" else "none (blur)")
                )
            )
        )
        lines.append(f"| {fam} | {pcol} | {thr} | {ff} | {note} |")
    lines.extend(
        [
            "",
            "## D01 crop & deadline (visual estimate)",
            "The deadline / response box is typically in the **lower half** of a full-page notice. `crop_bottom` with `keep_fraction` below ~**0.55–0.65** risks removing fields that sit near the bottom; confirm on your base JPEG.",
            "",
            "## First crossing (approximate first parameter where a gate becomes True, along sweep order)",
            "",
        ]
    )
    for fam, pcol, gcol in [
        ("distance", "scale", "gate_entropy"),
        ("distance", "scale", "gate_white"),
    ]:
        sub = df[df["family"] == fam]
        for bg in sub["background"].dropna().unique():
            ssub = sub[sub["background"] == bg].sort_values("scale")
            ff = _first_fire(ssub, "scale", gcol, sort_asc=False)
            lines.append(
                f"- {fam} / {bg} / {gcol}: first at scale = **{ff}** (sweep 1.0 → 0.15)" if ff is not None else f"- {fam} / {bg} / {gcol}: no fire in sweep"
            )

    rot = df[df["family"] == "rotation"].copy()
    if len(rot):
        rot["_abs_in"] = rot["input_angle_deg"].abs()
        rot = rot.sort_values("_abs_in", ascending=True)
        fr = rot[rot["gate_rotation"] == True]  # noqa: E712
        ffr = float(fr.iloc[0]["input_angle_deg"]) if len(fr) else None
        lines.append(
            f"- rotation / gate_rotation (retake): first at input angle **{ffr}** "
            "(sweep by increasing |input_angle_deg|; Hough may differ from applied angle)"
        )
        if "rotation_soft_warning" in rot.columns:
            frs = rot[rot["rotation_soft_warning"] == True]  # noqa: E712
            ffrs = float(frs.iloc[0]["input_angle_deg"]) if len(frs) else None
            if ffrs is not None:
                lines.append(
                    f"- rotation / rotation_soft_warning: first at input angle **{ffrs}** "
                    "(sweep by increasing |input|)"
                )

    cb = df[df["family"] == "crop_bottom"].sort_values("keep_fraction", ascending=False)
    ffa = _first_fire(cb, "keep_fraction", "gate_aspect", sort_asc=False)
    lines.append(
        f"- crop_bottom / gate_aspect: first at keep_fraction **{ffa}**" if ffa is not None else "- crop_bottom / gate_aspect: no fire"
    )

    lines.extend(["", "## Boundary characterization (min–max parameter where gate is True)", ""])
    dist = df[df["family"] == "distance"]
    for bg in dist["background"].dropna().unique():
        ss = dist[dist["background"] == bg]
        for gname, gc in [("gate_entropy", "gate_entropy"), ("gate_white", "gate_white")]:
            lo, hi = _param_range_when(ss, "scale", gc)
            lines.append(
                f"- distance / {bg} / {gname}: scale ∈ [{lo}, {hi}] (None = never fired)"
            )
    rot2 = df[df["family"] == "rotation"]
    if len(rot2):
        lo, hi = _param_range_when(rot2, "input_angle_deg", "gate_rotation")
        lines.append(f"- rotation / gate_rotation: input_angle_deg ∈ [{lo}, {hi}] when retake")
        if "rotation_soft_warning" in rot2.columns:
            lo2, hi2 = _param_range_when(rot2, "input_angle_deg", "rotation_soft_warning")
            lines.append(
                f"- rotation / rotation_soft_warning: input_angle_deg ∈ [{lo2}, {hi2}] when soft"
            )
    cb2 = df[df["family"] == "crop_bottom"]
    if len(cb2):
        lo, hi = _param_range_when(cb2, "keep_fraction", "gate_aspect")
        lines.append(f"- crop_bottom / gate_aspect: keep_fraction ∈ [{lo}, {hi}] when aspect gate fired")

    lines.append("")
    lines.append("## Notes")
    lines.append(
        "- `rotation_angle` is from Hough (see `estimate_rotation`); it may not match input angle 1:1—use this plot to judge shipping thresholds."
    )
    if not _HAS_NDIMAGE:
        lines.append("- Motion blur was skipped (scipy `ndimage` not available).")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


_PHOTO_CSV_CANDIDATES: tuple[tuple[Path, Path], ...] = (
    (
        _EVAL_DIR / "results" / "real_photo_analysis" / "photo_attributes.csv",
        _EVAL_DIR / "results" / "real_photo_analysis" / "converted",
    ),
    (
        _EVAL_DIR / "results" / "blur_testing" / "photo_attributes.csv",
        _EVAL_DIR / "results" / "blur_testing" / "converted",
    ),
)


def resolve_base_image(user_base: Path) -> Path:
    if user_base.is_file():
        a = extract_attributes(user_base)
        ok, _b = base_passes_gates(a)
        if ok:
            return user_base.resolve()
    for csv_path, conv in _PHOTO_CSV_CANDIDATES:
        if not csv_path.is_file() or not conv.is_dir():
            continue
        t = pd.read_csv(csv_path)
        if "label" not in t.columns or "filename" not in t.columns:
            continue
        t = t[t["label"] == "pass"]
        for _, row in t.iterrows():
            fn = row["filename"]
            c = conv / fn
            if c.is_file():
                a = extract_attributes(c)
                ok, _ = base_passes_gates(a)
                if ok:
                    return c.resolve()
    raise SystemExit(
        "No suitable base image: use --base with a JPEG that passes all four gates, "
        "or run real_photo_characterizer to produce photo_attributes.csv + converted/ under "
        "results/real_photo_analysis/ or results/blur_testing/."
    )


FAMILY_FUNCS = {
    "distance": generate_distance_variants,
    "rotation": generate_rotation_variants,
    "crop": generate_crop_variants,
    "blur": generate_blur_variants,
    "all": None,
}


def main() -> None:
    p = argparse.ArgumentParser(description="Synthetic threshold validation (attributes only)")
    p.add_argument(
        "--base",
        type=Path,
        default=_REPO_ROOT / "spike" / "artifacts" / "clean" / "jpeg" / "D01-clean.jpg",
    )
    p.add_argument(
        "--out",
        type=Path,
        default=_EVAL_DIR / "results" / "synthetic_validation",
    )
    p.add_argument(
        "--families",
        type=str,
        default="all",
        help="Comma list: distance,rotation,crop,blur,all",
    )
    args = p.parse_args()
    out = args.out.resolve()
    vdir = out / "variants"
    vdir.mkdir(parents=True, exist_ok=True)

    base = resolve_base_image(args.base)
    base_img = Image.open(base).convert("RGB")
    a0 = extract_attributes(base)
    base_ok, bad = base_passes_gates(a0)
    _g0 = evaluate_gates(a0)
    (out / "base_gate_check.txt").write_text(
        f"file={base}\nok={base_ok}\nfailed_gates={bad}\nattrs_histogram_entropy={a0.get('histogram_entropy')}\n"
        f"rotation_angle={a0.get('rotation_angle')}\nframe_aspect_ratio={a0.get('frame_aspect_ratio')}\n"
        f"white_region_ratio={a0.get('white_region_ratio')}\n"
        f"rotation_soft_warning={_g0.get('rotation_soft_warning')}\n"
        f"soft_message={ROTATION_SOFT_MESSAGE!r}\n",
        encoding="utf-8",
    )
    if not base_ok and args.base.resolve() == base:
        # Only strict fail if user explicitly wanted this file; resolve_base already swapped
        pass

    want = {x.strip() for x in args.families.split(",")}
    if "all" in want:
        want = {"distance", "rotation", "crop", "blur"}

    rows: list[dict] = []
    for name in want:
        if name not in FAMILY_FUNCS or (name == "all"):
            continue
        FAMILY_FUNCS[name](base_img, vdir, rows)  # type: ignore[misc]

    df = pd.DataFrame(rows)
    out.mkdir(parents=True, exist_ok=True)
    if len(df):
        df.to_csv(out / "variant_attributes.csv", index=False)
    else:
        (out / "variant_attributes.csv").write_text("")

    write_plots(df, out / "threshold_plots")
    write_false_positive_report(df, out / "false_positive_report.txt")
    write_summary(df, out / "summary.md", base_ok)
    print(f"Wrote: {out / 'variant_attributes.csv'}")
    print(f"Plots: {out / 'threshold_plots'}")


if __name__ == "__main__":
    main()
