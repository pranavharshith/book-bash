#!/usr/bin/env python
"""One-off: scale position-like Vector3 literals in themed_arena_decor.gd from
the 28x24 layout to a larger arena. Size arguments (the first Vector3 of
box()/add_box_body() calls, mesh sizes, extents) are left alone so props keep
their real dimensions; only where things stand moves outward.

    python tools/rescale_layout.py 18 16
"""
import re
import sys

OLD = (14.0, 12.0)
PATH = "scripts/game/themed_arena_decor.gd"
SKIP_LINE = ("mesh.size", "emission_box_extents", "visibility_aabb", "Vector3.ONE", "_landform(", "_cloud(", "Basis(")
SIZE_FIRST = (".box(", "add_box_body(")
NUM = r"-?\d+(?:\.\d+)?"
VEC = re.compile(r"Vector3\(\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*\)" % (NUM, NUM, NUM))


def main():
    sx = float(sys.argv[1]) / OLD[0]
    sz = float(sys.argv[2]) / OLD[1]
    out = []
    changed = 0
    for line in open(PATH, encoding="utf-8").read().split("\n"):
        if any(s in line for s in SKIP_LINE) or "HALF_" in line and "Vector3(" not in line:
            out.append(line)
            continue
        skip_first = any(s in line for s in SIZE_FIRST)
        index = [0]

        def repl(m):
            nonlocal changed
            index[0] += 1
            if skip_first and index[0] == 1:
                return m.group(0)
            x, y, z = (float(g) for g in m.groups())
            # Only positions in the play space: backdrop coordinates (far away)
            # already sit outside even the larger walls.
            if abs(x) > 14.5 or abs(z) > 12.5:
                return m.group(0)
            if abs(x) < 0.01 and abs(z) < 0.01:
                return m.group(0)
            changed += 1
            return "Vector3(%s, %s, %s)" % (fmt(x * sx), fmt(y), fmt(z * sz))

        out.append(VEC.sub(repl, line))
    open(PATH, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("scaled", changed, "positions")


def fmt(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    if "." not in s:
        s += ".0"
    return s


if __name__ == "__main__":
    main()
