"""
Alternative inference engine for Hugging Face Spaces.

This version uses Hugging Face's Transformers library with Gemma 4
instead of Ollama, for better compatibility with HF Spaces.
"""

from __future__ import annotations

import gc
import inspect
import io
import os
from pathlib import Path
from typing import Any

from PIL import Image
from transformers import BitsAndBytesConfig
from transformers import AutoProcessor, Gemma4ForConditionalGeneration
import torch

from inference_common import (
    max_input_images,
    max_new_tokens,
    parse_json_response,
    preprocess_image,
)
from prompts import build_track_a_prompt, build_track_b_prompt
from upload_utils import coerce_track_a_files, coerce_track_b_files

# Default to E2B on HF: fits 16 GiB Spaces. Override with google/gemma-4-E4B-it on larger GPUs.
MODEL_ID = os.environ.get(
    "CIVICLENS_HF_MODEL_ID",
    "google/gemma-4-E2B-it",
)


# Global model cache
_model = None
_processor = None


def _bnb_quantization_config(quant_mode: str) -> BitsAndBytesConfig | None:
    """4-bit / 8-bit quantization to fit Gemma E4B on ~16GiB GPUs (e.g. HF Spaces)."""
    q = quant_mode.strip().lower()
    if q in ("", "none", "off", "false", "no", "bf16"):
        return None
    if q in ("4bit", "4-bit", "nf4", "4"):
        return BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
        )
    if q in ("8bit", "8-bit", "8"):
        return BitsAndBytesConfig(load_in_8bit=True)
    print(
        f"[civiclens_hf] Unknown CIVICLENS_QUANTIZATION={quant_mode!r}; loading without quantization.",
        flush=True,
    )
    return None


def _resolve_quantization_mode() -> str:
    raw = os.environ.get("CIVICLENS_QUANTIZATION")
    if raw is None:
        return "4bit" if torch.cuda.is_available() else "none"
    return raw.strip()


def _bnb_available() -> bool:
    try:
        import bitsandbytes  # noqa: F401

        return True
    except ImportError:
        return False


def _hub_auth_kwargs() -> dict[str, Any]:
    """HF Spaces inject HF_TOKEN for gated repos; harmless for public models."""
    token = (
        os.environ.get("HF_TOKEN")
        or os.environ.get("HUGGING_FACE_HUB_TOKEN")
        or os.environ.get("HUGGINGFACE_HUB_TOKEN")
    )
    return {"token": token} if token else {}


