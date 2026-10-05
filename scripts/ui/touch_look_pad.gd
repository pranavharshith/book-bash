class_name TouchLookPad
extends Control
## Right-side camera drag area for the on-screen-joystick control scheme.
##
## On phones it reads touch events only. On a laptop using the on-screen
## joystick, `accept_mouse` lets a left-button mouse drag turn the camera too.
## It sits *behind* the action buttons in the HUD tree, so pressing a button
## never turns the camera. Fingers are tracked by index, so look and the
## movement stick work at the same time.

signal look_drag(pixels: Vector2)

const MOUSE_POINTER := -2

var accept_mouse := false
var _pointer := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pointer == -1:
			_pointer = touch.index
			accept_event()
		elif not touch.pressed and touch.index == _pointer:
			_pointer = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer:
			look_drag.emit(drag.screen_relative)
			accept_event()
	elif accept_mouse and event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _pointer == -1:
			_pointer = MOUSE_POINTER
		elif not event.pressed and _pointer == MOUSE_POINTER:
			_pointer = -1
		accept_event()
	elif accept_mouse and event is InputEventMouseMotion and _pointer == MOUSE_POINTER:
		look_drag.emit((event as InputEventMouseMotion).screen_relative)
		accept_event()

func is_engaged() -> bool:
	return _pointer != -1

func _draw() -> void:
	# A faint hint on the right side so players know they can drag to look.
	var text := "DRAG HERE TO LOOK"
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(size.y / 22.0, 12.0, 20.0))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, size.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.22 if not is_engaged() else 0.0))
