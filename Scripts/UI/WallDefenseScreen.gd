extends Control

## City Wall defensive hero assignment (persistence via HeroState).
## Runtime: GameHUD/ScreenRoot/WallDefenseScreen
## No PvP combat / Wall durability — assignment only.

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_SLOT := Color(0.08, 0.07, 0.10, 0.95)

const TOP_SAFE: float = 168.0
const BOTTOM_SAFE: float = 188.0
const UI_LAYOUT_VERSION: int = 1

var _editing: bool = false
var _draft_ids: Array[String] = []
var _built: bool = false
## Coalesce UI rebuilds so picker buttons are never freed mid-signal.
var _refresh_pending: bool = false

var _wall_level_label: Label
var _power_label: Label
var _status_label: Label
var _edit_button: Button
var _slots_row: HBoxContainer
var _slot_buttons: Array[Button] = []
var _slot_captions: Array[Label] = []
var _picker_list: VBoxContainer
var _picker_panel: PanelContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if has_node("/root/HeroState") and not HeroState.heroes_changed.is_connected(_on_heroes_changed):
		HeroState.heroes_changed.connect(_on_heroes_changed)


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_editing = false
	_sync_draft_from_saved()
	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editing = false
	_refresh_pending = false


func _on_heroes_changed() -> void:
	if visible:
		if not _editing:
			_sync_draft_from_saved()
		_request_refresh()


## Rebuild after the current signal/frame so pressed picker buttons are not freed while locked.
func _request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_perform_refresh")


func _perform_refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree() or not visible:
		return
	_refresh()


func _sync_draft_from_saved() -> void:
	_draft_ids.clear()
	if has_node("/root/HeroState"):
		for hid: String in HeroState.get_wall_defender_ids():
			_draft_ids.append(hid)


func _build_ui() -> void:
	if _built:
		return
	_built = true
	for child: Node in get_children():
		child.queue_free()
	_slot_buttons.clear()
	_slot_captions.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE
	dim.offset_bottom = -BOTTOM_SAFE
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 12.0
	window.offset_top = TOP_SAFE
	window.offset_right = -12.0
	window.offset_bottom = -BOTTOM_SAFE
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	window.add_child(margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	margin.add_child(shell)

	var header := HBoxContainer.new()
	shell.add_child(header)
	var title := Label.new()
	title.text = "CITY DEFENSE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(48, 44)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	_wall_level_label = Label.new()
	_wall_level_label.add_theme_font_size_override("font_size", 15)
	_wall_level_label.add_theme_color_override("font_color", COL_MUTED)
	shell.add_child(_wall_level_label)

	shell.add_child(_section("DEFENDING HEROES"))

	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 10)
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(_slots_row)

	var max_slots: int = 3
	if has_node("/root/HeroState"):
		max_slots = HeroState.get_max_wall_defenders()
	for i: int in range(max_slots):
		_slots_row.add_child(_make_slot(i))

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.add_theme_font_size_override("font_size", 18)
	_power_label.add_theme_color_override("font_color", COL_INK)
	shell.add_child(_power_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	shell.add_child(_status_label)

	_edit_button = Button.new()
	_edit_button.custom_minimum_size = Vector2(0, 56)
	_edit_button.add_theme_font_size_override("font_size", 20)
	_edit_button.pressed.connect(_on_edit_pressed)
	shell.add_child(_edit_button)

	_picker_panel = PanelContainer.new()
	_picker_panel.visible = false
	_picker_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_panel.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 12, 1))
	shell.add_child(_picker_panel)

	var picker_margin := MarginContainer.new()
	picker_margin.add_theme_constant_override("margin_left", 8)
	picker_margin.add_theme_constant_override("margin_right", 8)
	picker_margin.add_theme_constant_override("margin_top", 8)
	picker_margin.add_theme_constant_override("margin_bottom", 8)
	_picker_panel.add_child(picker_margin)

	var picker_scroll := ScrollContainer.new()
	picker_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	picker_margin.add_child(picker_scroll)

	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 6)
	picker_scroll.add_child(_picker_list)

	print("[WallDefenseScreen] layout v%d" % UI_LAYOUT_VERSION)


