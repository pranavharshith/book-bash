class_name GameManager
extends Node3D
## Match orchestration for local bot matches and 2–6-player ENet games.
##
## Owns fighter spawning, camera hand-off, HUD wiring, and the post-match reward
## flow. Combat rules live on `Fighter`; match phase lives on `RoundManager`.

const FIGHTER_SCENE := preload("res://scenes/characters/PlayerCharacter.tscn")
const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const SHAKE_ON_HIT := 0.45
const SHAKE_ON_KO := 0.8

@onready var _fighters_root: Node3D = $Fighters
@onready var _camera_rig: MatchCamera = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _round_manager: RoundManager = $RoundManager
@onready var _arena_decor: ThemedArenaDecor = $ArenaDecor
@onready var _spawn_director: SpawnDirector = $SpawnDirector

var _hud: MatchHud
var _fighters: Array[Fighter] = []
var _player_fighter: Fighter
var _player_input: PlayerInputMobile
var _match_finishing := false
var _handling_network_failure := false

func _ready() -> void:
	if GameState.game_mode.begins_with("network"):
		if not NetworkManager.network_match_ended.is_connected(_on_network_match_ended):
			NetworkManager.network_match_ended.connect(_on_network_match_ended)
		if not NetworkManager.match_peer_disconnected.is_connected(_on_network_peer_disconnected):
			NetworkManager.match_peer_disconnected.connect(_on_network_peer_disconnected)
		if not NetworkManager.host_connection_lost.is_connected(_on_host_connection_lost):
			NetworkManager.host_connection_lost.connect(_on_host_connection_lost)
	_camera_rig.setup(_camera)
	if _arena_decor:
		_camera_rig.arena_half_extents = _arena_decor.half_extents()
		_camera_rig.ceiling_height = _arena_decor.ceiling_height()
	_spawn_fighters()
	_setup_hud()
	_setup_round_manager()
	_camera_rig.spectating_changed.connect(_on_spectating_changed)
	_camera_rig.spectator_view_changed.connect(_on_spectator_view_changed)
	_camera_rig.track(_fighters, _player_fighter)
	_camera_rig.snap()
	_round_manager.start_countdown(3)

# --------------------------------------------------------------------------- #
# Spawning
# --------------------------------------------------------------------------- #

func _spawn_positions(count: int) -> Array[Vector3]:
	var authored := _spawn_director.fighter_spawn_points() if _spawn_director else [] as Array[Vector3]
	var positions: Array[Vector3] = []
	if authored.size() >= count:
		# Spread the used markers across the authored set so a 3-player match does
		# not cram everyone into three adjacent corners.
		var step := float(authored.size()) / float(count)
		for i in range(count):
			positions.append(authored[int(floor(i * step)) % authored.size()])
		return positions
	var radius := 7.6
	for i in range(count):
		var angle := TAU * float(i) / float(maxi(count, 1))
		positions.append(Vector3(sin(angle) * radius, 0.6, cos(angle) * radius))
	return positions

func _spawn_fighters() -> void:
	var roster: Array = GameState.get_active_roster()
	var count := mini(roster.size(), GameState.MAX_FIGHTERS)
	var positions := _spawn_positions(count)
	var networked := GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer()
	var difficulty := GameState.difficulty_settings()

	for i in range(count):
		var entry: Dictionary = roster[i]
		var fighter := FIGHTER_SCENE.instantiate() as Fighter
		fighter.fighter_name = String(entry.get("name", "Fighter"))
		fighter.fighter_color = entry.get("color", GameState.ROSTER_COLORS[i % GameState.ROSTER_COLORS.size()])
		fighter.is_bot = bool(entry.get("is_bot", true))
		fighter.model_path = String(entry.get("model", ""))
		fighter.cosmetics = entry.get("cosmetics", {})
		fighter.name = "Fighter_%d" % i
		_fighters_root.add_child(fighter)

		var spawn_position: Vector3 = positions[i]
		spawn_position.y = maxf(spawn_position.y, 0.6)
		fighter.respawn_position = spawn_position
		fighter.global_position = spawn_position
		if _arena_decor:
			fighter.arena_bounds = _arena_decor.half_extents()
		fighter.aim_direction = Vector3(-spawn_position.x, 0.0, -spawn_position.z).normalized()

		var owner_peer_id := int(entry.get("peer_id", 1))
		if fighter.is_bot:
			if not networked or multiplayer.is_server():
				var brain := BotBrain.new()
				brain.name = "BotBrain"
				brain.fighter_path = NodePath("..")
				fighter.add_child(brain)
				brain.configure(difficulty)
			owner_peer_id = 1
		elif not networked or owner_peer_id == multiplayer.get_unique_id():
			_player_fighter = fighter
			fighter.mark_as_local_player()
			var input := PlayerInputMobile.new()
			input.name = "PlayerInput"
			input.fighter_path = NodePath("..")
			fighter.add_child(input)
			input.set_camera(_camera, _camera_rig)
			_player_input = input
		if networked:
			var sync := NetworkFighterSync.new()
			sync.name = "NetworkSync"
			sync.fighter_path = NodePath("..")
			sync.owner_peer_id = owner_peer_id
			fighter.add_child(sync)

		fighter.hit_taken.connect(_on_any_fighter_hit.bind(fighter))
		fighter.knocked_out.connect(_on_any_fighter_ko)
		fighter.damage_dealt.connect(_on_damage_dealt)
		_fighters.append(fighter)

