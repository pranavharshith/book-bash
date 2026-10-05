extends SceneTree
## Dev-only: prints the world-space bounds of kit models (after ArenaBuilder's kit
## scale) so level layout can be built against measured, not guessed, sizes.
##
##   godot --headless --path . --script res://tools/measure_kits.gd -- dungeon:wall furniture:desk

const SCALES := {"dungeon": 1.0, "furniture": 2.2, "castle": 3.0, "props": 1.0, "raw": 1.0}
const EXT := {"dungeon": ".gltf", "furniture": ".glb", "castle": ".glb", "props": ".gltf"}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split(":", true, 1)
		var kit := parts[0]
		var path := ""
		if kit == "raw":
			path = parts[1]
		else:
			path = "res://assets/models/kits/%s/%s%s" % [kit, parts[1], EXT[kit]]
		if not ResourceLoader.exists(path):
			print("MISSING ", path)
			continue
		var node := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(node)
		node.scale = Vector3.ONE * float(SCALES[kit])
		var box := _bounds(node, node.global_transform)
		print("%-34s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f)" % [
			arg, box.size.x, box.size.y, box.size.z, box.position.x, box.position.y, box.position.z])
		node.queue_free()
	quit()

func _bounds(node: Node, _root_xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh in _meshes(node):
		var b := mesh.global_transform * mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for c in node.get_children():
		found.append_array(_meshes(c))
	return found
