extends Control

## Floating chat preview panel — stacked directly above the bottom nav.
## Opens ChatScreen on tap. UI-only; uses ChatManager signals for display.

const ChatMessageScript = preload("res://Scripts/Backend/ChatMessage.gd")

const COL_INK := Color(0.94, 0.90, 0.82, 1.0)
const COL_NAME := Color(0.98, 0.95, 0.88, 1.0)
const COL_MUTED := Color(0.78, 0.74, 0.66, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.36, 1.0)
const COL_PURPLE := Color(0.52, 0.34, 0.72, 0.95)
const COL_PANEL := Color(0.06, 0.07, 0.14, 0.96)
const COL_PANEL_EDGE := Color(0.10, 0.09, 0.18, 1.0)
const COL_BORDER := Color(0.78, 0.62, 0.32, 0.95)
const COL_BADGE := Color(0.82, 0.22, 0.22, 1.0)

## Design height at 720×1280; clamped to the reference band.
const PREVIEW_HEIGHT_DESIGN: float = 98.0
const PREVIEW_HEIGHT_MIN: float = 90.0
const PREVIEW_HEIGHT_MAX: float = 105.0
const DESIGN_VIEWPORT_H: float = 1280.0
## Fallback when BottomBarTexture is unavailable (matches GameHUD nav height).
const BOTTOM_NAV_CLEARANCE: float = 179.0
## Shared tuck: lower portion of ChatPreview sits behind BottomBarTexture (Kingdom reference).
const PREVIEW_NAV_OVERLAP: float = 28.0
const LEFT_COL_W: float = 76.0
## Below BottomBarTexture (z=70) on both City and Kingdom so nav paints/taps on top.
const PREVIEW_Z: int = 40

signal open_chat_requested
signal layout_changed(global_rect: Rect2)

var _panel: PanelContainer
var _hit_button: Button
var _channel_icon: Label
var _tag_label: Label
var _name_label: Label
var _body_label: Label
var _badge: Label
var _pulse: Tween

var _unread_count: int = 0
var _last_seen_id: String = ""
var _bound: bool = false
var _force_hidden: bool = false
var _chat_open: bool = false
var _activate_guard_ms: int = 0
var _built: bool = false
var _layout_guard: bool = false
var _bar_resized_bound: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PREVIEW_Z
	# Parent GameHUD/Control is a plain Control (not a Container) — manual offsets stick.
	size_flags_horizontal = 0
	size_flags_vertical = 0
	_build()
	_bind_signals()
	_refresh_from_latest()
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	# BottomBarTexture often finishes layout AFTER the first frame (safe-area / anchors).
	call_deferred("refresh_layout_after_nav")
	call_deferred("_log_hit_diagnostics")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("refresh_layout_after_nav")


func _on_viewport_resized() -> void:
	call_deferred("refresh_layout_after_nav")


## Public entry for GameHUD safe-area / orientation refreshes.
func refresh_layout() -> void:
	_layout()


## Wait until BottomBarTexture has its final rect, then snap to it.
func refresh_layout_after_nav() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_bind_bar_resized()
	_layout()
	# One more pass next frame — Android safe-area / stretch often settles late.
	await get_tree().process_frame
	_layout()


