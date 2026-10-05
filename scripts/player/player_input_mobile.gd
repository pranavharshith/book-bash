class_name PlayerInputMobile
extends Node
## Unifies keyboard + mouse, gamepad, and touch into the `Fighter` control surface
## for a third-person camera.
##
## - Movement is camera-relative using the camera *yaw only*, so looking up or
##   down never changes which way "forward" walks.
## - The crosshair is the aim: every frame a ray from the screen centre finds the
##   intended impact point, optional aim assist nudges it onto a nearby opponent,
##   and the fighter solves its throw to land exactly there. The trajectory
##   preview uses the same solve, so what you see is what you throw.
## - Mouse look uses a captured cursor. Touch look only reads real touch events,
##   so desktop mouse clicks can never be swallowed by the touch look pad.

@export var fighter_path: NodePath

const MOUSE_SENSITIVITY := 0.0024       # rad per pixel
const TOUCH_SENSITIVITY := 0.0062       # rad per pixel at 720p
const PAD_YAW_SPEED := 3.4              # rad/s at full deflection
const PAD_PITCH_SPEED := 2.3
const PAD_RESPONSE_EXPONENT := 1.7      # fine control near centre, fast at the edge
const AIM_MAX_DISTANCE := 60.0
## Aim assist cone half-angles. Wider on touch/gamepad, where precise aim is hard.
const ASSIST_ANGLE_MOUSE := deg_to_rad(3.0)
const ASSIST_ANGLE_PAD := deg_to_rad(6.5)
const ASSIST_ANGLE_TOUCH := deg_to_rad(8.0)
const ASSIST_MAX_RANGE := 26.0

var _fighter: Fighter
var _camera_rig: MatchCamera
var _camera: Camera3D
var _hud: MatchHud
var _preview: TrajectoryPreview
var _stick_axis := Vector2.ZERO
var _touch_primary := false
var _using_pad := false
var _hud_jump_held := false
var _assist_target: Fighter

func _ready() -> void:
	_fighter = get_node_or_null(fighter_path) as Fighter
	# Lobby > Controls decides this; phones default to the on-screen joystick.
	_touch_primary = GameState.control_scheme() == "touch"
	if not _touch_primary:
		capture_mouse()
	_preview = TrajectoryPreview.new()
	_preview.name = "TrajectoryPreview"
	# Top-level so it draws in world space regardless of the fighter transform.
	_preview.top_level = true
	add_child(_preview)

func _exit_tree() -> void:
	# Leaving a match must hand the cursor back to the menus.
	release_mouse()

func set_camera(camera: Camera3D, rig: Node3D = null) -> void:
	_camera = camera
	var resolved := rig if rig else (camera.get_parent() as Node3D if camera else null)
	_camera_rig = resolved as MatchCamera
	if _camera_rig:
		_camera_rig.auto_follow = _touch_primary

