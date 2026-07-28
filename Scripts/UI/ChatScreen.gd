extends Control

## Crownspire Chat UI — premium floating modal (Kingdom + Alliance only).
## UI/UX only. Uses existing ChatManager / AllianceBackend APIs unchanged.

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")
const ChatMessageScript = preload("res://scripts/Backend/ChatMessage.gd")

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.09, 0.07, 0.12, 0.97)
const COL_CARD := Color(0.13, 0.11, 0.17, 0.96)
const COL_CARD_SELF := Color(0.16, 0.14, 0.10, 0.97)
const COL_SYSTEM := Color(0.12, 0.14, 0.18, 0.92)
const COL_BORDER := Color(0.62, 0.50, 0.30, 0.95)
const COL_AVATAR := Color(0.28, 0.22, 0.34, 1.0)
const COL_FRAME := Color(0.82, 0.66, 0.28, 1.0)
const COL_INPUT := Color(0.07, 0.06, 0.09, 0.98)

const FALLBACK_TOP_INSET: float = 120.0
const FALLBACK_BOTTOM_INSET: float = 188.0
const LONG_PRESS_MS: int = 380

var _tab: String = "kingdom"
var _dim: ColorRect
var _window: PanelContainer
var _status_label: Label
var _messages_box: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit
var _send_btn: Button
var _kingdom_tab: Button
var _alliance_tab: Button
var _private_tab: Button
var _action_overlay: Control
var _action_box: VBoxContainer
var _emoji_overlay: Control
var _selected_message: RefCounted = null
var _built: bool = false
var _mobile_scroll
var _translations: Dictionary = {} ## message_id -> {ok, text/error}
var _press_msg: RefCounted = null
var _press_self: bool = false
var _press_msec: int = 0
var _press_pos: Vector2 = Vector2.ZERO
var _open_tab_hint: String = ""
var _pending_private_peer: String = ""
var _pending_private_name: String = ""
var _player_context_user_id: String = ""
var _player_context_name: String = ""


func _chat_manager() -> Node:
	return get_node_or_null("/root/ChatManager")


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_bind_chat_signals()


func on_open() -> void:
	_build_ui()
	if _open_tab_hint != "":
		_tab = _open_tab_hint
		_open_tab_hint = ""
	elif _pending_private_peer != "":
		_tab = "private"
	else:
		_tab = "kingdom"
	_close_actions()
	_close_emoji()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_window_position()
	_refresh_tabs()
	_refresh_status()
	_refresh_messages()
	if has_node("/root/ChatManager"):
		if _tab == "private" and _pending_private_peer != "":
			await _chat_manager().ensure_private_joined(_pending_private_peer, _pending_private_name)
			_pending_private_peer = ""
			_pending_private_name = ""
		else:
			await _chat_manager().ensure_kingdom_joined()
			if _tab == "alliance":
				await _chat_manager().ensure_alliance_joined()
		_refresh_status()
		_refresh_messages()
		_scroll_to_bottom()


func request_open_tab(tab_id: String) -> void:
	_open_tab_hint = tab_id


func request_open_private(user_id: String, display_name: String = "") -> void:
	_pending_private_peer = user_id.strip_edges()
	_pending_private_name = display_name.strip_edges()
	_open_tab_hint = "private"


func _open_active_channel() -> void:
	if not has_node("/root/ChatManager"):
		return
	if _tab == "alliance":
		await _chat_manager().ensure_alliance_joined()
	elif _tab == "private":
		var peer: String = _chat_manager().get_active_dm_peer()
		if peer == "" and _pending_private_peer != "":
			peer = _pending_private_peer
		if peer != "":
			await _chat_manager().ensure_private_joined(peer, _pending_private_name)
	else:
		await _chat_manager().ensure_kingdom_joined()
	_refresh_status()
	_refresh_messages()
	_scroll_to_bottom()


func on_close() -> void:
	_close_actions()
	_close_emoji()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _bind_chat_signals() -> void:
	if not has_node("/root/ChatManager"):
		return
	var cm: Node = _chat_manager()
	if not cm.message_received.is_connected(_on_message_event):
		cm.message_received.connect(_on_message_event)
	if not cm.message_sent.is_connected(_on_message_event):
		cm.message_sent.connect(_on_message_event)
	if not cm.messages_loaded.is_connected(_on_messages_loaded):
		cm.messages_loaded.connect(_on_messages_loaded)
	if not cm.availability_changed.is_connected(_on_availability):
		cm.availability_changed.connect(_on_availability)
	if not cm.send_failed.is_connected(_on_send_failed):
		cm.send_failed.connect(_on_send_failed)
	if not cm.kingdom_join_failed.is_connected(_on_join_failed):
		cm.kingdom_join_failed.connect(_on_join_failed)
	if not cm.alliance_join_failed.is_connected(_on_alliance_join_failed):
		cm.alliance_join_failed.connect(_on_alliance_join_failed)
	if not cm.alliance_joined.is_connected(_on_alliance_joined):
		cm.alliance_joined.connect(_on_alliance_joined)


