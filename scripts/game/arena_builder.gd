class_name ArenaBuilder
extends RefCounted
## Shared helpers for assembling an arena out of the imported model kits and a
## small set of primitives.
##
## Collision is split into three deliberate layers:
##   1  world            visible architecture + cover. Fighters, books, and the
##                        camera all collide with it. Simple boxes, never meshes.
##   5  camera_blockers  camera-only volumes (none needed by most arenas).
##   6  fighter_bounds   invisible containment that only fighters touch, so a
##                        lobbed book sails over a wall instead of stopping in
##                        mid-air against an invisible plane.
## Decorative pieces get no collision at all.
##
## The kits were authored at different scales (Kenney furniture ~1:2.2, Kenney
## castle 1:3, KayKit and the Fantasy props 1:1), so every placement goes through
## `place()`, which applies the kit's correction for you.

const KIT_DUNGEON := "dungeon"
const KIT_FURNITURE := "furniture"
const KIT_CASTLE := "castle"
const KIT_PROPS := "props"

const LAYER_WORLD := 1
const LAYER_CAMERA := 16
const LAYER_FIGHTER_BOUNDS := 32

const KIT_ROOTS := {
	KIT_DUNGEON: "res://assets/models/kits/dungeon/",
	KIT_FURNITURE: "res://assets/models/kits/furniture/",
	KIT_CASTLE: "res://assets/models/kits/castle/",
	KIT_PROPS: "res://assets/models/kits/props/",
}

const KIT_EXTENSIONS := {
	KIT_DUNGEON: ".gltf",
	KIT_FURNITURE: ".glb",
	KIT_CASTLE: ".glb",
	KIT_PROPS: ".gltf",
}

## Authoring scale correction per kit, measured with tools/measure_kits.gd.
const KIT_SCALES := {
	KIT_DUNGEON: 1.0,
	KIT_FURNITURE: 2.2,
	KIT_CASTLE: 3.0,
	KIT_PROPS: 1.0,
}

## Kenney's furniture models are anchored at a footprint corner rather than the
## centre, so placements in that kit get re-centred automatically.
const KIT_ORIGIN_CENTERED := {
	KIT_DUNGEON: true,
	KIT_FURNITURE: false,
	KIT_CASTLE: true,
	KIT_PROPS: true,
}

## Ground decals have to clear the kit floor tiles, whose top surface sits at
## y = 0.05. Anything painted lower z-fights.
const DECAL_HEIGHT := 0.08

var parent: Node3D
var rng := RandomNumberGenerator.new()
## When true, `place()` gives every floor-standing prop a collider. Fighters
## must never walk through furniture, walls, or scenery.
var solid_by_default := true

var _scene_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _tint_cache: Dictionary = {}
var _static_root: Node3D
var _decor_root: Node3D
var _accent_light_count := 0
static var _grain_texture: NoiseTexture2D
## Every kit model any builder asked for. tools/gen_preload_manifest.gd dumps this
## per arena so the loading screen can fetch them on background threads.
static var recorded_paths: Dictionary = {}

func _init(target: Node3D, deterministic_seed: int) -> void:
	parent = target
	rng.seed = deterministic_seed
	_static_root = Node3D.new()
	_static_root.name = "Collision"
	parent.add_child(_static_root)
	_decor_root = Node3D.new()
	_decor_root.name = "Decor"
	parent.add_child(_decor_root)

# --------------------------------------------------------------------------- #
# Materials
# --------------------------------------------------------------------------- #

## Low-contrast seamless grain, applied triplanar so any primitive of any size
## gets surface texture instead of reading as a flat untextured block.
static func grain_texture() -> NoiseTexture2D:
	if _grain_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.035
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.8, 0.8, 0.8))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.seamless = true
		texture.noise = noise
		texture.color_ramp = ramp
		_grain_texture = texture
	return _grain_texture

