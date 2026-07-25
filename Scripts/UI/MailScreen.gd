extends Control

## Crownspire Mail — battle reports inbox + detail.
## Rewards are display-only; opening mail never grants anything.
##
## Runtime: GameHUD/ScreenRoot/MailScreen → res://scripts/UI/MailScreen.gd
## Layout sits BETWEEN permanent top HUD and bottom nav (ScreenRoot is under HUD z).

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_UNREAD := Color(0.95, 0.72, 0.28, 1.0)

## Fallbacks if HUD nodes are missing (720x1280 portrait).
## Top bar global bottom is ~164px; keep clear gap so header/X are never under chrome z=100.
const FALLBACK_TOP_INSET: float = 180.0
const FALLBACK_BOTTOM_INSET: float = 190.0
const SIDE_INSET: float = 20.0
const CONTENT_GAP: float = 12.0
## Compact centered mailbox (not a full-band page).
const MAIL_WIDTH: float = 660.0
const MAIL_HEIGHT: float = 560.0
const UI_LAYOUT_VERSION: int = 4

var _category: String = "battle"
var _detail_id: String = ""
var _built_layout_version: int = -1
var _top_inset: float = FALLBACK_TOP_INSET
var _bottom_inset: float = FALLBACK_BOTTOM_INSET

var _dim: ColorRect
var _window: PanelContainer
var _list_root: VBoxContainer
var _detail_body: VBoxContainer
var _inbox_root: Control
var _detail_root: Control
var _tabs_row: HBoxContainer
var _empty_label: Label
var _battle_tab: Button
var _system_tab: Button
var _inbox_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _mobile_inbox
var _mobile_detail
var _header_title: Label
var _header_back_button: Button
var _close_button: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_current_layout()
	if has_node("/root/MailManager") and not MailManager.mail_changed.is_connected(_on_mail_changed):
		MailManager.mail_changed.connect(_on_mail_changed)
	resized.connect(_on_resized)


func on_open() -> void:
	_ensure_current_layout()
	_detail_id = ""
	_pick_initial_category()
	_apply_safe_area()
	_show_inbox()
	_refresh_list()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[MailScreen] opened layout v%d | safe top=%.1f bottom=%.1f | window %.0fx%.0f" % [
		UI_LAYOUT_VERSION,
		_top_inset,
		_bottom_inset,
		_window.size.x if _window else 0.0,
		_window.size.y if _window else 0.0,
	])
	call_deferred("_log_safe_area_after_layout")


func on_close() -> void:
	_reset_to_inbox_state()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_tree_mouse_ignore(self, true)


func _on_resized() -> void:
	if visible:
		_apply_safe_area()


func _ensure_current_layout() -> void:
	# Rebuild when layout version changes so compact popup replaces full-band Mail.
	if _built_layout_version != UI_LAYOUT_VERSION or get_node_or_null("MailWindow") == null:
		_build_ui()
	_apply_safe_area()


func _pick_initial_category() -> void:
	if not has_node("/root/MailManager"):
		return
	var battle_rows: Array[Dictionary] = MailManager.get_messages_by_category("battle")
	var system_rows: Array[Dictionary] = MailManager.get_messages_by_category("system")
	if battle_rows.is_empty() and not system_rows.is_empty():
		_category = "system"
	elif not battle_rows.is_empty() and system_rows.is_empty():
		_category = "battle"


func _reset_to_inbox_state() -> void:
	_detail_id = ""
	_clear_detail_body()
	_show_inbox()


func _on_mail_changed() -> void:
	if not visible:
		return
	if _detail_id != "":
		_populate_detail(_detail_id)
	else:
		_refresh_list()


## Measure permanent HUD bars and place Mail in the usable center band.
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
		var top_bottom_local: float = (top_rect.position.y + top_rect.size.y) - local_origin.y
		top_inset = maxf(FALLBACK_TOP_INSET, top_bottom_local + CONTENT_GAP)

	if bottom_bar != null:
		var bot_rect: Rect2 = bottom_bar.get_global_rect()
		var bot_top_local: float = bot_rect.position.y - local_origin.y
		var from_bottom: float = view_h - bot_top_local
		bottom_inset = maxf(FALLBACK_BOTTOM_INSET, from_bottom + CONTENT_GAP)

	# Keep a usable content band even on odd viewports.
	var max_top: float = maxf(80.0, view_h - bottom_inset - 220.0)
	top_inset = clampf(top_inset, 80.0, max_top)
	return Vector2(top_inset, bottom_inset)