func get_preview_height() -> float:
	var vh: float = get_viewport_rect().size.y
	if vh <= 1.0:
		return PREVIEW_HEIGHT_DESIGN
	var scaled: float = PREVIEW_HEIGHT_DESIGN * (vh / DESIGN_VIEWPORT_H)
	return clampf(scaled, PREVIEW_HEIGHT_MIN, PREVIEW_HEIGHT_MAX)


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
	if _built:
		return
	_built = true
	for c in get_children():
		c.queue_free()

	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	_panel = PanelContainer.new()
	_panel.name = "PreviewPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.set_corner_radius_all(12)
	style.shadow_color = Color(COL_PURPLE.r, COL_PURPLE.g, COL_PURPLE.b, 0.35)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	# Inner bevel wash via a second edge tone on the border.
	style.border_color = Color(
		lerpf(COL_BORDER.r, COL_PURPLE.r, 0.22),
		lerpf(COL_BORDER.g, COL_PURPLE.g, 0.22),
		lerpf(COL_BORDER.b, COL_PURPLE.b, 0.22),
		0.96
	)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.name = "PreviewRow"
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(row)

	# LEFT — chat/speech icon column
	var left_col := CenterContainer.new()
	left_col.custom_minimum_size = Vector2(LEFT_COL_W, 0)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_col)
	_channel_icon = Label.new()
	_channel_icon.text = "💬"
	_channel_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_channel_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_channel_icon.add_theme_font_size_override("font_size", 30)
	_channel_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_channel_icon)

	# CENTER — name + message
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 4)
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(name_row)

	_tag_label = Label.new()
	_tag_label.visible = false
	_tag_label.add_theme_font_size_override("font_size", 16)
	_tag_label.add_theme_color_override("font_color", COL_GOLD)
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_label.clip_text = true
	name_row.add_child(_tag_label)

	_name_label = Label.new()
	_name_label.text = "Kingdom Chat"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", COL_NAME)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.clip_text = true
	name_row.add_child(_name_label)

	_body_label = Label.new()
	_body_label.text = "Tap to open chat"
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", COL_MUTED)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.clip_text = true
	_body_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_col.add_child(_body_label)

	# Unread badge floats on the panel (no envelope / right icon column).
	_badge = Label.new()
	_badge.visible = false
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.custom_minimum_size = Vector2(26, 26)
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.offset_left = -34.0
	_badge.offset_right = -8.0
	_badge.offset_top = 8.0
	_badge.offset_bottom = 34.0
	_panel.add_child(_badge)

	# Full-panel hit target (covers icon / text / blank panel area).
	_hit_button = Button.new()
	_hit_button.name = "PreviewHitButton"
	_hit_button.flat = true
	_hit_button.focus_mode = Control.FOCUS_NONE
	_hit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hit_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_button.z_index = 1
	var empty := StyleBoxEmpty.new()
	_hit_button.add_theme_stylebox_override("normal", empty)
	_hit_button.add_theme_stylebox_override("hover", empty)
	_hit_button.add_theme_stylebox_override("pressed", empty)
	_hit_button.add_theme_stylebox_override("disabled", empty)
	_hit_button.add_theme_stylebox_override("focus", empty)
	_hit_button.pressed.connect(_on_hit_pressed)
	_hit_button.gui_input.connect(_on_hit_gui_input)
	add_child(_hit_button)


func _bind_bar_resized() -> void:
	if _bar_resized_bound:
		return
	var bar: Control = _find_bottom_nav_bar()
	if bar == null:
		return
	_bar_resized_bound = true
	if not bar.resized.is_connected(_on_bar_resized):
		bar.resized.connect(_on_bar_resized)
	if bar.has_signal("item_rect_changed") and not bar.item_rect_changed.is_connected(_on_bar_resized):
		bar.item_rect_changed.connect(_on_bar_resized)


func _on_bar_resized() -> void:
	if _layout_guard:
		return
	call_deferred("_layout")


func _is_world_hud() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("game_hud") if get_tree() != null else null
	if hud != null and "is_world_screen" in hud:
		return bool(hud.is_world_screen)
	return false


func _layout() -> void:
	if _layout_guard:
		return
	_layout_guard = true
	var world: bool = _is_world_hud()
	z_index = PREVIEW_Z
	var host: Control = get_parent() as Control
	if host == null:
		_layout_guard = false
		return

	var height: float = get_preview_height()
	var bar: Control = _find_bottom_nav_bar()
	_bind_bar_resized()

	## CRITICAL: ChatPreview must share BottomBarTexture's bottom-anchored space.
	## Previous top-left absolute Y drifted from BottomBarTexture whenever
	## GameHUD/Control height changed (Android safe-area inset on chrome.offset_bottom).
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0

	## City + Kingdom: tuck behind nav (Kingdom screenshot is the reference).
	var gap: float = -PREVIEW_NAV_OVERLAP
	var overlap_px: float = PREVIEW_NAV_OVERLAP

	if bar != null and is_instance_valid(bar) and bar.size.x > 8.0 and host.size.y > 8.0:
		# Sibling-local: same parent Control under GameHUD CanvasLayer — no canvas inverse.
		# World uses SCALE fill → use true bar top. City may still letterbox → visible top.
		var nav_top_local: float = bar.position.y if world else _visible_nav_top_local(bar)
		var left: float = bar.position.x
		var right: float = bar.position.x + bar.size.x
		# Distance from parent bottom up to chat bottom (= nav top − gap).
		# Negative gap places chat bottom below nav top (tucked behind).
		var offset_b: float = nav_top_local - host.size.y - gap
		offset_left = left
		offset_right = right
		offset_bottom = offset_b
		offset_top = offset_b - height
		custom_minimum_size = Vector2(maxf(8.0, right - left), height)
	else:
		# Fallback only if bar missing — still bottom-anchored to host.
		offset_left = 0.0
		offset_right = host.size.x
		offset_bottom = -(BOTTOM_NAV_CLEARANCE - PREVIEW_NAV_OVERLAP)
		offset_top = offset_bottom - height
		custom_minimum_size = Vector2(maxf(8.0, host.size.x), height)

	if _panel != null:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_hit_button(overlap_px)

	_layout_guard = false
	layout_changed.emit(get_global_rect())


