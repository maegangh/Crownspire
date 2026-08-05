extends Control

## Crownspire Chat UI — Kingdom / Alliance / Direct (private DMs + friends hub).
## Uses ChatManager + FriendsBackend. Private never mixes into Kingdom/Alliance.

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")
const ChatMessageScript = preload("res://scripts/Backend/ChatMessage.gd")
const ChatEmojiCatalogScript = preload("res://scripts/UI/ChatEmojiCatalog.gd")

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
const KEYBOARD_POLL_SEC: float = 0.08
const SCROLL_STICK_MARGIN_PX: float = 96.0
const EMOJI_CELL_SIZE: float = 46.0
const EMOJI_INLINE_SIZE: float = 22.0

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
var _dm_peer_bar: HBoxContainer
var _dm_peer_label: Label
var _dm_back_btn: Button
var _dm_hub_section: String = "conversations" ## conversations | friends | requests
var _composer_wrap: Control
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
var _keyboard_lift_px: float = 0.0
var _keyboard_poll_accum: float = 0.0
var _stick_to_bottom: bool = true
var _emoji_grid: GridContainer = null
var _emoji_panel: PanelContainer = null
var _emoji_grid_scroll: ScrollContainer = null
var _tool_emoji_btn: Button = null
var _tool_location_btn: Button = null
var _tool_rally_btn: Button = null
var _tool_more_btn: Button = null
var _chat_font: Font = null
var _emoji_preview_row: HBoxContainer = null
var _emoji_preview_flow: HFlowContainer = null
var _emoji_preview_hint: Label = null


