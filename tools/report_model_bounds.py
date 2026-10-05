#!/usr/bin/env python
"""Print the world-space bounding box of each model in a kit folder.

Arena layout code needs to know how big a `wall` or a `bookcaseOpen` actually is,
because the three kits Book Bash uses were authored at different scales. Reading
the accessor min/max out of the glTF is exact and far quicker than eyeballing it
in an editor.

    python tools/report_model_bounds.py assets/models/kits/dungeon
"""

from __future__ import annotations

import glob
import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67


def _load_document(path: str) -> dict:
    if path.lower().endswith(".gltf"):
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    with open(path, "rb") as handle:
        data = handle.read()
    magic = struct.unpack("<I", data[:4])[0]
    if magic != GLB_MAGIC:
        raise ValueError("not a glb: %s" % path)
    length = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + length].decode("utf-8"))


def _node_matrix(node: dict):
    if "matrix" in node:
        m = node["matrix"]
        return [
            [m[0], m[4], m[8], m[12]],
            [m[1], m[5], m[9], m[13]],
            [m[2], m[6], m[10], m[14]],
            [m[3], m[7], m[11], m[15]],
        ]
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    sx, sy, sz = node.get("scale", [1.0, 1.0, 1.0])
    rotation = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    scale = [sx, sy, sz]
    return [
        [rotation[r][0] * scale[0], rotation[r][1] * scale[1], rotation[r][2] * scale[2], [tx, ty, tz][r]]
        for r in range(3)
    ] + [[0.0, 0.0, 0.0, 1.0]]


def _multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def _transform(matrix, point):
    return [
        sum(matrix[r][c] * point[c] for c in range(3)) + matrix[r][3]
        for r in range(3)
    ]


def bounds(path: str):
    document = _load_document(path)
    meshes = document.get("meshes", [])
    accessors = document.get("accessors", [])
    minimum = [float("inf")] * 3
    maximum = [float("-inf")] * 3

    def walk(node_index: int, parent):
        node = document["nodes"][node_index]
        world = _multiply(parent, _node_matrix(node))
        mesh_index = node.get("mesh")
        if mesh_index is not None:
            for primitive in meshes[mesh_index].get("primitives", []):
                accessor_index = primitive.get("attributes", {}).get("POSITION")
                if accessor_index is None:
                    continue
                accessor = accessors[accessor_index]
                lo = accessor.get("min")
                hi = accessor.get("max")
                if not lo or not hi:
                    continue
                for cx in (lo[0], hi[0]):
                    for cy in (lo[1], hi[1]):
                        for cz in (lo[2], hi[2]):
                            world_point = _transform(world, [cx, cy, cz])
                            for axis in range(3):
                                minimum[axis] = min(minimum[axis], world_point[axis])
                                maximum[axis] = max(maximum[axis], world_point[axis])
        for child in node.get("children", []):
            walk(child, world)

    identity = [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]
    scene = document.get("scenes", [{}])[document.get("scene", 0)]
    for root in scene.get("nodes", []):
        walk(root, identity)
    if minimum[0] == float("inf"):
        return None
    return minimum, maximum


def main() -> None:
    targets = sys.argv[1:] or ["assets/models/kits/dungeon"]
    for target in targets:
        paths = []
        if os.path.isdir(target):
            for pattern in ("*.gltf", "*.glb"):
                paths.extend(sorted(glob.glob(os.path.join(target, pattern))))
        else:
            paths = [target]
        print("==", target)
        for path in paths:
            try:
                result = bounds(path)
            except Exception as error:  # noqa: BLE001 - diagnostics tool
                print("  %-44s ERROR %s" % (os.path.basename(path), error))
                continue
            if result is None:
                print("  %-44s (no geometry)" % os.path.basename(path))
                continue
            lo, hi = result
            size = [hi[i] - lo[i] for i in range(3)]
            print("  %-44s size=%6.2f x %6.2f x %6.2f   minY=%6.2f" % (
                os.path.basename(path), size[0], size[1], size[2], lo[1],
            ))


if __name__ == "__main__":
    main()
