class_name ThemedArenaDecor
extends Node3D
## Builds each of the six arenas for the third-person camera.
##
## Layout rules (all arenas):
## - 28 x 24 m floor, enclosed on all four sides. The camera orbits freely, so
##   there is no "camera side" any more; every edge is a real wall.
## - The centre (~5 m radius) stays open for direct fights. Cover sits in a
##   mid ring: low cover (~1 m, you can see and throw over it) and a few pieces
##   of full cover (break line of sight). Decoration hugs the walls.
## - Open-air arenas use 4 m walls with a world beyond them; interiors use 8 m
##   walls and a lit ceiling.
## - Gameplay collision is simple boxes; decoration has none.
##
## Layout is deterministic (seeded from the arena id) so all network peers build
## identical geometry and pickup node paths line up.

## 36 x 32 m: room for six fighters to spread out, dodge, and flank. Both sides
## are multiples of the 4 m wall/floor module.
const HALF_X := 18.0
const HALF_Z := 16.0
const COLUMNS := int(HALF_X * 2.0 / 4.0)
const ROWS := int(HALF_Z * 2.0 / 4.0)
## Scale from the original 28 x 24 design layout to the current size.
const LAYOUT_SX := HALF_X / 14.0
const LAYOUT_SZ := HALF_Z / 12.0
const OPEN_WALL_HEIGHT := 4.0
const INTERIOR_HEIGHT := 8.0

@export_enum("sky_library", "classroom_chaos", "ancient_ruins", "tech_tower", "candy_island", "volcano_core")
var arena_id := "sky_library"

const THEMES := {
	"sky_library": {
		"name": "SKY LIBRARY", "interior": false,
		"floor": Color("f0e2cf"), "floor_tint": Color(0.5, 0.78, 0.98), "wall": Color(1.5, 1.3, 1.08), "accent": Color("e9bd4a"), "secondary": Color("7d93d6"),
		"sky_top": Color("3f63b8"), "sky_horizon": Color("cfdcf3"), "ground_horizon": Color("e8eef8"), "ground_bottom": Color("b9c8e6"),
		"fog": Color("d4def2"), "fog_begin": 40.0, "fog_end": 190.0, "fog_sky_affect": 0.15,
		"sun": Color("fff1d8"), "sun_energy": 1.25, "sun_rotation": Vector3(-48, -32, 0),
		"ambient": Color("aab8d8"), "ambient_energy": 0.55, "fill_energy": 0.3, "exposure": 0.95,
	},
	"classroom_chaos": {
		"name": "CLASSROOM CHAOS", "interior": true,
		"floor": Color("caa27a"), "floor_tint": Color(0.6, 0.9, 1.0), "wall": Color("dfe6d6"), "accent": Color("e4c957"), "secondary": Color("9fc4d8"),
		"sky_top": Color("6aa2cf"), "sky_horizon": Color("d8ecf2"),
		"fog": Color("cfe0e4"), "fog_begin": 60.0, "fog_end": 200.0,
		"sun": Color("fff5e2"), "sun_energy": 0.85, "sun_rotation": Vector3(-74, -24, 0),
		"ambient": Color("c4c8c2"), "ambient_energy": 0.62, "fill_energy": 0.2, "exposure": 0.95,
	},
	"ancient_ruins": {
		"name": "ANCIENT RUINS", "interior": false,
		"floor": Color("d8d0b8"), "floor_tint": Color(0.78, 0.9, 1.0), "wall": Color("c9c3a8"), "accent": Color("d3a941"), "secondary": Color("8fa1b8"),
		"sky_top": Color("58719a"), "sky_horizon": Color("e8cfa0"), "ground_horizon": Color("b6a07a"), "ground_bottom": Color("6f6450"),
		"fog": Color("c9bfa6"), "fog_begin": 45.0, "fog_end": 230.0, "fog_sky_affect": 0.3,
		"sun": Color("ffdcae"), "sun_energy": 1.2, "sun_rotation": Vector3(-34, -58, 0),
		"ambient": Color("9a917c"), "ambient_energy": 0.55, "fill_energy": 0.28, "exposure": 0.95,
	},
	"tech_tower": {
		"name": "TECH TOWER", "interior": true,
		"floor": Color("5a6680"), "wall": Color("2b3446"), "accent": Color("27d8ea"), "secondary": Color("8c5be0"),
		"sky_top": Color("070b16"), "sky_horizon": Color("1b2448"),
		"fog": Color("141c34"), "fog_begin": 60.0, "fog_end": 200.0,
		"sun": Color("d6e6ff"), "sun_energy": 0.7, "sun_rotation": Vector3(-76, 30, 0),
		"ambient": Color("6a7aa6"), "ambient_energy": 0.6, "fill_energy": 0.15, "exposure": 1.0, "glow": 0.55,
	},
	"candy_island": {
		"name": "CANDY ISLAND", "interior": false, "wall_height": 3.0,
		"floor": Color("f7a8c4"), "wall": Color("fff2f6"), "accent": Color("ffe273"), "secondary": Color("8fe0d4"),
		"sky_top": Color("5bb3ea"), "sky_horizon": Color("ffe1ec"), "ground_horizon": Color("ffd6e6"), "ground_bottom": Color("e98fb4"),
		"fog": Color("ffe3ee"), "fog_begin": 35.0, "fog_end": 170.0, "fog_sky_affect": 0.2,
		"sun": Color("fff6ea"), "sun_energy": 1.15, "sun_rotation": Vector3(-52, 28, 0),
		"ambient": Color("d0b0c0"), "ambient_energy": 0.5, "fill_energy": 0.3, "exposure": 0.8, "saturation": 1.1,
	},
	"volcano_core": {
		"name": "VOLCANO CORE", "interior": false,
		"floor": Color("8a7e7a"), "floor_tint": Color(0.5, 0.58, 0.66), "wall": Color("6e625f"), "accent": Color("ff6a2a"), "secondary": Color("ff9a5a"),
		"sky_top": Color("1a0a12"), "sky_horizon": Color("a8361c"), "ground_horizon": Color("c0441c"), "ground_bottom": Color("3a0e08"),
		"fog": Color("6a2414"), "fog_begin": 25.0, "fog_end": 140.0, "fog_sky_affect": 0.35,
		"sun": Color("ffc09a"), "sun_energy": 1.3, "sun_rotation": Vector3(-40, 150, 0),
		"ambient": Color("b08070"), "ambient_energy": 1.05, "fill_energy": 0.5, "exposure": 1.0, "glow": 0.6,
	},
}

var _theme: Dictionary
var _builder: ArenaBuilder
var _chalkboard: Node3D
var _ruins_shelves: Array[Node3D] = []
var _conveyor_arrows: Array[Node3D] = []
var _lava_ring: MeshInstance3D
var _ceiling_nodes: Array[Node3D] = []
var _world_environment: WorldEnvironment
var _base_fog_begin := 30.0
var _base_fog_end := 160.0

func _ready() -> void:
	_theme = THEMES.get(arena_id, THEMES["sky_library"])
	_builder = ArenaBuilder.new(self, arena_id.hash())
	_world_environment = _builder.environment(_theme)
	_base_fog_begin = _world_environment.environment.fog_depth_begin
	_base_fog_end = _world_environment.environment.fog_depth_end
	_build_shell()
	match arena_id:
		"sky_library": _build_sky_library()
		"classroom_chaos": _build_classroom()
		"ancient_ruins": _build_ruins()
		"tech_tower": _build_tech()
		"candy_island": _build_candy()
		"volcano_core": _build_volcano()
	if Perf.is_mobile():
		_builder.strip_static_shadows()

func half_extents() -> Vector2:
	return Vector2(HALF_X, HALF_Z)

func theme() -> Dictionary:
	return _theme

## Overhead "god's eye" spectating: interior ceilings are hidden so the camera can
## look down into the room, and fog is pushed back so the far floor is not hazed.
func set_overhead_view(enabled: bool) -> void:
	for node in _ceiling_nodes:
		if is_instance_valid(node):
			node.visible = not enabled
	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		env.fog_depth_begin = _base_fog_begin + (70.0 if enabled else 0.0)
		env.fog_depth_end = _base_fog_end + (70.0 if enabled else 0.0)

func is_interior() -> bool:
	return bool(_theme.get("interior", false))

## Camera ceiling clamp. Open-air arenas only bound it by the fighter lid.
func ceiling_height() -> float:
	return INTERIOR_HEIGHT if is_interior() else 9.5

# --------------------------------------------------------------------------- #
# Shared shell
# --------------------------------------------------------------------------- #

