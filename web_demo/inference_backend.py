"""
Select inference implementation at import time.

- Default `ollama`: `inference.py` + local Ollama (desktop dev).
- `hf`: `inference_hf.py` + Transformers on GPU / local weights (Docker / HF Spaces GPU).
- `hf_api`: `inference_hf_api.py` + Hugging Face Inference API (hosted, small RAM; HF_TOKEN billing).

See README for Dockerfile / env knobs.
"""

from __future__ import annotations

import os

_BACKEND = os.environ.get("CIVICLENS_INFERENCE_BACKEND", "ollama").lower().strip()

if _BACKEND in ("hf_api", "hf-inference", "hub", "inference"):
    from inference_hf_api import run_track_a, run_track_b
elif _BACKEND in ("hf", "huggingface", "transformers"):
    from inference_hf import run_track_a, run_track_b
else:
    from inference import run_track_a, run_track_b

__all__ = ["run_track_a", "run_track_b"]