func _on_message_event(_msg: RefCounted) -> void:
	if not visible:
		return
	_refresh_messages()
	_scroll_to_bottom()


func _on_messages_loaded(kind: String) -> void:
	if not visible:
		return
	if kind == "alliance" and _tab != "alliance":
		return
	if kind == "kingdom" and _tab != "kingdom":
		return
	if kind == "private" and _tab != "private":
		_refresh_tabs()
		return
	_refresh_messages()


func _on_availability(_available: bool) -> void:
	if visible:
		_refresh_status()


func _on_send_failed(reason: String) -> void:
	_status_label.text = str(reason)


func _on_join_failed(reason: String) -> void:
	if _tab == "kingdom":
		_status_label.text = "Chat unavailable: %s" % reason


func _on_alliance_join_failed(reason: String) -> void:
	if _tab == "alliance":
		_status_label.text = str(reason)
		_refresh_status()
		_refresh_messages()


func _on_alliance_joined(_channel_id: String) -> void:
	if visible and _tab == "alliance":
		_refresh_status()
		_refresh_messages()
		_scroll_to_bottom()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_window_position()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	for child in get_children():
		child.queue_free()

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.04, 0.03, 0.06, 0.48)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.offset_bottom = -FALLBACK_BOTTOM_INSET
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_close_pressed()
		elif e is InputEventScreenTouch and e.pressed:
			_on_close_pressed()
	)
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "ChatWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_window.add_theme_stylebox_override("panel", style)
	add_child(_window)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_window.add_child(root)

	# Header
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "CHAT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(48, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	_style_icon_button(close_btn)
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	# Tabs — Kingdom / Alliance / Private (when open)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	_kingdom_tab = _make_tab_button("KINGDOM")
	_alliance_tab = _make_tab_button("ALLIANCE")
	_private_tab = _make_tab_button("PRIVATE")
	_kingdom_tab.pressed.connect(func(): _set_tab("kingdom"))
	_alliance_tab.pressed.connect(func(): _set_tab("alliance"))
	_private_tab.pressed.connect(func(): _set_tab("private"))
	tabs.add_child(_kingdom_tab)
	tabs.add_child(_alliance_tab)
	tabs.add_child(_private_tab)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_mobile_scroll = MobileScrollUtil.ensure(self, _scroll, "ChatMobileScroll")

	_messages_box = VBoxContainer.new()
	_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_messages_box)

	# Composer toolbar + input
	root.add_child(_build_composer())

	_build_action_overlay()
	_build_emoji_overlay()
	_apply_window_position()


func _build_composer() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	wrap.add_child(tools)

	var emoji_btn := _make_tool_button("😀", "Emoji")
	emoji_btn.pressed.connect(_open_emoji_placeholder)
	tools.add_child(emoji_btn)

	var loc_btn := _make_tool_button("📍", "Share location")
	loc_btn.pressed.connect(_on_share_location)
	tools.add_child(loc_btn)

	var rally_btn := _make_tool_button("⚔", "Share rally")
	rally_btn.pressed.connect(_on_share_rally)
	tools.add_child(rally_btn)

	var more_btn := _make_tool_button("➕", "Attachments coming soon")
	more_btn.disabled = true
	more_btn.tooltip_text = "Attachments coming soon"
	tools.add_child(more_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)

	_input = LineEdit.new()
	_input.placeholder_text = "Write a message…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 52)
	_input.max_length = ChatMessageScript.MAX_TEXT_LENGTH
	_input.text_submitted.connect(func(_t): _on_send_pressed())
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = COL_INPUT
	input_style.border_color = COL_BORDER
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(10)
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	_input.add_theme_stylebox_override("normal", input_style)
	_input.add_theme_color_override("font_color", COL_INK)
	_input.add_theme_color_override("font_placeholder_color", COL_MUTED)
	row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "SEND"
	_send_btn.custom_minimum_size = Vector2(96, 52)
	_send_btn.focus_mode = Control.FOCUS_NONE
	_style_primary_button(_send_btn)
	_send_btn.pressed.connect(_on_send_pressed)
	row.add_child(_send_btn)

	return wrap


