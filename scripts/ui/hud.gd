class_name MatchHud
extends CanvasLayer
## Match HUD, laid out in code so it adapts to any phone, tablet, or desktop
## aspect ratio without a scene full of hand-tuned offsets.
##
## Layout mirrors the design reference: three portraits on each side of a centre
## timer, joystick bottom-left, and a charge-ring throw button bottom-right with
## dodge and power-up satellites.

signal move_input(vector: Vector2)
signal aim_input(vector: Vector2)
signal throw_started()
signal throw_released(charge: float)
signal dodge_pressed()
signal settings_pressed()
signal look_drag(pixels: Vector2)
signal jump_pressed()
signal jump_released()
signal camera_toggle_pressed()
signal menu_opened()
signal menu_closed()
signal controls_changed(scheme: String)
signal quit_requested()

const CHARGE_TIME := Fighter.THROW_CHARGE_TIME
const SAFE_MARGIN := 26.0

var _root: Control
var _chips: Array[PlayerChip] = []
var _joystick: TouchJoystick
var _throw_button: ActionButton
var _dodge_button: ActionButton
var _power_chip: Panel
var _power_label: Label
var _timer_label: Label
var _arena_label: Label
var _banner: Label
var _feed: VBoxContainer
var _settings_button: Button

var _look_pad: TouchLookPad
var _jump_button: ActionButton
var _camera_button: Button
var _crosshair: Crosshair
var _desktop_panel: Panel
var _desktop_ammo: Label
var _desktop_dodge: Label
var _desktop_hints: Label
var _touch_layout := true
var _books := 1

var _is_charging := false
var _charge := 0.0
var _banner_timer := 0.0
var _pending_layout := true

func _ready() -> void:
	layer = 10
	_build()
	get_viewport().size_changed.connect(_queue_layout)

func _queue_layout() -> void:
	_pending_layout = true

# --------------------------------------------------------------------------- #
# Construction
# --------------------------------------------------------------------------- #

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top_strip()
	_build_banner()
	_build_controls()
	_build_player_status()
	_build_overlays()
	_apply_layout()

func _build_top_strip() -> void:
	for i in range(GameState.MAX_FIGHTERS):
		var chip := PlayerChip.new()
		chip.name = "Chip%d" % i
		chip.visible = false
		_root.add_child(chip)
		_chips.append(chip)

	var pill := Panel.new()
	pill.name = "TimerPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _rounded_style(Color(0.06, 0.05, 0.09, 0.72), 26))
	_root.add_child(pill)

	_arena_label = Label.new()
	_arena_label.name = "ArenaLabel"
	_arena_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arena_label.add_theme_font_size_override("font_size", 14)
	_arena_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7, 0.7))
	_arena_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(_arena_label)

	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "02:30"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(_timer_label)

	_feed = VBoxContainer.new()
	_feed.name = "Feed"
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 2)
	_root.add_child(_feed)

	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "II"
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.add_theme_font_size_override("font_size", 20)
	_settings_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.06, 0.05, 0.09, 0.6), 999))
	_settings_button.add_theme_stylebox_override("hover", _rounded_style(Color(0.14, 0.12, 0.2, 0.75), 999))
	_settings_button.add_theme_stylebox_override("pressed", _rounded_style(Color(0.2, 0.17, 0.28, 0.85), 999))
	# Opens the pause menu; quitting is a deliberate choice inside it.
	_settings_button.pressed.connect(toggle_pause_menu)
	_root.add_child(_settings_button)

func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 58)
	_banner.add_theme_color_override("font_color", Color(1, 0.86, 0.32))
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.0))
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_root.add_child(_banner)

