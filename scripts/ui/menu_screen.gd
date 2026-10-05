class_name MenuScreen
extends Control
## Shared shell for Customize, Store, Battle Pass, Arena select, and Multiplayer.
##
## One script drives all five because they are the same page: a header with the
## currency balances, a tab strip, and a scrolling body of cards. Item data comes
## from `GameState.COSMETICS` / `ARENAS`, so adding content is a data row rather
## than new UI code.

@export_enum("customize", "store", "battle_pass", "map_select", "multiplayer")
var screen_id := "store"

const CARD_MIN_WIDTH := 232.0

var _body: VBoxContainer
var _tab_strip: HBoxContainer
var _coins_label: Label
var _gems_label: Label
var _status_label: Label
var _preview: CharacterPreview
var _tab_buttons: Dictionary = {}
var _active_tab := ""

# Multiplayer form state, kept as fields so the buttons can read it back.
var _address_field: LineEdit
var _port_field: SpinBox
var _name_field: LineEdit

func _ready() -> void:
	_build_shell()
	GameState.profile_changed.connect(_on_profile_changed)
	GameState.profile_save_failed.connect(_on_profile_save_failed)
	if screen_id == "multiplayer":
		NetworkManager.status_changed.connect(_set_status)
		NetworkManager.players_changed.connect(_on_players_changed)
	_active_tab = _default_tab()
	_render()
	if not GameState.last_profile_save_error.is_empty():
		_on_profile_save_failed()

# --------------------------------------------------------------------------- #
# Shell
# --------------------------------------------------------------------------- #

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.custom_minimum_size = Vector2(0, 56)
	column.add_child(header)

	var back := UiKit.secondary_button("‹  LOBBY", 19)
	back.custom_minimum_size = Vector2(150, 52)
	back.pressed.connect(_go_back)
	back.mouse_entered.connect(func(): Audio.play_ui("hover", -18.0))
	header.add_child(back)

	var heading := UiKit.title(_title_for_screen(), 34)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)

	var coins := UiKit.currency_pill("●", UiKit.COIN)
	var coins_root: Panel = coins["root"]
	coins_root.custom_minimum_size = Vector2(130, 46)
	_coins_label = coins["label"]
	header.add_child(coins_root)

	var gems := UiKit.currency_pill("◆", UiKit.GEM)
	var gems_root: Panel = gems["root"]
	gems_root.custom_minimum_size = Vector2(110, 46)
	_gems_label = gems["label"]
	header.add_child(gems_root)

	# Tabs
	_tab_strip = HBoxContainer.new()
	_tab_strip.add_theme_constant_override("separation", 8)
	_tab_strip.custom_minimum_size = Vector2(0, 44)
	column.add_child(_tab_strip)

	# Body: optional live preview beside a scrolling card list.
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)

	if screen_id == "customize":
		var stage := Panel.new()
		stage.add_theme_stylebox_override("panel", UiKit.rounded(Color(0.09, 0.06, 0.18, 0.6), 24))
		stage.custom_minimum_size = Vector2(300, 0)
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(stage)
		_preview = CharacterPreview.new()
		_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(_preview)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_status_label = UiKit.label("", 17, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.custom_minimum_size = Vector2(0, 34)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	_refresh_header()

func _title_for_screen() -> String:
	match screen_id:
		"customize": return "CUSTOMIZE"
		"store": return "STORE"
		"battle_pass": return "BATTLE PASS"
		"map_select": return "CHOOSE ARENA"
		"multiplayer": return "PLAY WITH FRIENDS"
	return "BOOK BASH"

func _tabs() -> Array:
	match screen_id:
		"customize": return GameState.COSMETIC_CATEGORIES
		"store": return ["all", "skin", "book", "hat", "accessory", "trail", "emote"]
	return []

func _default_tab() -> String:
	var tabs := _tabs()
	return String(tabs[0]) if not tabs.is_empty() else ""

func _rebuild_tabs() -> void:
	for child in _tab_strip.get_children():
		_tab_strip.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var tabs := _tabs()
	_tab_strip.visible = not tabs.is_empty()
	for tab in tabs:
		var button := UiKit.tab_button(String(tab).capitalize(), 18)
		button.custom_minimum_size = Vector2(120, 40)
		UiKit.wire_audio(button)
		button.pressed.connect(_select_tab.bind(String(tab)))
		_tab_strip.add_child(button)
		_tab_buttons[String(tab)] = button
	for tab_id in _tab_buttons:
		UiKit.set_tab_active(_tab_buttons[tab_id], tab_id == _active_tab)

func _select_tab(tab: String) -> void:
	_active_tab = tab
	_render()

# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #

func _render() -> void:
	_rebuild_tabs()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match screen_id:
		"customize": _render_customize()
		"store": _render_store()
		"battle_pass": _render_battle_pass()
		"map_select": _render_maps()
		"multiplayer": _render_multiplayer()
	_refresh_header()
	if _preview:
		_preview.refresh()

func _section(text: String) -> void:
	var label := UiKit.label(text, 22, UiKit.ACCENT)
	_body.add_child(label)

func _grid(columns: int = 3) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	return grid

## One cosmetic/arena card: swatch, name, state line, and an action button.
func _card(item_name: String, detail: String, swatch: Color, action_text: String, enabled: bool, highlight: bool, on_press: Callable) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UiKit.rounded(UiKit.PANEL if not highlight else UiKit.PANEL_RAISED, 18, UiKit.ACCENT, 3 if highlight else 0)
	)
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	card.add_child(layout)

	var swatch_rect := Panel.new()
	swatch_rect.add_theme_stylebox_override("panel", UiKit.rounded(swatch, 12))
	swatch_rect.custom_minimum_size = Vector2(0, 34)
	swatch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(swatch_rect)

	var name_label := UiKit.label(item_name, 18, UiKit.TEXT)
	name_label.clip_text = true
	layout.add_child(name_label)

	var detail_label := UiKit.label(detail, 15, UiKit.TEXT_DIM)
	detail_label.clip_text = true
	layout.add_child(detail_label)

	var button := UiKit.secondary_button(action_text, 16)
	button.custom_minimum_size = Vector2(0, 36)
	button.disabled = not enabled
	if enabled:
		UiKit.wire_audio(button)
		button.pressed.connect(on_press)
	layout.add_child(button)
	return card

