#!/usr/bin/env python3
"""Windows CI integration test for the resumable N.O.M.A.D. PowerShell downloader."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: test-resumable-downloader.py downloader.ps1 reassembler.ps1")
    downloader = Path(sys.argv[1]).resolve()
    reassembler = Path(sys.argv[2]).resolve()

    with tempfile.TemporaryDirectory(prefix="nomad-download-test-") as td:
        root = Path(td)
        assets = root / "assets"
        destination = root / "downloaded"
        assets.mkdir()
        destination.mkdir()
        base = "NOMAD-Debian13.7-E93z.iso"

        original = bytes(((i * 31 + 17) % 256 for i in range(2_700_123)))
        parts = []
        for index, offset in enumerate(range(0, len(original), 900_000)):
            name = f"{base}.part{index:02d}"
            data = original[offset:offset + 900_000]
            (assets / name).write_bytes(data)
            parts.append(name)
        digest = hashlib.sha512(original).hexdigest()
        (assets / f"{base}.sha512").write_text(f"{digest}  {base}\n", encoding="ascii")
        shutil.copy2(reassembler, assets / "reassemble-nomad-iso.ps1")

        asset_names = parts + [f"{base}.sha512", "reassemble-nomad-iso.ps1"]
        interrupted = {"done": False}
        resumed = {"seen": False}
        server_ref = {}

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path == "/releases":
                    port = server_ref["server"].server_address[1]
                    items = []
                    for name in asset_names:
                        path = assets / name
                        items.append({
                            "name": name,
                            "size": path.stat().st_size,
                            "browser_download_url": f"http://127.0.0.1:{port}/assets/{name}",
                        })
                    body = json.dumps([{
                        "tag_name": "nomad-e93z-resume-test",
                        "draft": False,
                        "prerelease": True,
                        "created_at": "2026-11-03T00:00:00Z",
                        "assets": items,
                    }]).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return

                if not parsed.path.startswith("/assets/"):
                    self.send_error(404)
                    return
                name = unquote(parsed.path[len("/assets/"):])
                path = assets / name
                if not path.is_file() or path.parent != assets:
                    self.send_error(404)
                    return
                size = path.stat().st_size
                range_header = self.headers.get("Range")
                start = 0
                if range_header:
                    try:
                        start = int(range_header.strip().removeprefix("bytes=").split("-", 1)[0])
                    except Exception:
                        self.send_error(400)
                        return
                    if start >= size:
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{size}")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    resumed["seen"] = True
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{size-1}/{size}")
                else:
                    self.send_response(200)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(size - start))
                self.end_headers()

                # Simulate a broken connection halfway through the first large segment.
                if name == parts[0] and not range_header and not interrupted["done"]:
                    interrupted["done"] = True
                    with path.open("rb") as source:
                        self.wfile.write(source.read(max(1, size // 2)))
                        self.wfile.flush()
                    try:
                        self.connection.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    self.connection.close()
                    self.close_connection = True
                    return

                with path.open("rb") as source:
                    source.seek(start)
                    shutil.copyfileobj(source, self.wfile, length=64 * 1024)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server_ref["server"] = server
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            api = f"http://127.0.0.1:{server.server_address[1]}/releases"
            subprocess.run([
                "pwsh", "-NoLogo", "-NoProfile", "-File", str(downloader),
                "-Directory", str(destination), "-ApiUrl", api,
            ], check=True)
            output = destination / base
            if not output.is_file():
                raise RuntimeError("Downloader did not create the assembled ISO.")
            if hashlib.sha512(output.read_bytes()).hexdigest() != digest:
                raise RuntimeError("Assembled ISO checksum differs from the test source.")
            if not interrupted["done"]:
                raise RuntimeError("The simulated network interruption was not triggered.")
            if not resumed["seen"]:
                raise RuntimeError("Downloader did not resume with an HTTP Range request.")
            print("Resumable Windows downloader integration test passed.")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