func _apply_safe_area() -> void:
	var insets: Vector2 = _measure_hud_insets()
	_top_inset = insets.x
	_bottom_inset = insets.y
	var view_w: float = size.x if size.x > 1.0 else float(get_viewport_rect().size.x)
	var view_h: float = size.y if size.y > 1.0 else float(get_viewport_rect().size.y)

	if _dim != null:
		_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_dim.offset_left = 0.0
		_dim.offset_top = 0.0
		_dim.offset_right = 0.0
		_dim.offset_bottom = 0.0

	if _window != null:
		var usable_top: float = _top_inset
		var usable_bottom: float = view_h - _bottom_inset
		var usable_h: float = maxf(320.0, usable_bottom - usable_top)
		var win_w: float = minf(MAIL_WIDTH, maxf(320.0, view_w - SIDE_INSET * 2.0))
		# Fixed compact height — never stretch to fill the HUD band.
		var win_h: float = MAIL_HEIGHT if usable_h >= MAIL_HEIGHT + 24.0 else maxf(320.0, usable_h - 24.0)
		var center_x: float = view_w * 0.5
		var center_y: float = usable_top + usable_h * 0.5
		_window.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_window.anchor_left = 0.0
		_window.anchor_top = 0.0
		_window.anchor_right = 0.0
		_window.anchor_bottom = 0.0
		_window.offset_left = center_x - win_w * 0.5
		_window.offset_right = center_x + win_w * 0.5
		_window.offset_top = center_y - win_h * 0.5
		_window.offset_bottom = center_y + win_h * 0.5
		_window.custom_minimum_size = Vector2(win_w, win_h)


func _build_ui() -> void:
	# Immediate free so stale layout-v2 chrome cannot linger a frame under the HUD.
	while get_child_count() > 0:
		var old: Node = get_child(0)
		remove_child(old)
		old.free()
	_mobile_inbox = null
	_mobile_detail = null
	_built_layout_version = UI_LAYOUT_VERSION

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0.04, 0.03, 0.06, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "MailWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(_window)

	var outer := MarginContainer.new()
	outer.name = "MailMargins"
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_top", 10)
	outer.add_theme_constant_override("margin_bottom", 10)
	_window.add_child(outer)

	var shell := VBoxContainer.new()
	shell.name = "MailShell"
	shell.add_theme_constant_override("separation", 10)
	outer.add_child(shell)

	# Fixed header — NOT inside any ScrollContainer.
	var header := HBoxContainer.new()
	header.name = "MailHeader"
	header.add_theme_constant_override("separation", 8)
	shell.add_child(header)

	_header_back_button = _chrome_button("BACK", Vector2(110, 54))
	_header_back_button.name = "MailBackButton"
	_header_back_button.visible = false
	_header_back_button.pressed.connect(_on_detail_back)
	header.add_child(_header_back_button)

	_header_title = Label.new()
	_header_title.name = "MailTitle"
	_header_title.text = "MAIL"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_title.add_theme_font_size_override("font_size", 28)
	_header_title.add_theme_color_override("font_color", COL_GOLD)
	_header_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_header_title)

	_close_button = _chrome_button("X", Vector2(72, 54))
	_close_button.name = "MailCloseButton"
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(_close_mail)
	header.add_child(_close_button)

	_tabs_row = HBoxContainer.new()
	_tabs_row.name = "CategoryTabs"
	_tabs_row.add_theme_constant_override("separation", 8)
	_tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(_tabs_row)

	_battle_tab = _chrome_button("BATTLE", Vector2(180, 46))
	_battle_tab.pressed.connect(func() -> void: _set_category("battle"))
	_tabs_row.add_child(_battle_tab)
	_system_tab = _chrome_button("SYSTEM", Vector2(180, 46))
	_system_tab.pressed.connect(func() -> void: _set_category("system"))
	_tabs_row.add_child(_system_tab)

	# Inbox: scrollable report list only.
	_inbox_root = Control.new()
	_inbox_root.name = "InboxRoot"
	_inbox_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inbox_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(_inbox_root)

	_inbox_scroll = ScrollContainer.new()
	_inbox_scroll.name = "InboxScroll"
	_inbox_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inbox_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inbox_root.add_child(_inbox_scroll)

	_list_root = VBoxContainer.new()
	_list_root.name = "ReportList"
	_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_root.add_theme_constant_override("separation", 10)
	_inbox_scroll.add_child(_list_root)

	_empty_label = Label.new()
	_empty_label.text = "No battle reports."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 18)
	_empty_label.add_theme_color_override("font_color", COL_MUTED)
	_list_root.add_child(_empty_label)

	# Detail: scrollable body only; BACK/X stay in fixed header.
	_detail_root = Control.new()
	_detail_root.name = "DetailRoot"
	_detail_root.visible = false
	_detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(_detail_root)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(_detail_scroll)

	_detail_body = VBoxContainer.new()
	_detail_body.name = "DetailBody"
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_constant_override("separation", 12)
	_detail_scroll.add_child(_detail_body)

	_mobile_inbox = MobileScrollUtil.ensure(self, _inbox_scroll, "MobileScrollInbox")
	_mobile_detail = MobileScrollUtil.ensure(self, _detail_scroll, "MobileScrollDetail")
	if _mobile_detail != null:
		_mobile_detail.set_enabled(false)

	_apply_safe_area()
	_refresh_tab_styles()
	print("[MailScreen] layout v%d built; header X outside scroll; CloseButton=%s" % [
		UI_LAYOUT_VERSION,
		str(_close_button != null),
	])


