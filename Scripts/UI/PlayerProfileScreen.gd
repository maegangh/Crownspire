extends Control

## Player Profile modal — self and other players.
## Opened from HUD avatar, Alliance Members, and chat context menus.

const PlayerAvatarCatalog = preload("res://scripts/UI/PlayerAvatarCatalog.gd")

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_PANEL := Color(0.09, 0.07, 0.12, 0.97)
const COL_BORDER := Color(0.62, 0.50, 0.30, 0.95)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)

signal message_requested(user_id: String, display_name: String)
signal closed

var _target_user_id: String = ""
var _is_self: bool = true
var _profile: Dictionary = {}
var _built: bool = false
var _dim: ColorRect
var _window: PanelContainer
var _content: VBoxContainer
var _status: Label
var _avatar_tex: TextureRect
var _pending_avatar_id: String = ""


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func open_self() -> void:
	_target_user_id = ""
	_is_self = true
	await _open_async()


func open_user(user_id: String) -> void:
	_target_user_id = user_id.strip_edges()
	var nc: Node = _nakama_connection()
	var local_id: String = nc.get_user_id() if nc != null else ""
	_is_self = _target_user_id == "" or _target_user_id == local_id
	await _open_async()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


func _open_async() -> void:
	_build()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_status.text = "Loading…"
	await _load_profile()
	_rebuild_content()


func _build() -> void:
	if _built:
		return
	_built = true
	for c in get_children():
		c.queue_free()

	_dim = ColorRect.new()
	_dim.color = Color(0.04, 0.03, 0.06, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_close()
	)
	add_child(_dim)

	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -300
	_window.offset_right = 300
	_window.offset_top = -420
	_window.offset_bottom = 420
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_window.add_theme_stylebox_override("panel", style)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_window.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Player Profile"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 22)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.pressed.connect(on_close)
	header.add_child(close_btn)

	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	_status.add_theme_font_size_override("font_size", 13)
	root.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)


func _load_profile() -> void:
	var ab: Node = _alliance_backend()
	if ab == null:
		_profile = _local_fallback_profile()
		_status.text = "Offline profile"
		return
	if _is_self:
		if ab.has_method("sync_identity_from_local"):
			await ab.sync_identity_from_local()
		await ab.refresh_profile()
		_profile = ab.get_profile()
		if _profile.is_empty():
			_profile = _local_fallback_profile()
		_status.text = ""
	else:
		var res: Dictionary = await ab.get_public_profile(_target_user_id)
		if bool(res.get("ok", false)) and typeof(res.get("profile")) == TYPE_DICTIONARY:
			_profile = res.get("profile", {})
			_status.text = ""
		else:
			_profile = {"user_id": _target_user_id, "display_name": "Unknown"}
			_status.text = str(res.get("error", "Profile unavailable"))


func _local_fallback_profile() -> Dictionary:
	var nc: Node = _nakama_connection()
	var uid: String = nc.get_user_id() if nc != null else "local"
	var power: int = int(GameState.power) if has_node("/root/GameState") else 0
	var citadel: int = int(GameState.castle_level) if has_node("/root/GameState") else 1
	var vip: int = int(GameState.vip_level) if has_node("/root/GameState") else 0
	return {
		"user_id": uid,
		"display_name": "Commander",
		"avatar_id": "avatar_01",
		"kingdom_id": "offline",
		"alliance_name": "",
		"alliance_tag": "",
		"power": power,
		"citadel_level": citadel,
		"vip_level": vip,
		"online_status": "offline",
	}