func _build_controls() -> void:
	# Look pad first so every button added after it sits on top and wins touches.
	_look_pad = TouchLookPad.new()
	_look_pad.name = "LookPad"
	_look_pad.look_drag.connect(func(pixels: Vector2): look_drag.emit(pixels))
	_root.add_child(_look_pad)

	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_crosshair)

	_build_desktop_panel()

	_jump_button = ActionButton.new()
	_jump_button.name = "JumpButton"
	_jump_button.label_text = "JUMP"
	_jump_button.fill_color = Color(0.45, 0.85, 0.5, 0.92)
	_jump_button.font_size = 15
	_jump_button.pressed_down.connect(func(): jump_pressed.emit())
	_jump_button.released.connect(func(_drag: Vector2): jump_released.emit())
	_root.add_child(_jump_button)

	_camera_button = Button.new()
	_camera_button.name = "CameraButton"
	_camera_button.text = "CAM"
	_camera_button.focus_mode = Control.FOCUS_NONE
	_camera_button.add_theme_font_size_override("font_size", 14)
	_camera_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.06, 0.05, 0.09, 0.6), 999))
	_camera_button.add_theme_stylebox_override("hover", _rounded_style(Color(0.14, 0.12, 0.2, 0.75), 999))
	_camera_button.add_theme_stylebox_override("pressed", _rounded_style(Color(0.2, 0.17, 0.28, 0.85), 999))
	_camera_button.pressed.connect(func(): camera_toggle_pressed.emit())
	_root.add_child(_camera_button)

	_joystick = TouchJoystick.new()
	_joystick.name = "Joystick"
	_joystick.move_input.connect(func(value: Vector2): move_input.emit(value))
	_root.add_child(_joystick)

	_throw_button = ActionButton.new()
	_throw_button.name = "ThrowButton"
	_throw_button.label_text = "THROW"
	_throw_button.aim_pad = true
	_throw_button.font_size = 20
	_throw_button.pressed_down.connect(_on_throw_pressed)
	# Dragging the held THROW button steers the camera, i.e. the crosshair.
	_throw_button.aim_pad = false
	_throw_button.drag_delta.connect(func(pixels: Vector2): look_drag.emit(pixels))
	_throw_button.released.connect(_on_throw_released)
	_root.add_child(_throw_button)

	_dodge_button = ActionButton.new()
	_dodge_button.name = "DodgeButton"
	_dodge_button.label_text = "DODGE"
	_dodge_button.fill_color = Color(0.3, 0.62, 1.0, 0.92)
	_dodge_button.font_size = 15
	_dodge_button.pressed_down.connect(func(): dodge_pressed.emit())
	_root.add_child(_dodge_button)

	_power_chip = Panel.new()
	_power_chip.name = "PowerChip"
	_power_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_chip.add_theme_stylebox_override("panel", _rounded_style(Color(0.08, 0.07, 0.12, 0.8), 18))
	_power_chip.visible = false
	_root.add_child(_power_chip)

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_power_label.add_theme_font_size_override("font_size", 16)
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_power_chip.add_child(_power_label)

## Keyboard/mouse players get a compact ammo + dodge readout and a control hint
## strip instead of on-screen touch buttons they cannot press.
func _build_desktop_panel() -> void:
	_desktop_panel = Panel.new()
	_desktop_panel.name = "DesktopPanel"
	_desktop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.06, 0.05, 0.09, 0.66), 16))
	_root.add_child(_desktop_panel)
	_desktop_ammo = Label.new()
	_desktop_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_ammo.add_theme_color_override("font_color", Color(1, 0.88, 0.5))
	_desktop_panel.add_child(_desktop_ammo)
	_desktop_dodge = Label.new()
	_desktop_dodge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_panel.add_child(_desktop_dodge)
	_desktop_hints = Label.new()
	_desktop_hints.name = "Hints"
	_desktop_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_hints.text = "WASD move   •   Mouse look   •   Hold LMB throw   •   Space jump   •   Shift dodge   •   V camera   •   Esc cursor"
	_desktop_hints.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_desktop_hints.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_desktop_hints.add_theme_constant_override("outline_size", 4)
	_root.add_child(_desktop_hints)

func set_touch_layout(touch: bool) -> void:
	_touch_layout = touch
	_pending_layout = true

