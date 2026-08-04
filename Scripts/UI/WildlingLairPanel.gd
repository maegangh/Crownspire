extends Control

## Compact Wildling Lair world popup — Scout / Attack / Rally.

const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")

const TOP_SAFE := 188.0
const BOTTOM_SAFE := 200.0
const PANEL_W := 640.0
const PANEL_MAX_H := 820.0

const COL_INK := Color(0.18, 0.16, 0.22, 1.0)
const COL_MUTED := Color(0.42, 0.40, 0.48, 1.0)
const COL_GOLD := Color(0.78, 0.62, 0.22, 1.0)
const COL_GOLD_BRIGHT := Color(0.92, 0.76, 0.28, 1.0)
const COL_SAPPHIRE := Color(0.22, 0.42, 0.72, 1.0)
const COL_PANEL := Color(0.96, 0.95, 0.92, 0.98)
const COL_BORDER := Color(0.78, 0.62, 0.22, 0.95)
const COL_WARN := Color(0.72, 0.28, 0.22, 1.0)
const COL_BTN := Color(0.22, 0.42, 0.72, 1.0)

var _payload: Dictionary = {}
var _lair_node: Node2D = null
var _scout_mode: bool = false
var _status_msg: String = ""

var _dim: ColorRect
var _window: PanelContainer
var _title_label: Label
var _level_label: Label
var _creature_label: Label
var _art_rect: TextureRect
var _power_label: Label
var _hp_label: Label
var _difficulty_label: Label
var _coords_label: Label
var _enemies_label: Label
var _rewards_label: Label
var _scout_label: Label
var _beta_label: Label
var _action_status: Label
var _scout_btn: Button
var _attack_btn: Button
var _rally_btn: Button
var _close_btn: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	close_panel()


