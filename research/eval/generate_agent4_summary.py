#!/usr/bin/env python3
"""Build research/eval/summary_for_agent4.md from one or more runner JSONL files."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from runner import compute_summary  # noqa: E402


def load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def pct(x: float) -> str:
    return f"{100.0 * x:.1f}%"


def fmt_ms(x: float) -> str:
    return f"{int(round(x)):,}"


def summarize_by_token_budget(rows: list[dict]) -> list[tuple[int | None, dict]]:
    budgets = sorted(
        {r.get("token_budget") for r in rows},
        key=lambda b: (b is None, b or 0),
    )
    if len(budgets) <= 1:
        return [(budgets[0] if budgets else None, compute_summary(rows))]
    out: list[tuple[int | None, dict]] = []
    for b in budgets:
        sub = [r for r in rows if r.get("token_budget") == b]
        if sub:
            out.append((b, compute_summary(sub)))
    return out


def markdown_block(
    *,
    device: str,
    files: list[Path],
    combined_rows: list[dict],
) -> str:
    lines: list[str] = [
        "# Eval results summary for Kaggle writeup",
        "",
        f"_Generated from JSONL runs. Device note: **{device}**._",
        "",
        "## Input files",
        "",
    ]
    for p in files:
        lines.append(f"- `{p}`")
    lines.extend(["", "## Accuracy metrics (combined)", ""])

    s_all = compute_summary(combined_rows)
    if not s_all:
        lines.append("_No scored rows (empty or missing field scores)._")
    else:
        lines.extend(
            [
                f"- **Parse OK rate:** {pct(s_all['parse_ok_rate'])}",
                f"- **Field exact match rate:** {pct(s_all['exact_rate'])}",
                f"- **Field partial match rate:** {pct(s_all['partial_rate'])}",
                f"- **Hallucination rate (field-level):** {pct(s_all['hallucination_rate'])}",
                f"- **Missing rate:** {pct(s_all['missing_rate'])}",
                f"- **Unreadable rate:** {pct(s_all['unreadable_rate'])}",
                f"- **Avg score mean (0–2 scale):** {s_all['avg_score_mean']:.4f}",
                "",
                "Document-level classification (if needed for narrative): see spike / separate experiments — this harness scores **field extraction** vs `ground_truth.csv`.",
                "",
            ]
        )

    lines.extend(["## Latency metrics (combined)", ""])
    if s_all:
        lines.extend(
            [
                f"- **Mean:** {fmt_ms(s_all['latency_mean_ms'])} ms",
                f"- **P95:** {fmt_ms(s_all['latency_p95_ms'])} ms",
                f"- **Std dev:** {fmt_ms(s_all['latency_std_ms'])} ms",
                "",
            ]
        )
    else:
        lines.append("_No latency data._\n")

    # Per-file snippets
    lines.extend(["## Per-file summaries", ""])
    for p in files:
        rows = load_rows(p)
        s = compute_summary(rows)
        lines.append(f"### `{p.name}`")
        lines.append("")
        if not s:
            lines.append("_Empty or unscored._\n")
            continue
        lines.append(f"- Runs: {s['n_runs']}, scored rows: {s['n_scored']}")
        lines.append(f"- Parse OK: {pct(s['parse_ok_rate'])}, avg score: {s['avg_score_mean']:.4f}")
        lines.append(
            f"- Latency mean / p95: {fmt_ms(s['latency_mean_ms'])} / {fmt_ms(s['latency_p95_ms'])} ms"
        )
        lines.append("")

    # Token budget table if ablation
    by_tb = summarize_by_token_budget(combined_rows)
    if len(by_tb) > 1:
        lines.extend(["## Token budget tradeoff", "", "| Budget | Avg score | Latency mean (ms) | Parse OK |", "|--------|-----------|-------------------|----------|"])
        for b, s in by_tb:
            if not s:
                continue
            bb = "default" if b is None else str(b)
            lines.append(
                f"| {bb} | {s['avg_score_mean']:.4f} | {fmt_ms(s['latency_mean_ms'])} | {pct(s['parse_ok_rate'])} |"
            )
        lines.append("")
        lines.append("_Interpretation:_ higher budgets often improve completeness on long JSON; compare hallucination_rate in per-budget slices if you split JSONL by `token_budget`.")
        lines.append("")

    lines.extend(
        [
            "## Raw data",
            "",
            "All source rows: paths listed above under **Input files**.",
            "",
            "Optional plots:",
            "",
            "```bash",
            "python plot_run_latency.py results/your_run.jsonl -o results/latency.png",
            "```",
            "",
        ]
    )

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "jsonl",
        type=Path,
        nargs="+",
        help="One or more runner.py JSONL outputs",
    )
    ap.add_argument(
        "-o",
        "--out",
        type=Path,
        default=Path("summary_for_agent4.md"),
        help="Output markdown path",
    )
    ap.add_argument(
        "--device",
        default="iPhone (on-device Gemma 4 E2B, llama.cpp)",
        help="Device string for the summary header",
    )
    args = ap.parse_args()

    files: list[Path] = []
    combined: list[dict] = []
    for p in args.jsonl:
        if not p.is_file():
            print(f"ERROR: not a file: {p}", file=sys.stderr)
            return 1
        files.append(p.resolve())
        combined.extend(load_rows(p))

    text = markdown_block(device=args.device, files=files, combined_rows=combined)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