func _chat_manager() -> Node:
	return get_node_or_null("/root/ChatManager")


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _friends_backend() -> Node:
	return get_node_or_null("/root/FriendsBackend")


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
	_keyboard_lift_px = 0.0
	_stick_to_bottom = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_apply_window_position()
	_refresh_tabs()
	_refresh_status()
	_refresh_messages()
	print("[ChatScreen] opened tab=%s" % _tab)
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
		_scroll_to_bottom(true)


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
	_keyboard_lift_px = 0.0
	if _input != null and _input.has_focus():
		_input.release_focus()
	DisplayServer.virtual_keyboard_hide()
	set_process(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_window_position()


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
	if cm.has_signal("dm_conversations_changed") and not cm.dm_conversations_changed.is_connected(_on_dm_hub_changed):
		cm.dm_conversations_changed.connect(_on_dm_hub_changed)
	if cm.has_signal("dm_unread_changed") and not cm.dm_unread_changed.is_connected(_on_dm_unread_ui):
		cm.dm_unread_changed.connect(_on_dm_unread_ui)
	var fb_bind: Node = _friends_backend()
	if fb_bind != null:
		if fb_bind.has_signal("friends_changed") and not fb_bind.friends_changed.is_connected(_on_dm_hub_changed):
			fb_bind.friends_changed.connect(_on_dm_hub_changed)
	if not cm.alliance_joined.is_connected(_on_alliance_joined):
		cm.alliance_joined.connect(_on_alliance_joined)
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_signal("connection_state_changed"):
		if not nc.connection_state_changed.is_connected(_on_conn_state_changed):
			nc.connection_state_changed.connect(_on_conn_state_changed)
	if nc != null and nc.has_signal("socket_connected"):
		if not nc.socket_connected.is_connected(_on_socket_reconnected):
			nc.socket_connected.connect(_on_socket_reconnected)


func _on_conn_state_changed(_state: String) -> void:
	if visible:
		_refresh_status()


func _on_socket_reconnected() -> void:
	if not visible:
		return
	_refresh_status()
	_open_active_channel()


func _on_message_event(_msg: RefCounted) -> void:
	if not visible:
		return
	_refresh_messages()
	_scroll_to_bottom(false)


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
	_scroll_to_bottom(true)


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
		if _emoji_overlay != null and _emoji_overlay.visible:
			_fit_emoji_panel()
		if visible and _stick_to_bottom:
			_scroll_to_bottom(false)


func _process(delta: float) -> void:
	if not visible:
		return
	_keyboard_poll_accum += delta
	if _keyboard_poll_accum < KEYBOARD_POLL_SEC:
		return
	_keyboard_poll_accum = 0.0
	_update_keyboard_lift()


func _update_keyboard_lift() -> void:
	var focused: bool = _input != null and _input.has_focus()
	var kb_h: float = 0.0
	if focused:
		kb_h = float(DisplayServer.virtual_keyboard_get_height())
		## Some Android builds report 0 until Soft Input Mode resizes the viewport;
		## use a viewport shrink heuristic as fallback.
		if kb_h <= 1.0:
			var shrink: float = maxf(0.0, get_viewport().get_visible_rect().size.y - size.y)
			if shrink > 80.0:
				kb_h = shrink
	var next_lift: float = 0.0
	if kb_h > 40.0:
		## Lift enough to clear the keyboard while keeping the panel above the nav bar when closed.
		next_lift = maxf(0.0, kb_h - FALLBACK_BOTTOM_INSET + 12.0)
	if absf(next_lift - _keyboard_lift_px) > 1.0:
		_keyboard_lift_px = next_lift
		_apply_window_position()
		if _stick_to_bottom:
			_scroll_to_bottom(false)


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
	_private_tab = _make_tab_button("DIRECT")
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

	_dm_peer_bar = HBoxContainer.new()
	_dm_peer_bar.visible = false
	_dm_peer_bar.add_theme_constant_override("separation", 8)
	root.add_child(_dm_peer_bar)
	_dm_back_btn = Button.new()
	_dm_back_btn.text = "← Inbox"
	_dm_back_btn.focus_mode = Control.FOCUS_NONE
	_dm_back_btn.custom_minimum_size = Vector2(110, 40)
	_style_icon_button(_dm_back_btn)
	_dm_back_btn.pressed.connect(_on_dm_back_pressed)
	_dm_peer_bar.add_child(_dm_back_btn)
	_dm_peer_label = Label.new()
	_dm_peer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dm_peer_label.add_theme_color_override("font_color", COL_GOLD)
	_dm_peer_label.add_theme_font_size_override("font_size", 16)
	_dm_peer_bar.add_child(_dm_peer_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_mobile_scroll = MobileScrollUtil.ensure(self, _scroll, "ChatMobileScroll")
	var vbar: ScrollBar = _scroll.get_v_scroll_bar()
	if vbar != null and not vbar.value_changed.is_connected(_on_chat_scroll_value_changed):
		vbar.value_changed.connect(_on_chat_scroll_value_changed)

	_messages_box = VBoxContainer.new()
	_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_box.add_theme_constant_override("separation", 14)
	_scroll.add_child(_messages_box)

	# Composer toolbar + input
	_composer_wrap = _build_composer()
	root.add_child(_composer_wrap)

	_build_action_overlay()
	_build_emoji_overlay()
	_apply_window_position()


func _build_composer() -> Control:
	var wrap := VBoxContainer.new()
	wrap.name = "Composer"
	wrap.add_theme_constant_override("separation", 6)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	wrap.add_child(tools)

	## Original callbacks (in order):
	## 1) _open_emoji_picker — emoji picker
	## 2) _on_share_location — share map location
	## 3) _on_share_rally — share rally preview
	## 4) attachments stub (was disabled "coming soon") → More menu
	_tool_emoji_btn = _make_tool_button("Emoji", "Open emoji picker")
	_tool_emoji_btn.pressed.connect(_open_emoji_picker)
	tools.add_child(_tool_emoji_btn)

	_tool_location_btn = _make_tool_button("Map", "Share map location")
	_tool_location_btn.pressed.connect(_on_share_location)
	tools.add_child(_tool_location_btn)

	_tool_rally_btn = _make_tool_button("Rally", "Share rally")
	_tool_rally_btn.pressed.connect(_on_share_rally)
	tools.add_child(_tool_rally_btn)

	_tool_more_btn = _make_tool_button("More", "More actions")
	_tool_more_btn.pressed.connect(_on_composer_more_pressed)
	tools.add_child(_tool_more_btn)

	## PNG preview of emoji tokens in the draft (LineEdit cannot show inline images).
	_emoji_preview_row = HBoxContainer.new()
	_emoji_preview_row.add_theme_constant_override("separation", 8)
	_emoji_preview_row.custom_minimum_size = Vector2(0, 28)
	wrap.add_child(_emoji_preview_row)
	var preview_lbl := Label.new()
	preview_lbl.text = "Emoji"
	preview_lbl.add_theme_color_override("font_color", COL_MUTED)
	preview_lbl.add_theme_font_size_override("font_size", 12)
	_apply_chat_font(preview_lbl, 12)
	_emoji_preview_row.add_child(preview_lbl)
	_emoji_preview_flow = HFlowContainer.new()
	_emoji_preview_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emoji_preview_flow.add_theme_constant_override("h_separation", 4)
	_emoji_preview_flow.add_theme_constant_override("v_separation", 2)
	_emoji_preview_row.add_child(_emoji_preview_flow)
	_emoji_preview_hint = Label.new()
	_emoji_preview_hint.text = "Pick an emoji to insert :token:"
	_emoji_preview_hint.add_theme_color_override("font_color", Color(COL_MUTED.r, COL_MUTED.g, COL_MUTED.b, 0.85))
	_emoji_preview_hint.add_theme_font_size_override("font_size", 12)
	_apply_chat_font(_emoji_preview_hint, 12)
	_emoji_preview_flow.add_child(_emoji_preview_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)

	_input = LineEdit.new()
	_input.placeholder_text = "Write a message…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 52)
	_input.max_length = ChatMessageScript.MAX_TEXT_LENGTH
	_input.text_submitted.connect(func(_t): _on_send_pressed())
	_input.text_changed.connect(_on_composer_text_changed)
	_input.focus_entered.connect(_on_composer_focus_entered)
	_input.focus_exited.connect(_on_composer_focus_exited)
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
	_apply_chat_font(_input, 16)
	row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "SEND"
	_send_btn.custom_minimum_size = Vector2(96, 52)
	_send_btn.focus_mode = Control.FOCUS_NONE
	_style_primary_button(_send_btn)
	_send_btn.pressed.connect(_on_send_pressed)
	row.add_child(_send_btn)

	_refresh_composer_tools()
	_refresh_emoji_preview()
	return wrap


func _on_composer_text_changed(_new_text: String) -> void:
	_refresh_emoji_preview()


func _refresh_emoji_preview() -> void:
	if _emoji_preview_flow == null:
		return
	for c in _emoji_preview_flow.get_children():
		c.queue_free()
	var draft: String = ""
	if _input != null:
		draft = _input.text
	var tokens: PackedStringArray = ChatEmojiCatalogScript.list_tokens_in_text(draft)
	if tokens.is_empty():
		_emoji_preview_hint = Label.new()
		_emoji_preview_hint.text = "Pick an emoji to insert :token:"
		_emoji_preview_hint.add_theme_color_override("font_color", Color(COL_MUTED.r, COL_MUTED.g, COL_MUTED.b, 0.85))
		_emoji_preview_hint.add_theme_font_size_override("font_size", 12)
		_apply_chat_font(_emoji_preview_hint, 12)
		_emoji_preview_flow.add_child(_emoji_preview_hint)
		return
	for tok in tokens:
		var tex: Texture2D = ChatEmojiCatalogScript.texture_for_token(str(tok))
		if tex == null:
			var fallback := Label.new()
			fallback.text = ChatEmojiCatalogScript.token_literal(str(tok))
			fallback.add_theme_color_override("font_color", COL_INK)
			fallback.add_theme_font_size_override("font_size", 12)
			_apply_chat_font(fallback, 12)
			_emoji_preview_flow.add_child(fallback)
			continue
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = ChatEmojiCatalogScript.token_literal(str(tok))
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_emoji_preview_flow.add_child(icon)


func _make_tool_button(label_text: String, tip: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	_style_icon_button(btn)
	btn.add_theme_font_size_override("font_size", 13)
	_apply_chat_font(btn, 13)
	return btn


func _refresh_composer_tools() -> void:
	## Rally share is kingdom/alliance only — hide in Direct instead of failing after tap.
	if _tool_rally_btn != null:
		var rally_ok: bool = _tab != "private"
		_tool_rally_btn.visible = rally_ok
		_tool_rally_btn.disabled = not rally_ok
	if _tool_location_btn != null:
		_tool_location_btn.disabled = not _can_compose()
	if _tool_emoji_btn != null:
		_tool_emoji_btn.disabled = not _can_compose()
	if _tool_more_btn != null:
		_tool_more_btn.disabled = false


func _on_composer_more_pressed() -> void:
	_close_emoji()
	## Small action menu for the former attachments stub (+).
	_selected_message = null
	if _action_overlay == null or _action_box == null:
		if _status_label != null:
			_status_label.text = "Attachments are coming soon."
		return
	for c in _action_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "More"
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 18)
	_apply_chat_font(title, 18)
	_action_box.add_child(title)
	_add_action("Attachments (coming soon)", func():
		_close_actions()
		if _status_label != null:
			_status_label.text = "Attachments are coming soon."
	)
	## Mirror Map/Rally here so players still find them if the toolbar feels crowded.
	if _can_compose():
		_add_action("Share Map Location", func():
			_close_actions()
			_on_share_location()
		)
	if _tab != "private" and _can_compose():
		_add_action("Share Rally", func():
			_close_actions()
			_on_share_rally()
		)
	_add_action("Cancel", _close_actions)
	_action_overlay.visible = true


func _get_chat_font() -> Font:
	if _chat_font != null:
		return _chat_font
	## Plain system UI font only — emoji rendering is PNG/token based, not Unicode fonts.
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["sans-serif", "Roboto", "Arial", "Helvetica"])
	base.multichannel_signed_distance_field = false
	_chat_font = base
	return _chat_font


func _apply_chat_font(ctrl: Control, font_size: int = 16) -> void:
	if ctrl == null:
		return
	var font: Font = _get_chat_font()
	if font == null:
		return
	if ctrl is LineEdit:
		(ctrl as LineEdit).add_theme_font_override("font", font)
		(ctrl as LineEdit).add_theme_font_size_override("font_size", font_size)
	elif ctrl is Button:
		(ctrl as Button).add_theme_font_override("font", font)
		(ctrl as Button).add_theme_font_size_override("font_size", font_size)
	elif ctrl is Label:
		(ctrl as Label).add_theme_font_override("font", font)
		(ctrl as Label).add_theme_font_size_override("font_size", font_size)


func _style_icon_button(btn: Button) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.14, 0.12, 0.18, 1.0)
	fill.border_color = COL_BORDER
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(10)
	var disabled := fill.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.09, 0.12, 1.0)
	disabled.border_color = Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, 0.35)
	btn.add_theme_stylebox_override("normal", fill)
	btn.add_theme_stylebox_override("pressed", fill)
	btn.add_theme_stylebox_override("hover", fill)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_color_override("font_disabled_color", Color(COL_MUTED.r, COL_MUTED.g, COL_MUTED.b, 0.55))
	_apply_chat_font(btn, 13)


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
	_emoji_panel = PanelContainer.new()
	_emoji_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = COL_CARD
	st.border_color = COL_BORDER
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_emoji_panel.add_theme_stylebox_override("panel", st)
	_emoji_overlay.add_child(_emoji_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_emoji_panel.add_child(col)
	var t := Label.new()
	t.text = "Emoji"
	t.add_theme_color_override("font_color", COL_GOLD)
	t.add_theme_font_size_override("font_size", 18)
	_apply_chat_font(t, 18)
	col.add_child(t)
	var tip := Label.new()
	tip.text = "Inserts :token: — preview shows above the message field"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", COL_MUTED)
	tip.add_theme_font_size_override("font_size", 11)
	_apply_chat_font(tip, 11)
	col.add_child(tip)
	_emoji_grid_scroll = ScrollContainer.new()
	_emoji_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_emoji_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emoji_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_emoji_grid_scroll.custom_minimum_size = Vector2(0, 200)
	col.add_child(_emoji_grid_scroll)
	_emoji_grid = GridContainer.new()
	_emoji_grid.columns = 6
	_emoji_grid.add_theme_constant_override("h_separation", 6)
	_emoji_grid.add_theme_constant_override("v_separation", 6)
	_emoji_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emoji_grid_scroll.add_child(_emoji_grid)
	for i in range(ChatEmojiCatalogScript.TOKENS.size()):
		var tok: String = str(ChatEmojiCatalogScript.TOKENS[i])
		var file_name: String = str(ChatEmojiCatalogScript.FILES[i]) if i < ChatEmojiCatalogScript.FILES.size() else ""
		_emoji_grid.add_child(_make_emoji_cell(tok, file_name))
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 48)
	close.focus_mode = Control.FOCUS_NONE
	_style_primary_button(close)
	close.pressed.connect(_close_emoji)
	col.add_child(close)
	_fit_emoji_panel()


