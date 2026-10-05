class_name RoundManager
extends Node
## Authoritative match phase machine: countdown, live round, timeout, and winner.
##
## In a network match only the host resolves the outcome; clients display the
## result the host broadcasts.

signal countdown_tick(seconds_left: int)
signal match_started()
signal timer_updated(seconds_left: int)
signal fighter_updated(index: int, health_ratio: float, stocks: int, knockouts: int, is_active: bool)
signal match_ended(winner_name: String)

@export var fighters: Array[Fighter] = []

var _time_left: float = GameState.MATCH_DURATION
var _running := false
var _finished := false
var _last_emitted_seconds := -1

func start_countdown(seconds: int = 3) -> void:
	_running = false
	for fighter in fighters:
		if fighter:
			fighter.set_control_enabled(false)
	_push_all_fighter_states()
	for i in range(seconds, 0, -1):
		countdown_tick.emit(i)
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	countdown_tick.emit(0)
	_begin_match()

func is_running() -> bool:
	return _running

func time_left() -> float:
	return maxf(_time_left, 0.0)

func _begin_match() -> void:
	_running = true
	_time_left = GameState.MATCH_DURATION
	for fighter in fighters:
		if fighter == null:
			continue
		fighter.set_control_enabled(true)
		if not fighter.knocked_out.is_connected(_on_fighter_knocked_out):
			fighter.knocked_out.connect(_on_fighter_knocked_out)
		if not fighter.state_changed.is_connected(_on_fighter_state_changed):
			fighter.state_changed.connect(_on_fighter_state_changed)
	match_started.emit()
	_push_all_fighter_states()

func _process(delta: float) -> void:
	if not _running:
		return
	_time_left -= delta
	# Only when the displayed second changes; per-frame emits re-laid-out the HUD.
	var whole_seconds := maxi(int(ceil(_time_left)), 0)
	if whole_seconds != _last_emitted_seconds:
		_last_emitted_seconds = whole_seconds
		timer_updated.emit(whole_seconds)
	if _time_left <= 0.0 and _can_resolve_match():
		_end_match(_leader_name())

func _on_fighter_state_changed(fighter: Fighter) -> void:
	_push_fighter_state(fighter)

func _on_fighter_knocked_out(fighter: Fighter) -> void:
	_push_fighter_state(fighter)
	if not _running or not _can_resolve_match():
		return
	var alive_count := 0
	var last_alive: Fighter = null
	for candidate in fighters:
		if candidate and candidate.alive:
			alive_count += 1
			last_alive = candidate
	if alive_count <= 1:
		_end_match(last_alive.fighter_name if last_alive else _leader_name())

func _end_match(winner: String) -> void:
	if not _running or _finished:
		return
	_finished = true
	_running = false
	for fighter in fighters:
		if fighter:
			fighter.set_control_enabled(false)
	GameState.last_winner_name = winner
	match_ended.emit(winner)

func stop_match() -> void:
	_running = false
	for fighter in fighters:
		if fighter:
			fighter.set_control_enabled(false)

func _can_resolve_match() -> bool:
	return not GameState.game_mode.begins_with("network") or not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

## Ranking used both for a timeout win and for post-match placement: surviving
## stocks first, then knockouts scored, then remaining health.
func _score_tuple(fighter: Fighter) -> Array:
	return [fighter.stocks, fighter.knockout_score, fighter.health]

func _is_better(a: Fighter, b: Fighter) -> bool:
	var left := _score_tuple(a)
	var right := _score_tuple(b)
	for i in range(left.size()):
		if left[i] != right[i]:
			return left[i] > right[i]
	return false

func _leader_name() -> String:
	var best: Fighter = null
	for fighter in fighters:
		if fighter == null:
			continue
		if best == null or _is_better(fighter, best):
			best = fighter
	return best.fighter_name if best else "Nobody"

## 1-based finishing position for `fighter`.
func placement_of(fighter: Fighter) -> int:
	if fighter == null:
		return 0
	var position := 1
	for other in fighters:
		if other == null or other == fighter:
			continue
		if _is_better(other, fighter):
			position += 1
	return position

func _push_all_fighter_states() -> void:
	for fighter in fighters:
		_push_fighter_state(fighter)

func _push_fighter_state(fighter: Fighter) -> void:
	if fighter == null:
		return
	var index := fighters.find(fighter)
	if index == -1:
		return
	fighter_updated.emit(
		index,
		fighter.health / Fighter.MAX_HEALTH,
		fighter.stocks,
		fighter.knockout_score,
		fighter.alive
	)
