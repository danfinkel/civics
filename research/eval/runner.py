#!/usr/bin/env python3
"""Monte Carlo eval harness: drive on-device /infer from a Mac over Wi‑Fi."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import re
import sys
import threading
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import requests

from prompt_conditions import (
    GENERIC_TO_GT_D01,
    PROMPT_ABLATION_VERSION,
    build_extraction_prompt,
    critical_deadline_key,
    field_keys_for_condition,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS_ROOT = REPO_ROOT / "research" / "artifacts"
ARTIFACTS_CLEAN = ARTIFACTS_ROOT / "clean"
ARTIFACTS_DEGRADED = ARTIFACTS_ROOT / "degraded"
ARTIFACTS_BLURRY = ARTIFACTS_ROOT / "blurry"
GROUND_TRUTH_CSV = ARTIFACTS_ROOT / "clean" / "html" / "ground_truth.csv"
DEFAULT_EVAL_JSONL_OUT = REPO_ROOT / "research" / "eval" / "results" / "run.jsonl"

FIELD_SCORE_LABELS: tuple[str, ...] = (
    "exact",
    "partial",
    "format_mismatch",
    "transcription_error",
    "unreadable",
    "missing",
    "semantic_paraphrase",
    "verbatim_quote",
    "misattribution",
    "hallucinated",
)

# OCR / blur transcription vs other-field match (score_field + misattribution detection)
LEVENSHTEIN_THRESHOLD = 0.45


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


class InferStrictAbort(RuntimeError):
    """Raised when --strict-infer sees an empty or errored /infer response."""


def health_ping_latencies_ms(
    phone_url: str, *, pings: int, timeout_s: float
) -> list[float]:
    """Wall-clock RTT in ms for each GET /health (cold connection each ping)."""
    out: list[float] = []
    for _ in range(pings):
        t0 = time.perf_counter()
        r = requests.get(f"{phone_url}/health", timeout=timeout_s)
        r.raise_for_status()
        out.append((time.perf_counter() - t0) * 1000.0)
    return out


def ensure_health_before_condition_batch(
    phone_url: str,
    *,
    pings: int = 3,
    max_mean_ms: float = 200.0,
    per_request_timeout_s: float = 10.0,
    max_rounds: int = 3,
    wait_between_rounds_s: float = 30.0,
) -> None:
    """
    Ping /health `pings` times; mean latency must be <= max_mean_ms.
    On failure, warn, wait wait_between_rounds_s, retry up to max_rounds.
    Raises RuntimeError if all rounds fail (halt experiment; do not record bad rows).
    """
    last_err: str | None = None
    for round_i in range(1, max_rounds + 1):
        try:
            lat = health_ping_latencies_ms(
                phone_url, pings=pings, timeout_s=per_request_timeout_s
            )
            mean_ms = sum(lat) / len(lat)
            if mean_ms <= max_mean_ms:
                print(
                    f"Health OK (round {round_i}/{max_rounds}): "
                    f"/health mean {mean_ms:.1f}ms over {pings} pings "
                    f"(max {max_mean_ms:.0f}ms)"
                )
                return
            last_err = (
                f"mean latency {mean_ms:.1f}ms exceeds {max_mean_ms:.0f}ms "
                f"(pings_ms={','.join(f'{x:.1f}' for x in lat)})"
            )
            print(
                f"WARNING: pre-batch health latency check failed: {last_err}",
                file=sys.stderr,
            )
        except Exception as e:
            last_err = str(e)
            print(
                f"WARNING: pre-batch /health failed (round {round_i}/{max_rounds}): {e}",
                file=sys.stderr,
            )
        if round_i < max_rounds:
            print(
                f"Waiting {wait_between_rounds_s:.0f}s before retry...",
                file=sys.stderr,
            )
            time.sleep(wait_between_rounds_s)
    raise RuntimeError(
        "FATAL: eval halted after repeated /health failures or high latency. "
        f"Last issue: {last_err}. Fix device/network/thermal state before re-running."
    )


def condition_break_countdown(seconds: float, label: str = "Condition break") -> None:
    """Visible cooldown between prompt-condition batches (thermal / memory)."""
    total = max(0, int(round(seconds)))
    if total <= 0:
        return
    print(f"\n{label}: waiting {total}s before next batch...")
    for remaining in range(total, 0, -1):
        print(f"\r  {label}: {remaining}s remaining... ", end="", flush=True)
        time.sleep(1.0)
    print(f"\r  {label}: done.{' ' * 20}")


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
    elif variant == "clean_jpeg":
        # Rasterized from clean PDF (see research/spike/rasterize_clean_pdfs_to_jpeg.py).
        candidates = [
            ARTIFACTS_CLEAN / f"{artifact_id}-clean-raster.jpg",
            ARTIFACTS_CLEAN / f"{artifact_id}-clean-raster.jpeg",
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


SCORING_RUBRIC_VERSION = "2026-04-12-v3"

LABEL_SCORES: dict[str, int] = {
    "exact": 2,
    "partial": 1,
    "format_mismatch": 1,
    "transcription_error": 0,
    "unreadable": 0,
    "missing": 0,
    "semantic_paraphrase": 0,
    "verbatim_quote": 0,
    "misattribution": -1,
    "hallucinated": -1,
}

_PARAPHRASE_STOPWORDS = frozenset(
    """
    a an the and or but if in on at to for of as by with from is are was were be been
    being it its this that these those your our their we you they he she his her
    not no yes so than then too very can could should would may might must will
    """.split()
)


def normalize(v: str) -> str:
    return v.lower().strip().replace(",", "").replace("$", "").replace(" ", "")


def aggressive_normalize(v: str) -> str:
    """Lowercase; strip underscores, hyphens, punctuation, and whitespace for format checks."""
    s = str(v).lower()
    return re.sub(r"[^a-z0-9]", "", s)


try:
    import Levenshtein  # type: ignore[import-untyped]

    def _lev_distance(a: str, b: str) -> int:
        return int(Levenshtein.distance(a, b))

except ImportError:

    def _lev_distance(a: str, b: str) -> int:
        """O(nm) fallback if python-Levenshtein is not installed."""
        if a == b:
            return 0
        if not a:
            return len(b)
        if not b:
            return len(a)
        prev = list(range(len(b) + 1))
        for i, ca in enumerate(a, 1):
            cur = [i]
            for j, cb in enumerate(b, 1):
                ins, delete, sub = cur[j - 1] + 1, prev[j] + 1, prev[j - 1]
                if ca != cb:
                    sub += 1
                cur.append(min(ins, delete, sub))
            prev = cur
        return prev[-1]


def _sf(label: str, *, correct_field: bool = True) -> dict:
    return {
        "score": LABEL_SCORES[label],
        "label": label,
        "correct_field": correct_field,
    }


def _matches_other_gt_value(extracted: str, other_exp: str) -> bool:
    """True if extracted aligns with another field's expected value (misattribution signal)."""
    if not other_exp or not str(extracted).strip():
        return False
    ext_s = str(extracted).strip()
    oth = str(other_exp).strip()
    ext_d = canonical_date_string(ext_s)
    oth_d = canonical_date_string(oth)
    if ext_d is not None and oth_d is not None and ext_d == oth_d:
        return True
    if aggressive_normalize(ext_s) == aggressive_normalize(oth):
        return True
    en, on = normalize(ext_s), normalize(oth)
    if en == on or (on and (on in en or en in on)):
        return True
    if len(on) > 0:
        ratio = _lev_distance(en, on) / len(on)
        if ratio <= LEVENSHTEIN_THRESHOLD:
            return True
    return False


