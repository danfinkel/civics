# Blur & image-quality eval outputs

**Canonical path** for [`blur_testing.ipynb`](../blur_testing.ipynb) runs. Point `real_photo_characterizer.py` here so CSVs, `converted/`, and reports land next to the notebook.

From `research/eval` (Jupyter’s cwd is often this directory):

```bash
python3 real_photo_characterizer.py --photos /path/to/your/photos --out results/blur_testing --backend ollama
```

From the **repo root**:

```bash
python3 research/eval/real_photo_characterizer.py --photos /path/to/your/photos --out research/eval/results/blur_testing --backend ollama
```

**Default** for the tool if you omit `--out` is still `research/eval/results/real_photo_analysis/`; use `--out` as above for blur work.

**Typical files** in this directory after a full run: `photo_attributes.csv`, `eval_runs.csv`, `attribute_ranking.csv`, `summary.md`, `converted/`, etc.

You can also place **side-by-side exports** (e.g. `eval_runs_clean.csv`, `eval_runs_some_motion.csv`) in this folder for comparison; the notebook discovers `RESULT_DIR` from `photo_attributes.csv`’s parent.

The parent `results/` tree is usually gitignored; this README is tracked so the path stays documented in-repo.
