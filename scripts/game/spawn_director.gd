class_name SpawnDirector
extends Node
## Creates the book and power-up pickups for a match.
##
## Placement is generated in code rather than hand-authored per arena so all six
## maps stay consistent, but it is fully deterministic: identical geometry plus the
## same node names means every network peer builds the same pickup set at the same
## NodePaths, which is what the pickup RPCs rely on. Availability and claims remain
## host-authoritative.

@export var book_pickup_scene: PackedScene
@export var power_up_scene: PackedScene
@export var fighter_spawns_path: NodePath = NodePath("../SpawnPoints")
@export var book_count := 8
@export var power_up_count := 2
## Classroom Chaos hides an extra drop behind the chalkboard; the hazard script
## reveals it on a timer and expects to find it at `../ChalkboardDrop`.
@export var chalkboard_drop := false

## Pickup rings are ellipses matching the 28 x 24 room. Books sit on an outer
## ring (between spawns and cover, a short run from each start) and an inner ring
## that pulls fights toward the open centre; power-ups sit in the mid ring.
const BOOK_OUTER := Vector2(11.6, 9.8)
const BOOK_INNER := Vector2(5.6, 4.8)
const POWER_RING := Vector2(8.5, 7.2)
const CLEARANCE_RADIUS := 0.6
const BOUNDS := Vector2(16.6, 14.6)

var _placed_books: Array[BookPickup] = []
var _placed_power_ups: Array[PowerUpPickup] = []

func _ready() -> void:
	# One physics frame so the arena's generated static bodies are queryable and
	# pickups can be nudged out of props deterministically.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_spawn_books()
	_spawn_power_ups()
	if chalkboard_drop:
		_spawn_chalkboard_drop()

func fighter_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var container := get_node_or_null(fighter_spawns_path)
	if container:
		for child in container.get_children():
			if child is Node3D:
				points.append((child as Node3D).position)
	return points

func _spawn_books() -> void:
	if book_pickup_scene == null:
		return
	var skins := ["book_classic", "book_flame", "book_frost", "book_gold"]
	for i in range(book_count):
		var outer := i % 2 == 0
		var ring := BOOK_OUTER if outer else BOOK_INNER
		var angle := TAU * float(i) / float(maxi(book_count, 1)) + (PI / 8.0 if outer else PI / float(maxi(book_count, 1)) + PI / 4.0)
		var position := _clear_position(Vector3(sin(angle) * ring.x, 0.0, cos(angle) * ring.y))
		var pickup := book_pickup_scene.instantiate() as BookPickup
		if pickup == null:
			return
		pickup.name = "Book_%d" % i
		pickup.pickup_id = pickup.name
		pickup.book_skin_id = skins[i % skins.size()]
		add_child(pickup)
		pickup.position = position
		pickup.add_to_group("book_pickups")
		_placed_books.append(pickup)

func _spawn_power_ups() -> void:
	if power_up_scene == null:
		return
	for i in range(power_up_count):
		var angle := PI * 0.5 + TAU * float(i) / float(maxi(power_up_count, 1))
		var position := _clear_position(Vector3(sin(angle) * POWER_RING.x, 0.0, cos(angle) * POWER_RING.y))
		var pickup := power_up_scene.instantiate() as PowerUpPickup
		if pickup == null:
			return
		pickup.name = "Power_%d" % i
		add_child(pickup)
		pickup.position = position
		pickup.add_to_group("power_ups")
		_placed_power_ups.append(pickup)

func _spawn_chalkboard_drop() -> void:
	if power_up_scene == null:
		return
	var arena := get_parent()
	if arena == null or arena.has_node("ChalkboardDrop"):
		return
	var pickup := power_up_scene.instantiate() as PowerUpPickup
	if pickup == null:
		return
	pickup.name = "ChalkboardDrop"
	pickup.starts_available = false
	pickup.auto_respawn = false
	arena.add_child(pickup)
	pickup.position = Vector3(0, 0.1, -13.2)
	pickup.add_to_group("power_ups")

## Walks a short deterministic search outward until the spot is not inside arena
## geometry, so a generated pickup never ends up buried in a bookcase.
func _clear_position(candidate: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state if get_viewport() else null
	if space == null:
		return candidate + Vector3.UP * 0.1
	var shape := SphereShape3D.new()
	shape.radius = CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	var offsets: Array[Vector3] = [Vector3.ZERO]
	for step in [1.2, 2.4, 3.6]:
		for angle_index in range(8):
			var angle := TAU * float(angle_index) / 8.0
			offsets.append(Vector3(sin(angle) * step, 0.0, cos(angle) * step))
	for offset in offsets:
		var probe := candidate + offset
		probe.x = clampf(probe.x, -BOUNDS.x, BOUNDS.x)
		probe.z = clampf(probe.z, -BOUNDS.y, BOUNDS.y)
		query.transform = Transform3D(Basis.IDENTITY, probe + Vector3.UP * 0.7)
		if space.intersect_shape(query, 1).is_empty():
			return probe + Vector3.UP * 0.1
	return candidate + Vector3.UP * 0.1
