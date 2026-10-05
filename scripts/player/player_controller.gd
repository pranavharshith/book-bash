class_name Fighter
extends CharacterBody3D
## Shared arcade controller for human and bot fighters.
##
## The same node drives local play, bot opponents, and network peers. In network
## matches the host resolves all combat; clients run the identical movement and
## presentation code so prediction stays visually consistent.

signal hit_taken(remaining_health: float)
signal knocked_out(fighter: Fighter)
signal ammo_changed(books_held: int)
signal state_changed(fighter: Fighter)
signal power_up_changed(power_id: String, seconds_left: float)
signal damage_dealt(target: Fighter, amount: float, world_position: Vector3)

# --- Health / stocks -------------------------------------------------------- #
const MAX_HEALTH := 100.0
const MAX_STOCKS := 3

# --- Locomotion ------------------------------------------------------------- #
## Arcade tuning: reaches full speed in ~0.12 s and stops in ~0.14 s so the
## character responds instantly without feeling like it teleports. Turning
## against the current direction gets an extra boost so reversals are crisp
## rather than skating through a slow U-turn.
const MOVE_SPEED := 6.2
const ACCEL := 52.0
const FRICTION := 44.0
const REVERSE_ACCEL_BONUS := 1.6
const AIR_ACCEL := 20.0
const AIR_FRICTION := 3.0
const TURN_SPEED := 14.0
const GRAVITY := 26.0
## Falling faster than rising removes the floaty "moon jump" feel.
const FALL_GRAVITY_MULTIPLIER := 1.45
const MAX_FALL_SPEED := 28.0
const KNOCKBACK_FRICTION := 9.0

# --- Jumping ---------------------------------------------------------------- #
## ~1.15 m apex: enough to hop onto a table or over a book stack, never enough to
## clear the 4 m perimeter.
const JUMP_VELOCITY := 7.7
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.13
## Releasing jump early cuts the rise for a short hop.
const JUMP_CUT_MULTIPLIER := 0.5

# --- Aiming locomotion ------------------------------------------------------ #
## While charging a throw the fighter faces the crosshair and strafes, slightly
## slower, like drawing a bow in a third-person action game.
const CHARGE_MOVE_MULTIPLIER := 0.72

# --- Fighter separation ----------------------------------------------------- #
## Fighters do not physically collide with each other (no head-standing, no
## being launched or wedged). A soft push keeps bodies from overlapping instead.
const SEPARATION_RADIUS := 0.95
const SEPARATION_STRENGTH := 9.0

# --- Ammo ------------------------------------------------------------------- #
## Players carry a small stack of books instead of a single one. Running dry and
## having to walk to a pickup every single throw made the loop feel like chores,
## so a slow passive refill guarantees you always have something to do.
const MAX_BOOKS := 3
## Faster refill on the bigger map so nobody (bot or human) spends the match
## jogging between pickups with empty hands.
const AMMO_REGEN_SECONDS := 4.5
const STARTING_BOOKS := 2

# --- Throwing --------------------------------------------------------------- #
const THROW_CHARGE_TIME := 0.62
## Horizontal launch speed. Charge trades a lobbed, slow book for a fast flat one;
## the vertical component is solved so the book lands on the aimed point.
const THROW_SPEED_MIN := 14.0
const THROW_SPEED_MAX := 24.0
## Kept for compatibility with older callers; arcs are now solved per throw.
const THROW_ARC_MIN := 2.6
const THROW_ARC_MAX := 6.4
## Aim range grows with charge. Past it the throw still flies along the aim line,
## it just is not guaranteed to reach the crosshair (the preview shows where).
const THROW_RANGE_MIN := 14.0
const THROW_RANGE_MAX := 30.0
## Vertical launch speed cap: aiming at the sky lobs, it does not fire a rocket.
const THROW_MAX_VERTICAL := 11.0
const THROW_GRAVITY := 14.0
const THROW_DAMAGE_MIN := 13.0
const THROW_DAMAGE_MAX := 24.0
const THROW_COOLDOWN := 0.26
const MULTI_THROW_SPREAD_DEGREES := 13.0

# --- Dodge ------------------------------------------------------------------ #
const DODGE_SPEED := 13.5
const DODGE_DURATION := 0.28
const DODGE_COOLDOWN := 0.85

# --- Reactions -------------------------------------------------------------- #
const HIT_STUN_DURATION := 0.28
const KO_LOCKOUT := 1.35
const RESPAWN_INVULNERABILITY := 1.7
const SAFETY_NET_Y := -8.0

const FOOTSTEP_INTERVAL := 0.3
const AUTO_AIM_RANGE := 17.0
const AUTO_AIM_ALIGNMENT_WEIGHT := 2.2

# --- Power-ups -------------------------------------------------------------- #
const POWER_SPEED := "speed"
const POWER_DAMAGE := "damage"
const POWER_SHIELD := "shield"
const POWER_MULTI := "multi"
const POWER_SPEED_MULTIPLIER := 1.5
const POWER_DAMAGE_MULTIPLIER := 1.8
const POWER_SHIELD_HITS := 2

## The imported Creative-Characters rig is authored facing +Z, while Godot's
## `looking_at()` aims a node's -Z at its target. Without this the whole cast
## sprints backwards, which is exactly how the first playable looked.
const MODEL_YAW_OFFSET := PI

@export var fighter_name := "Fighter"
@export var fighter_color := Color.WHITE
@export var book_projectile_scene: PackedScene
@export var is_bot := false
@export var model_path := ""

