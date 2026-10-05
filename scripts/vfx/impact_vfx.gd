class_name ImpactVfx
extends RefCounted
## Code-generated combat feedback: impact bursts, projectile trails, floating
## damage numbers, and shield breaks. Everything is built at runtime so a new
## cosmetic trail is a colour row in the catalogue rather than a new scene.

static func spawn(parent: Node, position: Vector3, color: Color = Color("ffd45c"), scale: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	# CPU particles: on phones GPU particles (transform feedback) cost more than
	# these few dozen quads, and they avoid a per-hit shader/material build.
	var particles := CPUParticles3D.new()
	particles.amount = maxi(int(12 * scale), 4) if Perf.is_mobile() else int(20 * scale)
	particles.lifetime = 0.42
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.18 * scale
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 3.0 * scale
	particles.initial_velocity_max = 6.5 * scale
	particles.gravity = Vector3(0, -9, 0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.mesh = _quad(color, 2.4, Vector2(0.07, 0.07) * scale)
	parent.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	_auto_free(particles, 0.9)

## A short-lived expanding ring reads much better than more sparks for "your
## shield ate that hit", because it has to be distinguishable at a glance.
static func spawn_shield_break(parent: Node, position: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var ring := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.95, 0.68, 0.55)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.95, 0.68)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	parent.add_child(ring)
	ring.global_position = position
	ring.scale = Vector3.ONE * 0.4
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 1.6, 0.3)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)

static func spawn_damage_number(parent: Node, position: Vector3, amount: float, color: Color = Color(1, 0.92, 0.45)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = "-%d" % int(round(amount))
	label.font_size = 64
	label.pixel_size = 0.0038
	label.outline_size = 18
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.fixed_size = false
	parent.add_child(label)
	label.global_position = position
	var drift := Vector3(randf_range(-0.35, 0.35), 1.15, randf_range(-0.2, 0.2))
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", position + drift, 0.72)
	tween.tween_property(label, "modulate:a", 0.0, 0.72).set_delay(0.24)
	tween.chain().tween_callback(label.queue_free)

static func add_trail(projectile: Node3D, trail_id: String = "trail_paper") -> void:
	if projectile == null:
		return
	var color := GameState.trail_color(trail_id)
	var energetic := trail_id != "trail_paper"
	var particles := CPUParticles3D.new()
	particles.name = "BookTrail"
	var mobile := Perf.is_mobile()
	particles.amount = (10 if energetic else 7) if mobile else (30 if energetic else 22)
	particles.lifetime = 0.36 if energetic else 0.3
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.08
	particles.initial_velocity_min = 0.05
	particles.initial_velocity_max = 0.45 if energetic else 0.25
	particles.gravity = Vector3(0, 0.4, 0) if trail_id == "trail_fire" else Vector3(0, -0.7, 0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.mesh = _quad(color, 2.2 if energetic else 1.4, Vector2(0.05, 0.04) if energetic else Vector2(0.045, 0.03))
	projectile.add_child(particles)
	particles.emitting = true

static func spawn_pickup_flash(parent: Node, position: Vector3, color: Color) -> void:
	spawn(parent, position, color, 0.7)

static var _quad_cache: Dictionary = {}

## Quads and their materials are shared between every burst of the same look.
static func _quad(color: Color, emission_energy: float, size: Vector2) -> QuadMesh:
	var key := "%s|%f|%f|%f" % [color.to_html(), emission_energy, size.x, size.y]
	if _quad_cache.has(key):
		return _quad_cache[key]
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = _particle_material(color, emission_energy)
	_quad_cache[key] = quad
	return quad

static func _particle_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material

static func _auto_free(node: Node, seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	timer.autostart = true
	timer.timeout.connect(node.queue_free)
	node.add_child(timer)
