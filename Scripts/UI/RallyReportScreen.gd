extends Control

## Rally battle report — lair, outcome, participants, rewards.

const TOP_SAFE := 188.0
const BOTTOM_SAFE := 200.0

const COL_INK := Color(0.18, 0.16, 0.22, 1.0)
const COL_MUTED := Color(0.42, 0.40, 0.48, 1.0)
const COL_GOLD := Color(0.78, 0.62, 0.22, 1.0)
const COL_SAPPHIRE := Color(0.22, 0.42, 0.72, 1.0)
const COL_PANEL := Color(0.96, 0.95, 0.92, 0.98)
const COL_CARD := Color(0.91, 0.90, 0.87, 0.96)
const COL_BORDER := Color(0.78, 0.62, 0.22, 0.95)
const COL_OK := Color(0.18, 0.52, 0.32, 1.0)
const COL_FAIL := Color(0.72, 0.28, 0.22, 1.0)

var _rally: Dictionary = {}
var _body: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 48
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_for_rally(rally: Dictionary) -> void:
	_rally = rally.duplicate(true)
	_rebuild_body()
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.open_screen("RallyReportScreen")
	else:
		on_open()


func _build_shell() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.06, 0.10, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE
	dim.offset_bottom = -BOTTOM_SAFE
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 16
	window.offset_top = TOP_SAFE + 20
	window.offset_right = -16
	window.offset_bottom = -BOTTOM_SAFE - 20
	window.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER))
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "RALLY REPORT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(64, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", _style(COL_CARD, COL_BORDER))
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)


func _rebuild_body() -> void:
	if _body == null:
		_build_shell()
	for c in _body.get_children():
		c.queue_free()
	var result: Dictionary = _rally.get("result", {}) as Dictionary
	var victory: bool = bool(result.get("victory", false))
	var outcome := Label.new()
	outcome.text = "VICTORY" if victory else "DEFEAT"
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.add_theme_font_size_override("font_size", 36)
	outcome.add_theme_color_override("font_color", COL_OK if victory else COL_FAIL)
	_body.add_child(outcome)

	_body.add_child(_line("Lair", "Wildling Lair Lv.%d" % int(_rally.get("lair_level", 1))))
	_body.add_child(_line("Difficulty", "Recommended Power %s" % _fmt(int(_rally.get("recommended_power", 0)))))
	_body.add_child(_line("Damage Dealt", _fmt(int(result.get("damage_dealt", 0)))))
	_body.add_child(_line("Remaining HP", _fmt(int(result.get("remaining_hp", 0)))))

	var parts_title := Label.new()
	parts_title.text = "Participants"
	parts_title.add_theme_color_override("font_color", COL_SAPPHIRE)
	parts_title.add_theme_font_size_override("font_size", 18)
	_body.add_child(parts_title)

	for p in _rally.get("participants", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var tc: Dictionary = p.get("troop_counts", {}) as Dictionary
		var troops: int = int(tc.get("infantry", 0)) + int(tc.get("marksmen", 0)) + int(tc.get("cavalry", 0))
		_body.add_child(_line(str(p.get("display_name", "Player")), "%d troops · %s power" % [troops, _fmt(int(p.get("power", 0)))]))

	var rewards: Dictionary = result.get("rewards", {}) as Dictionary
	if not rewards.is_empty():
		var rt := Label.new()
		rt.text = "Rewards"
		rt.add_theme_color_override("font_color", COL_GOLD)
		rt.add_theme_font_size_override("font_size", 18)
		_body.add_child(rt)
		for k in rewards.keys():
			_body.add_child(_line(str(k).capitalize(), str(rewards[k])))

	var ok := Button.new()
	ok.text = "CONTINUE"
	ok.custom_minimum_size = Vector2(0, 64)
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_font_size_override("font_size", 20)
	ok.add_theme_color_override("font_color", Color.WHITE)
	ok.add_theme_stylebox_override("normal", _style(COL_SAPPHIRE, COL_GOLD))
	ok.pressed.connect(_on_close)
	_body.add_child(ok)

	if victory:
		outcome.scale = Vector2(0.85, 0.85)
		var tw := create_tween()
		tw.tween_property(outcome, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _line(left: String, right: String) -> Control:
	var row := HBoxContainer.new()
	var a := Label.new()
	a.text = left
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_color_override("font_color", COL_MUTED)
	a.add_theme_font_size_override("font_size", 16)
	row.add_child(a)
	var b := Label.new()
	b.text = right
	b.add_theme_color_override("font_color", COL_INK)
	b.add_theme_font_size_override("font_size", 16)
	row.add_child(b)
	return row


func _on_close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _fmt(v: int) -> String:
	if v >= 1000000:
		return "%.1fM" % (float(v) / 1000000.0)
	if v >= 1000:
		return "%.1fK" % (float(v) / 1000.0)
	return str(v)


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