func _build_shell() -> void:
	_builder.floor_plate(HALF_X, HALF_Z, Color(_theme["floor"]).darkened(0.35))
	var height := INTERIOR_HEIGHT if is_interior() else float(_theme.get("wall_height", OPEN_WALL_HEIGHT))
	# Visible walls block fighters, books, and the camera.
	_builder.wall_colliders(HALF_X, HALF_Z, height)
	# Fighter-only lid + extension so knockback/bounces can never clear a wall.
	_builder.boundary_walls(HALF_X, HALF_Z, INTERIOR_HEIGHT if is_interior() else 10.0)
	if is_interior():
		_builder.add_box_body(Vector3(HALF_X * 2.0 + 2.0, 0.5, HALF_Z * 2.0 + 2.0), Vector3(0, INTERIOR_HEIGHT + 0.25, 0))

## 4 m kit floor tiles, exactly 7 x 6 across the play space. Tinted by
## multiplying the original texture, so the planks/stones keep their detail.
func _tile_floor(kit: String, model_name: String, variation: float = 0.06) -> void:
	# The kit floors are saturated terracotta. A per-theme tint (multiplied into
	# the texture, so plank/stone detail survives) pulls them to the right hue.
	var base := Color(_theme.get("floor_tint", _theme["floor"]))
	for column in range(COLUMNS):
		for row in range(ROWS):
			var position := Vector3(-HALF_X + 4.0 * (0.5 + column), 0.0, -HALF_Z + 4.0 * (0.5 + row))
			var tile := _builder.place(kit, model_name, position, PI * 0.5 * float((column * 3 + row) % 2), 1.0, false)
			if tile:
				var shade := base.lightened(variation) if (column + row) % 2 == 0 else base.darkened(variation * 0.5)
				_builder.tint(tile, shade)

## Kit walls (4 m modules) around all four sides, faces pointing inward, inner
## face exactly on the collision line. `models` cycles per module; `inset`
## pushes modules whose detail protrudes (wall_shelves) back into the wall line.
func _kit_wall_ring(models: Array, rows: int = 1, inset: Dictionary = {}) -> void:
	var color: Color = _theme.get("wall", Color.WHITE)
	var index := 0
	var runs := [
		# [start, step, count, fixed coordinate, rotation, along x]
		[-HALF_X + 2.0, 4.0, COLUMNS, -HALF_Z - 0.5, 0.0, true],
		[-HALF_X + 2.0, 4.0, COLUMNS, HALF_Z + 0.5, PI, true],
		[-HALF_Z + 2.0, 4.0, ROWS, -HALF_X - 0.5, PI * 0.5, false],
		[-HALF_Z + 2.0, 4.0, ROWS, HALF_X + 0.5, -PI * 0.5, false],
	]
	for run in runs:
		for i in range(int(run[2])):
			var along: float = float(run[0]) + float(run[1]) * i
			var inward := Vector3(0.0, 0.0, 1.33).rotated(Vector3.UP, float(run[4]))
			for row in range(rows):
				var model := String(models[(index + row * 3) % models.size()])
				var position := Vector3(along, 4.0 * row, float(run[3])) if bool(run[5]) else Vector3(float(run[3]), 4.0 * row, along)
				position -= inward * float(inset.get(model, 0.0))
				var wall := _builder.place(ArenaBuilder.KIT_DUNGEON, model, position, float(run[4]), 1.0, false)
				if wall:
					_builder.tint(wall, color.darkened(_builder.rng.randf_range(0.0, 0.06)))
			index += 1
	for corner in [Vector3(-HALF_X - 0.5, 0, -HALF_Z - 0.5), Vector3(HALF_X + 0.5, 0, -HALF_Z - 0.5), Vector3(-HALF_X - 0.5, 0, HALF_Z + 0.5), Vector3(HALF_X + 0.5, 0, HALF_Z + 0.5)]:
		for row in range(rows):
			var pillar := _builder.place(ArenaBuilder.KIT_DUNGEON, "pillar", corner + Vector3(0, 4.0 * row, 0), 0.0, 1.05, false)
			if pillar:
				_builder.tint(pillar, color.darkened(0.08))

## Points evenly around the arena beyond the walls, for backdrop placement.
func _ring_points(count: int, radius_min: float, radius_max: float, phase: float = 0.0) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(count):
		var angle := phase + TAU * (float(i) + _builder.rng.randf_range(-0.3, 0.3)) / float(count)
		var radius := _builder.rng.randf_range(radius_min, radius_max)
		points.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	if Perf.is_mobile():
		# Every point is still generated above so the seeded random stream (and so
		# all gameplay layout) is identical on phones and PCs. Phones just draw
		# half of the far-away backdrop pieces.
		var thinned: Array[Vector3] = []
		for i in range(0, points.size(), 2):
			thinned.append(points[i])
		return thinned
	return points

## Soft cloud bank made of a few overlapping flattened spheres.
func _cloud(centre: Vector3, size: float, color: Color) -> void:
	var material := _builder.toon_material(color, 0.0, false, 1.0)
	var puffs := 4 + _builder.rng.randi() % 3
	for i in range(puffs):
		var mesh := SphereMesh.new()
		var r := size * _builder.rng.randf_range(0.45, 0.8)
		mesh.radius = r
		mesh.height = r * 2.0
		mesh.radial_segments = 14
		mesh.rings = 7
		var offset := Vector3((float(i) - puffs * 0.5) * size * 0.55, _builder.rng.randf_range(-0.1, 0.25) * size, _builder.rng.randf_range(-0.3, 0.3) * size)
		_builder.backdrop(mesh, Transform3D(Basis.IDENTITY.scaled(Vector3(1.29, 0.55, 1.07)), centre + offset), material)

func _landform(profile: Array, radius: float, position: Vector3, cap: Color, side: Color, rotation_y: float = 0.0, segments: int = 9, jitter: float = 0.18, emission: float = 0.0) -> MeshInstance3D:
	var mesh := BackdropForms.landform(radius, profile, segments, jitter, int(position.x * 13.0 + position.z * 7.0) + arena_id.hash(), cap, side)
	return _builder.backdrop(mesh, Transform3D(Basis(Vector3.UP, rotation_y), position), BackdropForms.vertex_color_material(emission))

func _wall_light(position: Vector3, rotation_y: float, color: Color, energy: float = 0.7) -> void:
	_builder.place(ArenaBuilder.KIT_DUNGEON, "torch_mounted", position, rotation_y, 1.0, false)
	_builder.accent_light(position + Vector3(0, 0.6, 0) + Vector3(0.0, 0.0, 0.8).rotated(Vector3.UP, rotation_y), color, energy, 6.0)

# --------------------------------------------------------------------------- #
# Sky Library — open-roofed reading hall floating above a sea of clouds
# --------------------------------------------------------------------------- #