func _make_emoji_cell(token_name: String, file_name: String) -> Control:
	var tex: Texture2D = ChatEmojiCatalogScript.load_texture(file_name)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(EMOJI_CELL_SIZE, EMOJI_CELL_SIZE)
	btn.tooltip_text = ChatEmojiCatalogScript.token_literal(token_name)
	_style_icon_button(btn)
	btn.add_theme_font_size_override("font_size", 1)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		btn.add_child(icon)
	else:
		btn.text = token_name.substr(0, 1).to_upper()
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", COL_INK)
		_apply_chat_font(btn, 14)
	var picked: String = token_name
	btn.pressed.connect(func(): _insert_emoji_token(picked))
	return btn


func _build_emoji_text_block(text: String, font_size: int, color: Color) -> Control:
	## Render :token: (and known legacy Unicode) as PNG; never treat BBCode as markup.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 2)
	flow.add_theme_constant_override("v_separation", 2)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_px: float = float(font_size) + 4.0
	for seg in ChatEmojiCatalogScript.parse_segments(str(text)):
		var kind: String = str(seg.get("kind", "text"))
		if kind == "emoji":
			var tex: Texture2D = ChatEmojiCatalogScript.load_texture(str(seg.get("file", "")))
			if tex != null:
				var icon := TextureRect.new()
				icon.texture = tex
				icon.custom_minimum_size = Vector2(icon_px, icon_px)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.tooltip_text = ChatEmojiCatalogScript.token_literal(str(seg.get("token", "")))
				flow.add_child(icon)
			else:
				## Missing asset — show the token text safely.
				flow.add_child(_make_plain_run_label(str(seg.get("text", "")), font_size, color))
		else:
			var plain: String = str(seg.get("text", ""))
			if plain != "":
				flow.add_child(_make_plain_run_label(plain, font_size, color))
	if flow.get_child_count() == 0:
		flow.add_child(_make_plain_run_label("", font_size, color))
	return flow