func _rebuild_content() -> void:
	for c in _content.get_children():
		c.queue_free()

	var avatar_id: String = PlayerAvatarCatalog.normalize_id(str(_profile.get("avatar_id", "avatar_01")))
	_pending_avatar_id = avatar_id

	_content.add_theme_constant_override("separation", 8)

	_avatar_tex = TextureRect.new()
	_avatar_tex.custom_minimum_size = Vector2(168, 168)
	_avatar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar_tex.texture = PlayerAvatarCatalog.get_texture(avatar_id, 256)
	_avatar_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_avatar_tex)

	var name_lbl := Label.new()
	name_lbl.text = str(_profile.get("display_name", "Player"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", COL_INK)
	name_lbl.add_theme_font_size_override("font_size", 26)
	_content.add_child(name_lbl)

	if _is_self:
		var rename_btn := Button.new()
		rename_btn.text = "Rename (Free Beta)"
		rename_btn.custom_minimum_size = Vector2(220, 42)
		rename_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rename_btn.pressed.connect(_on_rename_pressed)
		_content.add_child(rename_btn)

		_add_section("Choose Avatar")
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_content.add_child(grid)
		for aid in PlayerAvatarCatalog.AVATAR_IDS:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 2)
			var btn := TextureButton.new()
			btn.custom_minimum_size = Vector2(72, 72)
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
			btn.texture_normal = PlayerAvatarCatalog.get_texture(aid, 128)
			btn.tooltip_text = PlayerAvatarCatalog.get_label(aid)
			if aid == avatar_id:
				btn.modulate = Color(1.12, 1.08, 0.9)
			btn.pressed.connect(_on_avatar_picked.bind(aid))
			cell.add_child(btn)
			var cap := Label.new()
			cap.text = PlayerAvatarCatalog.get_label(aid)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cap.add_theme_font_size_override("font_size", 11)
			cap.add_theme_color_override("font_color", COL_MUTED)
			cell.add_child(cap)
			grid.add_child(cell)

	_add_section("Commander Info")
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	_content.add_child(stats)
	_add_stat_row(stats, "⚔", "Power", _format_num(int(_profile.get("power", 0))))
	_add_stat_row(stats, "🗺", "Kingdom", str(_profile.get("kingdom_id", "—")))
	var alliance: String = str(_profile.get("alliance_name", "")).strip_edges()
	var tag: String = str(_profile.get("alliance_tag", "")).strip_edges()
	if alliance == "":
		alliance = "None"
	elif tag != "":
		alliance = "[%s] %s" % [tag, alliance]
	_add_stat_row(stats, "🛡", "Alliance", alliance)
	_add_stat_row(stats, "🏛", "Citadel", "Level %d" % int(_profile.get("citadel_level", 1)))
	_add_stat_row(stats, "✦", "VIP", "Level %d" % int(_profile.get("vip_level", 0)))
	_add_stat_row(stats, "🆔", "Player ID", str(_profile.get("user_id", "—")))

	if not _is_self:
		var online: String = str(_profile.get("online_status", "offline"))
		_add_stat_row(stats, "●", "Status", "Online" if online == "online" else "Offline")
		var msg_btn := Button.new()
		msg_btn.text = "Message"
		msg_btn.custom_minimum_size = Vector2(0, 52)
		msg_btn.pressed.connect(func():
			message_requested.emit(str(_profile.get("user_id", "")), str(_profile.get("display_name", "Player")))
			on_close()
		)
		_content.add_child(msg_btn)


func _add_stat_row(parent: VBoxContainer, icon: String, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := Label.new()
	ic.text = icon
	ic.custom_minimum_size = Vector2(28, 0)
	ic.add_theme_font_size_override("font_size", 16)
	row.add_child(ic)
	var a := Label.new()
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_color_override("font_color", COL_MUTED)
	a.add_theme_font_size_override("font_size", 14)
	row.add_child(a)
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_color_override("font_color", COL_INK)
	b.add_theme_font_size_override("font_size", 14)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	parent.add_child(row)


func _add_section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COL_GOLD)
	l.add_theme_font_size_override("font_size", 16)
	_content.add_child(l)


func _add_row(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var a := Label.new()
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_color_override("font_color", COL_MUTED)
	row.add_child(a)
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_color_override("font_color", COL_INK)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	_content.add_child(row)


func _format_num(value: int) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)


func _on_rename_pressed() -> void:
	var ab: Node = _alliance_backend()
	if ab == null or not ab.has_method("set_display_name"):
		_status.text = "Rename unavailable offline."
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Rename"
	dialog.dialog_text = "Enter a new display name (3–24 chars). Free during beta."
	var edit := LineEdit.new()
	edit.text = str(_profile.get("display_name", ""))
	edit.custom_minimum_size = Vector2(280, 40)
	dialog.add_child(edit)
	# Godot AcceptDialog doesn't easily host LineEdit — use prompt pattern via Window.
	dialog.queue_free()
	_prompt_rename()


func _prompt_rename() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 20
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -90
	panel.offset_bottom = 90
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var tip := Label.new()
	tip.text = "New name (free beta)"
	tip.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(tip)
	var edit := LineEdit.new()
	edit.text = str(_profile.get("display_name", ""))
	edit.custom_minimum_size = Vector2(0, 40)
	box.add_child(edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func(): overlay.queue_free())
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = "Save"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func():
		var name: String = edit.text.strip_edges()
		overlay.queue_free()
		_apply_rename(name)
	)
	row.add_child(ok)
	edit.grab_focus()


func _apply_rename(name: String) -> void:
	var ab: Node = _alliance_backend()
	_status.text = "Saving name…"
	var res: Dictionary = await ab.set_display_name(name)
	if bool(res.get("ok", false)):
		_status.text = "Name updated."
		_status.add_theme_color_override("font_color", COL_OK)
		await _load_profile()
		_rebuild_content()
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(res.get("error", "Rename failed"))


func _on_avatar_picked(avatar_id: String) -> void:
	var ab: Node = _alliance_backend()
	if ab == null or not ab.has_method("update_player_identity"):
		_status.text = "Avatar save unavailable."
		return
	_status.text = "Saving avatar…"
	var res: Dictionary = await ab.update_player_identity({"avatar_id": avatar_id})
	if bool(res.get("ok", false)):
		_status.text = "Avatar updated."
		_status.add_theme_color_override("font_color", COL_OK)
		await _load_profile()
		_rebuild_content()
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(res.get("error", "Avatar save failed"))
