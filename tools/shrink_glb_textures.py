#!/usr/bin/env python
"""Downscale the textures embedded in a .glb so a desktop-scanned asset can ship
on a phone.

The Sketchfab bookshelf that Book Bash uses as its hero library prop arrives with
4K PBR maps (18 MB of GLB plus 18 MB of loose PNGs). That is more texture memory
than the whole rest of the game. This rewrites the GLB in place with the same
geometry and a capped texture resolution, which keeps the asset (and its licence
trail) instead of discarding it.

    python tools/shrink_glb_textures.py assets/models/props/bookshelf.glb --max 512
"""

from __future__ import annotations

import argparse
import io
import json
import os
import struct

from PIL import Image

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def _read_glb(path: str):
    with open(path, "rb") as handle:
        data = handle.read()
    magic, version, _length = struct.unpack("<III", data[:12])
    if magic != GLB_MAGIC:
        raise SystemExit("%s is not a binary glTF" % path)
    offset = 12
    document = None
    binary = b""
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack("<II", data[offset:offset + 8])
        payload = data[offset + 8:offset + 8 + chunk_length]
        if chunk_type == CHUNK_JSON:
            document = json.loads(payload.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary = payload
        offset += 8 + chunk_length + (-chunk_length % 4)
    if document is None:
        raise SystemExit("%s has no JSON chunk" % path)
    return version, document, binary


def _write_glb(path: str, version: int, document: dict, binary: bytes) -> None:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    total = 12 + 8 + len(json_bytes) + (8 + len(binary) if binary else 0)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, version, total))
        handle.write(struct.pack("<II", len(json_bytes), CHUNK_JSON))
        handle.write(json_bytes)
        if binary:
            handle.write(struct.pack("<II", len(binary), CHUNK_BIN))
            handle.write(binary)


def shrink(path: str, max_size: int, quality: int) -> None:
    version, document, binary = _read_glb(path)
    views = document.get("bufferViews", [])
    images = document.get("images", [])
    if not images:
        print("  %s: no embedded images" % os.path.basename(path))
        return

    # Rebuild the binary chunk from scratch so shrunken images shorten the file
    # instead of leaving dead space behind.
    payloads = []
    for view in views:
        start = view.get("byteOffset", 0)
        payloads.append(bytearray(binary[start:start + view["byteLength"]]))

    for index, image in enumerate(images):
        view_index = image.get("bufferView")
        if view_index is None:
            continue
        source = Image.open(io.BytesIO(bytes(payloads[view_index])))
        original = source.size
        if max(original) > max_size:
            scale = max_size / float(max(original))
            source = source.resize(
                (max(1, int(original[0] * scale)), max(1, int(original[1] * scale))),
                Image.LANCZOS,
            )
        buffer = io.BytesIO()
        if source.mode in ("RGBA", "LA", "P"):
            source.convert("RGBA").save(buffer, format="PNG", optimize=True)
            image["mimeType"] = "image/png"
        else:
            source.convert("RGB").save(buffer, format="JPEG", quality=quality, optimize=True)
            image["mimeType"] = "image/jpeg"
        payloads[view_index] = bytearray(buffer.getvalue())
        print("  image %d: %sx%s -> %sx%s (%d KB)" % (
            index, original[0], original[1], source.size[0], source.size[1],
            len(payloads[view_index]) // 1024,
        ))

    rebuilt = bytearray()
    for view_index, view in enumerate(views):
        while len(rebuilt) % 4:
            rebuilt.append(0)
        view["byteOffset"] = len(rebuilt)
        view["byteLength"] = len(payloads[view_index])
        rebuilt += payloads[view_index]
    document["buffers"] = [{"byteLength": len(rebuilt)}]

    before = os.path.getsize(path)
    _write_glb(path, version, document, bytes(rebuilt))
    print("  %s: %.1f MB -> %.1f MB" % (
        os.path.basename(path), before / 1048576.0, os.path.getsize(path) / 1048576.0,
    ))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--max", type=int, default=512)
    parser.add_argument("--quality", type=int, default=82)
    args = parser.parse_args()
    for path in args.paths:
        print("==", path)
        shrink(path, args.max, args.quality)


if __name__ == "__main__":
    main()