func _render_customize() -> void:
	var category := _active_tab if _active_tab != "" else "skin"
	var equipped := GameState.get_equipped_cosmetics()
	var items := GameState.cosmetics_in_category(category)
	_section("%s  —  %d owned of %d" % [category.capitalize(), _owned_count(items), items.size()])
	var grid := _grid(2 if _preview else 3)
	for item in items:
		var item_id := String(item.get("id", ""))
		var owned := Inventory.owns(GameState.profile, item_id)
		var is_equipped := String(equipped.get(category, "")) == item_id
		var action := "EQUIPPED" if is_equipped else ("EQUIP" if owned else "IN STORE")
		var detail := "Owned" if owned else "%d %s" % [int(item.get("price", 0)), String(item.get("currency", "coins"))]
		grid.add_child(_card(
			String(item.get("name", "Item")), detail, _swatch_for(item),
			action, owned and not is_equipped, is_equipped,
			_equip.bind(item_id)
		))

func _render_store() -> void:
	var equipped_filter := _active_tab
	_section("Earn coins by playing. Gems come from the Battle Pass.")
	var grid := _grid(3)
	var shown := 0
	for item in GameState.COSMETICS:
		if int(item.get("price", 0)) <= 0:
			continue
		var category := String(item.get("category", ""))
		if equipped_filter != "all" and equipped_filter != "" and category != equipped_filter:
			continue
		shown += 1
		var item_id := String(item.get("id", ""))
		var owned := Inventory.owns(GameState.profile, item_id)
		var currency := String(item.get("currency", "coins"))
		var price := int(item.get("price", 0))
		var affordable := int(GameState.profile.get(currency, 0)) >= price
		var action := "OWNED" if owned else ("BUY  %d %s" % [price, "●" if currency == "coins" else "◆"])
		grid.add_child(_card(
			String(item.get("name", "Item")), category.capitalize(), _swatch_for(item),
			action, not owned and affordable, false, _purchase.bind(item_id)
		))
	if shown == 0:
		_body.add_child(UiKit.label("Everything in this tab is already unlocked.", 17, UiKit.TEXT_DIM))
	var note := UiKit.label(
		"Real-money purchases stay disabled until Play Billing products and server-side receipt validation are configured.",
		14, UiKit.TEXT_DIM
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(note)

func _render_battle_pass() -> void:
	var xp := int(GameState.profile.get("battle_xp", 0))
	var current_tier := BattlePass.tier_for_xp(xp)
	var premium := bool(GameState.profile.get("battle_pass_premium", false))
	_section("Season 1  —  Tier %d of %d" % [current_tier, BattlePass.MAX_TIER])

	var bar := UiKit.progress_bar()
	bar.max_value = BattlePass.XP_PER_TIER
	bar.value = BattlePass.progress_in_tier(xp)
	bar.custom_minimum_size = Vector2(0, 26)
	_body.add_child(bar)
	_body.add_child(UiKit.label(
		"%d / %d XP to the next tier  •  %s" % [
			BattlePass.progress_in_tier(xp), BattlePass.XP_PER_TIER,
			"Premium unlocked" if premium else "Free track only",
		], 16, UiKit.TEXT_DIM
	))

	if not premium:
		var upgrade := UiKit.primary_button("UNLOCK PREMIUM PASS  —  250 ◆", 22)
		upgrade.custom_minimum_size = Vector2(0, 56)
		UiKit.wire_audio(upgrade)
		upgrade.pressed.connect(_upgrade_pass)
		_body.add_child(upgrade)

	var claimed: Array = GameState.profile.get("claimed_pass_rewards", [])
	for tier in range(1, BattlePass.MAX_TIER + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tier_label := UiKit.label("Tier %02d" % tier, 17, UiKit.TEXT if tier <= current_tier else UiKit.TEXT_DIM)
		tier_label.custom_minimum_size = Vector2(96, 44)
		tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tier_label)
		for is_premium in [false, true]:
			var reward := BattlePass.reward_for_tier(tier, is_premium)
			var key := "%s_%d" % ["premium" if is_premium else "free", tier]
			var already := key in claimed
			var reward_text := "%d ●" % int(reward.get("coins", 0))
			if int(reward.get("gems", 0)) > 0:
				reward_text += "   %d ◆" % int(reward.get("gems", 0))
			var button := UiKit.secondary_button(
				"%s  %s%s" % ["PREMIUM" if is_premium else "FREE", reward_text, "  ✓" if already else ""], 16
			)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 44)
			button.disabled = already or tier > current_tier or (is_premium and not premium)
			if not button.disabled:
				UiKit.wire_audio(button)
				button.pressed.connect(_claim_pass.bind(tier, is_premium))
			row.add_child(button)
		_body.add_child(row)

