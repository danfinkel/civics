#!/usr/bin/env python3
"""Monte Carlo eval harness: drive on-device /infer from a Mac over Wi‑Fi."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import sys
import threading
import time
from collections import defaultdict
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parents[2]
SPIKE_DIR = REPO_ROOT / "spike"
ARTIFACTS_CLEAN = SPIKE_DIR / "artifacts" / "clean"
ARTIFACTS_DEGRADED = SPIKE_DIR / "artifacts" / "degraded"
ARTIFACTS_BLURRY = SPIKE_DIR / "artifacts" / "blurry"
GROUND_TRUTH_CSV = SPIKE_DIR / "artifacts" / "clean" / "html" / "ground_truth.csv"


def metrics_poll_worker(
    phone_url: str,
    log_path: Path,
    interval_s: float,
    stop: threading.Event,
) -> None:
    """Background thread: sample GET /metrics for thermal / memory characterization."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(
            json.dumps(
                {"event": "metrics_poll_start", "t_wall": time.time()},
                ensure_ascii=False,
            )
            + "\n"
        )
        f.flush()
        while True:
            try:
                r = requests.get(f"{phone_url}/metrics", timeout=5)
                body = r.json() if r.ok else {"_http_body": r.text[:500]}
                rec = {
                    "t_wall": time.time(),
                    "http_ok": r.ok,
                    "status_code": r.status_code,
                    "metrics": body,
                }
            except Exception as e:
                rec = {
                    "t_wall": time.time(),
                    "http_ok": False,
                    "error": str(e),
                }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            if stop.wait(timeout=interval_s):
                break
        f.write(
            json.dumps(
                {"event": "metrics_poll_stop", "t_wall": time.time()},
                ensure_ascii=False,
            )
            + "\n"
        )
        f.flush()


def phone_base_url() -> str:
    url = os.environ.get("PHONE_URL", "").strip()
    if url:
        return url.rstrip("/")
    ip = os.environ.get("PHONE_IP", "127.0.0.1").strip()
    return f"http://{ip}:8080"


def load_ground_truth() -> dict[str, dict[str, str]]:
    gt: dict[str, dict[str, str]] = defaultdict(dict)
    if not GROUND_TRUTH_CSV.is_file():
        raise FileNotFoundError(f"Ground truth not found: {GROUND_TRUTH_CSV}")
    with GROUND_TRUTH_CSV.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            aid = row["artifact_id"]
            gt[aid][row["field_name"]] = row["expected_value"]
    return dict(gt)


def load_image_bytes(artifact_id: str, variant: str) -> bytes:
    if variant == "clean":
        candidates = [
            ARTIFACTS_CLEAN / f"{artifact_id}-clean.pdf",
            ARTIFACTS_CLEAN / f"{artifact_id}-clean.jpg",
            ARTIFACTS_CLEAN / f"{artifact_id}.pdf",
            ARTIFACTS_CLEAN / f"{artifact_id}.jpg",
        ]
    elif variant == "degraded":
        candidates = [ARTIFACTS_DEGRADED / f"{artifact_id}-degraded.jpg"]
    elif variant == "blurry":
        candidates = [ARTIFACTS_BLURRY / f"{artifact_id}-blurry.jpg"]
    else:
        candidates = [
            ARTIFACTS_DEGRADED / f"{artifact_id}-{variant}.jpg",
            ARTIFACTS_DEGRADED / f"{artifact_id}-{variant}.jpeg",
        ]

    for path in candidates:
        if path.is_file():
            return path.read_bytes()
    raise FileNotFoundError(
        f"No artifact file for {artifact_id!r} variant {variant!r} (tried {candidates})"
    )


def load_image_b64(artifact_id: str, variant: str) -> str:
    return base64.b64encode(load_image_bytes(artifact_id, variant)).decode("ascii")


def build_prompt(artifact_id: str, gt: dict[str, dict[str, str]], track: str) -> str:
    _ = track
    fields = gt.get(artifact_id, {})
    if not fields:
        return (
            f"You are a document analysis assistant. Artifact {artifact_id} has no "
            "ground-truth fields in this CSV; return an empty JSON object {{}}."
        )
    field_json = "\n".join([f'  "{k}": "",' for k in fields])
    return f"""You are a document analysis assistant. Read the document carefully.

Rules:
- Extract only values clearly present in the document
- Read each field directly from its labeled location
- For pay-stub income: use current-period column only, not YTD
- Copy names character-by-character as printed
- If you cannot read a field, set its value to UNREADABLE
- Return ONLY valid JSON with exactly these keys. No markdown.

{{
{field_json}
}}
"""


