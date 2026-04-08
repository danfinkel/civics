"""
Deploy script for Hugging Face Spaces.

This script creates or updates a Hugging Face Space for the CivicLens web demo.
Requires HF_TOKEN environment variable to be set.
"""

import os
from pathlib import Path

from huggingface_hub import HfApi, create_repo, upload_folder


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


def deploy():
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

    # Upload files
    web_demo_dir = Path(__file__).parent
    print(f"Uploading files from {web_demo_dir}...")

    upload_folder(
        repo_id=repo_id,
        repo_type="space",
        folder_path=web_demo_dir,
        path_in_repo="",
        token=token,
        ignore_patterns=["__pycache__", "*.pyc", ".git", "deploy.py"],
    )

    print(f"\nDeployment complete!")
    print(f"Space URL: https://huggingface.co/spaces/{repo_id}")
    print(f"\nNote: The space will need Ollama and Gemma 4 E4B configured.")
    print("For a CPU-only demo, consider using the Transformers backend instead.")


if __name__ == "__main__":
    deploy()