func _layout_hit_button(overlap_px: float) -> void:
	## Artwork may extend behind the nav; the hit target must stop at the nav's
	## visible top so Heroes/Wayfinder/Bag/Quest/Alliance/Map taps stay clean.
	if _hit_button == null or not is_instance_valid(_hit_button):
		return
	_hit_button.anchor_left = 0.0
	_hit_button.anchor_right = 1.0
	_hit_button.anchor_top = 0.0
	_hit_button.anchor_bottom = 1.0
	_hit_button.offset_left = 0.0
	_hit_button.offset_right = 0.0
	_hit_button.offset_top = 0.0
	_hit_button.offset_bottom = -maxf(0.0, overlap_px)
	_hit_button.mouse_filter = Control.MOUSE_FILTER_STOP


## Top of the actually drawn BottomBarTexture content in parent-local Y.
## Accounts for KEEP_ASPECT_CENTERED letterboxing inside the TextureRect.
func _visible_nav_top_local(bar: Control) -> float:
	var top: float = bar.position.y
	if not (bar is TextureRect):
		return top
	var tr: TextureRect = bar as TextureRect
	var tex: Texture2D = tr.texture
	if tex == null:
		return top
	var tex_size: Vector2 = tex.get_size()
	var rect_size: Vector2 = tr.size
	if tex_size.x <= 1.0 or tex_size.y <= 1.0 or rect_size.y <= 1.0:
		return top
	# stretch_mode 5 = KEEP_ASPECT_CENTERED on BottomBarTexture.
	if tr.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED \
		or tr.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT \
		or tr.stretch_mode == TextureRect.STRETCH_KEEP_CENTERED:
		var scale: float = minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
		var drawn_h: float = tex_size.y * scale
		var pad_y: float = maxf(0.0, (rect_size.y - drawn_h) * 0.5)
		return top + pad_y
	return top


func _find_bottom_nav_bar() -> Control:
	var host: Node = get_parent()
	if host != null:
		var sibling: Control = host.get_node_or_null("BottomBarTexture") as Control
		if sibling != null:
			return sibling
	var hud: Node = get_tree().get_first_node_in_group("game_hud") if get_tree() != null else null
	if hud != null:
		return hud.get_node_or_null("Control/BottomBarTexture") as Control
	return null


func _log_hit_diagnostics() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = get_global_rect()
	var hit_rect: Rect2 = _hit_button.get_global_rect() if _hit_button != null else Rect2()
	print("[ChatPreview] ready rect=%s hit=%s h=%.1f visible=%s z=%d anchors_bottom=%s" % [
		str(rect), str(hit_rect), rect.size.y, str(visible), z_index, str(anchor_bottom),
	])
	var bar: Control = _find_bottom_nav_bar()
	var host: Control = get_parent() as Control
	if bar != null and is_instance_valid(bar) and host != null:
		var nav: Rect2 = bar.get_global_rect()
		var vis_top_local: float = _visible_nav_top_local(bar)
		var vis_top_global: float = (host.get_global_transform_with_canvas() * Vector2(bar.position.x, vis_top_local)).y
		var dx_l: float = absf(rect.position.x - nav.position.x)
		var dx_r: float = absf(rect.end.x - nav.end.x)
		var gap: float = vis_top_global - rect.end.y
		print("[ChatPreview] nav align leftΔ=%.2f rightΔ=%.2f gap=%.2f nav=%s visTopLocal=%.1f hostH=%.1f" % [
			dx_l, dx_r, gap, str(nav), vis_top_local, host.size.y,
		])


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
	if cm.has_signal("dm_conversations_changed") and not cm.dm_conversations_changed.is_connected(_on_dm_conversations_changed):
		cm.dm_conversations_changed.connect(_on_dm_conversations_changed)
	if cm.has_signal("private_message_notify") and not cm.private_message_notify.is_connected(_on_private_message_notify):
		cm.private_message_notify.connect(_on_private_message_notify)