def normalize(v: str) -> str:
    return v.lower().strip().replace(",", "").replace("$", "").replace(" ", "")


def score_field(extracted, expected: str) -> dict:
    if extracted is None or (isinstance(extracted, str) and not extracted.strip()):
        return {"score": 0, "label": "missing"}
    ext_n = normalize(str(extracted))
    exp_n = normalize(expected)
    if ext_n == "unreadable":
        return {"score": 0, "label": "unreadable"}
    if ext_n == exp_n:
        return {"score": 2, "label": "exact"}
    if exp_n in ext_n or ext_n in exp_n:
        return {"score": 1, "label": "partial"}
    return {"score": -1, "label": "hallucinated"}


def parse_with_retry(raw: str) -> dict | None:
    if not raw or not str(raw).strip():
        return None
    text = str(raw).strip()
    if text.startswith("```"):
        lines = text.split("\n")
        if lines and lines[0].strip().startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        out = json.loads(text)
        return out if isinstance(out, dict) else None
    except json.JSONDecodeError:
        return None


def run_inference(
    phone_url: str,
    image_b64: str,
    prompt: str,
    track: str,
    temperature: float = 0.0,
    token_budget: int | None = None,
    timeout: int = 120,
) -> dict:
    payload: dict = {
        "image": image_b64,
        "prompt": prompt,
        "track": track,
        "temperature": temperature,
    }
    if token_budget is not None:
        payload["token_budget"] = token_budget

    t0 = time.time()
    try:
        r = requests.post(f"{phone_url}/infer", json=payload, timeout=timeout)
        r.raise_for_status()
        data = r.json()
        return {
            "response": data.get("response", ""),
            "elapsed_ms": data.get("elapsed_ms", int((time.time() - t0) * 1000)),
            "parse_ok": bool(data.get("parse_ok")),
            "error": None,
        }
    except requests.exceptions.Timeout:
        return {
            "response": "",
            "elapsed_ms": timeout * 1000,
            "parse_ok": False,
            "error": "timeout",
        }
    except Exception as e:
        return {
            "response": "",
            "elapsed_ms": int((time.time() - t0) * 1000),
            "parse_ok": False,
            "error": str(e),
        }


def run_experiment(
    phone_url: str,
    artifact_id: str,
    variant: str,
    track: str,
    n_runs: int,
    temperature: float,
    token_budget: int | None,
    gt: dict[str, dict[str, str]],
    cooldown_s: float = 2.0,
    infer_timeout: int = 120,
) -> list[dict]:
    image_b64 = load_image_b64(artifact_id, variant)
    prompt = build_prompt(artifact_id, gt, track)
    fields = gt.get(artifact_id, {})

    results = []
    for i in range(n_runs):
        print(
            f"  {artifact_id} {variant} temp={temperature} budget={token_budget} "
            f"run {i + 1}/{n_runs}",
            end="\r",
            flush=True,
        )

        infer_result = run_inference(
            phone_url,
            image_b64,
            prompt,
            track,
            temperature,
            token_budget,
            timeout=infer_timeout,
        )
        parsed = parse_with_retry(infer_result["response"])

        field_scores: dict = {}
        if parsed and fields:
            for fname, expected in fields.items():
                field_scores[fname] = score_field(parsed.get(fname), expected)

        pts = [s["score"] for s in field_scores.values()]
        avg_score = sum(pts) / len(pts) if pts else None
        halluc_count = sum(1 for s in field_scores.values() if s["label"] == "hallucinated")

        record = {
            "artifact_id": artifact_id,
            "variant": variant,
            "track": track,
            "run": i,
            "temperature": temperature,
            "token_budget": token_budget,
            "elapsed_ms": infer_result["elapsed_ms"],
            "parse_ok": parsed is not None,
            "error": infer_result["error"],
            "raw_response": infer_result["response"],
            "field_scores": field_scores,
            "avg_score": round(avg_score, 4) if avg_score is not None else None,
            "hallucination_count": halluc_count,
        }
        results.append(record)

        if i < n_runs - 1:
            time.sleep(cooldown_s)

    print()
    return results


