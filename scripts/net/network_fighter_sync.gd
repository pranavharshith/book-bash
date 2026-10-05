class_name NetworkFighterSync
extends Node
## Host-authoritative combat snapshots with owner-side movement prediction.
##
## Clients may submit bounded movement/action intent, but the host alone resolves
## hits, stocks, hazards, pickups, bot logic, and match results. Submitted motion
## is validated for finiteness, per-step distance, and wall clipping, so a modified
## client cannot teleport or walk through arena geometry.

@export var fighter_path: NodePath
@export var owner_peer_id := 1

const SEND_INTERVAL := 1.0 / 20.0
const MIN_SERVER_STEP := 0.05
const MAX_SERVER_STEP := 0.45
const POSITION_EPSILON := 0.22
const HARD_SNAP_DISTANCE := 2.2

var _fighter: Fighter
var _send_timer := 0.0
var _target_position := Vector3.ZERO
var _has_remote_position := false
var _was_charging := false
var _was_dodging := false
var _last_charge := 0.0
var _last_owner_motion_msec := 0

func _ready() -> void:
	_fighter = get_node_or_null(fighter_path) as Fighter
	set_multiplayer_authority(owner_peer_id)

func _physics_process(delta: float) -> void:
	if _fighter == null or not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		if owner_peer_id == 1:
			_detect_local_actions(true)
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_INTERVAL
			_broadcast_server_state()
	elif multiplayer.get_unique_id() == owner_peer_id:
		_detect_local_actions(false)
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_INTERVAL
			_submit_owner_motion.rpc_id(1, _fighter.global_position, _fighter.velocity, _fighter.aim_direction)
	elif _has_remote_position:
		_fighter.global_position = _fighter.global_position.lerp(_target_position, clampf(delta * 14.0, 0.0, 1.0))

func _detect_local_actions(host_owned: bool) -> void:
	if _fighter.is_charging:
		_last_charge = _fighter.charge_amount
	if _fighter.is_charging and not _was_charging:
		if host_owned:
			_server_throw_start.rpc()
		else:
			_request_throw_start.rpc_id(1)
	elif not _fighter.is_charging and _was_charging:
		var aim := _fighter.aim_point if _fighter.has_aim_point else Vector3.INF
		if host_owned:
			_server_throw_release.rpc(_last_charge, aim)
		else:
			_request_throw_release.rpc_id(1, _last_charge, aim)
	if _fighter.is_dodging and not _was_dodging:
		if host_owned:
			_server_dodge.rpc(_fighter.dodge_direction())
		else:
			_request_dodge.rpc_id(1, _fighter.dodge_direction())
	_was_charging = _fighter.is_charging
	_was_dodging = _fighter.is_dodging

