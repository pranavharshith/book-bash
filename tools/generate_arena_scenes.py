#!/usr/bin/env python
"""Generate the six arena scene files.

All six arenas share the same node skeleton (decor, spawn markers, camera rig,
round manager, spawn director, hazards) and differ only by id, uid, and a couple
of spawn-director flags. Generating them keeps the set from drifting apart as the
skeleton changes, which is exactly how the first pass ended up with per-arena
inconsistencies.

    python tools/generate_arena_scenes.py
"""

from __future__ import annotations

import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ARENAS = [
    # (arena_id, scene file stem, root node name, uid, chalkboard drop, power-ups)
    ("sky_library", "SkyLibrary", "SkyLibrary", "uid://skylibrary_bookbash", False, 2),
    ("classroom_chaos", "ClassroomChaos", "ClassroomChaos", "uid://classroomchaos_bookbash", True, 2),
    ("ancient_ruins", "AncientRuins", "AncientRuins", "uid://ancientruins_bookbash", False, 2),
    ("tech_tower", "TechTower", "TechTower", "uid://techtower_bookbash", False, 2),
    ("candy_island", "CandyIsland", "CandyIsland", "uid://candyisland_bookbash", False, 3),
    ("volcano_core", "VolcanoCore", "VolcanoCore", "uid://volcanocore_bookbash", False, 2),
]

# Spawn ellipse fitted inside the shared 24 x 20 play area, chosen to avoid the
# cover props each theme places.
SPAWN_RADIUS_X = 13.5
SPAWN_RADIUS_Z = 11.3
SPAWN_COUNT = 8
SPAWN_HEIGHT = 0.7

TEMPLATE = """[gd_scene load_steps=9 format=3 uid="{uid}"]

[ext_resource type="Script" path="res://scripts/game/game_manager.gd" id="1"]
[ext_resource type="Script" path="res://scripts/game/themed_arena_decor.gd" id="2"]
[ext_resource type="Script" path="res://scripts/game/round_manager.gd" id="3"]
[ext_resource type="Script" path="res://scripts/game/spawn_director.gd" id="4"]
[ext_resource type="PackedScene" path="res://scenes/props/BookPickup.tscn" id="5"]
[ext_resource type="Script" path="res://scripts/game/arena_hazards.gd" id="6"]
[ext_resource type="PackedScene" path="res://scenes/props/PowerUpPickup.tscn" id="7"]
[ext_resource type="Script" path="res://scripts/game/match_camera.gd" id="8"]

[node name="{root}" type="Node3D"]
script = ExtResource("1")

[node name="ArenaDecor" type="Node3D" parent="."]
script = ExtResource("2")
arena_id = "{arena_id}"

[node name="SpawnPoints" type="Node3D" parent="."]
{spawns}
[node name="Fighters" type="Node3D" parent="."]

[node name="CameraRig" type="Node3D" parent="."]
script = ExtResource("8")

[node name="Camera3D" type="Camera3D" parent="CameraRig"]
fov = 50.0
keep_aspect = 1
near = 0.06
far = 220.0

[node name="RoundManager" type="Node" parent="."]
script = ExtResource("3")

[node name="SpawnDirector" type="Node" parent="."]
script = ExtResource("4")
book_pickup_scene = ExtResource("5")
power_up_scene = ExtResource("7")
book_count = 12
power_up_count = {power_ups}
chalkboard_drop = {chalkboard}

[node name="ArenaHazards" type="Node3D" parent="."]
script = ExtResource("6")
arena_id = "{arena_id}"
"""


def spawn_block() -> str:
    lines = []
    for i in range(SPAWN_COUNT):
        angle = math.tau * i / SPAWN_COUNT
        x = math.sin(angle) * SPAWN_RADIUS_X
        z = math.cos(angle) * SPAWN_RADIUS_Z
        lines.append('[node name="Spawn%d" type="Marker3D" parent="SpawnPoints"]' % i)
        lines.append("position = Vector3(%.3f, %.2f, %.3f)" % (x, SPAWN_HEIGHT, z))
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    out_dir = os.path.join(ROOT, "scenes", "arenas")
    os.makedirs(out_dir, exist_ok=True)
    spawns = spawn_block()
    for arena_id, stem, root, uid, chalkboard, power_ups in ARENAS:
        text = TEMPLATE.format(
            uid=uid,
            root=root,
            arena_id=arena_id,
            spawns=spawns,
            chalkboard="true" if chalkboard else "false",
            power_ups=power_ups,
        )
        path = os.path.join(out_dir, stem + ".tscn")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
