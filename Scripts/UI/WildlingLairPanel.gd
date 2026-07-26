extends Control

## Compact Wildling Lair world popup (720×1280 HUD-safe).
## CREATE RALLY opens Rally Setup UI shell only — no authoritative rally.

const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")

const TOP_SAFE := 188.0
const BOTTOM_SAFE := 200.0
const PANEL_W := 640.0
const PANEL_MAX_H := 820.0

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_GOLD_BRIGHT := Color(1.0, 0.86, 0.42, 1.0)
const COL_PANEL := Color(0.12, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.72, 0.32, 0.28, 0.95)
const COL_WARN := Color(0.95, 0.55, 0.45, 1.0)
const COL_BTN := Color(0.42, 0.18, 0.16, 1.0)

var _payload: Dictionary = {}
var _lair_node: Node2D = null

var _dim: ColorRect
var _window: PanelContainer
var _title_label: Label
var _level_label: Label
var _creature_label: Label
var _art_rect: TextureRect
var _power_label: Label
var _enemies_label: Label
var _rewards_label: Label
var _beta_label: Label
var _create_btn: Button
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
	_dim.color = Color(0.04, 0.02, 0.03, 0.66)
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
	_title_label.text = "WILDLING LAIR"
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

	col.add_child(_muted_label("Enemies"))
	_enemies_label = _body_label("")
	col.add_child(_enemies_label)

	var rally_req := _section_label("Rally Required", 22, COL_WARN)
	col.add_child(rally_req)

	col.add_child(_muted_label("Rewards"))
	_rewards_label = _body_label("")
	col.add_child(_rewards_label)

	_beta_label = _muted_label("BETA placeholder balance")
	_beta_label.add_theme_font_size_override("font_size", 14)
	col.add_child(_beta_label)

	_create_btn = Button.new()
	_create_btn.text = "CREATE RALLY"
	_create_btn.custom_minimum_size = Vector2(0, 72)
	_create_btn.focus_mode = Control.FOCUS_NONE
	_create_btn.add_theme_font_size_override("font_size", 24)
	_create_btn.add_theme_color_override("font_color", COL_INK)
	_create_btn.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_GOLD))
	_create_btn.add_theme_stylebox_override("hover", _button_style(Color(0.52, 0.24, 0.20, 1.0), COL_GOLD_BRIGHT))
	_create_btn.add_theme_stylebox_override("pressed", _button_style(Color(0.32, 0.14, 0.12, 1.0), COL_GOLD))
	_create_btn.pressed.connect(_on_create_rally)
	outer.add_child(_create_btn)

	_layout_window()


func _refresh() -> void:
	var level: int = int(_payload.get("lair_level", _payload.get("den_level", 1)))
	var def: Dictionary = _payload.get("level_def", {}) as Dictionary
	if def.is_empty():
		def = WildlingLairDatabase.get_level_def(level)
	var power: int = int(_payload.get("recommended_power", def.get("recommended_power", 0)))
	var creature: String = str(_payload.get("creature_title", WildlingLairDatabase.creature_title(def)))
	if _title_label != null:
		_title_label.text = "WILDLING LAIR"
	if _level_label != null:
		_level_label.text = "Lv. %d" % level
	if _creature_label != null:
		_creature_label.text = creature
		_creature_label.visible = not creature.is_empty()
	if _art_rect != null:
		_art_rect.texture = WildlingLairDatabase.get_texture_for_level_def(def)
	if _power_label != null:
		_power_label.text = WildlingLairDatabase.format_power(power)
	if _enemies_label != null:
		_enemies_label.text = str(def.get("enemy_description", "Elite lair creatures. Rally required."))
	if _rewards_label != null:
		var rewards: Dictionary = def.get("reward_preview", {}) as Dictionary
		_rewards_label.text = WildlingLairDatabase.format_reward_preview(rewards)
	if _beta_label != null:
		_beta_label.visible = WildlingLairDatabase.is_beta()
	_layout_window()


func _on_create_rally() -> void:
	close_panel()
	var screen: Node = _find_rally_setup()
	if screen == null:
		push_error("[WildlingLair] RallySetupScreen not found")
		return
	if screen.has_method("open_for_lair"):
		screen.call("open_for_lair", _payload.duplicate(true))
	else:
		push_error("[WildlingLair] RallySetupScreen missing open_for_lair()")


func _find_rally_setup() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var via_hud: Node = scene.get_node_or_null("GameHUD/ScreenRoot/RallySetupScreen")
		if via_hud != null:
			return via_hud
	return get_tree().root.find_child("RallySetupScreen", true, false)


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
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.10, 0.11, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.14, 0.14, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.08, 0.08, 1.0), COL_GOLD))
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
