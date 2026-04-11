#!/usr/bin/env python3
"""Minimal HTTP server for Gemma GGUF + /health (used by serve_model.sh)."""

from __future__ import annotations

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import unquote


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve a GGUF file over HTTP")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=8888, help="Port")
    parser.add_argument(
        "--file",
        required=True,
        help="Path to .gguf file",
    )
    args = parser.parse_args()

    path = os.path.abspath(args.file)
    if not os.path.isfile(path):
        print(f"ERROR: Model file not found: {path}", file=sys.stderr)
        sys.exit(1)

    name = os.path.basename(path)
    size = os.path.getsize(path)
    print(f"Serving {name} ({size / (1024**3):.2f} GB) on http://{args.host}:{args.port}/")
    print(f"  GET /health  -> JSON status")
    print(f"  GET /{name}  -> file download")
    print("")
    print("iPhone must use your Mac's LAN IP (not localhost), same Wi‑Fi.")
    print("")

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *log_args: object) -> None:
            print(f"[{self.log_date_time_string()}] {fmt % log_args}")

        def do_GET(self) -> None:  # noqa: N802
            raw = unquote(self.path.split("?", 1)[0])
            if raw in ("/health", "/health/"):
                body = json.dumps({"status": "ok"}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if raw in (f"/{name}", f"/{name}/"):
                try:
                    f = open(path, "rb")  # noqa: SIM115
                except OSError as e:
                    self.send_error(500, str(e))
                    return
                try:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Length", str(size))
                    self.send_header("Content-Disposition", f'attachment; filename="{name}"')
                    self.end_headers()
                    while True:
                        chunk = f.read(1024 * 1024)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                finally:
                    f.close()
                return

            self.send_error(404, "Not Found")

    server = HTTPServer((args.host, args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
