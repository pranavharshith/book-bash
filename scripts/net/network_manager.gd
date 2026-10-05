extends Node
## ENet lobby and match coordinator for 2–6 players. A host can run locally,
## across LAN, or from a reachable public/dedicated UDP endpoint.

signal status_changed(text: String)
signal players_changed(players: Dictionary)
signal network_match_ended(winner_name: String)
signal match_peer_disconnected(peer_id: int)
signal host_connection_lost()

const DEFAULT_PORT := 24567
const MAX_CLIENTS := 5

var players: Dictionary = {}
var status_text := "Offline"
var match_active := false
var _peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	if "--book-bash-server" in args:
		host_game(DEFAULT_PORT)
		if "--book-bash-autostart" in args:
			_auto_start_match()
	else:
		for argument in args:
			if argument.begins_with("--book-bash-connect="):
				join_game(argument.trim_prefix("--book-bash-connect="), DEFAULT_PORT)
				break

func _auto_start_match() -> void:
	var wait_seconds := 30
	while wait_seconds > 0 and players.size() < 2:
		await get_tree().create_timer(1.0).timeout
		wait_seconds -= 1
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		start_match()

func host_game(port: int = DEFAULT_PORT) -> bool:
	disconnect_game()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_set_status("Host failed: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = _peer
	players = {1: _make_player_data(1)}
	players_changed.emit(players)
	_set_status("Hosting up to %d players on UDP %d" % [GameState.MAX_FIGHTERS, port])
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if address.is_empty():
		address = "127.0.0.1"
	disconnect_game()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		_set_status("Join failed: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = _peer
	_set_status("Connecting to %s:%d…" % [address, port])
	return true

func disconnect_game() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	players.clear()
	match_active = false
	GameState.network_roster.clear()
	if status_text != "Offline":
		_set_status("Offline")

func start_match() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		_set_status("Only the host can start the match")
		return
	var roster: Array = []
	var colors := [Color(0.30, 0.62, 1.00), Color(1.00, 0.32, 0.30), Color(0.36, 0.88, 0.42), Color(0.72, 0.42, 1.00), Color(1.00, 0.62, 0.26), Color(0.24, 0.84, 0.88)]
	var models := [
		"res://assets/models/characters/player_blue.glb",
		"res://assets/models/characters/bot_red.glb",
		"res://assets/models/characters/bot_green.glb",
		"res://assets/models/characters/bot_purple.glb",
		"res://assets/models/characters/bot_red.glb",
		"res://assets/models/characters/bot_green.glb",
	]
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	for i in range(mini(peer_ids.size(), GameState.MAX_FIGHTERS)):
		var peer_id: int = peer_ids[i]
		var data: Dictionary = players[peer_id]
		roster.append({"name": data.get("name", "Player"), "color": colors[i], "model": models[i], "is_bot": false, "peer_id": peer_id, "cosmetics": data.get("cosmetics", {})})
	while roster.size() < GameState.MAX_FIGHTERS:
		var bot_index := roster.size()
		var bot: Dictionary = GameState.ROSTER[clampi(bot_index, 1, GameState.ROSTER.size() - 1)].duplicate(true)
		bot["peer_id"] = 0
		bot["cosmetics"] = {"book": "book_classic", "hat": "hat_none", "trail": "trail_paper", "emote": "emote_wave"}
		roster.append(bot)
	match_active = true
	_begin_network_match.rpc(roster, GameState.get_selected_arena_scene())

func _make_player_data(peer_id: int) -> Dictionary:
	return {"peer_id": peer_id, "name": GameState.profile.get("player_name", "Reader").left(18), "cosmetics": GameState.get_equipped_cosmetics()}

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_set_status("Peer %d connected — registering…" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var was_in_match := GameState.game_mode.begins_with("network") and not GameState.network_roster.is_empty()
	players.erase(peer_id)
	players_changed.emit(players)
	if was_in_match and multiplayer.is_server():
		match_peer_disconnected.emit(peer_id)
	_set_status("Player left — %d connected" % players.size())

func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, GameState.profile.get("player_name", "Reader").left(18), GameState.get_equipped_cosmetics())
	_set_status("Connected — waiting for host")

func _on_connection_failed() -> void:
	_set_status("Connection failed. Check address, UDP port, and firewall.")
	disconnect_game()

func _on_server_disconnected() -> void:
	var was_in_match := GameState.game_mode.begins_with("network") and not GameState.network_roster.is_empty()
	_set_status("Host disconnected")
	if was_in_match:
		host_connection_lost.emit()
	disconnect_game()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String, cosmetics: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if match_active or players.size() >= GameState.MAX_FIGHTERS:
		_reject_full_lobby.rpc_id(peer_id)
		return
	players[peer_id] = {"peer_id": peer_id, "name": player_name.strip_edges().left(18) if not player_name.strip_edges().is_empty() else "Player %d" % peer_id, "cosmetics": cosmetics.duplicate(true)}
	_sync_players.rpc(players)
	_sync_players(players)
	_set_status("Lobby ready — %d/%d human player(s)" % [players.size(), GameState.MAX_FIGHTERS])

@rpc("authority", "call_remote", "reliable")
func _reject_full_lobby() -> void:
	_set_status("This match is full (maximum %d players)." % GameState.MAX_FIGHTERS)
	disconnect_game()

@rpc("authority", "call_remote", "reliable")
func _sync_players(server_players: Dictionary) -> void:
	players = server_players.duplicate(true)
	players_changed.emit(players)
	_set_status("Connected — %d/%d human player(s), host can start" % [players.size(), GameState.MAX_FIGHTERS])

@rpc("authority", "call_local", "reliable")
func _begin_network_match(roster: Array, scene_path: String) -> void:
	GameState.game_mode = "network"
	GameState.network_roster = roster.duplicate(true)
	_set_status("Starting match…")
	LoadingScreen.go(get_tree(), scene_path)

func broadcast_match_result(winner_name: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_receive_match_result.rpc(winner_name)

@rpc("authority", "call_remote", "reliable")
func _receive_match_result(winner_name: String) -> void:
	network_match_ended.emit(winner_name)

func _set_status(text: String) -> void:
	status_text = text
	print("[Network] ", text)
	status_changed.emit(text)