func _make_tool_button(icon_text: String, tip: String) -> Button:
	var btn := Button.new()
	btn.text = icon_text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(52, 48)
	_style_icon_button(btn)
	return btn


func _style_icon_button(btn: Button) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.14, 0.12, 0.18, 1.0)
	fill.border_color = COL_BORDER
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", fill)
	btn.add_theme_stylebox_override("pressed", fill)
	btn.add_theme_stylebox_override("hover", fill)
	btn.add_theme_stylebox_override("disabled", fill)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", COL_INK)


func _style_primary_button(btn: Button) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.28, 0.22, 0.12, 1.0)
	fill.border_color = COL_GOLD
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", fill)
	btn.add_theme_stylebox_override("pressed", fill)
	btn.add_theme_stylebox_override("hover", fill)
	btn.add_theme_stylebox_override("disabled", fill)
	btn.add_theme_color_override("font_color", COL_GOLD)
	btn.add_theme_font_size_override("font_size", 15)


func _build_action_overlay() -> void:
	_action_overlay = Control.new()
	_action_overlay.visible = false
	_action_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_action_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_action_overlay)
	var action_dim := ColorRect.new()
	action_dim.color = Color(0, 0, 0, 0.5)
	action_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_actions()
		elif e is InputEventScreenTouch and e.pressed:
			_close_actions()
	)
	_action_overlay.add_child(action_dim)
	var action_panel := PanelContainer.new()
	action_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_panel.anchor_left = 0.08
	action_panel.anchor_right = 0.92
	action_panel.offset_bottom = -220.0
	action_panel.offset_top = -520.0
	var ap_style := StyleBoxFlat.new()
	ap_style.bg_color = COL_CARD
	ap_style.border_color = COL_GOLD
	ap_style.set_border_width_all(2)
	ap_style.set_corner_radius_all(14)
	ap_style.content_margin_left = 14
	ap_style.content_margin_right = 14
	ap_style.content_margin_top = 14
	ap_style.content_margin_bottom = 14
	action_panel.add_theme_stylebox_override("panel", ap_style)
	_action_overlay.add_child(action_panel)
	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 8)
	action_panel.add_child(_action_box)


func _build_emoji_overlay() -> void:
	_emoji_overlay = Control.new()
	_emoji_overlay.visible = false
	_emoji_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emoji_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_emoji_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_emoji()
		elif e is InputEventScreenTouch and e.pressed:
			_close_emoji()
	)
	_emoji_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 180)
	var st := StyleBoxFlat.new()
	st.bg_color = COL_CARD
	st.border_color = COL_BORDER
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", st)
	_emoji_overlay.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var t := Label.new()
	t.text = "Emoji Picker"
	t.add_theme_color_override("font_color", COL_GOLD)
	t.add_theme_font_size_override("font_size", 20)
	col.add_child(t)
	var body := Label.new()
	body.text = "Emoji support is coming soon.\nThis button is ready for the full picker."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 48)
	close.focus_mode = Control.FOCUS_NONE
	_style_primary_button(close)
	close.pressed.connect(_close_emoji)
	col.add_child(close)


func _make_tab_button(text_value: String) -> Button:
	var btn := Button.new()
	btn.text = text_value
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(140, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn


func _apply_window_position() -> void:
	if _window == null:
		return
	var top: float = FALLBACK_TOP_INSET
	var bottom: float = FALLBACK_BOTTOM_INSET
	var avail_h: float = maxf(360.0, size.y - top - bottom)
	var h: float = clampf(size.y * 0.72, 420.0, avail_h)
	var w: float = minf(size.x - 28.0, 680.0)
	_window.custom_minimum_size = Vector2(w, h)
	_window.size = Vector2(w, h)
	_window.position = Vector2((size.x - w) * 0.5, top + (avail_h - h) * 0.35)
	if _dim != null:
		_dim.offset_bottom = -bottom


func _set_tab(tab_id: String) -> void:
	_tab = tab_id
	_close_actions()
	_close_emoji()
	_refresh_tabs()
	_refresh_status()
	_refresh_messages()
	_open_active_channel()
	if _tab == "alliance":
		_input.placeholder_text = "Message alliance…"
	elif _tab == "private":
		_input.placeholder_text = "Private message…"
	else:
		_input.placeholder_text = "Message kingdom…"


func _refresh_tabs() -> void:
	_style_tab(_kingdom_tab, _tab == "kingdom")
	_style_tab(_alliance_tab, _tab == "alliance")
	_style_tab(_private_tab, _tab == "private")
	if _private_tab != null:
		var peer: String = ""
		if has_node("/root/ChatManager"):
			peer = _chat_manager().get_active_dm_peer()
		if peer == "" and _pending_private_peer != "":
			peer = _pending_private_peer
		_private_tab.visible = peer != "" or _tab == "private"
		if peer != "" and has_node("/root/ChatManager"):
			var unread: int = int(_chat_manager().get_dm_unread_total())
			var label: String = "PRIVATE"
			if unread > 0 and _tab != "private":
				label = "PRIVATE (%d)" % unread
			_private_tab.text = label


func _style_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.24, 0.19, 0.12, 1.0) if active else Color(0.11, 0.09, 0.13, 1.0)
	fill.border_color = COL_GOLD if active else COL_BORDER
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", fill)
	btn.add_theme_stylebox_override("pressed", fill)
	btn.add_theme_stylebox_override("hover", fill)
	btn.add_theme_color_override("font_color", COL_INK if active else COL_MUTED)
	btn.add_theme_font_size_override("font_size", 15)


