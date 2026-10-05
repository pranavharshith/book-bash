class_name BotBrain
extends Node
## Combat AI driving the same `Fighter` control surface a human uses.
##
## Difficulty is expressed through four levers only: how often it re-plans
## (reaction), how accurately it throws (accuracy), how willing it is to close
## distance (aggression), and how reliably it reacts to an incoming book
## (dodge_chance). Keeping the levers few makes the tiers actually feel different
## instead of just "faster numbers".

enum State { SEEK_BOOK, SEEK_POWER, HUNT, THROW_WINDUP, RETREAT }

@export var fighter_path: NodePath
@export var throw_range := 9.5
@export var flee_health_pct := 0.28

const STUCK_CHECK_INTERVAL := 0.55
const STUCK_DISTANCE_THRESHOLD := 0.32
const SIDESTEP_DURATION := 0.5
const POWER_UP_INTEREST_RANGE := 11.0

var reaction_time := 0.3
var accuracy := 0.75
var aggression := 0.75
var dodge_chance := 0.45

var _fighter: Fighter
var _state := State.SEEK_BOOK
var _think_timer := 0.0
var _target: Fighter = null
var _stuck_check_timer := 0.0
var _last_check_position := Vector3.ZERO
var _sidestep_timer := 0.0
var _sidestep_dir := Vector2.ZERO
var _strafe_sign := 1.0
var _strafe_timer := 0.0

func configure(settings: Dictionary) -> void:
	reaction_time = float(settings.get("reaction", 0.3))
	accuracy = float(settings.get("accuracy", 0.75))
	aggression = float(settings.get("aggression", 0.75))
	dodge_chance = float(settings.get("dodge_chance", 0.45))
	_apply_accuracy()

func _ready() -> void:
	_fighter = get_node_or_null(fighter_path) as Fighter
	if _fighter:
		_last_check_position = _fighter.global_position
	_apply_accuracy()
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0

