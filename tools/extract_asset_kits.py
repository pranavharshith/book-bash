#!/usr/bin/env python
"""Extract the licensed asset archives staged in `SOME ASSESTS/` into `assets/`.

Everything Book Bash ships at runtime has to live under `assets/` so Godot can
import it. The archives themselves stay in `SOME ASSESTS/` (which is `.gdignore`d)
as the provenance record. This script is idempotent: re-running it reproduces the
same output tree, so the runtime asset set is always rebuildable from the
archives plus this file.

Run from the repo root:
    python tools/extract_asset_kits.py
"""

from __future__ import annotations

import io
import json
import os
import shutil
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGING = os.path.join(ROOT, "SOME ASSESTS")
ASSETS = os.path.join(ROOT, "assets")

# --------------------------------------------------------------------------- #
# Curated model subsets. Kept deliberately small: every extra mesh is download
# size and draw calls on a phone, and the arenas only need a themed kit each.
# --------------------------------------------------------------------------- #

KENNEY_FURNITURE = [
    # Library / study
    "bookcaseClosed", "bookcaseClosedDoors", "bookcaseClosedWide", "bookcaseOpen",
    "bookcaseOpenLow", "books", "desk", "deskCorner", "chairDesk", "chair",
    "chairCushion", "chairModernCushion", "chairRounded", "bench", "benchCushion",
    "table", "tableCloth", "tableRound", "tableCross", "tableCoffee", "sideTable",
    "stoolBar", "stoolBarSquare",
    # Soft furnishing / dressing
    "rugRound", "rugRectangle", "rugSquare", "rugRounded", "rugDoormat",
    "pillow", "pillowBlue", "pillowLong", "loungeSofa", "loungeChair",
    "lampRoundFloor", "lampSquareFloor", "lampRoundTable", "lampWall",
    "pottedPlant", "plantSmall1", "plantSmall2", "plantSmall3",
    "cardboardBoxClosed", "cardboardBoxOpen", "trashcan", "coatRack",
    # Tech Tower dressing
    "computerScreen", "computerKeyboard", "laptop", "speaker", "speakerSmall",
    "televisionModern", "radio", "cabinetTelevision", "cabinetTelevisionDoors",
    "kitchenFridge", "kitchenFridgeLarge",
    # Structure
    "wall", "wallHalf", "wallWindow", "wallCorner", "wallDoorway", "paneling",
    "floorFull", "floorHalf", "stairs", "stairsOpen", "doorway",
]

KENNEY_CASTLE = [
    "wall", "wall-half", "wall-corner", "wall-corner-half", "wall-pillar",
    "wall-narrow", "wall-narrow-corner", "wall-narrow-stairs", "wall-doorway",
    "wall-half-modular", "wall-stud", "wall-to-narrow", "wall-narrow-wood",
    "stairs-stone", "stairs-stone-square", "gate", "metal-gate", "door",
    "tower-base", "tower-square-base", "tower-square-mid", "tower-square-top",
    "tower-square-arch", "tower-hexagon-base", "tower-hexagon-mid",
    "tower-top", "tower-slant-roof",
    "rocks-large", "rocks-small", "tree-large", "tree-small", "tree-log",
    "tree-trunk", "flag", "flag-banner-long", "flag-pennant", "flag-wide",
    "bridge-straight", "bridge-straight-pillar", "ground", "ground-hills",
    "siege-catapult", "siege-ballista",
]