func _broadcast_server_state() -> void:
	var lock_seconds := maxf(_fighter.hit_stun_remaining(), maxf(_fighter.dodge_remaining(), _fighter.ko_remaining()))
	_server_state.rpc(
		_fighter.global_position,
		_fighter.velocity,
		_fighter.aim_direction,
		_fighter.health,
		_fighter.stocks,
		_fighter.alive,
		_fighter.is_knocked_out,
		_fighter.is_hit_stunned,
		_fighter.is_dodging,
		lock_seconds,
		_fighter.books_held,
		_fighter.knockout_score,
		_fighter.active_power_up(),
		_fighter.active_power_up_seconds()
	)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_owner_motion(position: Vector3, linear_velocity: Vector3, aim: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	if _fighter.is_knocked_out or _fighter.is_hit_stunned or not position.is_finite() or not linear_velocity.is_finite() or not aim.is_finite():
		return
	var now := Time.get_ticks_msec()
	var elapsed := SEND_INTERVAL
	if _last_owner_motion_msec > 0:
		elapsed = clampf(float(now - _last_owner_motion_msec) / 1000.0, MIN_SERVER_STEP, MAX_SERVER_STEP)
	_last_owner_motion_msec = now
	var max_speed := Fighter.DODGE_SPEED if _fighter.is_dodging else _fighter.effective_move_speed()
	var max_distance := max_speed * elapsed * 1.3 + 0.1
	# Vertical motion is validated separately so jumps replicate, but a client
	# cannot fly: rise is bounded by jump speed, and the route is wall-checked.
	var max_rise := Fighter.JUMP_VELOCITY * elapsed * 1.3 + 0.1
	var max_drop := Fighter.MAX_FALL_SPEED * elapsed * 1.3 + 0.1
	var dy := position.y - _fighter.global_position.y
	if dy > max_rise or dy < -max_drop:
		position.y = _fighter.global_position.y
	var flat_step := Vector2(position.x - _fighter.global_position.x, position.z - _fighter.global_position.z).length()
	if flat_step > max_distance:
		return
	if _route_hits_world(_fighter.global_position, position):
		return
	_fighter.global_position = position
	var max_velocity := max_speed + 0.6
	var vertical := clampf(linear_velocity.y, -Fighter.MAX_FALL_SPEED, Fighter.JUMP_VELOCITY + 0.5)
	linear_velocity.y = 0.0
	_fighter.velocity = linear_velocity.limit_length(max_velocity) + Vector3.UP * vertical
	aim.y = 0.0
	if aim.length() > 0.01:
		_fighter.aim_direction = aim.normalized()

func _route_hits_world(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.0001:
		return false
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, to + Vector3.UP * 0.8, 1)
	query.exclude = [_fighter.get_rid()]
	return not _fighter.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

@rpc("any_peer", "call_remote", "reliable")
func _request_throw_start() -> void:
	if not _valid_owner_request():
		return
	_fighter.start_charging_throw()
	_server_throw_start.rpc()

@rpc("any_peer", "call_remote", "reliable")
func _request_throw_release(charge: float, aim: Vector3) -> void:
	if not _valid_owner_request():
		return
	charge = clampf(charge, 0.0, 1.0)
	_apply_aim(aim)
	if not _fighter.is_charging:
		_fighter.start_charging_throw()
	_fighter.charge_amount = charge
	_fighter.release_throw()
	_server_throw_release.rpc(charge, aim)

## Accepts a remote aim point only if it is finite and plausibly in the arena;
## the throw solve itself clamps range, so this cannot extend reach.
func _apply_aim(aim: Vector3) -> void:
	if aim.is_finite() and aim.distance_to(_fighter.global_position) < 80.0:
		_fighter.aim_point = aim
		_fighter.has_aim_point = true
	else:
		_fighter.has_aim_point = false

@rpc("any_peer", "call_remote", "reliable")
func _request_dodge(direction: Vector3) -> void:
	if not _valid_owner_request() or not direction.is_finite():
		return
	_fighter.dodge(direction)
	_server_dodge.rpc(direction)

func _valid_owner_request() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == owner_peer_id and _fighter != null and _fighter.alive

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _server_state(
	position: Vector3, linear_velocity: Vector3, aim: Vector3,
	synced_health: float, synced_stocks: int, synced_alive: bool,
	synced_knocked_out: bool, synced_hit_stunned: bool, synced_dodging: bool,
	lock_seconds: float, synced_books: int, synced_score: int,
	synced_power_id: String, synced_power_seconds: float
) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _fighter == null:
		return
	var is_owner := multiplayer.get_unique_id() == owner_peer_id
	if is_owner:
		var error_distance := _fighter.global_position.distance_to(position)
		if error_distance > HARD_SNAP_DISTANCE:
			_fighter.global_position = position
		elif error_distance > POSITION_EPSILON:
			_fighter.global_position = _fighter.global_position.lerp(position, 0.18)
		if synced_hit_stunned or synced_knocked_out or synced_dodging:
			_fighter.velocity = linear_velocity
	else:
		_target_position = position
		_has_remote_position = true
		_fighter.velocity = linear_velocity
		_fighter.aim_direction = aim
	_fighter.apply_network_combat_state(
		synced_health, synced_stocks, synced_alive, synced_knocked_out,
		synced_hit_stunned, synced_dodging, lock_seconds, linear_velocity
	)
	_fighter.set_network_ammo(synced_books)
	_fighter.apply_network_score(synced_score)
	if not is_owner:
		_fighter.apply_network_power_up(synced_power_id, synced_power_seconds)

@rpc("any_peer", "call_remote", "reliable")
func _server_throw_start() -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.get_unique_id() == owner_peer_id or _fighter == null:
		return
	if _fighter.books_held <= 0:
		_fighter.set_network_ammo(1)
	_fighter.start_charging_throw()

@rpc("any_peer", "call_remote", "reliable")
func _server_throw_release(charge: float, aim: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.get_unique_id() == owner_peer_id or _fighter == null:
		return
	_apply_aim(aim)
	if _fighter.books_held <= 0:
		_fighter.set_network_ammo(1)
	if not _fighter.is_charging:
		_fighter.start_charging_throw()
	_fighter.charge_amount = clampf(charge, 0.0, 1.0)
	_fighter.release_throw()

@rpc("any_peer", "call_remote", "reliable")
func _server_dodge(direction: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.get_unique_id() == owner_peer_id or _fighter == null:
		return
	_fighter.dodge(direction)