def is_verbatim_quote(extracted: str, expected: str) -> bool:
    """
    Long extracted document text vs short categorical GT (e.g. consequence vs case_closure).
    correct_field must be True — caller applies only before misattribution.
    """
    if len(extracted) <= 50:
        return False
    if len(expected) > 20 or "_" not in expected:
        return False
    key_terms = [t for t in expected.replace("_", " ").split() if len(t) > 3]
    if not key_terms:
        return False
    extracted_lower = extracted.lower()
    matches = sum(1 for t in key_terms if t.lower() in extracted_lower)
    return matches / len(key_terms) >= 0.5


def _semantic_paraphrase_ok(extracted: str, expected: str) -> bool:
    exp = str(expected).strip()
    ext = str(extracted).strip()
    if len(exp) > 20 or "_" not in exp:
        return False
    if len(ext) <= 30:
        return False
    terms = [t for t in exp.split("_") if len(t) > 1 and t.lower() not in _PARAPHRASE_STOPWORDS]
    if not terms:
        terms = [t for t in exp.split("_") if len(t) > 1]
    if not terms:
        return False
    ext_l = ext.lower()
    hits = sum(1 for t in terms if t.lower() in ext_l)
    return hits / len(terms) >= 0.5


# Month-first and ISO forms the model and ground_truth.csv use.
_DATE_PARSE_FORMATS: tuple[str, ...] = (
    "%Y-%m-%d",
    "%Y/%m/%d",
    "%m/%d/%Y",
    "%m-%d-%Y",
    "%B %d, %Y",
    "%b %d, %Y",
    "%B %d %Y",
    "%b %d %Y",
    "%d %B %Y",
    "%d %b %Y",
)


