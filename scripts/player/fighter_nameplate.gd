class_name FighterNameplate
extends Node3D
## Floating name + health bar above a fighter.
##
## Six fighters in a wide arena are unreadable without world-space feedback, and
## HUD chips alone do not tell you which body on screen is which. Built in code
## so every fighter, bot or human, gets one without scene duplication.

const BAR_WIDTH := 1.05
const BAR_HEIGHT := 0.11

var _name_label: Label3D
var _bar_background: MeshInstance3D
var _bar_fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _last_ratio := -1.0
var _last_visible := true

func setup(fighter_name: String, color: Color) -> void:
	_name_label = Label3D.new()
	_name_label.text = fighter_name
	_name_label.font_size = 48
	_name_label.pixel_size = 0.0042
	_name_label.outline_size = 16
	_name_label.modulate = Color(1, 1, 1, 0.96)
	_name_label.outline_modulate = Color(0, 0, 0, 0.85)
	# The chase camera keeps a fixed yaw and the nameplate node never rotates with
	# the model, so it already faces the camera. Billboarding a quad that carries a
	# `center_offset` pivot instead made the health bars swing off-centre.
	_name_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_name_label.no_depth_test = false
	_name_label.shaded = false
	_name_label.double_sided = true
	_name_label.position = Vector3(0, 0.3, 0)
	add_child(_name_label)

	_bar_background = _make_bar(Color(0.05, 0.05, 0.08, 0.78), 0.0)
	_bar_background.scale = Vector3(1.06, 1.34, 1.0)
	add_child(_bar_background)

	_fill_material = _bar_material(color, 1.25)
	_bar_fill = _make_bar(color, 1.25)
	_bar_fill.material_override = _fill_material
	# Anchor the quad's left edge at the node origin so a horizontal scale reads
	# as a health bar draining toward the left instead of shrinking centred.
	add_child(_bar_fill)
	_bar_fill.position = Vector3(-BAR_WIDTH * 0.5, 0.0, 0.002)

func _make_bar(color: Color, emission: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	quad.center_offset = Vector3(BAR_WIDTH * 0.5, 0.0, 0.0)
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = _bar_material(color, emission)
	instance.position = Vector3(-BAR_WIDTH * 0.5, 0.0, 0.0)
	return instance

func _bar_material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func set_local_player(is_local: bool) -> void:
	if _name_label == null:
		return
	if is_local:
		# Your own plate would float straight across the over-the-shoulder view;
		# the HUD chip already shows your health.
		_is_local = true
		visible = false

var _is_local := false

## Yaw-only facing toward the active camera so plates read from any orbit angle
## without tilting (full billboarding skewed the left-anchored health bar).
func _process(_delta: float) -> void:
	if not visible:
		return
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera == null:
		return
	var to_camera := camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length() < 0.01:
		return
	global_basis = Basis(Vector3.UP, atan2(to_camera.x, to_camera.z))

func update_state(health_ratio: float, _stocks: int, is_active: bool) -> void:
	if _bar_fill == null:
		return
	if is_active != _last_visible:
		_last_visible = is_active
		visible = is_active and not _is_local
	if not is_active:
		return
	health_ratio = clampf(health_ratio, 0.0, 1.0)
	if is_equal_approx(health_ratio, _last_ratio):
		return
	_last_ratio = health_ratio
	_bar_fill.scale = Vector3(maxf(health_ratio, 0.001), 1.0, 1.0)
	if _fill_material:
		var low := Color(0.95, 0.25, 0.2)
		var high := Color(0.35, 0.9, 0.45)
		_fill_material.albedo_color = low.lerp(high, health_ratio)
		_fill_material.emission = _fill_material.albedo_color