func _build_sky_library() -> void:
	_tile_floor(ArenaBuilder.KIT_DUNGEON, "floor_wood_large")
	_kit_wall_ring(["wall_archedwindow_open", "wall_shelves", "wall", "wall_archedwindow_open", "wall_shelves", "wall_window_open"], 1, {"wall_shelves": 0.37})

	# Landmark: central reading dais. Gentle 25 deg edge so everyone (bots too)
	# simply runs up it; standing on it gives a small height edge for throws.
	_builder.frustum(3.0, 3.7, 0.35, Vector3(0, 0.175, 0), Color("b89a7a"), true, 40)
	var rug := _builder.place(ArenaBuilder.KIT_FURNITURE, "rugRound", Vector3(0, 0.36, 0), 0.0, 2.7, false)
	if rug:
		_builder.tint(rug, Color("b0384a"))
	_builder.glow_ring(3.65, 0.12, Vector3(0, 0.37, 0), Color(_theme["accent"]), 0.7)
	_builder.place(ArenaBuilder.KIT_PROPS, "BookStand", Vector3(0, 0.35, 0), 0.0, 1.0, true, 0.1)
	_floating_book_ring(Vector3(0, 6.6, 0), 4.2, 8)

	# Full cover: two tall shelf stacks and a free-standing case, deliberately
	# not mirrored, so each side of the hall reads differently.
	for spec in [[Vector3(-10.29, 0.0, -5.33), 0.3], [Vector3(11.06, 0.0, 5.87), -0.45]]:
		var yaw: float = spec[1]
		var centre: Vector3 = spec[0]
		var along := Vector3(0.0, 0.0, 0.32).rotated(Vector3.UP, yaw)
		_builder.place(ArenaBuilder.KIT_PROPS, "Bookcase_2", centre + along, yaw, 1.0, false)
		_builder.place(ArenaBuilder.KIT_PROPS, "Bookcase_2", centre - along, yaw + PI, 1.0, false)
		_builder.add_box_body(Vector3(1.4, 2.5, 0.9), centre + Vector3(0, 1.25, 0), yaw)
		_builder.place(ArenaBuilder.KIT_PROPS, "Book_Stack_2", centre + Vector3(0, 2.52, 0), yaw, 1.0, false)
	var case := load("res://assets/models/props/bookshelf.glb") as PackedScene
	if case:
		var shelf := case.instantiate() as Node3D
		_builder.decor_root().add_child(shelf)
		shelf.position = Vector3(4.11, 0.0, -11.47)
		shelf.rotation.y = 0.15
		_builder.add_box_body(Vector3(1.75, 2.38, 0.8), Vector3(4.11, 1.19, -11.53), 0.15)

	# Low cover: reading tables you can see and throw over.
	for spec in [[Vector3(-5.91, 0.0, 6.67), 0.4], [Vector3(5.91, 0.0, -6.13), -0.25], [Vector3(-5.4, 0.0, 12.8), 0.0]]:
		_builder.place(ArenaBuilder.KIT_PROPS, "Table_Large", spec[0], spec[1], 1.0, true, 0.15)
		_builder.place(ArenaBuilder.KIT_PROPS, "Book_Stack_1", spec[0] + Vector3(0.77, 0.81, 0.13).rotated(Vector3.UP, spec[1]), _builder.rng.randf_range(0, TAU), 1.0, false)
		_builder.place(ArenaBuilder.KIT_PROPS, "CandleStick_Triple", spec[0] + Vector3(-0.9, 0.81, 0.0).rotated(Vector3.UP, spec[1]), spec[1], 1.0, false)
		for side in [-1.0, 1.0]:
			_builder.place(ArenaBuilder.KIT_PROPS, "Chair_1", spec[0] + Vector3(0.4 * side, 0, 0.85 * side).rotated(Vector3.UP, spec[1]), spec[1] + (0.0 if side < 0 else PI), 1.0, false)

	# Perimeter dressing only: crates of returns, a reading bench, lanterns.
	for position in [Vector3(16.2, 0.0, -4.8), Vector3(-16.2, 0.0, 5.6)]:
		_builder.place(ArenaBuilder.KIT_PROPS, "Crate_Wooden", position, _builder.rng.randf_range(-0.3, 0.3), 1.0, true, 0.1)
		_builder.place(ArenaBuilder.KIT_PROPS, "BookGroup_Medium_1", position + Vector3(0, 1.12, 0), 0.4, 1.0, false)
	_builder.place(ArenaBuilder.KIT_PROPS, "Bench", Vector3(11.57, 0.0, 15.07), PI, 1.0, true, 0.1)
	_builder.place(ArenaBuilder.KIT_PROPS, "Bench", Vector3(-12.21, 0.0, -15.07), 0.0, 1.0, true, 0.1)
	for spec in [[Vector3(-HALF_X, 2.4, -6.0), PI * 0.5], [Vector3(-HALF_X, 2.4, 6.0), PI * 0.5], [Vector3(HALF_X, 2.4, -6.0), -PI * 0.5], [Vector3(HALF_X, 2.4, 6.0), -PI * 0.5]]:
		_wall_light(spec[0], spec[1], Color("ffc27a"), 0.6)

	_sky_backdrop()

## Books slowly orbiting above the dais: the hall's signature landmark, readable
## from anywhere in the arena and well above every fighter.
func _floating_book_ring(centre: Vector3, radius: float, count: int) -> void:
	var pivot := Node3D.new()
	pivot.name = "FloatingBooks"
	pivot.position = centre
	_builder.decor_root().add_child(pivot)
	var book_scene := load(GameState.BOOK_MODEL) as PackedScene
	var colours := [Color("b0384a"), Color("3f63b8"), Color("e9bd4a"), Color("4f9a62")]
	for i in range(count):
		if book_scene == null:
			break
		var angle := TAU * float(i) / float(count)
		var book := book_scene.instantiate() as Node3D
		pivot.add_child(book)
		book.position = Vector3(cos(angle) * radius, sin(angle * 2.0) * 0.4, sin(angle) * radius)
		book.rotation = Vector3(0.3 * sin(angle * 3.0), -angle, 0.25)
		book.scale = Vector3.ONE * 1.7
		GameState.apply_book_style(book, "book_gold" if i % 2 == 0 else "book_classic")
		_builder.set_shadows(book, false)
	var tween := pivot.create_tween().set_loops()
	tween.tween_property(pivot, "rotation:y", TAU, 48.0).from(0.0)
	_builder.accent_light(centre + Vector3(0, -1.5, 0), Color("ffe2a8"), 0.7, 7.0)

func _sky_backdrop() -> void:
	var grass := Color("8cc46a")
	var rock := Color("9c8a7c")
	# Mid-distance islands carry small libraries so the world reads as "more of
	# this place", not empty sky.
	var islands := _ring_points(7, 42.0, 70.0, 0.4)
	for i in range(islands.size()):
		var base := islands[i] + Vector3(0, _builder.rng.randf_range(-6.0, 9.0), 0)
		var radius := _builder.rng.randf_range(6.0, 11.0)
		_landform(BackdropForms.island_profile(1.2, radius * 1.4), radius, base, grass, rock, _builder.rng.randf() * TAU, 10)
		if i % 2 == 0:
			var tower := _builder.place_transformed(ArenaBuilder.KIT_CASTLE, "tower_square_base", Transform3D(Basis(Vector3.UP, _builder.rng.randf() * TAU).scaled(Vector3.ONE * 1.4), base + Vector3(0, 1.1, 0)))
			if tower:
				_builder.tint(tower, Color("efe4d2"))
			_builder.place_transformed(ArenaBuilder.KIT_CASTLE, "tower_slant_roof", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.4), base + Vector3(0, 1.1 + 4.2, 0)))
		else:
			for k in range(2):
				_builder.place_transformed(ArenaBuilder.KIT_PROPS, "Bookcase_2", Transform3D(Basis(Vector3.UP, _builder.rng.randf() * TAU).scaled(Vector3.ONE * 2.2), base + Vector3(k * 3.0 - 1.5, 1.1, 0)))
	# Far islands: silhouettes only, softened by fog.
	for point in _ring_points(9, 95.0, 140.0, 1.1):
		var radius := _builder.rng.randf_range(10.0, 18.0)
		_landform(BackdropForms.island_profile(1.5, radius * 1.5), radius, point + Vector3(0, _builder.rng.randf_range(-4.0, 16.0), 0), grass.darkened(0.1), rock, _builder.rng.randf() * TAU, 8)
	# Clouds above and below the horizon; the low ones form the "cloud sea".
	for point in _ring_points(12, 34.0, 120.0, 0.0):
		_cloud(point + Vector3(0, _builder.rng.randf_range(-14.0, -6.0), 0), _builder.rng.randf_range(6.0, 12.0), Color("f4f7ff"))
	for point in _ring_points(8, 50.0, 130.0, 0.7):
		_cloud(point + Vector3(0, _builder.rng.randf_range(14.0, 34.0), 0), _builder.rng.randf_range(5.0, 10.0), Color("ffffff"))

# --------------------------------------------------------------------------- #
# Shared layout helpers
# --------------------------------------------------------------------------- #

## Cover slots sit *between* the eight spawn markers (spawns use angles k*45 deg
## on a 10.5 x 8.5 ellipse), so no fighter ever spawns pressed against cover and
## every spawn has an equal mix of open lanes and nearby protection.
func _cover_slot(index: int, rx: float = 7.5 * LAYOUT_SX, rz: float = 6.2 * LAYOUT_SZ) -> Vector3:
	var angle := deg_to_rad(22.5 + 45.0 * float(index))
	return Vector3(sin(angle) * rx, 0.0, cos(angle) * rz)

## Room shell for interior arenas: plaster walls with wainscot and trim, and a
## ceiling with beams. Walls and ceiling cast no shadows because the room is lit
## from fixtures *inside* it (the steep "key" light stands in for those panels);
## props and fighters still cast the soft downward shadows panel lights give.
func _interior_shell(wall_color: Color, wainscot_color: Color, trim_color: Color, ceiling_color: Color, wainscot_height: float = 1.2) -> void:
	var h := INTERIOR_HEIGHT
	var faces := [
		[Vector3(0, h * 0.5, -HALF_Z - 0.2), Vector3(HALF_X * 2.0 + 0.8, h, 0.4), 0.0],
		[Vector3(0, h * 0.5, HALF_Z + 0.2), Vector3(HALF_X * 2.0 + 0.8, h, 0.4), 0.0],
		[Vector3(-HALF_X - 0.2, h * 0.5, 0), Vector3(0.4, h, HALF_Z * 2.0 + 0.8), 0.0],
		[Vector3(HALF_X + 0.2, h * 0.5, 0), Vector3(0.4, h, HALF_Z * 2.0 + 0.8), 0.0],
	]
	for face in faces:
		var wall := _builder.box(face[1], face[0], wall_color, 0.0, false)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Wainscot, chair rail, skirting, and crown moulding run round the room.
	for side in [[Vector3(0, 0, -HALF_Z), true], [Vector3(0, 0, HALF_Z), true], [Vector3(-HALF_X, 0, 0), false], [Vector3(HALF_X, 0, 0), false]]:
		var origin: Vector3 = side[0]
		var along_x: bool = side[1]
		var inward := -origin.normalized() if origin.length() > 0.0 else Vector3.ZERO
		var length := HALF_X * 2.0 if along_x else HALF_Z * 2.0
		var strips := [
			[wainscot_height, 0.08, wainscot_height * 0.5, wainscot_color],
			[0.12, 0.14, wainscot_height + 0.06, trim_color],
			[0.18, 0.12, 0.09, trim_color.darkened(0.2)],
			[0.25, 0.16, h - 0.12, trim_color],
		]
		for strip in strips:
			var size := Vector3(length, strip[0], strip[1]) if along_x else Vector3(strip[1], strip[0], length)
			var piece := _builder.box(size, origin + inward * float(strip[1]) * 0.5 + Vector3(0, strip[2], 0), strip[3], 0.0, false)
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ceiling := _builder.box(Vector3(HALF_X * 2.0 + 0.8, 0.3, HALF_Z * 2.0 + 0.8), Vector3(0, h + 0.15, 0), ceiling_color, 0.0, false)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ceiling_nodes.append(ceiling)
	for i in range(COLUMNS - 1):
		var beam := _builder.box(Vector3(0.45, 0.4, HALF_Z * 2.0), Vector3(-HALF_X + 4.0 * (i + 1), h - 0.2, 0), ceiling_color.darkened(0.12), 0.0, false)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ceiling_nodes.append(beam)

