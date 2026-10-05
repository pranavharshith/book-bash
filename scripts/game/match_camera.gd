class_name MatchCamera
extends Node3D
## Third-person over-the-shoulder camera with an optional first-person mode.
##
## The rig node sits on the follow pivot and carries the camera *yaw only*, so
## `PlayerInputMobile` keeps resolving camera-relative movement from
## `global_rotation.y` exactly as before. Pitch, shoulder offset, and the
## collision-shortened boom are applied to the child `Camera3D`.
##
## Collision is a sphere sweep from the pivot out to the desired camera spot
## against the world layer plus a camera-only blocker layer. The boom snaps in
## immediately when something obstructs it (never a frame inside a wall) and eases
## back out once the obstruction clears.

enum Mode { THIRD_PERSON, FIRST_PERSON }

## Emitted when the local player is eliminated (true) and the camera takes over as
## a spectator. GameManager uses it to swap the HUD and open up interior ceilings.
signal spectating_changed(active: bool)
signal spectator_view_changed(overhead: bool)

## Render layer 19 holds the local player's own body. Hiding it from the camera
## is a cull-mask flip, which is free; the body still casts its shadow because the
## sun does not cull by this layer. (Swapping shadow modes on every mesh of the
## rig each time the view changed is what made camera switches stutter.)
const SELF_LAYER_NUMBER := 19

# --- Spectator "god's eye" view -------------------------------------------- #
const GOD_HEIGHT := 30.0
const GOD_PITCH := deg_to_rad(-68.0)
const GOD_FOV := 58.0
const GOD_SHARPNESS := 5.0

# --- Framing ---------------------------------------------------------------- #
## Pivot sits just under head height of the 1.9 m fighters, so the camera reads
## as "behind the shoulder" rather than "above the arena".
## Pivot slightly above head height: the camera looks *over* the fighter, which
## places them in the lower-centre of the frame with the arena ahead visible.
const PIVOT_HEIGHT := 1.85
const FIRST_PERSON_HEIGHT := 1.62
const BOOM_LENGTH := 4.3
const SHOULDER_OFFSET := 0.55
const FOV_THIRD_PERSON := 50.0   # vertical; ~80 deg horizontal at 16:9
const FOV_FIRST_PERSON := 58.0
const DEFAULT_PITCH := deg_to_rad(-12.0)
const PITCH_MIN_TP := deg_to_rad(-62.0)
const PITCH_MAX_TP := deg_to_rad(38.0)
const PITCH_MIN_FP := deg_to_rad(-80.0)
const PITCH_MAX_FP := deg_to_rad(80.0)

# --- Follow / smoothing ----------------------------------------------------- #
## Horizontal follow is tight so the fighter never drifts in frame; vertical is
## softer so a jump does not jerk the whole view.
const FOLLOW_SHARPNESS_XZ := 22.0
const FOLLOW_SHARPNESS_Y := 9.0
const BOOM_RETURN_SPEED := 5.5      # m/s ease-out after an obstruction clears
const MODE_BLEND_SHARPNESS := 10.0

# --- Collision -------------------------------------------------------------- #
const CAMERA_RADIUS := 0.24
const WORLD_LAYER := 1
const CAMERA_BLOCKER_LAYER := 16    # physics layer 5, "camera" only
const MIN_BOOM := 0.35
## Below this boom length the fighter's own body would fill the lens, so it is
## rendered shadow-only for the local view. Geometry always wins over distance:
## the camera never enters a wall to keep a comfortable gap, it hides the body.
const HIDE_SELF_DISTANCE := 1.1

# --- Shake ------------------------------------------------------------------ #
## Trauma model: shake = trauma^2, so small events barely register and only big
## ones (getting knocked out) are felt. Kept deliberately subtle.
const SHAKE_DECAY := 2.6
const SHAKE_MAX := 1.0
const SHAKE_MAX_ANGLE := deg_to_rad(1.4)
const SHAKE_MAX_OFFSET := 0.05

## Inner half extents of the playable floor. The camera is clamped a little
## inside the containment walls as a final guard behind collision.
var arena_half_extents := Vector2(14.0, 12.0)
## Interior arenas set this to their ceiling height; open-air ones leave it high.
var ceiling_height := 60.0

var yaw := 0.0
var pitch := DEFAULT_PITCH
var mode := Mode.THIRD_PERSON
## Gentle auto-recentre behind the fighter while moving, used for touch play
## where constantly dragging the camera is tiring. Off for mouse users.
var auto_follow := false