func bind_hud(hud: Node) -> void:
	if hud == null:
		return
	_hud = hud as MatchHud
	if hud.has_signal("move_input"):
		hud.move_input.connect(_on_move_input)
	if hud.has_signal("look_drag"):
		hud.look_drag.connect(_on_look_drag)
	if hud.has_signal("throw_started"):
		hud.throw_started.connect(_on_throw_started)
	if hud.has_signal("throw_released"):
		hud.throw_released.connect(_on_throw_released)
	if hud.has_signal("dodge_pressed"):
		hud.dodge_pressed.connect(_on_dodge_pressed)
	if hud.has_signal("jump_pressed"):
		hud.jump_pressed.connect(_on_jump_pressed)
	if hud.has_signal("jump_released"):
		hud.jump_released.connect(func(): _hud_jump_held = false)
	if hud.has_signal("camera_toggle_pressed"):
		hud.camera_toggle_pressed.connect(_toggle_camera)
	if hud.has_signal("controls_changed"):
		hud.controls_changed.connect(_on_controls_changed)
	if _hud:
		_hud.set_touch_layout(_touch_primary)
		_hud.set_mouse_look_pad(_touch_primary and not (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")))
		if hud.has_signal("menu_closed"):
			hud.menu_closed.connect(capture_mouse)
		if hud.has_signal("menu_opened"):
			hud.menu_opened.connect(release_mouse)

func is_touch_primary() -> bool:
	return _touch_primary

## Switched from the pause menu mid-match.
func _on_controls_changed(scheme: String) -> void:
	_touch_primary = scheme == "touch"
	if _camera_rig:
		_camera_rig.auto_follow = _touch_primary
	if _hud:
		_hud.set_mouse_look_pad(_touch_primary and not (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")))

# --------------------------------------------------------------------------- #
# Mouse capture
# --------------------------------------------------------------------------- #

func capture_mouse() -> void:
	if _touch_primary or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

# --------------------------------------------------------------------------- #
# HUD (touch) callbacks
# --------------------------------------------------------------------------- #

func _on_move_input(vector: Vector2) -> void:
	_stick_axis = vector

func _on_look_drag(pixels: Vector2) -> void:
	if _camera_rig == null:
		return
	var view_height := get_viewport().get_visible_rect().size.y if get_viewport() else 720.0
	var scale := TOUCH_SENSITIVITY * GameState.mouse_sensitivity() * (720.0 / maxf(view_height, 1.0))
	_camera_rig.add_look_input(-pixels.x * scale, -pixels.y * scale)

func _on_throw_started() -> void:
	if _fighter:
		_update_aim()
		_fighter.start_charging_throw()

func _on_throw_released(charge: float) -> void:
	if _fighter == null:
		return
	if _fighter.is_charging:
		_fighter.charge_amount = clampf(charge, 0.0, 1.0)
	_update_aim()
	_fighter.release_throw()

func _on_dodge_pressed() -> void:
	if _fighter:
		_fighter.dodge(_dodge_direction())

func _on_jump_pressed() -> void:
	_hud_jump_held = true
	if _fighter:
		_fighter.jump()

func _toggle_camera() -> void:
	if _camera_rig:
		_camera_rig.toggle_mode()

# --------------------------------------------------------------------------- #
# Device input
# --------------------------------------------------------------------------- #

func _unhandled_input(event: InputEvent) -> void:
	if _fighter == null:
		return
	# On-screen controls own every pointer in touch mode. Godot also turns each
	# finger into an emulated mouse click, and the left mouse button is bound to
	# "throw_book", so without this any touch that missed a button threw a book.
	if _touch_primary and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_using_pad = false

	if event is InputEventMouseMotion and _mouse_captured() and _camera_rig:
		var motion := (event as InputEventMouseMotion).screen_relative
		var sensitivity := MOUSE_SENSITIVITY * GameState.mouse_sensitivity()
		_camera_rig.add_look_input(-motion.x * sensitivity, -motion.y * sensitivity)
		return

	# A click on the game view while the cursor is free just re-captures it; it
	# must not also fire a throw the player did not intend.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _mouse_captured() and not _touch_primary and not (_hud and _hud.is_menu_open()):
		capture_mouse()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if _hud:
			_hud.toggle_pause_menu()
		return
	if event.is_action_pressed("help") and _hud:
		_hud.toggle_controls_help()
		return
	if _hud and _hud.is_menu_open():
		return
	if event.is_action_pressed("camera_toggle"):
		_toggle_camera()
	elif event.is_action_pressed("jump"):
		_fighter.jump()
	elif event.is_action_pressed("throw_book"):
		_update_aim()
		_fighter.start_charging_throw()
		if _hud and _fighter.is_charging:
			_hud.begin_external_charge()
	elif event.is_action_released("throw_book"):
		if _hud and _hud.is_charging():
			_fighter.charge_amount = _hud.end_external_charge()
		_update_aim()
		_fighter.release_throw()
	elif event.is_action_pressed("dodge"):
		_fighter.dodge(_dodge_direction())

func _process(delta: float) -> void:
	# Camera look runs at render rate so it is perfectly smooth on high-refresh
	# displays; the physics tick is too coarse for mouse/stick look.
	if _camera_rig == null:
		return
	var look := Vector2(
		Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	)
	if look.length() > 0.01:
		var magnitude := pow(minf(look.length(), 1.0), PAD_RESPONSE_EXPONENT)
		look = look.normalized() * magnitude
		_camera_rig.add_look_input(-look.x * PAD_YAW_SPEED * delta, -look.y * PAD_PITCH_SPEED * delta)
		_using_pad = true

func _physics_process(_delta: float) -> void:
	if _fighter == null or not _fighter.alive:
		return
	var keyboard_axis := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)
	var axis := _stick_axis if _stick_axis.length() > 0.02 else keyboard_axis
	if axis.length() > 1.0:
		axis = axis.normalized()
	if _hud and _hud.is_menu_open():
		axis = Vector2.ZERO
	if axis.length() > 0.1 and _hud:
		_hud.notify_player_moved()
	var world_move := _camera_relative(axis)
	_fighter.move_axis = Vector2(world_move.x, world_move.z)
	_fighter.jump_held = Input.is_action_pressed("jump") or _hud_jump_held
	_fighter.manual_aim_active = true

	_update_aim()

	# Facing: toward the crosshair while charging (strafe/aim mode) or in first
	# person; otherwise toward the direction of travel.
	var face_camera := _fighter.is_charging or (_camera_rig != null and _camera_rig.is_first_person())
	if face_camera and _fighter.has_aim_point:
		var to_aim := _fighter.aim_point - _fighter.global_position
		to_aim.y = 0.0
		if to_aim.length() > 0.3:
			_fighter.aim_direction = to_aim.normalized()
		elif _camera_rig:
			_fighter.aim_direction = _camera_rig.flat_forward()
	elif world_move.length() > 0.05:
		_fighter.aim_direction = world_move.normalized()

	_update_preview()
	if _hud:
		_hud.set_dodge_cooldown(_fighter.dodge_cooldown_ratio())
		_hud.set_crosshair_state(_assist_target != null, _fighter.is_charging, _fighter.books_held > 0 and _fighter.alive)

# --------------------------------------------------------------------------- #
# Aim
# --------------------------------------------------------------------------- #

## Resolves the crosshair to a world point, then applies aim assist.
func _update_aim() -> void:
	if _fighter == null or _camera_rig == null or _camera == null:
		return
	var origin := _camera_rig.aim_ray_origin()
	var direction := _camera_rig.aim_ray_direction()
	var space := _fighter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * AIM_MAX_DISTANCE, 3)
	query.exclude = [_fighter.get_rid()]
	var hit := space.intersect_ray(query)
	var point: Vector3 = hit["position"] if not hit.is_empty() else origin + direction * AIM_MAX_DISTANCE

	_assist_target = _find_assist_target(origin, direction, space)
	if _assist_target:
		point = _fighter.lead_point_for(_assist_target, _fighter.charge_amount)
	_fighter.aim_point = point
	_fighter.has_aim_point = true

func _assist_angle() -> float:
	if _touch_primary:
		return ASSIST_ANGLE_TOUCH
	return ASSIST_ANGLE_PAD if _using_pad else ASSIST_ANGLE_MOUSE

func _find_assist_target(origin: Vector3, direction: Vector3, space: PhysicsDirectSpaceState3D) -> Fighter:
	var best: Fighter = null
	var best_angle := _assist_angle()
	var throw_origin := _fighter.throw_origin()
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == _fighter or not (node is Fighter):
			continue
		var other := node as Fighter
		if not other.alive or other.is_knocked_out or not other.visible:
			continue
		var chest := other.global_position + Vector3.UP * 1.05
		if chest.distance_to(_fighter.global_position) > ASSIST_MAX_RANGE:
			continue
		var to_target := chest - origin
		if to_target.dot(direction) <= 0.0:
			continue
		var angle := direction.angle_to(to_target.normalized())
		if angle >= best_angle:
			continue
		# Line of sight from the hand, so assist never bends a throw through cover.
		var los := PhysicsRayQueryParameters3D.create(throw_origin, chest, 1)
		if not space.intersect_ray(los).is_empty():
			continue
		best_angle = angle
		best = other
	return best

func _update_preview() -> void:
	if _preview == null:
		return
	if not _fighter.is_charging or not _fighter.alive or _fighter.is_knocked_out:
		_preview.hide_preview()
		return
	var launch := _fighter.compute_launch(_fighter.charge_amount)
	var exclude: Array[RID] = [_fighter.get_rid()]
	var result := BookProjectile.simulate(
		_fighter.get_world_3d().direct_space_state,
		launch["origin"], launch["velocity"], Fighter.THROW_GRAVITY, exclude
	)
	var on_fighter: bool = result["collider"] is Fighter
	_preview.show_path(result["points"], result["position"], result["normal"], on_fighter, result["hit"])

func _dodge_direction() -> Vector3:
	var move := Vector3(_fighter.move_axis.x, 0.0, _fighter.move_axis.y)
	if move.length() > 0.1:
		return move.normalized()
	# No stick input: dodge backward relative to the camera, the safe default
	# when something is flying at you.
	if _camera_rig:
		return -_camera_rig.flat_forward()
	return Vector3.ZERO

## Maps a stick vector onto the ground plane using only the camera's heading.
## `+y` on the stick always means "away from the camera".
func _camera_relative(axis: Vector2) -> Vector3:
	var yaw := 0.0
	if _camera_rig and is_instance_valid(_camera_rig):
		yaw = _camera_rig.yaw
	elif _camera and is_instance_valid(_camera):
		var basis := _camera.global_transform.basis
		var flat_forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
		if flat_forward.length() > 0.001:
			yaw = atan2(-flat_forward.x, -flat_forward.z)
	var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
	return right * axis.x + forward * axis.y