func _set_category(category: String) -> void:
	_category = category
	_detail_id = ""
	_show_inbox()
	_refresh_list()


func _set_panel_input(panel: Control, active: bool) -> void:
	if panel == null:
		return
	panel.visible = active
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		_set_tree_mouse_ignore(panel, true)


func _set_tree_mouse_ignore(node: Node, ignore_when_hidden: bool) -> void:
	if node is Control:
		var c := node as Control
		if ignore_when_hidden and not c.visible:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_tree_mouse_ignore(child, ignore_when_hidden)


func _show_inbox() -> void:
	_set_panel_input(_inbox_root, true)
	_set_panel_input(_detail_root, false)
	if _header_title != null:
		_header_title.text = "MAIL"
	if _header_back_button != null:
		_header_back_button.visible = false
	if _tabs_row != null:
		_tabs_row.visible = true
	_refresh_tab_styles()
	if _mobile_inbox != null:
		_mobile_inbox.bind(_inbox_scroll)
		_mobile_inbox.set_enabled(true)
	if _mobile_detail != null:
		_mobile_detail.set_enabled(false)
	if _close_button != null:
		_close_button.visible = true
		_close_button.disabled = false


func _refresh_tab_styles() -> void:
	_style_category_tab(_battle_tab, _category == "battle")
	_style_category_tab(_system_tab, _category == "system")


func _style_category_tab(tab: Button, selected: bool) -> void:
	if tab == null:
		return
	tab.disabled = false
	if selected:
		tab.add_theme_stylebox_override("normal", _button_style(Color(0.42, 0.32, 0.12, 1.0), Color(1.0, 0.86, 0.42, 1.0)))
		tab.add_theme_stylebox_override("hover", _button_style(Color(0.50, 0.38, 0.14, 1.0), Color(1.0, 0.92, 0.55, 1.0)))
		tab.add_theme_stylebox_override("pressed", _button_style(Color(0.34, 0.26, 0.10, 1.0), COL_GOLD))
		tab.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72, 1.0))
		tab.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		tab.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.10, 0.14, 1.0), Color(0.35, 0.30, 0.24, 0.85)))
		tab.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.15, 0.20, 1.0), Color(0.55, 0.45, 0.30, 0.95)))
		tab.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.08, 0.12, 1.0), COL_BORDER))
		tab.add_theme_color_override("font_color", COL_MUTED)
		tab.modulate = Color(0.92, 0.90, 0.88, 1.0)


func _show_detail_page() -> void:
	_set_panel_input(_inbox_root, false)
	_set_panel_input(_detail_root, true)
	if _header_title != null:
		var detail_title: String = "BATTLE REPORT"
		if has_node("/root/MailManager") and _detail_id != "":
			var msg: Dictionary = MailManager.get_message(_detail_id)
			if str(msg.get("type", "")) == "gathering_report":
				detail_title = "GATHERING REPORT"
		_header_title.text = detail_title
	if _header_back_button != null:
		_header_back_button.visible = true
		_header_back_button.disabled = false
	if _tabs_row != null:
		_tabs_row.visible = false
	if _mobile_inbox != null:
		_mobile_inbox.set_enabled(false)
	if _mobile_detail != null:
		_mobile_detail.bind(_detail_scroll)
		_mobile_detail.set_enabled(true)
	if _close_button != null:
		_close_button.visible = true
		_close_button.disabled = false


