"""
Deploy script for Hugging Face Spaces.

This script creates or updates a Hugging Face Space for the CivicLens web demo.
Requires HF_TOKEN environment variable to be set.
"""

import os
import sys
from pathlib import Path

from huggingface_hub import HfApi, create_repo, upload_folder


def deploy():
    """Deploy the web demo to Hugging Face Spaces."""
    token = os.environ.get("HF_TOKEN")
    if not token:
        print("Error: HF_TOKEN environment variable not set")
        print("Get your token from https://huggingface.co/settings/tokens")
        sys.exit(1)

    # Space configuration
    repo_id = "danfinkel/civiclens-demo"  # Change this to your username/space-name
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