var cosmetics: Dictionary = {}
var move_axis := Vector2.ZERO
var aim_direction := Vector3.FORWARD
var manual_aim_active := false
var control_enabled := false
var movement_multiplier := 1.0
var respawn_position := Vector3.ZERO
var health := MAX_HEALTH
var stocks := MAX_STOCKS
var knockout_score := 0
var books_held := STARTING_BOOKS
var is_charging := false
var charge_amount := 0.0
var is_dodging := false
var is_hit_stunned := false
var is_knocked_out := false
var alive := true
var is_local_player := false
## Random spread applied to the final throw direction. Bots use this to express a
## difficulty tier; human throws stay exact so the aim assist feels trustworthy.
var aim_error_degrees := 0.0
## World-space point the human player is aiming at (crosshair hit). When set, the
## throw is solved to land exactly there and the preview uses the same solve.
var aim_point := Vector3.ZERO
var has_aim_point := false
## Set by input: true while the jump button is held (for variable jump height).
var jump_held := false

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _jumped_this_air := false
var _was_on_floor := true
var _view_hidden := false

var _dodge_timer := 0.0
var _dodge_cooldown_timer := 0.0
var _hit_stun_timer := 0.0
var _ko_timer := 0.0
var _invulnerability_timer := 0.0
var _throw_cooldown_timer := 0.0
var _ammo_regen_timer := AMMO_REGEN_SECONDS
var _dodge_dir := Vector3.ZERO
var _anim: PlayerAnimationState
var _model_root: Node3D
var _skeleton: Skeleton3D
var _footstep_timer := 0.0
var _footstep_alt := false
var _power_timers: Dictionary = {}
var _shield_hits := 0
var _nameplate: FighterNameplate
var _local_marker: Node3D
var _hand_book: Node3D

@onready var _model_holder: Node3D = get_node_or_null("ModelHolder")
@onready var _throw_point: Marker3D = get_node_or_null("ModelHolder/ThrowPoint")

func _ready() -> void:
	add_to_group("fighters")
	_load_model()
	_build_nameplate()
	_apply_cosmetics()

# --------------------------------------------------------------------------- #
# Model, skeleton, and cosmetics
# --------------------------------------------------------------------------- #

func _load_model() -> void:
	if _model_holder == null:
		return
	var path := model_path
	if path == "":
		for entry in GameState.ROSTER:
			if entry.get("name", "") == fighter_name:
				path = entry.get("model", "")
				break
	if path == "" or not ResourceLoader.exists(path):
		path = GameState.DEFAULT_MODEL
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	_model_root = scene.instantiate()
	_model_root.rotation.y = MODEL_YAW_OFFSET
	_model_holder.add_child(_model_root)
	_skeleton = _find_node_of_type(_model_root, "Skeleton3D") as Skeleton3D
	_tint_outfit()
	var anim_player := _find_node_of_type(_model_root, "AnimationPlayer") as AnimationPlayer
	if anim_player:
		_anim = PlayerAnimationState.new(anim_player, _model_root)
		_anim.play_loop(PlayerAnimationState.CLIP_IDLE)

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null

## Gives each roster slot a readable team colour without needing one texture per
## fighter: the shirt mesh is tinted, everything else keeps its authored look.
func _tint_outfit() -> void:
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance := child as MeshInstance3D
		if not mesh_instance.name.to_lower().begins_with("t_shirt"):
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = fighter_color
		material.roughness = 0.75
		mesh_instance.material_override = material

func _bone_socket(bone_name: String) -> BoneAttachment3D:
	if _skeleton == null:
		return null
	if _skeleton.find_bone(bone_name) < 0:
		return null
	var existing := _skeleton.get_node_or_null("Socket_" + bone_name) as BoneAttachment3D
	if existing:
		return existing
	var attachment := BoneAttachment3D.new()
	attachment.name = "Socket_" + bone_name
	_skeleton.add_child(attachment)
	attachment.bone_name = bone_name
	return attachment

## Accessory meshes ship skinned to this rig, so their vertices sit in skeleton
## rest space. Cancelling the bone's rest transform lets the plain mesh ride the
## live bone pose exactly where the original skinned version would have been.
func _rest_correction(bone_name: String) -> Transform3D:
	if _skeleton == null:
		return Transform3D.IDENTITY
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0:
		return Transform3D.IDENTITY
	return _skeleton.get_bone_global_rest(bone).affine_inverse()

## Attaches a cosmetic that was authored *as a skinned mesh of this rig* (hats,
## hair, glasses). Those need the rest-pose correction.
func _attach_accessory(bone_name: String, scene_path: String, node_name: String) -> Node3D:
	return _attach_to_bone(bone_name, scene_path, node_name, _rest_correction(bone_name))

## Attaches an independent prop (the book) that has its own local origin. Applying
## the rest-pose correction here is wrong — it is only meaningful for meshes whose
## vertices live in this skeleton's rest space — and it left the book hovering a
## metre away from the hand.
func _attach_prop(bone_name: String, scene_path: String, node_name: String, local: Transform3D) -> Node3D:
	return _attach_to_bone(bone_name, scene_path, node_name, local)

func _attach_to_bone(bone_name: String, scene_path: String, node_name: String, local: Transform3D) -> Node3D:
	var socket := _bone_socket(bone_name)
	if socket == null or not ResourceLoader.exists(scene_path):
		return null
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return null
	var instance := scene.instantiate()
	var holder := Node3D.new()
	holder.name = node_name
	socket.add_child(holder)
	holder.add_child(instance)
	holder.transform = local
	_strip_skinning(instance)
	return holder

