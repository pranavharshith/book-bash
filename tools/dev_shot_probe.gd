extends Node
## Development-only screenshot + scripted playtest harness. Not part of gameplay:
## it is inert unless `--bb-shot=` or `--bb-play=` is passed after `--`.
##
##   godot --path . scenes/arenas/SkyLibrary.tscn --resolution 1280x720 \
##       -- --bb-shot=user://shots/sky --bb-times=1.5,4,8 --bb-quit=9
##
## `--bb-play=<scenario>` drives the local fighter through real InputMap actions
## and camera look calls, logging position / grounding / camera metrics, and
## saves a frame at each `shot` step. `--bb-calm` freezes bots so the run is
## repeatable. Scenarios: move, walls, aim, tour.

var _prefix := ""
var _times: Array[float] = []
var _quit_after := -1.0
var _elapsed := 0.0
var _index := 0
var _scenario := ""
var _steps: Array = []
var _step_index := 0
var _held: Array[String] = []
var _log_timer := 0.0
var _calm := false
var _shot_counter := 0
var _max_abs := Vector2.ZERO
var _min_y := 99.0
var _max_y := -99.0
var _min_cam_gap := 99.0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bb-shot="):
			_prefix = argument.trim_prefix("--bb-shot=")
		elif argument.begins_with("--bb-times="):
			for part in argument.trim_prefix("--bb-times=").split(","):
				_times.append(float(part))
		elif argument.begins_with("--bb-quit="):
			_quit_after = float(argument.trim_prefix("--bb-quit="))
		elif argument.begins_with("--bb-play="):
			_scenario = argument.trim_prefix("--bb-play=")
		elif argument == "--bb-calm":
			_calm = true
	if _prefix.is_empty() and _scenario.is_empty():
		set_process(false)
		return
	if not _prefix.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_prefix).get_base_dir())
	_steps = _build_scenario(_scenario)
	print("[probe] armed prefix=", ProjectSettings.globalize_path(_prefix), " times=", _times, " scenario=", _scenario)

func _process(delta: float) -> void:
	_elapsed += delta
	while _index < _times.size() and _elapsed >= _times[_index]:
		await _save_shot("%02d" % _index)
		_index += 1
	if _calm:
		_freeze_bots()
	_run_steps()
	_log_timer -= delta
	if not _scenario.is_empty() and _log_timer <= 0.0:
		_log_timer = 0.25 if _scenario != "bots" else 1.0
		if _scenario == "bots":
			_log_bots()
		else:
			_log_state()
	_track_frame_time(delta)
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		if _frame_count > 0:
			print("[probe] FRAMES avg=%.1fms worst=%.1fms (after 4s warmup, %d frames) spectating=%s" % [
				_frame_sum / _frame_count * 1000.0, _frame_worst * 1000.0, _frame_count,
				str(_rig().is_spectating()) if _rig() else "-"])
		for action in _held:
			_send_action(action, false)
		print("[probe] SUMMARY max|x|=%.2f max|z|=%.2f minY=%.2f maxY=%.2f minCamGap=%.2f" % [_max_abs.x, _max_abs.y, _min_y, _max_y, _min_cam_gap])
		get_tree().quit()

func _save_shot(tag: String) -> void:
	if _prefix.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_prefix, tag]
	image.save_png(path)
	print("[probe] saved ", ProjectSettings.globalize_path(path))

# --------------------------------------------------------------------------- #
# Scenario helpers
# --------------------------------------------------------------------------- #

func _player() -> Fighter:
	for node in get_tree().get_nodes_in_group("fighters"):
		if node is Fighter and (node as Fighter).is_local_player:
			return node
	return null

func _rig() -> MatchCamera:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("CameraRig") as MatchCamera if scene else null

func _freeze_bots() -> void:
	for node in get_tree().get_nodes_in_group("fighters"):
		var fighter := node as Fighter
		if fighter and fighter.is_bot:
			var brain := fighter.get_node_or_null("BotBrain")
			if brain:
				brain.set_physics_process(false)
			fighter.move_axis = Vector2.ZERO

