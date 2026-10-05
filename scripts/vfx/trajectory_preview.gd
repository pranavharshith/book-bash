class_name TrajectoryPreview
extends Node3D
## Dotted throw arc plus a landing marker, drawn from the exact points produced by
## `BookProjectile.simulate()` (the same model the thrown book flies on).

const DOT_EVERY := 3          # one dot per N simulation steps (~20 dots/second of flight)
const MAX_DOTS := 64
const DOT_RADIUS := 0.055

var _dots: MultiMeshInstance3D
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _dot_material: StandardMaterial3D

const COLOR_PATH := Color(1.0, 0.97, 0.88, 0.9)
const COLOR_LAND := Color(1.0, 0.84, 0.3, 0.95)
const COLOR_FIGHTER := Color(1.0, 0.32, 0.25, 0.95)

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_dot_material = StandardMaterial3D.new()
	_dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dot_material.vertex_color_use_as_albedo = true
	_dot_material.albedo_color = Color.WHITE
	sphere.material = _dot_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	multimesh.instance_count = MAX_DOTS
	multimesh.visible_instance_count = 0
	_dots = MultiMeshInstance3D.new()
	_dots.name = "Dots"
	_dots.multimesh = multimesh
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.46
	ring.rings = 28
	ring.ring_segments = 6
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.albedo_color = COLOR_LAND
	_marker_material.no_depth_test = true
	_marker_material.render_priority = 1
	ring.material = _marker_material
	_marker = MeshInstance3D.new()
	_marker.name = "LandingMarker"
	_marker.mesh = ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	hide_preview()

func hide_preview() -> void:
	if _dots:
		_dots.multimesh.visible_instance_count = 0
	if _marker:
		_marker.visible = false

func show_path(points: PackedVector3Array, land_position: Vector3, land_normal: Vector3, on_fighter: bool, did_hit: bool) -> void:
	if _dots == null:
		return
	global_transform = Transform3D.IDENTITY
	var multimesh := _dots.multimesh
	var count := 0
	# Skip the first few steps: dots inside the hand read as clutter.
	var index := DOT_EVERY * 2
	while index < points.size() and count < MAX_DOTS:
		var fade := 1.0 - float(count) / float(MAX_DOTS)
		var color := COLOR_PATH
		color.a *= lerpf(0.35, 1.0, fade)
		multimesh.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lerpf(0.7, 1.0, fade)), points[index]))
		multimesh.set_instance_color(count, color)
		count += 1
		index += DOT_EVERY
	multimesh.visible_instance_count = count

	_marker.visible = did_hit
	if did_hit:
		var normal := land_normal.normalized() if land_normal.length() > 0.01 else Vector3.UP
		var basis := _basis_from_up(normal)
		_marker.global_transform = Transform3D(basis.scaled(Vector3(1.0, 0.08, 1.0)), land_position + normal * 0.04)
		_marker_material.albedo_color = COLOR_FIGHTER if on_fighter else COLOR_LAND

static func _basis_from_up(up: Vector3) -> Basis:
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := reference.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)