## Accessory GLBs arrive as full skinned scenes. Only the meshes are wanted, and
## they must not stay bound to their own (now absent) skeleton. Their bundled
## AnimationPlayer is dropped too, so it cannot be mistaken for the character's.
func _strip_skinning(node: Node) -> void:
	if node is AnimationPlayer or node is AnimationTree:
		node.queue_free()
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.skeleton = NodePath()
		mesh_instance.skin = null
	if node is Skeleton3D:
		for child in node.get_children():
			node.remove_child(child)
			node.get_parent().add_child(child)
			child.owner = null
			_strip_skinning(child)
		node.queue_free()
		return
	for child in node.get_children().duplicate():
		_strip_skinning(child)

func _apply_cosmetics() -> void:
	_apply_hat(String(cosmetics.get("hat", "hat_default")))
	_apply_accessory(String(cosmetics.get("accessory", "acc_none")))
	_apply_carried_book(String(cosmetics.get("book", "book_classic")))
	_refresh_carried_book()

func _apply_accessory(accessory_id: String) -> void:
	var item := GameState.find_cosmetic(accessory_id)
	var model := String(item.get("model", ""))
	if model.is_empty():
		return
	_attach_accessory("Head", model, "CosmeticAccessory")

func _apply_hat(hat_id: String) -> void:
	var item := GameState.find_cosmetic(hat_id)
	var baked := _skeleton.get_node_or_null("Hat_010") if _skeleton else null
	var model := String(item.get("model", ""))
	if model.is_empty():
		if baked:
			(baked as Node3D).visible = hat_id != "hat_bare"
		return
	if baked:
		(baked as Node3D).visible = false
	_attach_accessory("Head", model, "CosmeticHat")

## Local placement of the book inside the hand-prop bone. `book.glb` is a 0.39 x
## 0.28 m upright book, so it only needs a small forward nudge and a scale down.
## Basis written out as columns (Z-rotation of -18 deg, scaled 0.75) because
## method calls like `Basis.from_euler()` are not constant expressions. It must
## stay a `const`: the lobby's CharacterPreview reads it as `Fighter.CARRIED_BOOK_LOCAL`.
const CARRIED_BOOK_LOCAL := Transform3D(
	Vector3(0.713293, -0.231763, 0.0),
	Vector3(0.231763, 0.713293, 0.0),
	Vector3(0.0, 0.0, 0.75),
	Vector3(0.02, -0.04, 0.05)
)

func _apply_carried_book(book_id: String) -> void:
	var holder := _attach_prop("RightHandProp", GameState.BOOK_MODEL, "CarriedBook", CARRIED_BOOK_LOCAL)
	if holder == null:
		# No prop bone (unexpected rig): fall back to a hand-relative offset so
		# the carried book still reads on screen.
		if _model_holder == null or not ResourceLoader.exists(GameState.BOOK_MODEL):
			return
		holder = Node3D.new()
		holder.name = "CarriedBook"
		_model_holder.add_child(holder)
		holder.position = Vector3(0.34, 1.02, -0.3)
		holder.scale = Vector3.ONE * 0.75
		holder.add_child(load(GameState.BOOK_MODEL).instantiate())
	_hand_book = holder
	GameState.apply_book_style(_hand_book, book_id)

func _refresh_carried_book() -> void:
	if _hand_book:
		_hand_book.visible = books_held > 0 and alive and not is_knocked_out

func _build_nameplate() -> void:
	_nameplate = FighterNameplate.new()
	_nameplate.name = "Nameplate"
	add_child(_nameplate)
	_nameplate.setup(fighter_name, fighter_color)
	_nameplate.position = Vector3(0, 2.05, 0)

func mark_as_local_player() -> void:
	is_local_player = true
	if _model_holder:
		_tag_own_body(_model_holder)
	if _local_marker or _nameplate == null:
		return
	_nameplate.set_local_player(true)
	var ring := MeshInstance3D.new()
	ring.name = "LocalRing"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.46
	mesh.outer_radius = 0.62
	mesh.rings = 32
	mesh.ring_segments = 6
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = fighter_color
	material.emission_enabled = true
	material.emission = fighter_color
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	ring.position = Vector3(0, 0.14, 0)
	ring.scale = Vector3(1.0, 0.14, 1.0)
	add_child(ring)
	_local_marker = ring

# --------------------------------------------------------------------------- #
# Simulation
# --------------------------------------------------------------------------- #

func _is_network_client() -> bool:
	return GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer() and not multiplayer.is_server()

func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	# Deliberately not a knockout. Falling out of the world was never a designed
	# mechanic here, only a symptom of open arena edges, so it silently recovers.
	if global_position.y < SAFETY_NET_Y or _outside_arena():
		_safety_recover()
		return

	if is_knocked_out:
		_process_knocked_out(delta)
		return
	if not alive:
		return

	if is_hit_stunned:
		_hit_stun_timer -= delta
		_decay_horizontal_velocity(delta, KNOCKBACK_FRICTION)
		if _hit_stun_timer <= 0.0:
			is_hit_stunned = false

	if is_dodging:
		_dodge_timer -= delta
		velocity.x = _dodge_dir.x * DODGE_SPEED
		velocity.z = _dodge_dir.z * DODGE_SPEED
		if _dodge_timer <= 0.0:
			is_dodging = false
	elif not is_hit_stunned:
		if control_enabled:
			_apply_movement(delta)
		else:
			_decay_horizontal_velocity(delta, FRICTION)

	if is_charging and control_enabled:
		charge_amount = clampf(charge_amount + delta / THROW_CHARGE_TIME, 0.0, 1.0)

	_apply_separation(delta)
	_apply_vertical(delta)
	var pre_move_vy := velocity.y
	# Separation rides along for this one move only, so it is collision-aware
	# (cannot shove anyone into a wall) and never accumulates into velocity.
	velocity += _separation_velocity
	move_and_slide()
	velocity -= _separation_velocity
	_post_move(pre_move_vy)
	_update_facing(delta)
	_update_animation()
	_update_footsteps(delta)