func _make_plain_run_label(plain: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = plain
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_chat_font(lbl, font_size)
	return lbl


func _fit_emoji_panel() -> void:
	if _emoji_panel == null:
		return
	## Fit inside phone viewport with margins for notches / bottom nav / short heights.
	var margin_x: float = 16.0
	var margin_y: float = 20.0
	var avail_w: float = maxf(240.0, size.x - margin_x * 2.0)
	var avail_h: float = maxf(260.0, size.y - margin_y * 2.0 - 40.0)
	## Target ~720×1280 portrait: keep panel fully on-screen on narrower/taller phones too.
	var max_w: float = minf(avail_w, 360.0)
	var max_h: float = minf(avail_h, 420.0)
	## Constrain scroll body so PanelContainer cannot grow with the full grid height.
	if _emoji_grid_scroll != null:
		var scroll_h: float = maxf(160.0, max_h - 140.0)
		_emoji_grid_scroll.custom_minimum_size = Vector2(max_w - 28.0, scroll_h)
		_emoji_grid_scroll.size = Vector2(max_w - 28.0, scroll_h)
	_emoji_panel.clip_contents = true
	_emoji_panel.custom_minimum_size = Vector2(max_w, max_h)
	_emoji_panel.size = Vector2(max_w, max_h)
	_emoji_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_emoji_panel.anchor_right = 0.0
	_emoji_panel.anchor_bottom = 0.0
	var x: float = (size.x - max_w) * 0.5
	var y: float = clampf((size.y - max_h) * 0.38, margin_y, maxf(margin_y, size.y - max_h - margin_y))
	_emoji_panel.position = Vector2(x, y)
	## Re-assert size after layout in case content tried to expand the panel.
	_emoji_panel.size = Vector2(max_w, max_h)


func _make_tab_button(text_value: String) -> Button:
	var btn := Button.new()
	btn.text = text_value
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(140, 54)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn


func _apply_window_position() -> void:
	if _window == null:
		return
	var top: float = FALLBACK_TOP_INSET
	var bottom: float = FALLBACK_BOTTOM_INSET
	## Keep composer clear of the Android keyboard without overlapping bottom nav when closed.
	var keyboard_pad: float = maxf(0.0, _keyboard_lift_px)
	var avail_h: float = maxf(280.0, size.y - top - bottom - keyboard_pad)
	var h: float = clampf(size.y * 0.72, 360.0, avail_h)
	var w: float = minf(size.x - 28.0, 680.0)
	_window.custom_minimum_size = Vector2(w, h)
	_window.size = Vector2(w, h)
	var y: float = top + maxf(0.0, (avail_h - h) * 0.2)
	## When keyboard is open, pin the window just above the keyboard/nav pad.
	if keyboard_pad > 1.0:
		y = maxf(8.0, size.y - bottom - keyboard_pad - h - 8.0)
	_window.position = Vector2((size.x - w) * 0.5, y)
	if _dim != null:
		_dim.offset_bottom = -bottom


func _on_composer_focus_entered() -> void:
	if _input == null:
		return
	DisplayServer.virtual_keyboard_show(_input.text)
	_update_keyboard_lift()


func _on_composer_focus_exited() -> void:
	DisplayServer.virtual_keyboard_hide()
	_keyboard_lift_px = 0.0
	_apply_window_position()


func _on_chat_scroll_value_changed(_value: float) -> void:
	_stick_to_bottom = _is_near_bottom()


func _set_tab(tab_id: String) -> void:
	_tab = tab_id
	_close_actions()
	_close_emoji()
	if _tab != "private" and has_node("/root/ChatManager"):
		_chat_manager().clear_active_dm_peer()
	_refresh_tabs()
	_refresh_status()
	_refresh_messages()
	_open_active_channel()
	if _tab == "alliance":
		_input.placeholder_text = "Message alliance…"
	elif _tab == "private":
		_input.placeholder_text = "Private message…"
		var fb_refresh: Node = _friends_backend()
		if fb_refresh != null and fb_refresh.has_method("refresh_friends"):
			fb_refresh.call("refresh_friends")
	else:
		_input.placeholder_text = "Message kingdom…"


func _refresh_tabs() -> void:
	_style_tab(_kingdom_tab, _tab == "kingdom")
	_style_tab(_alliance_tab, _tab == "alliance")
	_style_tab(_private_tab, _tab == "private")
	if _private_tab != null:
		_private_tab.visible = true
		var unread: int = 0
		if has_node("/root/ChatManager"):
			unread = int(_chat_manager().get_dm_unread_total())
		var label: String = "DIRECT"
		if unread > 0 and _tab != "private":
			label = "DIRECT (%d)" % unread
		_private_tab.text = label
	_update_dm_chrome()
	_refresh_composer_tools()


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
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	var conn_label: String = ""
	if nc != null and nc.has_method("get_connection_status_label"):
		conn_label = str(nc.get_connection_status_label())

	if _tab == "private":
		if not has_node("/root/ChatManager") or not _chat_manager().is_chat_available():
			_status_label.text = _format_conn_banner(conn_label, "Direct Messages unavailable")
			_input.editable = false
			_send_btn.disabled = true
			_update_dm_chrome()
			return
		var peer: String = _chat_manager().get_active_dm_peer()
		if peer == "":
			_status_label.text = "Direct · Private inbox · %s" % (conn_label if conn_label != "" else "Connected")
			_input.editable = false
			_send_btn.disabled = true
		else:
			var pname: String = _chat_manager().get_dm_display_name(peer)
			_status_label.text = "Direct · Messaging %s · %s" % [pname, conn_label if conn_label != "" else "Connected"]
			_input.editable = true
			_send_btn.disabled = false
		_update_dm_chrome()
		return
	if _tab == "alliance":
		if not has_node("/root/ChatManager") or not _chat_manager().is_alliance_chat_available():
			var reason: String = _chat_manager().get_alliance_chat_unavailable_reason() if has_node("/root/ChatManager") else "Join an Alliance to use Alliance Chat."
			_status_label.text = _format_conn_banner(conn_label, reason)
			_input.editable = false
			_send_btn.disabled = true
			return
		var tag: String = _alliance_backend().get_alliance_tag() if has_node("/root/AllianceBackend") else ""
		var aname: String = _alliance_backend().get_alliance_name() if has_node("/root/AllianceBackend") else ""
		var joined_a: bool = _chat_manager().is_alliance_joined()
		_status_label.text = "[%s] %s · %s" % [
			tag if tag != "" else "???",
			aname if aname != "" else "Alliance",
			"Connected" if joined_a else (conn_label if conn_label != "" else "Joining…"),
		]
		_input.editable = joined_a
		_send_btn.disabled = not joined_a
		return

	if not has_node("/root/ChatManager") or not _chat_manager().is_chat_available():
		_status_label.text = _format_conn_banner(conn_label, "Kingdom Chat unavailable")
		_input.editable = false
		_send_btn.disabled = true
		return

	var kid: String = _chat_manager().get_kingdom_id()
	var joined: bool = _chat_manager().is_kingdom_joined()
	_status_label.text = "Kingdom %s · %s" % [
		kid,
		"Connected" if joined else (conn_label if conn_label != "" else "Joining…"),
	]
	_input.editable = joined
	_send_btn.disabled = not joined


func _format_conn_banner(conn_label: String, detail: String) -> String:
	var state: String = conn_label if conn_label != "" else "Offline"
	return "%s — %s" % [state, detail]


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
		_render_dm_hub()
		return

	var has_more: bool = false
	if _tab == "alliance":
		has_more = _chat_manager().get_alliance_history_has_more()
	elif _tab == "private":
		has_more = false
	else:
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


func _update_dm_chrome() -> void:
	var in_private: bool = _tab == "private"
	var peer: String = ""
	if in_private and has_node("/root/ChatManager"):
		peer = _chat_manager().get_active_dm_peer()
	if _dm_peer_bar != null:
		_dm_peer_bar.visible = in_private and peer != ""
		if peer != "":
			_dm_peer_label.text = "Private with %s" % _chat_manager().get_dm_display_name(peer)
	if _composer_wrap != null:
		_composer_wrap.visible = not in_private or peer != ""


func _on_dm_back_pressed() -> void:
	if has_node("/root/ChatManager"):
		_chat_manager().clear_active_dm_peer()
	_dm_hub_section = "conversations"
	_refresh_tabs()
	_refresh_status()
	_refresh_messages()


func _on_dm_hub_changed(_a = null, _b = null, _c = null) -> void:
	if not visible or _tab != "private":
		if visible:
			_refresh_tabs()
		return
	_refresh_tabs()
	_refresh_status()
	if _chat_manager().get_active_dm_peer() == "":
		_refresh_messages()


func _on_dm_unread_ui(_total: int = 0) -> void:
	_refresh_tabs()


func _render_dm_hub() -> void:
	var section_row := HBoxContainer.new()
	section_row.add_theme_constant_override("separation", 6)
	_messages_box.add_child(section_row)
	for item in [
		["conversations", "Inbox"],
		["friends", "Friends"],
		["requests", "Requests"],
	]:
		var sid: String = str(item[0])
		var btn := Button.new()
		btn.text = str(item[1])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tab(btn, _dm_hub_section == sid)
		btn.pressed.connect(func():
			_dm_hub_section = sid
			_refresh_messages()
		)
		section_row.add_child(btn)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", COL_MUTED)
	note.add_theme_font_size_override("font_size", 12)
	note.text = "Private messages stay in Direct. They never post to Kingdom or Alliance."
	_messages_box.add_child(note)

	match _dm_hub_section:
		"friends":
			_render_dm_friends_list()
		"requests":
			_render_dm_requests_list()
		_:
			_render_dm_conversations_list()


func _render_dm_conversations_list() -> void:
	var convos: Array[Dictionary] = _chat_manager().list_dm_conversations()
	if convos.is_empty():
		var empty := Label.new()
		empty.text = "No conversations yet. Message a player from their Profile or Friends."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", COL_MUTED)
		_messages_box.add_child(empty)
		return
	for c in convos:
		_messages_box.add_child(_build_dm_convo_row(c))


func _build_dm_convo_row(c: Dictionary) -> Control:
	var uid: String = str(c.get("user_id", ""))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.border_color = Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_col)
	var title := Label.new()
	var unread: int = int(c.get("unread", 0))
	title.text = str(c.get("display_name", "Player"))
	if unread > 0:
		title.text = "%s  (%d)" % [title.text, unread]
	title.add_theme_color_override("font_color", COL_GOLD if unread > 0 else COL_INK)
	title.add_theme_font_size_override("font_size", 16)
	name_col.add_child(title)
	var preview := Label.new()
	preview.text = str(c.get("preview", ""))
	if preview.text == "":
		preview.text = "Tap to open conversation"
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_color_override("font_color", COL_MUTED)
	preview.add_theme_font_size_override("font_size", 12)
	name_col.add_child(preview)
	var ts := Label.new()
	ts.text = _format_unix_short(int(c.get("timestamp_unix", 0)))
	ts.add_theme_color_override("font_color", COL_MUTED)
	ts.add_theme_font_size_override("font_size", 11)
	row.add_child(ts)
	var open_btn := Button.new()
	open_btn.text = "Open"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.custom_minimum_size = Vector2(72, 44)
	_style_icon_button(open_btn)
	open_btn.pressed.connect(func(): _start_private_with(uid, str(c.get("display_name", "Player"))))
	row.add_child(open_btn)
	return panel