func _refresh_status() -> void:
	if _status_label == null:
		return
	if _tab == "private":
		if not has_node("/root/ChatManager") or not _chat_manager().is_chat_available():
			_status_label.text = "Private chat unavailable — reconnect to Nakama."
			_input.editable = false
			_send_btn.disabled = true
			return
		var peer: String = _chat_manager().get_active_dm_peer()
		var pname: String = _chat_manager().get_dm_display_name(peer) if peer != "" else "Player"
		_status_label.text = "Private · %s" % pname
		_input.editable = peer != ""
		_send_btn.disabled = peer == ""
		return
	if _tab == "alliance":
		if not has_node("/root/ChatManager") or not _chat_manager().is_alliance_chat_available():
			_status_label.text = _chat_manager().get_alliance_chat_unavailable_reason() if has_node("/root/ChatManager") else "You are not currently in an Alliance."
			_input.editable = false
			_send_btn.disabled = true
			return
		var tag: String = _alliance_backend().get_alliance_tag() if has_node("/root/AllianceBackend") else ""
		var aname: String = _alliance_backend().get_alliance_name() if has_node("/root/AllianceBackend") else ""
		var joined_a: bool = _chat_manager().is_alliance_joined()
		_status_label.text = "[%s] %s%s" % [
			tag if tag != "" else "???",
			aname if aname != "" else "Alliance",
			" • connected" if joined_a else " • joining…",
		]
		_input.editable = joined_a
		_send_btn.disabled = not joined_a
		return

	if not has_node("/root/ChatManager") or not _chat_manager().is_chat_available():
		_status_label.text = "Disconnected — Kingdom Chat unavailable. Local gameplay still works."
		_input.editable = false
		_send_btn.disabled = true
		return

	var kid: String = _chat_manager().get_kingdom_id()
	var joined: bool = _chat_manager().is_kingdom_joined()
	_status_label.text = "Kingdom %s%s" % [kid, " • connected" if joined else " • joining…"]
	_input.editable = joined
	_send_btn.disabled = not joined