def _ensure_hf_hub_ram_budget() -> None:
    """Tiny RAM Spaces OOM during Hub download + layered safetensors materialization."""
    os.environ.setdefault("HF_HUB_DOWNLOAD_NUM_WORKERS", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")


def _require_cuda_for_multimodal() -> None:
    """
    bitsandbytes 4-bit and bf16 multimodal inference target a CUDA GPU.
    CPU-only Spaces try to float32-load the whole model — will OOM 16 GiB RAM quickly.
    """
    if torch.cuda.is_available():
        return
    if os.environ.get("CIVICLENS_ALLOW_CPU_INFERENCE", "").strip().lower() in (
        "1",
        "true",
        "yes",
    ):
        print(
            "[civiclens_hf] CIVICLENS_ALLOW_CPU_INFERENCE=1 — loading on CPU (very slow; may still OOM).",
            flush=True,
        )
        return
    raise RuntimeError(
        "CUDA is not available (torch.cuda.is_available() is False). "
        "This demo needs a GPU: 4-bit quantization and bf16 inference are not run on CPU here.\n\n"
        "Hugging Face Spaces: open the Space → Settings → Hardware → "
        "Accelerators → pick a GPU (e.g. T4), save, then Restart Space.\n\n"
        "Optional: set Space secret HF_TOKEN (read) for reliable model downloads.\n\n"
        "Only for local experiments: CIVICLENS_ALLOW_CPU_INFERENCE=1 (not supported on free RAM)."
    )


def _device_map_kw() -> Any:
    """
    Sequential placement reduces peak allocations vs one giant GPU dump on cramped hosts.
    CIVICLENS_DEVICE_MAP: sequential (default), auto, or single -> {"" : 0}
    """
    raw = os.environ.get("CIVICLENS_DEVICE_MAP", "").strip().lower()
    if raw in ("", "sequential"):
        return {"device_map": "sequential"}
    if raw == "auto":
        return {"device_map": "auto"}
    if raw in ("single", "one", "cuda0", "gpu0"):
        return {"device_map": {"": 0}}
    return {"device_map": "sequential"}


def _from_pretrained_kw() -> dict[str, Any]:
    """Optional mmap for safetensors (lower RSS on some transformers versions)."""
    kwargs: dict[str, Any] = {}
    sig = inspect.signature(Gemma4ForConditionalGeneration.from_pretrained)
    if "mmap" in sig.parameters:
        kwargs["mmap"] = True
    return kwargs


def get_model():
    """Get or load the Gemma 4 model."""
    global _model, _processor
    if _model is None:
        _ensure_hf_hub_ram_budget()
        _require_cuda_for_multimodal()
        auth = _hub_auth_kwargs()
        if auth.get("token") is None:
            print(
                "[civiclens_hf] Set HF_TOKEN in Space secrets — anonymous downloads have "
                "low rate limits; retries/timeouts can inflate RAM spikes while caching shards.",
                flush=True,
            )

        quant_mode = _resolve_quantization_mode()
        qc = _bnb_quantization_config(quant_mode) if torch.cuda.is_available() else None
        if qc is not None and not _bnb_available():
            print(
                "[civiclens_hf] bitsandbytes not installed; falling back to bf16 (may OOM on 16 GiB).",
                flush=True,
            )
            qc = None

        # BF16 materialization + multimodal spikes host RAM above 16 Gi container limits.
        # Quantized loads: prefer low_cpu_mem_usage=True to stagger weight streaming.
        # BF16 fallback: False avoids historical Gemma4 "meta tensor" quirks.
        lc_raw = os.environ.get("CIVICLENS_LOW_CPU_MEM_USAGE")
        if qc is not None:
            lc = (lc_raw is None or lc_raw.strip().lower() not in ("0", "false", "no"))
        else:
            lc = lc_raw is not None and lc_raw.strip().lower() in ("1", "true", "yes")

        load_kw: dict[str, Any] = {
            **auth,
            "low_cpu_mem_usage": lc,
        }

        dm_extra = {}
        if torch.cuda.is_available():
            dm_extra = _device_map_kw()
            load_kw.update(dm_extra)

        if torch.cuda.is_available():
            if qc is not None:
                load_kw["quantization_config"] = qc
            else:
                load_kw["torch_dtype"] = torch.bfloat16
        else:
            load_kw["torch_dtype"] = torch.float32

        attn = os.environ.get("CIVICLENS_ATTN_IMPLEMENTATION")
        if attn is None:
            load_kw["attn_implementation"] = "eager"
        else:
            a = attn.strip().lower()
            if a and a not in ("default", "none"):
                load_kw["attn_implementation"] = a

        load_kw.update(_from_pretrained_kw())

        print(
            "[civiclens_hf] load plan: cuda=%s resolved_mode=%s qc_active=%s bnb=%s low_cpu_mem=%s attn=%s device_map=%s mmap=%s"
            % (
                torch.cuda.is_available(),
                quant_mode,
                qc is not None,
                _bnb_available(),
                lc,
                load_kw.get("attn_implementation"),
                dm_extra.get("device_map"),
                load_kw.get("mmap"),
            ),
            flush=True,
        )

        gc.collect()
        print("[civiclens_hf] loading model weights...", flush=True)
        try:
            _model = Gemma4ForConditionalGeneration.from_pretrained(MODEL_ID, **load_kw)
        except Exception as e:
            if qc is not None:
                print(
                    f"[civiclens_hf] Quantized load failed ({e!s}); retrying bf16 (may OOM on small GPUs).",
                    flush=True,
                )
                load_kw.pop("quantization_config", None)
                load_kw["torch_dtype"] = torch.bfloat16
                load_kw.update(_device_map_kw())
                load_kw["low_cpu_mem_usage"] = False
                _model = Gemma4ForConditionalGeneration.from_pretrained(MODEL_ID, **load_kw)
            else:
                raise
        _model.eval()

        gc.collect()
        print("[civiclens_hf] loading processor...", flush=True)
        _processor = AutoProcessor.from_pretrained(MODEL_ID, **auth)

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print(
            "[civiclens_hf] model ready [%s]"
            % ("quantized" if qc is not None else "bf16 full precision"),
            flush=True,
        )
    return _model, _processor


def run_inference_with_hf(images: list[Image.Image], prompt: str) -> str:
    """Run inference using Hugging Face Transformers (Gemma 4 multimodal)."""
    model, processor = get_model()

    # Required message shape for Gemma 4 (see HF model card + apply_chat_template docs).
    content: list[dict[str, Any]] = []
    for img in images:
        content.append({"type": "image", "image": img.convert("RGB")})
    content.append({"type": "text", "text": prompt})

    messages = [{"role": "user", "content": content}]

    inputs = processor.apply_chat_template(
        messages,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
        add_generation_prompt=True,
    )

    # Match weights' device (reliable for accelerate / device_map; model.device can be wrong for sharded models).
    main_dev = next(model.parameters()).device
    if main_dev.type == "meta":
        raise RuntimeError(
            "Model weights are still on the meta device after load. "
            "Try unsetting CPU offload or use a single-GPU device_map."
        )

    if hasattr(inputs, "to"):
        inputs = inputs.to(main_dev)
    else:
        def _tensor_to_dev(batch: dict) -> dict:
            out = {}
            for key, val in batch.items():
                if hasattr(val, "to"):
                    out[key] = val.to(main_dev)
                else:
                    out[key] = val
            return out

        inputs = _tensor_to_dev(inputs)

    input_ids = inputs.get("input_ids")
    if input_ids is None:
        raise RuntimeError("apply_chat_template did not return input_ids")

    input_len = int(input_ids.shape[-1])

    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens(),
            do_sample=False,
        )

    tokenizer = getattr(processor, "tokenizer", None)

    def _decode_ids(ids_tensor: torch.Tensor, *, skip_special_tokens: bool) -> str:
        if hasattr(processor, "decode"):
            return processor.decode(ids_tensor, skip_special_tokens=skip_special_tokens)
        if tokenizer is not None:
            return tokenizer.decode(ids_tensor, skip_special_tokens=skip_special_tokens)
        raise RuntimeError("Processor has no decode/tokenizer.decode")

    # New tokens only — never decode the full seq as "response" or we echo the prompt / multimodal noise.
    seq = outputs[0].cpu()
    out_len = int(seq.shape[-1])
    gen_ids = seq[input_len:out_len]

    response = ""
    if out_len > input_len:
        response = _decode_ids(gen_ids, skip_special_tokens=True).strip()

    # If everything was stripped as "special", try again without skipping tokens (then trim empties manually).
    if not response and out_len > input_len:
        response = _decode_ids(gen_ids, skip_special_tokens=False).strip()

    print(
        "[civiclens_hf] decoded_chars=%s input_len=%s output_len=%s gen_len=%s"
        % (len(response), input_len, out_len, max(0, out_len - input_len)),
        flush=True,
    )

    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    return response