func _render_dm_friends_list() -> void:
	var fb: Node = _friends_backend()
	if fb == null or not fb.has_method("get_friends"):
		var miss := Label.new()
		miss.text = "Friends unavailable."
		miss.add_theme_color_override("font_color", COL_MUTED)
		_messages_box.add_child(miss)
		return
	var friends: Array[Dictionary] = fb.get_friends()
	if friends.is_empty():
		var empty := Label.new()
		empty.text = "No friends yet. Send a request from a Player Profile."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", COL_MUTED)
		_messages_box.add_child(empty)
		return
	for f in friends:
		_messages_box.add_child(_build_friend_row(f, "friend"))


func _render_dm_requests_list() -> void:
	var fb: Node = _friends_backend()
	if fb == null:
		return
	var incoming: Array[Dictionary] = fb.get_incoming_requests()
	var outgoing: Array[Dictionary] = fb.get_outgoing_requests()
	var blocked: Array[Dictionary] = fb.get_blocked()

	_add_hub_heading("Incoming")
	if incoming.is_empty():
		_add_hub_empty("No incoming requests.")
	else:
		for f in incoming:
			_messages_box.add_child(_build_friend_row(f, "invite_received"))

	_add_hub_heading("Outgoing")
	if outgoing.is_empty():
		_add_hub_empty("No outgoing requests.")
	else:
		for f in outgoing:
			_messages_box.add_child(_build_friend_row(f, "invite_sent"))

	_add_hub_heading("Blocked")
	if blocked.is_empty():
		_add_hub_empty("No blocked players.")
	else:
		for f in blocked:
			_messages_box.add_child(_build_friend_row(f, "blocked"))


