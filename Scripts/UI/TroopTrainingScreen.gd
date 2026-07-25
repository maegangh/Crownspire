extends Control

## Crownspire Troop Training — single-page Train / Promote (no vertical scroll).
## Runtime: GameHUD/ScreenRoot/TroopTrainingScreen

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_LOCK := Color(0.45, 0.40, 0.38, 1.0)
const COL_SEL := Color(0.32, 0.24, 0.12, 1.0)

const FALLBACK_TOP_INSET: float = 180.0
const FALLBACK_BOTTOM_INSET: float = 190.0
const SIDE_INSET: float = 14.0
const CONTENT_GAP: float = 10.0
const UI_LAYOUT_VERSION: int = 5
const TIER_CHIP_COUNT: int = 6 ## visible window of tiers around selection

const TROOP_ICONS := {
	"infantry": "res://assets/Buttons/infantry.png",
	"marksmen": "res://assets/Buttons/marksman.png",
	"cavalry": "res://assets/Buttons/cavalry.png",
}

## Shared type tabs: label + TroopState canon type + City node name + building_id.
const TYPE_TABS: Array[Dictionary] = [
	{"label": "INFANTRY", "type": "Infantry", "node": "InfantryBarracks", "building_id": "infantry_barracks"},
	{"label": "MARKSMEN", "type": "Marksmen", "node": "MarksmenCamp", "building_id": "marksmen_camp"},
	{"label": "CAVALRY", "type": "Cavalry", "node": "CavalryStable", "building_id": "cavalry_stable"},
]

var _troop_type: String = "Infantry"
var _building_id: String = "infantry_barracks"
var _building_level: int = 1
var _selected_tier: int = 1
var _source_tier: int = 1
var _mode: String = "train" ## train | promote
var _amount: int = 0
var _built_layout_version: int = -1
var _top_inset: float = FALLBACK_TOP_INSET
var _bottom_inset: float = FALLBACK_BOTTOM_INSET
var _refresh_accum: float = 0.0
var _tier_window_start: int = 1

var _dim: ColorRect
var _window: PanelContainer
var _shell: VBoxContainer
var _type_tab_row: HBoxContainer
var _type_tab_buttons: Array[Button] = []
var _building_title: Label
var _status_label: Label

var _icon: TextureRect
var _troop_name_label: Label
var _troop_meta_label: Label
var _stats_label: Label

var _tier_row: HBoxContainer
var _tier_buttons: Array[Button] = []
var _train_mode_btn: Button
var _promote_mode_btn: Button
var _source_label: Label
var _source_row: HBoxContainer
var _source_buttons: Array[Button] = []

var _amount_label: Label
var _summary_label: Label
var _cost_label: Label
var _action_button: Button

var _idle_block: VBoxContainer
var _job_block: VBoxContainer
var _job_title: Label
var _job_detail: Label
var _job_time: Label
var _collect_button: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_current_layout()
	resized.connect(_on_resized)
	if has_node("/root/TroopState") and not TroopState.training_updated.is_connected(_on_training_updated):
		TroopState.training_updated.connect(_on_training_updated)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.35:
		return
	_refresh_accum = 0.0
	# Refresh current job timers and optional tab indicators (other types' jobs).
	if _any_job_needs_timer_tick():
		_refresh_view()
	else:
		_refresh_type_tabs()


func on_open() -> void:
	_ensure_current_layout()
	_apply_safe_area()
	_bootstrap_selection()
	_refresh_view()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("/root/GameState"):
		GameState.popup_open = true


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_tree_mouse_ignore(self, true)
	if has_node("/root/GameState"):
		GameState.popup_open = false


func open_for_building(troop_type: String, building_id: String = "", building_level: int = 1) -> void:
	_apply_troop_context(troop_type, building_id, building_level, true)
	_ensure_current_layout()
	var manager: Node = _find_ui_manager()
	if manager != null and manager.has_method("open_screen"):
		manager.open_screen("TroopTrainingScreen")
	else:
		on_open()


## In-screen switch: updates context and refreshes; does not close/reopen.
func switch_troop_type(troop_type: String) -> void:
	var canon: String = _canonicalize_troop_type(troop_type)
	if canon == _troop_type:
		_refresh_type_tabs()
		return
	_apply_troop_context(canon, "", -1, true)
	_refresh_view()