## Gravity, coyote time, jump buffering, and variable jump height.
func _apply_vertical(delta: float) -> void:
	var grounded := is_on_floor()
	if grounded:
		_coyote_timer = COYOTE_TIME
		_jumped_this_air = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta
		if _coyote_timer > 0.0 and not _jumped_this_air and _can_act():
			_do_jump()

	if not grounded:
		var g := GRAVITY
		if velocity.y < 0.0:
			g *= FALL_GRAVITY_MULTIPLIER
		elif not jump_held and _jumped_this_air:
			# Short hop: released early, so bleed the remaining rise quickly.
			g *= 1.0 / JUMP_CUT_MULTIPLIER
		velocity.y = maxf(velocity.y - g * delta, -MAX_FALL_SPEED)

func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	_jumped_this_air = true
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	# Leave the floor cleanly: without this the floor snap glues the body back
	# down on the first frame and the jump randomly fails on slopes.
	floor_snap_length = 0.0
	Audio.play_at("dodge", global_position, -14.0)
	_squash(Vector3(0.9, 1.12, 0.9), 0.1)

## Grounding is re-armed only after landing so floor snap never fights a jump.
func _post_move(pre_move_vy: float) -> void:
	var grounded := is_on_floor()
	if grounded:
		floor_snap_length = 0.45
		if not _was_on_floor and pre_move_vy < -6.0:
			_squash(Vector3(1.12, 0.86, 1.12), 0.12)
			Audio.play_at("footstep", global_position, -10.0)
	# Hitting a ceiling or the underside of a prop kills upward speed instead of
	# sliding along it, which is what read as "getting launched".
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0
	# Fighters are solid to each other, but nobody gets to stand on a head: if
	# the thing under us is another fighter, slide off sideways.
	for i in range(get_slide_collision_count()):
		var hit := get_slide_collision(i)
		if hit.get_collider() is Fighter and hit.get_normal().y > 0.35:
			var away := global_position - (hit.get_collider() as Fighter).global_position
			away.y = 0.0
			if away.length() < 0.05:
				away = Vector3.RIGHT.rotated(Vector3.UP, float(get_instance_id() % 360))
			velocity += away.normalized() * 4.0
			velocity.y = minf(velocity.y, -1.0)
			break
	_was_on_floor = grounded

func _can_act() -> bool:
	return control_enabled and alive and not is_knocked_out and not is_hit_stunned

## Request a jump. Buffered, so pressing slightly before landing still jumps.
func jump() -> void:
	if not _can_act():
		return
	_jump_buffer_timer = JUMP_BUFFER_TIME

func is_grounded() -> bool:
	return is_on_floor()

## Soft push away from overlapping fighters. Fighters do not collide with each
## other physically (mask excludes the fighter layer), so this is the only thing
## keeping two bodies from occupying the same spot.
func _apply_separation(delta: float) -> void:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == self or not (node is Fighter):
			continue
		var other := node as Fighter
		if not other.visible or not other.alive:
			continue
		var offset := global_position - other.global_position
		if absf(offset.y) > 1.6:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance >= SEPARATION_RADIUS:
			continue
		if distance < 0.01:
			offset = Vector3(sin(float(get_instance_id() % 628) * 0.01), 0.0, cos(float(get_instance_id() % 628) * 0.01))
			distance = 0.01
		push += offset / distance * (SEPARATION_RADIUS - distance) / SEPARATION_RADIUS
	_separation_velocity = push.limit_length(1.0) * SEPARATION_STRENGTH * 0.45

var _separation_velocity := Vector3.ZERO

var _squash_tween: Tween
func _squash(amount: Vector3, duration: float) -> void:
	# Squash the inner model, never ModelHolder: the holder's basis is slerped for
	# facing and must stay orthonormal.
	if _model_root == null or not is_inside_tree():
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	_model_root.scale = Vector3.ONE
	_squash_tween = create_tween()
	_squash_tween.tween_property(_model_root, "scale", amount, duration * 0.5)
	_squash_tween.tween_property(_model_root, "scale", Vector3.ONE, duration * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _tick_timers(delta: float) -> void:
	if _invulnerability_timer > 0.0:
		_invulnerability_timer -= delta
	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer -= delta
	if _throw_cooldown_timer > 0.0:
		_throw_cooldown_timer -= delta
	_tick_power_ups(delta)
	if control_enabled and alive and not is_knocked_out and books_held < MAX_BOOKS and not _is_network_client():
		_ammo_regen_timer -= delta
		if _ammo_regen_timer <= 0.0:
			_ammo_regen_timer = AMMO_REGEN_SECONDS
			set_network_ammo(books_held + 1)

func _process_knocked_out(delta: float) -> void:
	_ko_timer -= delta
	_decay_horizontal_velocity(delta, KNOCKBACK_FRICTION)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * FALL_GRAVITY_MULTIPLIER * delta, -MAX_FALL_SPEED)
	if _ko_timer <= 0.0 and not _is_network_client():
		_recover_from_ko()
	move_and_slide()

func _decay_horizontal_velocity(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)