def run_track_a(
    notice_file: Path | str | None,
    doc1: Path | str | None,
    doc2: Path | str | None = None,
    doc3: Path | str | None = None,
) -> dict[str, Any]:
    """Run Track A (SNAP Proof-Pack) inference."""
    notice_file, doc1, doc2, doc3 = coerce_track_a_files(notice_file, doc1, doc2, doc3)

    files = []
    if notice_file:
        files.append(("Government Notice", notice_file))
    if doc1:
        files.append(("Document 1", doc1))
    if doc2:
        files.append(("Document 2", doc2))
    if doc3:
        files.append(("Document 3", doc3))

    if not files:
        return {"error": "No documents provided", "raw_response": "", "success": False}

    cap = max_input_images()
    if len(files) > cap:
        print(
            f"[civiclens_hf] using first {cap} of {len(files)} uploads (CIVICLENS_MAX_INPUT_IMAGES)",
            flush=True,
        )
        files = files[:cap]

    # Preprocess all images
    images = []
    blur_warnings = []
    metadata = []

    for label, file_path in files:
        if file_path is None:
            continue
        jpeg_bytes, meta = preprocess_image(file_path)
        img = Image.open(io.BytesIO(jpeg_bytes))
        images.append(img)
        metadata.append({"label": label, **meta})

        if meta["is_blurry"]:
            blur_warnings.append(f"{label}: {meta['blur_guidance']}")

    # Build prompt
    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_a_prompt(doc_labels)

    # Run inference
    try:
        raw_response = run_inference_with_hf(images, prompt)
    except Exception as e:
        return {
            "error": f"Inference failed: {str(e)}",
            "raw_response": "",
            "success": False,
            "blur_warnings": blur_warnings,
            "metadata": metadata,
        }

    # Parse response
    parsed = parse_json_response(raw_response)

    ret: dict[str, Any] = {
        "parsed": parsed,
        "raw_response": raw_response,
        "blur_warnings": blur_warnings,
        "metadata": metadata,
        "success": parsed is not None,
    }
    if parsed is None:
        ret["error"] = (
            "The model responded, but the reply could not be parsed as JSON. "
            "Expand “Raw JSON Output” below to inspect the reply."
        )
    return ret


