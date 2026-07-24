extends Control

## Crownspire Mail — battle reports inbox + detail.
## Rewards are display-only; opening mail never grants anything.

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_UNREAD := Color(0.95, 0.72, 0.28, 1.0)

const BOTTOM_SAFE_MARGIN: float = 200.0

var _category: String = "battle"
var _detail_id: String = ""
var _list_root: VBoxContainer
var _detail_root: Control
var _inbox_root: Control
var _empty_label: Label
var _battle_tab: Button
var _system_tab: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if has_node("/root/MailManager") and not MailManager.mail_changed.is_connected(_on_mail_changed):
		MailManager.mail_changed.connect(_on_mail_changed)


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_id = ""
	_show_inbox()
	_refresh_list()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_id = ""


func _on_mail_changed() -> void:
	if visible:
		if _detail_id != "":
			_show_detail(_detail_id)
		else:
			_refresh_list()


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.04, 0.03, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_bottom = -BOTTOM_SAFE_MARGIN
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "MailWindow"
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 18.0
	window.offset_top = 36.0
	window.offset_right = -18.0
	window.offset_bottom = -BOTTOM_SAFE_MARGIN
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(window)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	window.add_child(outer)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	outer.add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	shell.add_child(header)

	var title := Label.new()
	title.text = "MAIL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)

	var close_btn := _chrome_button("X", Vector2(64, 48))
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(tabs)

	_battle_tab = _chrome_button("BATTLE", Vector2(180, 46))
	_battle_tab.pressed.connect(func() -> void: _set_category("battle"))
	tabs.add_child(_battle_tab)
	_system_tab = _chrome_button("SYSTEM", Vector2(180, 46))
	_system_tab.pressed.connect(func() -> void: _set_category("system"))
	tabs.add_child(_system_tab)

	_inbox_root = Control.new()
	_inbox_root.name = "InboxRoot"
	_inbox_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inbox_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(_inbox_root)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inbox_root.add_child(scroll)

	_list_root = VBoxContainer.new()
	_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_root.add_theme_constant_override("separation", 10)
	scroll.add_child(_list_root)

	_empty_label = Label.new()
	_empty_label.text = "No battle reports yet."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 18)
	_empty_label.add_theme_color_override("font_color", COL_MUTED)
	_list_root.add_child(_empty_label)

	_detail_root = Control.new()
	_detail_root.name = "DetailRoot"
	_detail_root.visible = false
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(_detail_root)


func _set_category(category: String) -> void:
	_category = category
	_detail_id = ""
	_show_inbox()
	_refresh_list()


func _show_inbox() -> void:
	_inbox_root.visible = true
	_detail_root.visible = false
	_battle_tab.disabled = _category == "battle"
	_system_tab.disabled = _category == "system"


func _refresh_list() -> void:
	for child: Node in _list_root.get_children():
		child.queue_free()

	if not has_node("/root/MailManager"):
		_empty_label = Label.new()
		_empty_label.text = "Mail system unavailable."
		_empty_label.add_theme_color_override("font_color", COL_WARN)
		_list_root.add_child(_empty_label)
		return

	var rows: Array[Dictionary] = MailManager.get_messages_by_category(_category)
	if rows.is_empty():
		_empty_label = Label.new()
		if _category == "system":
			_empty_label.text = "No system messages."
		else:
			_empty_label.text = "No battle reports yet."
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.add_theme_font_size_override("font_size", 18)
		_empty_label.add_theme_color_override("font_color", COL_MUTED)
		_list_root.add_child(_empty_label)
		return

	for msg: Dictionary in rows:
		_list_root.add_child(_make_inbox_row(msg))


func _make_inbox_row(msg: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 12, 1))
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(0, 88)
	card.add_child(btn)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	var victory: bool = bool(msg.get("result", {}).get("victory", false))
	var result_l := Label.new()
	result_l.text = "VICTORY" if victory else "DEFEAT"
	result_l.add_theme_font_size_override("font_size", 18)
	result_l.add_theme_color_override("font_color", COL_OK if victory else COL_WARN)
	result_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(result_l)

	if not bool(msg.get("read", false)):
		var unread := Label.new()
		unread.text = "● NEW"
		unread.add_theme_font_size_override("font_size", 14)
		unread.add_theme_color_override("font_color", COL_UNREAD)
		unread.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(unread)

	var target: Dictionary = msg.get("target", {})
	var target_l := Label.new()
	target_l.text = "%s  Lv.%d" % [
		str(target.get("display_name", "Wildling")),
		int(target.get("level", 1)),
	]
	target_l.add_theme_font_size_override("font_size", 16)
	target_l.add_theme_color_override("font_color", COL_INK)
	target_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(target_l)

	var time_l := Label.new()
	time_l.text = _format_timestamp(int(msg.get("timestamp", 0)))
	time_l.add_theme_font_size_override("font_size", 13)
	time_l.add_theme_color_override("font_color", COL_MUTED)
	time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(time_l)

	var report_id: String = str(msg.get("report_id", ""))
	btn.pressed.connect(func() -> void: _open_report(report_id))
	return card


