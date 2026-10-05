class_name BookPickup
extends Area3D
## A host-authoritative, self-respawning book pickup.
##
## Nodes are created deterministically on every peer (see `SpawnDirector`) so their
## paths match for pickup RPCs; only the host grants a book or respawns one.

signal picked_up(fighter: Node3D)

@export var respawn_delay := 3.0
@export var pickup_id := ""
@export var starts_available := true
@export var auto_respawn := true
@export var book_skin_id := "book_classic"

var _available := true
var _respawning := false
var _bob := 0.0
var _model: Node3D
var _halo: MeshInstance3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_model = get_node_or_null("BookModel")
	_bob = randf() * TAU
	if _model:
		GameState.apply_book_style(_model, book_skin_id)
	_build_halo()
	_set_available(starts_available)

## A ground halo makes a small book readable from the chase camera. Without it,
## players simply could not see what they were supposed to run toward.
func _build_halo() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.62
	mesh.bottom_radius = 0.62
	mesh.height = 0.02
	mesh.radial_segments = 20
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = mesh
	var color := GameState.book_color(book_skin_id).lightened(0.35)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.5)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = material
	_halo.position = Vector3(0, 0.03, 0)
	add_child(_halo)

func _process(delta: float) -> void:
	if not _available or _model == null:
		return
	_bob += delta * 2.4
	_model.position.y = 0.35 + sin(_bob) * 0.12
	_model.rotate_y(delta * 1.5)

func is_available() -> bool:
	return _available

func set_host_available(value: bool) -> bool:
	if _is_network_client() or _available == value:
		return false
	_set_available(value)
	if _is_networked():
		_sync_availability.rpc(value)
	return true

func _on_body_entered(body: Node3D) -> void:
	if not _can_claim(body):
		return
	if _is_network_client():
		var sync := body.get_node_or_null("NetworkSync")
		if sync and sync.is_multiplayer_authority():
			_request_pickup.rpc_id(1, body.get_path())
		return
	_claim(body)

func _can_claim(body: Node3D) -> bool:
	return _available and body != null and body.has_method("give_book") and body.can_carry_book()

func _claim(fighter: Fighter) -> void:
	if not _can_claim(fighter):
		return
	_set_available(false)
	fighter.give_book()
	picked_up.emit(fighter)
	ImpactVfx.spawn_pickup_flash(get_tree().current_scene, global_position + Vector3.UP * 0.4, GameState.book_color(book_skin_id).lightened(0.3))
	if _is_networked():
		_sync_availability.rpc(false)
	if auto_respawn:
		_start_host_respawn()

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
	if fighter.global_position.distance_to(global_position) > 2.2:
		return
	_claim(fighter)

@rpc("authority", "call_remote", "reliable")
func _sync_availability(value: bool) -> void:
	_set_available(value)
