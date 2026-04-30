"""
Day 1 re-run with prompt fixes.

Re-runs the artifacts that had issues in the initial Day 1 run:
- D01 degraded (timeout)
- D02 degraded (empty response - prompt field mismatch)
- D05 clean (timeout)
- D08 degraded (empty response - prompt field mismatch)
- D12 degraded (empty response - JSON format issue)
- D16 clean (timeout)

Usage:
  cd spike/scripts/day1
  python day1_rerun_fixed.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

def main() -> None:
    # Jobs to re-run: these were the problematic ones from Day 1
    jobs = [
        "D01:degraded",  # timeout
        "D02:degraded",  # empty response
        "D05:clean",     # timeout
        "D08:degraded",  # empty response
        "D12:degraded",  # empty response / JSON issue
        "D16:clean",     # timeout
    ]

    jobs_arg = ",".join(jobs)

    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "day1_extract.py"),
        "--jobs", jobs_arg,
        "--http-timeout", "900",
        "--pdf-dpi", "100",
        "--out", str(SCRIPT_DIR / "day1_rerun_results.jsonl"),
    ]

    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=SCRIPT_DIR)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