func set_crosshair_state(locked: bool, charging: bool, has_ammo: bool) -> void:
	if _crosshair:
		_crosshair.set_state(locked, charging, has_ammo, _charge if _is_charging else 0.0)

func _rounded_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

# --------------------------------------------------------------------------- #
# Responsive layout
# --------------------------------------------------------------------------- #

func _apply_layout() -> void:
	_pending_layout = false
	var viewport := get_viewport()
	if viewport == null:
		return
	var view := viewport.get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var scale_factor := clampf(minf(view.x, view.y) / 720.0, 0.72, 1.5)
	var margin := SAFE_MARGIN * scale_factor

	# Portrait strip: three per side, hugging the top corners so a notch in the
	# centre of the screen never covers a player's status.
	var chip_size := Vector2(64, 92) * scale_factor
	var chip_gap := 10.0 * scale_factor
	for i in range(_chips.size()):
		var chip := _chips[i]
		chip.size = chip_size
		chip.max_stocks = Fighter.MAX_STOCKS
		var column := i % 3
		if i < 3:
			chip.position = Vector2(margin + column * (chip_size.x + chip_gap), margin)
		else:
			var from_right := 2 - column
			chip.position = Vector2(
				view.x - margin - chip_size.x - from_right * (chip_size.x + chip_gap),
				margin
			)

	var pill_size := Vector2(168, 68) * scale_factor
	var pill := _root.get_node("TimerPill") as Panel
	pill.size = pill_size
	pill.position = Vector2((view.x - pill_size.x) * 0.5, margin * 0.5)
	_arena_label.position = Vector2(0, pill_size.y * 0.1)
	_arena_label.size = Vector2(pill_size.x, pill_size.y * 0.32)
	_arena_label.add_theme_font_size_override("font_size", int(13 * scale_factor))
	_timer_label.position = Vector2(0, pill_size.y * 0.34)
	_timer_label.size = Vector2(pill_size.x, pill_size.y * 0.6)
	_timer_label.add_theme_font_size_override("font_size", int(30 * scale_factor))

	_feed.position = Vector2((view.x - 300.0 * scale_factor) * 0.5, margin * 0.5 + pill_size.y + 6.0)
	_feed.size = Vector2(300.0 * scale_factor, 120.0 * scale_factor)

	var settings_size := Vector2.ONE * 46.0 * scale_factor
	_settings_button.size = settings_size
	_settings_button.position = Vector2(view.x - margin - settings_size.x, margin + chip_size.y + 8.0 * scale_factor)

	_banner.size = Vector2(view.x * 0.8, 120.0 * scale_factor)
	_banner.position = Vector2(view.x * 0.1, view.y * 0.34)
	_banner.add_theme_font_size_override("font_size", int(56 * scale_factor))

	_joystick.apply_scale_for_viewport(view)
	_joystick.position = Vector2(margin, view.y - margin - _joystick.size.y)

	_throw_button.apply_scale_for_viewport(view, 148.0)
	_throw_button.position = Vector2(
		view.x - margin - _throw_button.size.x,
		view.y - margin - _throw_button.size.y
	)

	_dodge_button.apply_scale_for_viewport(view, 92.0)
	_dodge_button.position = Vector2(
		_throw_button.position.x - _dodge_button.size.x - 14.0 * scale_factor,
		_throw_button.position.y + _throw_button.size.y - _dodge_button.size.y - 6.0 * scale_factor
	)

	_jump_button.apply_scale_for_viewport(view, 92.0)
	_jump_button.position = Vector2(
		_throw_button.position.x + _throw_button.size.x - _jump_button.size.x - 4.0 * scale_factor,
		_throw_button.position.y - _jump_button.size.y - 14.0 * scale_factor
	)

	var camera_size := Vector2.ONE * 46.0 * scale_factor
	_camera_button.size = camera_size
	_camera_button.position = _settings_button.position + Vector2(-camera_size.x - 10.0 * scale_factor, 0.0)
	_camera_button.add_theme_font_size_override("font_size", int(13 * scale_factor))

	# Right half (minus the top strip) turns the camera on touch screens.
	_look_pad.position = Vector2(view.x * 0.42, margin + chip_size.y + 60.0 * scale_factor)
	_look_pad.size = Vector2(view.x * 0.58, view.y - _look_pad.position.y)

	var panel_size := Vector2(210, 64) * scale_factor
	_desktop_panel.size = panel_size
	_desktop_panel.position = Vector2(view.x - margin - panel_size.x, view.y - margin - panel_size.y)
	_desktop_ammo.position = Vector2(16, 6) * scale_factor
	_desktop_ammo.add_theme_font_size_override("font_size", int(22 * scale_factor))
	_desktop_dodge.position = Vector2(16, 36) * scale_factor
	_desktop_dodge.add_theme_font_size_override("font_size", int(15 * scale_factor))
	_desktop_hints.size = Vector2(view.x, 24 * scale_factor)
	_desktop_hints.position = Vector2(0, view.y - margin * 0.5 - 22 * scale_factor)
	_desktop_hints.add_theme_font_size_override("font_size", int(14 * scale_factor))

	_layout_overlays(view, scale_factor)
	var touch := _touch_layout
	# Eliminated players only need to look around and switch view.
	var fighting := touch and not _spectating
	_joystick.visible = fighting
	_throw_button.visible = fighting
	_dodge_button.visible = fighting
	_jump_button.visible = fighting
	_crosshair.visible = not _spectating
	_look_pad.visible = touch
	_camera_button.visible = touch
	_desktop_panel.visible = not touch and not _spectating
	_desktop_hints.visible = not touch

	var power_size := Vector2(150, 40) * scale_factor
	_power_chip.size = power_size
	if touch:
		_power_chip.position = Vector2(
			_jump_button.position.x - power_size.x - 12.0 * scale_factor,
			_jump_button.position.y + (_jump_button.size.y - power_size.y) * 0.5
		)
	else:
		_power_chip.position = Vector2(
			_desktop_panel.position.x + panel_size.x - power_size.x,
			_desktop_panel.position.y - power_size.y - 10.0 * scale_factor
		)
	_power_label.add_theme_font_size_override("font_size", int(16 * scale_factor))

