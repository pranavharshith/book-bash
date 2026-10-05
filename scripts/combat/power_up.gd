class_name PowerUpPickup
extends Area3D
## Host-authoritative power-up pickup for the four effects in the design reference:
## Speed Surge, Power Read, Page Shield, and Triple Tome.
##
## Like `BookPickup`, the node exists on every peer at a stable path so claims can
## be resolved by RPC, and only the host decides who actually gets the effect.

signal collected(fighter: Node3D, power_id: String)

@export var respawn_delay := 16.0
@export var starts_available := true
@export var auto_respawn := true
## Empty means "pick a random effect each time it respawns", which keeps the map
## from becoming a predictable shield farm.
@export var fixed_power_id := ""

var _available := true
var _respawning := false
var _power_id := "speed"
var _bob := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_bob = randf() * TAU
	_power_id = fixed_power_id if fixed_power_id != "" else _random_power()
	_build_visuals()
	_set_available(starts_available)

func _random_power() -> String:
	var keys: Array = GameState.POWER_UPS.keys()
	if keys.is_empty():
		return "speed"
	return String(keys[randi() % keys.size()])

func _build_visuals() -> void:
	for child in get_children():
		if child.name in ["Core", "Halo", "Glow", "Icon"]:
			child.queue_free()
	var definition: Dictionary = GameState.POWER_UPS.get(_power_id, {})
	var color: Color = definition.get("color", Color.WHITE)

	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(0.5, 0.62, 0.16)
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = core_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.roughness = 0.35
	_core.material_override = material
	_core.position = Vector3(0, 0.7, 0)
	add_child(_core)

	var halo_mesh := CylinderMesh.new()
	halo_mesh.top_radius = 0.75
	halo_mesh.bottom_radius = 0.75
	halo_mesh.height = 0.02
	halo_mesh.radial_segments = 22
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = halo_mesh
	var halo_material := StandardMaterial3D.new()
	halo_material.albedo_color = Color(color.r, color.g, color.b, 0.45)
	halo_material.emission_enabled = true
	halo_material.emission = color
	halo_material.emission_energy_multiplier = 1.8
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = halo_material
	_halo.position = Vector3(0, 0.04, 0)
	add_child(_halo)

	var icon := Label3D.new()
	icon.name = "Icon"
	icon.text = String(definition.get("icon", "★"))
	icon.font_size = 64
	icon.pixel_size = 0.004
	icon.outline_size = 12
	icon.modulate = Color(1, 1, 1)
	icon.outline_modulate = Color(0, 0, 0, 0.7)
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.shaded = false
	icon.position = Vector3(0, 1.35, 0)
	add_child(icon)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = color
	_light.light_energy = 1.8
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.8, 0)
	add_child(_light)

func _process(delta: float) -> void:
	if not _available:
		return
	_bob += delta * 2.0
	if _core:
		_core.position.y = 0.7 + sin(_bob) * 0.14
		_core.rotate_y(delta * 2.2)

func power_id() -> String:
	return _power_id

func is_available() -> bool:
	return _available

func set_host_available(value: bool) -> bool:
	if _is_network_client() or _available == value:
		return false
	if value and fixed_power_id == "":
		_power_id = _random_power()
		_build_visuals()
	_set_available(value)
	if _is_networked():
		_sync_availability.rpc(value, _power_id)
	return true

func _on_body_entered(body: Node3D) -> void:
	if not _can_claim(body):
		return
	if _is_network_client():
		var sync := body.get_node_or_null("NetworkSync")
		if sync and sync.is_multiplayer_authority():
			_request_pickup.rpc_id(1, body.get_path())
		return
	_claim(body as Fighter)

func _can_claim(body: Node3D) -> bool:
	if not _available or body == null or not (body is Fighter):
		return false
	var fighter := body as Fighter
	return fighter.control_enabled and fighter.alive and not fighter.is_knocked_out

func _claim(fighter: Fighter) -> void:
	if not _can_claim(fighter):
		return
	var definition: Dictionary = GameState.POWER_UPS.get(_power_id, {})
	_set_available(false)
	fighter.grant_power_up(_power_id, float(definition.get("duration", 8.0)))
	collected.emit(fighter, _power_id)
	if _is_networked():
		_sync_collected.rpc(fighter.get_path(), _power_id, float(definition.get("duration", 8.0)))
	_present_collect(definition.get("color", Color.WHITE))
	if auto_respawn:
		_start_host_respawn()

func _present_collect(color: Color) -> void:
	ImpactVfx.spawn(get_tree().current_scene, global_position + Vector3.UP * 0.8, color, 1.4)
	Audio.play_at("power_up", global_position, -2.0)

func _start_host_respawn() -> void:
	if _respawning:
		return
	_respawning = true
	await get_tree().create_timer(respawn_delay).timeout
	_respawning = false
	if not is_inside_tree():
		return
	if _is_networked() and not multiplayer.is_server():
		return
	set_host_available(true)

func _set_available(value: bool) -> void:
	_available = value
	visible = value
	set_process(value)
	set_deferred("monitoring", value)

func _is_networked() -> bool:
	return GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer()

func _is_network_client() -> bool:
	return _is_networked() and not multiplayer.is_server()

@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(fighter_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var fighter := get_node_or_null(fighter_path) as Fighter
	if fighter == null:
		return
	var sync := fighter.get_node_or_null("NetworkSync")
	if sync == null or sync.owner_peer_id != multiplayer.get_remote_sender_id():
		return
	if fighter.global_position.distance_to(global_position) > 2.4:
		return
	_claim(fighter)

@rpc("authority", "call_remote", "reliable")
func _sync_availability(value: bool, synced_power_id: String) -> void:
	if synced_power_id != _power_id:
		_power_id = synced_power_id
		_build_visuals()
	_set_available(value)

@rpc("authority", "call_remote", "reliable")
func _sync_collected(fighter_path: NodePath, synced_power_id: String, duration: float) -> void:
	_set_available(false)
	var fighter := get_node_or_null(fighter_path) as Fighter
	if fighter:
		fighter.apply_network_power_up(synced_power_id, duration)
	_present_collect(GameState.POWER_UPS.get(synced_power_id, {}).get("color", Color.WHITE))