func _refresh_messages() -> void:
	if _messages_box == null:
		return
	for child in _messages_box.get_children():
		child.queue_free()

	if not has_node("/root/ChatManager"):
		return

	if _tab == "alliance" and not _chat_manager().is_alliance_chat_available():
		var locked := Label.new()
		locked.text = _chat_manager().get_alliance_chat_unavailable_reason()
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked.add_theme_color_override("font_color", COL_MUTED)
		locked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_messages_box.add_child(locked)
		return

	if _tab == "private" and _chat_manager().get_active_dm_peer() == "":
		var no_dm := Label.new()
		no_dm.text = "Select Message from a player to start a private conversation."
		no_dm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_dm.add_theme_color_override("font_color", COL_MUTED)
		no_dm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_messages_box.add_child(no_dm)
		return

	var has_more: bool = false
	if _tab == "alliance":
		has_more = _chat_manager().get_alliance_history_has_more()
	elif _tab != "private":
		has_more = _chat_manager().get_history_has_more()
	if has_more:
		var older := Button.new()
		older.text = "Load older messages"
		older.focus_mode = Control.FOCUS_NONE
		older.custom_minimum_size = Vector2(0, 44)
		_style_icon_button(older)
		older.pressed.connect(_on_load_older)
		_messages_box.add_child(older)

	var local_id: String = _chat_manager().get_local_user_id()
	var msgs: Array[RefCounted]
	if _tab == "alliance":
		msgs = _chat_manager().get_alliance_messages()
	elif _tab == "private":
		msgs = _chat_manager().get_private_messages()
	else:
		msgs = _chat_manager().get_messages()
	if msgs.is_empty():
		var empty := Label.new()
		empty.text = "No messages yet."
		empty.add_theme_color_override("font_color", COL_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_messages_box.add_child(empty)
		return

	for msg in msgs:
		_messages_box.add_child(_build_message_row(msg, local_id))


func _build_message_row(msg: RefCounted, local_id: String) -> Control:
	var is_system: bool = str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM
	var is_self: bool = (not is_system) and str(msg.sender_user_id) == local_id and local_id != ""

	if is_system:
		return _build_system_row(msg)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD_SELF if is_self else COL_CARD
	style.border_color = COL_GOLD if is_self else COL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_long_press(panel, msg, is_self)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	row.add_child(_build_avatar(msg, is_self))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(header)

	var tag: String = str(msg.sender_alliance_tag).strip_edges()
	var name_text: String = str(msg.sender_display_name).strip_edges()
	if name_text == "":
		name_text = "Player"
	var name_lbl := Label.new()
	if tag != "":
		name_lbl.text = "[%s] %s" % [tag, name_text]
	else:
		name_lbl.text = name_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", COL_GOLD if is_self else COL_INK)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	if not is_self:
		name_lbl.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_open_player_context(str(msg.sender_user_id), name_text)
			elif e is InputEventScreenTouch and e.pressed:
				_open_player_context(str(msg.sender_user_id), name_text)
		)
	header.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.text = str(msg.format_timestamp_local())
	time_lbl.add_theme_color_override("font_color", COL_MUTED)
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(time_lbl)

	match str(msg.message_type):
		ChatMessageScript.TYPE_MAP_LOCATION:
			col.add_child(_build_map_card(msg))
		ChatMessageScript.TYPE_RALLY:
			col.add_child(_build_rally_card(msg))
		_:
			var body := Label.new()
			body.text = str(msg.text)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_color_override("font_color", COL_INK)
			body.add_theme_font_size_override("font_size", 16)
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(body)

	var mid: String = str(msg.message_id)
	if _translations.has(mid):
		col.add_child(_build_translation_block(_translations[mid]))

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	col.add_child(tools)
	var tr_btn := Button.new()
	tr_btn.text = "Translate"
	tr_btn.focus_mode = Control.FOCUS_NONE
	tr_btn.custom_minimum_size = Vector2(96, 34)
	tr_btn.add_theme_font_size_override("font_size", 12)
	_style_icon_button(tr_btn)
	tr_btn.pressed.connect(func(): _apply_translate(msg))
	tools.add_child(tr_btn)

	return panel


func _build_system_row(msg: RefCounted) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_SYSTEM
	style.border_color = Color(0.40, 0.48, 0.58, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var sys := Label.new()
	sys.text = "◆ SYSTEM  %s" % str(msg.format_timestamp_local())
	sys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sys.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90, 1.0))
	sys.add_theme_font_size_override("font_size", 11)
	col.add_child(sys)
	var body := Label.new()
	body.text = str(msg.text)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", COL_MUTED)
	body.add_theme_font_size_override("font_size", 14)
	col.add_child(body)
	return panel


func _build_avatar(msg: RefCounted, is_self: bool) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(44, 44)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = COL_FRAME if is_self else COL_BORDER
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(22)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(frame)

	var face := Panel.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 3
	face.offset_top = 3
	face.offset_right = -3
	face.offset_bottom = -3
	var face_style := StyleBoxFlat.new()
	face_style.bg_color = COL_AVATAR
	face_style.set_corner_radius_all(20)
	face.add_theme_stylebox_override("panel", face_style)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(face)

	var initials := Label.new()
	initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.text = _initials_for(str(msg.sender_display_name))
	initials.add_theme_font_size_override("font_size", 14)
	initials.add_theme_color_override("font_color", COL_INK)
	initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(initials)
	return wrap


func _initials_for(name_text: String) -> String:
	var cleaned: String = name_text.strip_edges()
	if cleaned == "":
		return "?"
	var parts: PackedStringArray = cleaned.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	return cleaned.substr(0, mini(2, cleaned.length())).to_upper()


func _wire_long_press(control: Control, msg: RefCounted, is_self: bool) -> void:
	control.gui_input.connect(func(event: InputEvent):
		if str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_press_msg = msg
				_press_self = is_self
				_press_msec = Time.get_ticks_msec()
				_press_pos = mb.position
			else:
				_finish_press(mb.position)
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_press_msg = msg
				_press_self = is_self
				_press_msec = Time.get_ticks_msec()
				_press_pos = st.position
			else:
				_finish_press(st.position)
	)