func _add_hub_heading(text_value: String) -> void:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.add_theme_font_size_override("font_size", 15)
	_messages_box.add_child(lbl)


func _add_hub_empty(text_value: String) -> void:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_color_override("font_color", COL_MUTED)
	lbl.add_theme_font_size_override("font_size", 12)
	_messages_box.add_child(lbl)


func _build_friend_row(f: Dictionary, mode: String) -> Control:
	var uid: String = str(f.get("user_id", ""))
	var dname: String = str(f.get("display_name", "Player"))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.border_color = Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var title := Label.new()
	var online: String = str(f.get("online_status", "unknown"))
	var online_mark: String = ""
	if online == "online":
		online_mark = " ●"
	elif online == "offline":
		online_mark = " ○"
	title.text = "%s%s" % [dname, online_mark]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COL_OK if online == "online" else COL_INK)
	title.add_theme_font_size_override("font_size", 15)
	top.add_child(title)
	var profile_btn := Button.new()
	profile_btn.text = "Profile"
	profile_btn.focus_mode = Control.FOCUS_NONE
	profile_btn.custom_minimum_size = Vector2(72, 40)
	_style_icon_button(profile_btn)
	profile_btn.pressed.connect(func(): _open_external_profile(uid))
	top.add_child(profile_btn)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	col.add_child(actions)
	match mode:
		"friend":
			_hub_action_btn(actions, "Message", func(): _start_private_with(uid, dname))
			_hub_action_btn(actions, "Remove", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.remove_friend(uid)
			)
		"invite_received":
			_hub_action_btn(actions, "Accept", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.accept_friend_request(uid)
			)
			_hub_action_btn(actions, "Decline", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.decline_friend_request(uid)
			)
		"invite_sent":
			_hub_action_btn(actions, "Cancel", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.cancel_friend_request(uid)
			)
		"blocked":
			_hub_action_btn(actions, "Unblock", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.unblock_player(uid)
			)
	return panel