## Last-resort escape guard behind the physical containment walls. Set by the
## GameManager from the arena's inner half extents; zero disables the check.
var arena_bounds := Vector2.ZERO

func _outside_arena() -> bool:
	if arena_bounds == Vector2.ZERO:
		return false
	return absf(global_position.x) > arena_bounds.x + 0.75 or absf(global_position.z) > arena_bounds.y + 0.75

func _safety_recover() -> void:
	velocity = Vector3.ZERO
	global_position = respawn_position + Vector3.UP * 0.5
	_invulnerability_timer = maxf(_invulnerability_timer, 0.8)

func _apply_movement(delta: float) -> void:
	var world_dir := Vector3(move_axis.x, 0.0, move_axis.y)
	if world_dir.length() > 1.0:
		world_dir = world_dir.normalized()
	var speed := effective_move_speed()
	if is_charging:
		speed *= CHARGE_MOVE_MULTIPLIER
	var target := world_dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()
	var moving := world_dir.length() > 0.01
	var rate: float
	if grounded:
		rate = ACCEL if moving else FRICTION
		# Reversing direction: brake harder so the turn feels snappy.
		if moving and horizontal.length() > 0.5 and horizontal.normalized().dot(world_dir.normalized()) < -0.2:
			rate *= REVERSE_ACCEL_BONUS
	else:
		# Air: keep momentum, allow steering, no hard stop mid-jump.
		rate = AIR_ACCEL if moving else AIR_FRICTION
	var result := horizontal.move_toward(target, rate * delta)
	velocity.x = result.x
	velocity.z = result.z

func effective_move_speed() -> float:
	var speed := MOVE_SPEED * movement_multiplier
	if has_power_up(POWER_SPEED):
		speed *= POWER_SPEED_MULTIPLIER
	return speed

## Hides the local body from its own camera (first person / camera squeezed into
## a corner) while keeping its shadow, so the player still reads their position.
func set_view_hidden(hidden: bool) -> void:
	if _view_hidden == hidden:
		return
	_view_hidden = hidden
	# The body itself is hidden by the camera's cull mask (see MatchCamera), which
	# costs nothing and keeps the shadow. Only the extras are toggled here.
	if _nameplate and not is_local_player:
		_nameplate.visible = not hidden
	if _local_marker:
		_local_marker.visible = not hidden

## Puts the fighter's meshes on the "own body" render layer so the local camera
## can hide them with a cull mask (regular layer 1 is kept so everything else,
## including the sun's shadow pass, still sees them).
const SELF_RENDER_LAYER_BIT := 1 << 18

func _tag_own_body(node: Node) -> void:
	if node is VisualInstance3D and not (node is Label3D):
		(node as VisualInstance3D).layers |= SELF_RENDER_LAYER_BIT
	for child in node.get_children():
		_tag_own_body(child)

func _update_facing(delta: float) -> void:
	var facing := aim_direction
	if facing.length() < 0.01:
		var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
		if flat_velocity.length() < 0.01:
			return
		facing = flat_velocity
	facing.y = 0.0
	if facing.length() < 0.01:
		return
	var target_basis := Transform3D().looking_at(facing, Vector3.UP).basis
	var holder := _model_holder if _model_holder else self
	holder.transform.basis = holder.transform.basis.slerp(target_basis, clampf(TURN_SPEED * delta, 0.0, 1.0))

func _update_animation() -> void:
	if _anim == null or _anim.is_locked() or is_dodging or is_hit_stunned or is_knocked_out:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 3.0:
		_anim.play_loop(PlayerAnimationState.CLIP_RUN, clampf(speed / MOVE_SPEED, 0.7, 1.45))
	elif speed > 0.35:
		_anim.play_loop(PlayerAnimationState.CLIP_WALK, clampf(speed / 2.6, 0.7, 1.3))
	else:
		_anim.play_loop(PlayerAnimationState.CLIP_IDLE)

func _update_footsteps(delta: float) -> void:
	if is_knocked_out or not alive or not control_enabled:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 1.2 or not is_on_floor():
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = FOOTSTEP_INTERVAL * clampf(MOVE_SPEED / maxf(speed, 0.1), 0.6, 1.4)
		Audio.play_at("footstep_alt" if _footstep_alt else "footstep", global_position, -16.0)
		_footstep_alt = not _footstep_alt

# --------------------------------------------------------------------------- #
# Control surface used by input, bots, and the network layer
# --------------------------------------------------------------------------- #

func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		move_axis = Vector2.ZERO
		is_charging = false
		charge_amount = 0.0

func can_carry_book() -> bool:
	return control_enabled and alive and books_held < MAX_BOOKS and not is_knocked_out

func give_book() -> void:
	if not can_carry_book():
		return
	set_network_ammo(books_held + 1)
	Audio.play_at("pickup", global_position, -6.0)

func start_charging_throw() -> void:
	if not control_enabled or books_held <= 0 or is_knocked_out or not alive:
		return
	if _throw_cooldown_timer > 0.0:
		return
	is_charging = true
	charge_amount = 0.0

func release_throw() -> void:
	if not is_charging:
		return
	is_charging = false
	var charge := charge_amount
	charge_amount = 0.0
	if not control_enabled or books_held <= 0:
		return
	_throw_book(charge)