# --------------------------------------------------------------------------- #
# Presentation
# --------------------------------------------------------------------------- #

## Only events that happen *to you* shake the view. Shaking for every hit across
## a six-player arena made the third-person camera constantly jitter.
func _on_any_fighter_hit(_remaining: float, fighter: Fighter) -> void:
	if fighter == _player_fighter:
		_camera_rig.add_shake(SHAKE_ON_HIT)

func _on_any_fighter_ko(fighter: Fighter) -> void:
	if fighter == _player_fighter:
		_camera_rig.add_shake(SHAKE_ON_KO)
	if _hud == null or fighter == null:
		return
	if fighter.stocks > 0:
		_hud.push_feed("%s was knocked down" % fighter.fighter_name, fighter.fighter_color)
	else:
		_hud.push_feed("%s is OUT" % fighter.fighter_name, Color(1, 0.45, 0.4))
	Audio.play_at("ko", fighter.global_position, -3.0)

func _on_damage_dealt(target: Fighter, amount: float, world_position: Vector3) -> void:
	ImpactVfx.spawn_damage_number(self, world_position, amount, Color(1, 0.9, 0.45) if target != _player_fighter else Color(1, 0.5, 0.45))

# --------------------------------------------------------------------------- #
# Spectating (local player eliminated)
# --------------------------------------------------------------------------- #

func _on_spectating_changed(active: bool) -> void:
	if _hud:
		_hud.set_spectating(active, _camera_rig.is_overhead())
	if not active and _arena_decor:
		_arena_decor.set_overhead_view(false)

func _on_spectator_view_changed(overhead: bool) -> void:
	# Interior ceilings and fog only get out of the way for the overhead camera.
	if _arena_decor:
		_arena_decor.set_overhead_view(overhead)
	if _hud:
		_hud.set_spectating(true, overhead)

# --------------------------------------------------------------------------- #
# HUD
# --------------------------------------------------------------------------- #

func _setup_hud() -> void:
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	# Read the name from the arena itself rather than the saved selection so a
	# directly-launched scene (dev runs, deep links) still labels itself correctly.
	var arena_name := String(GameState.ARENAS.get(GameState.selected_arena, {}).get("name", "Arena"))
	if _arena_decor:
		arena_name = String(_arena_decor.theme().get("name", arena_name))
	_hud.set_arena_name(arena_name)
	_hud.settings_pressed.connect(_on_settings_pressed)
	if _player_input:
		_player_input.bind_hud(_hud)
	if _player_fighter:
		_player_fighter.ammo_changed.connect(_hud.set_ammo)
		_player_fighter.power_up_changed.connect(_hud.set_power_up)
		_hud.set_ammo(_player_fighter.books_held)
	else:
		# Spectating (local player already eliminated in a network match).
		_hud.set_ammo(0)

func _process(_delta: float) -> void:
	if _hud and _player_fighter and is_instance_valid(_player_fighter):
		_hud.set_power_up(_player_fighter.active_power_up(), _player_fighter.active_power_up_seconds())

# --------------------------------------------------------------------------- #
# Round wiring
# --------------------------------------------------------------------------- #