func _hub_action_btn(parent: Control, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_icon_button(btn)
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _format_unix_short(ts: int) -> String:
	if ts <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d:%02d" % [int(dt.get("hour", 0)), int(dt.get("minute", 0))]


func _build_message_row(msg: RefCounted, local_id: String) -> Control:
	var is_system: bool = str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM
	var is_self: bool = (not is_system) and str(msg.sender_user_id) == local_id and local_id != ""

	if is_system:
		return _build_system_row(msg)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD_SELF if is_self else COL_CARD
	style.border_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.35) if is_self else Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
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
	var name_btn := Button.new()
	if tag != "":
		name_btn.text = "[%s] %s" % [tag, name_text]
	else:
		name_btn.text = name_text
	name_btn.flat = true
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.add_theme_color_override("font_color", COL_GOLD if is_self else COL_INK)
	name_btn.add_theme_font_size_override("font_size", 14)
	name_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if not is_self:
		name_btn.pressed.connect(func():
			_open_player_context(str(msg.sender_user_id), name_text)
		)
	header.add_child(name_btn)

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
			col.add_child(_build_emoji_text_block(str(msg.text), 16, COL_INK))

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
	var body := _build_emoji_text_block(str(msg.text), 14, COL_MUTED)
	col.add_child(body)
	return panel


func _build_avatar(msg: RefCounted, is_self: bool) -> Control:
	var wrap := Button.new()
	wrap.flat = true
	wrap.focus_mode = Control.FOCUS_NONE
	wrap.custom_minimum_size = Vector2(44, 44)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	wrap.add_theme_stylebox_override("normal", empty)
	wrap.add_theme_stylebox_override("hover", empty)
	wrap.add_theme_stylebox_override("pressed", empty)

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
	if not is_self:
		wrap.pressed.connect(func():
			_open_player_context(str(msg.sender_user_id), str(msg.sender_display_name))
		)
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
			print("[Chat] castle location tapped kingdom=%s x=%s y=%s" % [
				str(payload.get("kingdom_id", "")),
				str(payload.get("x", 0)),
				str(payload.get("y", 0)),
			])
			var result: Dictionary = await _chat_manager().navigate_to_map_location(payload)
			if bool(result.get("navigated", false)):
				_status_label.text = "Navigating to location…"
			else:
				_status_label.text = str(result.get("error", result.get("note", "Could not open location.")))
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
	join.focus_mode = Control.FOCUS_NONE
	join.custom_minimum_size = Vector2(100, 44)
	join.tooltip_text = "Join this Alliance Rally"
	_style_primary_button(join)
	var rally_id: String = str(payload.get("rally_id", ""))
	join.pressed.connect(func():
		_on_join_rally_pressed(rally_id, payload)
	)
	row.add_child(join)
	return card