func _finish_press(release_pos: Vector2) -> void:
	if _press_msg == null:
		return
	var held: int = Time.get_ticks_msec() - _press_msec
	var moved: float = release_pos.distance_to(_press_pos)
	var msg: RefCounted = _press_msg
	var is_self: bool = _press_self
	_press_msg = null
	if moved > 18.0:
		return
	if held >= LONG_PRESS_MS:
		_open_actions(msg, is_self)


func _build_map_card(msg: RefCounted) -> Control:
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.12, 0.16, 0.95)
	st.border_color = Color(0.45, 0.55, 0.70, 0.85)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var payload: Dictionary = msg.payload if typeof(msg.payload) == TYPE_DICTIONARY else {}
	var title := Label.new()
	title.text = "📍 %s" % str(payload.get("label", "Location"))
	title.add_theme_color_override("font_color", COL_INK)
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var coords := Label.new()
	coords.text = "X:%.0f  Y:%.0f" % [float(payload.get("x", 0.0)), float(payload.get("y", 0.0))]
	coords.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(coords)
	var view := Button.new()
	view.text = "VIEW"
	view.focus_mode = Control.FOCUS_NONE
	view.custom_minimum_size = Vector2(120, 44)
	_style_primary_button(view)
	view.pressed.connect(func():
		if has_node("/root/ChatManager"):
			var result: Dictionary = _chat_manager().navigate_to_map_location(payload)
			_status_label.text = "Location opened." if bool(result.get("navigated", false)) else str(result.get("note", "Location ready."))
	)
	box.add_child(view)
	return card


func _build_rally_card(msg: RefCounted) -> Control:
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.11, 0.10, 0.96)
	st.border_color = COL_GOLD
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var payload: Dictionary = msg.payload if typeof(msg.payload) == TYPE_DICTIONARY else {}
	var title := Label.new()
	title.text = "⚔ RALLY"
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	var target := Label.new()
	target.text = str(payload.get("target_name", "Rally Target"))
	target.add_theme_color_override("font_color", COL_INK)
	target.add_theme_font_size_override("font_size", 16)
	box.add_child(target)
	var leader := Label.new()
	leader.text = "Leader: %s" % str(msg.sender_display_name)
	leader.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(leader)
	var remain := Label.new()
	remain.text = _format_rally_remaining(payload)
	remain.add_theme_color_override("font_color", COL_WARN)
	remain.add_theme_font_size_override("font_size", 13)
	box.add_child(remain)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var view := Button.new()
	view.text = "VIEW"
	view.focus_mode = Control.FOCUS_NONE
	view.custom_minimum_size = Vector2(100, 44)
	_style_primary_button(view)
	view.pressed.connect(func():
		if has_node("/root/ChatManager"):
			_chat_manager().navigate_to_map_location({
				"kingdom_id": payload.get("kingdom_id", _chat_manager().get_kingdom_id()),
				"x": payload.get("x", 0.0),
				"y": payload.get("y", 0.0),
				"label": payload.get("target_name", "Rally"),
				"target_type": payload.get("target_type", "rally"),
				"target_id": payload.get("target_id", ""),
			})
	)
	row.add_child(view)
	var join := Button.new()
	join.text = "JOIN"
	join.disabled = true
	join.focus_mode = Control.FOCUS_NONE
	join.custom_minimum_size = Vector2(100, 44)
	join.tooltip_text = "Server-authoritative rallies are not connected yet."
	_style_icon_button(join)
	row.add_child(join)
	return card


func _format_rally_remaining(payload: Dictionary) -> String:
	var expiry: int = int(payload.get("expiry_unix", 0))
	if expiry <= 0:
		return "Time remaining unavailable"
	var now: int = int(Time.get_unix_time_from_system())
	var left: int = maxi(0, expiry - now)
	var mins: int = left / 60
	var secs: int = left % 60
	return "%02d:%02d Remaining" % [mins, secs]


func _build_translation_block(data: Dictionary) -> Control:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	if bool(data.get("ok", false)):
		lbl.text = str(data.get("text", ""))
		lbl.add_theme_color_override("font_color", COL_OK)
	else:
		lbl.text = str(data.get("error", "Translation service not configured."))
		lbl.add_theme_color_override("font_color", COL_WARN)
	return lbl


