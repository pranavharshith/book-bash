extends Node
## Global match configuration, selected mode/map, cosmetic catalogue, and the
## persistent local profile. Registered as the `GameState` autoload.

signal profile_changed(profile: Dictionary)
signal profile_save_failed()
signal selection_changed()

const MATCH_DURATION := 150.0
const MAX_FIGHTERS := 6
const PROFILE_VERSION := 3

const DEFAULT_MODEL := "res://assets/models/characters/player_blue.glb"
const BOOK_MODEL := "res://assets/models/props/book.glb"
const COSMETIC_DIR := "res://assets/models/cosmetics/"

## Difficulty presets for the solo/bots mode. Reaction time and aim discipline
## are the two levers that actually change how hard a bot feels to fight.
const BOT_DIFFICULTIES := {
	"casual": {"name": "Casual", "reaction": 0.46, "accuracy": 0.55, "aggression": 0.55, "dodge_chance": 0.25},
	"normal": {"name": "Normal", "reaction": 0.3, "accuracy": 0.75, "aggression": 0.75, "dodge_chance": 0.45},
	"brutal": {"name": "Brutal", "reaction": 0.17, "accuracy": 0.94, "aggression": 0.95, "dodge_chance": 0.7},
}

const ROSTER := [
	{"name": "You", "color": Color(0.30, 0.62, 1.00), "model": "res://assets/models/characters/player_blue.glb", "is_bot": false, "peer_id": 1},
	{"name": "Rex", "color": Color(1.00, 0.32, 0.30), "model": "res://assets/models/characters/bot_red.glb", "is_bot": true, "peer_id": 0},
	{"name": "Mint", "color": Color(0.36, 0.88, 0.42), "model": "res://assets/models/characters/bot_green.glb", "is_bot": true, "peer_id": 0},
	{"name": "Nova", "color": Color(0.72, 0.42, 1.00), "model": "res://assets/models/characters/bot_purple.glb", "is_bot": true, "peer_id": 0},
	{"name": "Page", "color": Color(1.00, 0.62, 0.26), "model": "res://assets/models/characters/bot_red.glb", "is_bot": true, "peer_id": 0},
	{"name": "Ink", "color": Color(0.24, 0.84, 0.88), "model": "res://assets/models/characters/bot_green.glb", "is_bot": true, "peer_id": 0},
]

const ROSTER_COLORS := [
	Color(0.30, 0.62, 1.00), Color(1.00, 0.32, 0.30), Color(0.36, 0.88, 0.42),
	Color(0.72, 0.42, 1.00), Color(1.00, 0.62, 0.26), Color(0.24, 0.84, 0.88),
]

const ARENAS := {
	"sky_library": {
		"name": "Sky Library", "scene": "res://scenes/arenas/SkyLibrary.tscn",
		"description": "Enclosed reading hall in the clouds",
		"tint": Color(0.42, 0.60, 0.86), "accent": Color(0.91, 0.74, 0.29),
	},
	"classroom_chaos": {
		"name": "Classroom Chaos", "scene": "res://scenes/arenas/ClassroomChaos.tscn",
		"description": "Desk cover and surprise supply drops",
		"tint": Color(0.36, 0.55, 0.44), "accent": Color(0.89, 0.79, 0.34),
	},
	"ancient_ruins": {
		"name": "Ancient Ruins", "scene": "res://scenes/arenas/AncientRuins.tscn",
		"description": "Collapsing shelves and broken stone",
		"tint": Color(0.48, 0.45, 0.35), "accent": Color(0.83, 0.66, 0.26),
	},
	"tech_tower": {
		"name": "Tech Tower", "scene": "res://scenes/arenas/TechTower.tscn",
		"description": "Conveyor floors shove your aim",
		"tint": Color(0.15, 0.21, 0.30), "accent": Color(0.13, 0.84, 0.90),
	},
	"candy_island": {
		"name": "Candy Island", "scene": "res://scenes/arenas/CandyIsland.tscn",
		"description": "Sticky syrup and bouncy gumdrops",
		"tint": Color(0.94, 0.72, 0.80), "accent": Color(1.00, 0.89, 0.45),
	},
	"volcano_core": {
		"name": "Volcano Core", "scene": "res://scenes/arenas/VolcanoCore.tscn",
		"description": "The safe zone closes in",
		"tint": Color(0.30, 0.16, 0.17), "accent": Color(1.00, 0.36, 0.15),
	},
}