func _apply_troop_context(
	troop_type: String,
	building_id: String = "",
	building_level: int = -1,
	reset_mode_amount: bool = true
) -> void:
	_troop_type = _canonicalize_troop_type(troop_type)
	_building_id = building_id if building_id != "" else TroopState.building_id_for_troop_type(_troop_type)
	if building_level >= 1:
		_building_level = building_level
	else:
		_building_level = _lookup_training_building_level(_troop_type, _building_id)
	if reset_mode_amount:
		_mode = "train"
		_amount = 0
		_status_label_text_clear()
	_bootstrap_selection()


func _status_label_text_clear() -> void:
	if _status_label != null:
		_status_label.text = ""


func _any_job_needs_timer_tick() -> bool:
	if not has_node("/root/TroopState"):
		return false
	for tab: Dictionary in TYPE_TABS:
		var t: String = str(tab.get("type", ""))
		if TroopState.is_training_active(t) or TroopState.is_training_ready(t):
			return true
	return false


func _on_resized() -> void:
	if visible:
		_apply_safe_area()


func _on_training_updated() -> void:
	if visible:
		_refresh_view()


func _ensure_current_layout() -> void:
	if _built_layout_version != UI_LAYOUT_VERSION or get_node_or_null("TrainingWindow") == null:
		_build_ui()
	_apply_safe_area()


func _bootstrap_selection() -> void:
	if has_node("/root/TroopDatabase"):
		_selected_tier = TroopDatabase.get_highest_unlocked_tier(_db_type(), _building_level)
	else:
		_selected_tier = 1
	_source_tier = _default_source_tier()
	_tier_window_start = maxi(1, _selected_tier - 2)
	_clamp_amount()


func _db_type() -> String:
	return _troop_type.to_lower()


func _canonicalize_troop_type(raw: String) -> String:
	var clean: String = raw.strip_edges().to_lower()
	match clean:
		"infantry", "infantry barracks", "barracks":
			return "Infantry"
		"marksmen", "marksman", "archer", "archers", "marksmen camp":
			return "Marksmen"
		"cavalry", "cavalry stable", "stable":
			return "Cavalry"
		_:
			return raw.capitalize() if raw != "" else "Infantry"


func _building_titles() -> Dictionary:
	match _troop_type:
		"Infantry":
			return {"title": "BARRACKS", "subtitle": "Infantry Training"}
		"Marksmen":
			return {"title": "MARKSMAN RANGE", "subtitle": "Marksmen Training"}
		"Cavalry":
			return {"title": "CAVALRY STABLE", "subtitle": "Cavalry Training"}
		_:
			return {"title": "TRAINING", "subtitle": _troop_type}


func _lookup_training_building_level(troop_type: String, building_id: String) -> int:
	var node: Node = _find_training_building_node(troop_type, building_id)
	if node != null and "building_level" in node:
		return maxi(1, int(node.get("building_level")))
	# Fallback: same buildings.cfg keys ResourceManager uses (building_name).
	var save := ConfigFile.new()
	if save.load("user://buildings.cfg") == OK:
		var names: PackedStringArray = PackedStringArray()
		match _canonicalize_troop_type(troop_type):
			"Infantry":
				names = PackedStringArray(["Infantry Barracks", "InfantryBarracks"])
			"Marksmen":
				names = PackedStringArray(["Marksmen Camp", "MarksmenCamp"])
			"Cavalry":
				names = PackedStringArray(["Cavalry Stable", "CavalryStable"])
		for key: String in names:
			if save.has_section_key(key, "level"):
				return maxi(1, int(save.get_value(key, "level", 1)))
	return 1


