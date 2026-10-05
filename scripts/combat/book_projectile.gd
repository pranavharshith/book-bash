class_name BookProjectile
extends Area3D
## Gravity-arced thrown book with swept collision.
##
## Movement is integrated manually and resolved with a raycast along the frame's
## travel segment. At 23 m/s a 60 Hz Area3D overlap check tunnels straight through
## a 0.9 m-wide fighter, so relying on `body_entered` alone loses hits.

signal hit_fighter(fighter: Node3D, damage: float)

@export var fall_gravity := 14.0
@export var spin_speed := 14.0
@export var lifetime := 5.0

var velocity := Vector3.ZERO
var thrown_by: Node3D = null
var hit_damage := 16.0
var book_skin_id := "book_classic"
var trail_id := "trail_paper"

var _age := 0.0
var _spent := false
var _launched := false

@onready var _mesh: Node3D = get_node_or_null("BookMesh")

func configure_cosmetics(book_id: String, selected_trail_id: String) -> void:
	book_skin_id = book_id
	trail_id = selected_trail_id

func _ready() -> void:
	if _mesh:
		GameState.apply_book_style(_mesh, book_skin_id)
	ImpactVfx.add_trail(self, trail_id)

const HIT_MASK := 3          # world + fighters
const SIM_STEP := 1.0 / 60.0  # matches the physics tick

var _origin := Vector3.ZERO
var _launch_velocity := Vector3.ZERO

# --------------------------------------------------------------------------- #
# Shared ballistic model. The flying book, the aim preview, and the landing
# marker all use these functions, so the preview is exactly where the book goes.
# --------------------------------------------------------------------------- #

## Closed-form position, so frame timing cannot drift the book off its preview.
static func position_at(origin: Vector3, launch_velocity: Vector3, gravity: float, t: float) -> Vector3:
	return origin + launch_velocity * t + Vector3(0.0, -0.5 * gravity * t * t, 0.0)

static func velocity_at(launch_velocity: Vector3, gravity: float, t: float) -> Vector3:
	return launch_velocity + Vector3(0.0, -gravity * t, 0.0)

## Launch velocity with a fixed horizontal speed whose vertical component makes
## the arc pass through `target`. Vertical speed is capped, so absurd targets
## (straight up at the sky) produce a lob rather than a rocket.
static func solve_launch(origin: Vector3, target: Vector3, horizontal_speed: float, gravity: float, max_vertical: float) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var distance := flat.length()
	if distance < 0.05:
		return Vector3(0.0, 2.0, 0.0)
	var t := distance / maxf(horizontal_speed, 0.1)
	var vy := ((target.y - origin.y) + 0.5 * gravity * t * t) / t
	vy = clampf(vy, -max_vertical, max_vertical)
	return flat / distance * horizontal_speed + Vector3.UP * vy

## Steps the shared model with the same per-tick ray sweeps the live projectile
## uses. Returns {"points": PackedVector3Array, "hit": bool, "position": Vector3,
## "normal": Vector3, "collider": Object}.
static func simulate(space: PhysicsDirectSpaceState3D, origin: Vector3, launch_velocity: Vector3, gravity: float, exclude: Array[RID], max_time: float = 3.0) -> Dictionary:
	var points := PackedVector3Array()
	points.append(origin)
	var previous := origin
	var t := 0.0
	while t < max_time:
		t += SIM_STEP
		var next := position_at(origin, launch_velocity, gravity, t)
		var query := PhysicsRayQueryParameters3D.create(previous, next, HIT_MASK)
		query.collide_with_areas = false
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if not result.is_empty():
			points.append(result["position"])
			return {"points": points, "hit": true, "position": result["position"], "normal": result["normal"], "collider": result["collider"]}
		points.append(next)
		previous = next
		if next.y < -4.0:
			break
	return {"points": points, "hit": false, "position": previous, "normal": Vector3.UP, "collider": null}

## Legacy entry point: horizontal direction, speed, and an upward arc speed.
func launch(from: Vector3, direction: Vector3, speed: float, arc: float, owner_node: Node3D, damage: float) -> void:
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length() < 0.001:
		flat_direction = Vector3.FORWARD
	launch_with_velocity(from, flat_direction.normalized() * speed + Vector3.UP * arc, owner_node, damage)

func launch_with_velocity(from: Vector3, launch_velocity: Vector3, owner_node: Node3D, damage: float) -> void:
	global_position = from
	_origin = from
	_launch_velocity = launch_velocity
	velocity = launch_velocity
	thrown_by = owner_node
	hit_damage = damage
	_age = 0.0
	monitoring = true
	_launched = true
	_notify_incoming_bots()

func _physics_process(delta: float) -> void:
	if _spent or not _launched:
		return
	var previous_age := _age
	_age += delta
	if _age > lifetime:
		_despawn()
		return
	var from := position_at(_origin, _launch_velocity, fall_gravity, previous_age)
	var to := position_at(_origin, _launch_velocity, fall_gravity, _age)
	velocity = velocity_at(_launch_velocity, fall_gravity, _age)
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	if thrown_by is CollisionObject3D:
		query.exclude.append((thrown_by as CollisionObject3D).get_rid())
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		global_position = result.get("position", to)
		_handle_collision(result.get("collider"))
		return
	global_position = to
	if _mesh:
		_mesh.rotate_x(spin_speed * delta)
	if global_position.y < -4.0:
		_despawn()

## Lets bots react to a book already in flight toward them, which is what makes
## their dodges look deliberate instead of random.
func _notify_incoming_bots() -> void:
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() < 0.01:
		return
	var direction := flat_velocity.normalized()
	for node in get_tree().get_nodes_in_group("fighters"):
		if node == thrown_by or not (node is Fighter):
			continue
		var fighter := node as Fighter
		if not fighter.alive or not fighter.is_bot:
			continue
		var offset := fighter.global_position - global_position
		offset.y = 0.0
		var forward_distance := offset.dot(direction)
		if forward_distance <= 0.0 or forward_distance > 13.0:
			continue
		var lateral_distance := (offset - direction * forward_distance).length()
		if lateral_distance < 1.7:
			var brain := fighter.get_node_or_null("BotBrain")
			if brain and brain.has_method("on_incoming_threat"):
				brain.call_deferred("on_incoming_threat")

func _on_body_entered(body: Node3D) -> void:
	_handle_collision(body)

func _on_area_entered(area: Area3D) -> void:
	_handle_collision(area)

func _handle_collision(collider: Variant) -> void:
	if _spent or collider == null or collider == thrown_by:
		return
	var node := collider as Node
	if node == null:
		return
	var hit_target: Node = node
	if not hit_target.has_method("apply_hit") and hit_target.get_parent() and hit_target.get_parent().has_method("apply_hit"):
		hit_target = hit_target.get_parent()
	if hit_target == thrown_by:
		return
	_spent = true
	var book_color := GameState.book_color(book_skin_id).lightened(0.25)
	if hit_target.has_method("apply_hit"):
		hit_target.apply_hit(hit_damage, self)
		hit_fighter.emit(hit_target, hit_damage)
		ImpactVfx.spawn(get_tree().current_scene, global_position, book_color, 1.2)
		Audio.play_at("impact_body", global_position, -2.0)
	else:
		ImpactVfx.spawn(get_tree().current_scene, global_position, book_color, 0.6)
		Audio.play_at("impact_wood", global_position, -9.0)
	queue_free()

func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()