func _process(delta: float) -> void:
	if _pending_layout:
		_apply_layout()
	_update_status(delta)
	if _is_charging:
		_charge = clampf(_charge + delta / CHARGE_TIME, 0.0, 1.0)
		_throw_button.charge = _charge
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false

# --------------------------------------------------------------------------- #
# Input plumbing
# --------------------------------------------------------------------------- #

func _on_throw_pressed() -> void:
	if not _throw_button.enabled:
		return
	_is_charging = true
	_charge = 0.0
	_throw_button.charge = 0.0
	throw_started.emit()

func _on_throw_released(drag: Vector2) -> void:
	if not _is_charging:
		return
	_is_charging = false
	if drag.length() > 0.01:
		aim_input.emit(drag)
	throw_released.emit(_charge)
	aim_input.emit(Vector2.ZERO)
	_charge = 0.0
	_throw_button.charge = 0.0

## Keyboard/gamepad charging must drive the same ring so both control schemes show
## identical feedback.
func begin_external_charge() -> void:
	if _is_charging:
		return
	_is_charging = true
	_charge = 0.0
	_throw_button.charge = 0.0

func end_external_charge() -> float:
	if not _is_charging:
		return 0.0
	_is_charging = false
	var value := _charge
	_charge = 0.0
	_throw_button.charge = 0.0
	return value

func is_charging() -> bool:
	return _is_charging

func joystick_engaged() -> bool:
	return _joystick != null and _joystick.is_engaged()

# --------------------------------------------------------------------------- #
# State display
# --------------------------------------------------------------------------- #

func configure_slot(index: int, color: Color, fighter_name: String, is_local: bool) -> void:
	if index < 0 or index >= _chips.size():
		return
	_chips[index].visible = true
	_chips[index].configure(color, fighter_name, is_local)

