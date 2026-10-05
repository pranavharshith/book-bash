class_name PlayerAnimationState
extends RefCounted
## Dynamic AnimationTree wrapper for the AnimationPlayer inside each loaded GLB.
## Clip lookup tolerates Godot's imported library prefixes and falls back to direct
## AnimationPlayer control if a future cosmetic model lacks a complete combat set.

const CLIP_IDLE := "Idle"
const CLIP_RUN := "Run"
const CLIP_WALK := "Walk"
const CLIP_THROW := "Throw"
const CLIP_HIT := "Hit"
const CLIP_DODGE := "Dodge"
const CLIP_KO := "KO"

const CLIPS := [CLIP_IDLE, CLIP_RUN, CLIP_WALK, CLIP_THROW, CLIP_HIT, CLIP_DODGE, CLIP_KO]
const LOOPING_CLIPS := [CLIP_IDLE, CLIP_RUN, CLIP_WALK]

var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _resolved: Dictionary = {}
var _using_tree := false
var _locked_until_finished := false
var _lock_ends_at_msec := 0
var _current := ""

func _init(animation_player: AnimationPlayer, model_root: Node = null) -> void:
	_player = animation_player
	if _player == null:
		return
	for clip in CLIPS:
		var found := _resolve(clip)
		if not found.is_empty():
			_resolved[clip] = found
	# Imported locomotion strips may not be marked to loop in their source GLB.
	for clip in LOOPING_CLIPS:
		var anim := _get_animation(clip)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
	if not _build_animation_tree(model_root):
		_player.animation_finished.connect(_on_animation_finished)

func _build_animation_tree(model_root: Node) -> bool:
	if model_root == null:
		return false
	for clip in CLIPS:
		if not _resolved.has(clip):
			return false
	var machine := AnimationNodeStateMachine.new()
	for index in CLIPS.size():
		var clip: String = CLIPS[index]
		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = _resolved[clip]
		machine.add_node(clip, animation_node, Vector2((index % 4) * 240.0, (index / 4) * 160.0))
	for from_clip in CLIPS:
		for to_clip in CLIPS:
			if from_clip == to_clip:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.15 if from_clip in LOOPING_CLIPS and to_clip in LOOPING_CLIPS else 0.08
			machine.add_transition(from_clip, to_clip, transition)
	_tree = AnimationTree.new()
	_tree.name = "CombatAnimationTree"
	_tree.tree_root = machine
	model_root.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		_tree.queue_free()
		_tree = null
		return false
	_playback.start(CLIP_IDLE)
	_using_tree = true
	_current = CLIP_IDLE
	return true

func _resolve(clip: String) -> String:
	if _player == null:
		return ""
	var names := _player.get_animation_list()
	for name in names:
		if name == clip:
			return name
	for name in names:
		if name.get_slice("/", name.get_slice_count("/") - 1) == clip:
			return name
	for name in names:
		if name.to_lower().contains(clip.to_lower()):
			return name
	return ""

func _get_animation(clip: String) -> Animation:
	if not _resolved.has(clip):
		return null
	return _player.get_animation(_resolved[clip])

func has_clip(clip: String) -> bool:
	return _resolved.has(clip)

## Plays locomotion. AnimationTree keeps transitions blended while an action lock
## prevents movement clips from interrupting Throw, Hit, or Dodge.
func play_loop(clip: String, speed: float = 1.0) -> void:
	if _is_locked() or _player == null or not _resolved.has(clip):
		return
	if _using_tree:
		if _current == clip:
			return
		_current = clip
		_playback.travel(clip)
		return
	var target: String = _resolved[clip]
	if _current == target:
		_player.speed_scale = speed
		return
	_current = target
	_player.speed_scale = speed
	_player.play(target, 0.15)

## Plays an action state. Tree playback uses the source clip's duration for its
## lock timer; direct playback retains its signal-driven compatibility fallback.
func play_action(clip: String, speed: float = 1.0, hold: bool = false) -> void:
	if _player == null or not _resolved.has(clip):
		return
	var anim := _get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if hold else Animation.LOOP_NONE
	if _using_tree:
		_current = clip
		_locked_until_finished = not hold
		_lock_ends_at_msec = Time.get_ticks_msec() + int((anim.length if anim else 0.1) * 1000.0 / maxf(speed, 0.01)) if not hold else 0
		_playback.travel(clip)
		return
	var target: String = _resolved[clip]
	_locked_until_finished = not hold
	_current = target
	_player.speed_scale = speed
	_player.play(target, 0.08)

func clear_lock() -> void:
	_locked_until_finished = false
	_lock_ends_at_msec = 0

func is_locked() -> bool:
	return _is_locked()

func _is_locked() -> bool:
	if _using_tree and _locked_until_finished and Time.get_ticks_msec() >= _lock_ends_at_msec:
		_locked_until_finished = false
		_lock_ends_at_msec = 0
		_current = ""
	return _locked_until_finished

func _on_animation_finished(_anim_name: StringName) -> void:
	_locked_until_finished = false
	_current = ""