func _make_slot(index: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(110, 120)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("normal", _panel_style(COL_SLOT, COL_BORDER, 10, 1))
	slot.pressed.connect(func() -> void: _on_slot_pressed(index))
	var cap := Label.new()
	cap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cap.offset_left = 6
	cap.offset_top = 6
	cap.offset_right = -6
	cap.offset_bottom = -6
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", COL_MUTED)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cap)
	_slot_buttons.append(slot)
	_slot_captions.append(cap)
	return slot


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l


func _refresh() -> void:
	_wall_level_label.text = "Wall Lv. %d" % _get_wall_level()
	var power: int = 0
	if has_node("/root/HeroState"):
		# Draft power while editing; saved power otherwise.
		if _editing:
			for hid: String in _draft_ids:
				power += HeroState.get_hero_display_power(hid)
		else:
			power = HeroState.get_city_defense_power()
	_power_label.text = "City Defense Power: %s" % _format_number(power)

	for i: int in range(_slot_captions.size()):
		if i < _draft_ids.size():
			var hid: String = _draft_ids[i]
			var name_s: String = hid.capitalize()
			var level: int = 1
			if has_node("/root/HeroState"):
				var owned: Dictionary = HeroState.get_owned_hero(hid)
				name_s = str(owned.get("name", hid.capitalize()))
				level = int(owned.get("level", 1))
			_slot_captions[i].text = "%s\nLv.%d" % [name_s, level]
			_slot_captions[i].add_theme_color_override("font_color", COL_INK)
		else:
			_slot_captions[i].text = "Empty"
			_slot_captions[i].add_theme_color_override("font_color", COL_MUTED)

	_edit_button.text = "SAVE DEFENDERS" if _editing else "EDIT DEFENDERS"
	_picker_panel.visible = _editing
	if _editing:
		_rebuild_picker()
		_status_label.text = "Tap a hero to assign, or tap a filled slot to remove."
		_status_label.add_theme_color_override("font_color", COL_MUTED)
	else:
		if _draft_ids.is_empty():
			_status_label.text = "No defenders assigned. Assign heroes to prepare City Defense."
		else:
			_status_label.text = "Defenders ready. They cannot join marches while assigned."
		_status_label.add_theme_color_override("font_color", COL_OK)


func _rebuild_picker() -> void:
	for child: Node in _picker_list.get_children():
		_picker_list.remove_child(child)
		child.queue_free()
	if not has_node("/root/HeroState"):
		return
	var max_slots: int = HeroState.get_max_wall_defenders()
	for hero: Dictionary in HeroState.get_owned_heroes():
		var hid: String = str(hero.get("id", ""))
		if hid.is_empty():
			continue
		# Capture by value for this button (avoid loop-variable reuse).
		var assign_id: String = hid
		var on_march: bool = HeroState.is_hero_on_march(hid)
		var already: bool = hid in _draft_ids
		var btn := Button.new()
		var name_s: String = str(hero.get("name", hid.capitalize()))
		var level: int = int(hero.get("level", 1))
		var pwr: int = HeroState.get_hero_display_power(hid)
		if on_march:
			btn.text = "%s Lv.%d — ON MARCH" % [name_s, level]
			btn.disabled = true
		elif already:
			btn.text = "%s Lv.%d — ASSIGNED (tap slot to remove)" % [name_s, level]
			btn.disabled = true
		elif _draft_ids.size() >= max_slots:
			btn.text = "%s Lv.%d · Pwr %s — SLOTS FULL" % [name_s, level, _format_number(pwr)]
			btn.disabled = true
		else:
			btn.text = "%s Lv.%d · Pwr %s — ASSIGN" % [name_s, level, _format_number(pwr)]
			btn.disabled = false
			btn.pressed.connect(func() -> void: _assign_hero(assign_id))
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_picker_list.add_child(btn)


func _assign_hero(hero_id: String) -> void:
	if hero_id in _draft_ids:
		return
	if not has_node("/root/HeroState"):
		return
	if HeroState.is_hero_on_march(hero_id):
		_status_label.text = "Hero is on a march."
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	var max_slots: int = HeroState.get_max_wall_defenders()
	if _draft_ids.size() >= max_slots:
		return
	_draft_ids.append(hero_id)
	_request_refresh()


func _on_slot_pressed(index: int) -> void:
	if not _editing:
		return
	if index < _draft_ids.size():
		_draft_ids.remove_at(index)
		_request_refresh()


func _on_edit_pressed() -> void:
	if not _editing:
		_editing = true
		_sync_draft_from_saved()
		_request_refresh()
		return
	# Save draft
	if not has_node("/root/HeroState"):
		_status_label.text = "HeroState unavailable."
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	var result: Dictionary = HeroState.set_wall_defenders(_draft_ids)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Could not save defenders."))
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	_editing = false
	_sync_draft_from_saved()
	_request_refresh()
	_status_label.text = "Defenders saved."
	_status_label.add_theme_color_override("font_color", COL_OK)


func _get_wall_level() -> int:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return 1
	var wall: Node = scene.get_node_or_null("Buildings/Wall")
	if wall == null:
		wall = scene.find_child("Wall", true, false)
	if wall != null and "building_level" in wall:
		return maxi(1, int(wall.get("building_level")))
	return 1


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _panel_style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(border_w))
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _format_number(value: int) -> String:
	var raw: String = str(maxi(0, value))
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