## Grid of emissive ceiling panels, each with a soft local light under it. These
## are what visibly "light the room".
func _ceiling_panels(columns: int, rows: int, panel_size: Vector2, color: Color, light_color: Color, energy: float, light_energy: float = 0.75) -> void:
	for c in range(columns):
		for r in range(rows):
			var x := -HALF_X + (HALF_X * 2.0) * (float(c) + 0.5) / float(columns)
			var z := -HALF_Z + (HALF_Z * 2.0) * (float(r) + 0.5) / float(rows)
			var panel := _builder.box(Vector3(panel_size.x, 0.06, panel_size.y), Vector3(x, INTERIOR_HEIGHT - 0.04, z), color, 0.0, false, energy)
			panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ceiling_nodes.append(panel)
			var housing := _builder.box(Vector3(panel_size.x + 0.2, 0.08, panel_size.y + 0.2), Vector3(x, INTERIOR_HEIGHT - 0.0, z), Color("d8d8d8"), 0.0, false)
			housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ceiling_nodes.append(housing)
			_builder.accent_light(Vector3(x, INTERIOR_HEIGHT - 1.2, z), light_color, light_energy, 9.5)

# --------------------------------------------------------------------------- #
# Classroom Chaos — an enclosed, daylit classroom
# --------------------------------------------------------------------------- #

func _build_classroom() -> void:
	_tile_floor(ArenaBuilder.KIT_DUNGEON, "floor_wood_large", 0.04)
	_interior_shell(Color("e6ead8"), Color("9a6a43"), Color("f4f0e4"), Color("f2f1ea"))
	_ceiling_panels(3, 2, Vector2(3.4, 1.4), Color("fffaf0"), Color("fff3dc"), 2.2, 0.7)

	# Landmark: the chalkboard. The hazard flashes it when a supply drop appears
	# at its foot, so it sits centred on the far wall where everyone can see it.
	_builder.box(Vector3(11.6, 3.8, 0.12), Vector3(0, 2.75, -HALF_Z + 0.06), Color("7a5232"), 0.0, false)
	_chalkboard = _builder.box(Vector3(11.0, 3.2, 0.12), Vector3(0, 2.75, -HALF_Z + 0.14), Color("2f5a46"), 0.0, false)
	_chalkboard.name = "Chalkboard"
	_builder.box(Vector3(11.0, 0.08, 0.3), Vector3(0, 1.1, -HALF_Z + 0.2), Color("7a5232"), 0.0, false)
	for i in range(6):
		# Chalk "writing": a few pale strokes so the board reads as a board.
		_builder.box(Vector3(_builder.rng.randf_range(1.2, 3.4), 0.08, 0.02), Vector3(_builder.rng.randf_range(-4.0, 4.0), 3.6 - i * 0.38, -HALF_Z + 0.21), Color("e9efe6"), 0.0, false, 0.15, false)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "desk", Vector3(-7.97, 0.0, -12.8), 0.0, 1.15, true, 0.15)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "chairDesk", Vector3(-7.97, 0.0, -14.4), PI, 1.0, false)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "laptop", Vector3(-8.36, 0.98, -12.8), 0.2, 1.0, false)
	_builder.place(ArenaBuilder.KIT_PROPS, "Book_Stack_1", Vector3(-7.2, 0.98, -12.67), 0.6, 1.4, false)

	# East wall: tall daylight windows. Emissive glass plus a cool fill light per
	# window is what tells you it is daytime outside.
	for z in [-10.5, -3.5, 3.5, 10.5]:
		var glass := _builder.box(Vector3(0.05, 3.4, 3.0), Vector3(HALF_X - 0.03, 3.9, z), Color("dff1ff"), 0.0, false, 1.3, false)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for offset in [Vector3(0, 1.75, 0), Vector3(0, -1.75, 0)]:
			_builder.box(Vector3(0.14, 0.12, 3.2), Vector3(HALF_X - 0.07, 3.9, z) + offset, Color("f4f0e4"), 0.0, false)
		for offset in [Vector3(0.0, 0.0, 2.07), Vector3(0.0, 0.0, -2.07), Vector3(0, 0, 0)]:
			_builder.box(Vector3(0.14, 3.6, 0.1), Vector3(HALF_X - 0.07, 3.9, z) + offset, Color("f4f0e4"), 0.0, false)
		_builder.box(Vector3(0.4, 0.08, 3.3), Vector3(HALF_X - 0.2, 2.15, z), Color("f4f0e4"), 0.0, false)
		_builder.accent_light(Vector3(HALF_X - 1.6, 3.6, z), Color("cfe6ff"), 0.6, 7.0)

	# West wall: locker bank (dressing, collides as one flat face).
	var locker_colours := [Color("4f7fb8"), Color("4a76ad")]
	for i in range(16):
		var z := -13.5 + i * 0.9
		_builder.box(Vector3(0.6, 2.2, 0.86), Vector3(-HALF_X + 0.3, 1.1, z), locker_colours[i % 2], 0.0, false)
		_builder.box(Vector3(0.02, 0.5, 0.4), Vector3(-HALF_X + 0.61, 1.7, z), Color("2e4f7a"), 0.0, false, 0.0, false)
	_builder.add_box_body(Vector3(0.6, 2.2, 14.4), Vector3(-HALF_X + 0.3, 1.1, -6.75))
	for z in [5.0, 8.5, 12.0]:
		_builder.place(ArenaBuilder.KIT_FURNITURE, "bookcaseClosedWide", Vector3(-HALF_X + 0.35, 0, z), PI * 0.5, 1.0, true, 0.1)

	# South wall: pinboard of artwork, a clock, bins.
	_builder.box(Vector3(6.0, 2.0, 0.06), Vector3(4.0, 2.6, HALF_Z - 0.04), Color("b98a5a"), 0.0, false)
	var paper := [Color("f6e27a"), Color("f2a3a3"), Color("a3d6f2"), Color("b7e3a1"), Color("ffffff")]
	for i in range(9):
		_builder.box(Vector3(0.7, 0.55, 0.02), Vector3(1.6 + (i % 5) * 1.15 + _builder.rng.randf_range(-0.1, 0.1), 3.05 - (i / 5) * 0.85, HALF_Z - 0.08), paper[i % paper.size()], 0.0, false, 0.0, false)
	_builder.cylinder(0.42, 0.08, Vector3(-4.0, 5.4, HALF_Z - 0.08), Color("fbfbf6"), false)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "trashcan", Vector3(-1.5, 0, HALF_Z - 0.5), 0.0, 1.0, false)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "pottedPlant", Vector3(HALF_X - 0.6, 0, HALF_Z - 0.6), 0.0, 1.4, false)
	_builder.place(ArenaBuilder.KIT_FURNITURE, "pottedPlant", Vector3(HALF_X - 0.6, 0, -HALF_Z + 0.6), 0.0, 1.4, false)

	# Low cover: four pairs of student desks between spawns (throw over them,
	# crouch-jog behind them). Full cover: two tall supply cabinets.
	for slot in [1, 3, 5, 7]:
		var centre := _cover_slot(slot)
		var yaw := atan2(-centre.x, -centre.z) + _builder.rng.randf_range(-0.25, 0.25)
		for side in [-0.74, 0.74]:
			var desk_pos := centre + Vector3(side, 0, 0).rotated(Vector3.UP, yaw)
			_builder.place(ArenaBuilder.KIT_FURNITURE, "desk", desk_pos, yaw, 0.9, true, 0.1)
			_builder.place(ArenaBuilder.KIT_FURNITURE, "chairDesk", desk_pos + Vector3(0.0, 0.0, 1.27).rotated(Vector3.UP, yaw), yaw + PI, 0.95, false)
			if _builder.rng.randf() < 0.7:
				_builder.place(ArenaBuilder.KIT_PROPS, "Book_5", desk_pos + Vector3(0, 0.78, 0), _builder.rng.randf_range(0, TAU), 1.0, false)
	# Full cover: a single supply cabinet each, pushed out toward the room edge
	# and turned side-on so it blocks a lane without walling off a spawn.
	for slot in [2, 6]:
		var centre := _cover_slot(slot, 9.0 * LAYOUT_SX, 7.4 * LAYOUT_SZ)
		var yaw := atan2(-centre.x, -centre.z)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "bookcaseClosedDoors", centre, yaw, 1.05, true, 0.1)