# KayKit shares one 17 KB atlas across every prop, so a generous subset is cheap.
KAYKIT_DUNGEON = [
    # Structure
    "wall", "wall_half", "wall_arched", "wall_archedwindow_open",
    "wall_archedwindow_gated", "wall_broken", "wall_cracked", "wall_corner",
    "wall_corner_small", "wall_doorway", "wall_doorway_sides", "wall_endcap",
    "wall_gated", "wall_pillar", "wall_scaffold", "wall_shelves", "wall_sloped",
    "wall_window_closed", "wall_window_open", "column", "pillar",
    "pillar_decorated", "barrier", "barrier_half", "barrier_column",
    "barrier_corner",
    # Floors
    "floor_tile_large", "floor_tile_small", "floor_tile_small_broken_A",
    "floor_tile_small_broken_B", "floor_tile_small_decorated",
    "floor_tile_large_rocks", "floor_tile_big_grate", "floor_tile_big_spikes",
    "floor_wood_large", "floor_wood_large_dark", "floor_wood_small",
    "floor_dirt_large", "floor_dirt_large_rocky", "floor_foundation_allsides",
    "stairs", "stairs_wide", "stairs_wood", "stairs_walled", "stairs_narrow",
    # Library / furniture
    "shelf_large", "shelf_small", "shelf_small_candles", "shelves",
    "wall_shelves", "table_long", "table_long_broken", "table_medium",
    "table_medium_broken", "table_small", "table_long_tablecloth", "chair",
    "stool", "bed_decorated", "bed_frame",
    # Props / dressing
    "barrel_large", "barrel_small", "barrel_small_stack", "box_large",
    "box_small", "box_stacked", "crates_stacked", "keg", "chest", "chest_gold",
    "coin", "coin_stack_large", "coin_stack_medium", "coin_stack_small",
    "candle", "candle_lit", "candle_triple", "candle_melted",
    "torch", "torch_lit", "torch_mounted", "rubble_half", "rubble_large",
    "bottle_A_green", "bottle_B_brown", "bottle_C_green", "plate", "plate_stack",
    "key", "keyring", "sword_shield", "trunk_large_A", "trunk_medium_B",
    "trunk_small_C",
    # Banners for arena identity
    "banner_blue", "banner_red", "banner_green", "banner_yellow",
    "banner_patternA_blue", "banner_patternB_red", "banner_triple_green",
    "banner_shield_yellow", "banner_thin_white",
]

# The Fantasy MegaKit is PBR-trim based, so only hero library dressing is worth
# the texture budget. Its shared trim maps get downscaled below.
FANTASY_PROPS = [
    "Book_5", "Book_7", "Book_Simplified_Single", "Book_Stack_1", "Book_Stack_2",
    "BookGroup_Medium_1", "BookGroup_Medium_2", "BookGroup_Small_1",
    "BookGroup_Small_2", "BookStand", "Bookcase_2", "Shelf_Simple", "Shelf_Arch",
    "Shelf_Small_Bottles", "Table_Large", "Chair_1", "Stool", "Bench",
    "Candle_1", "CandleStick", "CandleStick_Triple", "Chandelier", "Chest_Wood",
    "Barrel", "Crate_Wooden", "Torch_Metal", "Scroll_1", "Scroll_2", "Cauldron",
    "Coin_Pile", "Potion_1", "Potion_2", "Potion_4", "Vase_Rubble_Medium",
    "Lantern_Wall", "Banner_1_Cloth", "Rope_1", "Workbench", "Cabinet",
]

# Trim atlas budget. Base colour keeps enough detail to read on a phone; the
# normal/ORM maps only need to survive as low-frequency shading information.
FANTASY_TEXTURE_LIMITS = {
    "T_Trim_Cloth_BaseColor.png": 512,
    "T_Trim_Furniture_BaseColor.png": 512,
    "T_Trim_Metal_BaseColor.png": 512,
    "T_Trim_Props_BaseColor.png": 512,
    "T_Trim_Cloth_Normal.png": 256,
    "T_Trim_Furniture_Normal.png": 256,
    "T_Trim_Metal_Normal.png": 256,
    "T_Trim_Props_Normal.png": 256,
    "T_Trim_Cloth_ORM.png": 256,
    "T_Trim_Furniture_ORM.png": 256,
    "T_Trim_Metal_ORM.png": 256,
    "T_Trim_Props_ORM.png": 256,
    "T_Page_Noise.png": 256,
}

# Creative Characters accessories drive the cosmetic catalogue. They are skinned
# to the same rig as the player GLBs, so the runtime attaches them to bones.
COSMETICS = [
    "Hat_010", "Hat_049", "Hat_057", "Glasses_004", "Glasses_006",
    "Headphones_002", "Hairstyle_male_010", "Hairstyle_male_012",
    "Clown_nose_001", "Moustache_001", "Moustache_002", "Pacifier_001",
]