func _apply_translate(msg: RefCounted) -> void:
	if not has_node("/root/ChatManager") or msg == null:
		return
	var result: Dictionary = _chat_manager().request_translate(msg)
	var mid: String = str(msg.message_id)
	if mid == "":
		mid = str(msg.timestamp_unix) + "|" + str(msg.sender_user_id)
	if bool(result.get("ok", false)):
		_translations[mid] = {"ok": true, "text": str(result.get("translated_text", result.get("text", "")))}
		if str(_translations[mid]["text"]).strip_edges() == "":
			_translations[mid] = {"ok": false, "error": "Translation service not configured."}
	else:
		_translations[mid] = {
			"ok": false,
			"error": str(result.get("error", "Translation service not configured.")),
		}
	_refresh_messages()


func _open_actions(msg: RefCounted, is_self: bool) -> void:
	_selected_message = msg
	for child in _action_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Message Actions"
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 18)
	_action_box.add_child(title)

	_add_action("View Profile", func():
		_show_player_profile(msg)
		_close_actions()
	)
	_add_action("Translate", func():
		_apply_translate(msg)
		_close_actions()
	)
	if not is_self:
		_add_action("Message", func():
			_start_private_with(str(msg.sender_user_id), str(msg.sender_display_name))
			_close_actions()
		)
		_add_action("Mute", func():
			_chat_manager().mute_user(str(msg.sender_user_id))
			_status_label.text = "Player muted in chat."
			_close_actions()
			_refresh_messages()
		)
		_add_action("Block", func():
			_chat_manager().block_user(str(msg.sender_user_id))
			_status_label.text = "Player blocked in chat."
			_close_actions()
			_refresh_messages()
		)
		_add_action("Report", func():
			_open_report_reasons(msg)
		)
	_add_action("Cancel", func(): _close_actions())
	_action_overlay.visible = true


func _open_player_context(user_id: String, display_name: String) -> void:
	_player_context_user_id = user_id.strip_edges()
	_player_context_name = display_name.strip_edges()
	if _player_context_user_id == "":
		return
	for child in _action_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = _player_context_name if _player_context_name != "" else "Player"
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 18)
	_action_box.add_child(title)
	_add_action("View Profile", func():
		_open_external_profile(_player_context_user_id)
		_close_actions()
	)
	_add_action("Message", func():
		_start_private_with(_player_context_user_id, _player_context_name)
		_close_actions()
	)
	_add_action("Block", func():
		_chat_manager().block_user(_player_context_user_id)
		_status_label.text = "Player blocked (local filter)."
		_close_actions()
	)
	_add_action("Report", func():
		_status_label.text = "Report stub — use long-press Report on a message."
		_close_actions()
	)
	_add_action("Cancel", func(): _close_actions())
	_action_overlay.visible = true


func _start_private_with(user_id: String, display_name: String) -> void:
	_pending_private_peer = user_id.strip_edges()
	_pending_private_name = display_name.strip_edges()
	_tab = "private"
	_refresh_tabs()
	await _chat_manager().ensure_private_joined(_pending_private_peer, _pending_private_name)
	_pending_private_peer = ""
	_pending_private_name = ""
	_refresh_status()
	_refresh_messages()
	_scroll_to_bottom()


func _open_external_profile(user_id: String) -> void:
	var hud := get_tree().get_first_node_in_group("game_hud")
	if hud == null:
		# Fallback: climb to GameHUD
		var n: Node = self
		while n != null:
			if n.has_method("open_player_profile"):
				hud = n
				break
			n = n.get_parent()
	if hud != null and hud.has_method("open_player_profile"):
		hud.open_player_profile(user_id)
	elif has_node("/root/AllianceBackend"):
		_status_label.text = "Opening profile…"
		var res: Dictionary = await _alliance_backend().get_public_profile(user_id)
		if bool(res.get("ok", false)):
			var p: Dictionary = res.get("profile", {})
			_status_label.text = "%s · Power %s · Citadel %s" % [
				str(p.get("display_name", "?")),
				str(p.get("power", 0)),
				str(p.get("citadel_level", 1)),
			]


func _add_action(label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 52)
	_style_icon_button(btn)
	btn.pressed.connect(cb)
	_action_box.add_child(btn)


func _close_actions() -> void:
	_selected_message = null
	if _action_overlay != null:
		_action_overlay.visible = false


func _open_emoji_placeholder() -> void:
	_close_actions()
	if _emoji_overlay != null:
		_emoji_overlay.visible = true


func _close_emoji() -> void:
	if _emoji_overlay != null:
		_emoji_overlay.visible = false