## Shared material for primitives. Name kept from the old cel-shader version so
## callers stay compatible; it is now a regular StandardMaterial3D so primitives
## light identically to the textured kit pieces around them.
func toon_material(color: Color, emission: float = 0.0, grain: bool = true, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%f|%s|%f" % [color.to_html(), emission, grain, roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 0.25
	if grain and emission <= 0.0:
		material.albedo_texture = grain_texture()
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE * 0.35
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_cache[key] = material
	return material

func unshaded_material(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var key := "unshaded|%s|%f" % [color.to_html(), energy]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_fog = false
	_material_cache[key] = material
	return material

# --------------------------------------------------------------------------- #
# Primitives
# --------------------------------------------------------------------------- #

func _add_mesh(mesh: Mesh, position: Vector3, material: Material, rotation_y: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation.y = rotation_y
	_decor_root.add_child(instance)
	return instance

func box(size: Vector3, position: Vector3, color: Color, rotation_y: float = 0.0, collidable: bool = true, emission: float = 0.0, grain: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _add_mesh(mesh, position, toon_material(color, emission, grain), rotation_y)
	if collidable:
		add_box_body(size, position, rotation_y)
	return instance

func cylinder(radius: float, height: float, position: Vector3, color: Color, collidable: bool = true, emission: float = 0.0, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var instance := _add_mesh(mesh, position, toon_material(color, emission))
	if collidable:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_add_shape_body(shape, Transform3D(Basis.IDENTITY, position))
	return instance

## Truncated cone. With a shallow side slope this is a walkable dais or mound:
## the convex collider lets fighters run straight up the side instead of being
## blocked by a step the controller cannot climb.
func frustum(top_radius: float, bottom_radius: float, height: float, position: Vector3, color: Color, collidable: bool = true, segments: int = 32, emission: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var instance := _add_mesh(mesh, position, toon_material(color, emission))
	if collidable:
		_add_shape_body(mesh.create_convex_shape(true, false), Transform3D(Basis.IDENTITY, position))
	return instance

func sphere(radius: float, position: Vector3, color: Color, squash: Vector3 = Vector3.ONE, collidable: bool = false, emission: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var instance := _add_mesh(mesh, position, toon_material(color, emission))
	instance.scale = squash
	if collidable:
		var shape := SphereShape3D.new()
		shape.radius = radius * minf(squash.x, squash.z)
		_add_shape_body(shape, Transform3D(Basis.IDENTITY, position))
	return instance

## Decorative far-field geometry: no collision, no shadows (they would only cost
## shadow-map resolution for things the fight never touches).
func backdrop(mesh: Mesh, transform: Transform3D, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transform = transform
	_decor_root.add_child(instance)
	return instance

func add_box_body(size: Vector3, position: Vector3, rotation_y: float = 0.0, layer: int = LAYER_WORLD) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _add_shape_body(shape, Transform3D(Basis(Vector3.UP, rotation_y), position), layer)

## Kept for older callers.
func _add_box_body(size: Vector3, position: Vector3, rotation_y: float) -> StaticBody3D:
	return add_box_body(size, position, rotation_y)

func _add_shape_body(shape: Shape3D, transform: Transform3D, layer: int = LAYER_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.transform = transform
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_static_root.add_child(body)
	return body

# --------------------------------------------------------------------------- #
# Kit placement
# --------------------------------------------------------------------------- #

func _kit_scene(kit: String, model_name: String) -> PackedScene:
	var key := kit + "/" + model_name
	if _scene_cache.has(key):
		return _scene_cache[key]
	var path := String(KIT_ROOTS.get(kit, "")) + model_name + String(KIT_EXTENSIONS.get(kit, ".glb"))
	recorded_paths[path] = true
	if not ResourceLoader.exists(path):
		push_warning("ArenaBuilder: missing kit model %s" % path)
		_scene_cache[key] = null
		return null
	var scene: PackedScene = load(path)
	_scene_cache[key] = scene
	return scene

## Places one kit model. `collide` derives a box collider from the model bounds;
## `collision_inset` shrinks it so a decorative silhouette (a chair, a banner)
## does not feel like a bigger obstacle than it looks.
func place(
	kit: String, model_name: String, position: Vector3, rotation_y: float = 0.0,
	scale_multiplier: float = 1.0, collide: bool = false,
	collision_inset: float = 0.1, node_name: String = ""
) -> Node3D:
	var scene := _kit_scene(kit, model_name)
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return null
	if not node_name.is_empty():
		instance.name = node_name
	var final_scale := float(KIT_SCALES.get(kit, 1.0)) * scale_multiplier
	instance.scale = Vector3.ONE * final_scale
	instance.position = position
	instance.rotation.y = rotation_y
	_decor_root.add_child(instance)

	var bounds := _local_aabb(instance)
	var centre := bounds.get_center() * final_scale
	if not bool(KIT_ORIGIN_CENTERED.get(kit, true)):
		var correction := Vector3(-centre.x, 0.0, -centre.z).rotated(Vector3.UP, rotation_y)
		instance.position += correction
		centre.x = 0.0
		centre.z = 0.0
	# Anything that stands on the floor is solid. Only flat things (tiles, rugs,
	# decals) and items resting on top of other props (books on a table) are not.
	if not collide and solid_by_default and bounds.size.y * final_scale > 0.3 and position.y < 0.6 and bounds.position.y * final_scale < 0.5 and maxf(bounds.size.x, bounds.size.z) * final_scale < 9.0:
		collide = true
		collision_inset = maxf(collision_inset, 0.12)
	if collide and bounds.size.length() > 0.001:
		var size := bounds.size * final_scale
		size.x = maxf(size.x - collision_inset, 0.12)
		size.z = maxf(size.z - collision_inset, 0.12)
		add_box_body(size, instance.position + centre.rotated(Vector3.UP, rotation_y), rotation_y)
	return instance

## Places a kit model with a full transform (tilted, non-uniform). Decorative only.
func place_transformed(kit: String, model_name: String, transform: Transform3D, shadows: bool = false) -> Node3D:
	var scene := _kit_scene(kit, model_name)
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	_decor_root.add_child(instance)
	var kit_scale := float(KIT_SCALES.get(kit, 1.0))
	instance.transform = Transform3D(transform.basis.scaled(Vector3.ONE * kit_scale), transform.origin)
	if not shadows:
		set_shadows(instance, false)
	return instance

## Repeats a model along a straight run, e.g. a wall or a row of desks.
func place_row(
	kit: String, model_name: String, from: Vector3, to: Vector3, count: int,
	rotation_y: float = 0.0, scale_multiplier: float = 1.0, collide: bool = false
) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	if count <= 0:
		return placed
	for i in range(count):
		var t := 0.0 if count == 1 else float(i) / float(count - 1)
		var node := place(kit, model_name, from.lerp(to, t), rotation_y, scale_multiplier, collide)
		if node:
			placed.append(node)
	return placed

func _local_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var initialised := false
	for mesh_instance in _collect_meshes(node):
		var local := node.global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_bounds := local * mesh_instance.get_aabb()
		if not initialised:
			result = mesh_bounds
			initialised = true
		else:
			result = result.merge(mesh_bounds)
	return result

func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_collect_meshes(child))
	return found

func set_shadows(node: Node, enabled: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		set_shadows(child, enabled)

# --------------------------------------------------------------------------- #
# Arena shell
# --------------------------------------------------------------------------- #

## Solid floor plate (collision + a base colour under the tiles).
func floor_plate(half_x: float, half_z: float, color: Color) -> void:
	box(Vector3(half_x * 2.0 + 2.0, 0.6, half_z * 2.0 + 2.0), Vector3(0, -0.3, 0), color)

## One collision box per side, matching the visible wall run exactly. Simple
## boxes keep fighters from snagging on the kit's sculpted wall detail.
func wall_colliders(half_x: float, half_z: float, height: float, thickness: float = 1.0) -> void:
	var long_x := half_x * 2.0 + thickness * 2.0
	var long_z := half_z * 2.0 + thickness * 2.0
	add_box_body(Vector3(long_x, height, thickness), Vector3(0, height * 0.5, -half_z - thickness * 0.5))
	add_box_body(Vector3(long_x, height, thickness), Vector3(0, height * 0.5, half_z + thickness * 0.5))
	add_box_body(Vector3(thickness, height, long_z), Vector3(-half_x - thickness * 0.5, height * 0.5, 0))
	add_box_body(Vector3(thickness, height, long_z), Vector3(half_x + thickness * 0.5, height * 0.5, 0))

## Fighter-only containment above the visible walls plus a lid, so no knockback,
## bounce pad, or jump can ever put a fighter outside. Books and the camera
## ignore this layer.
func boundary_walls(half_x: float, half_z: float, height: float = 10.0) -> void:
	var thickness := 1.0
	var long_x := half_x * 2.0 + thickness * 2.0
	var long_z := half_z * 2.0 + thickness * 2.0
	var layer := LAYER_FIGHTER_BOUNDS
	add_box_body(Vector3(long_x, height, thickness), Vector3(0, height * 0.5, -half_z - thickness * 0.5), 0.0, layer)
	add_box_body(Vector3(long_x, height, thickness), Vector3(0, height * 0.5, half_z + thickness * 0.5), 0.0, layer)
	add_box_body(Vector3(thickness, height, long_z), Vector3(-half_x - thickness * 0.5, height * 0.5, 0), 0.0, layer)
	add_box_body(Vector3(thickness, height, long_z), Vector3(half_x + thickness * 0.5, height * 0.5, 0), 0.0, layer)
	add_box_body(Vector3(long_x, thickness, long_z), Vector3(0, height + thickness * 0.5, 0), 0.0, layer)

func environment(theme: Dictionary) -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = theme.get("sky_top", Color("4a5f8f"))
	sky_material.sky_horizon_color = theme.get("sky_horizon", Color("d8c9a8"))
	sky_material.ground_horizon_color = theme.get("ground_horizon", theme.get("sky_horizon", Color("d8c9a8")))
	sky_material.ground_bottom_color = theme.get("ground_bottom", Color(theme.get("sky_top", Color("4a5f8f"))).darkened(0.4))
	sky_material.sky_curve = 0.12
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 20.0
	sky_material.sky_energy_multiplier = float(theme.get("sky_energy", 1.0))
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Mostly-explicit ambient: a pure sky-derived ambient tinted everything by
	# the sky hue. A partial sky contribution keeps a little directional variety.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.get("ambient", Color("8f9ab5"))
	env.ambient_light_energy = float(theme.get("ambient_energy", 0.5))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Distance fog only past the arena: it separates the background silhouettes
	# from the play space without hazing the fight itself.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = theme.get("fog", Color("9aa6c4"))
	env.fog_light_energy = 1.0
	env.fog_depth_begin = float(theme.get("fog_begin", 30.0))
	env.fog_depth_end = float(theme.get("fog_end", 160.0))
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = float(theme.get("fog_sky_affect", 0.25))
	var mobile := Perf.is_mobile()
	if mobile:
		# Tonemap, glow, and colour adjustment each add a full-screen pass. On a
		# phone GPU those passes cost more than the whole arena, so they are off.
		# Linear tonemapping with a slight exposure trim keeps the brightness close.
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = float(theme.get("exposure", 0.95)) * 0.92
		env.glow_enabled = false
		env.adjustment_enabled = false
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 1.6
		env.tonemap_exposure = float(theme.get("exposure", 0.95))
		# Glow only catches genuinely emissive things (lava, screens, magic) because
		# the threshold sits above normal lit albedo.
		env.glow_enabled = true
		env.glow_intensity = float(theme.get("glow", 0.35))
		env.glow_strength = 0.9
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.1
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.adjustment_enabled = true
		env.adjustment_contrast = float(theme.get("contrast", 1.06))
		env.adjustment_saturation = float(theme.get("saturation", 1.08))

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = env
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = theme.get("sun_rotation", Vector3(-50, -35, 0))
	sun.light_color = theme.get("sun", Color("ffe9c4"))
	sun.light_energy = float(theme.get("sun_energy", 1.1))
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	if mobile:
		# One shadow map, short range: only fighters cast shadows on phones.
		sun.shadow_blur = 1.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 34.0
	else:
		sun.shadow_blur = 1.2
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.25
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_max_distance = 42.0
	sun.directional_shadow_fade_start = 0.85
	parent.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_color = theme.get("secondary", Color("6f86c6"))
	fill.light_energy = float(theme.get("fill_energy", 0.25))
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	parent.add_child(fill)
	return world_environment

## Local accent light. Short range and no shadows: a handful of wide, bright
## omni lights blanket an arena and wash its albedo out.
func accent_light(position: Vector3, color: Color, energy: float = 0.7, range_value: float = 5.0) -> OmniLight3D:
	if Perf.is_mobile():
		if _accent_light_count >= Perf.MOBILE_MAX_ACCENT_LIGHTS:
			return null
		_accent_light_count += 1
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.4
	light.light_specular = 0.15
	light.shadow_enabled = false
	_decor_root.add_child(light)
	return light

## Recolours a kit prop while *keeping its texture*: each surface material is
## duplicated with its albedo multiplied by `color`. The old version replaced the
## material with a flat colour, which erased all of KayKit's texture detail.
## Duplicates are cached per (source material, tint), so tinting fifty walls the
## same colour still shares one material.
func tint(node: Node, color: Color, _roughness: float = 0.8) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var source := mesh_instance.get_active_material(surface)
				mesh_instance.set_surface_override_material(surface, _tinted(source, color))
	for child in node.get_children():
		tint(child, color, _roughness)

func _tinted(source: Material, color: Color) -> Material:
	if source == null:
		return toon_material(color)
	var key := "%d|%s" % [source.get_instance_id(), color.to_html()]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var result: Material = source
	if source is BaseMaterial3D:
		var copy := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
		copy.albedo_color = copy.albedo_color * color
		result = copy
	_tint_cache[key] = result
	return result

func glow_decal(radius: float, position: Vector3, color: Color, energy: float = 1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 32
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.62)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.3
	var instance := _add_mesh(mesh, position, material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

## Flat emissive annulus used for arena markings.
func glow_ring(radius: float, thickness: float, position: Vector3, color: Color, energy: float = 0.6) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.05)
	mesh.outer_radius = radius
	mesh.rings = 64
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.8)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := _add_mesh(mesh, position, material)
	instance.scale = Vector3(1.0, 0.06, 1.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func decor_root() -> Node3D:
	return _decor_root

## Phones skip the shadow pass for all static scenery (hundreds of draw calls).
func strip_static_shadows() -> void:
	set_shadows(_decor_root, false)