func _apply_accuracy() -> void:
	if _fighter:
		_fighter.aim_error_degrees = lerpf(16.0, 1.5, clampf(accuracy, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	if _fighter == null or not _fighter.control_enabled or not _fighter.alive or _fighter.is_knocked_out:
		if _fighter:
			_fighter.move_axis = Vector2.ZERO
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think()
		_think_timer = reaction_time + randf_range(-0.05, 0.1)
	_act(delta)
	_update_stuck_detection(delta)

func _update_stuck_detection(delta: float) -> void:
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		_fighter.move_axis = _sidestep_dir
		return
	_stuck_check_timer -= delta
	if _stuck_check_timer > 0.0:
		return
	_stuck_check_timer = STUCK_CHECK_INTERVAL
	var wanted_to_move := _fighter.move_axis.length() > 0.1
	var moved_distance := _fighter.global_position.distance_to(_last_check_position)
	_last_check_position = _fighter.global_position
	if wanted_to_move and moved_distance < STUCK_DISTANCE_THRESHOLD:
		var perpendicular := Vector2(-_fighter.move_axis.y, _fighter.move_axis.x).normalized()
		if randf() < 0.5:
			perpendicular = -perpendicular
		_sidestep_dir = perpendicular
		_sidestep_timer = SIDESTEP_DURATION

func _think() -> void:
	var power_up := _nearest_power_up()
	if power_up and _fighter.active_power_up().is_empty() and randf() < aggression:
		_state = State.SEEK_POWER
		return
	if _fighter.books_held <= 0:
		_state = State.SEEK_BOOK
		return
	_target = _find_nearest_opponent()
	if _target == null:
		_state = State.SEEK_BOOK
		return
	if _fighter.health / Fighter.MAX_HEALTH <= flee_health_pct and randf() < (1.0 - aggression) + 0.25:
		_state = State.RETREAT
		return
	var distance := _fighter.global_position.distance_to(_target.global_position)
	if distance <= throw_range and _has_line_of_sight(_target):
		_state = State.THROW_WINDUP
	else:
		_state = State.HUNT

func _act(delta: float) -> void:
	match _state:
		State.SEEK_BOOK:
			_move_toward_nearest_book()
		State.SEEK_POWER:
			_move_toward(_nearest_power_up())
		State.HUNT:
			_move_toward(_target)
		State.THROW_WINDUP:
			_face_and_throw(delta)
		State.RETREAT:
			_move_away_from(_target)

func _move_toward_nearest_book() -> void:
	var nearest: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("book_pickups"):
		if not (node is Node3D):
			continue
		if node.has_method("is_available") and not node.is_available():
			continue
		var distance := _fighter.global_position.distance_to((node as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = node as Node3D
	if nearest:
		_move_toward(nearest)
	else:
		# Nothing to fetch: keep circling an opponent rather than standing still.
		_target = _find_nearest_opponent()
		if _target:
			_strafe_around(_target)
		else:
			_fighter.move_axis = Vector2.ZERO

func _nearest_power_up() -> Node3D:
	var nearest: Node3D = null
	var best_distance := POWER_UP_INTEREST_RANGE
	for node in get_tree().get_nodes_in_group("power_ups"):
		if not (node is Node3D):
			continue
		if node.has_method("is_available") and not node.is_available():
			continue
		var distance := _fighter.global_position.distance_to((node as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = node as Node3D
	return nearest

func _move_toward(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		_fighter.move_axis = Vector2.ZERO
		return
	var offset := target.global_position - _fighter.global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		_fighter.move_axis = Vector2.ZERO
		return
	# Do not run into an opponent's face: hold a throwing distance and circle.
	if target is Fighter and offset.length() < PREFERRED_RANGE_MIN:
		_strafe_around(target)
		return
	var direction := _steer(offset.normalized())
	_fighter.move_axis = Vector2(direction.x, direction.z)
	_fighter.aim_direction = offset.normalized()

const PREFERRED_RANGE_MIN := 5.0
const AVOID_PROBE := 1.8

## Simple whisker steering: if the straight path is blocked by cover, try angles
## to either side and take the first clear one. Keeps bots flowing around desks
## and pillars instead of grinding against them.
func _steer(direction: Vector3) -> Vector3:
	var space := _fighter.get_world_3d().direct_space_state
	var origin := _fighter.global_position + Vector3.UP * 0.6
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var candidate := direction.rotated(Vector3.UP, angle * _strafe_sign)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * AVOID_PROBE, 1)
		query.exclude = [_fighter.get_rid()]
		if space.intersect_ray(query).is_empty():
			return candidate
	return direction

func _strafe_around(target: Node3D) -> void:
	_strafe_timer -= get_physics_process_delta_time()
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.4)
		_strafe_sign *= -1.0
	var offset := target.global_position - _fighter.global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return
	var direction := offset.normalized()
	var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_sign
	# Drift in or out toward a comfortable 6-9 m duel distance while circling.
	var distance := offset.length()
	var radial := 0.0
	if distance < 6.0:
		radial = -0.6
	elif distance > 9.0:
		radial = 0.5
	var move := _steer((tangent + direction * radial).normalized())
	_fighter.move_axis = Vector2(move.x, move.z)
	_fighter.aim_direction = direction

func _move_away_from(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var away := _fighter.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	var direction := away.normalized()
	_fighter.move_axis = Vector2(direction.x, direction.z)
	if randf() < 0.03 * (1.0 + dodge_chance):
		_fighter.dodge(direction)

func _face_and_throw(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		_fighter.move_axis = Vector2.ZERO
		return
	var offset := _target.global_position - _fighter.global_position
	offset.y = 0.0
	if offset.length() > 0.01:
		_fighter.aim_direction = offset.normalized()
	# Keep moving while winding up: a stationary bot is trivially easy to hit.
	_strafe_around(_target)
	if not _fighter.is_charging:
		_fighter.start_charging_throw()
		return
	var wanted_charge := clampf(offset.length() / 12.0, 0.35, 0.95) * lerpf(0.75, 1.0, accuracy)
	if _fighter.charge_amount >= wanted_charge:
		_fighter.release_throw()

func _has_line_of_sight(target: Fighter) -> bool:
	var from := _fighter.global_position + Vector3.UP * 1.1
	var to := target.global_position + Vector3.UP * 1.1
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [_fighter.get_rid()]
	return _fighter.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Picks a target and sticks with it for a few seconds. Pure nearest-opponent
## made every bot converge on the same fighter and form one big pile.
var _target_lock_until := 0.0
var _personal_bias := randf_range(0.0, 6.0)

func _find_nearest_opponent() -> Fighter:
	var now := Time.get_ticks_msec() / 1000.0
	if _target and is_instance_valid(_target) and _target.alive and not _target.is_knocked_out and now < _target_lock_until:
		return _target
	var best: Fighter = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == _fighter or not (node is Fighter):
			continue
		var fighter := node as Fighter
		if not fighter.alive or fighter.is_knocked_out:
			continue
		var score := _fighter.global_position.distance_to(fighter.global_position)
		# Count how many other bots already chase this fighter and spread out.
		score += _pressure_on(fighter) * 5.0
		score += randf_range(0.0, _personal_bias)
		if score < best_score:
			best_score = score
			best = fighter
	_target_lock_until = now + randf_range(2.5, 4.5)
	return best

func _pressure_on(fighter: Fighter) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("fighters"):
		var brain := node.get_node_or_null("BotBrain") if node != _fighter else null
		if brain and brain._target == fighter:
			count += 1
	return count

func _find_nearest_opponent_raw() -> Fighter:
	var best: Fighter = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == _fighter or not (node is Fighter):
			continue
		var fighter := node as Fighter
		if not fighter.alive or fighter.is_knocked_out:
			continue
		var distance := _fighter.global_position.distance_to(fighter.global_position)
		if distance < best_distance:
			best_distance = distance
			best = fighter
	return best

func on_incoming_threat() -> void:
	if _fighter and _fighter.control_enabled and randf() < dodge_chance:
		_fighter.dodge()
