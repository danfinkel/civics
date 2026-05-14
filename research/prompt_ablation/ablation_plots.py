"""Shared loaders + plotting for D01 prompt ablation JSONLs (research/eval/runner.py)."""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def hallucination_rates_by_variant(rows: list[dict]) -> pd.DataFrame:
    """One row per variant: critical_label == hallucinated rate + row count."""
    df = pd.json_normalize(rows)
    if df.empty:
        raise ValueError("empty rows")
    out = (
        df.groupby("variant", sort=False)
        .agg(
            rows=("run", "count"),
            halluc_frac=("critical_label", lambda s: float((s == "hallucinated").mean())),
        )
        .reset_index()
    )
    return out


def plot_single_condition_variant_bars(
    rows: list[dict],
    *,
    title: str,
    save_path: Path,
    ymax: float = 105,
) -> None:
    tbl = hallucination_rates_by_variant(rows)
    save_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(6, 4))
    xv = range(len(tbl))
    ax.bar(xv, 100 * tbl["halluc_frac"], color="#4e79a7")
    ax.set_xticks(list(xv), tbl["variant"].tolist(), rotation=25, ha="right")
    ax.set_ylim(0, ymax)
    ax.set_ylabel("critical_label = hallucinated (%)")
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_generic_vs_semantic_grouped(
    generic_rows: list[dict],
    semantic_rows: list[dict],
    *,
    save_path: Path,
    ymax: float = 105,
) -> None:
    g = hallucination_rates_by_variant(generic_rows).rename(
        columns={"halluc_frac": "generic"}
    )[["variant", "generic"]]
    s = hallucination_rates_by_variant(semantic_rows).rename(
        columns={"halluc_frac": "semantic"}
    )[["variant", "semantic"]]
    merged = g.merge(s, on="variant", how="outer")
    merged = merged.sort_values("variant")
    variants = merged["variant"].tolist()
    x = range(len(variants))
    w = 0.35
    save_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar([i - w / 2 for i in x], 100 * merged["generic"].fillna(0), width=w, label="generic")
    ax.bar([i + w / 2 for i in x], 100 * merged["semantic"].fillna(0), width=w, label="semantic")
    ax.set_xticks(list(x), variants, rotation=25, ha="right")
    ax.set_ylim(0, ymax)
    ax.set_ylabel("critical hallucinated (%)")
    ax.set_title("D01: generic vs semantic (by artifact variant)")
    ax.legend()
    fig.tight_layout()
    fig.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