var _camera: Camera3D
var _fighters: Array[Fighter] = []
var _local_player: Fighter
var _subject: Fighter
var _pivot := Vector3.ZERO
var _boom := BOOM_LENGTH
var _mode_blend := 0.0   # 0 = third person, 1 = first person
var _trauma := 0.0
var _shake_time := 0.0
var _idle_look_time := 0.0
var _self_hidden := false
var _spectating := false
var _overhead := true        # spectating: true = god's eye, false = follow a player
var _god_yaw := 0.0
var _god_blend := 0.0        # 0 = normal camera, 1 = god's eye
var _sweep_shape: SphereShape3D
var _sweep_query: PhysicsShapeQueryParameters3D

func setup(camera: Camera3D) -> void:
	_camera = camera
	rotation = Vector3.ZERO
	if _camera:
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.fov = FOV_THIRD_PERSON
		_camera.near = 0.06
		_camera.far = 220.0
		_camera.current = true

func track(fighters: Array[Fighter], local_player: Fighter) -> void:
	_fighters = fighters
	_local_player = local_player
	# Saved preference (Lobby > View). First person is the default.
	set_first_person(GameState.camera_view() == "first" and local_player != null)
	_mode_blend = 1.0 if mode == Mode.FIRST_PERSON else 0.0
	_build_viewmodel()
	_subject = _pick_subject()
	if _subject:
		# Start looking the way the fighter faces, i.e. toward the arena centre.
		var facing := _subject.aim_direction
		facing.y = 0.0
		if facing.length() > 0.01:
			yaw = atan2(-facing.x, -facing.z)

func snap() -> void:
	_subject = _pick_subject()
	if _subject:
		_pivot = _subject_pivot()
	_boom = _solve_boom(_pivot, _orbit_basis(), BOOM_LENGTH)
	_place_camera(0.0)

# --------------------------------------------------------------------------- #
# Public control surface
# --------------------------------------------------------------------------- #

## Applies a look delta in radians. Positive yaw turns left, positive pitch looks up.
func add_look_input(delta_yaw: float, delta_pitch: float) -> void:
	if _spectating and _overhead:
		# Dragging swings the overhead view round the arena.
		_god_yaw = wrapf(_god_yaw - delta_yaw, -PI, PI)
		return
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	var lo := PITCH_MIN_FP if mode == Mode.FIRST_PERSON else PITCH_MIN_TP
	var hi := PITCH_MAX_FP if mode == Mode.FIRST_PERSON else PITCH_MAX_TP
	pitch = clampf(pitch + delta_pitch, lo, hi)
	if absf(delta_yaw) + absf(delta_pitch) > 0.0001:
		_idle_look_time = 0.0

func toggle_mode() -> void:
	if _spectating:
		# Eliminated: CAM flips between the overhead view and following a player.
		_overhead = not _overhead
		spectator_view_changed.emit(_overhead)
		return
	set_first_person(mode != Mode.FIRST_PERSON)

func is_spectating() -> bool:
	return _spectating

# --- Shader warm-up (driven by LoadingScreen while it still covers the view) - #
var _warmup_overhead := false
var _warmup_saved_yaw := 0.0
var _warmup_active := false

## Points the camera somewhere new so every material in that direction gets its
## shader compiled now, behind the loading overlay, instead of mid-match.
func warmup_pose(step: int, overhead: bool) -> void:
	if not _warmup_active:
		_warmup_active = true
		_warmup_saved_yaw = yaw
	_warmup_overhead = overhead
	if overhead:
		_god_yaw = PI * float(step % 2)
	else:
		yaw = wrapf(TAU * float(step) / 8.0, -PI, PI)

func end_warmup() -> void:
	if not _warmup_active:
		return
	_warmup_active = false
	_warmup_overhead = false
	_god_blend = 0.0
	_god_yaw = 0.0
	yaw = _warmup_saved_yaw
	snap()

## While following another fighter as a spectator, their own floating name/health
## plate would sit right in front of the lens, so it is hidden for that fighter.
var _plate_hidden_for: Fighter

func _update_followed_nameplate() -> void:
	var wanted: Fighter = null
	if _spectating and not _overhead and _subject and _subject != _local_player:
		wanted = _subject
	if wanted == _plate_hidden_for:
		return
	if _plate_hidden_for and is_instance_valid(_plate_hidden_for) and _plate_hidden_for.nameplate():
		_plate_hidden_for.nameplate().visible = _plate_hidden_for.alive and not _plate_hidden_for.is_knocked_out
	_plate_hidden_for = wanted
	if wanted and wanted.nameplate():
		wanted.nameplate().visible = false