## Data-driven cosmetics. Adding an item is a row here plus (optionally) a model
## path; no new code is required, which is what the plan asked for in section 8.
const COSMETICS := [
	# --- Skins ------------------------------------------------------------- #
	{"id": "skin_blue", "name": "Sky Scholar", "category": "skin", "currency": "coins", "price": 0, "color": Color(0.30, 0.62, 1.00), "model": "res://assets/models/characters/player_blue.glb"},
	{"id": "skin_red", "name": "Crimson Reader", "category": "skin", "currency": "coins", "price": 450, "color": Color(1.00, 0.32, 0.30), "model": "res://assets/models/characters/bot_red.glb"},
	{"id": "skin_green", "name": "Mint Mage", "category": "skin", "currency": "coins", "price": 600, "color": Color(0.36, 0.88, 0.42), "model": "res://assets/models/characters/bot_green.glb"},
	{"id": "skin_purple", "name": "Nova Scribe", "category": "skin", "currency": "gems", "price": 40, "color": Color(0.72, 0.42, 1.00), "model": "res://assets/models/characters/bot_purple.glb"},

	# --- Books ------------------------------------------------------------- #
	{"id": "book_classic", "name": "Classic Hardcover", "category": "book", "currency": "coins", "price": 0, "color": Color("8d3f2d"), "emission": 0.0},
	{"id": "book_flame", "name": "Flame Tome", "category": "book", "currency": "coins", "price": 700, "color": Color("d9482b"), "emission": 1.4},
	{"id": "book_frost", "name": "Frosted Pages", "category": "book", "currency": "gems", "price": 30, "color": Color("69cce6"), "emission": 0.9},
	{"id": "book_gold", "name": "Gilded Codex", "category": "book", "currency": "coins", "price": 999, "color": Color("e8bb46"), "emission": 1.1},
	{"id": "book_arcane", "name": "Arcane Grimoire", "category": "book", "currency": "gems", "price": 55, "color": Color("8a5cf0"), "emission": 1.6},
	{"id": "book_rainbow", "name": "Prism Reader", "category": "book", "currency": "gems", "price": 80, "color": Color("57e0c0"), "emission": 1.8},

	# --- Hats -------------------------------------------------------------- #
	{"id": "hat_default", "name": "Study Cap", "category": "hat", "currency": "coins", "price": 0, "color": Color("6f7f4a")},
	{"id": "hat_bare", "name": "No Hat", "category": "hat", "currency": "coins", "price": 0, "color": Color("4a4356")},
	{"id": "hat_wizard", "name": "Wizard Hat", "category": "hat", "currency": "coins", "price": 500, "color": Color("5f42b0"), "model": COSMETIC_DIR + "Hat_049.glb"},
	{"id": "hat_winter", "name": "Winter Beanie", "category": "hat", "currency": "coins", "price": 650, "color": Color("d8e6ee"), "model": COSMETIC_DIR + "Hat_057.glb"},
	{"id": "hat_hair_spike", "name": "Spiked Hair", "category": "hat", "currency": "coins", "price": 380, "color": Color("6b4630"), "model": COSMETIC_DIR + "Hairstyle_male_012.glb"},

	# --- Accessories ------------------------------------------------------- #
	{"id": "acc_none", "name": "None", "category": "accessory", "currency": "coins", "price": 0, "color": Color("4a4356")},
	{"id": "acc_glasses", "name": "Reading Glasses", "category": "accessory", "currency": "coins", "price": 260, "color": Color("8fd0e8"), "model": COSMETIC_DIR + "Glasses_004.glb"},
	{"id": "acc_shades", "name": "Cool Shades", "category": "accessory", "currency": "coins", "price": 420, "color": Color("2b2b33"), "model": COSMETIC_DIR + "Glasses_006.glb"},
	{"id": "acc_headphones", "name": "Headphones", "category": "accessory", "currency": "gems", "price": 35, "color": Color("ff6fa8"), "model": COSMETIC_DIR + "Headphones_002.glb"},
	{"id": "acc_clown", "name": "Clown Nose", "category": "accessory", "currency": "coins", "price": 300, "color": Color("e2413f"), "model": COSMETIC_DIR + "Clown_nose_001.glb"},
	{"id": "acc_moustache", "name": "Grand Moustache", "category": "accessory", "currency": "coins", "price": 340, "color": Color("52351f"), "model": COSMETIC_DIR + "Moustache_002.glb"},

	# --- Trails ------------------------------------------------------------ #
	{"id": "trail_paper", "name": "Paper Trail", "category": "trail", "currency": "coins", "price": 0, "color": Color(1.0, 0.88, 0.55)},
	{"id": "trail_fire", "name": "Fire Trail", "category": "trail", "currency": "coins", "price": 850, "color": Color("ff6a2d")},
	{"id": "trail_frost", "name": "Frost Trail", "category": "trail", "currency": "coins", "price": 900, "color": Color("7fd8ff")},
	{"id": "trail_spark", "name": "Star Sparkle", "category": "trail", "currency": "gems", "price": 45, "color": Color("ffe98a")},

	# --- Emotes ------------------------------------------------------------ #
	{"id": "emote_wave", "name": "Wave", "category": "emote", "currency": "coins", "price": 0, "color": Color("46b4d8")},
	{"id": "emote_victory", "name": "Victory Bounce", "category": "emote", "currency": "coins", "price": 400, "color": Color("f0a83c")},
]

