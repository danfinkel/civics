"""
Deploy script for Hugging Face Spaces.

This script creates or updates a Hugging Face Space for the CivicLens web demo.
Requires HF_TOKEN environment variable to be set.
"""

import os
import argparse
import shutil
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from huggingface_hub import HfApi, create_repo, upload_folder
from huggingface_hub.errors import HfHubHTTPError


def load_local_env(env_path: Path) -> None:
    """Load KEY=VALUE pairs from a local .env file into os.environ."""
    if not env_path.exists():
        return

    for raw_line in env_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deploy CivicLens web demo to Hugging Face Spaces.")
    parser.add_argument(
        "--force-rebuild",
        action="store_true",
        help=(
            "Force a full Space rebuild by uploading a cache-busted Dockerfile and "
            "requesting a Hugging Face factory reboot after upload."
        ),
    )
    return parser.parse_args()


def stage_space_files(
    source_dir: Path,
    space_files: list[str],
    *,
    force_rebuild: bool,
) -> tempfile.TemporaryDirectory[str]:
    """Copy deploy artifacts to a temp folder; optionally inject a Docker cache buster."""
    tmp = tempfile.TemporaryDirectory(prefix="civiclens-space-")
    staging_dir = Path(tmp.name)

    for name in space_files:
        source = source_dir / name
        destination = staging_dir / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    if force_rebuild:
        build_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        marker = staging_dir / ".civiclens_build_id"
        marker.write_text(f"{build_id}\n", encoding="utf-8")

        dockerfile = staging_dir / "Dockerfile"
        original = dockerfile.read_text(encoding="utf-8")
        cache_bust = (
            f"ARG CIVICLENS_FORCE_REBUILD={build_id}\n"
            "ENV CIVICLENS_FORCE_REBUILD=$CIVICLENS_FORCE_REBUILD\n"
            "COPY .civiclens_build_id .civiclens_build_id\n\n"
        )
        if "ARG CIVICLENS_FORCE_REBUILD=" in original:
            lines = original.splitlines(keepends=True)
            filtered: list[str] = []
            skip_next = 0
            for line in lines:
                if skip_next:
                    skip_next -= 1
                    continue
                if line.startswith("ARG CIVICLENS_FORCE_REBUILD="):
                    skip_next = 2  # matching ENV + COPY lines from prior generated Dockerfile
                    continue
                filtered.append(line)
            original = "".join(filtered)
        dockerfile.write_text(original.replace("WORKDIR /app\n\n", f"WORKDIR /app\n\n{cache_bust}", 1), encoding="utf-8")

    return tmp


def deploy(*, force_rebuild: bool = False):
    """Deploy the web demo to Hugging Face Spaces."""
    load_local_env(Path(__file__).parent / ".env")
    token = os.environ.get("HF_TOKEN")
    if not token:
        raise RuntimeError(
            "Missing HF_TOKEN. Set it in web_demo/.env or your environment."
        )

    # Space configuration
    repo_id = "DanFinkel/civiclens"  # Change this to your username/space-name
    space_sdk = "docker"

    api = HfApi(token=token)

    # Check if space exists, create if not
    try:
        api.repo_info(repo_id=repo_id, repo_type="space")
        print(f"Space {repo_id} exists, updating...")
    except Exception:
        print(f"Creating space {repo_id}...")
        create_repo(
            repo_id=repo_id,
            repo_type="space",
            space_sdk=space_sdk,
            token=token,
            private=False,
        )
        print(f"Space created: https://huggingface.co/spaces/{repo_id}")

    # Upload only files the Space needs (avoids .venv, __pycache__, huge accidential trees).
    web_demo_dir = Path(__file__).parent
    space_files = [
        "app.py",
        "api.py",
        "blur_detector.py",
        "inference.py",
        "inference_common.py",
        "inference_hf.py",
        "inference_hf_api.py",
        "inference_backend.py",
        "label_formatting.py",
        "prompts.py",
        # Branding (referenced by app.py for hero icon data-URI; must exist on disk when deploy runs)
        "branding/app_icon.png",
        # Demo sample JPGs (Dockerfile COPY sample_docs ./sample_docs — must be in staged upload)
        "sample_docs/D01-clean.jpg",
        "sample_docs/D03-clean.jpg",
        "Dockerfile",
        "README.md",
        "requirements.txt",
        "requirements_hf.txt",
        "requirements_hf_api.txt",
        "upload_utils.py",
    ]
    upload_patterns = list(space_files)
    if force_rebuild:
        upload_patterns.append(".civiclens_build_id")

    for name in space_files:
        p = web_demo_dir / name
        if not p.is_file():
            raise FileNotFoundError(f"Expected Space file missing: {p}")

    with stage_space_files(web_demo_dir, space_files, force_rebuild=force_rebuild) as staging:
        staging_dir = Path(staging)
        print(f"Uploading {len(upload_patterns)} file(s) from staged deploy folder...")
        if force_rebuild:
            print("Force rebuild enabled: Docker cache-buster injected and factory reboot will be requested.")

        # HF occasionally returns 5xx on commit; retry a few times with backoff.
        backoff_s = (5, 20, 60)
        for attempt in range(4):
            if attempt:
                w = backoff_s[attempt - 1]
                print(f"Waiting {w}s before retry (attempt {attempt + 1}/4)...")
                time.sleep(w)
            try:
                upload_folder(
                    repo_id=repo_id,
                    repo_type="space",
                    folder_path=staging_dir,
                    path_in_repo="",
                    token=token,
                    allow_patterns=upload_patterns,
                )
                break
            except HfHubHTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                retriable = code in (500, 502, 503, 504)
                if not retriable or attempt == 3:
                    raise
                print(f"Hub returned HTTP {code}; will retry. ({e!s})")

    if force_rebuild:
        print("Requesting Hugging Face Space factory rebuild...")
        api.restart_space(repo_id=repo_id, token=token, factory_reboot=True)

    print(f"\nDeployment complete!")
    print(f"Space URL: https://huggingface.co/spaces/{repo_id}")
    print(f"\nNote: The space will need Ollama and Gemma 4 E4B configured.")
    print("For a CPU-only demo, consider using the Transformers backend instead.")


if __name__ == "__main__":
    args = parse_args()
    deploy(force_rebuild=args.force_rebuild)