def canonical_date_string(s: str) -> str | None:
    """If s is a calendar date, return YYYY-MM-DD; else None."""
    raw = str(s).strip()
    if not raw or raw.upper() == "UNREADABLE":
        return None
    m = re.match(r"^(\d{4}-\d{2}-\d{2})", raw)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d").date().isoformat()
        except ValueError:
            pass
    for fmt in _DATE_PARSE_FORMATS:
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue
    return None


def _score_rank(sf: dict) -> tuple[int, int]:
    """Higher is better for picking a winning critical field."""
    label_order = {
        "exact": 8,
        "partial": 7,
        "format_mismatch": 7,
        "transcription_error": 5,
        "semantic_paraphrase": 5,
        "verbatim_quote": 5,
        "unreadable": 4,
        "missing": 3,
        "misattribution": 1,
        "hallucinated": 0,
    }
    return (int(sf.get("score", -99)), label_order.get(sf.get("label", ""), 0))


def best_response_deadline_score_generic(
    parsed: dict | None,
    exp_deadline: str,
    *,
    gt_by_generic: dict[str, str],
) -> tuple[dict, object | None]:
    """Pick best match to response_deadline from key_date or secondary_date (slot swap)."""
    if not parsed:
        sf = score_field(
            None,
            exp_deadline,
            field_name="key_date",
            all_extracted=None,
            gt_by_field=gt_by_generic,
        )
        return sf, None
    candidates: list[tuple[dict, object | None]] = []
    for k in ("key_date", "secondary_date"):
        val = parsed.get(k)
        candidates.append(
            (
                score_field(
                    val,
                    exp_deadline,
                    field_name=k,
                    all_extracted=parsed,
                    gt_by_field=gt_by_generic,
                ),
                val,
            )
        )
    best_sf, best_val = max(candidates, key=lambda t: _score_rank(t[0]))
    return best_sf, best_val


def is_abstention_value(v) -> bool:
    if v is None:
        return True
    s = str(v).strip().upper()
    return s in ("", "UNREADABLE", "UNCERTAIN")


def abstention_rate_for_keys(parsed: dict | None, keys: tuple[str, ...]) -> float:
    if not keys:
        return 0.0
    if not parsed:
        return 1.0
    return sum(1 for k in keys if is_abstention_value(parsed.get(k))) / len(keys)


def score_prompt_ablation_row(
    parsed: dict | None,
    artifact_id: str,
    gt: dict[str, dict[str, str]],
    prompt_condition: str,
) -> tuple[dict, dict, float]:
    """Field scores (prompt keys), critical deadline info, abstention rate."""
    fields_gt = gt.get(artifact_id, {})
    keys = field_keys_for_condition(prompt_condition)
    field_scores: dict = {}

    gt_by_generic: dict[str, str] = {}
    if prompt_condition == "generic":
        for gen_key in keys:
            gt_field = GENERIC_TO_GT_D01.get(gen_key)
            if gt_field and gt_field in fields_gt:
                gt_by_generic[gen_key] = fields_gt[gt_field]

    if prompt_condition == "generic":
        for gen_key in keys:
            gt_field = GENERIC_TO_GT_D01.get(gen_key)
            if not gt_field or gt_field not in fields_gt:
                continue
            field_scores[gen_key] = score_field(
                parsed.get(gen_key) if parsed else None,
                fields_gt[gt_field],
                field_name=gen_key,
                all_extracted=parsed,
                gt_by_field=gt_by_generic,
                ground_truth_raw=fields_gt[gt_field],
            )
    else:
        for k in keys:
            if k not in fields_gt:
                continue
            field_scores[k] = score_field(
                parsed.get(k) if parsed else None,
                fields_gt[k],
                field_name=k,
                all_extracted=parsed,
                gt_by_field=fields_gt,
                ground_truth_raw=fields_gt[k],
            )

    crit_key = critical_deadline_key(prompt_condition)
    exp_deadline = fields_gt.get("response_deadline", "")
    if prompt_condition == "generic":
        crit_sf, crit_val = best_response_deadline_score_generic(
            parsed, exp_deadline, gt_by_generic=gt_by_generic
        )
        critical_info = {
            "critical_field": crit_key,
            "critical_expected": exp_deadline,
            "critical_extracted": crit_val,
            "critical_label": crit_sf["label"],
            "critical_score": crit_sf["score"],
        }
    else:
        crit_val = parsed.get(crit_key) if parsed else None
        crit_sf = score_field(
            crit_val,
            exp_deadline,
            field_name=crit_key,
            all_extracted=parsed,
            gt_by_field=fields_gt,
            ground_truth_raw=exp_deadline,
        )
        critical_info = {
            "critical_field": crit_key,
            "critical_expected": exp_deadline,
            "critical_extracted": crit_val,
            "critical_label": crit_sf["label"],
            "critical_score": crit_sf["score"],
        }
    abst = abstention_rate_for_keys(parsed, keys)
    return field_scores, critical_info, abst