func _render_maps() -> void:
	_section("Tap an arena to make it your next match.")
	var grid := _grid(3)
	for key in GameState.ARENAS:
		var arena_id := String(key)
		var arena: Dictionary = GameState.ARENAS[arena_id]
		var selected: bool = GameState.selected_arena == arena_id
		grid.add_child(_card(
			String(arena.get("name", arena_id)),
			String(arena.get("description", "")),
			arena.get("tint", UiKit.PANEL_RAISED),
			"SELECTED" if selected else "SELECT",
			not selected, selected,
			_select_map.bind(String(arena_id))
		))

func _render_multiplayer() -> void:
	_section("LAN, direct IP, or a relay endpoint")

	var form := GridContainer.new()
	form.columns = 2
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("h_separation", 10)
	form.add_theme_constant_override("v_separation", 8)
	_body.add_child(form)

	form.add_child(UiKit.label("Your name", 17, UiKit.TEXT_DIM))
	_name_field = LineEdit.new()
	_name_field.text = String(GameState.profile.get("player_name", "Reader"))
	_name_field.max_length = 18
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name_field)

	form.add_child(UiKit.label("Host address", 17, UiKit.TEXT_DIM))
	_address_field = LineEdit.new()
	_address_field.placeholder_text = "Host IPv4, hostname, or relay address"
	_address_field.text = "127.0.0.1"
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_address_field)

	form.add_child(UiKit.label("UDP port", 17, UiKit.TEXT_DIM))
	_port_field = SpinBox.new()
	_port_field.min_value = 1024
	_port_field.max_value = 65535
	_port_field.value = NetworkManager.DEFAULT_PORT
	form.add_child(_port_field)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_body.add_child(buttons)

	var host := UiKit.primary_button("HOST MATCH", 21)
	host.custom_minimum_size = Vector2(0, 54)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.wire_audio(host)
	host.pressed.connect(_host_pressed)
	buttons.add_child(host)

	var join := UiKit.secondary_button("JOIN", 21)
	join.custom_minimum_size = Vector2(0, 54)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.wire_audio(join)
	join.pressed.connect(_join_pressed)
	buttons.add_child(join)

	# Explicit widths: these two sit next to expanding buttons, and with a zero
	# minimum they collapsed to slivers and clipped their own labels.
	var lan := UiKit.secondary_button("SHOW MY IP", 18)
	lan.custom_minimum_size = Vector2(190, 54)
	UiKit.wire_audio(lan)
	lan.pressed.connect(_show_local_addresses)
	buttons.add_child(lan)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 10)
	_body.add_child(control_row)

	var start := UiKit.primary_button("START MATCH (HOST ONLY)", 19)
	start.custom_minimum_size = Vector2(0, 50)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.wire_audio(start)
	start.pressed.connect(NetworkManager.start_match)
	control_row.add_child(start)

	var leave := UiKit.secondary_button("DISCONNECT", 19)
	leave.custom_minimum_size = Vector2(190, 50)
	UiKit.wire_audio(leave)
	leave.pressed.connect(NetworkManager.disconnect_game)
	control_row.add_child(leave)

	_body.add_child(UiKit.label("Lobby", 20, UiKit.ACCENT))
	var roster := VBoxContainer.new()
	roster.name = "Roster"
	roster.add_theme_constant_override("separation", 4)
	_body.add_child(roster)
	_populate_roster(NetworkManager.players)

	var help := UiKit.label(
		"LAN: everyone joins the host's local IPv4 address on the same Wi-Fi. "
		+ "Internet: the host needs a reachable public address — either a forwarded UDP port "
		+ "or a deployed relay. Empty slots are filled with bots up to six fighters.",
		15, UiKit.TEXT_DIM
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(help)
	_set_status(NetworkManager.status_text)

func _populate_roster(players: Dictionary) -> void:
	var roster := _body.get_node_or_null("Roster") as VBoxContainer
	if roster == null:
		return
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	if players.is_empty():
		roster.add_child(UiKit.label("Not connected.", 16, UiKit.TEXT_DIM))
		return
	var ids: Array = players.keys()
	ids.sort()
	for index in range(ids.size()):
		var data: Dictionary = players[ids[index]]
		var line := "%d.  %s%s" % [
			index + 1, String(data.get("name", "Player")),
			"   (host)" if int(ids[index]) == 1 else "",
		]
		roster.add_child(UiKit.label(line, 17, UiKit.TEXT))
	var bots := GameState.MAX_FIGHTERS - players.size()
	if bots > 0:
		roster.add_child(UiKit.label("+ %d bot(s) will fill the remaining slots." % bots, 16, UiKit.TEXT_DIM))

func _on_players_changed(players: Dictionary) -> void:
	if screen_id == "multiplayer":
		_populate_roster(players)

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

func _swatch_for(item: Dictionary) -> Color:
	if item.has("color"):
		return item["color"]
	match String(item.get("category", "")):
		"skin": return item.get("tint", UiKit.PANEL_RAISED)
		"hat": return Color("6f5bc0")
		"accessory": return Color("4f8fc0")
		"emote": return Color("c05f9a")
	return UiKit.PANEL_RAISED

func _owned_count(items: Array) -> int:
	var count := 0
	for item in items:
		if Inventory.owns(GameState.profile, String(item.get("id", ""))):
			count += 1
	return count

func _equip(item_id: String) -> void:
	_set_status("Equipped." if GameState.equip_cosmetic(item_id) else _failure_or("That item is locked."))
	_render()

func _purchase(item_id: String) -> void:
	_set_status(GameState.purchase_cosmetic(item_id))
	_render()

func _upgrade_pass() -> void:
	_set_status("Premium pass unlocked." if GameState.upgrade_battle_pass() else _failure_or("You need 250 gems."))
	_render()

func _claim_pass(tier: int, premium: bool) -> void:
	_set_status("Reward claimed." if GameState.claim_battle_pass(tier, premium) else _failure_or("Reward unavailable."))
	_render()

func _select_map(arena_id: String) -> void:
	if GameState.select_arena(arena_id):
		_set_status("Next match: %s" % String(GameState.ARENAS[arena_id].get("name", arena_id)))
	else:
		_set_status(_failure_or("Arena unavailable."))
	_render()

func _host_pressed() -> void:
	if not GameState.set_player_name(_name_field.text):
		_set_status(GameState.last_profile_save_error)
		return
	if NetworkManager.host_game(int(_port_field.value)):
		GameState.game_mode = "network"

func _join_pressed() -> void:
	if not GameState.set_player_name(_name_field.text):
		_set_status(GameState.last_profile_save_error)
		return
	if NetworkManager.join_game(_address_field.text.strip_edges(), int(_port_field.value)):
		GameState.game_mode = "network"

## Surfaces the host's own addresses so a LAN game does not require the player to
## go hunting through their OS network settings.
func _show_local_addresses() -> void:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if address.begins_with("127.") or address.contains(":"):
			continue
		addresses.append(address)
	if addresses.is_empty():
		_set_status("No local IPv4 address found. Check your Wi-Fi connection.")
		return
	_set_status("Others join you at:  %s   (UDP %d)" % [", ".join(addresses), int(_port_field.value)])

func _failure_or(fallback: String) -> String:
	return GameState.last_profile_save_error if not GameState.last_profile_save_error.is_empty() else fallback

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text

func _refresh_header() -> void:
	if _coins_label:
		_coins_label.text = "● %d" % int(GameState.profile.get("coins", 0))
	if _gems_label:
		_gems_label.text = "◆ %d" % int(GameState.profile.get("gems", 0))

func _on_profile_changed(_profile: Dictionary) -> void:
	_refresh_header()

func _on_profile_save_failed() -> void:
	_set_status(GameState.last_profile_save_error)

func _go_back() -> void:
	Audio.play_ui("back")
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")