func is_overhead() -> bool:
	return _spectating and _overhead

func _update_spectating() -> void:
	var out := _local_player != null and is_instance_valid(_local_player) and not _local_player.alive
	if out == _spectating:
		return
	_spectating = out
	if out:
		_overhead = true
		_god_yaw = 0.0
		mode = Mode.THIRD_PERSON
		_set_self_hidden(false)
	spectating_changed.emit(out)
	if out:
		spectator_view_changed.emit(true)

func set_first_person(enabled: bool) -> void:
	mode = Mode.FIRST_PERSON if enabled else Mode.THIRD_PERSON
	pitch = clampf(pitch, PITCH_MIN_FP if enabled else PITCH_MIN_TP, PITCH_MAX_FP if enabled else PITCH_MAX_TP)

func is_first_person() -> bool:
	return mode == Mode.FIRST_PERSON

func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, SHAKE_MAX)

func camera() -> Camera3D:
	return _camera

## World-space ray through the centre of the screen (the crosshair).
func aim_ray_origin() -> Vector3:
	return _camera.global_position if _camera else global_position

func aim_ray_direction() -> Vector3:
	return -_camera.global_transform.basis.z if _camera else Vector3.FORWARD

## Flat forward of the current view, used for camera-relative movement.
func flat_forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)

func subject() -> Fighter:
	return _subject

# --------------------------------------------------------------------------- #
# Update
# --------------------------------------------------------------------------- #

func _process(delta: float) -> void:
	if _camera == null:
		return
	_update_spectating()
	var god_target := 1.0 if (_spectating and _overhead) else 0.0
	if _warmup_overhead:
		god_target = 1.0
		_god_blend = 1.0
	_god_blend = lerpf(_god_blend, god_target, 1.0 - exp(-GOD_SHARPNESS * delta))
	if absf(_god_blend - god_target) < 0.002:
		_god_blend = god_target
	var subject := _pick_subject()
	if subject != _subject:
		_set_self_hidden(false)
		_subject = subject
	_update_followed_nameplate()
	if _subject == null:
		return

	_update_auto_follow(delta)

	var target_pivot := _subject_pivot()
	# Exponential smoothing, frame-rate independent. A respawn teleport is snapped
	# rather than dragged across the arena.
	if _pivot.distance_to(target_pivot) > 6.0:
		_pivot = target_pivot
	else:
		var kxz := 1.0 - exp(-FOLLOW_SHARPNESS_XZ * delta)
		var ky := 1.0 - exp(-FOLLOW_SHARPNESS_Y * delta)
		_pivot.x = lerpf(_pivot.x, target_pivot.x, kxz)
		_pivot.z = lerpf(_pivot.z, target_pivot.z, kxz)
		_pivot.y = lerpf(_pivot.y, target_pivot.y, ky)

	var target_blend := 1.0 if mode == Mode.FIRST_PERSON else 0.0
	_mode_blend = lerpf(_mode_blend, target_blend, 1.0 - exp(-MODE_BLEND_SHARPNESS * delta))
	if absf(_mode_blend - target_blend) < 0.002:
		_mode_blend = target_blend

	if _god_blend >= 1.0:
		# Fully overhead: no boom sweep needed at all.
		_place_god_camera()
		return

	var wanted := lerpf(BOOM_LENGTH, 0.0, _mode_blend)
	var allowed := _solve_boom(_pivot, _orbit_basis(), wanted)
	if allowed < _boom:
		_boom = allowed                      # obstruction: pull in immediately
	else:
		_boom = move_toward(_boom, allowed, BOOM_RETURN_SPEED * delta)

	if _trauma > 0.0:
		_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
		_shake_time += delta
	_place_camera(delta)

func _update_auto_follow(delta: float) -> void:
	_idle_look_time += delta
	if not auto_follow or mode == Mode.FIRST_PERSON or _idle_look_time < 1.2:
		return
	if _subject == null or _subject.is_charging:
		return
	var flat := Vector3(_subject.velocity.x, 0.0, _subject.velocity.z)
	if flat.length() < 2.0:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	var diff := wrapf(target_yaw - yaw, -PI, PI)
	# Never swing round when running toward the camera; only ease toward
	# sideways/forward motion, like most mobile third-person games.
	if absf(diff) > deg_to_rad(120.0):
		return
	yaw = wrapf(yaw + diff * (1.0 - exp(-1.6 * delta)), -PI, PI)

func _orbit_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))

