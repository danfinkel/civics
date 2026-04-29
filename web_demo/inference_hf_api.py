"""
Multimodal inference via Hugging Face Inference Providers (hosted API).

No local model weights on the Space (**CPU OK**); usage is billed to your HF account
(**HF_TOKEN** with Inference API / provider access).

Routing gotchas:
- **`google/gemma-4-*-it`**: the Hub **`/v1/chat/completions`** route often rejects them (“not a chat model”).
  Use **`CIVICLENS_INFERENCE_BACKEND=hf`** + GPU for Gemma locally.
- Some doc examples (e.g. **Llama 3.2 Vision**) have **empty Inference Provider mappings** on the Hub, so
  the router returns “**not supported by any provider you have enabled**.”
  Defaults use **`zai-org/GLM-4.5V`** with **`novita`**, which has live mappings.

Override **`CIVICLENS_HF_INFERENCE_MODEL_ID`** / **`CIVICLENS_HF_INFERENCE_PROVIDER`**; enable providers at
https://huggingface.co/settings/inference-providers and check each model’s Inference Providers widget.
"""

from __future__ import annotations

import base64
import io
import json
import os
from pathlib import Path
from typing import Any

from huggingface_hub import InferenceClient
from PIL import Image

from inference_common import (
    JPEG_QUALITY,
    max_input_images,
    max_new_tokens,
    parse_json_response,
    preprocess_image,
)
from prompts import build_track_a_prompt, build_track_b_prompt
from upload_utils import coerce_track_a_files, coerce_track_b_files


def _hub_token() -> str | None:
    return (
        os.environ.get("HF_TOKEN")
        or os.environ.get("HUGGING_FACE_HUB_TOKEN")
        or os.environ.get("HUGGINGFACE_HUB_TOKEN")
    )


# GLM-4.5V has live provider mappings (e.g. novita, zai-org). Many other VLMs have no mapping → router errors.
_DEFAULT_CHAT_VLM = "zai-org/GLM-4.5V"
_DEFAULT_INFERENCE_PROVIDER = "novita"


def _inference_model_id() -> str:
    return os.environ.get("CIVICLENS_HF_INFERENCE_MODEL_ID", _DEFAULT_CHAT_VLM)


def _inference_provider() -> str | None:
    """Explicit provider; None = Hub auto-router (needs enabled providers in account settings)."""
    raw = os.environ.get("CIVICLENS_HF_INFERENCE_PROVIDER")
    if raw is None:
        return _DEFAULT_INFERENCE_PROVIDER
    s = raw.strip()
    if not s or s.lower() in ("auto", "default", "router"):
        return None
    return s


def _inference_client() -> InferenceClient:
    token = _hub_token()
    if not token:
        raise RuntimeError(
            "HF_TOKEN (or HUGGING_FACE_HUB_TOKEN) is required for hosted Hub inference — "
            "set it as a Space secret."
        )
    mid = _inference_model_id()
    kw: dict[str, Any] = {"model": mid, "token": token}
    pv = _inference_provider()
    if pv is not None:
        kw["provider"] = pv
    return InferenceClient(**kw)


