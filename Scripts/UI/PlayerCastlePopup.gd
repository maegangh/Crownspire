extends Control

## Compact Kingdom Map castle / player action popup.
## Valid actions only: Profile, Message, Share Location (Kingdom / Alliance when available).
## Attack / Rally are omitted until player-castle PvP exists.

const TOP_SAFE := 188.0
const BOTTOM_SAFE := 200.0
const PANEL_W := 560.0

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_PANEL := Color(0.09, 0.08, 0.13, 0.97)
const COL_BORDER := Color(0.72, 0.58, 0.30, 0.95)

var _payload: Dictionary = {}
var _is_self: bool = false
var _built: bool = false

var _dim: ColorRect
var _window: PanelContainer
var _title: Label
var _subtitle: Label
var _coords: Label
var _status: Label
var _actions: VBoxContainer
var _share_row: HBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 120
	_build()


func open_for_castle(payload: Dictionary) -> void:
	_payload = payload.duplicate(true)
	var uid: String = str(_payload.get("user_id", "")).strip_edges()
	var local_id: String = ""
	if has_node("/root/NakamaConnection"):
		local_id = str(get_node("/root/NakamaConnection").get_user_id())
	_is_self = uid != "" and uid == local_id
	print("[CastlePopup] selected user=%s kingdom=%s x=%s y=%s" % [
		uid,
		str(_payload.get("kingdom_id", "")),
		str(_payload.get("world_x", _payload.get("x", 0))),
		str(_payload.get("world_y", _payload.get("y", 0))),
	])
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	print("[PlayerCastlePopup] opened owner=%s self=%s" % [uid, str(_is_self)])


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _share_row != null:
		_share_row.visible = false


func _build() -> void:
	if _built:
		return
	_built = true
	for c in get_children():
		c.queue_free()

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.04, 0.03, 0.06, 0.45)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_panel()
		elif e is InputEventScreenTouch and e.pressed:
			close_panel()
	)
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "CastleWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -PANEL_W * 0.5
	_window.offset_right = PANEL_W * 0.5
	_window.offset_top = -210.0
	_window.offset_bottom = 210.0
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_window.add_theme_stylebox_override("panel", style)
	add_child(_window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_window.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", COL_GOLD)
	_title.add_theme_font_size_override("font_size", 22)
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(48, 44)
	close_btn.pressed.connect(close_panel)
	header.add_child(close_btn)

	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color", COL_MUTED)
	_subtitle.add_theme_font_size_override("font_size", 14)
	box.add_child(_subtitle)

	_coords = Label.new()
	_coords.add_theme_color_override("font_color", COL_INK)
	_coords.add_theme_font_size_override("font_size", 15)
	box.add_child(_coords)

	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	box.add_child(_actions)

	_share_row = HBoxContainer.new()
	_share_row.visible = false
	_share_row.add_theme_constant_override("separation", 8)
	box.add_child(_share_row)


func _refresh() -> void:
	var tag: String = str(_payload.get("alliance_tag", "")).strip_edges()
	var name_text: String = str(_payload.get("display_name", "Lord")).strip_edges()
	if name_text == "":
		name_text = "Lord"
	_title.text = "[%s] %s" % [tag, name_text] if tag != "" else name_text
	var power: int = int(_payload.get("power", 0))
	var citadel: int = int(_payload.get("citadel_level", 1))
	_subtitle.text = "Citadel Lv.%d · Power %s%s" % [
		maxi(1, citadel),
		_format_num(power),
		" · Your Castle" if _is_self else "",
	]
	var x: float = float(_payload.get("world_x", _payload.get("x", 0)))
	var y: float = float(_payload.get("world_y", _payload.get("y", 0)))
	_coords.text = "X:%.0f   Y:%.0f" % [x, y]
	_status.text = ""
	_share_row.visible = false
	for c in _actions.get_children():
		c.queue_free()
	for c in _share_row.get_children():
		c.queue_free()

	_add_action("Profile", _on_profile)
	if not _is_self:
		_add_action("Message", _on_message)
	_add_action("Share Location", _on_share_pressed)
	# Attack / Rally intentionally omitted — no player-castle PvP path yet.


func _add_action(label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.14, 0.22, 0.96)
	st.border_color = COL_BORDER
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st)
	btn.add_theme_stylebox_override("pressed", st)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.pressed.connect(cb)
	_actions.add_child(btn)