# --------------------------------------------------------------------------- #
# Tech Tower — server floor high above a night city
# --------------------------------------------------------------------------- #

func _build_tech() -> void:
	var accent := Color(_theme["accent"])
	var secondary := Color(_theme["secondary"])
	# Floor: dark plates with thin glowing seams (seams are the readable grid).
	for column in range(COLUMNS):
		for row in range(ROWS):
			var position := Vector3(-HALF_X + 4.0 * (0.5 + column), 0.0, -HALF_Z + 4.0 * (0.5 + row))
			var shade := Color(_theme["floor"]).lightened(0.05 if (column + row) % 2 == 0 else 0.0)
			_builder.box(Vector3(3.92, 0.1, 3.92), position + Vector3(0, -0.04, 0), shade, 0.0, false)
	for x in range(-3, 4):
		_builder.box(Vector3(0.06, 0.02, HALF_Z * 2.0), Vector3(x * 4.0, 0.015, 0), accent.darkened(0.35), 0.0, false, 0.6, false)
	_interior_shell(Color("2b3446"), Color("1f2636"), Color("3b475e"), Color("1c2230"), 0.9)
	# Long light strips rather than square panels: they read as "tech".
	for x in [-12.0, -4.0, 4.0, 12.0]:
		var strip := _builder.box(Vector3(0.35, 0.06, HALF_Z * 2.0 - 3.0), Vector3(x, INTERIOR_HEIGHT - 0.45, 0), Color("e6f6ff"), 0.0, false, 2.6, false)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ceiling_nodes.append(strip)
		# Phones get one light per strip (spread evenly) instead of three.
		for z in ([0.0] if Perf.is_mobile() else [-8.0, 0.0, 8.0]):
			_builder.accent_light(Vector3(x, INTERIOR_HEIGHT - 1.5, z), Color("dcefff"), 0.75, 9.0)
	# Accent seams round the walls at skirting height.
	for side in [[Vector3(0, 0.95, -HALF_Z + 0.02), Vector3(HALF_X * 2.0, 0.05, 0.04)], [Vector3(0, 0.95, HALF_Z - 0.02), Vector3(HALF_X * 2.0, 0.05, 0.04)], [Vector3(-HALF_X + 0.02, 0.95, 0), Vector3(0.04, 0.05, HALF_Z * 2.0)], [Vector3(HALF_X - 0.02, 0.95, 0), Vector3(0.04, 0.05, HALF_Z * 2.0)]]:
		_builder.box(side[1], side[0], accent, 0.0, false, 1.4, false)

	# North and south walls: rows of server racks with blinking LED faces.
	for z_sign in [-1.0, 1.0]:
		for i in range(8):
			var x := -14.0 + i * 4.0
			if absf(x) < 1.0:
				continue
			var rack_pos := Vector3(x, 1.3, (HALF_Z - 0.6) * z_sign)
			_builder.box(Vector3(3.2, 2.6, 1.2), rack_pos, Color("3a4766"), 0.0, true)
			for led in range(5):
				var color := accent if (i + led) % 3 != 0 else secondary
				_builder.box(Vector3(2.6, 0.05, 0.02), rack_pos + Vector3(0, -0.9 + led * 0.42, -0.61 * z_sign), color, 0.0, false, 1.2, false)

	# West wall: panoramic window onto the city at night (landmark backdrop).
	_builder.box(Vector3(0.05, 4.4, HALF_Z * 2.0 - 4.0), Vector3(-HALF_X + 0.03, 4.2, 0), Color("101a3a"), 0.0, false, 0.9, false)
	for i in range(25):
		var height := _builder.rng.randf_range(0.8, 3.4)
		var z := -12.6 + i * 1.05
		_builder.box(Vector3(0.04, height, 0.9), Vector3(-HALF_X + 0.06, 2.0 + height * 0.5, z), Color("05070f"), 0.0, false, 0.0, false)
		for w in range(int(height / 0.5)):
			if _builder.rng.randf() < 0.45:
				_builder.box(Vector3(0.02, 0.1, 0.16), Vector3(-HALF_X + 0.09, 2.2 + w * 0.5, z + _builder.rng.randf_range(-0.3, 0.3)), Color("ffd27a"), 0.0, false, 1.6, false)
	for z in [-13.0, -6.5, 0.0, 6.5, 13.0]:
		_builder.box(Vector3(0.18, 4.6, 0.18), Vector3(-HALF_X + 0.1, 4.2, z), Color("3b475e"), 0.0, false)

	# Landmark: holographic data globe hanging above the conveyor.
	var globe_material := StandardMaterial3D.new()
	globe_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.22)
	globe_material.emission_enabled = true
	globe_material.emission = accent
	globe_material.emission_energy_multiplier = 1.5
	globe_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	globe_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 1.4
	globe_mesh.height = 2.8
	globe_mesh.radial_segments = 16
	globe_mesh.rings = 8
	var globe := _builder.backdrop(globe_mesh, Transform3D(Basis.IDENTITY, Vector3(0, 5.6, 0)), globe_material)
	globe.create_tween().set_loops().tween_property(globe, "rotation:y", TAU, 14.0).from(0.0)
	_builder.glow_ring(1.9, 0.08, Vector3(0, 5.6, 0), accent, 1.4).rotation.x = 0.3
	_builder.box(Vector3(0.08, 1.6, 0.08), Vector3(0, 7.2, 0), Color("3b475e"), 0.0, false)

	# Conveyor lane through the middle; the hazard script supplies the push and
	# drives the chevrons, which point the way the belt is moving.
	var lane_length := ArenaHazards.CONVEYOR_LENGTH
	var lane_width := ArenaHazards.CONVEYOR_HALF_WIDTH * 2.0
	_builder.box(Vector3(lane_length, 0.06, lane_width), Vector3(0, 0.03, 0), Color("1d2533"), 0.0, false)
	for z in [-ArenaHazards.CONVEYOR_HALF_WIDTH, ArenaHazards.CONVEYOR_HALF_WIDTH]:
		_builder.box(Vector3(lane_length, 0.08, 0.12), Vector3(0, 0.05, z), Color("f2c230"), 0.0, false, 0.4)
	_conveyor_arrows.clear()
	var arrow_count := int(lane_length / ArenaHazards.CONVEYOR_ARROW_SPACING)
	for i in range(arrow_count):
		var arrow := Node3D.new()
		arrow.name = "Chevron%d" % i
		arrow.position = Vector3(-lane_length * 0.5 + i * ArenaHazards.CONVEYOR_ARROW_SPACING, 0.075, 0)
		_builder.decor_root().add_child(arrow)
		for side in [-1.0, 1.0]:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.18, 0.02, 1.7)
			var bar := MeshInstance3D.new()
			bar.mesh = mesh
			bar.material_override = _builder.toon_material(accent.darkened(0.15), 1.2, false)
			bar.position = Vector3(0, 0, 0.62 * side)
			bar.rotation.y = 0.55 * side
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arrow.add_child(bar)
		_conveyor_arrows.append(arrow)

	# Full cover: two server-rack islands. Low cover: two operator consoles.
	for slot in [0, 4]:
		var centre := _cover_slot(slot)
		var yaw := atan2(-centre.x, -centre.z) + PI * 0.5
		_builder.box(Vector3(2.6, 2.3, 1.1), centre + Vector3(0, 1.15, 0), Color("46557a"), yaw, true)
		for face in [-1.0, 1.0]:
			for led in range(4):
				_builder.box(Vector3(2.1, 0.05, 0.02), centre + Vector3(0, 0.5 + led * 0.42, 0.56 * face).rotated(Vector3.UP, yaw) + Vector3(0, 0, 0), accent if led % 2 == 0 else secondary, yaw, false, 1.2, false)
		_builder.box(Vector3(2.7, 0.08, 1.2), centre + Vector3(0, 2.34, 0), accent.darkened(0.4), yaw, false, 0.8, false)
	for slot in [3, 7]:
		var centre := _cover_slot(slot)
		var yaw := atan2(-centre.x, -centre.z)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "desk", centre, yaw, 1.2, true, 0.1)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "computerScreen", centre + Vector3(-0.39, 1.02, 0.0).rotated(Vector3.UP, yaw), yaw, 1.0, false)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "computerScreen", centre + Vector3(0.58, 1.02, 0.0).rotated(Vector3.UP, yaw), yaw - 0.3, 1.0, false)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "computerKeyboard", centre + Vector3(0.0, 1.02, 0.4).rotated(Vector3.UP, yaw), yaw, 1.0, false)
		_builder.place(ArenaBuilder.KIT_FURNITURE, "chairDesk", centre + Vector3(0.0, 0.0, 1.33).rotated(Vector3.UP, yaw), yaw + PI, 1.0, false)
	for position in [Vector3(HALF_X - 0.7, 0, 9.5), Vector3(HALF_X - 0.7, 0, -9.5)]:
		_builder.place(ArenaBuilder.KIT_FURNITURE, "speaker", position, -PI * 0.5, 1.2, true, 0.1)
	for z in [-7.0, 7.0]:
		_builder.box(Vector3(0.2, 3.0, 3.6), Vector3(HALF_X - 0.1, 3.6, z), Color("101828"), 0.0, false, 0.0)
		_builder.box(Vector3(0.04, 2.6, 3.2), Vector3(HALF_X - 0.21, 3.6, z), secondary.darkened(0.35), 0.0, false, 1.1, false)