func _on_dm_conversations_changed() -> void:
	_refresh_from_latest()


func _on_private_message_notify(_peer: String, _display_name: String, _preview: String) -> void:
	_refresh_from_latest()


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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _hit_button != null and is_instance_valid(_hit_button):
		_hit_button.disabled = not visible
		_hit_button.mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
		_hit_button.visible = visible


func _refresh_from_latest() -> void:
	_bind_signals()
	var latest: RefCounted = _pick_newest_message()
	if latest == null:
		_channel_icon.text = "💬"
		_tag_label.visible = false
		_tag_label.text = ""
		_name_label.text = "Kingdom Chat"
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
	if cm.has_method("list_dm_conversations"):
		for conv: Variant in cm.list_dm_conversations():
			if typeof(conv) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = conv as Dictionary
			var peer: String = str(row.get("user_id", "")).strip_edges()
			if peer != "" and cm.has_method("get_private_messages"):
				pools.append(cm.get_private_messages(peer))
	elif cm.has_method("get_private_messages") and cm.has_method("get_active_dm_peer"):
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
	var is_alliance: bool = _message_is_alliance(msg)
	_channel_icon.text = "🛡" if is_alliance else "💬"

	var tag: String = str(msg.sender_alliance_tag).strip_edges()
	var name_text: String = str(msg.sender_display_name).strip_edges()
	if name_text == "":
		name_text = "Player"
	if str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM:
		_tag_label.visible = false
		_tag_label.text = ""
		_name_label.text = "SYSTEM"
		_body_label.text = _first_line(str(msg.text))
	else:
		if tag != "":
			_tag_label.visible = true
			_tag_label.text = "[%s]" % tag
		else:
			_tag_label.visible = false
			_tag_label.text = ""
		_name_label.text = name_text
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
			var label: String = str(payload.get("label", "Location"))
			if str(payload.get("target_type", "")) == "player_castle":
				return "🏰 %s" % label
			return "📍 %s" % label
		ChatMessageScript.TYPE_RALLY:
			var rp: Dictionary = msg.payload if typeof(msg.payload) == TYPE_DICTIONARY else {}
			return "⚔ Rally — %s" % str(rp.get("target_name", "Target"))
		_:
			return _first_line(str(msg.text))


func _first_line(text_value: String) -> String:
	var cleaned: String = text_value.strip_edges().replace("\n", " ")
	if cleaned.length() > 72:
		return cleaned.substr(0, 69) + "…"
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
	modulate = Color(1.12, 1.08, 0.96, 1.0)
	_pulse = create_tween()
	_pulse.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.35).set_ease(Tween.EASE_OUT)


func _on_hit_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			print("[ChatPreview] gui_input received: InputEventMouseButton pressed=%s" % str(mb.pressed))
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		print("[ChatPreview] gui_input received: InputEventScreenTouch pressed=%s idx=%d" % [str(st.pressed), st.index])


func _on_hit_pressed() -> void:
	_activate_from_input("button.pressed")


## Used by headless/input smoke tests to exercise activation without GUI pick.
func debug_activate_for_test() -> void:
	_activate_guard_ms = 0
	_activate_from_input("debug_activate_for_test")


func debug_reset_activate_guard() -> void:
	_activate_guard_ms = 0


func _activate_from_input(source: String) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _activate_guard_ms < 250:
		print("[ChatPreview] tap ignored (debounce) source=%s" % source)
		return
	_activate_guard_ms = now_ms
	print("[ChatPreview] tap activated source=%s" % source)
	open_chat_requested.emit()