func _find_training_building_node(troop_type: String, building_id: String) -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	var want_id: String = building_id if building_id != "" else TroopState.building_id_for_troop_type(troop_type)
	var node_name: String = ""
	for tab: Dictionary in TYPE_TABS:
		if str(tab.get("type", "")) == _canonicalize_troop_type(troop_type) \
				or str(tab.get("building_id", "")) == want_id:
			node_name = str(tab.get("node", ""))
			break
	if node_name != "":
		var by_name: Node = scene.find_child(node_name, true, false)
		if by_name != null:
			return by_name
	# Scan ResourceManager buildings by building_id export.
	for n: Node in scene.find_children("*", "Node2D", true, false):
		if "building_id" in n and str(n.get("building_id")) == want_id:
			return n
	return null


func _refresh_type_tabs() -> void:
	if _type_tab_buttons.is_empty():
		return
	for i: int in range(mini(_type_tab_buttons.size(), TYPE_TABS.size())):
		var tab: Dictionary = TYPE_TABS[i]
		var btn: Button = _type_tab_buttons[i]
		var t: String = str(tab.get("type", ""))
		var label: String = str(tab.get("label", t.to_upper()))
		var status: String = _type_tab_status(t)
		btn.text = "%s\n%s" % [label, status]
		var selected: bool = t == _troop_type
		if selected:
			btn.add_theme_stylebox_override("normal", _button_style(COL_SEL, COL_GOLD))
			btn.add_theme_stylebox_override("hover", _button_style(Color(0.40, 0.30, 0.14, 1.0), Color(1.0, 0.86, 0.42, 1.0)))
			btn.add_theme_color_override("font_color", COL_GOLD)
		else:
			btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.13, 0.18, 1.0), COL_BORDER))
			btn.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.19, 0.26, 1.0), Color(0.90, 0.78, 0.45, 1.0)))
			btn.add_theme_color_override("font_color", COL_INK)


func _type_tab_status(troop_type: String) -> String:
	if not has_node("/root/TroopState"):
		return "IDLE"
	if TroopState.is_training_ready(troop_type):
		return "READY"
	if TroopState.is_training_active(troop_type):
		return _format_mmss(int(TroopState.get_training_time_left(troop_type)))
	return "IDLE"