func _throw_book(charge: float) -> void:
	set_network_ammo(books_held - 1)
	_throw_cooldown_timer = THROW_COOLDOWN
	if book_projectile_scene == null:
		return
	var damage := lerpf(THROW_DAMAGE_MIN, THROW_DAMAGE_MAX, charge)
	if has_power_up(POWER_DAMAGE):
		damage *= POWER_DAMAGE_MULTIPLIER
	var launch := compute_launch(charge, true)
	var origin: Vector3 = launch["origin"]
	var launch_velocity: Vector3 = launch["velocity"]

	if aim_error_degrees > 0.01:
		launch_velocity = launch_velocity.rotated(Vector3.UP, deg_to_rad(randf_range(-aim_error_degrees, aim_error_degrees)))
	var flat := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
	if flat.length() > 0.01:
		aim_direction = flat.normalized()
		# Snap the body to the throw so the release animation points where the
		# book actually goes.
		if _model_holder:
			_model_holder.transform.basis = Transform3D().looking_at(aim_direction, Vector3.UP).basis

	var shots := 3 if has_power_up(POWER_MULTI) else 1
	for i in range(shots):
		var offset_degrees := 0.0
		if shots > 1:
			offset_degrees = (float(i) - float(shots - 1) * 0.5) * MULTI_THROW_SPREAD_DEGREES
		var shot_velocity := launch_velocity.rotated(Vector3.UP, deg_to_rad(offset_degrees))
		_spawn_projectile(origin, shot_velocity, damage if shots == 1 else damage * 0.62)
	if _anim:
		_anim.play_action(PlayerAnimationState.CLIP_THROW, 1.45)
	Audio.play_at("throw", global_position, -8.0)

## Launch origin and initial velocity for a throw at `charge`. This is the single
## source of truth: the actual throw and the on-screen trajectory preview both
## call it, then run the same `BookProjectile` motion model.
func compute_launch(charge: float, allow_auto_aim: bool = false) -> Dictionary:
	var origin := throw_origin()
	var horizontal_speed := lerpf(THROW_SPEED_MIN, THROW_SPEED_MAX, charge)
	var max_range := lerpf(THROW_RANGE_MIN, THROW_RANGE_MAX, charge)
	var target := Vector3.ZERO
	var resolved := false
	if has_aim_point and not is_bot:
		target = aim_point
		resolved = true
	elif allow_auto_aim or is_bot:
		var victim := _auto_aim_target()
		if victim:
			target = _lead_point(victim, origin, horizontal_speed)
			resolved = true
	if not resolved:
		target = origin + _forward_flat() * max_range * 0.6 + Vector3.DOWN * origin.y
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if flat.length() > max_range:
		flat = flat.normalized() * max_range
		target = Vector3(origin.x + flat.x, target.y, origin.z + flat.z)
	var velocity_out := BookProjectile.solve_launch(origin, target, horizontal_speed, THROW_GRAVITY, THROW_MAX_VERTICAL)
	return {"origin": origin, "velocity": velocity_out, "target": target}

func throw_origin() -> Vector3:
	if _throw_point:
		return _throw_point.global_position
	return global_position + Vector3.UP * 1.15

func _forward_flat() -> Vector3:
	var direction := aim_direction
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = -(_model_holder.global_transform.basis.z if _model_holder else global_transform.basis.z)
		direction.y = 0.0
	return direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD

func _spawn_projectile(origin: Vector3, launch_velocity: Vector3, damage: float) -> void:
	var projectile := book_projectile_scene.instantiate() as BookProjectile
	if projectile == null:
		return
	projectile.configure_cosmetics(String(cosmetics.get("book", "book_classic")), String(cosmetics.get("trail", "trail_paper")))
	var container := get_parent().get_parent() if get_parent() else get_tree().current_scene
	if container == null:
		container = get_tree().current_scene
	container.add_child(projectile)
	projectile.fall_gravity = THROW_GRAVITY
	projectile.launch_with_velocity(origin, launch_velocity, self, damage)

## Chest-height lead point: where the target will be when a book thrown at
## `horizontal_speed` arrives. Used by bots and by human aim assist.
func _lead_point(target: Fighter, origin: Vector3, horizontal_speed: float) -> Vector3:
	var chest := target.global_position + Vector3.UP * 1.05
	var flat := chest - origin
	flat.y = 0.0
	var travel_time := flat.length() / maxf(horizontal_speed, 0.1)
	var predicted := target.velocity * travel_time * 0.6
	predicted.y = 0.0
	return chest + predicted

func lead_point_for(target: Fighter, charge: float) -> Vector3:
	return _lead_point(target, throw_origin(), lerpf(THROW_SPEED_MIN, THROW_SPEED_MAX, charge))

## Kept for API compatibility with older callers.
func _solve_lead(target: Fighter, origin: Vector3, speed: float) -> Dictionary:
	var point := _lead_point(target, origin, speed)
	var v := BookProjectile.solve_launch(origin, point, speed, THROW_GRAVITY, THROW_MAX_VERTICAL)
	return {"direction": Vector3(v.x, 0.0, v.z).normalized(), "arc": v.y}

func _auto_aim_target() -> Fighter:
	var facing := aim_direction
	if facing.length() < 0.01:
		facing = -(_model_holder.global_transform.basis.z if _model_holder else global_transform.basis.z)
	facing.y = 0.0
	if facing.length() > 0.01:
		facing = facing.normalized()
	var best: Fighter = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == self or not (node is Fighter):
			continue
		var other := node as Fighter
		if not other.alive or other.is_knocked_out:
			continue
		var to_other := other.global_position - global_position
		to_other.y = 0.0
		var distance := to_other.length()
		if distance < 0.01 or distance > AUTO_AIM_RANGE:
			continue
		var direction := to_other / distance
		var alignment := direction.dot(facing)
		if alignment < 0.15:
			continue
		var score := alignment * AUTO_AIM_ALIGNMENT_WEIGHT - distance / AUTO_AIM_RANGE
		if score > best_score:
			best_score = score
			best = other
	return best

