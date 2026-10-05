class_name LoadingScreen
extends CanvasLayer
## Full-screen loading overlay used for every "go to the arena" transition.
##
## The old flow called `change_scene_to_file()` straight from the PLAY button,
## which loaded the arena, every character model, and every kit model on the main
## thread: the lobby froze for a couple of seconds with no feedback. This overlay
## draws immediately, streams all of that on background threads, swaps the scene,
## then stays up for a few frames so the arena's first-frame shader compiles also
## happen behind it rather than as a visible hitch.
##
## It lives on the root (not inside a scene), so it survives the scene change.

const MANIFEST_PATH := "res://data/preload_manifest.json"
## Frames to keep covering the arena after it is ready (first-draw shader compiles).
const SETTLE_FRAMES := 4
const FADE_TIME := 0.25
const WARMUP_HEADINGS := 8
const WARMUP_OVERHEAD := 2

## Keeps the preloaded resources referenced so the cache does not drop them
## before the arena instantiates them. Replaced on the next load.
static var _held: Array[Resource] = []
static var _active: LoadingScreen

var _target := ""
var _pending: Array[String] = []
var _total := 1
var _bar: ProgressBar
var _status: Label
var _phase := 0          # 0 loading, 1 switching, 2 settling
var _settle := 0
var _scene: PackedScene

## Starts a transition to `scene_path`. Safe to call from any screen.
static func go(tree: SceneTree, scene_path: String) -> void:
	if _active and is_instance_valid(_active):
		return
	var screen := LoadingScreen.new()
	screen._target = scene_path
	_active = screen
	tree.root.add_child(screen)

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_queue_loads()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow input so nothing underneath reacts while loading.
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.add_child(UiKit.backdrop())

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(520, 0)
	column.position = Vector2(-260, -90)
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(column)

	column.add_child(UiKit.title("BOOK BASH", 52))
	var arena_name := _arena_name_for(_target)
	column.add_child(UiKit.label("Entering %s" % arena_name if not arena_name.is_empty() else "Loading", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_bar = UiKit.progress_bar()
	_bar.custom_minimum_size = Vector2(0, 16)
	_bar.max_value = 1.0
	column.add_child(_bar)
	_status = UiKit.label("Loading arena…", 16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_status)

func _arena_name_for(scene_path: String) -> String:
	for arena_id in GameState.ARENAS:
		if String(GameState.ARENAS[arena_id].get("scene", "")) == scene_path:
			return String(GameState.ARENAS[arena_id].get("name", ""))
	return ""

# --------------------------------------------------------------------------- #
# Loading
# --------------------------------------------------------------------------- #

func _queue_loads() -> void:
	_held.clear()
	var paths: Dictionary = {}
	paths[_target] = true
	paths[GameState.BOOK_MODEL] = true
	paths[GameState.DEFAULT_MODEL] = true
	for entry in GameState.get_active_roster():
		var model := String(entry.get("model", ""))
		if not model.is_empty():
			paths[model] = true
		var cosmetics: Dictionary = entry.get("cosmetics", {})
		for slot in ["hat", "accessory"]:
			var item := GameState.find_cosmetic(String(cosmetics.get(slot, "")))
			var cosmetic_model := String(item.get("model", ""))
			if not cosmetic_model.is_empty():
				paths[cosmetic_model] = true
	for kit_path in _manifest_paths(_target):
		paths[kit_path] = true

	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", true) == OK:
			_pending.append(path)
	_total = maxi(_pending.size(), 1)

func _manifest_paths(scene_path: String) -> Array:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary:
		return (parsed as Dictionary).get(scene_path, [])
	return []

func _process(_delta: float) -> void:
	match _phase:
		0:
			_poll_loads()
		1:
			_switch_scene()
		2:
			_warm_up_step()

func _poll_loads() -> void:
	var index := _pending.size() - 1
	while index >= 0:
		var path := _pending[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource:
				_held.append(resource)
				if path == _target:
					_scene = resource as PackedScene
			_pending.remove_at(index)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_warning("LoadingScreen: could not preload %s" % path)
			_pending.remove_at(index)
		index -= 1
	_bar.value = 1.0 - float(_pending.size()) / float(_total)
	if _pending.is_empty():
		_status.text = "Building arena…"
		_bar.value = 1.0
		_phase = 1   # next frame, so the full bar is drawn before the build

func _switch_scene() -> void:
	_phase = 2
	var error := get_tree().change_scene_to_packed(_scene) if _scene else get_tree().change_scene_to_file(_target)
	if error != OK:
		push_error("LoadingScreen: scene change failed (%d)" % error)
		queue_free()

## Behind the overlay, swings the match camera through eight headings and then
## the overhead spectator view, one pose per frame. Each pose draws materials
## that have not been seen yet, so their shaders compile now rather than as a
## hitch the first time the player turns around or gets knocked out.
func _warm_up_step() -> void:
	var scene := get_tree().current_scene
	var rig := scene.get_node_or_null("CameraRig") as MatchCamera if scene else null
	var decor := scene.get_node_or_null("ArenaDecor") as ThemedArenaDecor if scene else null
	if rig == null:
		# Not an arena (or not ready yet): just cover a few frames.
		_settle += 1
		if _settle >= SETTLE_FRAMES + 30 or (scene != null and _settle >= SETTLE_FRAMES):
			_phase = 3
			_fade_out()
		return
	_status.text = "Warming up…"
	if _settle < WARMUP_HEADINGS:
		rig.warmup_pose(_settle, false)
	elif _settle < WARMUP_HEADINGS + WARMUP_OVERHEAD:
		if decor and _settle == WARMUP_HEADINGS:
			decor.set_overhead_view(true)
		rig.warmup_pose(_settle - WARMUP_HEADINGS, true)
	elif _settle == WARMUP_HEADINGS + WARMUP_OVERHEAD:
		if decor:
			decor.set_overhead_view(false)
		rig.end_warmup()
	elif _settle >= WARMUP_HEADINGS + WARMUP_OVERHEAD + SETTLE_FRAMES:
		_phase = 3
		_fade_out()
	_settle += 1

func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(get_child(0), "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(_finish)

func _finish() -> void:
	print_verbose("LoadingScreen: done at %d ms" % Time.get_ticks_msec())
	if OS.get_cmdline_user_args().has("--bb-autoplay"):
		print("[probe] loading finished at %d ms" % Time.get_ticks_msec())
	if _active == self:
		_active = null
	queue_free()
