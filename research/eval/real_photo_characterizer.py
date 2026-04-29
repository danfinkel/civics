#!/usr/bin/env python3
"""
Real-world image quality characterization for D01: attribute extraction + LLM
pass/fail labeling + statistical analysis (Cohen's d, logistic regression, LOO).
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import shutil
import sys
import threading
import time
from pathlib import Path

import numpy as np
import pandas as pd
import requests
from scipy import stats
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import LeaveOneOut
from sklearn.preprocessing import StandardScaler

# research/eval on path when launched from repo root
_EVAL_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _EVAL_DIR.parents[2]
_DEFAULT_RESULT_DIR = _REPO_ROOT / "research" / "eval" / "results" / "real_photo_analysis"
if str(_EVAL_DIR) not in sys.path:
    sys.path.insert(0, str(_EVAL_DIR))

from prompt_conditions import build_prompt_semantic
from runner import (
    load_ground_truth,
    parse_with_retry,
    run_inference,
    score_prompt_ablation_row,
)

try:
    import cv2
except ImportError as e:
    raise SystemExit(
        "OpenCV is required. Install: pip install opencv-python (or opencv-python-headless)"
    ) from e

try:
    from pillow_heif import register_heif_opener
except ImportError as e:
    raise SystemExit(
        "pillow-heif is required for HEIC. Install: pip install pillow-heif"
    ) from e
try:
    from PIL import Image
except ImportError as e:
    raise SystemExit("Pillow is required. Install: pip install pillow") from e

register_heif_opener()

# Production D01 semantic prompt (matches prompt_conditions.build_prompt_semantic).
D01_SEMANTIC_PROMPT = build_prompt_semantic()

OLLAMA_BASE = "http://127.0.0.1:11434"
DEFAULT_OLLAMA_MODEL = "gemma4:e4b"
# Match web_demo/inference.py — full iPhone resolution is far too large for local vision
# and will look “hung” for many minutes per request.
DEFAULT_OLLAMA_MAX_LONG_EDGE = 1024
DEFAULT_OLLAMA_TIMEOUT_S = 600.0

ATTRIBUTE_COLS = [
    # Sharpness, luminance, file (existing)
    "laplacian_variance",
    "tenengrad_variance",
    "laplacian_variance_center",
    "tenengrad_variance_center",
    "mean_luminance",
    "luminance_std",
    "histogram_entropy",
    "michelson_contrast",
    "rms_contrast",
    "rotation_angle",
    "noise_estimate",
    "file_size_kb",
    # Group 1 — document coverage
    "white_region_ratio",
    "document_coverage_ratio",
    "edge_density",
    "center_edge_density",
    # Group 2 — shadow / uneven lighting
    "shadow_ratio",
    "quadrant_luminance_variance",
    "min_quadrant_luminance",
    "quadrant_luminance_ratio",
    # Group 3 — directional blur
    "horizontal_blur_ratio",
    "gradient_direction_entropy",
    # Group 4 — document boundary / frame
    "document_touches_edge",
    "document_aspect_ratio",
    "frame_aspect_ratio",
    "document_center_offset",
]

PHOTO_EXTS = {".heic", ".heif", ".HEIC", ".HEIF", ".jpg", ".jpeg", ".JPG", ".JPEG"}


def laplacian_variance(gray_f: np.ndarray) -> float:
    lap = cv2.Laplacian(gray_f, cv2.CV_64F)
    return float(np.var(lap))


def tenengrad_variance(gray: np.ndarray) -> float:
    gx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
    return float(np.mean(gx**2 + gy**2))


def center_crop(img: np.ndarray, fraction: float = 0.6) -> np.ndarray:
    h, w = img.shape[:2]
    mh = int(h * (1 - fraction) / 2)
    mw = int(w * (1 - fraction) / 2)
    return img[mh : h - mh, mw : w - mw]


def michelson_contrast(gray_f: np.ndarray) -> float:
    mn, mx = gray_f.min(), gray_f.max()
    if mx + mn == 0:
        return 0.0
    return float((mx - mn) / (mx + mn))


def noise_estimate(gray: np.ndarray) -> float:
    blurred = cv2.GaussianBlur(gray, (0, 0), 1.0)
    diff = gray.astype(np.float64) - blurred.astype(np.float64)
    return float(np.std(diff))


def estimate_rotation(gray: np.ndarray) -> float:
    edges = cv2.Canny(gray, 50, 150, apertureSize=3)
    lines = cv2.HoughLines(edges, 1, np.pi / 180, threshold=100)
    if lines is None:
        return 0.0
    angles = []
    for line in lines[:20]:
        rho, theta = line[0]
        angle = np.degrees(theta) - 90
        if abs(angle) < 45:
            angles.append(angle)
    return float(np.median(angles)) if angles else 0.0


def white_region_ratio(gray: np.ndarray, white_threshold: int = 200) -> float:
    _, thresh = cv2.threshold(gray, white_threshold, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return 0.0
    largest = max(contours, key=cv2.contourArea)
    frame_area = gray.shape[0] * gray.shape[1]
    return float(cv2.contourArea(largest)) / float(frame_area)


def document_coverage_ratio(gray: np.ndarray) -> float:
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 30, 100)
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return 0.0
    largest = max(contours, key=cv2.contourArea)
    hull = cv2.convexHull(largest)
    frame_area = gray.shape[0] * gray.shape[1]
    return float(cv2.contourArea(hull)) / float(frame_area)


def edge_density_full(gray: np.ndarray) -> float:
    edges = cv2.Canny(gray, 50, 150)
    return float(np.sum(edges > 0)) / float(edges.size)


def edge_density_center(gray: np.ndarray) -> float:
    crop = center_crop(gray, fraction=0.6)
    edges = cv2.Canny(crop, 50, 150)
    return float(np.sum(edges > 0)) / float(edges.size)


def shadow_features(gray: np.ndarray) -> dict:
    h, w = gray.shape
    median_lum = float(np.median(gray))
    std_lum = float(np.std(gray))
    shadow_threshold = median_lum - 1.5 * std_lum
    shadow_ratio = float(np.sum(gray < shadow_threshold)) / float(gray.size)

    quads = [
        gray[: h // 2, : w // 2],
        gray[: h // 2, w // 2 :],
        gray[h // 2 :, : w // 2],
        gray[h // 2 :, w // 2 :],
    ]
    quad_means = [float(np.mean(q)) for q in quads]
    quad_var = float(np.var(quad_means))
    min_quad = float(min(quad_means))
    max_quad = float(max(quad_means))
    quad_ratio = min_quad / max_quad if max_quad > 0 else 1.0

    return {
        "shadow_ratio": shadow_ratio,
        "quadrant_luminance_variance": quad_var,
        "min_quadrant_luminance": min_quad,
        "quadrant_luminance_ratio": round(quad_ratio, 4),
    }


def directional_blur_features(gray: np.ndarray) -> dict:
    gx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
    h_energy = float(np.mean(gx**2))
    v_energy = float(np.mean(gy**2))
    h_ratio = h_energy / (v_energy + 1e-10)

    magnitude = np.sqrt(gx**2 + gy**2)
    flat = magnitude.ravel()
    pct = float(np.percentile(flat, 70))
    strong = magnitude > pct
    if np.count_nonzero(strong) < 64:
        strong = magnitude > float(np.median(flat))
    if not np.any(strong):
        return {
            "horizontal_blur_ratio": round(h_ratio, 4),
            "gradient_direction_entropy": 0.0,
        }
    ang = np.degrees(np.arctan2(gy[strong], gx[strong])) % 360.0
    hist, _ = np.histogram(ang, bins=36, range=(0.0, 360.0))
    hist = hist.astype(np.float64) + 1e-10
    hist /= hist.sum()
    direction_entropy = float(-np.sum(hist * np.log2(hist)))

    return {
        "horizontal_blur_ratio": round(h_ratio, 4),
        "gradient_direction_entropy": round(direction_entropy, 4),
    }


def document_boundary_features(gray: np.ndarray) -> dict:
    h, w = gray.shape
    frame_aspect = round(w / h, 4) if h > 0 else 1.0
    _, thresh = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        return {
            "document_touches_edge": 0,
            "document_aspect_ratio": 0.0,
            "frame_aspect_ratio": frame_aspect,
            "document_center_offset": 1.0,
        }

    largest = max(contours, key=cv2.contourArea)
    x, y, cw, ch = cv2.boundingRect(largest)
    touches = int(
        x <= 5
        or y <= 5
        or (x + cw) >= (w - 5)
        or (y + ch) >= (h - 5)
    )
    doc_aspect = round(cw / ch, 4) if ch > 0 else 1.0
    cx = x + cw / 2.0
    cy = y + ch / 2.0
    frame_cx, frame_cy = w / 2.0, h / 2.0
    diagonal = float(np.sqrt(w**2 + h**2))
    offset = (
        float(np.sqrt((cx - frame_cx) ** 2 + (cy - frame_cy) ** 2)) / diagonal
        if diagonal > 0
        else 0.0
    )

    return {
        "document_touches_edge": touches,
        "document_aspect_ratio": doc_aspect,
        "frame_aspect_ratio": frame_aspect,
        "document_center_offset": round(offset, 4),
    }


def heic_to_jpeg(heic_path: Path, out_dir: Path, quality: int = 85) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(heic_path)
    jpeg_name = heic_path.stem + ".jpg"
    jpeg_path = out_dir / jpeg_name
    if img.mode != "RGB":
        img = img.convert("RGB")
    img.save(str(jpeg_path), "JPEG", quality=quality)
    return jpeg_path


def extract_attributes(jpeg_path: str | Path) -> dict:
    jpeg_path = Path(jpeg_path)
    img_bgr = cv2.imread(str(jpeg_path))
    if img_bgr is None:
        raise ValueError(f"OpenCV could not read image: {jpeg_path}")
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    gray_f = gray.astype(np.float64)
    center = center_crop(gray, fraction=0.6)
    center_f = center.astype(np.float64)
    h, w = gray.shape
    file_size_kb = jpeg_path.stat().st_size / 1024
    hist_counts, _ = np.histogram(gray, bins=256, range=(0, 255))
    hist_for_entropy = hist_counts.astype(np.float64) + 1e-10

    attrs: dict = {
        "filename": jpeg_path.name,
        "laplacian_variance": laplacian_variance(gray_f),
        "tenengrad_variance": tenengrad_variance(gray),
        "laplacian_variance_center": laplacian_variance(center_f),
        "tenengrad_variance_center": tenengrad_variance(center),
        "mean_luminance": float(np.mean(gray_f)),
        "luminance_std": float(np.std(gray_f)),
        "histogram_entropy": float(stats.entropy(hist_for_entropy)),
        "michelson_contrast": michelson_contrast(gray_f),
        "rms_contrast": float(np.std(gray_f / 255.0)),
        "rotation_angle": estimate_rotation(gray),
        "noise_estimate": noise_estimate(gray),
        "file_size_kb": round(file_size_kb, 1),
        # Group 1 — document coverage
        "white_region_ratio": white_region_ratio(gray),
        "document_coverage_ratio": document_coverage_ratio(gray),
        "edge_density": edge_density_full(gray),
        "center_edge_density": edge_density_center(gray),
    }
    attrs.update(shadow_features(gray))
    attrs.update(directional_blur_features(gray))
    attrs.update(document_boundary_features(gray))
    attrs["width_px"] = w
    attrs["height_px"] = h
    return attrs


def list_photo_files(photo_dir: Path) -> list[Path]:
    if not photo_dir.is_dir():
        raise FileNotFoundError(f"Not a directory: {photo_dir}")
    out: list[Path] = []
    for p in sorted(photo_dir.iterdir()):
        if p.is_file() and p.suffix in PHOTO_EXTS:
            out.append(p)
    return out


def ensure_jpeg(photo: Path, converted_dir: Path, quality: int = 85) -> Path:
    converted_dir.mkdir(parents=True, exist_ok=True)
    suf = photo.suffix.lower()
    if suf in (".heic", ".heif"):
        return heic_to_jpeg(photo, converted_dir, quality=quality)
    if suf in (".jpg", ".jpeg"):
        dest = converted_dir / photo.name
        shutil.copy2(photo, dest)
        return dest
    raise ValueError(f"Unsupported image type: {photo}")


def ollama_jpeg_bytes(jpeg_path: Path, max_long_edge: int) -> tuple[bytes, str]:
    """
    Encode a JPEG for Ollama: optional downscale (same default as web_demo) + quality 85.
    If max_long_edge <= 0, send the file bytes unchanged (can be extremely slow / huge VRAM).
    """
    if max_long_edge <= 0:
        b = jpeg_path.read_bytes()
        return (
            b,
            f"Ollama input: {jpeg_path.name} — full file (~{len(b) / 1024:.0f} KB, no resize; may be very slow)",
        )
    from PIL import Image, ImageOps

    img = Image.open(jpeg_path).convert("RGB")
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    w, h = img.size
    m = max(w, h)
    if m > max_long_edge:
        r = max_long_edge / m
        img = img.resize(
            (max(1, int(w * r)), max(1, int(h * r))), Image.Resampling.LANCZOS
        )
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    out = buf.getvalue()
    w2, h2 = img.size
    return (
        out,
        f"Ollama input: {jpeg_path.name} → {w2}×{h2} JPEG (~{len(out) / 1024:.0f} KB, max edge {max_long_edge}px)",
    )


def ollama_available() -> bool:
    try:
        r = requests.get(f"{OLLAMA_BASE}/api/tags", timeout=2.0)
        return r.ok
    except OSError:
        return False
    except requests.RequestException:
        return False


def _ollama_heartbeat(
    stop: threading.Event, interval_s: float, label: str = "Ollama"
) -> None:
    """So long first loads / slow CPU inference don’t look like a freeze."""
    t = 0.0
    while not stop.wait(interval_s):
        t += interval_s
        print(
            f"  … still waiting on {label} ({t:.0f}s elapsed). "
            f"First vision request often loads a large model; CPU inference is slow.",
            flush=True,
        )


def call_ollama(
    image_b64: str,
    prompt: str,
    model: str = DEFAULT_OLLAMA_MODEL,
    temperature: float = 0.0,
    timeout_s: float = DEFAULT_OLLAMA_TIMEOUT_S,
) -> str:
    """
    Call Ollama via HTTP POST /api/chat (not the Python ollama client) so
    `requests` read timeouts always apply. Non-streaming JSON response.
    """
    url = f"{OLLAMA_BASE.rstrip('/')}/api/chat"
    payload: dict = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": prompt,
                "images": [image_b64],
            }
        ],
        "stream": False,
        "options": {"temperature": temperature},
    }
    print(
        "  HTTP POST /api/chat (heartbeat every 15s until response). "
        "First run may spend minutes loading the model into memory.",
        flush=True,
    )
    stop = threading.Event()
    hb = threading.Thread(
        target=_ollama_heartbeat,
        args=(stop, 15.0, "Ollama"),
        daemon=True,
    )
    hb.start()
    r: requests.Response | None = None
    try:
        r = requests.post(
            url,
            json=payload,
            timeout=(30.0, float(timeout_s)),
        )
    except requests.exceptions.Timeout as e:
        print(f"Ollama HTTP read timeout (>{timeout_s}s): {e}", file=sys.stderr)
        return ""
    except requests.RequestException as e:
        print(f"Ollama HTTP request failed: {e}", file=sys.stderr)
        return ""
    finally:
        stop.set()
    if r is None or not r.ok:
        sc = r.status_code if r is not None else "?"
        err = (r.text if r is not None else "")[:2000]
        print(f"Ollama /api/chat HTTP {sc}: {err}", file=sys.stderr)
        return ""
    try:
        data = r.json()
    except json.JSONDecodeError:
        print(f"Ollama: invalid JSON in response: {r.text[:500]!r}", file=sys.stderr)
        return ""
    return str((data.get("message") or {}).get("content") or "")


def eval_server_url(phone_ip: str | None) -> str:
    if phone_ip and phone_ip.strip():
        return f"http://{phone_ip.strip()}:8080"
    ip = os.environ.get("PHONE_IP", "").strip()
    if ip:
        return f"http://{ip}:8080"
    return ""


def call_eval_server_infer(
    phone_ip: str | None,
    prompt: str,
    image_b64: str,
) -> str:
    base = eval_server_url(phone_ip)
    if not base:
        print(
            "eval-server requires --phone-ip or PHONE_IP in the environment.",
            file=sys.stderr,
        )
        sys.exit(1)
    out = run_inference(
        base, image_b64, prompt, track="a", temperature=0.0, timeout=120
    )
    if out.get("error"):
        return ""
    return str(out.get("response") or "")


def score_against_ground_truth(
    artifact_id: str,
    parsed: dict | None,
    gt: dict[str, dict[str, str]],
) -> dict:
    field_scores, _crit, _abst = score_prompt_ablation_row(
        parsed, artifact_id, gt, "semantic"
    )
    return field_scores


def run_extraction(
    jpeg_path: Path,
    backend: str,
    phone_ip: str | None,
    gt: dict[str, dict[str, str]],
    n_runs: int = 3,
    cooldown: float = 3.0,
    ollama_max_long_edge: int = DEFAULT_OLLAMA_MAX_LONG_EDGE,
    ollama_timeout_s: float = DEFAULT_OLLAMA_TIMEOUT_S,
    ollama_temperature: float = 0.0,
) -> list[dict]:
    if backend == "ollama":
        if not ollama_available():
            print(
                "Ollama not found at localhost:11434. Start it with: ollama serve",
                file=sys.stderr,
            )
            sys.exit(1)
        raw_jpeg, log_line = ollama_jpeg_bytes(jpeg_path, ollama_max_long_edge)
        print(f"  {log_line}", flush=True)
        image_b64 = base64.b64encode(raw_jpeg).decode("ascii")
    else:
        image_b64 = base64.b64encode(jpeg_path.read_bytes()).decode("ascii")

    results: list[dict] = []
    for i in range(n_runs):
        if i > 0:
            time.sleep(cooldown)
        if backend == "ollama":
            raw = call_ollama(
                image_b64,
                D01_SEMANTIC_PROMPT,
                temperature=ollama_temperature,
                timeout_s=ollama_timeout_s,
            )
        else:
            raw = call_eval_server_infer(phone_ip, D01_SEMANTIC_PROMPT, image_b64)
        parsed = parse_with_retry(raw)
        scored = score_against_ground_truth("D01", parsed, gt)
        rd = scored.get("response_deadline") or {}
        label = rd.get("label")
        results.append(
            {
                "run": i,
                "raw_response": raw,
                "parsed": parsed,
                "scores": scored,
                "critical_deadline_exact": label == "exact",
            }
        )
    return results


def flatten_extraction_run(filename: str, item: dict) -> dict:
    """Build one flat dict per inference run for eval_runs.csv (no raw model text)."""
    row: dict = {
        "filename": filename,
        "run": int(item.get("run", 0)),
        "critical_deadline_exact": bool(item.get("critical_deadline_exact", False)),
    }
    scores = item.get("scores") or {}
    for k, v in scores.items():
        if not isinstance(v, dict):
            continue
        safe = k.replace(".", "_")
        row[f"{safe}_label"] = str(v.get("label", ""))
        se = v.get("score")
        row[f"{safe}_score"] = (
            float(se) if se is not None and se == se else float("nan")
        )
        cf = v.get("correct_field")
        row[f"{safe}_correct_field"] = bool(cf) if isinstance(cf, bool) else ""
    return row


def find_best_threshold(
    df: pd.DataFrame, attribute: str | None
) -> dict | None:
    if not attribute or attribute not in df.columns:
        return None
    s = df[attribute].dropna()
    if len(s) < 2:
        return None
    labels = (df.loc[s.index, "label"] == "pass").astype(int)
    best_acc, best_thresh, best_dir = 0.0, 0.0, "above"
    vals = s.to_numpy(dtype=float)
    for thresh in np.percentile(vals, np.arange(10, 91, 5)):
        for direction in ("above", "below"):
            if direction == "above":
                pred = (s >= thresh).astype(int)
            else:
                pred = (s < thresh).astype(int)
            acc = float(accuracy_score(labels.to_numpy(), pred.to_numpy()))
            if acc > best_acc:
                best_acc, best_thresh, best_dir = acc, float(thresh), direction
    n = len(s)
    n_ok = int(round(best_acc * n))
    sym = "≥" if best_dir == "above" else "<"
    return {
        "attribute": attribute,
        "threshold": round(best_thresh, 2),
        "direction": best_dir,
        "accuracy": round(best_acc, 3),
        "n_correct": n_ok,
        "n_total": n,
        "rule": f"pass if {attribute} {sym} {round(best_thresh, 2)}",
    }


def analyze(df: pd.DataFrame) -> dict:
    passing = df[df["label"] == "pass"]
    failing = df[df["label"] == "fail"]

    stat_rows: list[dict] = []
    for col in ATTRIBUTE_COLS:
        if col not in df.columns:
            continue
        p_vals = passing[col].dropna()
        f_vals = failing[col].dropna()
        if len(p_vals) < 2 or len(f_vals) < 2:
            continue
        pooled_std = np.sqrt((p_vals.std() ** 2 + f_vals.std() ** 2) / 2)
        cohens_d = (p_vals.mean() - f_vals.mean()) / (pooled_std + 1e-10)
        try:
            _, p_value = stats.mannwhitneyu(
                p_vals, f_vals, alternative="two-sided"
            )
        except ValueError:
            continue
        stat_rows.append(
            {
                "attribute": col,
                "pass_mean": round(float(p_vals.mean()), 3),
                "fail_mean": round(float(f_vals.mean()), 3),
                "cohens_d": round(float(abs(cohens_d)), 3),
                "p_value": round(float(p_value), 4),
                "significant": bool(p_value < 0.05),
            }
        )

    ranking = (
        pd.DataFrame(stat_rows).sort_values("cohens_d", ascending=False)
        if stat_rows
        else pd.DataFrame()
    )

    y = (df["label"] == "pass").astype(int).values
    X = df.reindex(columns=ATTRIBUTE_COLS).fillna(0).values
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    preds: list[int] = []
    loo = LeaveOneOut()
    lr = LogisticRegression(max_iter=1000)
    for train_idx, test_idx in loo.split(X_scaled):
        yt = y[train_idx]
        if np.all(yt == 0) or np.all(yt == 1):
            preds.append(int(yt[0]))
            continue
        try:
            lr.fit(X_scaled[train_idx], yt)
            preds.append(int(lr.predict(X_scaled[test_idx])[0]))
        except ValueError:
            maj = int(np.round(yt.mean()))
            preds.append(maj)

    loo_accuracy = float(accuracy_score(y, np.array(preds))) if len(y) else 0.0

    try:
        lr.fit(X_scaled, y)
        coefs = lr.coef_[0]
    except ValueError:
        coefs = np.zeros(len(ATTRIBUTE_COLS))
    coef_df = pd.DataFrame(
        {
            "attribute": ATTRIBUTE_COLS,
            "coefficient": np.round(coefs, 3),
            "abs_coefficient": np.abs(np.round(coefs, 3)),
        }
    ).sort_values("abs_coefficient", ascending=False)

    best_attr = str(ranking.iloc[0]["attribute"]) if len(ranking) else None
    best_rule = find_best_threshold(df, best_attr)
    current_detector = find_best_threshold(df, "laplacian_variance")

    return {
        "ranking": ranking,
        "loo_accuracy": loo_accuracy,
        "coef_df": coef_df,
        "best_rule": best_rule,
        "current_detector": current_detector,
        "n_pass": int((df["label"] == "pass").sum()),
        "n_fail": int((df["label"] == "fail").sum()),
    }


def write_logistic_regression_report(
    path: Path,
    loo_acc: float,
    coef_df: pd.DataFrame,
) -> None:
    lines = [
        f"Leave-one-out accuracy: {loo_acc:.2f}",
        "",
        "Feature importances (by abs coefficient):",
    ]
    for _, row in coef_df.iterrows():
        lines.append(
            f"  {row['attribute']}: {row['coefficient']:.3f} "
            f"(abs {row['abs_coefficient']:.3f})"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_decision_rule(
    path: Path,
    best: dict | None,
    current: dict | None,
) -> None:
    def single_rule_lines(heading: str, d: dict | None) -> list[str]:
        out = [heading]
        if not d:
            out.append("  (insufficient data)")
            return out
        sym = "≥" if d["direction"] == "above" else "<"
        out.append(
            f"  {d['attribute']} {sym} {d['threshold']}"
        )
        out.append(
            f"  Accuracy: {d['accuracy']:.2f} "
            f"({d['n_correct']}/{d['n_total']} photos)"
        )
        return out

    lines: list[str] = single_rule_lines("Best single-attribute rule:", best)
    lines.append("")
    lines.extend(single_rule_lines("Current detector (laplacian_variance):", current))
    if best and current and "accuracy" in best and "accuracy" in current:
        imp = (best["accuracy"] - current["accuracy"]) * 100
        sign = "+" if imp >= 0 else ""
        lines.append("")
        lines.append(f"Improvement: {sign}{imp:.0f} percentage points")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary_md(
    path: Path,
    analysis: dict,
    n_photos: int,
) -> None:
    top = None
    rnk = analysis["ranking"]
    if len(rnk):
        top = rnk.iloc[0]
    br = analysis["best_rule"] or {}
    cur = analysis["current_detector"] or {}
    acc_best = (br.get("accuracy") or 0) * 100
    acc_cur = (cur.get("accuracy") or 0) * 100
    if top is not None:
        key_finding = (
            f"**{top['attribute']}** was the largest separable signal by effect size "
            f"(Cohen's d = {top['cohens_d']}, p = {top['p_value']}). "
            f"The best single-attribute threshold rule reached ~{acc_best:.0f}% accuracy on this corpus; "
            f"optimizing `laplacian_variance` alone reached ~{acc_cur:.0f}%."
        )
    else:
        key_finding = (
            "With the current pass/fail split, no attribute met the minimum group sizes "
            "for effect-size and Mann–Whitney tests, or all labels are the same class."
        )
    # Markdown table
    table = ""
    if len(rnk):
        table = "| attribute | pass mean | fail mean | Cohen's d | p-value | significant |\n"
        table += "|---|---:|---:|---:|---:|:---:|\n"
        for _, row in rnk.iterrows():
            sig = "yes" if row["significant"] else "no"
            table += (
                f"| {row['attribute']} | {row['pass_mean']} | {row['fail_mean']} | "
                f"{row['cohens_d']} | {row['p_value']} | {sig} |\n"
            )
    rec = (
        f"Consider promoting **{br.get('attribute', 'N/A')}** with rule `{br.get('rule', 'n/a')}` "
        if br.get("attribute")
        else "Collect more diverse failing photos and re-run."
    )
    text = f"""# Real-World Image Quality Characterization — D01 SNAP Notice