def run_track_b(
    doc1: Path | str | None,
    doc2: Path | str | None = None,
    doc3: Path | str | None = None,
    doc4: Path | str | None = None,
    doc5: Path | str | None = None,
) -> dict[str, Any]:
    """Run Track B (BPS Packet Checker) inference."""
    doc1, doc2, doc3, doc4, doc5 = coerce_track_b_files(doc1, doc2, doc3, doc4, doc5)

    files = []
    docs = [doc1, doc2, doc3, doc4, doc5]
    for i, doc in enumerate(docs, 1):
        if doc:
            files.append((f"Document {i}", doc))

    if not files:
        return {"error": "No documents provided", "raw_response": "", "success": False}

    cap = max_input_images()
    if len(files) > cap:
        print(
            f"[civiclens_hf] using first {cap} of {len(files)} uploads (CIVICLENS_MAX_INPUT_IMAGES)",
            flush=True,
        )
        files = files[:cap]

    # Preprocess all images
    images = []
    blur_warnings = []
    metadata = []

    for label, file_path in files:
        jpeg_bytes, meta = preprocess_image(file_path)
        img = Image.open(io.BytesIO(jpeg_bytes))
        images.append(img)
        metadata.append({"label": label, **meta})

        if meta["is_blurry"]:
            blur_warnings.append(f"{label}: {meta['blur_guidance']}")

    # Build prompt
    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_b_prompt(doc_labels)

    # Run inference
    try:
        raw_response = run_inference_with_hf(images, prompt)
    except Exception as e:
        return {
            "error": f"Inference failed: {str(e)}",
            "raw_response": "",
            "success": False,
            "blur_warnings": blur_warnings,
            "metadata": metadata,
        }

    # Parse response
    parsed = parse_json_response(raw_response)

    ret: dict[str, Any] = {
        "parsed": parsed,
        "raw_response": raw_response,
        "blur_warnings": blur_warnings,
        "metadata": metadata,
        "success": parsed is not None,
    }
    if parsed is None:
        ret["error"] = (
            "The model responded, but the reply could not be parsed as JSON. "
            "Expand “Raw JSON Output” below to inspect the reply."
        )
    return ret
