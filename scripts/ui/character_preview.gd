class_name CharacterPreview
extends SubViewportContainer
## Rotating 3D character preview for the Lobby and Customize screens.
##
## Renders the equipped look through a `SubViewport` so a real 3D model can sit
## inside a Control layout, and rebuilds on demand when cosmetics change.

const PREVIEW_ENV_SKY_TOP := Color("3d2a63")
const PREVIEW_ENV_HORIZON := Color("6c4f9c")

var _viewport: SubViewport
var _world_root: Node3D
var _model_holder: Node3D
var _model_root: Node3D
var _skeleton: Skeleton3D
var _spin := 0.0
var _animation: PlayerAnimationState

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

func _ready() -> void:
	_build_world()
	refresh()

func _build_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "PreviewWorld"
	_viewport.add_child(_world_root)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = PREVIEW_ENV_SKY_TOP
	sky_material.sky_horizon_color = PREVIEW_ENV_HORIZON
	sky_material.ground_horizon_color = PREVIEW_ENV_HORIZON
	sky_material.ground_bottom_color = PREVIEW_ENV_SKY_TOP.darkened(0.4)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9d8fc4")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world_root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, 28, 0)
	key.light_energy = 1.1
	key.light_color = Color("fff1d9")
	_world_root.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14, -140, 0)
	rim.light_energy = 0.55
	rim.light_color = Color("8fb4ff")
	_world_root.add_child(rim)

	# Framed for a ~1.7 m rig: high enough to keep the hat in shot, far enough that
	# a tall cosmetic (wizard hat) does not clip the top of the panel.
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(0, 1.1, 4.4)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	_world_root.add_child(camera)

	_model_holder = Node3D.new()
	_model_holder.name = "ModelHolder"
	_world_root.add_child(_model_holder)
	_build_stage()

## Pedestal, glow ring, and a ring of orbiting books so the hub screen is alive
## instead of a figure standing on nothing.
var _orbit: Node3D

func _build_stage() -> void:
	var pedestal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 0.85
	mesh.height = 0.16
	mesh.radial_segments = 40
	pedestal.mesh = mesh
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("3a2a5e")
	stone.roughness = 0.6
	pedestal.material_override = stone
	pedestal.position = Vector3(0, -0.08, 0)
	_world_root.add_child(pedestal)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.86
	torus.rings = 48
	ring.mesh = torus
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.78, 0.25)
	ring.material_override = glow
	ring.scale = Vector3(1, 0.3, 1)
	_world_root.add_child(ring)
	var spot := OmniLight3D.new()
	spot.position = Vector3(0, 0.4, 0.9)
	spot.light_color = Color("ffd27a")
	spot.light_energy = 0.8
	spot.omni_range = 3.0
	_world_root.add_child(spot)

	_orbit = Node3D.new()
	_world_root.add_child(_orbit)
	if ResourceLoader.exists(GameState.BOOK_MODEL):
		var scene := load(GameState.BOOK_MODEL) as PackedScene
		var styles := ["book_classic", "book_flame", "book_frost", "book_gold"]
		for i in range(6):
			var book := scene.instantiate() as Node3D
			_orbit.add_child(book)
			var angle := TAU * i / 6.0
			book.position = Vector3(cos(angle) * 1.15, 0.6 + 0.9 * float(i % 3) / 2.0, sin(angle) * 1.15)
			book.rotation = Vector3(0.3, -angle, 0.4)
			book.scale = Vector3.ONE * 0.8
			GameState.apply_book_style(book, styles[i % styles.size()])