def score_field(
    extracted,
    expected: str,
    *,
    ground_truth_raw: str | None = None,
    field_name: str | None = None,
    all_extracted: dict | None = None,
    gt_by_field: dict[str, str] | None = None,
) -> dict:
    """
    Field-level score with multi-label taxonomy (see README «Scoring Rubric»).

    correct_field is False only for misattribution (value belongs to another slot).
    """
    _ = ground_truth_raw  # reserved for future raw-GT variants; scoring uses `expected`

    if extracted is None or (isinstance(extracted, str) and not extracted.strip()):
        return _sf("missing", correct_field=True)

    ext_s = str(extracted).strip()
    if ext_s.upper() == "UNREADABLE":
        return _sf("unreadable", correct_field=True)

    exp = str(expected).strip()

    # --- Dates: canonical equality → exact; else continue for format / transcription ---
    ext_d = canonical_date_string(ext_s)
    exp_d = canonical_date_string(exp)
    if ext_d is not None and exp_d is not None:
        if ext_d == exp_d:
            return _sf("exact", correct_field=True)
        # Different calendar dates: try aggressive / transcription on raw strings below
    elif ext_d is not None or exp_d is not None:
        # One side parses as date only — fall through to string rules
        pass

    ext_n = normalize(ext_s)
    exp_n = normalize(exp)
    if exp_n and ext_n == exp_n:
        return _sf("exact", correct_field=True)
    if exp_n and (exp_n in ext_n or ext_n in exp_n):
        return _sf("partial", correct_field=True)

    if exp_n and aggressive_normalize(ext_s) == aggressive_normalize(exp):
        return _sf("format_mismatch", correct_field=True)

    # Verbatim document text in the right field vs categorical GT (before misattribution)
    if is_verbatim_quote(ext_s, exp):
        return _sf("verbatim_quote", correct_field=True)

    # Misattribution: extracted aligns with another field's expected, not this one
    if (
        field_name
        and gt_by_field
        and all_extracted is not None
        and isinstance(all_extracted, dict)
    ):
        for other_field, other_exp in gt_by_field.items():
            if other_field == field_name:
                continue
            if not other_exp:
                continue
            if _matches_other_gt_value(ext_s, other_exp):
                return _sf("misattribution", correct_field=False)

    # Transcription / OCR slop vs *this* expected (ratio on standard normalize)
    if exp_n:
        denom = max(len(exp_n), 1)
        ratio = _lev_distance(ext_n, exp_n) / denom
        if ratio <= LEVENSHTEIN_THRESHOLD and not (exp_n in ext_n or ext_n in exp_n):
            return _sf("transcription_error", correct_field=True)

    if _semantic_paraphrase_ok(ext_s, exp):
        return _sf("semantic_paraphrase", correct_field=True)

    return _sf("hallucinated", correct_field=True)


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
    notice_preview_first: bool = False,
) -> dict:
    payload: dict = {
        "image": image_b64,
        "prompt": prompt,
        "track": track,
        "temperature": temperature,
        "notice_preview_first": notice_preview_first,
    }
    if token_budget is not None:
        payload["token_budget"] = token_budget

    effective_timeout = timeout * 3 if notice_preview_first else timeout

    t0 = time.time()
    try:
        r = requests.post(
            f"{phone_url}/infer", json=payload, timeout=effective_timeout
        )
        r.raise_for_status()
        data = r.json()
        out = {
            "response": data.get("response", ""),
            "elapsed_ms": data.get("elapsed_ms", int((time.time() - t0) * 1000)),
            "parse_ok": bool(data.get("parse_ok")),
            "error": None,
            "preview_elapsed_ms": data.get("preview_elapsed_ms"),
            "extract_elapsed_ms": data.get("extract_elapsed_ms"),
        }
        return out
    except requests.exceptions.Timeout:
        return {
            "response": "",
            "elapsed_ms": effective_timeout * 1000,
            "parse_ok": False,
            "error": "timeout",
            "preview_elapsed_ms": None,
            "extract_elapsed_ms": None,
        }
    except Exception as e:
        return {
            "response": "",
            "elapsed_ms": int((time.time() - t0) * 1000),
            "parse_ok": False,
            "error": str(e),
            "preview_elapsed_ms": None,
            "extract_elapsed_ms": None,
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
    prompt_condition: str | None = None,
    strict_infer: bool = False,
    echo_raw_response: bool = False,
) -> list[dict]:
    image_b64 = load_image_b64(artifact_id, variant)
    notice_preview_first = prompt_condition == "semantic-preview"
    if prompt_condition:
        prompt = build_extraction_prompt(prompt_condition)
    else:
        prompt = build_prompt(artifact_id, gt, track)
    fields = gt.get(artifact_id, {})

    results = []
    for i in range(n_runs):
        if prompt_condition:
            print(
                f"  {prompt_condition} {artifact_id} {variant} run {i + 1}/{n_runs}",
                end="\r",
                flush=True,
            )
        else:
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
            notice_preview_first=notice_preview_first,
        )
        if echo_raw_response:
            tag = f"{prompt_condition or 'gt-prompt'} {artifact_id} {variant} run {i + 1}/{n_runs}"
            print(f"\n--- raw_response ({tag}) ---", flush=True)
            body = infer_result.get("response")
            print(body if body else "(empty)", flush=True)
            if infer_result.get("error"):
                print(f"(infer error: {infer_result['error']})", flush=True)
            print("--- end raw_response ---\n", flush=True)

        if strict_infer:
            if infer_result.get("error"):
                raise InferStrictAbort(
                    f"/infer error on {artifact_id} {variant} run {i + 1}/{n_runs}: "
                    f"{infer_result['error']}"
                )
            if not str(infer_result.get("response") or "").strip():
                raise InferStrictAbort(
                    f"Empty /infer response on {artifact_id} {variant} run {i + 1}/{n_runs}; "
                    "halting so abstention-scored rows are not recorded as data."
                )

        parsed = parse_with_retry(infer_result["response"])

        if prompt_condition:
            field_scores, critical_info, abst_rate = score_prompt_ablation_row(
                parsed, artifact_id, gt, prompt_condition
            )
        else:
            critical_info = {}
            abst_rate = 0.0
            field_scores = {}
            if parsed and fields:
                for fname, expected in fields.items():
                    field_scores[fname] = score_field(
                        parsed.get(fname),
                        expected,
                        field_name=fname,
                        all_extracted=parsed,
                        gt_by_field=fields,
                        ground_truth_raw=expected,
                    )

        pts = [s["score"] for s in field_scores.values()]
        avg_score = sum(pts) / len(pts) if pts else None
        halluc_count = sum(1 for s in field_scores.values() if s["label"] == "hallucinated")

        record: dict = {
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
            "scoring_rubric_version": SCORING_RUBRIC_VERSION,
        }
        if prompt_condition:
            record["prompt_condition"] = prompt_condition
            record["prompt_ablation_version"] = PROMPT_ABLATION_VERSION
            record["notice_preview_first"] = notice_preview_first
            record["critical_field"] = critical_info.get("critical_field")
            record["critical_expected"] = critical_info.get("critical_expected")
            record["critical_extracted"] = critical_info.get("critical_extracted")
            record["critical_label"] = critical_info.get("critical_label")
            record["critical_score"] = critical_info.get("critical_score")
            record["abstention_rate"] = round(abst_rate, 6)
            record["preview_elapsed_ms"] = infer_result.get("preview_elapsed_ms")
            record["extract_elapsed_ms"] = infer_result.get("extract_elapsed_ms")

        results.append(record)

        if i < n_runs - 1:
            time.sleep(cooldown_s)

    print()
    return results