## Steps: [time, op, arg]. ops: press/release action, look (yaw_deg, pitch_deg
## spread over arg2 seconds), shot tag, teleport Vector3, yaw absolute deg.
func _build_scenario(name: String) -> Array:
	match name:
		"move":
			return [
				[3.6, "shot", "spawn"],
				[3.7, "press", "move_forward"], [4.6, "shot", "run_fwd"], [5.2, "release", "move_forward"],
				[5.25, "shot", "stopped"],
				[5.6, "press", "move_back"], [6.4, "shot", "run_back"], [6.8, "release", "move_back"],
				[7.0, "press", "move_right"], [7.6, "shot", "strafe"], [8.0, "release", "move_right"],
				[8.2, "press", "jump"], [8.45, "shot", "jump_apex"], [8.5, "release", "jump"],
				[9.0, "look", Vector2(120, -8), 1.0], [10.2, "shot", "looked"],
				[10.5, "camtoggle", null], [11.2, "shot", "first_person"], [11.4, "camtoggle", null],
				[12.0, "look", Vector2(0, 30), 0.5], [12.7, "shot", "look_up"],
				[12.8, "look", Vector2(0, -70), 0.6], [13.6, "shot", "look_down"],
			]
		"walls":
			# Run into every boundary and corner; the summary checks containment.
			var steps: Array = []
			var t := 3.6
			for yaw in [0.0, 90.0, 180.0, 270.0, 45.0, 135.0, 225.0, 315.0]:
				steps.append([t, "yaw", yaw])
				steps.append([t + 0.05, "press", "move_forward"])
				steps.append([t + 0.2, "press", "jump"])
				steps.append([t + 0.35, "release", "jump"])
				steps.append([t + 3.6, "shot", "wall_%d" % int(yaw)])
				steps.append([t + 3.65, "yaw", yaw + 180.0])
				steps.append([t + 3.7, "shot", "wall_%d_back" % int(yaw)])
				steps.append([t + 3.8, "release", "move_forward"])
				steps.append([t + 3.85, "teleport", Vector3(0, 0.7, 0)])
				t += 4.2
			return steps
		"aim":
			return [
				[3.6, "yaw", 0.0], [3.7, "press", "throw_book"], [4.15, "shot", "charge_half"],
				[4.45, "shot", "charge_full"], [4.5, "release", "throw_book"],
				[4.75, "shot", "book_flight"],
				[5.6, "yaw", 90.0], [5.7, "look", Vector2(0, 14), 0.2], [6.0, "press", "throw_book"], [6.6, "shot", "lob"], [6.7, "release", "throw_book"],
			]
		"spectate":
			# Local player is eliminated: overhead view, follow view, back again.
			return [
				[3.6, "shot", "alive"], [3.8, "forfeit", null],
				[5.8, "shot", "god_eye"], [6.0, "look", Vector2(-90, 0), 0.6], [7.0, "shot", "god_rotated"],
				[7.1, "camtoggle", null], [8.6, "shot", "follow"],
				[8.7, "camtoggle", null], [10.2, "shot", "god_again"],
			]
		"tour":
			# Orbit the camera from several positions for visual review.
			return [
				[3.6, "teleport", Vector3(0, 0.7, 6)], [3.7, "yaw", 0.0], [4.0, "shot", "a_centre_north"],
				[4.1, "yaw", 180.0], [4.4, "shot", "b_centre_south"],
				[4.5, "teleport", Vector3(-10, 0.7, 8)], [4.6, "yaw", -45.0], [4.9, "shot", "c_corner"],
				[5.0, "yaw", 90.0], [5.3, "shot", "d_side"],
				[5.4, "teleport", Vector3(9, 0.7, -8)], [5.5, "yaw", 135.0], [5.8, "shot", "e_corner2"],
				[5.9, "look", Vector2(0, 28), 0.3], [6.4, "shot", "f_sky"],
			]
	return []

var _look_rate := Vector2.ZERO
var _look_until := 0.0

