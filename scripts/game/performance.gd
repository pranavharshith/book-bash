class_name Perf
extends Node
## Autoload "PerfSetup" (class `Perf` for the static helpers): one place that decides how heavy the game is allowed to be.
##
## On phones the biggest costs are fill-rate (the 3D view renders at native
## resolution, often 2400x1080 or more), MSAA, full-screen post effects, and
## shadow passes over hundreds of static props. Everything here is skipped on
## desktop unless the game is launched with `-- --mobile` for testing.

## Target height of the 3D render. UI is drawn separately at full resolution, so
## text and buttons stay sharp while the 3D scene is cheaper to fill.
const MOBILE_RENDER_HEIGHT := 576.0
const MOBILE_MIN_SCALE := 0.5
const MOBILE_MAX_FPS := 60

## Accent/omni lights allowed per arena. Each one costs every pixel it touches.
const MOBILE_MAX_ACCENT_LIGHTS := 6

static var _forced := false

static func is_mobile() -> bool:
	return _forced or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

func _init() -> void:
	_forced = OS.get_cmdline_user_args().has("--mobile")

func _ready() -> void:
	if not is_mobile():
		return
	Engine.max_fps = MOBILE_MAX_FPS
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	var window := get_window()
	window.positional_shadow_atlas_size = 512
	window.msaa_3d = Viewport.MSAA_DISABLED
	window.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	window.use_taa = false
	window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	window.size_changed.connect(_apply_resolution_scale)
	_apply_resolution_scale()

## Scales the 3D render so its height is about MOBILE_RENDER_HEIGHT pixels.
func _apply_resolution_scale() -> void:
	var window := get_window()
	var screen_height := float(minf(window.size.x, window.size.y))
	if screen_height <= 0.0:
		return
	window.scaling_3d_scale = clampf(MOBILE_RENDER_HEIGHT / screen_height, MOBILE_MIN_SCALE, 1.0)
