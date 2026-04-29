---
title: CivicLens
emoji: 🏛
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
---

# CivicLens Web Demo

A privacy-first civic document intelligence demo using Gemma 4 E4B.

## Overview

This web demo helps residents prepare document packets for:
- **SNAP Benefits** (Track A): Check recertification documents against DTA notices
- **School Enrollment** (Track B): Verify BPS registration packet completeness

## Features

- Document upload (PDF, JPG, PNG)
- Blur detection pre-processing
- Gemma 4 E4B inference via Ollama
- Confidence visualization with color-coded results
- Plain-language action summaries

## Local Development

1. Install Ollama and pull Gemma 4 E4B:
```bash
ollama pull gemma4:e4b
```

2. Install Python dependencies:
```bash
pip install -r requirements.txt
```

3. Run the app (uses **Ollama** via `inference.py` by default):

```bash
python app.py
```

The app will be available at http://localhost:7860

### Push to Hugging Face Space

1. Create an access token at [Hugging Face settings](https://huggingface.co/settings/tokens) with **write** access.
2. Either `export HF_TOKEN=hf_...` in your shell, or create `web_demo/.env` containing `HF_TOKEN=hf_...` (this file is gitignored).
3. From the repo root (use a venv that has `requirements.txt` installed, including `huggingface_hub`):

```bash
cd web_demo
python deploy.py
```

The script uploads a fixed allow-list of files to the Space set in `deploy.py` (`repo_id`, default `DanFinkel/civiclens`)—only what the Docker Space needs, not `.venv` or `deploy.py`. Transient **HTTP 500** errors from the Hub are retried with backoff; if a push still fails, wait a few minutes and run `python deploy.py` again.

**Note:** keep `web_demo/.venv` only on your machine — never commit it, and the deploy script excludes it from uploads.

## Deployment

### Hosted inference (`hf_api`) — default Dockerfile

Uses **`inference_hf_api.py`** + **`InferenceClient`** (no Gemma weights in the Space; **CPU‑only Spaces are fine**).

1. **HF Space secrets:** **`HF_TOKEN`** with Inference Providers / API access.

2. **Model + provider defaults:** **`zai-org/GLM-4.5V`** via **`CIVICLENS_HF_INFERENCE_PROVIDER=novita`** (unset env uses these defaults in code). **Do not rely on Llama Vision IDs** — many show **zero** Inference Provider mappings on the Hub router (“not supported by any provider you have enabled”). **Gemma multimodal** is often rejected as “not a chat model” on `chat completions`; use **`CIVICLENS_INFERENCE_BACKEND=hf`** + GPU for Gemma locally.

3. **Account:** open https://huggingface.co/settings/inference-providers — **enable** the providers your model uses (e.g. **Novita**, **Z.ai**) and accept any **gated model** licenses on the model cards.

4. **Optional overrides:** **`CIVICLENS_HF_INFERENCE_MODEL_ID`**, **`CIVICLENS_HF_INFERENCE_PROVIDER`** (`zai-org`, **`auto`** / empty string for Hub auto-router), **`CIVICLENS_MAX_*`**.

5. **Deploy:** from `web_demo/`, **`python deploy.py`**, etc. Dockerfile sets **`CIVICLENS_INFERENCE_BACKEND=hf_api`**.

### Self‑hosted Gemma on a GPU Space (`hf`)

Use **`inference_hf.py`** (Transformers + local weights). In the **Dockerfile**, set **`ENV CIVICLENS_INFERENCE_BACKEND=hf`**, **`COPY requirements_hf.txt requirements.txt`**, add GPU libs if needed (see previous image), and pick a **GPU** in Space hardware. Default checkpoint **`google/gemma-4-E2B-it`**; **`CIVICLENS_HF_MODEL_ID`** for **`google/gemma-4-E4B-it`** on larger GPUs. **Set `HF_TOKEN`** for reliable Hub downloads. CPU‑only is blocked unless **`CIVICLENS_ALLOW_CPU_INFERENCE=1`**.

On CUDA (local `hf` only), **`CIVICLENS_QUANTIZATION`** defaults to **`4bit`**. Quantized loads default **`low_cpu_mem_usage=True`**; **`CIVICLENS_LOW_CPU_MEM_USAGE=0`** if meta-tensor errors return. **`CIVICLENS_DEVICE_MAP`** defaults **`sequential`** (safer peak RAM than `{"" : 0}` on small hosts); use **`single`** for `{ "" : 0 }`. **`CIVICLENS_ATTN_IMPLEMENTATION`** applies to local loads only.

**Both backends:** **`CIVICLENS_MAX_NEW_TOKENS`**, **`CIVICLENS_MAX_IMAGE_SIZE`**, **`CIVICLENS_MAX_INPUT_IMAGES`** tune upload size and generation length.

Local dev defaults to **`ollama`** (`inference.py`) when that variable is unset.

This demo is designed for Hugging Face Spaces. Push to a Space with:
- SDK: Docker
- Port: 7860

## Privacy Notice

This demo processes documents on the server where it's hosted. For true
privacy with on-device inference, use the CivicLens mobile app.

## Architecture

- **Gradio**: Web UI framework
- **Ollama**: Local LLM inference
- **Gemma 4 E4B**: Multimodal document understanding
- **Blur detection**: Laplacian variance method

## Design System

Based on the CivicLens Institutional design system:
- Primary: #002444 (dark navy)
- Success: #10B981 (green)
- Warning: #F59E0B (amber)
- Error: #EF4444 (red)
- Font: Inter
