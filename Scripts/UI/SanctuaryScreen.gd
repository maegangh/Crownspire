extends Control

## Sanctuary recovery screen — passive overflow, no heal/upgrade controls.
## Runtime: GameHUD/ScreenRoot/SanctuaryScreen

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)

const FALLBACK_TOP_INSET: float = 180.0
const FALLBACK_BOTTOM_INSET: float = 190.0
const SIDE_INSET: float = 14.0
const UI_LAYOUT_VERSION: int = 1

var _built_layout_version: int = -1
var _top_inset: float = FALLBACK_TOP_INSET
var _bottom_inset: float = FALLBACK_BOTTOM_INSET
var _refresh_accum: float = 0.0
var _row_fingerprint: String = ""

var _dim: ColorRect
var _window: PanelContainer
var _empty_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _total_label: Label
var _meta_label: Label
## key kind|tier -> timer Label
var _timer_labels: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_layout()
	if has_node("/root/SanctuaryState") and not SanctuaryState.sanctuary_changed.is_connected(_on_changed):
		SanctuaryState.sanctuary_changed.connect(_on_changed)
	if has_node("/root/TroopState") and not TroopState.training_updated.is_connected(_on_changed):
		TroopState.training_updated.connect(_on_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.35:
		return
	_refresh_accum = 0.0
	_refresh_timers_only()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row_fingerprint = ""
	_ensure_layout()
	_rebuild_rows()
	_refresh_totals()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_changed(_a = null, _b = null) -> void:
	if not visible:
		return
	_rebuild_rows()
	_refresh_totals()


func _hud_ui_manager() -> Node:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null:
		return manager
	var hud: Node = get_tree().root.find_child("GameHUD", true, false)
	if hud != null:
		return hud.get_node_or_null("UIManager")
	return null


func _close() -> void:
	var manager: Node = _hud_ui_manager()
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _ensure_layout() -> void:
	_resolve_insets()
	if _built_layout_version == UI_LAYOUT_VERSION and _window != null and is_instance_valid(_window):
		_apply_window_margins()
		return
	for child: Node in get_children():
		child.queue_free()
	_timer_labels.clear()
	_built_layout_version = UI_LAYOUT_VERSION

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 14, 2))
	add_child(_window)
	_apply_window_margins()

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_window.add_child(margin)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(header)
	var title := Label.new()
	title.text = "SANCTUARY"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(48, 48)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var blurb := Label.new()
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blurb.text = "A quiet refuge for wounded troops unable to enter the Hospital."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(blurb)

	var section := Label.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.text = "Recovering Troops"
	section.add_theme_font_size_override("font_size", 18)
	section.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(section)

	_empty_label = Label.new()
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.text = "The Sanctuary is empty."
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_empty_label)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 360)
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	_total_label = Label.new()
	_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total_label.add_theme_font_size_override("font_size", 16)
	_total_label.add_theme_color_override("font_color", COL_INK)
	root.add_child(_total_label)

	_meta_label = Label.new()
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta_label.text = "Recovery: Passive\nNo Resources Required"
	_meta_label.add_theme_font_size_override("font_size", 14)
	_meta_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_meta_label)


func _resolve_insets() -> void:
	_top_inset = FALLBACK_TOP_INSET
	_bottom_inset = FALLBACK_BOTTOM_INSET
	var hud: Node = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return
	var chrome: Control = hud.get_node_or_null("Control") as Control
	if chrome == null:
		return
	var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control
	var bottom_bar: Control = chrome.get_node_or_null("BottomBarTexture") as Control
	if top_bar != null:
		_top_inset = maxf(FALLBACK_TOP_INSET, top_bar.size.y + 12.0)
	if bottom_bar != null:
		_bottom_inset = maxf(FALLBACK_BOTTOM_INSET, bottom_bar.size.y + 12.0)


func _apply_window_margins() -> void:
	if _window == null:
		return
	_window.offset_left = SIDE_INSET
	_window.offset_right = -SIDE_INSET
	_window.offset_top = _top_inset
	_window.offset_bottom = -_bottom_inset


func _rebuild_rows() -> void:
	var stacks: Array = []
	if has_node("/root/SanctuaryState"):
		stacks = SanctuaryState.get_display_stacks()
	var fp: String = JSON.stringify(stacks)
	if fp == _row_fingerprint and _list != null and _list.get_child_count() > 0:
		_refresh_timers_only()
		return
	_row_fingerprint = fp
	_timer_labels.clear()
	if _list == null:
		return
	for child: Node in _list.get_children():
		child.queue_free()

	_empty_label.visible = stacks.is_empty()
	var last_kind: String = ""
	var now: int = int(Time.get_unix_time_from_system())
	for entry: Variant in stacks:
		var row: Dictionary = entry as Dictionary
		var kind: String = str(row.get("kind", ""))
		if kind != last_kind:
			last_kind = kind
			var hdr := Label.new()
			hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hdr.text = kind.to_upper()
			hdr.add_theme_font_size_override("font_size", 16)
			hdr.add_theme_color_override("font_color", COL_GOLD)
			_list.add_child(hdr)
		_list.add_child(_make_stack_row(row, now))


func _make_stack_row(row: Dictionary, now: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(COL_CARD, Color(1, 1, 1, 0.08), 8, 1))
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h)

	var info := Label.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = "T%d      %s" % [int(row.get("tier", 1)), _format_number(int(row.get("quantity", 0)))]
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", COL_INK)
	h.add_child(info)

	var timer := Label.new()
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer.custom_minimum_size = Vector2(100, 0)
	timer.add_theme_font_size_override("font_size", 15)
	timer.add_theme_color_override("font_color", COL_OK)
	var rem: float = maxf(0.0, float(int(row.get("end_unix", now)) - now))
	timer.text = _format_hms(rem)
	h.add_child(timer)
	_timer_labels["%s|%d" % [str(row.get("kind", "")), int(row.get("tier", 0))]] = {
		"label": timer,
		"end_unix": int(row.get("end_unix", now)),
	}
	return panel


func _refresh_timers_only() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for key: Variant in _timer_labels.keys():
		var entry: Dictionary = _timer_labels[key] as Dictionary
		var lbl: Label = entry.get("label") as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		var rem: float = maxf(0.0, float(int(entry.get("end_unix", now)) - now))
		lbl.text = _format_hms(rem)
	_refresh_totals()
	# If a wave completed, rebuild once.
	if has_node("/root/SanctuaryState"):
		var fp: String = JSON.stringify(SanctuaryState.get_display_stacks())
		if fp != _row_fingerprint:
			_rebuild_rows()


func _refresh_totals() -> void:
	var total: int = 0
	if has_node("/root/SanctuaryState"):
		total = SanctuaryState.get_total_recovering()
	_total_label.text = "Total Recovering:\n%s" % _format_number(total)


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


func _format_hms(seconds: float) -> String:
	var s: int = maxi(0, int(ceil(seconds)))
	var h: int = int(s / 3600)
	var m: int = int((s % 3600) / 60)
	var r: int = s % 60
	if h > 0:
		return "%02d:%02d:%02d" % [h, m, r]
	return "%02d:%02d" % [m, r]


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