# --------------------------------------------------------------------------- #
# Ancient Ruins — an overgrown courtyard in a valley of ruined towers
# --------------------------------------------------------------------------- #

func _build_ruins() -> void:
	_tile_floor(ArenaBuilder.KIT_DUNGEON, "floor_tile_large", 0.07)
	_kit_wall_ring(["wall_cracked", "wall", "wall_broken", "wall_arched", "wall", "wall_cracked", "wall_window_closed"])
	for i in range(10):
		# Moss and soil patches break up the tile grid.
		var p := Vector3(_builder.rng.randf_range(-12.5, 12.5), 0.06, _builder.rng.randf_range(-10.5, 10.5))
		var moss := _builder.cylinder(_builder.rng.randf_range(0.8, 1.6), 0.02, p, Color("6f8a4a"), false, 0.0, 10)
		moss.scale = Vector3(1.0, 1.0, _builder.rng.randf_range(0.6, 1.0))
		moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Landmark: an ancient tree breaking through the north-west corner.
	var tree := _builder.place_transformed(ArenaBuilder.KIT_CASTLE, "tree_large", Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3.ONE * 1.45), Vector3(-11.6, 0, -9.6)), true)
	if tree:
		_builder.tint(tree, Color(0.5, 0.72, 0.4))
	_builder.cylinder(0.75, 3.0, Vector3(-14.91, 1.5, -12.8), Color("6b4a33"), true).visible = false
	# Landmark: broken statue plinth on the south side (low cover with a top).
	_builder.box(Vector3(2.2, 0.9, 2.2), Vector3(6.43, 0.45, 13.07), Color("bdb497"), 0.4, true)
	_builder.place(ArenaBuilder.KIT_DUNGEON, "pillar_decorated", Vector3(6.43, 0.9, 13.07), 0.4, 0.6, false)

	# Hazard shelves: they topple into the lanes the hazard script damages.
	_ruins_shelves.clear()
	var left := _builder.place(ArenaBuilder.KIT_PROPS, "Bookcase_2", ArenaHazards.RUINS_SHELF_POSITIONS[0], PI * 0.5, 1.15, true, 0.3, "RuinsShelfLeft")
	var right := _builder.place(ArenaBuilder.KIT_PROPS, "Bookcase_2", ArenaHazards.RUINS_SHELF_POSITIONS[1], -PI * 0.5, 1.15, true, 0.3, "RuinsShelfRight")
	for shelf in [left, right]:
		if shelf:
			_ruins_shelves.append(shelf)
	# Paint the fall lanes faintly so the danger zone is learnable.
	for i in range(2):
		var origin: Vector3 = ArenaHazards.RUINS_SHELF_POSITIONS[i]
		var direction := 1.0 if i == 0 else -1.0
		var lane := _builder.box(Vector3(6.6, 0.01, 2.6), origin + Vector3(direction * 3.8, 0.02, 0), Color(0.75, 0.45, 0.25, 0.28), 0.0, false, 0.0, false)
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Full cover: two weathered pillars. Low cover: rubble and a fallen column.
	for slot in [2, 6]:
		_builder.place(ArenaBuilder.KIT_DUNGEON, "pillar_decorated", _cover_slot(slot), _builder.rng.randf_range(0, TAU), 1.0, true, 0.35)
	_builder.place(ArenaBuilder.KIT_DUNGEON, "rubble_half", _cover_slot(3), 0.5, 0.75, true, 0.6)
	var fallen_at := _cover_slot(7)
	var column_basis := Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, PI * 0.5)
	for k in range(3):
		_builder.place_transformed(ArenaBuilder.KIT_DUNGEON, "column", Transform3D(column_basis.scaled(Vector3(1.8, 1.0, 1.87)), fallen_at + Vector3(-1.4 + k * 1.4, 0.5, 0).rotated(Vector3.UP, 0.9)), true)
	_builder.add_box_body(Vector3(4.2, 0.95, 0.95), fallen_at + Vector3(0, 0.47, 0), 0.9)
	_builder.place(ArenaBuilder.KIT_DUNGEON, "barrier_half", _cover_slot(0, 8.2 * LAYOUT_SX, 6.6 * LAYOUT_SZ), 0.3, 1.0, true, 0.2)

	# Perimeter dressing.
	for spec in [[Vector3(15.94, 0.0, 7.33), 0.4], [Vector3(-16.2, 0.0, 9.33), 1.2], [Vector3(13.5, 0.0, -14.13), 2.0]]:
		_builder.place(ArenaBuilder.KIT_CASTLE, "rocks_small", spec[0], spec[1], 0.5, true, 0.5)
	for position in [Vector3(-16.46, 0.0, -2.67), Vector3(16.59, 0.0, 0.67), Vector3(-3.86, 0.0, 14.93)]:
		_builder.place(ArenaBuilder.KIT_PROPS, "Vase_Rubble_Medium", position, _builder.rng.randf_range(0, TAU), 1.0, false)
	for spec in [[Vector3(-HALF_X, 2.4, 2.0), PI * 0.5], [Vector3(HALF_X, 2.4, -6.0), -PI * 0.5], [Vector3(-2.0, 2.4, -HALF_Z), 0.0]]:
		_wall_light(spec[0], spec[1], Color("ffb066"), 0.5)

	_ruins_backdrop()

func _ruins_backdrop() -> void:
	var grass := Color("8aa65a")
	var earth := Color("8c7a5a")
	# Trees just beyond the walls: their crowns over the wall line are what make
	# the courtyard feel embedded in a landscape.
	for point in _ring_points(18, 27.0, 34.0, 0.2):
		var s := _builder.rng.randf_range(1.2, 1.9)
		var backdrop_tree := _builder.place_transformed(ArenaBuilder.KIT_CASTLE, "tree_large" if _builder.rng.randf() < 0.6 else "tree_small", Transform3D(Basis(Vector3.UP, _builder.rng.randf() * TAU).scaled(Vector3.ONE * s), point))
		if backdrop_tree:
			_builder.tint(backdrop_tree, Color(0.5, 0.72, 0.4))
	# Rolling valley hills and distant mountains.
	for point in _ring_points(10, 44.0, 72.0, 0.5):
		_landform(BackdropForms.hill_profile(_builder.rng.randf_range(6.0, 14.0)), _builder.rng.randf_range(16.0, 26.0), point + Vector3(0, -1.0, 0), grass, earth, _builder.rng.randf() * TAU, 9)
	for point in _ring_points(8, 100.0, 140.0, 1.3):
		_landform(BackdropForms.mountain_profile(_builder.rng.randf_range(30.0, 48.0)), _builder.rng.randf_range(30.0, 44.0), point + Vector3(0, -2.0, 0), Color("dfe3ea"), Color("5f6678"), _builder.rng.randf() * TAU, 13, 0.2)
	# Ruined watchtowers on the hills.
	for point in _ring_points(5, 38.0, 54.0, 2.2):
		var base := point + Vector3(0, 0.0, 0)
		var levels := 2 + _builder.rng.randi() % 2
		for level in range(levels):
			var piece := "tower_square_base" if level == 0 else ("tower_square_mid" if level < levels - 1 else "tower_square_top")
			var tower := _builder.place_transformed(ArenaBuilder.KIT_CASTLE, piece, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.6), base + Vector3(0, level * 4.85, 0)))
			if tower:
				_builder.tint(tower, Color("d8cfb4"))
	# A big ground plane so nothing ever shows a void under the hills.
	var ground := PlaneMesh.new()
	ground.size = Vector2(520, 520)
	_builder.backdrop(ground, Transform3D(Basis.IDENTITY, Vector3(0, -0.4, 0)), _builder.toon_material(grass.darkened(0.15), 0.0, true, 1.0))
	for point in _ring_points(7, 60.0, 130.0, 0.0):
		_cloud(point + Vector3(0, _builder.rng.randf_range(28.0, 45.0), 0), _builder.rng.randf_range(7.0, 12.0), Color("fff6e8"))