const COSMETIC_CATEGORIES := ["skin", "book", "hat", "accessory", "trail", "emote"]

## The four power-ups from the design reference. `duration` is seconds of effect.
const POWER_UPS := {
	"speed": {"name": "Speed Surge", "color": Color("6fd7ff"), "duration": 8.0, "icon": "≫"},
	"damage": {"name": "Power Read", "color": Color("ffb648"), "duration": 9.0, "icon": "✦"},
	"shield": {"name": "Page Shield", "color": Color("8be3a2"), "duration": 12.0, "icon": "◆"},
	"multi": {"name": "Triple Tome", "color": Color("ff7ac0"), "duration": 9.0, "icon": "≡"},
}

const REWARD_WIN_COINS := 140
const REWARD_LOSS_COINS := 55
const REWARD_KO_COINS := 12
const REWARD_WIN_XP := 160
const REWARD_LOSS_XP := 70
const REWARD_KO_XP := 10

var profile: Dictionary = {}
var selected_arena := "sky_library"
var game_mode := "bots"
var bot_difficulty := "normal"
var network_roster: Array = []
var last_winner_name := ""
var last_match_summary: Dictionary = {}
var last_profile_save_error := ""

func _ready() -> void:
	profile = SaveSystem.load_profile(_default_profile())
	selected_arena = String(profile.get("selected_arena", "sky_library"))
	if not ARENAS.has(selected_arena):
		selected_arena = "sky_library"
	bot_difficulty = String(profile.get("bot_difficulty", "normal"))
	if not BOT_DIFFICULTIES.has(bot_difficulty):
		bot_difficulty = "normal"

func _default_profile() -> Dictionary:
	return {
		"version": PROFILE_VERSION,
		"player_name": "Reader",
		"coins": 1200,
		"gems": 100,
		"level_xp": 0,
		"battle_xp": 0,
		"battle_pass_premium": false,
		"claimed_pass_rewards": [],
		"inventory": ["skin_blue", "book_classic", "hat_default", "hat_bare", "acc_none", "trail_paper", "emote_wave"],
		"equipped": {
			"skin": "skin_blue", "book": "book_classic", "hat": "hat_default",
			"accessory": "acc_none", "trail": "trail_paper", "emote": "emote_wave",
		},
		"selected_arena": "sky_library",
		"bot_difficulty": "normal",
		"stats": {"matches": 0, "wins": 0, "knockouts": 0},
	}

# --------------------------------------------------------------------------- #
# Profile persistence
# --------------------------------------------------------------------------- #

func _commit_profile(draft: Dictionary, draft_arena: String = selected_arena, draft_difficulty: String = bot_difficulty) -> bool:
	draft["version"] = PROFILE_VERSION
	draft["selected_arena"] = draft_arena
	draft["bot_difficulty"] = draft_difficulty
	if SaveSystem.save_profile(draft):
		profile = draft
		selected_arena = draft_arena
		bot_difficulty = draft_difficulty
		last_profile_save_error = ""
		profile_changed.emit(profile)
		return true
	last_profile_save_error = "Could not save changes. Nothing was applied; please retry."
	profile_save_failed.emit()
	return false

func save_profile() -> bool:
	return _commit_profile(profile.duplicate(true))

