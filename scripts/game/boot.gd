extends Node
## Entry point: immediately hands off to the Lobby. Kept as a separate tiny
## scene (rather than making Lobby the main scene) so a future splash/loading
## screen can be inserted here without touching project.godot again.

func _ready() -> void:
	call_deferred("_go_to_lobby")

func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")