func _run_steps() -> void:
	var rig := _rig()
	if rig and _elapsed < _look_until:
		var dt := get_process_delta_time()
		rig.add_look_input(deg_to_rad(_look_rate.x) * dt, deg_to_rad(_look_rate.y) * dt)
	while _step_index < _steps.size() and _elapsed >= float(_steps[_step_index][0]):
		var step: Array = _steps[_step_index]
		_step_index += 1
		var op := String(step[1])
		match op:
			"press":
				_send_action(String(step[2]), true)
				_held.append(String(step[2]))
			"release":
				_send_action(String(step[2]), false)
				_held.erase(String(step[2]))
			"look":
				var total: Vector2 = step[2]
				var duration := float(step[3]) if step.size() > 3 else 0.5
				_look_rate = total / maxf(duration, 0.01)
				_look_until = _elapsed + duration
			"yaw":
				if rig:
					rig.yaw = deg_to_rad(float(step[2]))
			"camtoggle":
				if rig:
					rig.toggle_mode()
			"teleport":
				var player := _player()
				if player:
					player.global_position = step[2]
					player.velocity = Vector3.ZERO
			"forfeit":
				var victim := _player()
				if victim:
					victim.forfeit()
			"shot":
				_shot_counter += 1
				_save_shot("%02d_%s" % [_shot_counter, String(step[2])])

var _frame_sum := 0.0
var _frame_worst := 0.0
var _frame_count := 0

func _track_frame_time(delta: float) -> void:
	if _elapsed < 4.0:
		return
	_frame_sum += delta
	_frame_worst = maxf(_frame_worst, delta)
	_frame_count += 1

var _bot_last: Dictionary = {}
var _bot_moved: Dictionary = {}
var _bot_throws: Dictionary = {}

func _log_bots() -> void:
	var line := "[probe] t=%.0f" % _elapsed
	for node in get_tree().get_nodes_in_group("fighters"):
		var f := node as Fighter
		if f == null or not f.is_bot:
			continue
		var brain := f.get_node_or_null("BotBrain")
		var state := str(brain._state) if brain else "-"
		var last: Vector3 = _bot_last.get(f.name, f.global_position)
		_bot_moved[f.name] = float(_bot_moved.get(f.name, 0.0)) + Vector2(f.global_position.x - last.x, f.global_position.z - last.z).length()
		_bot_last[f.name] = f.global_position
		line += " | %s s=%s (%.1f,%.1f) hp=%d b=%d" % [f.name.trim_prefix("Fighter_"), state, f.global_position.x, f.global_position.z, int(f.health), f.books_held]
	print(line)
	if _elapsed > 3.0:
		var moved := ""
		for k in _bot_moved:
			moved += " %s=%.0fm" % [k, _bot_moved[k]]
		print("[probe] distance travelled:", moved)

## Real InputEvents, so `_unhandled_input` handlers fire exactly as for a key press.
func _send_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func _log_state() -> void:
	var player := _player()
	var rig := _rig()
	if player == null:
		return
	var p := player.global_position
	_max_abs.x = maxf(_max_abs.x, absf(p.x))
	_max_abs.y = maxf(_max_abs.y, absf(p.z))
	if player.control_enabled:
		_min_y = minf(_min_y, p.y)
		_max_y = maxf(_max_y, p.y)
	var cam_info := ""
	if rig and rig.camera():
		var cam := rig.camera().global_position
		var gap := cam.distance_to(p + Vector3.UP * 1.55)
		_min_cam_gap = minf(_min_cam_gap, gap)
		cam_info = " cam=(%.2f,%.2f,%.2f) boom=%.2f yaw=%.0f pitch=%.0f" % [cam.x, cam.y, cam.z, gap, rad_to_deg(rig.yaw), rad_to_deg(rig.pitch)]
	print("[probe] t=%.2f pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) floor=%s ctrl=%s books=%d charge=%.2f%s" % [
		_elapsed, p.x, p.y, p.z, player.velocity.x, player.velocity.y, player.velocity.z,
		player.is_on_floor(), player.control_enabled, player.books_held, player.charge_amount, cam_info])