func _on_profile() -> void:
	var uid: String = str(_payload.get("user_id", "")).strip_edges()
	print("[CastlePopup] profile requested user=%s" % uid)
	close_panel()
	var hud := _game_hud()
	if hud != null and hud.has_method("open_player_profile"):
		if _is_self or uid == "":
			hud.call("open_player_profile", "")
		else:
			hud.call("open_player_profile", uid)


func _on_message() -> void:
	var uid: String = str(_payload.get("user_id", "")).strip_edges()
	var name_text: String = str(_payload.get("display_name", "Player"))
	close_panel()
	var hud := _game_hud()
	if hud != null and hud.has_method("open_private_chat"):
		hud.call("open_private_chat", uid, name_text)


func _on_share_pressed() -> void:
	# Reveal channel chooser (Kingdom / Alliance when available).
	for c in _share_row.get_children():
		c.queue_free()
	_share_row.visible = true
	var kingdom_btn := Button.new()
	kingdom_btn.text = "Kingdom Chat"
	kingdom_btn.focus_mode = Control.FOCUS_NONE
	kingdom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kingdom_btn.custom_minimum_size = Vector2(0, 48)
	kingdom_btn.pressed.connect(func(): _share_to("kingdom"))
	_share_row.add_child(kingdom_btn)

	var alliance_ok: bool = false
	if has_node("/root/ChatManager") and ChatManager.has_method("is_alliance_chat_available"):
		alliance_ok = bool(ChatManager.is_alliance_chat_available())
	if alliance_ok:
		var ally_btn := Button.new()
		ally_btn.text = "Alliance Chat"
		ally_btn.focus_mode = Control.FOCUS_NONE
		ally_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ally_btn.custom_minimum_size = Vector2(0, 48)
		ally_btn.pressed.connect(func(): _share_to("alliance"))
		_share_row.add_child(ally_btn)
	_status.text = "Choose where to share this castle location."


func _share_to(channel_kind: String) -> void:
	if not has_node("/root/ChatManager"):
		_status.text = "Chat unavailable."
		return
	var cm: Node = get_node("/root/ChatManager")
	var kid: String = cm.get_kingdom_id() if cm.has_method("get_kingdom_id") else str(_payload.get("kingdom_id", ""))
	var x: float = float(_payload.get("world_x", _payload.get("x", 0)))
	var y: float = float(_payload.get("world_y", _payload.get("y", 0)))
	var uid: String = str(_payload.get("user_id", "")).strip_edges()
	var name_text: String = str(_payload.get("display_name", "Lord")).strip_edges()
	if name_text == "":
		name_text = "Lord"
	print("[CastlePopup] share requested user=%s kingdom=%s x=%s y=%s channel=%s" % [
		uid, kid, str(x), str(y), channel_kind,
	])
	var payload := {
		"kingdom_id": kid,
		"x": x,
		"y": y,
		"label": "[Castle] %s" % name_text,
		"target_type": "player_castle",
		"target_id": uid,
		"owner_user_id": uid,
		"display_name": name_text,
	}
	_status.text = "Sharing…"
	var result: Dictionary = await cm.send_map_location(payload, channel_kind)
	if bool(result.get("ok", false)):
		print("[Chat] castle location sent channel=%s" % channel_kind)
		_status.text = "Shared to %s chat." % channel_kind.capitalize()
		_share_row.visible = false
	else:
		_status.text = str(result.get("error", "Share failed."))


func _game_hud() -> Node:
	var hud := get_tree().get_first_node_in_group("game_hud") if get_tree() != null else null
	if hud != null:
		return hud
	return get_tree().root.find_child("GameHUD", true, false) if get_tree() != null else null


func _format_num(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)