## Rebuilds the preview from the currently equipped cosmetics.
func refresh() -> void:
	if _model_holder == null:
		return
	for child in _model_holder.get_children():
		_model_holder.remove_child(child)
		child.queue_free()
	_model_root = null
	_skeleton = null
	_animation = null

	var equipped := GameState.get_equipped_cosmetics()
	var skin := GameState.find_cosmetic(String(equipped.get("skin", "skin_blue")))
	var model_path := String(skin.get("model", GameState.DEFAULT_MODEL))
	if not ResourceLoader.exists(model_path):
		model_path = GameState.DEFAULT_MODEL
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	_model_root = scene.instantiate()
	# The rig is authored facing +Z and the preview camera sits on +Z, so no yaw
	# correction here — the in-match fighter needs one only because Godot's
	# `looking_at()` aims -Z.
	_model_holder.add_child(_model_root)
	_skeleton = _find(_model_root, "Skeleton3D") as Skeleton3D

	# Resolve the character's own AnimationPlayer *before* attaching cosmetics.
	# Accessory GLBs ship their own AnimationPlayer, and a depth-first search after
	# attachment picked one of those up, leaving the character stuck in rest pose.
	var player := _find(_model_root, "AnimationPlayer") as AnimationPlayer

	_attach(String(equipped.get("hat", "hat_default")), "PreviewHat", true)
	_attach(String(equipped.get("accessory", "acc_none")), "PreviewAccessory", false)
	_attach_book(String(equipped.get("book", "book_classic")))

	if player:
		_animation = PlayerAnimationState.new(player, _model_root)
		_animation.play_loop(PlayerAnimationState.CLIP_IDLE)

func play_emote() -> void:
	if _animation:
		_animation.play_action(PlayerAnimationState.CLIP_THROW, 1.0)

func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found:
			return found
	return null

func _attach(item_id: String, node_name: String, is_hat: bool) -> void:
	var item := GameState.find_cosmetic(item_id)
	var model := String(item.get("model", ""))
	var baked := _skeleton.get_node_or_null("Hat_010") if _skeleton else null
	if is_hat and baked:
		(baked as Node3D).visible = model.is_empty() and item_id != "hat_bare"
	if model.is_empty() or _skeleton == null:
		return
	var bone := _skeleton.find_bone("Head")
	if bone < 0 or not ResourceLoader.exists(model):
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = node_name
	_skeleton.add_child(attachment)
	attachment.bone_name = "Head"
	var holder := Node3D.new()
	attachment.add_child(holder)
	holder.add_child(load(model).instantiate())
	holder.transform = _skeleton.get_bone_global_rest(bone).affine_inverse()
	_strip_skinning(holder)

func _attach_book(book_id: String) -> void:
	if _skeleton == null or not ResourceLoader.exists(GameState.BOOK_MODEL):
		return
	var bone := _skeleton.find_bone("RightHandProp")
	if bone < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "PreviewBook"
	_skeleton.add_child(attachment)
	attachment.bone_name = "RightHandProp"
	var holder := Node3D.new()
	attachment.add_child(holder)
	holder.add_child(load(GameState.BOOK_MODEL).instantiate())
	# The book is a standalone prop, not a skinned mesh of this rig, so it takes a
	# plain hand-local placement rather than the rest-pose correction the
	# hats/glasses need. Applying that correction left it floating beside the body.
	holder.transform = Fighter.CARRIED_BOOK_LOCAL
	_strip_skinning(holder)
	GameState.apply_book_style(holder, book_id)

func _strip_skinning(node: Node) -> void:
	if node is AnimationPlayer or node is AnimationTree:
		node.queue_free()
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.skeleton = NodePath()
		mesh_instance.skin = null
	if node is Skeleton3D:
		var parent := node.get_parent()
		for child in node.get_children():
			node.remove_child(child)
			parent.add_child(child)
			_strip_skinning(child)
		node.queue_free()
		return
	for child in node.get_children().duplicate():
		_strip_skinning(child)

func _process(delta: float) -> void:
	if _model_holder == null:
		return
	# `stretch` makes the container own the SubViewport's size; setting it manually
	# here just warns every frame.
	_spin += delta
	_model_holder.rotation.y = sin(_spin * 0.4) * 0.7
	if _orbit:
		_orbit.rotation.y += delta * 0.6
		for i in range(_orbit.get_child_count()):
			var book := _orbit.get_child(i) as Node3D
			book.position.y = 0.6 + 0.45 * float(i % 3) + sin(_spin * 1.5 + i) * 0.08
			book.rotate_y(delta * 1.2)