func _on_detail_back() -> void:
	_detail_id = ""
	_clear_detail_body()
	_show_inbox()
	_refresh_list()


func _clear_detail_body() -> void:
	if _detail_body == null:
		return
	for child: Node in _detail_body.get_children():
		child.queue_free()


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
			_empty_label.text = "No battle reports."
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.add_theme_font_size_override("font_size", 18)
		_empty_label.add_theme_color_override("font_color", COL_MUTED)
		_list_root.add_child(_empty_label)
		return

	for msg: Dictionary in rows:
		_list_root.add_child(_make_inbox_row(msg))


func _make_inbox_row(msg: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 10, 1))
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(0, 70)
	card.add_child(btn)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	var msg_type: String = str(msg.get("type", ""))
	var result_l := Label.new()
	if msg_type == "gathering_report":
		result_l.text = "GATHERING REPORT"
		result_l.add_theme_color_override("font_color", COL_OK)
	else:
		var victory: bool = bool(msg.get("result", {}).get("victory", false))
		result_l.text = "VICTORY" if victory else "DEFEAT"
		result_l.add_theme_color_override("font_color", COL_OK if victory else COL_WARN)
	result_l.add_theme_font_size_override("font_size", 16)
	result_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(result_l)

	if not bool(msg.get("read", false)):
		var unread := Label.new()
		unread.text = "● NEW"
		unread.add_theme_font_size_override("font_size", 12)
		unread.add_theme_color_override("font_color", COL_UNREAD)
		unread.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(unread)

	var preview_l := Label.new()
	if msg_type == "gathering_report":
		var source: Dictionary = msg.get("source", {})
		var resource: Dictionary = msg.get("resource", {})
		preview_l.text = "%s\nLv.%d\n+%s %s" % [
			str(source.get("display_name", "Resource")),
			int(source.get("level", 1)),
			_format_number(int(resource.get("amount", 0))),
			str(resource.get("display_type", resource.get("type", ""))),
		]
	else:
		var target: Dictionary = msg.get("target", {})
		preview_l.text = "%s  Lv.%d" % [
			str(target.get("display_name", "Wildling")),
			int(target.get("level", 1)),
		]
	preview_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_l.add_theme_font_size_override("font_size", 14)
	preview_l.add_theme_color_override("font_color", COL_INK)
	preview_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(preview_l)

	var time_l := Label.new()
	time_l.text = _format_timestamp(int(msg.get("timestamp", 0)))
	time_l.add_theme_font_size_override("font_size", 12)
	time_l.add_theme_color_override("font_color", COL_MUTED)
	time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(time_l)

	var report_id: String = str(msg.get("report_id", ""))
	if _mobile_inbox != null:
		_mobile_inbox.wire_tap(btn, func() -> void: _open_report(report_id))
	else:
		btn.pressed.connect(func() -> void: _open_report(report_id))
	return card


func _open_report(report_id: String) -> void:
	if has_node("/root/MailManager"):
		MailManager.mark_read(report_id)
	_detail_id = report_id
	_populate_detail(report_id)
	_show_detail_page()


func _populate_detail(report_id: String) -> void:
	_clear_detail_body()
	var msg: Dictionary = {}
	if has_node("/root/MailManager"):
		msg = MailManager.get_message(report_id)
	if msg.is_empty():
		var missing := Label.new()
		missing.text = "Report not found."
		missing.add_theme_color_override("font_color", COL_WARN)
		_detail_body.add_child(missing)
		return

	if str(msg.get("type", "")) == "gathering_report":
		_populate_gathering_detail(msg)
	else:
		_populate_battle_detail(msg)

	if _detail_scroll != null:
		_detail_scroll.scroll_vertical = 0


func _populate_gathering_detail(msg: Dictionary) -> void:
	var title := Label.new()
	title.text = "GATHERING REPORT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_GOLD)
	_detail_body.add_child(title)

	_detail_body.add_child(_kv_block("Status", str(msg.get("status", "Successful"))))

	var source: Dictionary = msg.get("source", {})
	_detail_body.add_child(_kv_block("Source", "%s · Lv.%d" % [
		str(source.get("display_name", "Resource")),
		int(source.get("level", 1)),
	]))

	var resource: Dictionary = msg.get("resource", {})
	var rtype: String = str(resource.get("display_type", resource.get("type", ""))).capitalize()
	_detail_body.add_child(_kv_block("%s Gathered" % rtype, _format_number(int(resource.get("amount", 0)))))

	_detail_body.add_child(_kv_block("Summary", str(msg.get("summary", "March returned safely."))))

	var march: Dictionary = msg.get("march", {})
	_detail_body.add_child(_kv_block("Troops", _troop_lines(march)))

	var hero_names: PackedStringArray = PackedStringArray()
	for hid: Variant in march.get("hero_ids", []):
		hero_names.append(_hero_display_name(str(hid)))
	_detail_body.add_child(_kv_block(
		"Heroes",
		", ".join(hero_names) if not hero_names.is_empty() else "None"
	))

	if int(march.get("cargo_capacity", 0)) > 0:
		_detail_body.add_child(_kv_block("Cargo", _format_number(int(march.get("cargo_capacity", 0)))))