def _text_from_chat_content_part(content: Any) -> str:
    """Normalize string vs OpenAI multimodal content list to plain text."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        chunks: list[str] = []
        for part in content:
            if isinstance(part, dict):
                # OpenAI-style {type,text} or providers that only set "text"/"content"
                if part.get("type") == "text":
                    chunks.append((part.get("text") or "").strip())
                elif "text" in part and part.get("text"):
                    chunks.append(str(part["text"]).strip())
                elif "content" in part and part.get("content"):
                    chunks.append(str(part["content"]).strip())
            elif isinstance(part, str):
                chunks.append(part.strip())
        return "\n".join(c for c in chunks if c)
    if isinstance(content, dict):
        t = content.get("text") or content.get("content")
        if t:
            return str(t).strip()
    return str(content).strip()


def _arguments_to_text(args: Any) -> str | None:
    if args is None:
        return None
    if isinstance(args, str):
        s = args.strip()
        return s if s else None
    if isinstance(args, (dict, list)):
        return json.dumps(args, ensure_ascii=False)
    s = str(args).strip()
    return s if s else None


def _tool_calls_to_text(tool_calls: Any) -> str:
    if not tool_calls:
        return ""
    parts: list[str] = []
    for tc in tool_calls:
        name: str | None = None
        args: Any = None
        if isinstance(tc, dict):
            fn = tc.get("function")
            if isinstance(fn, dict):
                args = fn.get("arguments")
                if args is None:
                    args = fn.get("args")
                name = fn.get("name")
            if args is None:
                args = tc.get("arguments") or tc.get("args")
            if name is None:
                name = tc.get("name")
        else:
            fn = getattr(tc, "function", None)
            if fn is not None:
                args = getattr(fn, "arguments", None)
                if args is None:
                    args = getattr(fn, "args", None)
                name = getattr(fn, "name", None)
        arg_text = _arguments_to_text(args)
        if arg_text:
            label = f"{name}: " if name else ""
            parts.append(f"{label}{arg_text}".strip())
        elif isinstance(tc, dict):
            # GLM / some routers return tool-like blobs without OpenAI-shaped function.arguments
            slim = {k: v for k, v in tc.items() if k not in ("id", "index")}
            if slim:
                try:
                    parts.append(json.dumps(slim, ensure_ascii=False))
                except (TypeError, ValueError):
                    parts.append(repr(tc))
    return "\n\n".join(parts).strip()


def _message_dict_view(msg: Any) -> dict[str, Any]:
    """Hub message can be ChatCompletionOutputMessage (dict subclass) or a plain dict."""
    if msg is None:
        return {}
    out: dict[str, Any] = {}
    if hasattr(msg, "keys"):
        try:
            for k in msg.keys():  # type: ignore[attr-defined]
                try:
                    out[str(k)] = msg[k]  # type: ignore[index]
                except Exception:
                    pass
            if out:
                return out
        except (TypeError, AttributeError):
            pass
    if isinstance(msg, dict):
        return dict(msg)
    for k, v in getattr(msg, "__dict__", {}).items():
        if not k.startswith("_"):
            out[k] = v
    return out


def _assistant_text_from_hub_message(msg: Any) -> str:
    """
    Collect text from content, reasoning, and common provider-specific fields.
    Some routers return multimodal assistant `content` as a list; others use `thinking` only.
    """
    if msg is None:
        return ""

    md = _message_dict_view(msg)
    # Preferred order — do not duplicate if same ref
    ordered_keys = (
        "content",
        "reasoning",
        "thinking",
        "thought",
        "analysis",
        "reflection",
        "refusal",
        "answer",
        "text",
        "output",
    )
    pieces: list[str] = []
    seen_txt: set[str] = set()

    def add_piece(s: str) -> None:
        s = s.strip()
        if not s or s in seen_txt:
            return
        seen_txt.add(s)
        pieces.append(s)

    for key in ordered_keys:
        raw_v = md.get(key)
        if raw_v is None:
            raw_v = getattr(msg, key, None)
        if raw_v is None:
            continue
        if isinstance(raw_v, (str, int, float)):
            add_piece(str(raw_v))
        else:
            t = _text_from_chat_content_part(raw_v)
            if t:
                add_piece(t)

    tool_text = _tool_calls_to_text(md.get("tool_calls"))
    if not tool_text and not isinstance(msg, dict):
        tool_text = _tool_calls_to_text(getattr(msg, "tool_calls", None))

    if tool_text:
        add_piece(tool_text)

    return "\n\n".join(pieces).strip()


def _assistant_text_from_chat_completion_choice(choice: Any) -> str:
    """First try message; then legacy choice.text (some gateways)."""
    msg = choice.get("message") if isinstance(choice, dict) else getattr(choice, "message", None)
    text = _assistant_text_from_hub_message(msg)
    if text:
        return text
    legacy = None
    if isinstance(choice, dict):
        legacy = choice.get("text")
    else:
        legacy = getattr(choice, "text", None)
    if legacy:
        return str(legacy).strip()
    return ""


def _log_empty_choice_debug(choice: Any, usage: Any) -> None:
    try:
        msg = choice.get("message") if isinstance(choice, dict) else getattr(choice, "message", None)
        md = _message_dict_view(msg)
        keys = sorted(md.keys())
        ct = md.get("content")
        ct_desc = type(ct).__name__
        ct_preview = repr(ct)[:220]
        u = ""
        if usage is not None:
            if isinstance(usage, dict):
                u = f" usage={usage!r}"
            else:
                u = (
                    " usage="
                    f"completion={getattr(usage, 'completion_tokens', '?')}"
                    f" prompt={getattr(usage, 'prompt_tokens', '?')}"
                )
        rn = md.get("reasoning")
        reason_preview = repr(rn)[:220] if rn is not None else "None"
        tc_raw = md.get("tool_calls")
        tc_prev = repr(tc_raw)[:400] if tc_raw is not None else "None"
        print(
            f"[civiclens_hf_api] empty assistant text: message_keys={keys} "
            f"content_type={ct_desc} content_preview={ct_preview!r} "
            f"reasoning_preview={reason_preview!r} tool_calls_preview={tc_prev!r}{u}",
            flush=True,
        )
    except Exception as e:
        print(f"[civiclens_hf_api] empty assistant text (debug log failed): {e}", flush=True)


def run_inference_with_hub_api(images: list[Image.Image], prompt: str) -> str:
    """OpenAI-style vision + text chat completion on HF Inference."""
    client = _inference_client()
    mid = _inference_model_id()
    pv = _inference_provider()
    if "gemma" in mid.lower():
        print(
            "[civiclens_hf_api] NOTE: Gemma Hub IDs often fail chat_completion routing; "
            "use backend `hf` + GPU for Gemma, or pick a model with Inference Providers for hf_api.",
            flush=True,
        )
    print(
        "[civiclens_hf_api] chat_completion model=%s provider=%s images=%s"
        % (mid, pv or "(Hub auto-router)", len(images)),
        flush=True,
    )

    content: list[dict[str, Any]] = []
    for img in images:
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="JPEG", quality=JPEG_QUALITY)
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
            }
        )
    content.append({"type": "text", "text": prompt})

    try:
        out = client.chat_completion(
            messages=[{"role": "user", "content": content}],
            max_tokens=max_new_tokens(hub_api=True),
            temperature=0.0,
        )
    except Exception as e:
        merged = (
            str(e).lower()
            + " "
            + (getattr(getattr(e, "response", None), "text", "") or "").lower()
        )
        if "not a chat model" in merged:
            raise RuntimeError(
                "Hugging Face Inference rejected this model for chat completions (often "
                "true for Gemma multimodal on the `/v1/chat/completions` route).\n"
                f"Try default model {_DEFAULT_CHAT_VLM!r} + provider {_DEFAULT_INFERENCE_PROVIDER!r}, "
                "or run Gemma locally: CIVICLENS_INFERENCE_BACKEND=hf + GPU Space.\n"
                f"\nUpstream: {e}"
            ) from e
        if "not supported by any provider" in merged or (
            "model_not_supported" in merged and "not a chat model" not in merged
        ):
            raise RuntimeError(
                "No Inference Provider on your account can serve this model+route (or the model "
                "has no Hub provider mapping — common for some Meta Llama vision IDs).\n"
                "Fixes: (1) https://huggingface.co/settings/inference-providers — enable at least "
                "one provider (e.g. Novita, Z.ai) and accept any license gates on the model card; "
                f"(2) use defaults CIVICLENS_HF_INFERENCE_MODEL_ID={_DEFAULT_CHAT_VLM!r} and "
                f"CIVICLENS_HF_INFERENCE_PROVIDER={_DEFAULT_INFERENCE_PROVIDER!r}; "
                "(3) try CIVICLENS_HF_INFERENCE_PROVIDER=zai-org for GLM; "
                "(4) self-host Gemma with CIVICLENS_INFERENCE_BACKEND=hf.\n"
                f"\nUpstream: {e}"
            ) from e
        raise

    if not out.choices:
        raise RuntimeError("Hub inference returned no choices.")

    usage = getattr(out, "usage", None)
    raw = ""
    for choice in out.choices:
        raw = _assistant_text_from_chat_completion_choice(choice)
        if raw:
            break

    if not raw:
        _log_empty_choice_debug(out.choices[0], usage)
        ctok = getattr(usage, "completion_tokens", None) if usage is not None else None
        ptok = getattr(usage, "prompt_tokens", None) if usage is not None else None
        ch0 = out.choices[0]
        if isinstance(ch0, dict):
            finish = ch0.get("finish_reason")
        else:
            finish = getattr(ch0, "finish_reason", None)
        hint = ""
        if ctok == 0:
            hint = (
                f" Completion returned 0 tokens (prompt_tokens={ptok}); try raising "
                f"CIVICLENS_MAX_NEW_TOKENS (currently {max_new_tokens(hub_api=True)} for Hub API), "
                "reducing image count/size, "
                "or switching model/provider."
            )
        extra = ""
        if finish:
            extra = f" finish_reason={finish!r}"
        raise RuntimeError(
            "Hub inference returned empty assistant message (no usable text in known fields)."
            + extra
            + hint
        )
    print(f"[civiclens_hf_api] assistant reply length={len(raw)}", flush=True)
    return raw


def run_track_a(
    notice_file: Path | str | None,
    doc1: Path | str | None,
    doc2: Path | str | None = None,
    doc3: Path | str | None = None,
) -> dict[str, Any]:
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
            f"[civiclens_hf_api] using first {cap} of {len(files)} uploads (CIVICLENS_MAX_INPUT_IMAGES)",
            flush=True,
        )
        files = files[:cap]

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

    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_a_prompt(doc_labels)

    try:
        raw_response = run_inference_with_hub_api(images, prompt)
    except Exception as e:
        return {
            "error": f"Inference failed: {str(e)}",
            "raw_response": "",
            "success": False,
            "blur_warnings": blur_warnings,
            "metadata": metadata,
        }

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
            f"[civiclens_hf_api] using first {cap} of {len(files)} uploads (CIVICLENS_MAX_INPUT_IMAGES)",
            flush=True,
        )
        files = files[:cap]

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

    doc_labels = [m["label"] for m in metadata]
    prompt = build_track_b_prompt(doc_labels)

    try:
        raw_response = run_inference_with_hub_api(images, prompt)
    except Exception as e:
        return {
            "error": f"Inference failed: {str(e)}",
            "raw_response": "",
            "success": False,
            "blur_warnings": blur_warnings,
            "metadata": metadata,
        }

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