func hide_slot(index: int) -> void:
	if index < 0 or index >= _chips.size():
		return
	_chips[index].visible = false

func set_player_slot(index: int, health_ratio: float, stocks: int, knockouts: int, is_active: bool) -> void:
	if index < 0 or index >= _chips.size():
		return
	_chips[index].update_state(health_ratio, stocks, knockouts, is_active)

func set_ammo(books_held: int) -> void:
	if _throw_button == null:
		return
	_books = books_held
	_throw_button.enabled = books_held > 0
	_throw_button.badge_text = str(books_held)
	_throw_button.label_text = "THROW" if books_held > 0 else "EMPTY"
	if _desktop_ammo:
		_desktop_ammo.text = "BOOKS  %d / %d" % [books_held, Fighter.MAX_BOOKS] if books_held > 0 else "OUT OF BOOKS"
		_desktop_ammo.add_theme_color_override("font_color", Color(1, 0.88, 0.5) if books_held > 0 else Color(1, 0.5, 0.45))

func set_dodge_cooldown(ratio: float) -> void:
	if _dodge_button:
		_dodge_button.cooldown = ratio
		_dodge_button.enabled = ratio <= 0.001
	if _desktop_dodge:
		var ready := ratio <= 0.001
		var text := "DODGE  READY" if ready else "DODGE  %d%%" % int((1.0 - ratio) * 100.0)
		if _desktop_dodge.text != text:
			_desktop_dodge.text = text
			_desktop_dodge.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0) if ready else Color(1, 1, 1, 0.5))

func set_power_up(power_id: String, seconds_left: float) -> void:
	if _power_chip == null:
		return
	if power_id.is_empty() or seconds_left <= 0.0:
		_power_chip.visible = false
		return
	var definition: Dictionary = GameState.POWER_UPS.get(power_id, {})
	_power_chip.visible = true
	var text := "%s  %s  %.0fs" % [definition.get("icon", "★"), definition.get("name", power_id), ceilf(seconds_left)]
	if text == _last_power_text:
		return
	_last_power_text = text
	_power_label.text = text
	_power_label.add_theme_color_override("font_color", definition.get("color", Color.WHITE))

func set_arena_name(text: String) -> void:
	if _arena_label:
		_arena_label.text = text.to_upper()

func set_timer(seconds: int) -> void:
	seconds = maxi(seconds, 0)
	_timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_timer_label.add_theme_color_override("font_color", Color(1, 0.4, 0.34) if seconds <= 10 else Color.WHITE)

func show_banner(text: String, duration: float = 2.0) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_timer = duration