func _format_mmss(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	return "%d:%02d" % [int(sec / 60.0), sec % 60]


func _measure_hud_insets() -> Vector2:
	var top_inset: float = FALLBACK_TOP_INSET
	var bottom_inset: float = FALLBACK_BOTTOM_INSET
	var hud: Node = get_parent()
	if hud != null:
		hud = hud.get_parent()
	if hud == null:
		return Vector2(top_inset, bottom_inset)
	var chrome: Control = hud.get_node_or_null("Control") as Control
	if chrome == null:
		return Vector2(top_inset, bottom_inset)
	var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control
	var bottom_bar: Control = chrome.get_node_or_null("BottomBarTexture") as Control
	var local_origin: Vector2 = global_position
	var view_h: float = size.y if size.y > 1.0 else float(get_viewport_rect().size.y)
	if top_bar != null:
		var top_rect: Rect2 = top_bar.get_global_rect()
		top_inset = maxf(FALLBACK_TOP_INSET, (top_rect.position.y + top_rect.size.y) - local_origin.y + CONTENT_GAP)
	if bottom_bar != null:
		var bot_rect: Rect2 = bottom_bar.get_global_rect()
		bottom_inset = maxf(FALLBACK_BOTTOM_INSET, view_h - (bot_rect.position.y - local_origin.y) + CONTENT_GAP)
	top_inset = clampf(top_inset, 80.0, maxf(80.0, view_h - bottom_inset - 220.0))
	return Vector2(top_inset, bottom_inset)


func _apply_safe_area() -> void:
	var insets: Vector2 = _measure_hud_insets()
	_top_inset = insets.x
	_bottom_inset = insets.y
	if _dim != null:
		_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_dim.offset_top = _top_inset
		_dim.offset_bottom = -_bottom_inset
	if _window != null:
		_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.offset_left = SIDE_INSET
		_window.offset_top = _top_inset
		_window.offset_right = -SIDE_INSET
		_window.offset_bottom = -_bottom_inset


func _build_ui() -> void:
	while get_child_count() > 0:
		var old: Node = get_child(0)
		remove_child(old)
		old.free()
	_tier_buttons.clear()
	_source_buttons.clear()
	_type_tab_buttons.clear()
	_built_layout_version = UI_LAYOUT_VERSION

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0.04, 0.03, 0.06, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "TrainingWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 14, 2))
	add_child(_window)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 8)
	outer.add_theme_constant_override("margin_right", 8)
	outer.add_theme_constant_override("margin_top", 6)
	outer.add_theme_constant_override("margin_bottom", 6)
	_window.add_child(outer)

	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", 4)
	outer.add_child(_shell)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	_shell.add_child(header)
	var back_btn := _chrome_button("BACK", Vector2(96, 44))
	back_btn.pressed.connect(_close_screen)
	header.add_child(back_btn)
	var title := Label.new()
	title.text = "TROOP TRAINING"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var close_btn := _chrome_button("X", Vector2(56, 44))
	close_btn.name = "CloseButton"
	close_btn.pressed.connect(_close_screen)
	header.add_child(close_btn)

	# Troop-type switcher (Infantry / Marksmen / Cavalry)
	_type_tab_row = HBoxContainer.new()
	_type_tab_row.name = "TypeTabs"
	_type_tab_row.add_theme_constant_override("separation", 6)
	_shell.add_child(_type_tab_row)
	for tab: Dictionary in TYPE_TABS:
		var btn := _chrome_button(str(tab.get("label", "")), Vector2(0, 52))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.clip_text = false
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF
		var troop_key: String = str(tab.get("type", "Infantry"))
		btn.pressed.connect(func() -> void: switch_troop_type(troop_key))
		_type_tab_row.add_child(btn)
		_type_tab_buttons.append(btn)

	_building_title = _ink_label("", 15, COL_MUTED)
	_building_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shell.add_child(_building_title)

	_status_label = _ink_label("", 13, COL_WARN)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shell.add_child(_status_label)

	_job_block = VBoxContainer.new()
	_job_block.visible = false
	_job_block.add_theme_constant_override("separation", 4)
	_shell.add_child(_job_block)
	_job_title = _ink_label("", 20, COL_GOLD)
	_job_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_block.add_child(_job_title)
	_job_detail = _ink_label("", 16, COL_INK)
	_job_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_block.add_child(_job_detail)
	_job_time = _ink_label("", 24, COL_OK)
	_job_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_block.add_child(_job_time)
	_collect_button = _chrome_button("COLLECT", Vector2(0, 56))
	_collect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collect_button.pressed.connect(_on_collect_pressed)
	_job_block.add_child(_collect_button)

	_idle_block = VBoxContainer.new()
	_idle_block.add_theme_constant_override("separation", 4)
	_idle_block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell.add_child(_idle_block)

	# Troop card
	var troop_row := HBoxContainer.new()
	troop_row.add_theme_constant_override("separation", 8)
	_idle_block.add_child(troop_row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(64, 64)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	troop_row.add_child(_icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	troop_row.add_child(info)
	_troop_name_label = _ink_label("", 18, COL_GOLD)
	info.add_child(_troop_name_label)
	_troop_meta_label = _ink_label("", 13, COL_MUTED)
	info.add_child(_troop_meta_label)
	_stats_label = _ink_label("", 13, COL_INK)
	info.add_child(_stats_label)

	_idle_block.add_child(_section("TIER"))
	var tier_nav := HBoxContainer.new()
	tier_nav.add_theme_constant_override("separation", 4)
	_idle_block.add_child(tier_nav)
	var prev := _chrome_button("<", Vector2(40, 42))
	prev.pressed.connect(func() -> void:
		_tier_window_start = maxi(1, _tier_window_start - 1)
		_refresh_tier_chips()
	)
	tier_nav.add_child(prev)
	_tier_row = HBoxContainer.new()
	_tier_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_row.add_theme_constant_override("separation", 4)
	tier_nav.add_child(_tier_row)
	var next := _chrome_button(">", Vector2(40, 42))
	next.pressed.connect(func() -> void:
		_tier_window_start = mini(12 - TIER_CHIP_COUNT + 1, _tier_window_start + 1)
		_tier_window_start = maxi(1, _tier_window_start)
		_refresh_tier_chips()
	)
	tier_nav.add_child(next)
	for i: int in range(TIER_CHIP_COUNT):
		var chip := _chrome_button("T?", Vector2(0, 42))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_size_override("font_size", 15)
		var idx: int = i
		chip.pressed.connect(func() -> void: _on_tier_chip_pressed(idx))
		_tier_row.add_child(chip)
		_tier_buttons.append(chip)

	_idle_block.add_child(_section("MODE"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	_idle_block.add_child(mode_row)
	_train_mode_btn = _chrome_button("TRAIN", Vector2(0, 44))
	_train_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_train_mode_btn.pressed.connect(func() -> void: _set_mode("train"))
	mode_row.add_child(_train_mode_btn)
	_promote_mode_btn = _chrome_button("PROMOTE", Vector2(0, 44))
	_promote_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_promote_mode_btn.pressed.connect(func() -> void: _set_mode("promote"))
	mode_row.add_child(_promote_mode_btn)

	_source_label = _section("FROM TIER")
	_idle_block.add_child(_source_label)
	_source_row = HBoxContainer.new()
	_source_row.add_theme_constant_override("separation", 4)
	_idle_block.add_child(_source_row)

	_idle_block.add_child(_section("AMOUNT"))
	var qty := HBoxContainer.new()
	qty.add_theme_constant_override("separation", 8)
	qty.alignment = BoxContainer.ALIGNMENT_CENTER
	_idle_block.add_child(qty)
	var minus := _chrome_button("−", Vector2(60, 48))
	minus.pressed.connect(func() -> void: _adjust_amount(-_amount_step()))
	qty.add_child(minus)
	_amount_label = Label.new()
	_amount_label.custom_minimum_size = Vector2(110, 48)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.add_theme_font_size_override("font_size", 26)
	_amount_label.add_theme_color_override("font_color", COL_INK)
	qty.add_child(_amount_label)
	var plus := _chrome_button("+", Vector2(60, 48))
	plus.pressed.connect(func() -> void: _adjust_amount(_amount_step()))
	qty.add_child(plus)
	var max_btn := _chrome_button("MAX", Vector2(0, 40))
	max_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_btn.pressed.connect(_on_max_pressed)
	_idle_block.add_child(max_btn)

	_summary_label = _ink_label("", 13, COL_INK)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_idle_block.add_child(_summary_label)
	_cost_label = _ink_label("", 13, COL_MUTED)
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_idle_block.add_child(_cost_label)

	_action_button = _chrome_button("TRAIN", Vector2(0, 56))
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.add_theme_font_size_override("font_size", 20)
	_action_button.pressed.connect(_on_action_pressed)
	_idle_block.add_child(_action_button)

	_apply_safe_area()
	_refresh_type_tabs()


func _section(text: String) -> Label:
	return _ink_label(text, 13, COL_GOLD)


func _set_mode(mode: String) -> void:
	_mode = mode
	if _mode == "promote":
		_source_tier = _default_source_tier()
	_clamp_amount()
	_refresh_view()


func _default_source_tier() -> int:
	# Prefer highest owned tier strictly below selected target.
	var best: int = 0
	for tier: int in range(_selected_tier - 1, 0, -1):
		if TroopState.get_tier_count(_troop_type, tier) > 0:
			return tier
		if best == 0:
			best = tier
	return maxi(1, best)


func _on_tier_chip_pressed(chip_index: int) -> void:
	var tier: int = _tier_window_start + chip_index
	if tier < 1 or tier > 12:
		return
	if not TroopDatabase.is_tier_unlocked(_db_type(), tier, _building_level):
		_status_label.text = "LOCKED\nRequires %s" % TroopDatabase.get_unlock_requirement_text(_db_type(), tier)
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	_selected_tier = tier
	if _mode == "promote":
		_source_tier = _default_source_tier()
	_clamp_amount()
	_refresh_view()


func _capacity() -> int:
	return TroopDatabase.get_training_capacity(_building_level) if has_node("/root/TroopDatabase") else 100


func _amount_step() -> int:
	return 10 if _capacity() >= 100 else 1


func _max_for_mode() -> int:
	if _mode == "promote":
		var avail: int = TroopState.get_tier_count(_troop_type, _source_tier)
		return TroopDatabase.get_max_promotable(_db_type(), _source_tier, _selected_tier, _building_level, avail)
	return TroopDatabase.get_max_trainable(_db_type(), _selected_tier, _building_level)


func _clamp_amount() -> void:
	var cap: int = _capacity()
	if _mode == "promote":
		cap = mini(cap, TroopState.get_tier_count(_troop_type, _source_tier))
	_amount = clampi(_amount, 0, maxi(0, cap))


func _adjust_amount(delta: int) -> void:
	_amount = clampi(_amount + delta, 0, _capacity() if _mode == "train" else mini(_capacity(), TroopState.get_tier_count(_troop_type, _source_tier)))
	_refresh_idle_summary()


func _on_max_pressed() -> void:
	_amount = _max_for_mode()
	if _amount <= 0:
		_status_label.text = "Nothing available to %s." % _mode
		_status_label.add_theme_color_override("font_color", COL_WARN)
	_refresh_idle_summary()


func _refresh_view() -> void:
	var titles: Dictionary = _building_titles()
	_building_title.text = "%s  ·  Lv.%d" % [str(titles.get("subtitle", "")), _building_level]
	_refresh_type_tabs()

	if TroopState.is_training_ready(_troop_type) or TroopState.is_training_active(_troop_type):
		_idle_block.visible = false
		_job_block.visible = true
		_refresh_job()
		return

	_idle_block.visible = true
	_job_block.visible = false
	_refresh_idle()


func _refresh_job() -> void:
	var job: Dictionary = TroopState.get_training_job(_troop_type)
	var job_type: String = str(job.get("job_type", "train"))
	var qty: int = int(job.get("quantity", 0))
	var target: int = int(job.get("target_tier", 1))
	var source: int = int(job.get("source_tier", 0))
	if job_type == "promote":
		_job_title.text = "PROMOTING"
		_job_detail.text = "%s  T%d → T%d" % [_format_number(qty), source, target]
	else:
		_job_title.text = "TRAINING"
		_job_detail.text = "%s  %s  T%d" % [_format_number(qty), _troop_type, target]
	_collect_button.visible = TroopState.is_training_ready(_troop_type)
	if TroopState.is_training_ready(_troop_type):
		_job_time.text = "Complete — ready to collect"
		_status_label.text = ""
	else:
		_job_time.text = _format_remaining(int(TroopState.get_training_time_left(_troop_type)))
		_status_label.text = ""


func _refresh_idle() -> void:
	var troop: Dictionary = TroopDatabase.get_troop(_db_type(), _selected_tier)
	_troop_name_label.text = str(troop.get("name", _troop_type))
	_troop_meta_label.text = "Tier %d  ·  Owned %s" % [
		_selected_tier,
		_format_number(TroopState.get_tier_count(_troop_type, _selected_tier)),
	]
	_stats_label.text = "ATK %s   DEF %s   HP %s   POW %s" % [
		_format_number(int(troop.get("attack", 0))),
		_format_number(int(troop.get("defense", 0))),
		_format_number(int(troop.get("health", 0))),
		_format_number(int(troop.get("power", 0))),
	]
	var icon_path: String = str(TROOP_ICONS.get(_db_type(), ""))
	_icon.texture = load(icon_path) as Texture2D if icon_path != "" and ResourceLoader.exists(icon_path) else null

	_refresh_tier_chips()
	_train_mode_btn.disabled = _mode == "train"
	_promote_mode_btn.disabled = _mode == "promote"
	_refresh_source_row()
	_clamp_amount()
	_refresh_idle_summary()


func _refresh_tier_chips() -> void:
	_tier_window_start = clampi(_tier_window_start, 1, maxi(1, 12 - TIER_CHIP_COUNT + 1))
	for i: int in range(_tier_buttons.size()):
		var tier: int = _tier_window_start + i
		var btn: Button = _tier_buttons[i]
		var unlocked: bool = TroopDatabase.is_tier_unlocked(_db_type(), tier, _building_level)
		if unlocked:
			btn.text = "T%d" % tier
			btn.disabled = false
			btn.modulate = Color(1.2, 1.1, 0.85, 1.0) if tier == _selected_tier else Color.WHITE
		else:
			btn.text = "T%d🔒" % tier
			btn.disabled = false ## still tappable to show requirement
			btn.modulate = Color(0.7, 0.7, 0.7, 1.0)


func _refresh_source_row() -> void:
	var show_source: bool = _mode == "promote"
	_source_label.visible = show_source
	_source_row.visible = show_source
	for child: Node in _source_row.get_children():
		child.queue_free()
	_source_buttons.clear()
	if not show_source:
		return
	var any: bool = false
	for tier: int in range(1, _selected_tier):
		var owned: int = TroopState.get_tier_count(_troop_type, tier)
		if owned <= 0:
			continue
		any = true
		var btn := _chrome_button("T%d (%s)" % [tier, _format_number(owned)], Vector2(0, 40))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		var t: int = tier
		btn.pressed.connect(func() -> void:
			_source_tier = t
			_clamp_amount()
			_refresh_idle_summary()
			_refresh_source_highlight()
		)
		_source_row.add_child(btn)
		_source_buttons.append(btn)
	if not any:
		var empty := _ink_label("No lower-tier troops to promote.", 14, COL_MUTED)
		_source_row.add_child(empty)
	_refresh_source_highlight()


func _refresh_source_highlight() -> void:
	for btn: Button in _source_buttons:
		btn.modulate = Color(1.2, 1.1, 0.85, 1.0) if ("T%d" % _source_tier) in btn.text else Color.WHITE


func _refresh_idle_summary() -> void:
	_amount_label.text = _format_number(_amount)
	var cap: int = _capacity()
	var time_sec: int = 0
	var cost: Dictionary = {}
	if _mode == "promote":
		time_sec = TroopDatabase.get_promotion_time(_db_type(), _source_tier, _selected_tier, _amount) if _amount > 0 else 0
		cost = TroopDatabase.get_promotion_cost(_db_type(), _source_tier, _selected_tier, _amount) if _amount > 0 else {}
		_summary_label.text = "Promote T%d → T%d\nAvailable %s\nCapacity %s / %s\nTime %s" % [
			_source_tier,
			_selected_tier,
			_format_number(TroopState.get_tier_count(_troop_type, _source_tier)),
			_format_number(_amount),
			_format_number(cap),
			_format_hms(time_sec),
		]
		_action_button.text = "PROMOTE %s → T%d" % [_format_number(_amount), _selected_tier]
	else:
		time_sec = TroopDatabase.get_training_time(_db_type(), _selected_tier, _amount) if _amount > 0 else 0
		cost = TroopDatabase.get_training_cost(_db_type(), _selected_tier, _amount) if _amount > 0 else {}
		_summary_label.text = "Train T%d\nOwned %s\nCapacity %s / %s\nTime %s" % [
			_selected_tier,
			_format_number(TroopState.get_tier_count(_troop_type, _selected_tier)),
			_format_number(_amount),
			_format_number(cap),
			_format_hms(time_sec),
		]
		_action_button.text = "TRAIN %s T%d" % [_format_number(_amount), _selected_tier]

	_cost_label.text = "Cost\n%s" % _format_cost_lines(cost)
	var reason: String = _validate_reason()
	_action_button.disabled = reason != ""
	if reason != "":
		_status_label.text = reason
		_status_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_status_label.text = ""


func _validate_reason() -> String:
	if TroopState.has_active_job(_troop_type):
		return "A training/promotion job is already active."
	if _amount <= 0:
		return "Select an amount greater than zero."
	if not TroopDatabase.is_tier_unlocked(_db_type(), _selected_tier, _building_level):
		return "LOCKED\nRequires %s" % TroopDatabase.get_unlock_requirement_text(_db_type(), _selected_tier)
	if _mode == "promote":
		if _selected_tier <= 1:
			return "Select a higher unlocked tier to promote into."
		if _source_tier <= 0 or _source_tier >= _selected_tier:
			return "Choose a lower source tier."
		if TroopState.get_tier_count(_troop_type, _source_tier) < _amount:
			return "Not enough T%d troops." % _source_tier
		var pcost: Dictionary = TroopDatabase.get_promotion_cost(_db_type(), _source_tier, _selected_tier, _amount)
		if not TroopDatabase.can_afford(pcost):
			return TroopDatabase.get_missing_cost_text(pcost)
	else:
		if _amount > _capacity():
			return "Amount exceeds training capacity."
		var tcost: Dictionary = TroopDatabase.get_training_cost(_db_type(), _selected_tier, _amount)
		if not TroopDatabase.can_afford(tcost):
			return TroopDatabase.get_missing_cost_text(tcost)
	return ""


func _on_action_pressed() -> void:
	var reason: String = _validate_reason()
	if reason != "":
		_status_label.text = reason
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return

	if _mode == "promote":
		var pcost: Dictionary = TroopDatabase.get_promotion_cost(_db_type(), _source_tier, _selected_tier, _amount)
		var pdur: int = TroopDatabase.get_promotion_time(_db_type(), _source_tier, _selected_tier, _amount)
		if not TroopDatabase.spend_training_cost(pcost):
			_status_label.text = TroopDatabase.get_missing_cost_text(pcost)
			return
		if not TroopState.start_promotion(_troop_type, _amount, pdur, _source_tier, _selected_tier):
			TroopDatabase.refund_training_cost(pcost)
			_status_label.text = "Could not start promotion."
			_status_label.add_theme_color_override("font_color", COL_WARN)
			return
	else:
		var tcost: Dictionary = TroopDatabase.get_training_cost(_db_type(), _selected_tier, _amount)
		var tdur: int = TroopDatabase.get_training_time(_db_type(), _selected_tier, _amount)
		if not TroopDatabase.spend_training_cost(tcost):
			_status_label.text = TroopDatabase.get_missing_cost_text(tcost)
			return
		if not TroopState.start_training(_troop_type, _amount, tdur, _selected_tier):
			TroopDatabase.refund_training_cost(tcost)
			_status_label.text = "Could not start training."
			_status_label.add_theme_color_override("font_color", COL_WARN)
			return

	_amount = 0
	_refresh_view()


func _on_collect_pressed() -> void:
	if not TroopState.collect_training(_troop_type):
		_status_label.text = "Nothing ready to collect."
		return
	_status_label.text = "Collected."
	_status_label.add_theme_color_override("font_color", COL_OK)
	_refresh_view()


func _close_screen() -> void:
	var manager: Node = _find_ui_manager()
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_tree_mouse_ignore(self, true)


func _find_ui_manager() -> Node:
	var local: Node = get_node_or_null("../../UIManager")
	if local != null:
		return local
	var hud: Node = get_parent()
	while hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null:
			return mgr
		hud = hud.get_parent()
	return get_tree().root.find_child("UIManager", true, false)


func _set_tree_mouse_ignore(node: Node, ignore_when_hidden: bool) -> void:
	if node is Control:
		var c := node as Control
		if ignore_when_hidden and not c.visible:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_tree_mouse_ignore(child, ignore_when_hidden)


func _format_cost_lines(cost: Dictionary) -> String:
	if cost.is_empty() or _amount <= 0:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["food", "wood", "stone", "iron"]:
		var value: int = int(cost.get(key, 0))
		if value > 0:
			parts.append("%s %s" % [key.capitalize(), _format_number(value)])
	return "  ".join(parts) if not parts.is_empty() else "Free"


func _format_hms(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	return "%02d:%02d:%02d" % [int(sec / 3600.0), int((sec % 3600) / 60.0), sec % 60]


func _format_remaining(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	if sec >= 3600:
		return "%dh %dm %ds" % [int(sec / 3600.0), int((sec % 3600) / 60.0), sec % 60]
	if sec >= 60:
		return "%dm %ds" % [int(sec / 60.0), sec % 60]
	return "%ds" % sec


func _format_number(value: int) -> String:
	var raw: String = str(value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _ink_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.14, 0.20, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.26, 0.20, 0.28, 1.0), Color(1.0, 0.86, 0.42, 1.0)))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.10, 0.14, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.16, 0.14, 0.16, 1.0), Color(0.35, 0.30, 0.28, 1.0)))
	return btn


func _panel_style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_w))
	style.set_corner_radius_all(int(radius))
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(bg, border, 10, 2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