IMPACT_SOUNDS = [
    "impactBell_heavy_000", "impactBell_heavy_001", "impactBell_heavy_002",
    "impactPunch_heavy_000", "impactPunch_heavy_002", "impactPunch_medium_001",
    "impactPunch_medium_003", "impactWood_heavy_000", "impactWood_heavy_002",
    "impactWood_medium_001", "impactWood_medium_003", "impactWood_light_000",
    "impactWood_light_002", "impactPlank_medium_000", "impactPlank_medium_002",
    "impactSoft_heavy_001", "impactSoft_medium_000", "impactGeneric_light_000",
    "impactGeneric_light_002", "impactGlass_light_001", "impactMetal_heavy_001",
    "impactMetal_light_000", "impactMining_002", "impactTin_medium_000",
    "footstep_wood_000", "footstep_wood_001", "footstep_wood_002",
    "footstep_wood_003", "footstep_carpet_000", "footstep_carpet_002",
    "footstep_concrete_000", "footstep_concrete_002", "footstep_grass_001",
    "footstep_snow_001",
]

UI_SOUNDS = [
    "click1", "click2", "click3", "click5", "mouseclick1", "mouserelease1",
    "rollover1", "rollover2", "rollover4", "switch1", "switch2", "switch7",
    "switch11", "switch19", "switch26", "switch33",
]


def _write(target: str, data: bytes) -> bool:
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target) and open(target, "rb").read() == data:
        return False
    with open(target, "wb") as handle:
        handle.write(data)
    return True


def _archive(name: str) -> zipfile.ZipFile:
    return zipfile.ZipFile(os.path.join(STAGING, name))


def _copy_license(zf: zipfile.ZipFile, out_dir: str, source_note: str) -> None:
    text = ""
    for entry in zf.namelist():
        if os.path.basename(entry).lower() in ("license.txt", "license_standard.txt", "license.md"):
            text = zf.read(entry).decode("utf-8", "replace")
            break
    header = "Source archive: %s\n%s\n\n" % (source_note, "-" * 60)
    _write(os.path.join(out_dir, "LICENSE.txt"), (header + text).encode("utf-8"))


def extract_kenney_furniture() -> int:
    out = os.path.join(ASSETS, "models", "kits", "furniture")
    zf = _archive("kenney_furniture-kit.zip")
    count = 0
    for stem in KENNEY_FURNITURE:
        entry = "Models/GLTF format/%s.glb" % stem
        if entry not in zf.namelist():
            print("  ! missing", entry)
            continue
        count += _write(os.path.join(out, stem + ".glb"), zf.read(entry))
    _copy_license(zf, out, "kenney_furniture-kit.zip (Kenney Furniture Kit)")
    return count


def extract_kenney_castle() -> int:
    out = os.path.join(ASSETS, "models", "kits", "castle")
    zf = _archive("kenney_castle-kit.zip")
    count = 0
    for stem in KENNEY_CASTLE:
        entry = "Models/GLB format/%s.glb" % stem
        if entry not in zf.namelist():
            print("  ! missing", entry)
            continue
        count += _write(os.path.join(out, stem.replace("-", "_") + ".glb"), zf.read(entry))
    _copy_license(zf, out, "kenney_castle-kit.zip (Kenney Castle Kit)")
    return count


def extract_kaykit() -> int:
    out = os.path.join(ASSETS, "models", "kits", "dungeon")
    zf = _archive("KayKit_Dungeon_Pack_1.1_FREE.zip")
    base = "KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/"
    names = set(zf.namelist())
    count = 0
    count += _write(os.path.join(out, "dungeon_texture.png"), zf.read(base + "dungeon_texture.png"))
    for stem in KAYKIT_DUNGEON:
        gltf = base + stem + ".gltf"
        if gltf not in names:
            print("  ! missing", gltf)
            continue
        document = json.loads(zf.read(gltf).decode("utf-8"))
        for buffer in document.get("buffers", []):
            uri = buffer.get("uri")
            if uri and base + uri in names:
                count += _write(os.path.join(out, uri), zf.read(base + uri))
        count += _write(os.path.join(out, stem + ".gltf"), zf.read(gltf))
    _copy_license(zf, out, "KayKit_Dungeon_Pack_1.1_FREE.zip (KayKit Dungeon Pack)")
    return count


