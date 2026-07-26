extends Control

## Rally Setup UI shell for Wildling Lairs.
## UI / contract only — does NOT create authoritative rallies, lock troops,
## consume march slots, or call MarchState / WildlingCombatResolver.

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")
const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")

const TOP_SAFE_MARGIN: float = 188.0
const BOTTOM_SAFE_MARGIN: float = 200.0

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.72, 0.32, 0.28, 0.90)
const COL_SLOT := Color(0.08, 0.07, 0.10, 0.95)

## Future Nakama RPC payload shape (not sent this phase).
## See build_rally_create_contract().

var _lair: Dictionary = {}
var _selected_heroes: Array[String] = []
var _infantry: int = 0
var _marksmen: int = 0
var _cavalry: int = 0
var _countdown_sec: int = 300

var _target_name_label: Label
var _power_label: Label
var _capacity_label: Label
var _combat_label: Label
var _status_label: Label
var _timer_buttons: Dictionary = {} # sec -> Button
var _hero_slots: Array[Button] = []
var _troop_qty_labels: Dictionary = {}
var _troop_avail_labels: Dictionary = {}
var _create_btn: Button
var _last_contract: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_for_lair(lair_payload: Dictionary) -> void:
	_lair = lair_payload.duplicate(true)
	_selected_heroes.clear()
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	_countdown_sec = 300
	var def: Dictionary = _lair.get("level_def", {}) as Dictionary
	if def.is_empty():
		def = WildlingLairDatabase.get_level_def(int(_lair.get("lair_level", _lair.get("den_level", 1))))
		_lair["level_def"] = def
	var opts: Array = def.get("countdown_options_sec", [300, 600, 1800]) as Array
	if not opts.is_empty():
		_countdown_sec = int(opts[0])
	_auto_pick_first_hero()
	_build_ui()
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.open_screen("RallySetupScreen")
	else:
		on_open()


## Proposed future Nakama contract (local preview only — never sent yet).
func build_rally_create_contract() -> Dictionary:
	var pos: Dictionary = _lair.get("world_position", {}) as Dictionary
	var def: Dictionary = _lair.get("level_def", {}) as Dictionary
	# Prefer any existing player id facade when present; else schema placeholder.
	var leader_id := "local_dev_player"
	if has_node("/root/GameState"):
		if GameState.has_method("get_player_id"):
			leader_id = str(GameState.call("get_player_id"))
		elif "player_id" in GameState:
			leader_id = str(GameState.player_id)

	var troop_tiers: Dictionary = {}
	if has_node("/root/MarchState") and MarchState.has_method("build_troop_tier_composition"):
		troop_tiers = MarchState.build_troop_tier_composition(_troop_dict())
	else:
		troop_tiers = {
			"infantry": {1: _infantry},
			"marksmen": {1: _marksmen},
			"cavalry": {1: _cavalry},
		}

	return {
		"rpc": "crownspire_rally_create",
		"lair_id": str(_lair.get("lair_id", _lair.get("den_id", ""))),
		"lair_level": int(_lair.get("lair_level", _lair.get("den_level", 1))),
		"lair_catalog_id": str(def.get("id", "")),
		"species": str(_lair.get("species", def.get("species", ""))),
		"visual_variant": str(_lair.get("visual_variant", def.get("visual_variant", ""))),
		"leader_player_id": leader_id,
		"countdown_seconds": _countdown_sec,
		"hero_ids": _selected_heroes.duplicate(),
		"troop_counts": {
			"Infantry": _infantry,
			"Marksmen": _marksmen,
			"Cavalry": _cavalry,
		},
		"troop_tiers": troop_tiers,
		"world_position": {
			"x": float(pos.get("x", 0.0)),
			"y": float(pos.get("y", 0.0)),
		},
		"recommended_power": int(_lair.get("recommended_power", def.get("recommended_power", 0))),
		"max_participants_hint": int(def.get("max_participants_hint", 5)),
		"client_phase": "ui_shell_only",
	}


func get_last_contract_preview() -> Dictionary:
	return _last_contract.duplicate(true)