def rescore_jsonl_records(
    rows: list[dict], gt: dict[str, dict[str, str]]
) -> list[dict]:
    """Recompute field_scores (and prompt-ablation critical_*) from raw_response."""
    out: list[dict] = []
    for r in rows:
        rec = dict(r)
        parsed = parse_with_retry(rec.get("raw_response") or "")
        aid = rec.get("artifact_id", "")
        pc = rec.get("prompt_condition")
        if pc:
            fs, crit, abst = score_prompt_ablation_row(parsed, aid, gt, pc)
            rec["field_scores"] = fs
            rec["critical_field"] = crit.get("critical_field")
            rec["critical_expected"] = crit.get("critical_expected")
            rec["critical_extracted"] = crit.get("critical_extracted")
            rec["critical_label"] = crit.get("critical_label")
            rec["critical_score"] = crit.get("critical_score")
            rec["abstention_rate"] = round(abst, 6)
        else:
            fields = gt.get(aid, {})
            fs = {}
            if parsed and fields:
                for fname, expected in fields.items():
                    fs[fname] = score_field(
                        parsed.get(fname),
                        expected,
                        field_name=fname,
                        all_extracted=parsed,
                        gt_by_field=fields,
                        ground_truth_raw=expected,
                    )
            rec["field_scores"] = fs
        pts = [s["score"] for s in rec["field_scores"].values()]
        rec["avg_score"] = round(sum(pts) / len(pts), 4) if pts else None
        rec["hallucination_count"] = sum(
            1 for s in rec["field_scores"].values() if s.get("label") == "hallucinated"
        )
        rec["parse_ok"] = parsed is not None
        rec["scoring_rubric_version"] = SCORING_RUBRIC_VERSION
        out.append(rec)
    return out


