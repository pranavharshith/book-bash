class_name BackdropForms
extends RefCounted
## Faceted low-poly landforms built from a radial profile: floating islands,
## hills, volcanoes, rock columns. Each facet is flat-shaded and coloured by its
## slope (top facets get the "grass/cap" colour, steep facets the "rock" colour),
## which is what makes these read as stylised terrain instead of primitives.
##
## Deterministic for a given seed so every network peer builds the same world.

## `profile`: Array of Vector2(radius_factor, height) from top to bottom. A final
## radius factor of 0 closes to a point (island underside / mountain peak).
static func landform(radius: float, profile: Array, segments: int, jitter: float, seed: int,
		cap_color: Color, side_color: Color, cap_threshold: float = 0.55) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rings: Array = []
	var offsets: Array[float] = []
	for s in range(segments):
		offsets.append(rng.randf_range(-0.35, 0.35))
	for p in profile:
		var point: Vector2 = p
		var ring: Array[Vector3] = []
		for s in range(segments):
			var angle := TAU * (float(s) + offsets[s] * 0.5) / float(segments)
			var r := radius * point.x * (1.0 + rng.randf_range(-jitter, jitter))
			var y := point.y + rng.randf_range(-jitter, jitter) * radius * 0.16 * (1.0 if (point.x > 0.01 and point.x < 0.99) else 0.0)
			ring.append(Vector3(cos(angle) * r, y, sin(angle) * r))
		rings.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Top cap: fan from a slightly raised centre so the top is not dead flat.
	var top: Array[Vector3] = rings[0]
	var top_centre := Vector3(0.0, (profile[0] as Vector2).y + radius * 0.02, 0.0)
	for s in range(segments):
		_tri(st, top_centre, top[(s + 1) % segments], top[s], cap_color, side_color, cap_threshold, rng)
	for i in range(rings.size() - 1):
		var a: Array[Vector3] = rings[i]
		var b: Array[Vector3] = rings[i + 1]
		for s in range(segments):
			var n := (s + 1) % segments
			_tri(st, a[s], a[n], b[s], cap_color, side_color, cap_threshold, rng)
			_tri(st, a[n], b[n], b[s], cap_color, side_color, cap_threshold, rng)
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, cap: Color, side: Color, threshold: float, rng: RandomNumberGenerator) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length() < 0.00001:
		return
	normal = normal.normalized()
	var color := cap if normal.y > threshold else side
	color = color.darkened(rng.randf_range(0.0, 0.12)) if normal.y > -0.2 else side.darkened(0.25 + rng.randf_range(0.0, 0.1))
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(c)

static func vertex_color_material(emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic_specular = 0.1
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = Color(1, 1, 1)
		material.emission_energy_multiplier = emission
	return material

# --- Preset profiles -------------------------------------------------------- #

## Grassy top, rocky tapered underside.
static func island_profile(top_height: float, depth: float) -> Array:
	return [Vector2(0.9, top_height), Vector2(1.0, top_height * 0.4), Vector2(0.85, -depth * 0.2),
		Vector2(0.55, -depth * 0.55), Vector2(0.22, -depth * 0.85), Vector2(0.0, -depth)]

static func hill_profile(height: float) -> Array:
	return [Vector2(0.25, height), Vector2(0.55, height * 0.75), Vector2(0.85, height * 0.32), Vector2(1.0, 0.0), Vector2(1.02, -2.0)]

## Ridged silhouette (shoulders and a steep summit) rather than a straight cone.
static func mountain_profile(height: float) -> Array:
	return [Vector2(0.05, height), Vector2(0.14, height * 0.9), Vector2(0.26, height * 0.72), Vector2(0.34, height * 0.6),
		Vector2(0.5, height * 0.4), Vector2(0.66, height * 0.24), Vector2(0.84, height * 0.1), Vector2(1.0, 0.0), Vector2(1.02, -3.0)]

## Open crater rim at the top for a volcano; the lava pool sits inside.
static func volcano_profile(height: float) -> Array:
	return [Vector2(0.16, height * 0.93), Vector2(0.24, height), Vector2(0.45, height * 0.66), Vector2(0.75, height * 0.3), Vector2(1.0, 0.0), Vector2(1.02, -3.0)]

static func column_profile(height: float) -> Array:
	return [Vector2(0.7, height), Vector2(0.95, height * 0.8), Vector2(1.0, height * 0.35), Vector2(1.12, 0.0), Vector2(1.12, -0.3)]