func set_player_name(value: String) -> bool:
	var player_name := value.strip_edges().left(18)
	if player_name.is_empty() or player_name == String(profile.get("player_name", "Reader")):
		return true
	var draft := profile.duplicate(true)
	draft["player_name"] = player_name
	return _commit_profile(draft)

func set_bot_difficulty(difficulty_id: String) -> bool:
	if not BOT_DIFFICULTIES.has(difficulty_id):
		return false
	return _commit_profile(profile.duplicate(true), selected_arena, difficulty_id)

func difficulty_settings() -> Dictionary:
	return BOT_DIFFICULTIES.get(bot_difficulty, BOT_DIFFICULTIES["normal"])

# --------------------------------------------------------------------------- #
# Player settings (control scheme + camera view)
# --------------------------------------------------------------------------- #

## "keyboard" = WASD + mouse look, "touch" = on-screen joystick/buttons (also
## usable with a mouse on a laptop). "auto" picks touch on phones.
const CONTROL_SCHEMES := {"keyboard": "Keyboard + Mouse", "touch": "On-screen Joystick"}
const CAMERA_VIEWS := {"first": "First Person", "third": "Third Person"}

func control_scheme() -> String:
	# Phones are always touch: a saved "keyboard" choice (or a stray tap on the
	# old lobby toggle) must never put desktop controls on a phone.
	if Perf.is_mobile():
		return "touch"
	var value := String(profile.get("settings", {}).get("controls", "auto"))
	if value == "auto" or not CONTROL_SCHEMES.has(value):
		var phone := DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")
		return "touch" if phone else "keyboard"
	return value

func camera_view() -> String:
	var value := String(profile.get("settings", {}).get("camera", "first"))
	return value if CAMERA_VIEWS.has(value) else "first"

func mouse_sensitivity() -> float:
	return float(profile.get("settings", {}).get("sensitivity", 1.0))

func has_seen_controls_help() -> bool:
	return bool(profile.get("settings", {}).get("seen_help", false))

func set_setting(key: String, value: Variant) -> bool:
	var draft := profile.duplicate(true)
	var settings: Dictionary = draft.get("settings", {})
	settings[key] = value
	draft["settings"] = settings
	return _commit_profile(draft)

# --------------------------------------------------------------------------- #
# Roster
# --------------------------------------------------------------------------- #

func roster_entry(index: int) -> Dictionary:
	return ROSTER[clampi(index, 0, ROSTER.size() - 1)]

func get_equipped_cosmetics() -> Dictionary:
	return (profile.get("equipped", {}) as Dictionary).duplicate(true)

func get_active_roster() -> Array:
	if game_mode.begins_with("network") and not network_roster.is_empty():
		return network_roster.duplicate(true)
	var roster := ROSTER.duplicate(true)
	roster[0]["name"] = String(profile.get("player_name", "You"))
	var equipped := get_equipped_cosmetics()
	var skin := find_cosmetic(String(equipped.get("skin", "skin_blue")))
	if not skin.is_empty():
		roster[0]["model"] = skin.get("model", roster[0]["model"])
	roster[0]["cosmetics"] = equipped
	for i in range(1, roster.size()):
		roster[i]["cosmetics"] = _bot_cosmetics(i)
	return roster

## Bots get a deterministic but varied look so a six-player brawl does not read
## as one character copied six times.
func _bot_cosmetics(index: int) -> Dictionary:
	var hats := ["hat_default", "hat_wizard", "hat_winter", "hat_hair_spike", "hat_default", "hat_bare"]
	var accessories := ["acc_none", "acc_glasses", "acc_shades", "acc_headphones", "acc_none", "acc_moustache"]
	var books := ["book_classic", "book_flame", "book_frost", "book_gold", "book_arcane", "book_classic"]
	return {
		"skin": "skin_blue",
		"hat": hats[index % hats.size()],
		"accessory": accessories[index % accessories.size()],
		"book": books[index % books.size()],
		"trail": "trail_paper",
		"emote": "emote_wave",
	}

# --------------------------------------------------------------------------- #
# Arenas
# --------------------------------------------------------------------------- #

func get_selected_arena_scene() -> String:
	return String(ARENAS.get(selected_arena, ARENAS["sky_library"]).get("scene", "res://scenes/arenas/SkyLibrary.tscn"))