func push_feed(text: String, color: Color = Color(1, 1, 1, 0.9)) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(label)
	while _feed.get_child_count() > 4:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := label.create_tween()
	tween.tween_interval(2.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

# --------------------------------------------------------------------------- #
# Player status: own health bar, hit marker, scoreboard
# --------------------------------------------------------------------------- #

var _fighters: Array = []
var _local: Fighter
var _health_back: Panel
var _health_fill: Panel
var _health_label: Label
var _hit_marker: Control
var _hit_timer := 0.0
var _scoreboard: Panel
var _scoreboard_list: VBoxContainer
var _help_panel: Panel
var _help_label: Label
var _help_timer := 0.0
var _pause_panel: Panel
var _pause_controls: Button
var _pause_view: Button
var _pause_sens: Label
var _menu_open := false
var _moved_once := false
var _last_hp := -1
var _last_stocks := -1
var _spectating := false
var _spectate_label: Label
var _last_power_text := ""

## Called by GameManager once fighters exist.
func bind_fighters(fighters: Array, local_player: Fighter) -> void:
	_fighters = fighters
	_local = local_player
	if _local:
		_local.damage_dealt.connect(func(_t, _a, _p): show_hit_marker())
	_refresh_help_text()
	_help_timer = 12.0 if not GameState.has_seen_controls_help() else 6.0
	_help_panel.visible = true

func _build_player_status() -> void:
	_health_back = Panel.new()
	_health_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_back.add_theme_stylebox_override("panel", _rounded_style(Color(0.04, 0.03, 0.07, 0.7), 10))
	_root.add_child(_health_back)
	_health_fill = Panel.new()
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_fill.add_theme_stylebox_override("panel", _rounded_style(Color(0.35, 0.9, 0.45), 8))
	_health_back.add_child(_health_fill)
	_health_label = Label.new()
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_health_label.add_theme_constant_override("outline_size", 5)
	_health_back.add_child(_health_label)

	_hit_marker = Control.new()
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_marker.draw.connect(_draw_hit_marker)
	_root.add_child(_hit_marker)

	_scoreboard = Panel.new()
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.add_theme_stylebox_override("panel", _rounded_style(Color(0.05, 0.04, 0.09, 0.88), 18))
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	_scoreboard_list = VBoxContainer.new()
	_scoreboard_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_list.add_theme_constant_override("separation", 6)
	_scoreboard.add_child(_scoreboard_list)

func show_hit_marker() -> void:
	_hit_timer = 0.25
	_hit_marker.queue_redraw()

func _draw_hit_marker() -> void:
	if _hit_timer <= 0.0:
		return
	var c := _hit_marker.size * 0.5
	var s := clampf(minf(_hit_marker.size.x, _hit_marker.size.y) / 720.0, 0.75, 1.6)
	var alpha := clampf(_hit_timer / 0.25, 0.0, 1.0)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_hit_marker.draw_line(c + d * 9.0 * s, c + d * 18.0 * s, Color(1, 0.3, 0.25, alpha), 3.0 * s, true)

func _update_status(delta: float) -> void:
	if _hit_timer > 0.0:
		_hit_timer -= delta
		_hit_marker.queue_redraw()
	if _help_timer > 0.0 and not _menu_open:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_help_panel.visible = false
	if _local and is_instance_valid(_local):
		# Only touch the bar when the numbers change; rewriting text and styles
		# every frame forced a UI relayout each frame.
		var hp := int(ceil(_local.health))
		if hp != _last_hp or _local.stocks != _last_stocks:
			_last_hp = hp
			_last_stocks = _local.stocks
			var ratio := clampf(_local.health / Fighter.MAX_HEALTH, 0.0, 1.0)
			_health_fill.size = Vector2(maxf((_health_back.size.x - 8.0) * ratio, 0.0), _health_back.size.y - 8.0)
			var style := _health_fill.get_theme_stylebox("panel") as StyleBoxFlat
			style.bg_color = Color(0.95, 0.28, 0.22).lerp(Color(0.35, 0.9, 0.45), ratio)
			_health_label.text = "%d HP   •   %s" % [hp, "♥ ".repeat(maxi(_local.stocks, 0)).strip_edges()]
		var show_health := _local.alive and not _spectating
		if _health_back.visible != show_health:
			_health_back.visible = show_health
	var show_board := Input.is_action_pressed("scoreboard") and not _menu_open
	if show_board != _scoreboard.visible:
		_scoreboard.visible = show_board
	if show_board:
		_refresh_scoreboard()

func _refresh_scoreboard() -> void:
	for child in _scoreboard_list.get_children():
		child.queue_free()
	var header := _row_label("PLAYER                     LIVES    KOs    HP", Color(1, 0.86, 0.4))
	_scoreboard_list.add_child(header)
	var sorted := _fighters.duplicate()
	sorted.sort_custom(func(a, b): return a.stocks * 1000 + a.knockout_score * 10 > b.stocks * 1000 + b.knockout_score * 10)
	for f in sorted:
		if f == null or not is_instance_valid(f):
			continue
		var name_text := String(f.fighter_name) + ("  (YOU)" if f == _local else "")
		var line := "%-26s %5d %6d %6s" % [name_text, f.stocks, f.knockout_score, str(int(f.health)) if f.alive else "OUT"]
		_scoreboard_list.add_child(_row_label(line, f.fighter_color.lightened(0.3) if f.alive else Color(1, 1, 1, 0.35)))

func _row_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", _mono_font())
	return label

var _mono: SystemFont
func _mono_font() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return _mono

# --------------------------------------------------------------------------- #
# Controls help card + pause menu
# --------------------------------------------------------------------------- #

func _build_overlays() -> void:
	_help_panel = Panel.new()
	_help_panel.name = "ControlsHelp"
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.05, 0.04, 0.09, 0.8), 16))
	_root.add_child(_help_panel)
	_help_label = Label.new()
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_help_panel.add_child(_help_label)
	_help_panel.visible = false

	_spectate_label = Label.new()
	_spectate_label.name = "SpectateLabel"
	_spectate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spectate_label.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	_spectate_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_spectate_label.add_theme_constant_override("outline_size", 6)
	_spectate_label.visible = false
	_root.add_child(_spectate_label)

	_pause_panel = Panel.new()
	_pause_panel.name = "PauseMenu"
	_pause_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.06, 0.04, 0.12, 0.94), 22))
	_pause_panel.visible = false
	_root.add_child(_pause_panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.25))
	column.add_child(title)
	column.add_child(_menu_button("RESUME", func(): toggle_pause_menu()))
	_pause_controls = _menu_button("", _cycle_controls)
	# Switching to keyboard + mouse makes no sense on a phone.
	_pause_controls.visible = not Perf.is_mobile()
	column.add_child(_pause_controls)
	_pause_view = _menu_button("", func(): camera_toggle_pressed.emit(); _toggle_saved_view())
	column.add_child(_pause_view)
	var sens_row := HBoxContainer.new()
	sens_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sens_row.add_theme_constant_override("separation", 10)
	sens_row.add_child(_menu_button(" - ", func(): _change_sensitivity(-0.1), 60))
	_pause_sens = Label.new()
	_pause_sens.custom_minimum_size = Vector2(240, 0)
	_pause_sens.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_sens.add_theme_font_size_override("font_size", 20)
	sens_row.add_child(_pause_sens)
	sens_row.add_child(_menu_button(" + ", func(): _change_sensitivity(0.1), 60))
	column.add_child(sens_row)
	column.add_child(_menu_button("SHOW CONTROLS", func(): toggle_pause_menu(); toggle_controls_help()))
	column.add_child(_menu_button("QUIT TO LOBBY", func(): quit_requested.emit(); settings_pressed.emit()))

