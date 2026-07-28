extends Control

## Floating chat preview strip — sits above the bottom nav.
## Opens ChatScreen on tap. UI-only; uses ChatManager signals for display.

const ChatMessageScript = preload("res://scripts/Backend/ChatMessage.gd")

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_PANEL := Color(0.08, 0.07, 0.11, 0.88)
const COL_BORDER := Color(0.72, 0.58, 0.30, 0.92)
const COL_BADGE := Color(0.82, 0.22, 0.22, 1.0)

const PREVIEW_HEIGHT: float = 56.0
## Bottom nav bar height ≈ 179px; keep only a few pixels of spacing.
const BOTTOM_NAV_CLEARANCE: float = 179.0
const PREVIEW_NAV_GAP: float = 4.0

signal open_chat_requested

var _panel: PanelContainer
var _channel_icon: Label
var _header_label: Label
var _body_label: Label
var _badge: Label
var _pulse: Tween

var _unread_count: int = 0
var _last_seen_id: String = ""
var _bound: bool = false
var _force_hidden: bool = false
var _chat_open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_bind_signals()
	_refresh_from_latest()
	call_deferred("_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func set_force_hidden(hidden: bool) -> void:
	_force_hidden = hidden
	_apply_visibility()


func set_chat_session_open(is_open: bool) -> void:
	var was_open: bool = _chat_open
	_chat_open = is_open
	if is_open and not was_open:
		mark_chat_opened()
	_apply_visibility()


func mark_chat_opened() -> void:
	_unread_count = 0
	_update_badge()
	var latest: RefCounted = _pick_newest_message()
	if latest != null:
		_last_seen_id = str(latest.message_id)


func _chat_manager() -> Node:
	return get_node_or_null("/root/ChatManager")


func _build() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor_left = 0.5
	anchor_right = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH

	_panel = PanelContainer.new()
	_panel.name = "PreviewPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_channel_icon = Label.new()
	_channel_icon.text = "🏰"
	_channel_icon.add_theme_font_size_override("font_size", 22)
	_channel_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_channel_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_channel_icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	_header_label = Label.new()
	_header_label.text = "Kingdom Chat"
	_header_label.add_theme_font_size_override("font_size", 14)
	_header_label.add_theme_color_override("font_color", COL_GOLD)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.clip_text = true
	text_col.add_child(_header_label)

	_body_label = Label.new()
	_body_label.text = "Tap to open chat"
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", COL_INK)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.clip_text = true
	text_col.add_child(_body_label)

	_badge = Label.new()
	_badge.visible = false
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.custom_minimum_size = Vector2(26, 26)
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_badge)

	gui_input.connect(_on_gui_input)
	_panel.gui_input.connect(_on_gui_input)


func _layout() -> void:
	var viewport_w: float = get_viewport_rect().size.x
	if viewport_w <= 1.0 and get_parent() is Control:
		viewport_w = (get_parent() as Control).size.x
	var width: float = clampf(viewport_w * 0.86, 280.0, 640.0)
	custom_minimum_size = Vector2(width, PREVIEW_HEIGHT)
	size = Vector2(width, PREVIEW_HEIGHT)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -(BOTTOM_NAV_CLEARANCE + PREVIEW_HEIGHT + PREVIEW_NAV_GAP)
	offset_bottom = -(BOTTOM_NAV_CLEARANCE + PREVIEW_NAV_GAP)


func _bind_signals() -> void:
	if _bound:
		return
	var cm: Node = _chat_manager()
	if cm == null:
		return
	_bound = true
	if not cm.message_received.is_connected(_on_chat_event):
		cm.message_received.connect(_on_chat_event)
	if not cm.message_sent.is_connected(_on_chat_event):
		cm.message_sent.connect(_on_chat_event)
	if not cm.messages_loaded.is_connected(_on_messages_loaded):
		cm.messages_loaded.connect(_on_messages_loaded)
	if not cm.availability_changed.is_connected(_on_availability):
		cm.availability_changed.connect(_on_availability)
	if cm.has_signal("dm_unread_changed") and not cm.dm_unread_changed.is_connected(_on_dm_unread):
		cm.dm_unread_changed.connect(_on_dm_unread)


func _on_dm_unread(total: int) -> void:
	if not _chat_open and total > _unread_count:
		_unread_count = total
	_update_badge()