func _open_report(report_id: String) -> void:
	if has_node("/root/MailManager"):
		MailManager.mark_read(report_id)
	_show_detail(report_id)


func _show_detail(report_id: String) -> void:
	_detail_id = report_id
	_inbox_root.visible = false
	_detail_root.visible = true
	for child: Node in _detail_root.get_children():
		child.queue_free()

	var msg: Dictionary = {}
	if has_node("/root/MailManager"):
		msg = MailManager.get_message(report_id)
	if msg.is_empty():
		var missing := Label.new()
		missing.text = "Report not found."
		missing.add_theme_color_override("font_color", COL_WARN)
		_detail_root.add_child(missing)
		return

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

	var heading := Label.new()
	heading.text = "BATTLE REPORT"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(heading)

	var victory: bool = bool(msg.get("result", {}).get("victory", false))
	var result_l := Label.new()
	result_l.text = "Victory" if victory else "Defeat"
	result_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_l.add_theme_font_size_override("font_size", 28)
	result_l.add_theme_color_override("font_color", COL_OK if victory else COL_WARN)
	root.add_child(result_l)

	var target: Dictionary = msg.get("target", {})
	root.add_child(_kv_block("Target", "%s\nLv.%d" % [
		str(target.get("display_name", "Wildling")),
		int(target.get("level", 1)),
	]))

	var march: Dictionary = msg.get("march", {})
	root.add_child(_kv_block("March Power", _format_number(int(march.get("march_power", 0)))))

	var hero_names: PackedStringArray = PackedStringArray()
	for hid: Variant in march.get("hero_ids", []):
		hero_names.append(_hero_display_name(str(hid)))
	root.add_child(_kv_block(
		"Heroes",
		", ".join(hero_names) if not hero_names.is_empty() else "None"
	))

	root.add_child(_kv_block("Troops Sent", _troop_lines(march)))
	root.add_child(_kv_block("Losses", _troop_lines(msg.get("losses", {}))))
	root.add_child(_kv_block("Survivors", _troop_lines(msg.get("survivors", {}))))

	var rewards: Dictionary = msg.get("rewards", {})
	if victory and not rewards.is_empty():
		root.add_child(_kv_block("Rewards", _reward_lines(rewards)))
	elif victory:
		root.add_child(_kv_block("Rewards", "None listed"))
	else:
		root.add_child(_kv_block("Rewards", "None (defeat)"))

	var back := _chrome_button("BACK", Vector2(0, 54))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		_detail_id = ""
		_show_inbox()
		_refresh_list()
	)
	root.add_child(back)


func _kv_block(title: String, body: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 12, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", COL_INK)
	col.add_child(b)
	return card


func _troop_lines(data: Dictionary) -> String:
	return "Infantry %s\nMarksmen %s\nCavalry %s" % [
		_format_number(int(data.get("infantry", 0))),
		_format_number(int(data.get("marksmen", 0))),
		_format_number(int(data.get("cavalry", 0))),
	]


func _reward_lines(rewards: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in rewards.keys():
		parts.append("%s  %s" % [str(key).capitalize().replace("_", " "), _format_number(int(rewards[key]))])
	return "\n".join(parts)


func _hero_display_name(hero_id: String) -> String:
	if has_node("/root/HeroState"):
		for hero: Dictionary in HeroState.recruited_heroes:
			if str(hero.get("id", "")) == hero_id:
				var n: String = str(hero.get("name", ""))
				if n != "":
					return n
	if has_node("/root/DataManager") and DataManager.has_method("get_hero"):
		var data: Dictionary = DataManager.get_hero(hero_id)
		if not data.is_empty():
			return str(data.get("name", hero_id.capitalize()))
	return hero_id.capitalize()


func _format_timestamp(unix_ts: int) -> String:
	if unix_ts <= 0:
		return ""
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_ts)
	return "%04d-%02d-%02d  %02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]


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


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.13, 0.18, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.18, 0.24, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.10, 0.14, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.22, 0.18, 0.12, 1.0), COL_GOLD))
	return btn


func _panel_style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_w))
	style.set_corner_radius_all(int(radius))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(bg, border, 12, 2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()