func _auto_pick_first_hero() -> void:
	if not has_node("/root/HeroState"):
		return
	for hero: Dictionary in HeroState.get_available_heroes():
		_selected_heroes.append(str(hero.get("id", "")))
		break


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	_hero_slots.clear()
	_troop_qty_labels.clear()
	_troop_avail_labels.clear()
	_timer_buttons.clear()

	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.04, 0.03, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE_MARGIN
	dim.offset_bottom = -BOTTOM_SAFE_MARGIN
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "RallyWindow"
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 12.0
	window.offset_top = TOP_SAFE_MARGIN
	window.offset_right = -12.0
	window.offset_bottom = -BOTTOM_SAFE_MARGIN
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER))
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	window.add_child(margin)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 10)
	margin.add_child(root_col)

	var header := HBoxContainer.new()
	root_col.add_child(header)
	var title := Label.new()
	title.text = "RALLY SETUP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := _chrome_button("X", Vector2(72, 54))
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	_target_name_label = Label.new()
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override("font_size", 22)
	_target_name_label.add_theme_color_override("font_color", COL_INK)
	root_col.add_child(_target_name_label)

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.add_theme_font_size_override("font_size", 18)
	_power_label.add_theme_color_override("font_color", COL_MUTED)
	root_col.add_child(_power_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	MobileScrollUtil.ensure(self, scroll, "MobileScrollRallySetup")
	root_col.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)

	col.add_child(_section_title("RALLY TIMER"))
	var timer_row := HBoxContainer.new()
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", 8)
	col.add_child(timer_row)
	for sec: int in [300, 600, 1800]:
		var label := _timer_label(sec)
		var btn := _chrome_button(label, Vector2(0, 56))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_timer_pressed.bind(sec))
		timer_row.add_child(btn)
		_timer_buttons[sec] = btn

	col.add_child(_section_title("MY MARCH"))
	col.add_child(_muted("Heroes"))
	var hero_row := HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", 10)
	col.add_child(hero_row)
	var max_heroes: int = 3
	if has_node("/root/MarchState"):
		max_heroes = MarchState.MAX_HEROES_PER_MARCH
	for i: int in range(max_heroes):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(96, 96)
		slot.focus_mode = Control.FOCUS_NONE
		slot.add_theme_stylebox_override("normal", _panel_style(COL_SLOT, COL_BORDER))
		slot.pressed.connect(_on_hero_slot_pressed.bind(i))
		hero_row.add_child(slot)
		_hero_slots.append(slot)

	var hero_actions := HBoxContainer.new()
	hero_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_actions.add_theme_constant_override("separation", 8)
	col.add_child(hero_actions)
	var select_heroes := _chrome_button("Select Heroes", Vector2(0, 48))
	select_heroes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_heroes.pressed.connect(_on_select_all_heroes)
	hero_actions.add_child(select_heroes)
	var clear_heroes := _chrome_button("Clear", Vector2(120, 48))
	clear_heroes.pressed.connect(_on_clear_heroes)
	hero_actions.add_child(clear_heroes)

	col.add_child(_muted("Troops"))
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		col.add_child(_build_troop_row(kind))

	var troop_actions := HBoxContainer.new()
	troop_actions.add_theme_constant_override("separation", 8)
	col.add_child(troop_actions)
	var fill_btn := _chrome_button("Fill Capacity", Vector2(0, 48))
	fill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_btn.pressed.connect(_on_fill_capacity)
	troop_actions.add_child(fill_btn)
	var clear_t := _chrome_button("Clear", Vector2(120, 48))
	clear_t.pressed.connect(_on_clear_troops)
	troop_actions.add_child(clear_t)

	_capacity_label = Label.new()
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capacity_label.add_theme_font_size_override("font_size", 18)
	_capacity_label.add_theme_color_override("font_color", COL_INK)
	col.add_child(_capacity_label)

	_combat_label = Label.new()
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_label.add_theme_font_size_override("font_size", 16)
	_combat_label.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(_combat_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", COL_WARN)
	_status_label.text = "UI shell only — multiplayer rally connection pending."
	col.add_child(_status_label)

	_create_btn = Button.new()
	_create_btn.text = "CREATE RALLY"
	_create_btn.custom_minimum_size = Vector2(0, 72)
	_create_btn.focus_mode = Control.FOCUS_NONE
	_create_btn.add_theme_font_size_override("font_size", 24)
	_create_btn.add_theme_color_override("font_color", COL_INK)
	_create_btn.add_theme_stylebox_override("normal", _panel_style(Color(0.42, 0.18, 0.16, 1.0), COL_GOLD))
	_create_btn.pressed.connect(_on_create_rally_pressed)
	root_col.add_child(_create_btn)

	_refresh()


func _build_troop_row(kind: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.text = kind.capitalize()
	name_l.custom_minimum_size = Vector2(120, 0)
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.add_theme_color_override("font_color", COL_INK)
	row.add_child(name_l)

	var minus := _chrome_button("−", Vector2(56, 48))
	minus.pressed.connect(_on_troop_adjust.bind(kind, -100))
	row.add_child(minus)

	var qty := Label.new()
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.custom_minimum_size = Vector2(90, 0)
	qty.add_theme_font_size_override("font_size", 20)
	qty.add_theme_color_override("font_color", COL_GOLD)
	row.add_child(qty)
	_troop_qty_labels[kind] = qty

	var plus := _chrome_button("+", Vector2(56, 48))
	plus.pressed.connect(_on_troop_adjust.bind(kind, 100))
	row.add_child(plus)

	var avail := Label.new()
	avail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	avail.add_theme_font_size_override("font_size", 14)
	avail.add_theme_color_override("font_color", COL_MUTED)
	row.add_child(avail)
	_troop_avail_labels[kind] = avail
	return row


func _refresh() -> void:
	var level: int = int(_lair.get("lair_level", _lair.get("den_level", 1)))
	var power: int = int(_lair.get("recommended_power", 0))
	var level_def: Dictionary = _lair.get("level_def", {}) as Dictionary
	var creature: String = str(_lair.get("creature_title", WildlingLairDatabase.creature_title(level_def)))
	if _target_name_label != null:
		_target_name_label.text = "Wildling Lair Lv.%d" % level
	if _power_label != null:
		var creature_line: String = ("Creature: %s\n" % creature) if not creature.is_empty() else ""
		_power_label.text = "%sRecommended Power  %s" % [
			creature_line,
			WildlingLairDatabase.format_power(power),
		]

	for sec: Variant in _timer_buttons.keys():
		var btn: Button = _timer_buttons[sec]
		var selected: bool = int(sec) == _countdown_sec
		btn.add_theme_stylebox_override(
			"normal",
			_panel_style(
				Color(0.42, 0.32, 0.12, 1.0) if selected else COL_CARD,
				COL_GOLD if selected else COL_BORDER
			)
		)

	for i: int in range(_hero_slots.size()):
		var slot: Button = _hero_slots[i]
		if i < _selected_heroes.size():
			slot.text = _selected_heroes[i].capitalize()
		else:
			slot.text = "+"

	for kind: String in ["infantry", "marksmen", "cavalry"]:
		if _troop_qty_labels.has(kind):
			_troop_qty_labels[kind].text = str(_get_troop(kind))
		if _troop_avail_labels.has(kind):
			_troop_avail_labels[kind].text = "Avail %d" % _available_for_kind(kind)

	var capacity: int = _march_capacity()
	var used: int = _infantry + _marksmen + _cavalry
	if _capacity_label != null:
		_capacity_label.text = "Capacity  %d / %d" % [used, capacity]

	if _combat_label != null:
		var atk := 0
		var defense := 0
		var hp := 0
		if has_node("/root/StatResolver") and has_node("/root/MarchState"):
			var composition: Dictionary = MarchState.build_troop_tier_composition(_troop_dict())
			var stats: Dictionary = StatResolver.resolve_march_combat_stats(composition, _selected_heroes)
			var totals: Dictionary = stats.get("totals", {}) as Dictionary
			atk = int(totals.get("attack", 0))
			defense = int(totals.get("defense", 0))
			hp = int(totals.get("health", 0))
		_combat_label.text = "Combat ATK %s  ·  DEF %s  ·  HP %s" % [
			WildlingLairDatabase.format_power(atk),
			WildlingLairDatabase.format_power(defense),
			WildlingLairDatabase.format_power(hp),
		]


func _on_timer_pressed(sec: int) -> void:
	_countdown_sec = sec
	_refresh()


func _on_troop_adjust(kind: String, delta: int) -> void:
	var current: int = _get_troop(kind)
	var available: int = _available_for_kind(kind)
	var capacity: int = _march_capacity()
	var others: int = (_infantry + _marksmen + _cavalry) - current
	var room: int = maxi(0, capacity - others)
	var max_allowed: int = mini(available, room)
	_set_troop(kind, clampi(current + delta, 0, max_allowed))
	_refresh()


func _on_fill_capacity() -> void:
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	var remaining: int = _march_capacity()
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var available: int = _available_for_kind(kind)
		var take: int = mini(available, remaining)
		_set_troop(kind, take)
		remaining -= take
	_refresh()


func _on_clear_troops() -> void:
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	_refresh()


func _on_select_all_heroes() -> void:
	_selected_heroes.clear()
	if not has_node("/root/HeroState"):
		_refresh()
		return
	var max_heroes: int = MarchState.MAX_HEROES_PER_MARCH if has_node("/root/MarchState") else 3
	for hero: Dictionary in HeroState.get_available_heroes():
		if _selected_heroes.size() >= max_heroes:
			break
		var hid: String = str(hero.get("id", ""))
		if hid.is_empty():
			continue
		if HeroState.is_hero_on_march(hid):
			continue
		_selected_heroes.append(hid)
	_refresh()


func _on_clear_heroes() -> void:
	_selected_heroes.clear()
	_refresh()


func _on_hero_slot_pressed(index: int) -> void:
	if index < _selected_heroes.size():
		_selected_heroes.remove_at(index)
		_refresh()
		return
	var max_heroes: int = MarchState.MAX_HEROES_PER_MARCH if has_node("/root/MarchState") else 3
	if _selected_heroes.size() >= max_heroes:
		return
	if not has_node("/root/HeroState"):
		return
	for hero: Dictionary in HeroState.get_available_heroes():
		var hid: String = str(hero.get("id", ""))
		if hid.is_empty() or hid in _selected_heroes:
			continue
		if HeroState.is_hero_on_march(hid):
			continue
		_selected_heroes.append(hid)
		break
	_refresh()


func _on_create_rally_pressed() -> void:
	# Contract preview only — no backend send, no troop lock, no MarchState.
	_last_contract = build_rally_create_contract()
	print("[WildlingLair] Rally create contract (NOT SENT): ", JSON.stringify(_last_contract))
	if _status_label != null:
		_status_label.text = "Multiplayer rally connection pending.\nContract prepared locally — troops unchanged."
		_status_label.add_theme_color_override("font_color", COL_OK)


func _on_close_pressed() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _available_for_kind(kind: String) -> int:
	if not has_node("/root/TroopState"):
		return 0
	return maxi(0, TroopState.get_available_count(_troop_type_name(kind)))


func _march_capacity() -> int:
	if has_node("/root/MarchState"):
		return MarchState.get_march_capacity(_selected_heroes)
	return 10000


func _troop_type_name(kind: String) -> String:
	match kind:
		"infantry":
			return "Infantry"
		"marksmen":
			return "Marksmen"
		"cavalry":
			return "Cavalry"
	return kind.capitalize()


func _get_troop(kind: String) -> int:
	match kind:
		"infantry":
			return _infantry
		"marksmen":
			return _marksmen
		"cavalry":
			return _cavalry
	return 0


func _set_troop(kind: String, amount: int) -> void:
	var safe: int = maxi(0, amount)
	match kind:
		"infantry":
			_infantry = safe
		"marksmen":
			_marksmen = safe
		"cavalry":
			_cavalry = safe


func _troop_dict() -> Dictionary:
	## Lowercase keys match MarchState.build_troop_tier_composition.
	return {
		"infantry": _infantry,
		"marksmen": _marksmen,
		"cavalry": _cavalry,
	}


func _timer_label(sec: int) -> String:
	if sec < 60:
		return "%d SEC" % sec
	var mins: int = int(sec / 60.0)
	return "%d MIN" % mins


func _section_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", COL_MUTED)
	return l


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _panel_style(COL_CARD, COL_BORDER))
	return btn


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