func _on_share_location() -> void:
	if not has_node("/root/ChatManager"):
		return
	if not _can_compose():
		return
	var cm: Node = _chat_manager()
	var kid: String = cm.get_kingdom_id()
	var payload := {
		"kingdom_id": kid,
		"x": 428.0,
		"y": 719.0,
		"label": "Shared Location",
		"target_type": "coord",
		"target_id": "",
	}
	var kind: String = "alliance" if _tab == "alliance" else "kingdom"
	var result: Dictionary = await cm.send_map_location(payload, kind)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Share location failed."))
	else:
		_refresh_messages()
		_scroll_to_bottom()


func _on_share_rally() -> void:
	if not has_node("/root/ChatManager"):
		return
	if not _can_compose():
		return
	var cm: Node = _chat_manager()
	var payload := {
		"rally_id": "ui_preview",
		"leader_user_id": cm.get_local_user_id(),
		"target_id": "",
		"target_type": "wildling",
		"target_name": "Wildling Lair Lv.20",
		"kingdom_id": cm.get_kingdom_id(),
		"x": 428.0,
		"y": 719.0,
		"expiry_unix": int(Time.get_unix_time_from_system()) + 204,
	}
	var kind: String = "alliance" if _tab == "alliance" else "kingdom"
	var result: Dictionary = await cm.send_rally_preview(payload, kind)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Share rally failed."))
	else:
		_refresh_messages()
		_scroll_to_bottom()


func _can_compose() -> bool:
	if _tab == "alliance":
		return has_node("/root/ChatManager") and _chat_manager().is_alliance_chat_available() and _chat_manager().is_alliance_joined()
	if _tab == "private":
		return has_node("/root/ChatManager") and _chat_manager().is_chat_available() and _chat_manager().get_active_dm_peer() != ""
	return has_node("/root/ChatManager") and _chat_manager().is_chat_available() and _chat_manager().is_kingdom_joined()


func _on_send_pressed() -> void:
	if not has_node("/root/ChatManager"):
		return
	if _tab == "alliance" and not _chat_manager().is_alliance_chat_available():
		return
	if _tab == "private" and _chat_manager().get_active_dm_peer() == "":
		return
	var text_value: String = _input.text
	_input.text = ""
	var kind: String = "kingdom"
	if _tab == "alliance":
		kind = "alliance"
	elif _tab == "private":
		kind = "private"
	var result: Dictionary = await _chat_manager().send_text_message(text_value, kind)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Send failed."))
	else:
		_refresh_status()
		_refresh_messages()
		_scroll_to_bottom()


func _on_load_older() -> void:
	if has_node("/root/ChatManager"):
		if _tab == "alliance":
			await _chat_manager().load_alliance_history(false)
		else:
			await _chat_manager().load_kingdom_history(false)
		_refresh_messages()


func _open_report_reasons(msg: RefCounted) -> void:
	for child in _action_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Report reason"
	title.add_theme_color_override("font_color", COL_GOLD)
	_action_box.add_child(title)
	var reasons: Array = []
	if has_node("/root/AllianceBackend"):
		reasons = _alliance_backend().REPORT_REASONS.duplicate()
	else:
		reasons = ["spam", "harassment", "other"]
	for reason in reasons:
		var r: String = str(reason)
		_add_action(r.replace("_", " ").capitalize(), func():
			var result: Dictionary = await _chat_manager().submit_report(msg, r)
			if bool(result.get("ok", false)):
				_status_label.text = "Report submitted (evidence only — no automatic punishment)."
			else:
				_status_label.text = str(result.get("error", "Report failed."))
			_close_actions()
		)
	_add_action("Cancel", func(): _close_actions())


func _show_player_profile(msg: RefCounted) -> void:
	if not has_node("/root/AllianceBackend"):
		_status_label.text = "Profile backend unavailable."
		return
	var result: Dictionary = await _alliance_backend().get_public_profile(str(msg.sender_user_id))
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Profile lookup failed."))
		return
	var p: Dictionary = result.get("profile", {})
	var tag: String = str(p.get("alliance_tag", "")).strip_edges()
	var aname: String = str(p.get("alliance_name", "")).strip_edges()
	var lines: PackedStringArray = PackedStringArray([
		"Name: %s" % str(p.get("display_name", "?")),
		"Alliance: %s%s" % [
			("[%s] " % tag) if tag != "" else "",
			aname if aname != "" else "(none)",
		],
	])
	_status_label.text = " · ".join(lines)


func _on_close_pressed() -> void:
	var manager := get_node_or_null("../../UIManager")
	if manager == null:
		var hud := get_tree().root.find_child("GameHUD", true, false)
		if hud != null:
			manager = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