func select_arena(arena_id: String) -> bool:
	if not ARENAS.has(arena_id):
		return false
	if not _commit_profile(profile.duplicate(true), arena_id):
		return false
	selection_changed.emit()
	return true

# --------------------------------------------------------------------------- #
# Cosmetics
# --------------------------------------------------------------------------- #

func find_cosmetic(item_id: String) -> Dictionary:
	for item in COSMETICS:
		if String(item.get("id", "")) == item_id:
			return item
	return {}

func cosmetics_in_category(category: String) -> Array:
	var result: Array = []
	for item in COSMETICS:
		if String(item.get("category", "")) == category:
			result.append(item)
	return result

func book_color(book_id: String) -> Color:
	var item := find_cosmetic(book_id)
	return item.get("color", Color("8d3f2d")) if not item.is_empty() else Color("8d3f2d")

func book_emission(book_id: String) -> float:
	var item := find_cosmetic(book_id)
	return float(item.get("emission", 0.0)) if not item.is_empty() else 0.0

func trail_color(trail_id: String) -> Color:
	var item := find_cosmetic(trail_id)
	return item.get("color", Color(1.0, 0.88, 0.55)) if not item.is_empty() else Color(1.0, 0.88, 0.55)

## Recolours every mesh under `root` to the selected book skin. Book meshes are
## shared geometry, so the skin is a material swap rather than a separate model.
func apply_book_style(root: Node, book_id: String) -> void:
	if root == null:
		return
	var color := book_color(book_id)
	var emission := book_emission(book_id)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color.lightened(0.18)
		material.emission_energy_multiplier = emission
	_assign_material(root, material)

func _assign_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_assign_material(child, material)

func purchase_cosmetic(item_id: String) -> String:
	var item := find_cosmetic(item_id)
	if item.is_empty():
		return "Item not found"
	var draft := profile.duplicate(true)
	var result := UnlockSystem.purchase(draft, item)
	if result.begins_with("Purchased") and not _commit_profile(draft):
		return last_profile_save_error
	return result

func equip_cosmetic(item_id: String) -> bool:
	var item := find_cosmetic(item_id)
	if item.is_empty():
		return false
	var draft := profile.duplicate(true)
	if not Inventory.equip(draft, String(item.get("category", "")), item_id):
		return false
	return _commit_profile(draft)

# --------------------------------------------------------------------------- #
# Progression
# --------------------------------------------------------------------------- #

func complete_local_match(player_won: bool, knockouts: int = 0, placement: int = 0, total_players: int = 0) -> Dictionary:
	var coins := (REWARD_WIN_COINS if player_won else REWARD_LOSS_COINS) + knockouts * REWARD_KO_COINS
	var xp := (REWARD_WIN_XP if player_won else REWARD_LOSS_XP) + knockouts * REWARD_KO_XP
	var draft := profile.duplicate(true)
	CurrencyManager.grant(draft, "coins", coins)
	draft["level_xp"] = int(draft.get("level_xp", 0)) + xp
	draft["battle_xp"] = int(draft.get("battle_xp", 0)) + xp
	var stats: Dictionary = draft.get("stats", {})
	stats["matches"] = int(stats.get("matches", 0)) + 1
	stats["knockouts"] = int(stats.get("knockouts", 0)) + knockouts
	if player_won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
	draft["stats"] = stats
	var saved := _commit_profile(draft)
	last_match_summary = {
		"coins": coins, "xp": xp, "saved": saved, "won": player_won,
		"knockouts": knockouts, "placement": placement, "total_players": total_players,
	}
	return last_match_summary

func player_level() -> int:
	return int(profile.get("level_xp", 0)) / 500 + 1

func level_progress() -> float:
	return float(int(profile.get("level_xp", 0)) % 500) / 500.0

func claim_battle_pass(tier: int, premium: bool = false) -> bool:
	var draft := profile.duplicate(true)
	if not BattlePass.claim(draft, tier, premium):
		return false
	return _commit_profile(draft)

func upgrade_battle_pass() -> bool:
	if bool(profile.get("battle_pass_premium", false)):
		return true
	var draft := profile.duplicate(true)
	if not CurrencyManager.spend(draft, "gems", 250):
		return false
	draft["battle_pass_premium"] = true
	return _commit_profile(draft)

func request_premium_purchase(_product_id: String) -> bool:
	# Platform billing must replace this stub after Play Console products and
	# server-side receipt validation are configured. No fake real-money grants.
	return false
