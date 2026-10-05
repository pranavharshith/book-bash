class_name PlayerChip
extends Control
## One fighter's status badge in the match HUD: colour ring, health arc, remaining
## stocks, and knockout score. Matches the portrait strip in the design reference.
##
## Self-drawn so six of them cost six draw calls and stay legible at any DPI.

@export var mirrored := false

var fighter_color := Color.WHITE
var fighter_label := ""
var health_ratio := 1.0
var stocks := 3
var max_stocks := 3
var score := 0
var is_active := true
var is_local := false

var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func configure(color: Color, label: String, local: bool) -> void:
	fighter_color = color
	fighter_label = label
	is_local = local
	queue_redraw()

func update_state(ratio: float, remaining_stocks: int, knockouts: int, active: bool) -> void:
	health_ratio = clampf(ratio, 0.0, 1.0)
	stocks = remaining_stocks
	score = knockouts
	is_active = active
	queue_redraw()

func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var radius := minf(size.x, size.y * 0.68) * 0.5
	var centre := Vector2(size.x * 0.5, radius + 3.0)
	var dim := 1.0 if is_active else 0.42

	# Portrait disc.
	draw_circle(centre, radius, Color(0.06, 0.05, 0.09, 0.85 * dim))
	draw_circle(centre, radius * 0.82, Color(fighter_color.r, fighter_color.g, fighter_color.b, 0.95 * dim))

	# Health as a ring so damage is readable without reading a number.
	var health_color := Color(0.95, 0.28, 0.22).lerp(Color(0.42, 0.92, 0.5), health_ratio)
	draw_arc(centre, radius - 3.0, -PI * 0.5, -PI * 0.5 + TAU, 40, Color(0, 0, 0, 0.42 * dim), 6.0, true)
	if health_ratio > 0.0:
		draw_arc(centre, radius - 3.0, -PI * 0.5, -PI * 0.5 + TAU * health_ratio, 40, Color(health_color.r, health_color.g, health_color.b, dim), 6.0, true)
	if is_local:
		draw_arc(centre, radius + 4.0, 0.0, TAU, 40, Color(1.0, 0.86, 0.3, 0.95 * dim), 3.0, true)

	# Initial keeps identity readable even when the ring colours are similar.
	var initial := fighter_label.substr(0, 1).to_upper() if not fighter_label.is_empty() else "?"
	var initial_size := _font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius))
	draw_string(
		_font, centre - initial_size * 0.5 + Vector2(0, initial_size.y * 0.34), initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius), Color(1, 1, 1, 0.92 * dim)
	)

	# Stock pips hug the top of the disc.
	var pip_radius := maxf(radius * 0.13, 2.5)
	var spacing := pip_radius * 2.8
	var start_x := centre.x - spacing * (max_stocks - 1) * 0.5
	for i in range(max_stocks):
		var filled := i < stocks
		var pip_colour := Color(1.0, 0.86, 0.32, dim) if filled else Color(1, 1, 1, 0.18 * dim)
		draw_circle(Vector2(start_x + spacing * i, centre.y - radius - pip_radius - 1.0), pip_radius, pip_colour)

	# Score pill under the portrait.
	var pill_size := Vector2(radius * 1.5, radius * 0.62)
	var pill_position := Vector2(centre.x - pill_size.x * 0.5, centre.y + radius - pill_size.y * 0.2)
	draw_rect(Rect2(pill_position, pill_size), Color(0.05, 0.04, 0.08, 0.88 * dim), true)
	var score_text := str(score)
	var score_font_size := int(maxf(pill_size.y * 0.78, 10.0))
	var score_size := _font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size)
	draw_string(
		_font, pill_position + pill_size * 0.5 - score_size * 0.5 + Vector2(0, score_size.y * 0.34),
		score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size, Color(1, 0.95, 0.8, dim)
	)
