extends Node
## SFX playback, registered as the `Audio` autoload.
##
## Callers ask for a *logical* sound ("impact", "footstep", "ui_click") and this
## picks a random variant from the Kenney sets. Randomising variants is what stops
## a fast-paced brawler from sounding like a machine gun of one identical click.
##
##     Audio.play_at("impact", global_position)     # positional 3D one-shot
##     Audio.play_ui("click")                       # flat UI feedback

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const MAX_CONCURRENT := 24

## Logical name -> interchangeable variant files.
const SOUNDS := {
	"impact": ["impactBell_heavy_000.ogg", "impactBell_heavy_001.ogg", "impactBell_heavy_002.ogg"],
	"impact_body": ["impactPunch_heavy_000.ogg", "impactPunch_heavy_002.ogg", "impactPunch_medium_001.ogg", "impactPunch_medium_003.ogg"],
	"impact_wood": ["impactWood_heavy_000.ogg", "impactWood_heavy_002.ogg", "impactWood_medium_001.ogg", "impactWood_medium_003.ogg"],
	"impact_light": ["impactWood_light_000.ogg", "impactWood_light_002.ogg", "impactGeneric_light_000.ogg", "impactGeneric_light_002.ogg"],
	"impact_soft": ["impactSoft_heavy_001.ogg", "impactSoft_medium_000.ogg"],
	"impact_metal": ["impactMetal_heavy_001.ogg", "impactMetal_light_000.ogg", "impactTin_medium_000.ogg"],
	"impact_glass": ["impactGlass_light_001.ogg"],
	"collapse": ["impactMining_002.ogg", "impactPlank_medium_000.ogg", "impactPlank_medium_002.ogg"],
	"footstep": ["footstep_wood_000.ogg", "footstep_wood_001.ogg", "footstep_wood_002.ogg", "footstep_wood_003.ogg"],
	"footstep_alt": ["footstep_carpet_000.ogg", "footstep_carpet_002.ogg"],
	"footstep_stone": ["footstep_concrete_000.ogg", "footstep_concrete_002.ogg"],
	"footstep_soft": ["footstep_grass_001.ogg", "footstep_snow_001.ogg"],
	"throw": ["switch7.ogg", "switch11.ogg"],
	"dodge": ["switch1.ogg", "switch2.ogg"],
	"shield": ["switch26.ogg"],
	"pickup": ["switch19.ogg", "switch33.ogg"],
	"power_up": ["click5.ogg", "switch33.ogg"],
	"click": ["click1.ogg", "click2.ogg"],
	"back": ["mouserelease1.ogg"],
	"hover": ["rollover1.ogg", "rollover2.ogg", "rollover4.ogg"],
	"error": ["click3.ogg"],
	"countdown": ["mouseclick1.ogg"],
	"go": ["impactBell_heavy_000.ogg"],
	"ko": ["impactSoft_heavy_001.ogg"],
	"victory": ["impactBell_heavy_002.ogg"],
}

var sfx_volume := 1.0
var music_volume := 0.6

var _cache: Dictionary = {}
var _live := 0
var _music_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _exit_tree() -> void:
	# Device and headless shutdown can interrupt OGG playback before the normal
	# `finished` callback runs. Stop managed players explicitly so scene teardown
	# does not retain live playback references.
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("book_bash_one_shot_audio"):
			if node.has_method("stop"):
				node.call("stop")
			node.queue_free()
	for child in get_children():
		if child.has_method("stop"):
			child.call("stop")
		child.queue_free()
	_cache.clear()

func _variant(sound_name: String) -> AudioStream:
	var files: Array = SOUNDS.get(sound_name, [])
	if files.is_empty():
		return null
	var file := String(files[_rng.randi() % files.size()])
	if _cache.has(file):
		return _cache[file]
	var path := SFX_DIR + file
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	_cache[file] = stream
	return stream

## Positional one-shot for impacts, footsteps, pickups.
func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.12) -> void:
	if _live >= MAX_CONCURRENT or sfx_volume <= 0.001:
		return
	var stream := _variant(sound_name)
	if stream == null:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db + linear_to_db(sfx_volume)
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.max_distance = 34.0
	player.unit_size = 6.0
	player.add_to_group("book_bash_one_shot_audio")
	tree.current_scene.add_child(player)
	player.global_position = position
	player.play()
	_track(player, stream)

## Flat, non-positional one-shot for UI feedback.
func play_ui(sound_name: String, volume_db: float = 0.0) -> void:
	if _live >= MAX_CONCURRENT or sfx_volume <= 0.001:
		return
	var stream := _variant(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db + linear_to_db(sfx_volume)
	player.pitch_scale = 1.0 + _rng.randf_range(-0.05, 0.05)
	player.add_to_group("book_bash_one_shot_audio")
	add_child(player)
	player.play()
	_track(player, stream)

## Music is an external dependency: no licensed track ships with the repo yet, so
## this looks for one and stays silent (rather than failing) when none exists.
func play_music(track_name: String) -> void:
	var path := MUSIC_DIR + track_name
	if not ResourceLoader.exists(path):
		return
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = "Master"
		add_child(_music_player)
	_music_player.stream = load(path)
	_music_player.volume_db = linear_to_db(maxf(music_volume, 0.001))
	_music_player.play()

func stop_music() -> void:
	if _music_player:
		_music_player.stop()

## Frees a one-shot player once it is done. `finished` is the normal path, but a
## backstop timer is also armed because a stream that never actually starts
## (dummy audio driver, no output device) never emits `finished`, and those nodes
## would otherwise accumulate for the whole match.
func _track(player: Node, stream: AudioStream) -> void:
	_live += 1
	var length := stream.get_length()
	if length <= 0.0:
		length = 3.0
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = length + 0.5
	guard.autostart = true
	guard.timeout.connect(_release.bind(player))
	player.add_child(guard)
	if player.has_signal("finished"):
		player.connect("finished", _release.bind(player))

func _release(player: Node) -> void:
	if player == null or not is_instance_valid(player) or player.is_queued_for_deletion():
		return
	_live = maxi(_live - 1, 0)
	player.queue_free()
