class_name ArenaHazards
extends Node3D
## Per-arena hazards. In network matches only the host simulates forces, damage,
## grants, and timers; clients receive the resulting fighter state plus a presentation
## RPC so the visual beat stays in sync.
##
## No hazard can eliminate a fighter by displacement. Arenas are fully enclosed,
## so hazards push, slow, bounce, and chip health instead of removing anyone from
## the world.

@export_enum("sky_library", "classroom_chaos", "ancient_ruins", "tech_tower", "candy_island", "volcano_core")
var arena_id := "sky_library"

## Hazard geometry lives here and `ThemedArenaDecor` builds its visuals from
## these same constants, so what you see is exactly where the hazard acts.
## Sized for the 36 x 32 m arenas.
const SYRUP_CENTRES := [Vector3(-6.0, 0, 6.0), Vector3(6.0, 0, -6.0)]
const SYRUP_RADIUS := 3.0
const GUMDROP_CENTRES := [Vector3(-8.4, 0, 0), Vector3(8.4, 0, 0), Vector3(0, 0, -7.3), Vector3(0, 0, 7.3)]
const GUMDROP_RADIUS := 1.8
const GUMDROP_HEIGHT := 0.6
const GUMDROP_LAUNCH := 11.0
const CONVEYOR_HALF_WIDTH := 2.4
const CONVEYOR_LENGTH := 34.0
const CONVEYOR_ARROW_SPACING := 2.0
const LAVA_START_RADIUS := 17.0
const LAVA_END_RADIUS := 8.0
const RUINS_SHELF_POSITIONS := [Vector3(-10.3, 0.05, 4.0), Vector3(10.3, 0.05, -4.0)]
const CHALKBOARD_DROP_POSITION := Vector3(0, 0.05, -12.4)

var _elapsed := 0.0
var _event_timer := 8.0
var _damage_timer := 0.0
var _conveyor_direction := 1.0
var _conveyor_scroll := 0.0
var _classroom_powerup_expires_at := 0.0

var _decor: ThemedArenaDecor

func _ready() -> void:
	_decor = get_node_or_null("../ArenaDecor") as ThemedArenaDecor

func _physics_process(delta: float) -> void:
	if _is_networked() and not multiplayer.is_server():
		return
	var round_manager := get_node_or_null("../RoundManager") as RoundManager
	if round_manager and not round_manager.is_running():
		return
	_elapsed += delta
	_event_timer -= delta
	_damage_timer -= delta
	var fighters := _fighters()
	for fighter in fighters:
		fighter.movement_multiplier = 1.0
	match arena_id:
		"sky_library": _sky_gust(fighters)
		"classroom_chaos": _classroom_supply()
		"ancient_ruins": _ruins_shelf_collapse(fighters)
		"tech_tower": _tech_conveyor(fighters, delta)
		"candy_island": _candy_island(fighters)
		"volcano_core": _volcano_lava(fighters)

func _fighters() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for node in get_tree().get_nodes_in_group("fighters"):
		if node is Fighter and node.alive and not node.is_knocked_out:
			result.append(node)
	return result

func _is_networked() -> bool:
	return GameState.game_mode.begins_with("network") and multiplayer.has_multiplayer_peer()

# --------------------------------------------------------------------------- #
# Sky Library — page gust
# --------------------------------------------------------------------------- #

## Sweeps everyone toward the centre of the hall. Originally this shoved players
## off the edge; with the arena enclosed it is a positioning disruptor instead.
func _sky_gust(fighters: Array[Fighter]) -> void:
	if _event_timer > 0.0:
		return
	_event_timer = 11.0
	for fighter in fighters:
		var to_centre := Vector3(-fighter.global_position.x, 0.0, -fighter.global_position.z)
		if to_centre.length() < 1.0:
			continue
		fighter.velocity += to_centre.normalized() * 4.2
		fighter.velocity.y = maxf(fighter.velocity.y, 1.6)
	_broadcast_gust()

func _broadcast_gust() -> void:
	if _is_networked():
		_present_gust.rpc()
	else:
		_present_gust()

@rpc("authority", "call_local", "reliable")
func _present_gust() -> void:
	ImpactVfx.spawn(get_tree().current_scene, Vector3(0, 1.6, 0), Color("f4e4bd"), 2.4)
	Audio.play_at("impact_light", Vector3(0, 1.5, 0), -6.0)

# --------------------------------------------------------------------------- #
# Classroom Chaos — chalkboard supply drop
# --------------------------------------------------------------------------- #

func _classroom_supply() -> void:
	var powerup := get_node_or_null("../ChalkboardDrop") as PowerUpPickup
	if powerup and _classroom_powerup_expires_at > 0.0 and _elapsed >= _classroom_powerup_expires_at:
		powerup.set_host_available(false)
		_classroom_powerup_expires_at = 0.0
	if _event_timer > 0.0:
		return
	_event_timer = 13.0
	if powerup and not powerup.is_available() and powerup.set_host_available(true):
		_classroom_powerup_expires_at = _elapsed + 9.0
		_broadcast_chalkboard_reveal()

func _broadcast_chalkboard_reveal() -> void:
	if _is_networked():
		_present_chalkboard_reveal.rpc()
	else:
		_present_chalkboard_reveal()

@rpc("authority", "call_local", "reliable")
func _present_chalkboard_reveal() -> void:
	var chalkboard := _decor.chalkboard() if _decor else null
	if chalkboard:
		var rest_scale := chalkboard.scale
		var tween := chalkboard.create_tween()
		tween.tween_property(chalkboard, "scale", rest_scale * Vector3(1.06, 1.1, 1.0), 0.12)
		tween.tween_property(chalkboard, "scale", rest_scale, 0.28)
	Audio.play_ui("power_up", -3.0)