func _on_availability(_available: bool) -> void:
	_refresh_from_latest()


func _on_messages_loaded(_kind: String) -> void:
	_refresh_from_latest()


func _on_chat_event(msg: RefCounted) -> void:
	if msg == null:
		return
	_apply_message(msg, true)
	if not _chat_open:
		var mid: String = str(msg.message_id)
		if mid != "" and mid != _last_seen_id:
			_unread_count += 1
			_update_badge()


func _apply_visibility() -> void:
	visible = (not _force_hidden) and (not _chat_open)
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE


func _refresh_from_latest() -> void:
	_bind_signals()
	var latest: RefCounted = _pick_newest_message()
	if latest == null:
		_channel_icon.text = "🏰"
		_header_label.text = "Kingdom Chat"
		_body_label.text = "Tap to open chat"
		return
	_apply_message(latest, false)


func _pick_newest_message() -> RefCounted:
	var cm: Node = _chat_manager()
	if cm == null:
		return null
	var best: RefCounted = null
	var best_ts: int = -1
	var pools: Array = []
	pools.append(cm.get_messages())
	if cm.has_method("is_alliance_chat_available") and cm.is_alliance_chat_available():
		pools.append(cm.get_alliance_messages())
	if cm.has_method("get_private_messages") and cm.has_method("get_active_dm_peer"):
		var peer: String = str(cm.get_active_dm_peer())
		if peer != "":
			pools.append(cm.get_private_messages(peer))
	for pool in pools:
		for m in pool:
			if m == null:
				continue
			var ts: int = int(m.timestamp_unix)
			if ts >= best_ts:
				best_ts = ts
				best = m
	return best


func _apply_message(msg: RefCounted, animate: bool) -> void:
	var is_alliance: bool = str(msg.message_type) != "" and _message_is_alliance(msg)
	_channel_icon.text = "🛡" if is_alliance else "🏰"

	var tag: String = str(msg.sender_alliance_tag).strip_edges()
	var name_text: String = str(msg.sender_display_name).strip_edges()
	if name_text == "":
		name_text = "Player"
	if str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM:
		_header_label.text = "SYSTEM"
		_body_label.text = _first_line(str(msg.text))
	else:
		if tag != "":
			_header_label.text = "[%s] %s" % [tag, name_text]
		else:
			_header_label.text = name_text
		_body_label.text = _preview_body(msg)

	if animate:
		_play_pulse()


func _message_is_alliance(msg: RefCounted) -> bool:
	var cm: Node = _chat_manager()
	if cm == null:
		return false
	var ally_id: String = str(cm.get_alliance_channel_id()) if cm.has_method("get_alliance_channel_id") else ""
	return ally_id != "" and str(msg.channel_id) == ally_id


func _preview_body(msg: RefCounted) -> String:
	match str(msg.message_type):
		ChatMessageScript.TYPE_MAP_LOCATION:
			var payload: Dictionary = msg.payload if typeof(msg.payload) == TYPE_DICTIONARY else {}
			return "📍 %s" % str(payload.get("label", "Location"))
		ChatMessageScript.TYPE_RALLY:
			var rp: Dictionary = msg.payload if typeof(msg.payload) == TYPE_DICTIONARY else {}
			return "⚔ Rally — %s" % str(rp.get("target_name", "Target"))
		_:
			return _first_line(str(msg.text))


func _first_line(text_value: String) -> String:
	var cleaned: String = text_value.strip_edges().replace("\n", " ")
	if cleaned.length() > 64:
		return cleaned.substr(0, 61) + "…"
	return cleaned if cleaned != "" else "…"


func _update_badge() -> void:
	if _badge == null:
		return
	if _unread_count <= 0:
		_badge.visible = false
		return
	_badge.visible = true
	_badge.text = str(mini(_unread_count, 99))
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = COL_BADGE
	badge_style.set_corner_radius_all(13)
	badge_style.content_margin_left = 6
	badge_style.content_margin_right = 6
	_badge.add_theme_stylebox_override("normal", badge_style)


func _play_pulse() -> void:
	if _pulse != null and _pulse.is_running():
		_pulse.kill()
	modulate = Color(1.15, 1.1, 0.95, 1.0)
	_pulse = create_tween()
	_pulse.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.35).set_ease(Tween.EASE_OUT)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_chat_requested.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		open_chat_requested.emit()
		accept_event()