func _on_join_rally_pressed(rally_id: String, payload: Dictionary) -> void:
	if rally_id.strip_edges() == "":
		if _status_label != null:
			_status_label.text = "Missing rally id."
		return
	if not has_node("/root/RallyBackend"):
		if _status_label != null:
			_status_label.text = "Rally backend unavailable."
		return
	var fetched: Dictionary = await RallyBackend.get_rally(rally_id)
	var rally: Dictionary = fetched.get("rally", {}) as Dictionary
	if not bool(fetched.get("ok", false)) or rally.is_empty():
		# Fall back to card payload for lobby lookup.
		rally = {
			"rally_id": rally_id,
			"lair_id": str(payload.get("target_id", "")),
			"lair_level": 1,
			"world_x": float(payload.get("x", 0.0)),
			"world_y": float(payload.get("y", 0.0)),
			"status": "FORMING",
			"participants": [],
			"countdown_seconds": 60,
			"launch_at": int(payload.get("expiry_unix", 0)),
		}
	var setup: Node = get_tree().root.find_child("RallySetupScreen", true, false)
	if setup != null and setup.has_method("open_to_join"):
		setup.call("open_to_join", rally)
		if _status_label != null:
			_status_label.text = "Opening Rally join…"
	else:
		var lobby: Node = get_tree().root.find_child("RallyLobbyScreen", true, false)
		if lobby != null and lobby.has_method("open_for_rally"):
			lobby.call("open_for_rally", rally)
		elif _status_label != null:
			_status_label.text = "Rally UI unavailable."


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
			if _status_label != null:
				_status_label.text = "Translation is not available yet — no translation provider is configured."
		else:
			if _status_label != null:
				_status_label.text = "Translation applied."
	else:
		var err_text: String = str(result.get("error", "Translation service not configured."))
		_translations[mid] = {"ok": false, "error": err_text}
		if _status_label != null:
			_status_label.text = "Translation unavailable: %s" % err_text
	_refresh_messages()
	if _stick_to_bottom:
		_scroll_to_bottom(false)


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
		_open_external_profile(str(msg.sender_user_id))
		_close_actions()
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
	var fb_ctx: Node = _friends_backend()
	if fb_ctx != null and fb_ctx.has_method("get_relationship"):
		var rel: String = str(fb_ctx.get_relationship(_player_context_user_id))
		if rel == "none":
			_add_action("Add Friend", func():
				var fb: Node = _friends_backend()
				if fb == null:
					return
				var r: Dictionary = await fb.send_friend_request(_player_context_user_id)
				_status_label.text = "Friend request sent." if bool(r.get("ok", false)) else str(r.get("error", "Request failed."))
				_close_actions()
			)
		elif rel == "invite_received":
			_add_action("Accept Friend", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.accept_friend_request(_player_context_user_id)
				_status_label.text = "Friend request accepted."
				_close_actions()
			)
		elif rel == "friend":
			_add_action("Remove Friend", func():
				var fb: Node = _friends_backend()
				if fb != null:
					await fb.remove_friend(_player_context_user_id)
				_status_label.text = "Friend removed."
				_close_actions()
			)
		_add_action("Block", func():
			var fb: Node = _friends_backend()
			if fb == null:
				return
			var br: Dictionary = await fb.block_player(_player_context_user_id)
			_status_label.text = "Player blocked." if bool(br.get("ok", false)) else str(br.get("error", "Block failed."))
			_close_actions()
		)
	else:
		_add_action("Block", func():
			_chat_manager().block_user(_player_context_user_id)
			_status_label.text = "Player blocked."
			_close_actions()
		)
	_add_action("Report", func():
		_status_label.text = "Long-press a message to report with evidence."
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


func _open_emoji_picker() -> void:
	_close_actions()
	if _emoji_overlay != null:
		_fit_emoji_panel()
		_emoji_overlay.visible = true
		call_deferred("_fit_emoji_panel")


func _insert_emoji_token(token_name: String) -> void:
	if _input == null or token_name == "":
		return
	var literal: String = ChatEmojiCatalogScript.token_literal(token_name)
	var caret: int = _input.caret_column
	var text: String = _input.text
	caret = clampi(caret, 0, text.length())
	## Insert ASCII token only — never invisible Unicode glyphs.
	_input.text = text.substr(0, caret) + literal + text.substr(caret)
	_input.caret_column = caret + literal.length()
	_refresh_emoji_preview()
	_close_emoji()
	_input.grab_focus()
	DisplayServer.virtual_keyboard_show(_input.text)


func _close_emoji() -> void:
	if _emoji_overlay != null:
		_emoji_overlay.visible = false


func _is_near_bottom() -> bool:
	if _scroll == null:
		return true
	var bar: ScrollBar = _scroll.get_v_scroll_bar()
	if bar == null:
		return true
	return float(bar.value) >= float(bar.max_value) - SCROLL_STICK_MARGIN_PX


func _scroll_to_bottom(force: bool = false) -> void:
	if not force and not _stick_to_bottom and not _is_near_bottom():
		return
	_stick_to_bottom = true
	await get_tree().process_frame
	await get_tree().process_frame
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_share_location() -> void:
	if not has_node("/root/ChatManager"):
		return
	if not _can_compose():
		return
	var cm: Node = _chat_manager()
	var kid: String = cm.get_kingdom_id()
	var share_pos := Vector2(4096, 4096)
	if has_node("/root/MarchState") and MarchState.has_method("get_castle_world_position"):
		share_pos = MarchState.get_castle_world_position()
	# Prefer live world camera center when already on the map.
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var cam: Camera2D = tree.current_scene.get_node_or_null("Camera2D") as Camera2D
		if cam != null and str(tree.current_scene.name) == "KingdomMap":
			share_pos = cam.global_position
	var payload := {
		"kingdom_id": kid,
		"x": share_pos.x,
		"y": share_pos.y,
		"label": "Shared Location",
		"target_type": "coord",
		"target_id": "",
	}
	var kind: String = "kingdom"
	if _tab == "alliance":
		kind = "alliance"
	elif _tab == "private":
		kind = "private"
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
	if _tab == "private":
		_status_label.text = "Rallies cannot be shared in Direct Messages."
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
	## Normalize known legacy Unicode → :token: before Nakama; keep ordinary text intact.
	var text_value: String = ChatEmojiCatalogScript.normalize_outbound(_input.text)
	_input.text = ""
	_refresh_emoji_preview()
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
	## Legacy helper — always opens the unified PlayerProfileScreen by user_id.
	_open_external_profile(str(msg.sender_user_id))


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
