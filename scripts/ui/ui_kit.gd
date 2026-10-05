class_name UiKit
extends RefCounted
## Shared visual language for every Book Bash menu.
##
## All menu screens build their layout in code rather than from hand-tuned scene
## offsets. That is a deliberate choice: the game ships to phones, tablets, and
## desktop, and the first pass used fixed pixel offsets that only lined up at
## exactly 1280x720. Building from containers plus one scale factor means one
## layout definition works everywhere.

const BACKDROP := Color("140c26")
const BACKDROP_ALT := Color("241543")
const PANEL := Color("2b1a4f")
const PANEL_RAISED := Color("3a2568")
const ACCENT := Color("ffc72e")
const ACCENT_DIM := Color("c8952a")
const COIN := Color("ffd24a")
const GEM := Color("a985ff")
const TEXT := Color("f3eefc")
const TEXT_DIM := Color("b8a9d6")
const DANGER := Color("ff6b6b")
const SUCCESS := Color("6fdc8c")

## Reference height the layout numbers are authored against.
const REFERENCE_HEIGHT := 720.0

static func scale_for(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.x / 1280.0, viewport_size.y / REFERENCE_HEIGHT), 0.62, 2.0)

static func rounded(color: Color, radius: int = 18, border_color: Color = Color(0, 0, 0, 0), border: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border > 0:
		style.set_border_width_all(border)
		style.border_color = border_color
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func panel(color: Color = PANEL, radius: int = 18) -> Panel:
	var node := Panel.new()
	node.add_theme_stylebox_override("panel", rounded(color, radius))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func label(text: String, font_size: int, color: Color = TEXT, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = alignment
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func title(text: String, font_size: int) -> Label:
	var node := label(text, font_size, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	node.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.0, 0.9))
	node.add_theme_constant_override("outline_size", maxi(int(font_size * 0.12), 4))
	return node

## Primary call-to-action, e.g. PLAY.
static func primary_button(text: String, font_size: int = 34) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("2a1a02"))
	node.add_theme_color_override("font_hover_color", Color("1c1100"))
	node.add_theme_color_override("font_pressed_color", Color("1c1100"))
	node.add_theme_stylebox_override("normal", rounded(ACCENT, 26))
	node.add_theme_stylebox_override("hover", rounded(ACCENT.lightened(0.1), 26))
	node.add_theme_stylebox_override("pressed", rounded(ACCENT_DIM, 26))
	node.add_theme_stylebox_override("disabled", rounded(ACCENT.darkened(0.45), 26))
	return node

static func secondary_button(text: String, font_size: int = 20) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.clip_text = true
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_hover_color", ACCENT)
	node.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.3))
	node.add_theme_stylebox_override("normal", rounded(PANEL_RAISED, 16))
	node.add_theme_stylebox_override("hover", rounded(PANEL_RAISED.lightened(0.12), 16))
	node.add_theme_stylebox_override("pressed", rounded(PANEL.darkened(0.15), 16))
	node.add_theme_stylebox_override("disabled", rounded(PANEL.darkened(0.35), 16))
	return node

## Toggle used for tab strips and mode pickers.
static func tab_button(text: String, font_size: int = 20) -> Button:
	var node := secondary_button(text, font_size)
	node.toggle_mode = true
	node.add_theme_stylebox_override("pressed", rounded(ACCENT, 16))
	node.add_theme_color_override("font_pressed_color", Color("2a1a02"))
	return node

static func set_tab_active(button: Button, active: bool) -> void:
	button.button_pressed = active
	if active:
		button.add_theme_stylebox_override("normal", rounded(ACCENT, 16))
		button.add_theme_color_override("font_color", Color("2a1a02"))
	else:
		button.add_theme_stylebox_override("normal", rounded(PANEL_RAISED, 16))
		button.add_theme_color_override("font_color", TEXT)

static func currency_pill(icon: String, color: Color) -> Dictionary:
	var root := Panel.new()
	root.add_theme_stylebox_override("panel", rounded(Color(0.05, 0.04, 0.09, 0.75), 20))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value := label("0", 20, color, HORIZONTAL_ALIGNMENT_CENTER)
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(value)
	return {"root": root, "label": value, "icon": icon}

static func progress_bar(color: Color = ACCENT) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", rounded(Color(0.05, 0.04, 0.09, 0.8), 12))
	var fill := rounded(color, 12)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

## Backdrop gradient. Flat colour looked cheap against the stylised 3D scenes.
static func backdrop() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, BACKDROP_ALT)
	gradient.set_color(1, BACKDROP)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.35, 1.0)
	texture.width = 64
	texture.height = 64
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Attaches hover/click audio to a button so every menu sounds the same.
static func wire_audio(button: BaseButton) -> void:
	button.mouse_entered.connect(func(): Audio.play_ui("hover", -18.0))
	button.pressed.connect(func(): Audio.play_ui("click", -8.0))