func _menu_button(text: String, callback: Callable, width: float = 380.0) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 54)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", _rounded_style(Color(0.23, 0.15, 0.4, 1.0), 14))
	button.add_theme_stylebox_override("hover", _rounded_style(Color(0.32, 0.22, 0.55, 1.0), 14))
	button.add_theme_stylebox_override("pressed", _rounded_style(Color(1, 0.78, 0.2, 1.0), 14))
	button.pressed.connect(callback)
	return button

func _layout_overlays(view: Vector2, s: float) -> void:
	var bar_size := Vector2(320, 30) * s
	_last_hp = -1
	_health_back.size = bar_size
	_health_back.position = Vector2((view.x - bar_size.x) * 0.5, view.y - bar_size.y - (54.0 if not _touch_layout else 24.0) * s)
	_health_fill.position = Vector2(4, 4)
	_health_label.size = bar_size
	_health_label.add_theme_font_size_override("font_size", int(15 * s))
	_scoreboard.size = Vector2(620, 320) * s
	_scoreboard.position = (view - _scoreboard.size) * 0.5
	_scoreboard_list.position = Vector2(24, 18) * s
	_spectate_label.size = Vector2(view.x * 0.6, 80.0 * s)
	_spectate_label.position = Vector2(view.x * 0.2, view.y - 80.0 * s - 14.0 * s)
	_spectate_label.add_theme_font_size_override("font_size", int(19 * s))
	_help_label.add_theme_font_size_override("font_size", int(16 * s))
	_help_label.position = Vector2(18, 12) * s
	_help_panel.size = Vector2(330, 250) * s
	_help_panel.position = Vector2(26 * s, view.y * 0.5 - _help_panel.size.y * 0.5 + 30 * s)
	var pause_size := Vector2(440, 500) * s
	_pause_panel.size = pause_size
	_pause_panel.position = (view - pause_size) * 0.5
	var column := _pause_panel.get_node("Column") as VBoxContainer
	column.position = Vector2(30, 24) * s
	column.size = pause_size - Vector2(60, 48) * s