func _setup_round_manager() -> void:
	_round_manager.fighters.clear()
	for fighter in _fighters:
		_round_manager.fighters.append(fighter)
	_round_manager.timer_updated.connect(_on_timer_updated)
	_round_manager.fighter_updated.connect(_on_fighter_updated)
	_round_manager.countdown_tick.connect(_on_countdown_tick)
	_round_manager.match_started.connect(_on_match_started)
	_round_manager.match_ended.connect(_on_match_ended)
	for i in range(_fighters.size()):
		var fighter := _fighters[i]
		_hud.configure_slot(i, fighter.fighter_color, fighter.fighter_name, fighter == _player_fighter)
		_hud.set_player_slot(i, 1.0, fighter.stocks, 0, true)
	for i in range(_fighters.size(), GameState.MAX_FIGHTERS):
		_hud.hide_slot(i)
	_hud.set_timer(int(GameState.MATCH_DURATION))
	_hud.bind_fighters(_fighters, _player_fighter)

func _on_countdown_tick(seconds_left: int) -> void:
	if seconds_left > 0:
		_hud.show_banner(str(seconds_left), 0.9)
		Audio.play_ui("countdown", -4.0)
	else:
		_hud.show_banner("GO!", 0.8)
		Audio.play_ui("go", -3.0)

func _on_match_started() -> void:
	_hud.push_feed("First to survive wins. Grab books, land hits.", Color(1, 0.9, 0.6))

func _on_timer_updated(seconds_left: int) -> void:
	_hud.set_timer(seconds_left)

func _on_fighter_updated(index: int, health_ratio: float, stocks: int, knockouts: int, is_active: bool) -> void:
	_hud.set_player_slot(index, health_ratio, stocks, knockouts, is_active)

# --------------------------------------------------------------------------- #
# Match resolution
# --------------------------------------------------------------------------- #

func _on_match_ended(winner_name: String) -> void:
	if GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		NetworkManager.broadcast_match_result(winner_name)
	_finish_match(winner_name)

func _on_network_match_ended(winner_name: String) -> void:
	_finish_match(winner_name)

func _on_network_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or _match_finishing:
		return
	for fighter in _fighters:
		var sync := fighter.get_node_or_null("NetworkSync") as NetworkFighterSync
		if sync and not fighter.is_bot and sync.owner_peer_id == peer_id:
			fighter.forfeit()
			_hud.push_feed("%s left the match" % fighter.fighter_name, Color(1, 0.7, 0.4))
			break

func _on_host_connection_lost() -> void:
	if _handling_network_failure or _match_finishing:
		return
	_handling_network_failure = true
	_round_manager.stop_match()
	_hud.show_banner("HOST DISCONNECTED", 2.5)
	await get_tree().create_timer(2.5).timeout
	_return_to_lobby()

func _finish_match(winner_name: String) -> void:
	if _match_finishing:
		return
	_match_finishing = true
	_round_manager.stop_match()
	GameState.last_winner_name = winner_name
	if _player_input:
		_player_input.release_mouse()

	var local_name := _player_fighter.fighter_name if _player_fighter else ""
	var won := winner_name == local_name and _player_fighter != null
	if won:
		_player_fighter.play_equipped_emote()
		Audio.play_ui("victory", -2.0)

	var knockouts := _player_fighter.knockout_score if _player_fighter else 0
	var placement := _round_manager.placement_of(_player_fighter) if _player_fighter else 0
	var rewards: Dictionary = GameState.complete_local_match(won, knockouts, placement, _fighters.size())

	var headline := "%s WINS!" % winner_name
	if rewards.get("saved", false):
		_hud.show_banner("%s\n+%d COINS   +%d XP" % [headline, rewards.get("coins", 0), rewards.get("xp", 0)], 4.0)
		_hud.push_feed("Placed #%d of %d  •  %d knockouts" % [placement, _fighters.size(), knockouts], Color(1, 0.92, 0.6))
	else:
		_hud.show_banner("%s\nResults could not be saved." % headline, 4.0)
	await get_tree().create_timer(4.0).timeout
	_return_to_lobby()

func _on_settings_pressed() -> void:
	_round_manager.stop_match()
	Audio.play_ui("back")
	_return_to_lobby()

func _return_to_lobby() -> void:
	if GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer():
		NetworkManager.disconnect_game()
	GameState.game_mode = "bots"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")
