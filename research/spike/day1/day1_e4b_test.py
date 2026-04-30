"""
Day 1 E4B head-to-head test on worst-performing artifacts.

Tests the 5 artifacts with worst E2B results to see if E4B improves extraction.

Usage:
  cd spike/scripts/day1
  python day1_e4b_test.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

def main() -> None:
    # Worst 5 artifacts from E2B run (by avg_score)
    jobs = [
        "D01:degraded",   # timeout / worst performer
        "D02:degraded",   # all empty
        "D11:degraded",   # -1.0 score
        "D03:degraded",   # -0.25 score
        "D06:degraded",   # -0.22 score
    ]

    jobs_arg = ",".join(jobs)

    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "day1_extract.py"),
        "--jobs", jobs_arg,
        "--model", "gemma4:e4b",
        "--http-timeout", "900",
        "--pdf-dpi", "100",
        "--out", str(SCRIPT_DIR / "day1_e4b_results.jsonl"),
    ]

    print(f"Running E4B test on worst 5 artifacts...")
    print(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=SCRIPT_DIR)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