func _subject_pivot() -> Vector3:
	var height := lerpf(PIVOT_HEIGHT, FIRST_PERSON_HEIGHT, _mode_blend)
	var pivot := _subject.global_position + Vector3.UP * height
	# Keep the pivot itself out of low ceilings (jumping under a table edge).
	pivot.y = minf(pivot.y, ceiling_height - CAMERA_RADIUS - 0.1)
	return pivot

## Sphere-sweeps from the pivot along the shoulder, then back along the boom.
## Returns the boom length that keeps the camera sphere out of geometry.
func _solve_boom(pivot: Vector3, basis: Basis, wanted: float) -> float:
	if wanted <= 0.001:
		return 0.0
	var world := get_world_3d()
	if world == null:
		return wanted
	var space := world.direct_space_state
	# Built once and reused: this runs every frame, twice.
	if _sweep_query == null:
		_sweep_shape = SphereShape3D.new()
		_sweep_shape.radius = CAMERA_RADIUS
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		_sweep_query.shape = _sweep_shape
		_sweep_query.collision_mask = WORLD_LAYER | CAMERA_BLOCKER_LAYER
		_sweep_query.collide_with_areas = false
	var query := _sweep_query

	# Shoulder leg first: in a tight corner the offset itself must not poke the
	# lens into the side wall.
	var shoulder_scale := 1.0 - _mode_blend
	var shoulder := basis.x * SHOULDER_OFFSET * shoulder_scale
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = shoulder
	var shoulder_fraction := 1.0
	if shoulder.length() > 0.001:
		var result := space.cast_motion(query)
		shoulder_fraction = result[0]
	var shoulder_point := pivot + shoulder * shoulder_fraction

	var boom_dir := basis.z
	query.transform = Transform3D(Basis.IDENTITY, shoulder_point)
	query.motion = boom_dir * wanted
	var boom_result := space.cast_motion(query)
	var length := wanted * float(boom_result[0])
	_last_shoulder_fraction = shoulder_fraction
	return clampf(length, 0.0 if wanted < MIN_BOOM else minf(MIN_BOOM, wanted), wanted)

var _last_shoulder_fraction := 1.0

func _place_camera(_delta: float) -> void:
	var basis := _orbit_basis()
	global_transform = Transform3D(Basis(Vector3.UP, yaw), _pivot)
	var shoulder := basis.x * SHOULDER_OFFSET * (1.0 - _mode_blend) * _last_shoulder_fraction
	var cam_pos := _pivot + shoulder + basis.z * _boom
	cam_pos = _clamp_to_arena(cam_pos)

	var cam_basis := basis
	if _trauma > 0.0:
		var shake := _trauma * _trauma
		var t := _shake_time * 31.0
		cam_basis = cam_basis * Basis.from_euler(Vector3(
			sin(t * 1.13) * SHAKE_MAX_ANGLE * shake,
			sin(t * 0.91 + 1.7) * SHAKE_MAX_ANGLE * shake,
			sin(t * 1.37 + 3.1) * SHAKE_MAX_ANGLE * 0.6 * shake
		))
		cam_pos += cam_basis.x * sin(t * 1.7) * SHAKE_MAX_OFFSET * shake + cam_basis.y * sin(t * 2.1 + 0.4) * SHAKE_MAX_OFFSET * shake
	var normal_fov := lerpf(FOV_THIRD_PERSON, FOV_FIRST_PERSON, _mode_blend)
	if _god_blend > 0.001:
		# Easing in from (or back out to) the overhead view.
		var god := _god_transform()
		var blended_origin := cam_pos.lerp(god.origin, _god_blend)
		var blended_basis := Basis(Quaternion(cam_basis).slerp(Quaternion(god.basis), _god_blend))
		_camera.global_transform = Transform3D(blended_basis, blended_origin)
		_camera.fov = lerpf(normal_fov, GOD_FOV, _god_blend)
	else:
		_camera.global_transform = Transform3D(cam_basis, cam_pos)
		_camera.fov = normal_fov
	_set_self_hidden(_subject != null and _subject == _local_player and _boom < HIDE_SELF_DISTANCE and not _spectating)
	_update_viewmodel(_delta)

## Overhead camera: high above the arena centre, tilted down, orbiting with the
## drag input. Tall enough to frame the whole 36 x 32 m floor on a wide phone.
func _god_transform() -> Transform3D:
	var reach := GOD_HEIGHT / tan(-GOD_PITCH)
	var position := Vector3(sin(_god_yaw) * reach, GOD_HEIGHT, cos(_god_yaw) * reach)
	var basis := Basis.looking_at(-position, Vector3.UP)
	return Transform3D(basis, position)

