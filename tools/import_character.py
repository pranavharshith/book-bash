"""Convert one licensed FBX character (including actions) to a Godot-ready GLB.

Run from the repository root on Windows:
    & ".\\devtools\\Blender\\blender-5.2.1-windows-x64\\blender.exe" --background \
        --python ".\\tools\\import_character.py" -- "source.fbx" "assets\\models\\characters\\character.glb"

The source FBX must be an asset that the project is licensed to use. The script
removes camera/light helpers, preserves mesh/armature/action data, names the
armature predictably, and exports a self-contained GLB for Godot import.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def _arguments() -> argparse.Namespace:
    if "--" not in sys.argv:
        raise SystemExit("Pass source and destination paths after Blender's -- separator.")
    parser = argparse.ArgumentParser(description="Convert a licensed FBX character into a Godot-ready GLB.")
    parser.add_argument("source", type=Path, help="Input FBX file with the character and animation actions.")
    parser.add_argument("destination", type=Path, help="Output .glb path.")
    parser.add_argument(
        "--armature-name",
        default="CharacterRig",
        help="Stable name assigned to the first imported armature (default: CharacterRig).",
    )
    parser.add_argument(
        "--keep-cameras-lights",
        action="store_true",
        help="Keep imported camera and light helpers instead of removing them.",
    )
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def _reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.materials, bpy.data.meshes, bpy.data.armatures, bpy.data.cameras, bpy.data.lights):
        for datablock in list(collection):
            collection.remove(datablock)


def _import_fbx(source: Path) -> None:
    if source.suffix.lower() != ".fbx":
        raise ValueError("The source file must use the .fbx extension.")
    if not source.is_file():
        raise FileNotFoundError(source)
    bpy.ops.import_scene.fbx(
        filepath=str(source),
        use_anim=True,
        automatic_bone_orientation=True,
        ignore_leaf_bones=False,
    )


def _clean_import(keep_cameras_lights: bool, armature_name: str) -> list[bpy.types.Object]:
    for obj in list(bpy.context.scene.objects):
        if not keep_cameras_lights and obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError("No armature was imported; choose a rigged FBX character.")
    armatures[0].name = armature_name
    armatures[0].data.name = f"{armature_name}Data"
    exported = [obj for obj in bpy.context.scene.objects if obj.type in {"ARMATURE", "MESH"}]
    if not exported:
        raise RuntimeError("No mesh or armature objects remain after import.")
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in exported)
    bpy.context.view_layer.objects.active = armatures[0]
    return exported


def _export_glb(destination: Path) -> None:
    if destination.suffix.lower() != ".glb":
        raise ValueError("The destination file must use the .glb extension.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_yup=True,
        export_force_sampling=True,
        export_nla_strips=True,
        export_animation_mode="ACTIONS",
    )


def main() -> None:
    options = _arguments()
    source = options.source.expanduser().resolve()
    destination = options.destination.expanduser().resolve()
    _reset_scene()
    _import_fbx(source)
    _clean_import(options.keep_cameras_lights, options.armature_name)
    _export_glb(destination)
    print(f"Converted {source.name} to {destination}")


if __name__ == "__main__":
    main()