## Dataset
- {n_photos} real iPhone (or folder) photos
- {analysis['n_pass']} passing (response_deadline **exact** in ≥2/3 runs)
- {analysis['n_fail']} failing

## Key Finding
{key_finding}

## Attribute Rankings
{table or '_No ranking table (insufficient contrast or sample sizes)._ '}

## Recommendation
{rec}
"""
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="HEIC→JPEG, attribute metrics, D01 LLM eval, pass/fail analysis"
    )
    parser.add_argument(
        "--photos", required=True, help="Directory containing HEIC/JPEG photos"
    )
    parser.add_argument(
        "--out",
        default=str(_DEFAULT_RESULT_DIR),
        help="Output directory (converted/ created inside); default is fixed under repo root",
    )
    parser.add_argument(
        "--backend",
        choices=["ollama", "eval-server"],
        default="ollama",
        help="ollama = Gemma4 E4B local; eval-server = on-device E2B",
    )
    parser.add_argument(
        "--phone-ip",
        default=os.environ.get("PHONE_IP", ""),
        help="iPhone IP for eval-server (or set PHONE_IP)",
    )
    parser.add_argument("--runs-per-photo", type=int, default=3)
    parser.add_argument(
        "--cooldown",
        type=float,
        default=3.0,
        help="Seconds between runs on the same photo",
    )
    parser.add_argument(
        "--photo-break",
        type=float,
        default=10.0,
        help="Seconds between photos (thermal management)",
    )
    parser.add_argument(
        "--attributes-only",
        action="store_true",
        help="Only convert images and extract attributes (no LLM)",
    )
    parser.add_argument(
        "--ollama-max-long-edge",
        type=int,
        default=DEFAULT_OLLAMA_MAX_LONG_EDGE,
        help=(
            "For --backend ollama: max longest image edge in pixels before the request "
            f"(default {DEFAULT_OLLAMA_MAX_LONG_EDGE}, same as web_demo; use 0 for full resolution — very slow)"
        ),
    )
    parser.add_argument(
        "--ollama-timeout",
        type=float,
        default=DEFAULT_OLLAMA_TIMEOUT_S,
        help="For --backend ollama: HTTP timeout in seconds per inference (default 600)",
    )
    parser.add_argument(
        "--ollama-temperature",
        type=float,
        default=0.0,
        help="For --backend ollama: sampling temperature (default 0.0)",
    )
    args = parser.parse_args()

    photo_dir = Path(args.photos).resolve()
    out_root = Path(args.out).expanduser().resolve()
    converted_dir = out_root / "converted"
    out_root.mkdir(parents=True, exist_ok=True)

    photos = list_photo_files(photo_dir)
    if not photos:
        print(f"No supported images in {photo_dir}", file=sys.stderr)
        sys.exit(1)

    gt = load_ground_truth()

    rows: list[dict] = []
    run_rows: list[dict] = []
    n = len(photos)
    for idx, p in enumerate(photos, start=1):
        print(f"Photo {idx}/{n}: {p.name} → ", end="", flush=True)
        jpeg_path = ensure_jpeg(p, converted_dir)
        attr = extract_attributes(jpeg_path)
        print("attributes extracted → ", end="", flush=True)

        if args.attributes_only:
            attr["pass_rate"] = float("nan")
            attr["label"] = ""
            print("inference: skipped (attributes-only)")
            rows.append(attr)
            continue

        ex = run_extraction(
            jpeg_path,
            args.backend,
            args.phone_ip or None,
            gt,
            n_runs=args.runs_per_photo,
            cooldown=args.cooldown,
            ollama_max_long_edge=args.ollama_max_long_edge,
            ollama_timeout_s=args.ollama_timeout,
            ollama_temperature=args.ollama_temperature,
        )
        pr = sum(1 for r in ex if r["critical_deadline_exact"]) / len(ex)
        label = "pass" if pr >= (2.0 / 3.0) else "fail"
        nat = sum(1 for r in ex if r["critical_deadline_exact"])
        attr["pass_rate"] = round(pr, 3)
        attr["label"] = label
        rows.append(attr)
        for r in ex:
            run_rows.append(flatten_extraction_run(jpeg_path.name, r))
        print(
            f"inference: {args.runs_per_photo}/{args.runs_per_photo} runs → "
            f"label: {label} ({nat}/{args.runs_per_photo} deadline exact)"
        )
        if idx < n and args.photo_break > 0:
            time.sleep(args.photo_break)

    df = pd.DataFrame(rows)
    df.to_csv(out_root / "photo_attributes.csv", index=False)
    if run_rows:
        run_df = pd.DataFrame(run_rows)
        lead = ["filename", "run", "critical_deadline_exact"]
        rest = sorted(c for c in run_df.columns if c not in lead)
        run_df = run_df[lead + rest]
        run_df.to_csv(out_root / "eval_runs.csv", index=False)

    if args.attributes_only:
        print(
            f"Wrote {out_root / 'photo_attributes.csv'} "
            f"({len(df)} rows). Skipped analysis (--attributes-only)."
        )
        return

    if df["label"].nunique() < 2:
        print(
            "Warning: only one class in labels — statistical comparisons will be weak. "
            f"pass={ (df['label']=='pass').sum() }, fail={(df['label']=='fail').sum()}"
        )

    analysis = analyze(df)
    rnk = analysis["ranking"]
    rnk.to_csv(out_root / "attribute_ranking.csv", index=False)
    write_logistic_regression_report(
        out_root / "logistic_regression_report.txt",
        analysis["loo_accuracy"],
        analysis["coef_df"],
    )
    write_decision_rule(
        out_root / "decision_rule.txt",
        analysis["best_rule"],
        analysis["current_detector"],
    )
    write_summary_md(out_root / "summary.md", analysis, len(df))

    top_name = "—"
    if len(rnk):
        top_name = str(rnk.iloc[0]["attribute"])
    print(
        f"Done. pass={analysis['n_pass']} fail={analysis['n_fail']} | "
        f"LOO accuracy={analysis['loo_accuracy']:.2f} | top attribute by |d|: {top_name}"
    )


if __name__ == "__main__":
    main()