def extract_fantasy_props() -> int:
    from PIL import Image

    out = os.path.join(ASSETS, "models", "kits", "props")
    zf = _archive("Fantasy Props MegaKit[Standard].zip")
    base = "Exports/glTF/"
    names = set(zf.namelist())
    count = 0
    for stem in FANTASY_PROPS:
        gltf = base + stem + ".gltf"
        if gltf not in names:
            print("  ! missing", gltf)
            continue
        document = json.loads(zf.read(gltf).decode("utf-8"))
        for buffer in document.get("buffers", []):
            uri = buffer.get("uri")
            if uri and base + uri in names:
                count += _write(os.path.join(out, uri), zf.read(base + uri))
        count += _write(os.path.join(out, stem + ".gltf"), zf.read(gltf))
    for texture, limit in FANTASY_TEXTURE_LIMITS.items():
        entry = base + texture
        if entry not in names:
            continue
        image = Image.open(io.BytesIO(zf.read(entry)))
        if max(image.size) > limit:
            scale = limit / float(max(image.size))
            image = image.resize(
                (max(1, int(image.width * scale)), max(1, int(image.height * scale))),
                Image.LANCZOS,
            )
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        count += _write(os.path.join(out, texture), buffer.getvalue())
    _copy_license(zf, out, "Fantasy Props MegaKit[Standard].zip (Quaternius Fantasy Props MegaKit)")
    return count


def extract_cosmetics() -> int:
    out = os.path.join(ASSETS, "models", "cosmetics")
    outer = _archive("source (1).zip")
    inner = zipfile.ZipFile(io.BytesIO(outer.read("Separate_assets_glb.zip")))
    base = "Separate_assets_glb/"
    names = set(inner.namelist())
    count = 0
    for stem in COSMETICS:
        entry = base + stem + ".glb"
        if entry not in names:
            print("  ! missing", entry)
            continue
        count += _write(os.path.join(out, stem.replace("-", "_") + ".glb"), inner.read(entry))
    if base + "Textures_4.png" in names:
        count += _write(os.path.join(out, "Textures_4.png"), inner.read(base + "Textures_4.png"))
    _write(
        os.path.join(out, "LICENSE.txt"),
        (
            "Source archive: SOME ASSESTS/source (1).zip -> Separate_assets_glb.zip\n"
            "Pack: Creative Characters FREE (modular character accessories).\n"
            "Retain the original store licence with the archive; verify redistribution\n"
            "terms before shipping a build.\n"
        ).encode("utf-8"),
    )
    return count


def extract_audio() -> int:
    out = os.path.join(ASSETS, "audio", "sfx")
    count = 0
    impacts = _archive("kenney_impact-sounds.zip")
    for stem in IMPACT_SOUNDS:
        entry = "Audio/%s.ogg" % stem
        if entry not in impacts.namelist():
            print("  ! missing", entry)
            continue
        count += _write(os.path.join(out, stem + ".ogg"), impacts.read(entry))
    ui = _archive("kenney_ui-audio.zip")
    for stem in UI_SOUNDS:
        entry = "Audio/%s.ogg" % stem
        if entry not in ui.namelist():
            print("  ! missing", entry)
            continue
        count += _write(os.path.join(out, stem + ".ogg"), ui.read(entry))
    _copy_license(impacts, out, "kenney_impact-sounds.zip + kenney_ui-audio.zip (Kenney)")
    return count


def main() -> None:
    if not os.path.isdir(STAGING):
        raise SystemExit("staging folder not found: %s" % STAGING)
    steps = [
        ("Kenney Furniture Kit", extract_kenney_furniture),
        ("Kenney Castle Kit", extract_kenney_castle),
        ("KayKit Dungeon Pack", extract_kaykit),
        ("Fantasy Props MegaKit", extract_fantasy_props),
        ("Creative Characters cosmetics", extract_cosmetics),
        ("Kenney audio", extract_audio),
    ]
    for label, step in steps:
        print("==", label)
        print("   wrote/updated %d file(s)" % step())
    total = 0
    for folder, _dirs, files in os.walk(ASSETS):
        for name in files:
            total += os.path.getsize(os.path.join(folder, name))
    print("assets/ total: %.1f MB" % (total / 1048576.0))


if __name__ == "__main__":
    main()