def print_prompt_ablation_report(rows: list[dict]) -> None:
    """Stdout table: condition × variant → deadline accuracy, hallucination, abstention, latency."""
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in rows:
        pc = r.get("prompt_condition")
        if not pc:
            continue
        groups[(pc, r["variant"])].append(r)

    print("\n=== Prompt ablation report (by condition × variant) ===\n")
    for (pc, var) in sorted(groups.keys()):
        g = groups[(pc, var)]
        n = len(g)
        crit_exact = sum(1 for x in g if x.get("critical_label") == "exact")
        crit_partial = sum(1 for x in g if x.get("critical_label") == "partial")
        crit_accept = sum(
            1
            for x in g
            if x.get("critical_label")
            in {
                "exact",
                "partial",
                "format_mismatch",
                "transcription_error",
                "semantic_paraphrase",
                "verbatim_quote",
            }
        )
        labels = [s["label"] for x in g for s in x.get("field_scores", {}).values()]
        hall = sum(1 for lb in labels if lb == "hallucinated")
        label_hist: dict[str, int] = defaultdict(int)
        for lb in labels:
            label_hist[lb] += 1
        abst_mean = sum(x.get("abstention_rate", 0) or 0 for x in g) / n if n else 0
        lat = [x["elapsed_ms"] for x in g if x.get("elapsed_ms")]
        lat_mean = sum(lat) / len(lat) if lat else 0

        print(f"** {pc} / {var} ** (n={n})")
        print(
            f"  critical_deadline exact: {crit_exact}/{n} "
            f"({100 * crit_exact / n:.1f}%), partial: {crit_partial}, "
            f"acceptable (incl. format/transcribe/paraphrase): {crit_accept}/{n}"
        )
        print(
            f"  field hallucinated rate (strict): {100 * hall / len(labels):.1f}% "
            f"({hall}/{len(labels)} field judgments)"
            if labels
            else "  field hallucinated rate: n/a"
        )
        if labels:
            parts = [
                f"{k}={v}" for k, v in sorted(label_hist.items(), key=lambda kv: -kv[1])
            ]
            print(f"  field label counts: {', '.join(parts)}")
        print(f"  mean abstention_rate (per run): {100 * abst_mean:.1f}%")
        print(f"  mean latency_ms: {lat_mean:.0f}")
        print()


