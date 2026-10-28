#!/usr/bin/env python3
"""Serve a zero-export Godot web preview of this project's source files.

Intended for a trusted development preview, not production deployment.
"""
import argparse
import hashlib
import io
import mimetypes
import re
import struct
from pathlib import Path
import tarfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen

PROJECT = Path(__file__).resolve().parent.parent
PREVIEW = PROJECT / "preview"
CACHE = PROJECT / ".godot" / "preview-template"
REVISION = "36ea472a53b68b4f644c8466e2ee8a668d13e5c7"
ARCHIVE = f"https://codeload.github.com/ChanceFlow/godot-web-templates/tar.gz/{REVISION}"
HASHES = {
    "godot.js": "ffc3898b59fba6f5af0c02f76e5ee526cc061e65c7d2d6f4f98186876cea15c4",
    "godot.wasm": "11ea19645368f8e73cf337b59cfd7ceeb4ebb51f7a3bbf77d1a5c3ddfedbc522",
}
# This preview intentionally supports the source-only prototype, not imported assets.
EXTENSIONS = {".gd", ".tscn", ".tres", ".gdshader"}


def prepare_template():
    CACHE.mkdir(parents=True, exist_ok=True)
    def valid(name):
        path = CACHE / name
        return path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == HASHES[name]
    if all(valid(name) for name in HASHES):
        return
    print("Downloading Godot 4.7.2 single-threaded web debug template…", flush=True)
    with urlopen(ARCHIVE, timeout=120) as response:
        data = response.read()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for name, digest in HASHES.items():
            suffix = f"/4.7.2-stable/nothreads_debug/{name}"
            members = [m for m in archive.getmembers() if m.name.endswith(suffix) and m.isfile()]
            if len(members) != 1:
                raise RuntimeError(f"Missing or ambiguous template file: {name}")
            content = archive.extractfile(members[0]).read()
            if hashlib.sha256(content).hexdigest() != digest:
                raise RuntimeError(f"Template checksum mismatch: {name}")
            (CACHE / name).write_bytes(content)


def files():
    paths = [PROJECT / "project.godot"]
    for folder in ("scripts", "scenes"):
        paths.extend(p for p in (PROJECT / folder).rglob("*") if p.is_file() and p.suffix in EXTENSIONS)
    return sorted(p.relative_to(PROJECT).as_posix() for p in paths)


def make_pack():
    """Build an unencrypted PCK v2 from source files for the debug template.

    This is a development pack, not Godot's import/export pipeline. Imported assets
    and platform-specific resource conversion require a normal editor export.
    """
    entries = [(path, (PROJECT / path).read_bytes()) for path in files()]
    # This prototype has no class_name scripts. A regular editor export generates
    # the full cache; do not silently serve incorrect data if that changes.
    if any(re.search(rb"(?m)^\s*class_name\s+", data) for path, data in entries if path.endswith(".gd")):
        raise RuntimeError("Global script classes require a normal Godot export")
    entries.append((".godot/global_script_class_cache.cfg", b"list=[]\n"))
    directory_size = sum(4 + ((len(path.encode("utf-8")) + 3) // 4 * 4) + 8 + 8 + 16 + 4 for path, _ in entries)
    offset = 4 * 6 + 8 + 16 * 4 + 4 + directory_size
    directory = bytearray()
    payload = bytearray()
    for path, data in entries:
        encoded = path.encode("utf-8")
        padded = encoded + bytes((-len(encoded)) % 4)
        directory.extend(struct.pack("<I", len(padded)))
        directory.extend(padded)
        directory.extend(struct.pack("<QQ", offset + len(payload), len(data)))
        directory.extend(hashlib.md5(data).digest())
        directory.extend(struct.pack("<I", 0))
        payload.extend(data)
    header = struct.pack("<6IQ", 0x43504447, 2, 4, 4, 1, 0, 0)
    return header + bytes(16 * 4) + struct.pack("<I", len(entries)) + directory + payload


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == "/game.pck":
            try:
                return self.respond(make_pack(), "application/octet-stream")
            except (OSError, RuntimeError) as error:
                self.send_error(500, str(error))
                return
        if path in ("/", "/index.html"):
            file = PREVIEW / "index.html"
        elif path in ("/godot.js", "/godot.wasm"):
            file = CACHE / path[1:]
        elif path in ("/godot.audio.worklet.js", "/godot.audio.position.worklet.js"):
            file = PREVIEW / path[1:]
        else:
            self.send_error(404)
            return
        if not file.is_file():
            self.send_error(404)
            return
        content_type = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        if file.suffix == ".wasm":
            content_type = "application/wasm"
        return self.respond(file.read_bytes(), content_type)

    def respond(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        # A refresh always loads the latest source and avoids stale preview builds.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    prepare_template()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Rotten Crown preview listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