# --------------------------------------------------------------------------- #
# Candy Island — a wafer-walled sweet garden in a candy landscape
# --------------------------------------------------------------------------- #

func _build_candy() -> void:
	var cream := Color("f3e2d2")
	var pink := Color("f59bbd")
	var pink_deep := Color("ec7aa6")
	for column in range(COLUMNS):
		for row in range(ROWS):
			var position := Vector3(-HALF_X + 4.0 * (0.5 + column), -0.04, -HALF_Z + 4.0 * (0.5 + row))
			_builder.box(Vector3(3.96, 0.1, 3.96), position, pink if (column + row) % 2 == 0 else cream, 0.0, false)
	# Wafer walls: candy-pink layered biscuit with a frosting cap. 2.6 m tall,
	# matching their collision exactly (see `wall_height` in the theme).
	var wall_h := float(_theme.get("wall_height", 2.6))
	for side in [[Vector3(0, 0, -HALF_Z - 0.3), Vector3(HALF_X * 2.0 + 1.2, 0, 0.6)], [Vector3(0, 0, HALF_Z + 0.3), Vector3(HALF_X * 2.0 + 1.2, 0, 0.6)], [Vector3(-HALF_X - 0.3, 0, 0), Vector3(0.6, 0, HALF_Z * 2.0 + 1.2)], [Vector3(HALF_X + 0.3, 0, 0), Vector3(0.6, 0, HALF_Z * 2.0 + 1.2)]]:
		var centre: Vector3 = side[0]
		var size: Vector3 = side[1]
		_builder.box(Vector3(size.x, wall_h, size.z), centre + Vector3(0, wall_h * 0.5, 0), Color("e8b07a"), 0.0, false)
		for layer in range(4):
			_builder.box(Vector3(size.x + 0.02, 0.1, size.z + 0.02), centre + Vector3(0, 0.45 + layer * 0.55, 0), pink_deep, 0.0, false)
		var cap := _builder.box(Vector3(size.x + 0.3, 0.32, size.z + 0.3), centre + Vector3(0, wall_h + 0.12, 0), cream, 0.0, false)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Candy-cane posts every 4 m give the perimeter its rhythm.
	var x := -HALF_X
	while x <= HALF_X + 0.01:
		for z in [-HALF_Z - 0.3, HALF_Z + 0.3]:
			_candy_cane(Vector3(x, 0, z), 3.6)
		x += 4.0
	var z_post := -HALF_Z + 4.0
	while z_post <= HALF_Z - 3.99:
		for xp in [-HALF_X - 0.3, HALF_X + 0.3]:
			_candy_cane(Vector3(xp, 0, z_post), 3.6)
		z_post += 4.0

	# Hazards double as landmarks: gumdrop bounce mounds (walk up, get launched)
	# and syrup pools that slow you down.
	var gumdrop_colours := [Color("4fc9b9"), Color("ffb03a"), Color("9a6ce8"), Color("62c95c")]
	for i in range(ArenaHazards.GUMDROP_CENTRES.size()):
		var centre: Vector3 = ArenaHazards.GUMDROP_CENTRES[i]
		_builder.frustum(ArenaHazards.GUMDROP_RADIUS * 0.55, ArenaHazards.GUMDROP_RADIUS + 0.2, ArenaHazards.GUMDROP_HEIGHT, centre + Vector3(0, ArenaHazards.GUMDROP_HEIGHT * 0.5, 0), gumdrop_colours[i % gumdrop_colours.size()], true, 28)
		_builder.sphere(ArenaHazards.GUMDROP_RADIUS * 0.6, centre + Vector3(0, ArenaHazards.GUMDROP_HEIGHT, 0), gumdrop_colours[i % gumdrop_colours.size()].lightened(0.15), Vector3(1.29, 0.25, 1.33))
		_builder.glow_ring(ArenaHazards.GUMDROP_RADIUS + 0.25, 0.14, centre + Vector3(0, 0.07, 0), Color("fffbf0"), 0.6)
	for centre in ArenaHazards.SYRUP_CENTRES:
		_builder.glow_decal(ArenaHazards.SYRUP_RADIUS, centre + Vector3(0, 0.03, 0), Color("c2407e"), 0.25)
		_builder.glow_ring(ArenaHazards.SYRUP_RADIUS, 0.12, centre + Vector3(0, 0.05, 0), Color("ffd0e4"), 0.5)

	# Cover: two chocolate bars (low) and two giant cupcakes (full).
	for spec in [[Vector3(13.37, 0.0, 5.33), 0.25], [Vector3(-13.37, 0.0, -5.33), 0.25]]:
		var centre: Vector3 = spec[0]
		_builder.box(Vector3(2.8, 1.0, 1.3), centre + Vector3(0, 0.5, 0), Color("5b3423"), spec[1], true)
		for k in range(4):
			_builder.box(Vector3(0.6, 0.1, 1.1), centre + Vector3(-1.05 + k * 0.7, 1.03, 0).rotated(Vector3.UP, spec[1]), Color("6e412c"), spec[1], false)
	for spec in [[Vector3(-12.09, 0.0, 5.6), Color("ff8fb8")], [Vector3(12.09, 0.0, -5.6), Color("9fd8ff")]]:
		var centre: Vector3 = spec[0]
		_builder.frustum(1.3, 1.0, 1.3, centre + Vector3(0, 0.65, 0), Color("e8b07a"), true, 14)
		_builder.sphere(1.45, centre + Vector3(0, 1.55, 0), spec[1], Vector3(1.29, 0.62, 1.33), true)
		_builder.sphere(0.32, centre + Vector3(0, 2.45, 0), Color("e8304a"))

	# Corner landmarks: giant lollipops (only the stick collides).
	for spec in [[Vector3(-16.2, 0.0, -14.13), Color("ff6f9c")], [Vector3(16.2, 0.0, 14.13), Color("7fd0ff")], [Vector3(16.2, 0.0, -14.13), Color("ffd86a")]]:
		_lollipop(spec[0], 5.2, 1.4, spec[1], true)
	for position in [Vector3(-16.2, 0.0, 14.13)]:
		_builder.sphere(1.2, position + Vector3(0, 0.9, 0), Color("62c95c"), Vector3(1.29, 0.8, 1.33), true)

	_candy_backdrop()

func _candy_cane(position: Vector3, height: float) -> void:
	var bands := 8
	for band in range(bands):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.26
		mesh.bottom_radius = 0.26
		mesh.height = height / bands
		mesh.radial_segments = 12
		_builder._add_mesh(mesh, position + Vector3(0, (band + 0.5) * height / bands, 0), _builder.toon_material(Color("fff6f8") if band % 2 == 0 else Color("e8304a"), 0.0, false, 0.45))
	_builder.sphere(0.36, position + Vector3(0, height + 0.15, 0), Color("fff6f8"))

func _lollipop(position: Vector3, height: float, radius: float, color: Color, collide: bool) -> void:
	_builder.cylinder(0.14 * radius, height, position + Vector3(0, height * 0.5, 0), Color("fbf3e6"), collide, 0.0, 10)
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = radius * 0.35
	disc.radial_segments = 28
	var head := _builder._add_mesh(disc, position + Vector3(0, height + radius * 0.85, 0), _builder.toon_material(color, 0.0, false, 0.35))
	head.rotation.x = PI * 0.5
	head.rotation.y = position.x * 0.1
	var swirl := TorusMesh.new()
	swirl.inner_radius = radius * 0.45
	swirl.outer_radius = radius * 0.62
	swirl.rings = 28
	swirl.ring_segments = 6
	var ring := _builder._add_mesh(swirl, Vector3.ZERO, _builder.toon_material(Color("fff6f8"), 0.0, false, 0.35))
	ring.reparent(head, false)
	ring.position = Vector3.ZERO
	ring.scale = Vector3(1.0, radius * 0.5, 1.0)