func _populate_battle_detail(msg: Dictionary) -> void:
	var victory: bool = bool(msg.get("result", {}).get("victory", false))
	var result_l := Label.new()
	result_l.text = "Victory" if victory else "Defeat"
	result_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_l.add_theme_font_size_override("font_size", 28)
	result_l.add_theme_color_override("font_color", COL_OK if victory else COL_WARN)
	_detail_body.add_child(result_l)

	var target: Dictionary = msg.get("target", {})
	_detail_body.add_child(_kv_block("Target", "%s\nLv.%d" % [
		str(target.get("display_name", "Wildling")),
		int(target.get("level", 1)),
	]))

	var march: Dictionary = msg.get("march", {})
	_detail_body.add_child(_kv_block("March Power", _format_number(int(march.get("march_power", 0)))))

	var hero_names: PackedStringArray = PackedStringArray()
	for hid: Variant in march.get("hero_ids", []):
		hero_names.append(_hero_display_name(str(hid)))
	_detail_body.add_child(_kv_block(
		"Heroes",
		", ".join(hero_names) if not hero_names.is_empty() else "None"
	))

	_detail_body.add_child(_kv_block("Troops Sent", _troop_lines(march)))
	_detail_body.add_child(_kv_block("Losses", _troop_lines(msg.get("losses", {}))))
	_detail_body.add_child(_kv_block("Survivors", _troop_lines(msg.get("survivors", {}))))

	var rewards: Dictionary = msg.get("rewards", {})
	if victory and not rewards.is_empty():
		_detail_body.add_child(_kv_block("Rewards", _reward_lines(rewards)))
	elif victory:
		_detail_body.add_child(_kv_block("Rewards", "None listed"))
	else:
		_detail_body.add_child(_kv_block("Rewards", "None (defeat)"))


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
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.14, 0.20, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.26, 0.20, 0.28, 1.0), Color(1.0, 0.86, 0.42, 1.0)))
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
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


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


func _log_safe_area_after_layout() -> void:
	_apply_safe_area()
	var dbg: Dictionary = get_layout_debug()
	var header: Rect2 = dbg.get("header", Rect2())
	var close_r: Rect2 = dbg.get("close", Rect2())
	var win: Rect2 = dbg.get("window", Rect2())
	print("[MailScreen] after-layout header y=%.1f close y=%.1f..%.1f window y=%.1f..%.1f (720x1280 band)" % [
		header.position.y,
		close_r.position.y,
		close_r.position.y + close_r.size.y,
		win.position.y,
		win.position.y + win.size.y,
	])


## Debug helper used by UIManager smoke — returns global rects.
func get_layout_debug() -> Dictionary:
	var close_rect := Rect2()
	var window_rect := Rect2()
	var header_rect := Rect2()
	if _close_button != null:
		close_rect = _close_button.get_global_rect()
	if _window != null:
		window_rect = _window.get_global_rect()
	var header: Control = get_node_or_null("MailWindow/MailMargins/MailShell/MailHeader") as Control
	if header == null and _close_button != null:
		header = _close_button.get_parent() as Control
	if header != null:
		header_rect = header.get_global_rect()
	return {
		"top_inset": _top_inset,
		"bottom_inset": _bottom_inset,
		"window": window_rect,
		"header": header_rect,
		"close": close_rect,
		"viewport": get_viewport_rect().size,
	}


## X — close entire Mail via GameHUD UIManager; restore world + HUD Mail button.
func _close_mail() -> void:
	print("[MailScreen] Close/X pressed — closing via UIManager")
	_reset_to_inbox_state()
	var manager: Node = _find_ui_manager()
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		push_warning("[MailScreen] UIManager missing; forcing local on_close()")
		on_close()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_tree_mouse_ignore(self, true)