func open_for_lair(payload: Dictionary, lair_node: Node2D = null) -> void:
	_payload = payload.duplicate(true)
	_lair_node = lair_node
	_scout_mode = false
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 920
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if _window != null:
		_window.mouse_filter = Control.MOUSE_FILTER_STOP


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lair_node = null
	_scout_mode = false
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _window != null:
		_window.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	while get_child_count() > 0:
		var old: Node = get_child(0)
		remove_child(old)
		old.free()

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0.08, 0.08, 0.12, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "LairWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 14, 2))
	add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_window.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)

	_title_label = Label.new()
	_title_label.text = "ALLIANCE LAIR"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", COL_GOLD_BRIGHT)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title_label)

	_close_btn = _chrome_button("X", Vector2(72, 54))
	_close_btn.pressed.connect(close_panel)
	header.add_child(_close_btn)

	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	_art_rect = TextureRect.new()
	_art_rect.name = "LairArt"
	_art_rect.custom_minimum_size = Vector2(220, 180)
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_art_rect)

	_level_label = _section_label("", 26, COL_INK)
	col.add_child(_level_label)

	_creature_label = _muted_label("")
	_creature_label.add_theme_font_size_override("font_size", 16)
	col.add_child(_creature_label)

	col.add_child(_muted_label("Recommended Power"))
	_power_label = _section_label("", 24, COL_GOLD)
	col.add_child(_power_label)

	col.add_child(_muted_label("HP"))
	_hp_label = _section_label("", 22, COL_SAPPHIRE)
	col.add_child(_hp_label)

	col.add_child(_muted_label("Difficulty"))
	_difficulty_label = _section_label("", 20, COL_INK)
	col.add_child(_difficulty_label)

	_coords_label = _muted_label("")
	_coords_label.add_theme_font_size_override("font_size", 15)
	col.add_child(_coords_label)

	col.add_child(_muted_label("Enemies"))
	_enemies_label = _body_label("")
	col.add_child(_enemies_label)

	_scout_label = _body_label("")
	_scout_label.add_theme_color_override("font_color", COL_SAPPHIRE)
	_scout_label.visible = false
	col.add_child(_scout_label)

	col.add_child(_muted_label("Rewards"))
	_rewards_label = _body_label("")
	col.add_child(_rewards_label)

	_beta_label = _muted_label("BETA placeholder balance")
	_beta_label.add_theme_font_size_override("font_size", 14)
	col.add_child(_beta_label)

	_action_status = _body_label("")
	_action_status.add_theme_color_override("font_color", COL_WARN)
	_action_status.visible = false
	col.add_child(_action_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	outer.add_child(actions)

	_scout_btn = _action_button("SCOUT")
	_scout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scout_btn.pressed.connect(_on_scout)
	actions.add_child(_scout_btn)

	_attack_btn = _action_button("ATTACK")
	_attack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attack_btn.pressed.connect(_on_attack)
	actions.add_child(_attack_btn)

	_rally_btn = _action_button("RALLY")
	_rally_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rally_btn.add_theme_stylebox_override("normal", _button_style(Color(0.55, 0.42, 0.12, 1.0), COL_GOLD_BRIGHT))
	_rally_btn.pressed.connect(_on_rally)
	actions.add_child(_rally_btn)

	_layout_window()


func _refresh() -> void:
	var level: int = int(_payload.get("lair_level", _payload.get("den_level", 1)))
	var def: Dictionary = _payload.get("level_def", {}) as Dictionary
	if def.is_empty():
		def = WildlingLairDatabase.get_level_def(level)
	var power: int = int(_payload.get("recommended_power", def.get("recommended_power", 0)))
	var creature: String = str(_payload.get("creature_title", WildlingLairDatabase.creature_title(def)))
	var max_hp: int = int(_payload.get("max_hp", def.get("max_hp", 0)))
	var cur_hp: int = int(_payload.get("current_hp", max_hp))
	var difficulty: String = str(_payload.get("difficulty", def.get("difficulty", "Normal")))
	var wx: float = float(_payload.get("world_x", _payload.get("world_position", {}).get("x", 0.0)))
	var wy: float = float(_payload.get("world_y", _payload.get("world_position", {}).get("y", 0.0)))
	var active: bool = bool(_payload.get("active", true))
	if _title_label != null:
		_title_label.text = str(_payload.get("display_name", "ALLIANCE LAIR")).to_upper()
	if _level_label != null:
		_level_label.text = "Lv. %d" % level
	if _creature_label != null:
		_creature_label.text = creature
		_creature_label.visible = not creature.is_empty()
	if _art_rect != null:
		_art_rect.texture = WildlingLairDatabase.get_texture_for_level_def(def)
	if _power_label != null:
		_power_label.text = WildlingLairDatabase.format_power(power)
	if _hp_label != null:
		_hp_label.text = "%s / %s" % [
			WildlingLairDatabase.format_power(cur_hp),
			WildlingLairDatabase.format_power(max_hp),
		]
	if _difficulty_label != null:
		_difficulty_label.text = difficulty
	if _coords_label != null:
		_coords_label.text = "Coords  X:%.0f  Y:%.0f" % [wx, wy]
	if _enemies_label != null:
		_enemies_label.text = str(def.get("enemy_description", "Elite lair creatures."))
	if _rewards_label != null:
		var rewards: Dictionary = def.get("reward_preview", {}) as Dictionary
		_rewards_label.text = WildlingLairDatabase.format_reward_preview(rewards)
	if _beta_label != null:
		_beta_label.visible = WildlingLairDatabase.is_beta()
	if _scout_label != null:
		_scout_label.visible = _scout_mode
		if _scout_mode:
			var rally_note: String = "Rally required." if bool(_payload.get("rally_required", def.get("rally_required", true))) else "Solo Attack allowed."
			_scout_label.text = "Scout Report (beta — no scout march yet)\nLevel: %d\nHP: %s / %s\nRecommended Power: %s\nDifficulty: %s\nExpected strength: %s\nRewards:\n%s\n%s\n(Scout travel march: future work)" % [
				level,
				WildlingLairDatabase.format_power(cur_hp),
				WildlingLairDatabase.format_power(max_hp),
				WildlingLairDatabase.format_power(power),
				difficulty,
				creature if creature != "" else "Unknown",
				WildlingLairDatabase.format_reward_preview(def.get("reward_preview", {})),
				rally_note,
			]
	if _action_status != null:
		if _status_msg != "":
			_action_status.text = _status_msg
			_action_status.visible = true
		elif not active:
			_action_status.text = "This Alliance Lair is defeated and respawning."
			_action_status.visible = true
		else:
			_action_status.visible = false
	if _attack_btn != null:
		_attack_btn.disabled = not active
	if _rally_btn != null:
		_rally_btn.disabled = not active
	_layout_window()


func _on_scout() -> void:
	_scout_mode = true
	_status_msg = ""
	_refresh()


func _on_attack() -> void:
	_status_msg = ""
	var lid: String = str(_payload.get("lair_id", ""))
	if has_node("/root/AllianceLairState"):
		var check: Dictionary = AllianceLairState.validate_solo_attack(lid)
		if not bool(check.get("ok", false)):
			_status_msg = str(check.get("error", "Cannot attack."))
			_refresh()
			return
	elif bool(_payload.get("rally_required", true)):
		_status_msg = "This Alliance Lair must be attacked by a Rally."
		_refresh()
		return
	close_panel()
	var setup: Node = _find_march_setup()
	if setup == null or not setup.has_method("open_for_target"):
		push_error("[AllianceLair] MarchSetupScreen missing")
		return
	var pos: Dictionary = _payload.get("world_position", {}) as Dictionary
	if pos.is_empty():
		pos = {"x": float(_payload.get("world_x", 0.0)), "y": float(_payload.get("world_y", 0.0))}
	var target: Dictionary = {
		"target_type": "wildling_lair",
		"target_id": lid,
		"lair_id": lid,
		"lair_level": int(_payload.get("lair_level", 1)),
		"level": int(_payload.get("lair_level", 1)),
		"species": str(_payload.get("species", "")),
		"recommended_power": int(_payload.get("recommended_power", 0)),
		"visual_variant": str(_payload.get("visual_variant", "")),
		"max_hp": int(_payload.get("max_hp", 0)),
		"current_hp": int(_payload.get("current_hp", 0)),
		"difficulty": str(_payload.get("difficulty", "")),
		"world_position": pos.duplicate(true),
		"position": pos.duplicate(true),
		"display_name": str(_payload.get("target_name", "Alliance Lair Lv.%d" % int(_payload.get("lair_level", 1)))),
		"level_def": _payload.get("level_def", {}),
		"kingdom_id": str(_payload.get("kingdom_id", "")),
	}
	setup.call("open_for_target", target)


func _on_rally() -> void:
	_status_msg = ""
	var lid: String = str(_payload.get("lair_id", ""))
	if has_node("/root/AllianceLairState"):
		var check: Dictionary = AllianceLairState.validate_rally_target(lid)
		if not bool(check.get("ok", false)):
			_status_msg = str(check.get("error", "Cannot rally."))
			_refresh()
			return
	if has_node("/root/AllianceBackend") and not AllianceBackend.is_membership_authority():
		_status_msg = "Join an Alliance to create a Rally."
		_refresh()
		return
	close_panel()
	var screen: Node = _find_rally_setup()
	if screen == null:
		push_error("[AllianceLair] RallySetupScreen not found")
		return
	var payload: Dictionary = _payload.duplicate(true)
	if has_node("/root/AllianceLairState") and lid != "":
		var fresh: Dictionary = AllianceLairState.build_ui_payload(lid)
		if not fresh.is_empty():
			payload = fresh
	if screen.has_method("open_for_lair"):
		screen.call("open_for_lair", payload)
	else:
		push_error("[AllianceLair] RallySetupScreen missing open_for_lair()")


func _find_rally_setup() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var via_hud: Node = scene.get_node_or_null("GameHUD/ScreenRoot/RallySetupScreen")
		if via_hud != null:
			return via_hud
	return get_tree().root.find_child("RallySetupScreen", true, false)


func _find_march_setup() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var via_hud: Node = scene.get_node_or_null("GameHUD/ScreenRoot/MarchSetupScreen")
		if via_hud != null:
			return via_hud
	return get_tree().root.find_child("MarchSetupScreen", true, false)


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
	elif event is InputEventScreenTouch and event.pressed:
		close_panel()


func _layout_window() -> void:
	if _window == null:
		return
	var view := get_viewport_rect().size
	var usable_top := TOP_SAFE
	var usable_bottom := view.y - BOTTOM_SAFE
	var usable_h := maxf(320.0, usable_bottom - usable_top)
	var win_w := minf(PANEL_W, maxf(300.0, view.x - 40.0))
	var win_h := minf(PANEL_MAX_H, usable_h - 24.0)
	var cx := view.x * 0.5
	var cy := usable_top + usable_h * 0.5
	_window.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_window.offset_left = cx - win_w * 0.5
	_window.offset_right = cx + win_w * 0.5
	_window.offset_top = cy - win_h * 0.5
	_window.offset_bottom = cy + win_h * 0.5
	_window.custom_minimum_size = Vector2(win_w, win_h)


func _section_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", COL_MUTED)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _body_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", COL_INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(560, 0)
	return l


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.92, 0.91, 0.88, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.97, 0.95, 0.90, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.86, 0.85, 0.82, 1.0), COL_GOLD))
	return btn


func _action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 68)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92, 1.0))
	btn.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_GOLD))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.28, 0.50, 0.80, 1.0), COL_GOLD_BRIGHT))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.32, 0.56, 1.0), COL_GOLD))
	return btn


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
