class_name LobbyScreen
extends Control
## Main hub. Everything here is wired: navigation, mode selection, difficulty,
## arena selection readout, currency balances, and level progress all come from the
## saved profile.
##
## Built with containers in code rather than fixed scene offsets. The previous
## version used Panels with `gui_input` handlers as fake buttons, which gave no
## hover or press feedback and silently swallowed touches.

const MODES := [
	{"id": "bots", "label": "SOLO vs BOTS"},
	{"id": "online", "label": "PLAY ONLINE"},
]

var _preview: CharacterPreview
var _coins_label: Label
var _gems_label: Label
var _status_label: Label
var _name_plate: Label
var _tagline: Label
var _level_label: Label
var _level_bar: ProgressBar
var _arena_label: Label
var _play_button: Button
var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _difficulty_row: HBoxContainer
var _selected_mode := "bots"

func _ready() -> void:
	_selected_mode = "bots"
	_build()
	GameState.profile_changed.connect(_on_profile_changed)
	GameState.profile_save_failed.connect(_on_profile_save_failed)
	_refresh()
	if not GameState.last_profile_save_error.is_empty():
		_on_profile_save_failed()

# --------------------------------------------------------------------------- #
# Layout
# --------------------------------------------------------------------------- #

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	add_child(MenuDrift.new())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	column.add_child(_build_top_bar())

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 16)
	column.add_child(middle)

	middle.add_child(_build_nav_column())

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 10)
	middle.add_child(centre)

	var stage := Panel.new()
	stage.add_theme_stylebox_override("panel", UiKit.rounded(Color(0.09, 0.06, 0.18, 0.6), 26))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(stage)

	_preview = CharacterPreview.new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_preview)

	_name_plate = UiKit.label("", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_name_plate.name = "PlayerName"
	_name_plate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name_plate.offset_top = -46
	_name_plate.offset_bottom = -12
	stage.add_child(_name_plate)

	centre.add_child(_build_mode_row())
	centre.add_child(_build_difficulty_row())
	centre.add_child(_build_settings_row())
	centre.add_child(_build_play_row())

	_status_label = UiKit.label("", 16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.custom_minimum_size = Vector2(0, 24)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

func _build_top_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 62)

	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	var brand_title := UiKit.title("BOOK BASH", 44)
	brand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.add_child(brand_title)
	_tagline = UiKit.label("Throw. Dodge. Bash.", 16, UiKit.TEXT_DIM)
	brand.add_child(_tagline)
	row.add_child(brand)

	var progress := VBoxContainer.new()
	progress.custom_minimum_size = Vector2(220, 0)
	progress.add_theme_constant_override("separation", 4)
	_level_label = UiKit.label("Level 1", 16, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	progress.add_child(_level_label)
	_level_bar = UiKit.progress_bar()
	_level_bar.custom_minimum_size = Vector2(0, 12)
	_level_bar.max_value = 1.0
	progress.add_child(_level_bar)
	progress.add_child(Control.new())
	row.add_child(progress)

	var coins := UiKit.currency_pill("●", UiKit.COIN)
	var coins_root: Panel = coins["root"]
	coins_root.custom_minimum_size = Vector2(130, 46)
	_coins_label = coins["label"]
	row.add_child(coins_root)

	var gems := UiKit.currency_pill("◆", UiKit.GEM)
	var gems_root: Panel = gems["root"]
	gems_root.custom_minimum_size = Vector2(110, 46)
	_gems_label = gems["label"]
	row.add_child(gems_root)
	return row

func _build_nav_column() -> Control:
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(150, 0)
	nav.add_theme_constant_override("separation", 10)
	var entries := [
		["STORE", "res://scenes/ui/Store.tscn"],
		["CUSTOMIZE", "res://scenes/ui/Customize.tscn"],
		["BATTLE PASS", "res://scenes/ui/BattlePass.tscn"],
		["ARENAS", "res://scenes/ui/MapSelect.tscn"],
		["FRIENDS", "res://scenes/ui/Multiplayer.tscn"],
	]
	for entry in entries:
		var button := UiKit.secondary_button(String(entry[0]), 17)
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		UiKit.wire_audio(button)
		button.pressed.connect(_open.bind(String(entry[1])))
		nav.add_child(button)
	return nav

func _build_mode_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for mode in MODES:
		var button := UiKit.tab_button(String(mode["label"]), 19)
		button.custom_minimum_size = Vector2(210, 46)
		UiKit.wire_audio(button)
		button.pressed.connect(_select_mode.bind(String(mode["id"])))
		row.add_child(button)
		_mode_buttons[String(mode["id"])] = button
	return row

func _build_difficulty_row() -> Control:
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_difficulty_row.add_theme_constant_override("separation", 8)
	_difficulty_row.add_child(UiKit.label("Bot skill", 16, UiKit.TEXT_DIM))
	for difficulty_id in GameState.BOT_DIFFICULTIES:
		var settings: Dictionary = GameState.BOT_DIFFICULTIES[difficulty_id]
		var button := UiKit.tab_button(String(settings.get("name", difficulty_id)), 16)
		button.custom_minimum_size = Vector2(120, 38)
		UiKit.wire_audio(button)
		button.pressed.connect(_select_difficulty.bind(String(difficulty_id)))
		_difficulty_row.add_child(button)
		_difficulty_buttons[String(difficulty_id)] = button
	return _difficulty_row

## Lets a laptop player choose WASD + mouse or the on-screen joystick, and first-
## or third-person view, before the match starts. Saved in the profile.
var _control_buttons: Dictionary = {}
var _view_buttons: Dictionary = {}

func _build_settings_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	# Phones only have touch controls, so the keyboard/joystick picker is desktop-only.
	if not Perf.is_mobile():
		row.add_child(UiKit.label("Controls", 16, UiKit.TEXT_DIM))
		for scheme in GameState.CONTROL_SCHEMES:
			var button := UiKit.tab_button(String(GameState.CONTROL_SCHEMES[scheme]), 15)
			button.custom_minimum_size = Vector2(170, 38)
			UiKit.wire_audio(button)
			button.pressed.connect(func(): _set_setting("controls", scheme))
			row.add_child(button)
			_control_buttons[scheme] = button
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(18, 0)
		row.add_child(spacer)
	row.add_child(UiKit.label("View", 16, UiKit.TEXT_DIM))
	for view in GameState.CAMERA_VIEWS:
		var button := UiKit.tab_button(String(GameState.CAMERA_VIEWS[view]), 15)
		button.custom_minimum_size = Vector2(130, 38)
		UiKit.wire_audio(button)
		button.pressed.connect(func(): _set_setting("camera", view))
		row.add_child(button)
		_view_buttons[view] = button
	return row

func _set_setting(key: String, value: String) -> void:
	if not GameState.set_setting(key, value):
		_status_label.text = GameState.last_profile_save_error
	_refresh()

func _build_play_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_arena_label = UiKit.label("", 17, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	row.add_child(_arena_label)
	_play_button = UiKit.primary_button("PLAY", 38)
	_play_button.custom_minimum_size = Vector2(0, 74)
	UiKit.wire_audio(_play_button)
	_play_button.pressed.connect(_on_play_pressed)
	row.add_child(_play_button)
	return row

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

func _refresh() -> void:
	var profile := GameState.profile
	_coins_label.text = "● %s" % _format_number(int(profile.get("coins", 0)))
	_gems_label.text = "◆ %s" % _format_number(int(profile.get("gems", 0)))
	_level_label.text = "Level %d" % GameState.player_level()
	_level_bar.value = GameState.level_progress()

	var arena: Dictionary = GameState.ARENAS.get(GameState.selected_arena, {})
	var stats: Dictionary = profile.get("stats", {})
	_arena_label.text = "Arena: %s   •   %d wins / %d matches   •   %d knockouts" % [
		arena.get("name", "Sky Library"),
		int(stats.get("wins", 0)), int(stats.get("matches", 0)), int(stats.get("knockouts", 0)),
	]

	if _name_plate:
		_name_plate.text = String(profile.get("player_name", "Reader"))

	for mode_id in _mode_buttons:
		UiKit.set_tab_active(_mode_buttons[mode_id], mode_id == _selected_mode)
	for difficulty_id in _difficulty_buttons:
		UiKit.set_tab_active(_difficulty_buttons[difficulty_id], difficulty_id == GameState.bot_difficulty)
	_difficulty_row.visible = _selected_mode == "bots"
	for scheme in _control_buttons:
		UiKit.set_tab_active(_control_buttons[scheme], scheme == GameState.control_scheme())
	for view in _view_buttons:
		UiKit.set_tab_active(_view_buttons[view], view == GameState.camera_view())
	_play_button.text = "PLAY" if _selected_mode == "bots" else "GO ONLINE"

	if GameState.last_winner_name != "" and _tagline:
		_tagline.text = "Last match winner: %s" % GameState.last_winner_name
	if _preview:
		_preview.refresh()

func _select_mode(mode_id: String) -> void:
	_selected_mode = mode_id
	_refresh()

func _select_difficulty(difficulty_id: String) -> void:
	if not GameState.set_bot_difficulty(difficulty_id):
		_status_label.text = GameState.last_profile_save_error
	_refresh()

func _on_profile_changed(_profile: Dictionary) -> void:
	_refresh()

func _on_profile_save_failed() -> void:
	_status_label.text = GameState.last_profile_save_error

func _format_number(value: int) -> String:
	var text := str(value)
	var output := ""
	while text.length() > 3:
		output = "," + text.right(3) + output
		text = text.left(text.length() - 3)
	return text + output

func _open(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _on_play_pressed() -> void:
	if _selected_mode == "online":
		get_tree().change_scene_to_file("res://scenes/ui/Multiplayer.tscn")
		return
	GameState.game_mode = "bots"
	GameState.network_roster.clear()
	_play_button.disabled = true
	LoadingScreen.go(get_tree(), GameState.get_selected_arena_scene())
