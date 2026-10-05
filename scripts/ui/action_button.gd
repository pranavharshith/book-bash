class_name ActionButton
extends Control
## Self-drawn round touch button used for THROW / DODGE / POWER.
##
## Drawn rather than assembled from Panels for the same reason as the joystick:
## nested Panel children default to `MOUSE_FILTER_STOP` and eat the press before
## the parent ever sees it. Drawing also gives us the radial charge ring from the
## design reference for free.
##
## THROW doubles as an aim pad: press and hold to charge, drag to aim, release to
## throw. That keeps the whole right thumb in one place instead of asking for a
## second stick on a phone-sized screen.

signal pressed_down()
signal released(drag: Vector2)
signal drag_changed(drag: Vector2)
## Raw per-event finger motion in pixels while held. THROW uses it to steer the
## camera (and therefore the crosshair) without lifting the thumb.
signal drag_delta(pixels: Vector2)

@export var label_text := "THROW"
@export var fill_color := Color(1.0, 0.78, 0.25, 0.94)
@export var ring_color := Color(1.0, 0.42, 0.2)
@export var aim_pad := false
@export var font_size := 22

## Drag distance, in pixels at the 720p design height, that maps to a full-length
## aim vector. Scaled with the viewport so a big screen is not twitchier.
@export var aim_radius := 78.0

var charge := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, charge):
			return
		charge = value
		queue_redraw()

var enabled := true:
	set(value):
		if value == enabled:
			return
		enabled = value
		queue_redraw()

var cooldown := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, cooldown):
			return
		cooldown = value
		queue_redraw()

var badge_text := "":
	set(value):
		if value == badge_text:
			return
		badge_text = value
		queue_redraw()

var _pointer := -1
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _drag := Vector2.ZERO
var _held := false
var _font: Font

const MOUSE_POINTER := -2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font

func apply_scale_for_viewport(viewport_size: Vector2, diameter_at_720p: float) -> void:
	var factor := clampf(minf(viewport_size.x, viewport_size.y) / 720.0, 0.78, 1.5)
	custom_minimum_size = Vector2.ONE * (diameter_at_720p * factor)
	size = custom_minimum_size
	aim_radius = 78.0 * factor
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pointer == -1:
			_begin(touch.index, touch.position)
		elif not touch.pressed and touch.index == _pointer:
			_finish()
		accept_event()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _pointer:
			_move(drag_event.position)
			accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and _pointer == -1:
			_begin(MOUSE_POINTER, button.position)
		elif not button.pressed and _pointer == MOUSE_POINTER:
			_finish()
		accept_event()
	elif event is InputEventMouseMotion and _pointer == MOUSE_POINTER:
		_move((event as InputEventMouseMotion).position)
		accept_event()

func _begin(pointer: int, local_position: Vector2) -> void:
	if not enabled:
		return
	_pointer = pointer
	_press_position = local_position
	_last_position = local_position
	_drag = Vector2.ZERO
	_held = true
	queue_redraw()
	pressed_down.emit()

func _move(local_position: Vector2) -> void:
	if _held:
		drag_delta.emit(local_position - _last_position)
	_last_position = local_position
	if not aim_pad:
		return
	var offset := local_position - _press_position
	var normalized := offset / maxf(aim_radius, 1.0)
	if normalized.length() > 1.0:
		normalized = normalized.normalized()
	# Screen-down should aim away from the camera, so invert Y once here.
	var aim := Vector2(normalized.x, -normalized.y)
	if aim.length() < 0.16:
		aim = Vector2.ZERO
	if not aim.is_equal_approx(_drag):
		_drag = aim
		drag_changed.emit(_drag)
	queue_redraw()

func _finish() -> void:
	_pointer = -1
	_held = false
	var final_drag := _drag
	_drag = Vector2.ZERO
	queue_redraw()
	released.emit(final_drag)

func is_held() -> bool:
	return _held

func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var dim := 1.0 if enabled else 0.4
	var press_scale := 0.94 if _held else 1.0
	var body_radius := radius * 0.88 * press_scale

	draw_circle(centre, radius * 0.96, Color(0.05, 0.04, 0.08, 0.35 * dim))
	draw_circle(centre, body_radius, Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * dim))
	draw_arc(centre, body_radius, 0.0, TAU, 40, Color(1, 1, 1, 0.4 * dim), 4.0, true)

	if cooldown > 0.0:
		# Sweep the remaining cooldown as a dark wedge, clockwise from the top.
		draw_arc(centre, body_radius * 0.62, -PI * 0.5, -PI * 0.5 + TAU * cooldown, 40, Color(0.03, 0.03, 0.05, 0.55), body_radius * 1.2, false)

	if charge > 0.0:
		draw_arc(centre, radius * 0.95, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, ring_color, 8.0, true)

	if aim_pad and _drag.length() > 0.01:
		var aim_screen := Vector2(_drag.x, -_drag.y)
		draw_line(centre, centre + aim_screen * body_radius * 0.9, Color(1, 1, 1, 0.85), 5.0, true)
		draw_circle(centre + aim_screen * body_radius * 0.9, 7.0, Color(1, 1, 1, 0.9))

	if _font == null:
		return
	var text_size := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		_font, centre - text_size * 0.5 + Vector2(0, text_size.y * 0.34), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.14, 0.09, 0.02, dim)
	)
	if badge_text.is_empty():
		return
	var badge_centre := centre + Vector2(radius * 0.62, -radius * 0.62)
	draw_circle(badge_centre, radius * 0.26, Color(0.08, 0.07, 0.12, 0.92))
	var badge_size := _font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		_font, badge_centre - badge_size * 0.5 + Vector2(0, badge_size.y * 0.34), badge_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.92, 0.6)
	)