func aim_preview_target() -> Fighter:
	return _auto_aim_target()

func dodge(direction: Vector3 = Vector3.ZERO) -> void:
	if not control_enabled or is_dodging or _dodge_cooldown_timer > 0.0 or is_knocked_out or not alive:
		return
	var dir := direction
	if dir.length() < 0.01:
		dir = Vector3(move_axis.x, 0.0, move_axis.y)
	if dir.length() < 0.01:
		dir = aim_direction
	if dir.length() < 0.01:
		dir = -(_model_holder.global_transform.basis.z if _model_holder else global_transform.basis.z)
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	is_dodging = true
	_dodge_timer = DODGE_DURATION
	_dodge_cooldown_timer = DODGE_COOLDOWN
	_dodge_dir = dir.normalized()
	if _anim:
		_anim.play_action(PlayerAnimationState.CLIP_DODGE, 1.6)
	Audio.play_at("dodge", global_position, -6.0)

func dodge_direction() -> Vector3:
	return _dodge_dir if _dodge_dir.length() > 0.01 else aim_direction

func dodge_cooldown_ratio() -> float:
	if DODGE_COOLDOWN <= 0.0:
		return 0.0
	return clampf(_dodge_cooldown_timer / DODGE_COOLDOWN, 0.0, 1.0)

# --------------------------------------------------------------------------- #
# Damage
# --------------------------------------------------------------------------- #

func apply_hit(damage: float, source: Node3D) -> void:
	if _is_network_client():
		return
	if not alive or is_knocked_out or is_dodging or _invulnerability_timer > 0.0:
		return
	if _shield_hits > 0:
		_shield_hits -= 1
		if _shield_hits <= 0:
			_clear_power_up(POWER_SHIELD)
		_invulnerability_timer = maxf(_invulnerability_timer, 0.28)
		ImpactVfx.spawn_shield_break(self, global_position + Vector3.UP)
		Audio.play_at("shield", global_position, -4.0)
		state_changed.emit(self)
		return

	health = maxf(health - damage, 0.0)
	var knock_direction := Vector3.ZERO
	if source is BookProjectile:
		knock_direction = (source as BookProjectile).velocity
	elif source and is_instance_valid(source):
		knock_direction = global_position - source.global_position
	knock_direction.y = 0.0
	if knock_direction.length() < 0.01:
		knock_direction = -aim_direction
	knock_direction = knock_direction.normalized()
	var knock_strength := 3.2 + damage * 0.14
	velocity.x = knock_direction.x * knock_strength
	velocity.z = knock_direction.z * knock_strength
	velocity.y = maxf(velocity.y, 1.8 + damage * 0.03)
	hit_taken.emit(health)
	state_changed.emit(self)

	var attacker := _fighter_behind(source)
	if attacker:
		attacker.damage_dealt.emit(self, damage, global_position + Vector3.UP * 1.9)

	if health <= 0.0:
		if attacker and attacker != self:
			attacker.knockout_score += 1
			attacker.state_changed.emit(attacker)
		_go_down()
	else:
		is_hit_stunned = true
		_hit_stun_timer = HIT_STUN_DURATION
		if _anim:
			_anim.play_action(PlayerAnimationState.CLIP_HIT, 1.25)

func _fighter_behind(source: Node3D) -> Fighter:
	if source is BookProjectile:
		var thrower := (source as BookProjectile).thrown_by
		return thrower as Fighter if thrower is Fighter else null
	return source as Fighter if source is Fighter else null

func _go_down() -> void:
	if is_knocked_out:
		return
	stocks = maxi(stocks - 1, 0)
	is_knocked_out = true
	is_charging = false
	_ko_timer = KO_LOCKOUT
	_power_timers.clear()
	_shield_hits = 0
	power_up_changed.emit("", 0.0)
	_refresh_carried_book()
	if _anim:
		_anim.play_action(PlayerAnimationState.CLIP_KO, 1.0, true)
	if stocks <= 0:
		alive = false
	state_changed.emit(self)
	knocked_out.emit(self)

func _recover_from_ko() -> void:
	is_knocked_out = false
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	if not alive:
		visible = false
		set_physics_process(false)
		state_changed.emit(self)
		return
	global_position = respawn_position
	_invulnerability_timer = RESPAWN_INVULNERABILITY
	books_held = maxi(books_held, STARTING_BOOKS)
	ammo_changed.emit(books_held)
	_refresh_carried_book()
	if _anim:
		_anim.clear_lock()
		_anim.play_loop(PlayerAnimationState.CLIP_IDLE)
	state_changed.emit(self)

func forfeit() -> void:
	if not alive:
		return
	health = 0.0
	stocks = 0
	is_charging = false
	is_knocked_out = false
	alive = false
	visible = false
	set_physics_process(false)
	state_changed.emit(self)
	knocked_out.emit(self)

func is_invulnerable() -> bool:
	return _invulnerability_timer > 0.0

# --------------------------------------------------------------------------- #
# Power-ups
# --------------------------------------------------------------------------- #

func grant_power_up(power_id: String, duration: float) -> void:
	_power_timers[power_id] = duration
	if power_id == POWER_SHIELD:
		_shield_hits = POWER_SHIELD_HITS
	power_up_changed.emit(power_id, duration)
	state_changed.emit(self)

