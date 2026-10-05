extends Node
## Dev tool. Builds each arena's decor once and records which kit models it loads,
## then writes res://data/preload_manifest.json for the loading screen.
##
## Runs as a scene (not `-s`) so autoloads like GameState exist. Always pass a
## frame cap so an error can never leave Godot idling:
##   godot --headless --path . res://tools/gen_preload_manifest.tscn --quit-after 300

func _ready() -> void:
	var manifest := {}
	for arena_id in GameState.ARENAS:
		ArenaBuilder.recorded_paths.clear()
		var decor := ThemedArenaDecor.new()
		decor.arena_id = String(arena_id)
		var started := Time.get_ticks_msec()
		add_child(decor)
		var elapsed := Time.get_ticks_msec() - started
		var paths: Array = ArenaBuilder.recorded_paths.keys()
		paths.sort()
		manifest[String(GameState.ARENAS[arena_id]["scene"])] = paths
		print("%s: %d models, built in %d ms" % [arena_id, paths.size(), elapsed])
		remove_child(decor)
		decor.free()
	DirAccess.make_dir_recursive_absolute("res://data")
	var file := FileAccess.open("res://data/preload_manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("could not write manifest")
	else:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
		print("MANIFEST_OK")
	get_tree().quit()