func _candy_backdrop() -> void:
	var caps := [Color("f6d2e0"), Color("a8e4d2"), Color("f6dc96"), Color("ecb6d4")]
	var sides := [Color("f08cb4"), Color("7fd6c4"), Color("f3b07a"), Color("c49bf0")]
	for point in _ring_points(11, 40.0, 64.0, 0.3):
		var i := _builder.rng.randi() % caps.size()
		_landform(BackdropForms.hill_profile(_builder.rng.randf_range(5.0, 11.0)), _builder.rng.randf_range(12.0, 20.0), point + Vector3(0, -0.6, 0), caps[i], sides[i], _builder.rng.randf() * TAU, 11, 0.1)
	for point in _ring_points(7, 80.0, 130.0, 1.0):
		var i := _builder.rng.randi() % caps.size()
		_landform(BackdropForms.mountain_profile(_builder.rng.randf_range(26.0, 40.0)), _builder.rng.randf_range(24.0, 36.0), point, caps[i], sides[i], 0.0, 12, 0.08)
	# Giant lollipop "trees" on the hills: the arena's skyline signature.
	var colours := [Color("ff6f9c"), Color("7fd0ff"), Color("ffd86a"), Color("a98bff"), Color("6fe0a0")]
	for point in _ring_points(9, 28.0, 40.0, 0.9):
		_lollipop(point, _builder.rng.randf_range(7.0, 12.0), _builder.rng.randf_range(2.2, 3.4), colours[_builder.rng.randi() % colours.size()], false)
	var ground := PlaneMesh.new()
	ground.size = Vector2(520, 520)
	_builder.backdrop(ground, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), _builder.toon_material(Color("b9f0e0"), 0.0, true, 1.0))
	for point in _ring_points(10, 50.0, 120.0, 0.0):
		_cloud(point + Vector3(0, _builder.rng.randf_range(22.0, 40.0), 0), _builder.rng.randf_range(6.0, 11.0), Color("ffe1ef"))

# --------------------------------------------------------------------------- #
# Volcano Core — a basalt fortress on a lava field ringed by volcanoes
# --------------------------------------------------------------------------- #

func _build_volcano() -> void:
	var accent := Color(_theme["accent"])
	_tile_floor(ArenaBuilder.KIT_DUNGEON, "floor_tile_large_rocks", 0.05)
	_kit_wall_ring(["wall_broken", "wall_cracked", "wall", "wall_cracked", "wall_broken", "wall"])

	# The hazard: a glowing safe ring that shrinks late in the round. Its
	# starting radius already clips the corners, so corners read as dangerous.
	_lava_ring = _builder.glow_ring(ArenaHazards.LAVA_START_RADIUS, 0.45, Vector3(0, 0.07, 0), accent, 2.2)
	# Glowing cracks in the corners (outside the starting safe radius).
	for corner in [Vector3(-1.29, 0.0, -1.33), Vector3(1.29, 0.0, -1.33), Vector3(-1.29, 0.0, 1.33), Vector3(1.29, 0.0, 1.33)]:
		var c := Vector3(corner.x * (HALF_X - 1.6), 0.05, corner.z * (HALF_Z - 1.4))
		var crack := _builder.glow_decal(1.7, c, Color("ff4d1a"), 2.0)
		crack.scale = Vector3(1.54, 1.0, 1.07)
		_builder.accent_light(c + Vector3(0, 0.8, 0), Color("ff6a2a"), 0.9, 5.0)

	# Full cover: clusters of hexagonal basalt columns with glowing veins.
	for slot in [0, 4]:
		var centre := _cover_slot(slot)
		for k in range(3):
			var offset := Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 0.75
			var height := 2.3 + k * 0.55
			var column := _builder.cylinder(0.62, height, centre + offset + Vector3(0, height * 0.5, 0), Color("6a5c60"), false, 0.0, 6)
			column.rotation.y = k * 0.4
			_builder.cylinder(0.5, 0.06, centre + offset + Vector3(0, height + 0.03, 0), accent, false, 2.4, 6)
		_builder.cylinder(1.35, 3.0, centre + Vector3(0, 1.5, 0), Color.BLACK, true).visible = false
		_builder.accent_light(centre + Vector3(0, 3.4, 0), accent, 0.8, 5.5)
	# Low cover: cooled lava boulders.
	for slot in [2, 6]:
		var rocks := _builder.place(ArenaBuilder.KIT_CASTLE, "rocks_small", _cover_slot(slot), _builder.rng.randf_range(0, TAU), 0.62, true, 0.5)
		if rocks:
			_builder.tint(rocks, Color("6a5a5a"))
	# Perimeter: ritual cauldrons and wall braziers.
	for position in [Vector3(-6.0, 0, -HALF_Z + 1.0), Vector3(6.5, 0, HALF_Z - 1.0)]:
		_builder.place(ArenaBuilder.KIT_PROPS, "Cauldron", position, 0.0, 1.3, true, 0.2)
		_builder.accent_light(position + Vector3(0, 1.3, 0), Color("ff7a3c"), 0.8, 4.5)
	for spec in [[Vector3(-HALF_X, 2.4, 5.0), PI * 0.5], [Vector3(HALF_X, 2.4, -5.0), -PI * 0.5]]:
		_wall_light(spec[0], spec[1], Color("ff8a4a"), 0.6)
	_embers()
	_volcano_backdrop()

func _embers() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Embers"
	particles.amount = 70
	particles.lifetime = 6.0
	particles.preprocess = 6.0
	particles.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 16, 40))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(HALF_X, 0.5, HALF_Z)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.2
	process.gravity = Vector3(0.26, 0.25, 0.0)
	particles.process_material = process
	# The compatibility renderer ignores particle scale ranges, so the size lives
	# on the quad itself (tiny) and the scale range is left at its default.
	process.scale_min = 1.0
	process.scale_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(1.0, 0.55, 0.2)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.15)
	material.emission_energy_multiplier = 3.0
	quad.material = material
	particles.draw_pass_1 = quad
	particles.position = Vector3(0, 0.4, 0)
	_builder.decor_root().add_child(particles)

func _volcano_backdrop() -> void:
	var basalt := Color("2e2628")
	var ash := Color("4a3f3e")
	var lava_material := _builder.toon_material(Color("ff5a1a"), 3.2, false)
	# Three hero volcanoes with glowing craters and lava streaks.
	for spec in [[Vector3(-48, -2, -70), 34.0, 42.0], [Vector3(62, -2, -40), 26.0, 30.0], [Vector3(20, -2, 85), 30.0, 36.0]]:
		var base: Vector3 = spec[0]
		var radius: float = spec[1]
		var height: float = spec[2]
		_landform(BackdropForms.volcano_profile(height), radius, base, ash, basalt, _builder.rng.randf() * TAU, 12, 0.1)
		var pool := CylinderMesh.new()
		pool.top_radius = radius * 0.2
		pool.bottom_radius = radius * 0.2
		pool.height = 0.5
		_builder.backdrop(pool, Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.94, 0)), lava_material)
		_builder.accent_light(base + Vector3(0, height + 4.0, 0), Color("ff5a1a"), 6.0, radius * 1.2)
		for k in range(3):
			var streak := BoxMesh.new()
			streak.size = Vector3(1.2, height * 0.6, 0.4)
			var angle := _builder.rng.randf() * TAU
			var dir := Vector3(cos(angle), 0, sin(angle))
			var t := Transform3D(Basis(Vector3.UP, -angle + PI * 0.5) * Basis(Vector3.RIGHT, -0.75), base + dir * radius * 0.42 + Vector3(0, height * 0.6, 0))
			_builder.backdrop(streak, t, lava_material)
	for point in _ring_points(12, 32.0, 58.0, 0.2):
		_landform(BackdropForms.column_profile(_builder.rng.randf_range(6.0, 16.0)), _builder.rng.randf_range(3.0, 7.0), point + Vector3(0, -1.0, 0), ash, basalt, _builder.rng.randf() * TAU, 6, 0.12)
	for point in _ring_points(9, 110.0, 150.0, 0.6):
		_landform(BackdropForms.mountain_profile(_builder.rng.randf_range(30.0, 45.0)), _builder.rng.randf_range(30.0, 40.0), point, ash.darkened(0.2), basalt.darkened(0.2), 0.0, 8)
	# Lava plain under everything: glows through the fog at the horizon.
	var plain := PlaneMesh.new()
	plain.size = Vector2(520, 520)
	_builder.backdrop(plain, Transform3D(Basis.IDENTITY, Vector3(0, -1.2, 0)), _builder.toon_material(Color("ff4a14"), 1.6, false))
	var crust := PlaneMesh.new()
	crust.size = Vector2(80, 80)
	_builder.backdrop(crust, Transform3D(Basis.IDENTITY, Vector3(0, -0.9, 0)), _builder.toon_material(basalt, 0.0, true, 1.0))

# --------------------------------------------------------------------------- #
# Hazard hooks
# --------------------------------------------------------------------------- #

func chalkboard() -> Node3D:
	return _chalkboard

func ruins_shelf(index: int) -> Node3D:
	if index < 0 or index >= _ruins_shelves.size():
		return null
	return _ruins_shelves[index]

func ruins_shelf_count() -> int:
	return _ruins_shelves.size()

func conveyor_arrows() -> Array[Node3D]:
	return _conveyor_arrows

func lava_ring() -> MeshInstance3D:
	return _lava_ring
