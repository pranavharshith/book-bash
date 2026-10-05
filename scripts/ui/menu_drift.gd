class_name MenuDrift
extends Control
## Slowly drifting, rotating book silhouettes behind the menus. Cheap (one
## _draw, ~24 rects) and gives the hub screens motion instead of a still image.

const COUNT := 24
var _books: Array = []
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var colours := [Color("ffc72e"), Color("a985ff"), Color("6fdc8c"), Color("ff6b6b"), Color("7fd0ff")]
	for i in range(COUNT):
		_books.append({
			"x": rng.randf(), "y": rng.randf(), "speed": rng.randf_range(0.012, 0.035),
			"size": rng.randf_range(18.0, 46.0), "spin": rng.randf_range(-0.6, 0.6),
			"angle": rng.randf() * TAU, "sway": rng.randf() * TAU,
			"color": colours[i % colours.size()],
		})

func _process(delta: float) -> void:
	_time += delta
	for book in _books:
		book["y"] = fposmod(float(book["y"]) - float(book["speed"]) * delta, 1.1)
		book["angle"] = float(book["angle"]) + float(book["spin"]) * delta
	queue_redraw()

func _draw() -> void:
	for book in _books:
		var s: float = book["size"]
		var pos := Vector2(float(book["x"]) * size.x + sin(_time * 0.4 + float(book["sway"])) * 24.0, (float(book["y"]) - 0.05) * size.y)
		var c: Color = book["color"]
		draw_set_transform(pos, float(book["angle"]), Vector2.ONE)
		draw_rect(Rect2(Vector2(-s * 0.35, -s * 0.5), Vector2(s * 0.7, s)), Color(c.r, c.g, c.b, 0.1))
		draw_rect(Rect2(Vector2(-s * 0.35, -s * 0.5), Vector2(s * 0.12, s)), Color(c.r, c.g, c.b, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