func _place_god_camera() -> void:
	# The camera is a child of this rig, so the rig moves first.
	global_transform = Transform3D(Basis(Vector3.UP, _god_yaw), Vector3.ZERO)
	_camera.global_transform = _god_transform()
	_camera.fov = GOD_FOV
	_set_self_hidden(false)
	_update_viewmodel(0.0)

# --------------------------------------------------------------------------- #
# First-person viewmodel: the held book in the lower right, like an FPS weapon.
# --------------------------------------------------------------------------- #

const VIEWMODEL_REST := Vector3(0.3, -0.27, -0.7)
var _viewmodel: Node3D
var _viewmodel_bob := 0.0
var _viewmodel_kick := 0.0
var _last_books := -1

func _build_viewmodel() -> void:
	if _camera == null or _viewmodel != null or not ResourceLoader.exists(GameState.BOOK_MODEL):
		return
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	_camera.add_child(_viewmodel)
	var book := (load(GameState.BOOK_MODEL) as PackedScene).instantiate() as Node3D
	_viewmodel.add_child(book)
	# Book is 0.39 x 0.28 m with its thin axis on X: turn the cover toward the
	# lens so it reads as "a book in my hand", small, in the lower-right corner.
	book.scale = Vector3.ONE * 0.55
	book.rotation = Vector3(deg_to_rad(-18), deg_to_rad(-115), deg_to_rad(-12))
	if _local_player:
		GameState.apply_book_style(book, String(_local_player.cosmetics.get("book", "book_classic")))
	_set_no_shadow(book)
	_viewmodel.position = VIEWMODEL_REST

func _set_no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_no_shadow(child)

func _update_viewmodel(delta: float) -> void:
	if _viewmodel == null:
		return
	var subject := _subject
	var show := subject != null and subject == _local_player and _mode_blend > 0.85 and subject.alive and not subject.is_knocked_out and subject.books_held > 0
	if subject and subject == _local_player and _last_books >= 0 and subject.books_held < _last_books:
		_viewmodel_kick = 1.0   # just threw: flick the arm forward
	_last_books = subject.books_held if subject else -1
	_viewmodel.visible = show or _viewmodel_kick > 0.05
	if subject == null:
		return
	var speed := Vector2(subject.velocity.x, subject.velocity.z).length()
	_viewmodel_bob += delta * speed * 1.6
	var bob := Vector3(sin(_viewmodel_bob) * 0.012, absf(cos(_viewmodel_bob)) * 0.016, 0.0) * minf(speed / 6.0, 1.0)
	var charge_pull := Vector3(0.04, 0.08, 0.18) * subject.charge_amount if subject.is_charging else Vector3.ZERO
	_viewmodel_kick = maxf(_viewmodel_kick - delta * 5.0, 0.0)
	var kick := Vector3(-0.1, 0.06, -0.35) * sin(_viewmodel_kick * PI)
	_viewmodel.position = _viewmodel.position.lerp(VIEWMODEL_REST + bob + charge_pull + kick, 1.0 - exp(-18.0 * delta))

func _clamp_to_arena(point: Vector3) -> Vector3:
	var margin := CAMERA_RADIUS + 0.05
	point.x = clampf(point.x, -arena_half_extents.x + margin, arena_half_extents.x - margin)
	point.z = clampf(point.z, -arena_half_extents.y + margin, arena_half_extents.y - margin)
	point.y = clampf(point.y, 0.25, ceiling_height - margin)
	return point

func _set_self_hidden(hidden: bool) -> void:
	if hidden == _self_hidden:
		return
	_self_hidden = hidden
	if _camera:
		_camera.set_cull_mask_value(SELF_LAYER_NUMBER, not hidden)
	if _subject and is_instance_valid(_subject) and _subject.has_method("set_view_hidden"):
		_subject.set_view_hidden(hidden)

## The local fighter while they are in the match, otherwise the first fighter
## still standing so an eliminated player keeps a watchable view.
func _pick_subject() -> Fighter:
	if _local_player and is_instance_valid(_local_player) and _local_player.alive:
		return _local_player
	if _subject and is_instance_valid(_subject) and _subject.alive and _subject.visible:
		return _subject
	for fighter in _fighters:
		if fighter and is_instance_valid(fighter) and fighter.alive and fighter.visible:
			return fighter
	return _local_player if _local_player and is_instance_valid(_local_player) else null
