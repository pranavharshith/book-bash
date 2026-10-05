class_name Crosshair
extends Control
## Centre-screen reticle. The crosshair is the aim point: throws are solved to
## land where it points. Turns red when aim assist has locked an opponent and
## tightens while charging, so the player can feel the throw getting stronger.

var locked := false
var charging := false
var armed := true
var charge := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(is_locked: bool, is_charging: bool, has_ammo: bool, charge_ratio: float) -> void:
	if is_locked == locked and is_charging == charging and has_ammo == armed and is_equal_approx(charge_ratio, charge):
		return
	locked = is_locked
	charging = is_charging
	armed = has_ammo
	charge = charge_ratio
	queue_redraw()

func _draw() -> void:
	var centre := size * 0.5
	var scale := clampf(minf(get_viewport_rect().size.x, get_viewport_rect().size.y) / 720.0, 0.75, 1.6)
	var color := Color(1.0, 0.35, 0.3, 0.95) if locked else Color(1, 1, 1, 0.9 if armed else 0.4)
	var shadow := Color(0, 0, 0, 0.55)
	var gap := lerpf(12.0, 6.0, charge if charging else 0.0) * scale
	var length := 9.0 * scale
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a: Vector2 = centre + direction * gap
		var b: Vector2 = centre + direction * (gap + length)
		draw_line(a, b, shadow, 5.5 * scale, true)
		draw_line(a, b, color, 2.6 * scale, true)
	draw_circle(centre, 3.4 * scale, shadow)
	draw_circle(centre, 2.2 * scale, color)
	if charging:
		draw_arc(centre, 20.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * charge, 40, Color(1.0, 0.78, 0.25, 0.95), 3.0 * scale, true)