func _refresh_help_text() -> void:
	if _help_label == null:
		return
	if _touch_layout:
		_help_label.text = "HOW TO PLAY\n\nLeft stick: move\nDrag right side: look / turn\nTHROW: hold to aim, release to throw\n   (drag while holding to steer)\nJUMP / DODGE buttons\nCAM: first / third person\nII: menu\n\nGrab glowing books, knock rivals out!"
	else:
		_help_label.text = "HOW TO PLAY\n\nW A S D: move\nMouse: look / turn\nLeft mouse (hold): aim + throw\nSpace: jump      Shift / RMB: dodge\nV: first / third person\nTab: scoreboard     H: this help\nEsc: menu\n\nGrab glowing books, knock rivals out!"

func toggle_controls_help() -> void:
	_help_panel.visible = not _help_panel.visible
	_help_timer = 0.0 if _help_panel.visible else 0.0

func notify_player_moved() -> void:
	# First movement means they have found the controls; fade the card soon.
	if not _moved_once:
		_moved_once = true
		_help_timer = minf(_help_timer, 4.0) if _help_timer > 0.0 else _help_timer
		if not GameState.has_seen_controls_help():
			GameState.set_setting("seen_help", true)

func toggle_pause_menu() -> void:
	_menu_open = not _menu_open
	_pause_panel.visible = _menu_open
	_refresh_pause_labels()
	if _menu_open:
		menu_opened.emit()
	else:
		menu_closed.emit()

func is_menu_open() -> bool:
	return _menu_open

func _refresh_pause_labels() -> void:
	_pause_controls.text = "CONTROLS:  %s" % GameState.CONTROL_SCHEMES.get(GameState.control_scheme(), "")
	_pause_view.text = "VIEW:  %s" % GameState.CAMERA_VIEWS.get(GameState.camera_view(), "")
	_pause_sens.text = "Look sensitivity  %.1f" % GameState.mouse_sensitivity()
	_pause_controls.visible = not Perf.is_mobile()

func _cycle_controls() -> void:
	var next := "touch" if GameState.control_scheme() == "keyboard" else "keyboard"
	GameState.set_setting("controls", next)
	set_touch_layout(next == "touch")
	controls_changed.emit(next)
	_refresh_help_text()
	_refresh_pause_labels()

func _toggle_saved_view() -> void:
	GameState.set_setting("camera", "third" if GameState.camera_view() == "first" else "first")
	_refresh_pause_labels()

func _change_sensitivity(step: float) -> void:
	GameState.set_setting("sensitivity", clampf(snappedf(GameState.mouse_sensitivity() + step, 0.1), 0.2, 3.0))
	_refresh_pause_labels()

## Local player eliminated: hide the fighting controls and explain the spectator
## view. `overhead` is true for the god's-eye camera, false when following a player.
func set_spectating(active: bool, overhead: bool = true) -> void:
	var changed := active != _spectating
	_spectating = active
	if changed:
		_pending_layout = true
		if active:
			_is_charging = false
			_help_panel.visible = false
			_health_back.visible = false
	_spectate_label.visible = active
	if active:
		var hint := "Drag to rotate the view" if overhead else "Following a player"
		if _touch_layout:
			_spectate_label.text = "YOU'RE OUT - SPECTATING\n%s  •  tap CAM to switch view" % hint
		else:
			_spectate_label.text = "YOU'RE OUT - SPECTATING\n%s  •  press V to switch view" % hint

func set_mouse_look_pad(enabled: bool) -> void:
	if _look_pad:
		_look_pad.accept_mouse = enabled