def compute_summary(results: list[dict]) -> dict:
    scored = [r for r in results if r["avg_score"] is not None]
    if not scored:
        return {}

    scores = [r["avg_score"] for r in scored]
    latencies = [r["elapsed_ms"] for r in results if r["elapsed_ms"]]
    all_labels = [s["label"] for r in scored for s in r["field_scores"].values()]

    n_fields = len(all_labels)
    mean_s = sum(scores) / len(scores)

    return {
        "n_runs": len(results),
        "n_scored": len(scored),
        "parse_ok_rate": sum(1 for r in results if r["parse_ok"]) / len(results),
        "avg_score_mean": mean_s,
        "avg_score_std": (
            sum((s - mean_s) ** 2 for s in scores) / len(scores)
        )
        ** 0.5,
        "hallucination_rate": all_labels.count("hallucinated") / n_fields
        if n_fields
        else 0,
        "exact_rate": all_labels.count("exact") / n_fields if n_fields else 0,
        "partial_rate": all_labels.count("partial") / n_fields if n_fields else 0,
        "missing_rate": all_labels.count("missing") / n_fields if n_fields else 0,
        "unreadable_rate": all_labels.count("unreadable") / n_fields
        if n_fields
        else 0,
        "latency_mean_ms": sum(latencies) / len(latencies) if latencies else 0,
        "latency_p95_ms": sorted(latencies)[int(len(latencies) * 0.95)]
        if len(latencies) > 1
        else (latencies[0] if latencies else 0),
        "latency_std_ms": (
            sum((l - sum(latencies) / len(latencies)) ** 2 for l in latencies)
            / len(latencies)
        )
        ** 0.5
        if latencies
        else 0,
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--artifacts",
        required=True,
        help="Comma-separated artifact ids, e.g. D01,D03",
    )
    p.add_argument("--track", default="a", help="Track label for logging (default: a)")
    p.add_argument(
        "--variants",
        default="clean,degraded",
        help="Comma-separated: clean, degraded, blurry, or custom degraded name",
    )
    p.add_argument("--runs", type=int, default=20, help="Monte Carlo iterations per cell")
    p.add_argument("--temp", type=float, default=0.0, dest="temperature")
    p.add_argument("--cooldown", type=float, default=2.0)
    p.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "research" / "eval" / "results" / "run.jsonl",
    )
    p.add_argument(
        "--phone-url",
        default="",
        help="Override PHONE_URL / PHONE_IP (e.g. http://192.168.1.10:8080)",
    )
    p.add_argument(
        "--token-budget",
        type=int,
        default=None,
        help="Optional max output tokens (maps to token_budget in JSON)",
    )
    p.add_argument(
        "--token-budgets",
        default="",
        help="With --ablation: comma-separated budgets, one experiment each",
    )
    p.add_argument(
        "--ablation",
        action="store_true",
        help="Run each --token-budgets value across all artifact/variant cells",
    )
    p.add_argument("--infer-timeout", type=int, default=120)
    p.add_argument(
        "--metrics-log",
        type=Path,
        default=None,
        help="Append /metrics samples (JSONL) during the whole run for thermal analysis",
    )
    p.add_argument(
        "--metrics-interval",
        type=float,
        default=30.0,
        help="Seconds between /metrics polls when --metrics-log is set (default: 30)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    phone_url = (args.phone_url or "").strip().rstrip("/") or phone_base_url()

    try:
        h = requests.get(f"{phone_url}/health", timeout=10)
        h.raise_for_status()
    except Exception as e:
        print(f"ERROR: /health failed ({phone_url}): {e}", file=sys.stderr)
        return 1

    gt = load_ground_truth()
    artifacts = [a.strip() for a in args.artifacts.split(",") if a.strip()]
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]

    if args.ablation:
        budgets = [
            int(x.strip())
            for x in args.token_budgets.split(",")
            if x.strip().isdigit()
        ]
        if not budgets:
            print("ERROR: --ablation requires --token-budgets with integers", file=sys.stderr)
            return 1
    else:
        budgets = [args.token_budget]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    all_rows: list[dict] = []

    stop_metrics = threading.Event()
    metrics_thread: threading.Thread | None = None
    if args.metrics_log is not None:
        metrics_thread = threading.Thread(
            target=metrics_poll_worker,
            args=(phone_url, args.metrics_log, args.metrics_interval, stop_metrics),
            daemon=True,
            name="metrics-poll",
        )
        metrics_thread.start()

    for budget in budgets:
        tb = budget if args.ablation else args.token_budget
        for aid in artifacts:
            for variant in variants:
                rows = run_experiment(
                    phone_url,
                    aid,
                    variant,
                    args.track,
                    args.runs,
                    args.temperature,
                    tb,
                    gt,
                    cooldown_s=args.cooldown,
                    infer_timeout=args.infer_timeout,
                )
                all_rows.extend(rows)

    stop_metrics.set()
    if metrics_thread is not None:
        metrics_thread.join(timeout=10.0)

    with args.out.open("w", encoding="utf-8") as f:
        for row in all_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = compute_summary(all_rows)
    print(json.dumps(summary, indent=2))
    print(f"Wrote {len(all_rows)} lines to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