def compute_summary(results: list[dict]) -> dict:
    scored = [r for r in results if r["avg_score"] is not None]
    if not scored:
        return {}

    scores = [r["avg_score"] for r in scored]
    latencies = [r["elapsed_ms"] for r in results if r["elapsed_ms"]]
    all_labels = [s["label"] for r in scored for s in r["field_scores"].values()]

    n_fields = len(all_labels)
    mean_s = sum(scores) / len(scores)

    label_counts: dict[str, int] = defaultdict(int)
    for lb in all_labels:
        label_counts[lb] += 1
    merged_counts = {lab: label_counts.get(lab, 0) for lab in FIELD_SCORE_LABELS}
    for lab, c in label_counts.items():
        if lab not in merged_counts:
            merged_counts[lab] = c

    out: dict = {
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
        "format_mismatch_rate": all_labels.count("format_mismatch") / n_fields
        if n_fields
        else 0,
        "transcription_error_rate": all_labels.count("transcription_error") / n_fields
        if n_fields
        else 0,
        "semantic_paraphrase_rate": all_labels.count("semantic_paraphrase") / n_fields
        if n_fields
        else 0,
        "verbatim_quote_rate": all_labels.count("verbatim_quote") / n_fields
        if n_fields
        else 0,
        "misattribution_rate": all_labels.count("misattribution") / n_fields
        if n_fields
        else 0,
        "missing_rate": all_labels.count("missing") / n_fields if n_fields else 0,
        "unreadable_rate": all_labels.count("unreadable") / n_fields
        if n_fields
        else 0,
        "field_label_counts": merged_counts,
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
    if n_fields:
        for lab in FIELD_SCORE_LABELS:
            out[f"field_label_rate_{lab}"] = label_counts.get(lab, 0) / n_fields
    else:
        for lab in FIELD_SCORE_LABELS:
            out[f"field_label_rate_{lab}"] = 0.0
    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--artifacts",
        default="",
        help="Comma-separated artifact ids, e.g. D01,D03 (not used with --rescore)",
    )
    p.add_argument(
        "--rescore",
        type=Path,
        default=None,
        metavar="PATH",
        help="Load existing JSONL and re-score field_scores from raw_response (no inference)",
    )
    p.add_argument("--track", default="a", help="Track label for logging (default: a)")
    p.add_argument(
        "--variants",
        default="clean,degraded",
        help="Comma-separated: clean (PDF), clean_jpeg (raster from PDF), degraded, blurry, "
        "or custom degraded basename",
    )
    p.add_argument("--runs", type=int, default=20, help="Monte Carlo iterations per cell")
    p.add_argument("--temp", type=float, default=0.0, dest="temperature")
    p.add_argument("--cooldown", type=float, default=2.0)
    p.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_EVAL_JSONL_OUT,
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
    p.add_argument(
        "--semantic-preview",
        action="store_true",
        help="Run only the semantic-preview ablation condition on D01 (notice preview + "
        "extract). Equivalent to --prompt-condition semantic-preview; default --artifacts D01 "
        "if omitted. Mutually exclusive with --prompt-condition and --ablation.",
    )
    p.add_argument(
        "--prompt-condition",
        default="",
        help="Comma-separated: generic, semantic, semantic-preview (D01 prompt ablation; "
        "see prompt_conditions.py). Incompatible with --ablation. For preview alone, prefer "
        "--semantic-preview.",
    )
    p.add_argument(
        "--condition-break-s",
        type=float,
        default=180.0,
        help="Seconds to wait between prompt-condition batches when multiple conditions "
        "are run in one process (default: 180). Use 0 to disable.",
    )
    p.add_argument(
        "--health-max-mean-ms",
        type=float,
        default=200.0,
        help="Max mean /health RTT in ms (3 pings) before pre-batch retry (default: 200)",
    )
    p.add_argument(
        "--health-retry-wait-s",
        type=float,
        default=30.0,
        help="Seconds to wait after a failed pre-batch health check (default: 30)",
    )
    p.add_argument(
        "--health-max-rounds",
        type=int,
        default=3,
        help="Pre-batch health rounds before halting (default: 3)",
    )
    p.add_argument(
        "--no-strict-infer",
        action="store_true",
        help="Record rows even when /infer errors or returns an empty body "
        "(default: strict for --prompt-condition runs)",
    )
    p.add_argument(
        "--print-raw-response",
        action="store_true",
        help="Print each model raw_response to stdout (diagnostics)",
    )
    p.add_argument(
        "--skip-prebatch-health",
        action="store_true",
        help="Skip latency-gated /health before each prompt-condition batch (not recommended)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    phone_url = (args.phone_url or "").strip().rstrip("/") or phone_base_url()

    gt = load_ground_truth()

    if args.rescore is not None:
        if not args.rescore.is_file():
            print(f"ERROR: --rescore file not found: {args.rescore}", file=sys.stderr)
            return 1
        rows_in: list[dict] = []
        with args.rescore.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    rows_in.append(json.loads(line))
        new_rows = rescore_jsonl_records(rows_in, gt)
        out_path = args.out.resolve()
        if out_path == DEFAULT_EVAL_JSONL_OUT.resolve():
            out_path = args.rescore.with_name(
                args.rescore.stem + "_rescored_v3.jsonl"
            ).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as f:
            for row in new_rows:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        summary = compute_summary(new_rows)
        print(json.dumps(summary, indent=2))
        prompt_rows = [r for r in new_rows if r.get("prompt_condition")]
        if prompt_rows:
            print_prompt_ablation_report(prompt_rows)
        print(f"Rescored {len(new_rows)} lines to {out_path}")
        return 0

    if args.semantic_preview:
        if args.ablation:
            print(
                "ERROR: --semantic-preview cannot be used with --ablation",
                file=sys.stderr,
            )
            return 1
        if (args.prompt_condition or "").strip():
            print(
                "ERROR: use either --semantic-preview or --prompt-condition, not both",
                file=sys.stderr,
            )
            return 1
        args.prompt_condition = "semantic-preview"
        if not (args.artifacts or "").strip():
            args.artifacts = "D01"

    if not (args.artifacts or "").strip():
        print(
            "ERROR: --artifacts is required unless using --rescore",
            file=sys.stderr,
        )
        return 1

    artifacts = [a.strip() for a in args.artifacts.split(",") if a.strip()]
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]

    prompt_conditions = [
        x.strip() for x in args.prompt_condition.split(",") if x.strip()
    ]
    valid_pc = {"generic", "semantic", "semantic-preview"}
    for pc in prompt_conditions:
        if pc not in valid_pc:
            print(f"ERROR: unknown --prompt-condition {pc!r}", file=sys.stderr)
            return 1
    if prompt_conditions and args.ablation:
        print(
            "ERROR: use either --prompt-condition or --ablation, not both",
            file=sys.stderr,
        )
        return 1
    if prompt_conditions:
        bad = [a for a in artifacts if a != "D01"]
        if bad:
            print(
                "ERROR: prompt ablation (--prompt-condition / --semantic-preview) is only "
                "wired for artifact D01 (field keys + GENERIC_TO_GT in prompt_conditions.py).\n"
                "For cross-artifact runs without generic-vs-semantic prompts, omit "
                "--prompt-condition: the runner builds JSON keys from ground_truth.csv per artifact.",
                file=sys.stderr,
            )
            return 1
        if args.token_budget is not None:
            print(
                "NOTE: ignoring --token-budget during prompt ablation "
                "(same default max tokens on device for all conditions).",
                file=sys.stderr,
            )

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

    strict_infer = bool(prompt_conditions) and not args.no_strict_infer

    if not prompt_conditions:
        try:
            h = requests.get(f"{phone_url}/health", timeout=10)
            h.raise_for_status()
        except Exception as e:
            print(f"ERROR: /health failed ({phone_url}): {e}", file=sys.stderr)
            return 1

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

    if prompt_conditions:
        for i_pc, pc in enumerate(prompt_conditions):
            if not args.skip_prebatch_health:
                try:
                    ensure_health_before_condition_batch(
                        phone_url,
                        max_mean_ms=args.health_max_mean_ms,
                        wait_between_rounds_s=args.health_retry_wait_s,
                        max_rounds=args.health_max_rounds,
                    )
                except RuntimeError as e:
                    print(str(e), file=sys.stderr)
                    return 1
            else:
                print("WARNING: skipping pre-batch /health latency gate (--skip-prebatch-health)")

            for aid in artifacts:
                for variant in variants:
                    try:
                        rows = run_experiment(
                            phone_url,
                            aid,
                            variant,
                            args.track,
                            args.runs,
                            args.temperature,
                            None,
                            gt,
                            cooldown_s=args.cooldown,
                            infer_timeout=args.infer_timeout,
                            prompt_condition=pc,
                            strict_infer=strict_infer,
                            echo_raw_response=args.print_raw_response,
                        )
                    except InferStrictAbort as e:
                        print(f"ERROR: {e}", file=sys.stderr)
                        return 1
                    all_rows.extend(rows)

            if i_pc < len(prompt_conditions) - 1 and args.condition_break_s > 0:
                condition_break_countdown(args.condition_break_s)
    else:
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
    if prompt_conditions:
        print_prompt_ablation_report(all_rows)
    print(f"Wrote {len(all_rows)} lines to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