# --------------------------------------------------------------------------- #
# Ancient Ruins — collapsing shelves
# --------------------------------------------------------------------------- #

func _ruins_shelf_collapse(fighters: Array[Fighter]) -> void:
	if _event_timer > 0.0 or _decor == null or _decor.ruins_shelf_count() == 0:
		return
	_event_timer = 10.0
	var shelf_index := randi_range(0, _decor.ruins_shelf_count() - 1)
	var shelf := _decor.ruins_shelf(shelf_index)
	if shelf == null:
		return
	var fall_direction := Vector3.RIGHT if shelf_index == 0 else Vector3.LEFT
	for fighter in fighters:
		var offset := fighter.global_position - shelf.global_position
		offset.y = 0.0
		var forward_distance := offset.dot(fall_direction)
		var lateral_distance := absf(offset.dot(Vector3.FORWARD))
		if forward_distance >= -0.8 and forward_distance <= 7.0 and lateral_distance <= 2.2:
			fighter.apply_hit(14.0, shelf)
	_broadcast_ruins_collapse(shelf_index)

func _broadcast_ruins_collapse(shelf_index: int) -> void:
	if _is_networked():
		_present_ruins_collapse.rpc(shelf_index)
	else:
		_present_ruins_collapse(shelf_index)

@rpc("authority", "call_local", "reliable")
func _present_ruins_collapse(shelf_index: int) -> void:
	var shelf := _decor.ruins_shelf(shelf_index) if _decor else null
	if shelf == null:
		return
	var rest_rotation := shelf.rotation_degrees
	var collapsed_rotation := rest_rotation
	collapsed_rotation.x += -70.0 if shelf_index == 0 else 70.0
	var tween := shelf.create_tween()
	tween.tween_property(shelf, "rotation_degrees", collapsed_rotation, 0.28).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.5)
	tween.tween_property(shelf, "rotation_degrees", rest_rotation, 0.5)
	ImpactVfx.spawn(get_tree().current_scene, shelf.global_position + Vector3.UP, Color("d3a941"), 1.8)
	Audio.play_at("collapse", shelf.global_position, -2.0)

# --------------------------------------------------------------------------- #
# Tech Tower — conveyor lane
# --------------------------------------------------------------------------- #

func _tech_conveyor(fighters: Array[Fighter], delta: float) -> void:
	if _event_timer <= 0.0:
		_event_timer = 6.5
		_conveyor_direction *= -1.0
		Audio.play_at("impact_metal", Vector3.ZERO, -10.0)
	for fighter in fighters:
		if absf(fighter.global_position.z) < CONVEYOR_HALF_WIDTH and fighter.is_on_floor():
			fighter.velocity.x += _conveyor_direction * 11.0 * delta
	if _decor == null:
		return
	_conveyor_scroll = fposmod(_conveyor_scroll + _conveyor_direction * delta * 3.0, CONVEYOR_ARROW_SPACING)
	var arrows := _decor.conveyor_arrows()
	var span := float(arrows.size()) * CONVEYOR_ARROW_SPACING
	for i in range(arrows.size()):
		var arrow := arrows[i]
		if arrow and is_instance_valid(arrow):
			arrow.position.x = -span * 0.5 + fposmod(float(i) * CONVEYOR_ARROW_SPACING + _conveyor_scroll, span)
			# Arrows point the way the belt is moving.
			arrow.rotation.y = 0.0 if _conveyor_direction > 0.0 else PI

# --------------------------------------------------------------------------- #
# Candy Island — syrup and gumdrops
# --------------------------------------------------------------------------- #

func _candy_island(fighters: Array[Fighter]) -> void:
	for fighter in fighters:
		for centre in SYRUP_CENTRES:
			if Vector2(fighter.global_position.x - centre.x, fighter.global_position.z - centre.z).length() < SYRUP_RADIUS:
				fighter.movement_multiplier = 0.55
		for gumdrop in GUMDROP_CENTRES:
			var offset := Vector2(fighter.global_position.x - gumdrop.x, fighter.global_position.z - gumdrop.z)
			if offset.length() < GUMDROP_RADIUS and fighter.global_position.y < GUMDROP_HEIGHT + 0.6 and fighter.velocity.y <= 0.5:
				fighter.velocity.y = GUMDROP_LAUNCH
				Audio.play_at("impact_soft", fighter.global_position, -8.0)

# --------------------------------------------------------------------------- #
# Volcano Core — shrinking safe zone
# --------------------------------------------------------------------------- #

func _volcano_lava(fighters: Array[Fighter]) -> void:
	var progress := clampf((_elapsed - 22.0) / 70.0, 0.0, 1.0)
	var safe_radius := lerpf(LAVA_START_RADIUS, LAVA_END_RADIUS, progress)
	if _decor:
		var ring := _decor.lava_ring()
		if ring and is_instance_valid(ring):
			# Y stays flattened: `ArenaBuilder.glow_ring` squashes the torus into a
			# floor decal, and restoring Y to 1.0 would pop it back into a donut.
			var ratio := safe_radius / LAVA_START_RADIUS
			ring.scale = Vector3(ratio, 0.06, ratio)
	if _damage_timer > 0.0:
		return
	_damage_timer = 1.1
	for fighter in fighters:
		var flat_distance := Vector2(fighter.global_position.x, fighter.global_position.z).length()
		if flat_distance > safe_radius:
			fighter.apply_hit(8.0, self)
