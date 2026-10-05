class_name TouchJoystick
extends Control
## Self-drawn virtual joystick.
##
## Two deliberate choices here, both from bugs in the first playable:
##
## 1. The stick draws itself instead of nesting Panel children. A child Panel
##    defaults to `MOUSE_FILTER_STOP`, so it silently swallowed every touch and
##    the joystick did nothing at all on any device.
## 2. `_gui_input` already delivers control-local positions. Converting them
##    again through the canvas transform offset the stick by the control's own
##    position, which pinned input to one corner.
##
## The stick is also *dynamic*: pressing anywhere in its (generous) touch area
## re-centres the base under your thumb, which is what makes it usable on phones
## of wildly different sizes without per-device tuning.

signal move_input(vector: Vector2)
signal touch_started()
signal touch_ended()

@export var base_radius := 96.0
@export var knob_radius := 44.0
@export var dead_zone := 0.14
@export var dynamic_origin := true
@export var base_color := Color(0.07, 0.06, 0.11, 0.55)
@export var rim_color := Color(1, 1, 1, 0.22)
@export var knob_color := Color(0.96, 0.97, 1.0, 0.92)

var _active_pointer := -1
var _origin := Vector2.ZERO
var _knob_offset := Vector2.ZERO
var _value := Vector2.ZERO

const MOUSE_POINTER := -2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_recentre)
	_recentre()

func _recentre() -> void:
	_origin = size * 0.5
	_knob_offset = Vector2.ZERO
	queue_redraw()

## Scales the stick to the shorter screen edge so it stays thumb-sized on a small
## phone and does not become a postage stamp on a tablet.
func apply_scale_for_viewport(viewport_size: Vector2) -> void:
	var reference := minf(viewport_size.x, viewport_size.y)
	var factor := clampf(reference / 720.0, 0.78, 1.5)
	base_radius = 96.0 * factor
	knob_radius = 44.0 * factor
	custom_minimum_size = Vector2.ONE * (base_radius * 2.6)
	size = custom_minimum_size
	_recentre()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _active_pointer == -1:
			_begin(touch.index, touch.position)
		elif not touch.pressed and touch.index == _active_pointer:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_pointer:
			_update(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and _active_pointer == -1:
			_begin(MOUSE_POINTER, button.position)
		elif not button.pressed and _active_pointer == MOUSE_POINTER:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
		_update((event as InputEventMouseMotion).position)
		accept_event()

func _begin(pointer: int, local_position: Vector2) -> void:
	_active_pointer = pointer
	if dynamic_origin:
		# Keep the re-centred base fully inside the control so the ring is never
		# half off-screen on a device with a different safe area.
		_origin = Vector2(
			clampf(local_position.x, base_radius, maxf(size.x - base_radius, base_radius)),
			clampf(local_position.y, base_radius, maxf(size.y - base_radius, base_radius))
		)
	touch_started.emit()
	_update(local_position)

func _update(local_position: Vector2) -> void:
	var offset := local_position - _origin
	_knob_offset = offset.limit_length(base_radius)
	var normalized := _knob_offset / maxf(base_radius, 1.0)
	if normalized.length() < dead_zone:
		normalized = Vector2.ZERO
	else:
		# Rescale past the dead zone so the usable range still reaches 1.0.
		var magnitude := (normalized.length() - dead_zone) / (1.0 - dead_zone)
		normalized = normalized.normalized() * clampf(magnitude, 0.0, 1.0)
	if not normalized.is_equal_approx(_value):
		_value = normalized
		move_input.emit(Vector2(normalized.x, -normalized.y))
	queue_redraw()

func _release() -> void:
	_active_pointer = -1
	_knob_offset = Vector2.ZERO
	_value = Vector2.ZERO
	move_input.emit(Vector2.ZERO)
	_recentre()
	touch_ended.emit()

func is_engaged() -> bool:
	return _active_pointer != -1

func _draw() -> void:
	var idle := _active_pointer == -1
	var alpha := 0.65 if idle else 1.0
	draw_circle(_origin, base_radius, Color(base_color.r, base_color.g, base_color.b, base_color.a * alpha))
	draw_arc(_origin, base_radius, 0.0, TAU, 48, Color(rim_color.r, rim_color.g, rim_color.b, rim_color.a * alpha), 4.0, true)
	# Directional ticks give the stick a readable "up is forward" affordance.
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			_origin + direction * (base_radius - 18.0),
			_origin + direction * (base_radius - 6.0),
			Color(1, 1, 1, 0.18 * alpha), 3.0, true
		)
	var knob_centre := _origin + _knob_offset
	draw_circle(knob_centre, knob_radius, Color(knob_color.r, knob_color.g, knob_color.b, knob_color.a * alpha))
	draw_arc(knob_centre, knob_radius, 0.0, TAU, 32, Color(0.1, 0.09, 0.14, 0.35 * alpha), 3.0, true)
