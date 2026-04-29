FROM python:3.11-slim

WORKDIR /app

# Bump when you must force HF Spaces to invalidate Docker layer cache without code changes (optional).
ARG CIVICLENS_CSS_BUNDLE=2026-04-29b
ENV CIVICLENS_CSS_BUNDLE=$CIVICLENS_CSS_BUNDLE

# Hosted Gemma via Hugging Face Inference Providers — no GPU or local model weights on this Space.
# For self-hosted Gemma (Transformers + GPU), use: CIVICLENS_INFERENCE_BACKEND=hf + COPY requirements_hf.txt
ENV CIVICLENS_INFERENCE_BACKEND=hf_api

RUN apt-get update && apt-get install -y \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY requirements_hf_api.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py .
COPY branding ./branding
COPY sample_docs ./sample_docs

EXPOSE 7860

CMD ["python", "api.py"]