func has_power_up(power_id: String) -> bool:
	return _power_timers.get(power_id, 0.0) > 0.0

func active_power_up() -> String:
	for power_id in _power_timers:
		if _power_timers[power_id] > 0.0:
			return power_id
	return ""

func active_power_up_seconds() -> float:
	var power_id := active_power_up()
	return float(_power_timers.get(power_id, 0.0)) if power_id != "" else 0.0

func shield_hits_left() -> int:
	return _shield_hits

func _tick_power_ups(delta: float) -> void:
	if _power_timers.is_empty():
		return
	var expired: Array[String] = []
	for power_id in _power_timers:
		_power_timers[power_id] = float(_power_timers[power_id]) - delta
		if _power_timers[power_id] <= 0.0:
			expired.append(power_id)
	for power_id in expired:
		_clear_power_up(power_id)

func _clear_power_up(power_id: String) -> void:
	_power_timers.erase(power_id)
	if power_id == POWER_SHIELD:
		_shield_hits = 0
	power_up_changed.emit(active_power_up(), active_power_up_seconds())

# --------------------------------------------------------------------------- #
# Network state application
# --------------------------------------------------------------------------- #

func hit_stun_remaining() -> float:
	return maxf(_hit_stun_timer, 0.0) if is_hit_stunned else 0.0

func dodge_remaining() -> float:
	return maxf(_dodge_timer, 0.0) if is_dodging else 0.0

func ko_remaining() -> float:
	return maxf(_ko_timer, 0.0) if is_knocked_out else 0.0

func set_network_ammo(value: int) -> void:
	value = clampi(value, 0, MAX_BOOKS)
	if books_held == value:
		return
	if value > books_held:
		_ammo_regen_timer = AMMO_REGEN_SECONDS
	books_held = value
	_refresh_carried_book()
	ammo_changed.emit(books_held)
	state_changed.emit(self)

func apply_network_combat_state(synced_health: float, synced_stocks: int, synced_alive: bool, synced_knocked_out: bool, synced_hit_stunned: bool, synced_dodging: bool, lock_seconds: float, authoritative_velocity: Vector3) -> void:
	var changed := not is_equal_approx(health, synced_health) or stocks != synced_stocks or alive != synced_alive or is_knocked_out != synced_knocked_out or is_hit_stunned != synced_hit_stunned or is_dodging != synced_dodging
	health = synced_health
	stocks = synced_stocks
	alive = synced_alive
	is_knocked_out = synced_knocked_out
	is_hit_stunned = synced_hit_stunned
	is_dodging = synced_dodging
	if synced_knocked_out:
		_ko_timer = maxf(lock_seconds, 0.1)
	elif synced_hit_stunned:
		_hit_stun_timer = maxf(lock_seconds, 0.05)
	elif synced_dodging:
		_dodge_timer = maxf(lock_seconds, 0.05)
	if synced_knocked_out or synced_hit_stunned or synced_dodging:
		velocity = authoritative_velocity
	if is_knocked_out:
		visible = true
		set_physics_process(true)
	elif not alive:
		visible = false
		set_physics_process(false)
	else:
		visible = true
		set_physics_process(true)
	_refresh_carried_book()
	if changed:
		state_changed.emit(self)

func apply_network_score(synced_score: int) -> void:
	if knockout_score == synced_score:
		return
	knockout_score = synced_score
	state_changed.emit(self)

func apply_network_power_up(power_id: String, seconds_left: float) -> void:
	_power_timers.clear()
	if power_id != "" and seconds_left > 0.0:
		_power_timers[power_id] = seconds_left
	power_up_changed.emit(power_id, seconds_left)

# --------------------------------------------------------------------------- #
# Presentation helpers
# --------------------------------------------------------------------------- #

func nameplate() -> FighterNameplate:
	return _nameplate

func play_equipped_emote() -> void:
	if _anim:
		_anim.play_action(PlayerAnimationState.CLIP_THROW, 0.85)
	# Animates the inner model so ModelHolder's facing basis stays orthonormal.
	if _model_root == null:
		return
	var tween := create_tween()
	var original_scale := _model_root.scale
	if String(cosmetics.get("emote", "emote_wave")) == "emote_victory":
		tween.tween_property(_model_root, "scale", original_scale * Vector3(1.18, 0.86, 1.18), 0.16)
		tween.tween_property(_model_root, "scale", original_scale * Vector3(0.94, 1.16, 0.94), 0.18)
		tween.tween_property(_model_root, "scale", original_scale, 0.2)
	else:
		tween.tween_property(_model_root, "rotation:z", 0.28, 0.18)
		tween.tween_property(_model_root, "rotation:z", -0.18, 0.18)
		tween.tween_property(_model_root, "rotation:z", 0.0, 0.18)

func respawn_at(position: Vector3) -> void:
	respawn_position = position
	global_position = position
	health = MAX_HEALTH
	stocks = MAX_STOCKS
	knockout_score = 0
	alive = true
	is_knocked_out = false
	is_hit_stunned = false
	is_dodging = false
	books_held = STARTING_BOOKS
	_power_timers.clear()
	_shield_hits = 0
	velocity = Vector3.ZERO
	visible = true
	set_physics_process(true)
	_refresh_carried_book()
	ammo_changed.emit(books_held)
	if _anim:
		_anim.clear_lock()
		_anim.play_loop(PlayerAnimationState.CLIP_IDLE)
	state_changed.emit(self)

func _process(_delta: float) -> void:
	if _nameplate:
		_nameplate.update_state(health / MAX_HEALTH, stocks, alive and not is_knocked_out)
