extends Control

## Full-screen Player Profile — Crownspire fantasy presentation.
## Opened from HUD avatar, Alliance Members, and chat context menus.

const PlayerAvatarCatalog = preload("res://Scripts/UI/PlayerAvatarCatalog.gd")

const COL_INK := Color(0.95, 0.92, 0.86, 1.0)
const COL_MUTED := Color(0.72, 0.68, 0.62, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.36, 1.0)
const COL_SAPPHIRE := Color(0.18, 0.22, 0.48, 1.0)
const COL_PURPLE := Color(0.28, 0.16, 0.42, 1.0)
const COL_PANEL := Color(0.08, 0.10, 0.18, 0.96)
const COL_BORDER := Color(0.72, 0.58, 0.28, 0.95)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_SLOT := Color(0.14, 0.16, 0.28, 0.92)

signal message_requested(user_id: String, display_name: String)
signal share_location_requested(profile: Dictionary)
signal closed

var _target_user_id: String = ""
var _is_self: bool = true
var _profile: Dictionary = {}
var _built: bool = false
var _root: VBoxContainer
var _hero_stage: Control
var _lower_card: PanelContainer
var _content: VBoxContainer
var _status: Label
var _avatar_tex: TextureRect
var _hero_tex: TextureRect
var _pending_avatar_id: String = ""

const EQUIP_SLOTS: Array[Dictionary] = [
	{"id": "head", "label": "Head", "pos": Vector2(0.08, 0.18)},
	{"id": "weapon", "label": "Weapon", "pos": Vector2(0.08, 0.42)},
	{"id": "accessory", "label": "Accessory", "pos": Vector2(0.08, 0.66)},
	{"id": "chest", "label": "Chest", "pos": Vector2(0.78, 0.18)},
	{"id": "legs", "label": "Legs", "pos": Vector2(0.78, 0.42)},
	{"id": "charm", "label": "Charm", "pos": Vector2(0.78, 0.66)},
]


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


func _friends_backend() -> Node:
	return get_node_or_null("/root/FriendsBackend")


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
	if not _is_self:
		var fb: Node = _friends_backend()
		if fb != null and fb.has_method("refresh_friends"):
			await fb.refresh_friends()
	_rebuild_content()


func _panel_style(bg: Color = COL_PANEL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _build() -> void:
	if _built:
		return
	_built = true
	for c in get_children():
		c.queue_free()

	# Soft sapphire / purple ambient background (full screen).
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.14, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(COL_PURPLE.r, COL_PURPLE.g, COL_PURPLE.b, 0.35)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 12
	_root.offset_right = -12
	_root.offset_top = 10
	_root.offset_bottom = -12
	_root.add_theme_constant_override("separation", 10)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Top bar
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 56)
	_root.add_child(header)
	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(110, 48)
	back.pressed.connect(on_close)
	header.add_child(back)
	var title := Label.new()
	title.text = "PLAYER PROFILE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", COL_GOLD)
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(110, 0)
	header.add_child(spacer)

	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	_status.add_theme_font_size_override("font_size", 13)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)

	# Hero stage (center)
	_hero_stage = Control.new()
	_hero_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_stage.custom_minimum_size = Vector2(0, 320)
	_root.add_child(_hero_stage)

	var stage_panel := PanelContainer.new()
	stage_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_panel.add_theme_stylebox_override("panel", _panel_style(Color(COL_SAPPHIRE.r, COL_SAPPHIRE.g, COL_SAPPHIRE.b, 0.55)))
	_hero_stage.add_child(stage_panel)

	var stage_inner := Control.new()
	stage_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_panel.add_child(stage_inner)

	_hero_tex = TextureRect.new()
	_hero_tex.set_anchors_preset(Control.PRESET_CENTER)
	_hero_tex.offset_left = -140
	_hero_tex.offset_right = 140
	_hero_tex.offset_top = -180
	_hero_tex.offset_bottom = 180
	_hero_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_inner.add_child(_hero_tex)

	for slot_v in EQUIP_SLOTS:
		var slot: Dictionary = slot_v
		var btn := Button.new()
		btn.text = str(slot.get("label", "Slot"))
		btn.custom_minimum_size = Vector2(92, 72)
		btn.focus_mode = Control.FOCUS_NONE
		var rel: Vector2 = slot.get("pos", Vector2(0.1, 0.2))
		btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.anchor_left = rel.x
		btn.anchor_top = rel.y
		btn.anchor_right = rel.x
		btn.anchor_bottom = rel.y
		btn.offset_right = 92
		btn.offset_bottom = 72
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = COL_SLOT
		slot_style.border_color = COL_GOLD
		slot_style.set_border_width_all(2)
		slot_style.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", slot_style)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func():
			_status.text = "%s equipment — Coming Soon (beta placeholder)" % str(slot.get("label", "Slot"))
		)
		stage_inner.add_child(btn)

	# Lower profile card
	_lower_card = PanelContainer.new()
	_lower_card.size_flags_vertical = Control.SIZE_SHRINK_END
	_lower_card.custom_minimum_size = Vector2(0, 280)
	_lower_card.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_lower_card)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lower_card.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
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
		# Phase 0B2-C: local self profile Citadel always from canonical castle (not stale mirror/server lag).
		# Remote profiles keep their supplied citadel_level unchanged.
		_profile["citadel_level"] = _local_canonical_castle_level()
		_status.text = ""
		print("[PlayerProfile] loaded user=%s power=%s (self)" % [
			str(_profile.get("user_id", "")), str(_profile.get("power", 0)),
		])
	else:
		print("[PlayerProfile] requesting public profile user=%s" % _target_user_id)
		var res: Dictionary = await ab.get_public_profile(_target_user_id)
		if bool(res.get("ok", false)) and typeof(res.get("profile")) == TYPE_DICTIONARY:
			_profile = res.get("profile", {})
			_status.text = ""
			print("[PlayerProfile] loaded user=%s power=%s" % [
				str(_profile.get("user_id", "")), str(_profile.get("power", 0)),
			])
		else:
			_profile = {"user_id": _target_user_id, "display_name": "Unknown"}
			_status.text = str(res.get("error", "Profile unavailable"))


func _local_canonical_castle_level() -> int:
	# Phase 0B2-C: local player Citadel/Castle completed level.
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(1, int(ConstructionState.get_canonical_building_level("castle")))
	return 1


func _local_fallback_profile() -> Dictionary:
	var nc: Node = _nakama_connection()
	var uid: String = nc.get_user_id() if nc != null else "local"
	var power: int = int(GameState.power) if has_node("/root/GameState") else 0
	var vip: int = int(GameState.vip_level) if has_node("/root/GameState") else 0
	return {
		"user_id": uid,
		"display_name": "Commander",
		"avatar_id": "avatar_01",
		"kingdom_id": "offline",
		"alliance_name": "",
		"alliance_tag": "",
		"power": power,
		"citadel_level": _local_canonical_castle_level(),
		"vip_level": vip,
		"online_status": "offline",
	}


func _rebuild_content() -> void:
	for c in _content.get_children():
		c.queue_free()

	var avatar_id: String = PlayerAvatarCatalog.normalize_id(str(_profile.get("avatar_id", "avatar_01")))
	_pending_avatar_id = avatar_id
	var hero_tex: Texture2D = PlayerAvatarCatalog.get_texture(avatar_id, 512)
	if _hero_tex != null:
		_hero_tex.texture = hero_tex

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	_content.add_child(identity)

	_avatar_tex = TextureRect.new()
	_avatar_tex.custom_minimum_size = Vector2(96, 96)
	_avatar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar_tex.texture = PlayerAvatarCatalog.get_texture(avatar_id, 256)
	identity.add_child(_avatar_tex)

	var id_col := VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.add_theme_constant_override("separation", 4)
	identity.add_child(id_col)

	var tag: String = str(_profile.get("alliance_tag", "")).strip_edges()
	var name_text: String = str(_profile.get("display_name", "Player"))
	var name_lbl := Label.new()
	name_lbl.text = "[%s] %s" % [tag, name_text] if tag != "" else name_text
	name_lbl.add_theme_color_override("font_color", COL_INK)
	name_lbl.add_theme_font_size_override("font_size", 22)
	id_col.add_child(name_lbl)

	if _is_self:
		var rename_btn := Button.new()
		rename_btn.text = "Rename"
		rename_btn.custom_minimum_size = Vector2(140, 40)
		rename_btn.pressed.connect(_on_rename_pressed)
		id_col.add_child(rename_btn)

	_add_stat_row(_content, "Power", _format_num(int(_profile.get("power", 0))))
	var highest: int = int(_profile.get("highest_power", _profile.get("power", 0)))
	_add_stat_row(_content, "Highest Power", _format_num(highest))
	_add_stat_row(_content, "Kills", _format_num(int(_profile.get("kills", 0))))
	_add_stat_row(_content, "Kingdom", str(_profile.get("kingdom_id", "—")))
	var alliance: String = str(_profile.get("alliance_name", "")).strip_edges()
	if alliance == "":
		alliance = "None"
	elif tag != "":
		alliance = "[%s] %s" % [tag, alliance]
	_add_stat_row(_content, "Alliance", alliance)
	_add_stat_row(_content, "Citadel", "Level %d" % int(_profile.get("citadel_level", 1)))
	_add_stat_row(_content, "VIP", "Level %d" % int(_profile.get("vip_level", 0)))
	var online: String = str(_profile.get("online_status", "offline"))
	_add_stat_row(_content, "Status", "Online" if online == "online" else "Offline")
	# Explicitly omit scout/military secrets (troops, resources, garrison, marches).

	_add_public_gear_section()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_content.add_child(actions)

	if _is_self:
		var avatar_btn := Button.new()
		avatar_btn.text = "Change Avatar"
		avatar_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		avatar_btn.custom_minimum_size = Vector2(0, 52)
		avatar_btn.pressed.connect(_show_avatar_picker)
		actions.add_child(avatar_btn)
		var share_self := Button.new()
		share_self.text = "Share Location"
		share_self.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share_self.custom_minimum_size = Vector2(0, 52)
		share_self.pressed.connect(_on_share_location)
		actions.add_child(share_self)
	else:
		var view_all := Button.new()
		view_all.text = "View Alliance"
		view_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view_all.custom_minimum_size = Vector2(0, 52)
		view_all.pressed.connect(_on_view_alliance)
		actions.add_child(view_all)
		var msg_btn := Button.new()
		msg_btn.text = "Message"
		msg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg_btn.custom_minimum_size = Vector2(0, 52)
		msg_btn.pressed.connect(func():
			message_requested.emit(str(_profile.get("user_id", "")), str(_profile.get("display_name", "Player")))
			on_close()
		)
		actions.add_child(msg_btn)

	if not _is_self:
		_add_friend_action_row()
		var share_other := Button.new()
		share_other.text = "Share Location"
		share_other.custom_minimum_size = Vector2(0, 48)
		share_other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share_other.pressed.connect(_on_share_location)
		_content.add_child(share_other)
		var mod_row := HBoxContainer.new()
		mod_row.add_theme_constant_override("separation", 8)
		_content.add_child(mod_row)
		var uid: String = str(_profile.get("user_id", ""))
		var fb_block: Node = _friends_backend()
		var blocked: bool = fb_block != null and fb_block.has_method("is_blocked") and bool(fb_block.is_blocked(uid))
		var block_btn := Button.new()
		block_btn.text = "Unblock" if blocked else "Block"
		block_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block_btn.custom_minimum_size = Vector2(0, 48)
		block_btn.pressed.connect(func(): await _on_block_pressed())
		mod_row.add_child(block_btn)
		var report_btn := Button.new()
		report_btn.text = "Report"
		report_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		report_btn.custom_minimum_size = Vector2(0, 48)
		report_btn.pressed.connect(_on_report_pressed)
		mod_row.add_child(report_btn)


func _show_avatar_picker() -> void:
	_add_section("Choose Avatar")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for aid in PlayerAvatarCatalog.AVATAR_IDS:
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(68, 68)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		btn.texture_normal = PlayerAvatarCatalog.get_texture(aid, 128)
		btn.tooltip_text = PlayerAvatarCatalog.get_label(aid)
		if aid == _pending_avatar_id:
			btn.modulate = Color(1.12, 1.08, 0.9)
		btn.pressed.connect(_on_avatar_picked.bind(aid))
		grid.add_child(btn)


func _on_view_alliance() -> void:
	var alliance_id: String = str(_profile.get("alliance_id", "")).strip_edges()
	if alliance_id == "":
		_status.text = "This commander has no Alliance."
		return
	on_close()
	var hud := get_tree().root.find_child("GameHUD", true, false)
	if hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null and mgr.has_method("open_screen"):
			mgr.call("open_screen", "AllianceScreen")


func _add_friend_action_row() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var fb: Node = _friends_backend()
	if uid == "" or fb == null or not fb.has_method("get_relationship"):
		return
	var rel: String = str(fb.get_relationship(uid))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	match rel:
		"friend":
			var friends_lbl := Button.new()
			friends_lbl.text = "Friends"
			friends_lbl.disabled = true
			friends_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			friends_lbl.custom_minimum_size = Vector2(0, 48)
			row.add_child(friends_lbl)
			var remove_btn := Button.new()
			remove_btn.text = "Remove Friend"
			remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			remove_btn.custom_minimum_size = Vector2(0, 48)
			remove_btn.pressed.connect(func(): await _friend_op("remove"))
			row.add_child(remove_btn)
		"invite_sent":
			var pending := Button.new()
			pending.text = "Pending"
			pending.disabled = true
			pending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pending.custom_minimum_size = Vector2(0, 48)
			row.add_child(pending)
			var cancel_btn := Button.new()
			cancel_btn.text = "Cancel Request"
			cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cancel_btn.custom_minimum_size = Vector2(0, 48)
			cancel_btn.pressed.connect(func(): await _friend_op("cancel"))
			row.add_child(cancel_btn)
		"invite_received":
			var accept_btn := Button.new()
			accept_btn.text = "Accept Friend"
			accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			accept_btn.custom_minimum_size = Vector2(0, 48)
			accept_btn.pressed.connect(func(): await _friend_op("accept"))
			row.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = "Decline"
			decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			decline_btn.custom_minimum_size = Vector2(0, 48)
			decline_btn.pressed.connect(func(): await _friend_op("decline"))
			row.add_child(decline_btn)
		"blocked":
			var blocked_lbl := Button.new()
			blocked_lbl.text = "Blocked"
			blocked_lbl.disabled = true
			blocked_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			blocked_lbl.custom_minimum_size = Vector2(0, 48)
			row.add_child(blocked_lbl)
		_:
			var add_btn := Button.new()
			add_btn.text = "Add Friend"
			add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			add_btn.custom_minimum_size = Vector2(0, 48)
			add_btn.pressed.connect(func(): await _friend_op("add"))
			row.add_child(add_btn)


func _friend_op(op: String) -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var fb: Node = _friends_backend()
	if uid == "" or fb == null:
		return
	var result: Dictionary = {}
	match op:
		"add":
			result = await fb.send_friend_request(uid)
		"accept":
			result = await fb.accept_friend_request(uid)
		"decline":
			result = await fb.decline_friend_request(uid)
		"cancel":
			result = await fb.cancel_friend_request(uid)
		"remove":
			result = await fb.remove_friend(uid)
		_:
			return
	if bool(result.get("ok", false)):
		_status.text = "Friends updated."
		await _open_async()
	else:
		_status.text = str(result.get("error", "Friends action failed."))


func _on_block_pressed() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var fb: Node = _friends_backend()
	if uid == "" or fb == null:
		_status.text = "Block unavailable."
		return
	var result: Dictionary
	if bool(fb.is_blocked(uid)):
		result = await fb.unblock_player(uid)
		_status.text = "Player unblocked." if bool(result.get("ok", false)) else str(result.get("error", "Unblock failed."))
	else:
		result = await fb.block_player(uid)
		_status.text = "Player blocked." if bool(result.get("ok", false)) else str(result.get("error", "Block failed."))
	if bool(result.get("ok", false)):
		await _open_async()


func _on_report_pressed() -> void:
	## Profile report uses chat_report evidence path with synthetic message/channel ids.
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	if uid == "" or not has_node("/root/AllianceBackend"):
		_status.text = "Report unavailable."
		return
	var ab: Node = _alliance_backend()
	var reasons: Array = ab.REPORT_REASONS.duplicate() if ab != null else ["spam", "harassment", "other"]
	_add_section("Report reason")
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	_content.add_child(grid)
	for reason_v in reasons:
		var reason: String = str(reason_v)
		var btn := Button.new()
		btn.text = reason.replace("_", " ").capitalize()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(func(): await _submit_profile_report(uid, reason))
		grid.add_child(btn)


func _submit_profile_report(user_id: String, reason: String) -> void:
	if not has_node("/root/AllianceBackend"):
		return
	var payload := {
		"reported_user_id": user_id,
		"message_id": "profile_%s_%d" % [user_id, int(Time.get_unix_time_from_system())],
		"channel_id": "player_profile",
		"message_type": "PROFILE",
		"message_text": "Profile report: %s" % str(_profile.get("display_name", "Player")),
		"create_time": Time.get_datetime_string_from_system(true),
		"reason": reason,
	}
	var result: Dictionary = await _alliance_backend().submit_chat_report(payload)
	if bool(result.get("ok", false)):
		_status.text = "Report submitted for review."
	else:
		_status.text = str(result.get("error", "Report failed."))


func _add_public_gear_section() -> void:
	_add_section("Public Gear")
	var gear: Array = []
	if typeof(_profile.get("public_equipment")) == TYPE_ARRAY:
		gear = _profile.get("public_equipment", [])
	if gear.is_empty():
		var empty := Label.new()
		empty.text = "No public gear published."
		empty.add_theme_color_override("font_color", COL_MUTED)
		empty.add_theme_font_size_override("font_size", 13)
		_content.add_child(empty)
		return
	for item_v in gear:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var slot: String = str(item.get("slot", item.get("gear_slot", "Gear")))
		var item_name: String = str(item.get("name", item.get("display_name", "Item")))
		var rarity: String = str(item.get("rarity", ""))
		var level: int = int(item.get("level", 0))
		var enhance: int = int(item.get("enhancement", item.get("refine", 0)))
		var line := "%s — %s" % [slot.capitalize(), item_name]
		if rarity != "":
			line += " · %s" % rarity
		if level > 0:
			line += " · Lv.%d" % level
		if enhance > 0:
			line += " · +%d" % enhance
		var row := Label.new()
		row.text = line
		row.add_theme_color_override("font_color", COL_INK)
		row.add_theme_font_size_override("font_size", 13)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(row)


func _on_share_location() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var x: float = float(_profile.get("world_x", 0))
	var y: float = float(_profile.get("world_y", 0))
	if x == 0.0 and y == 0.0 and has_node("/root/MarchState") and MarchState.has_method("get_castle_world_position"):
		var pos: Vector2 = MarchState.get_castle_world_position()
		x = pos.x
		y = pos.y
	if not has_node("/root/ChatManager"):
		_status.text = "Chat unavailable."
		return
	var cm: Node = get_node("/root/ChatManager")
	var kid: String = str(_profile.get("kingdom_id", ""))
	if kid == "" and cm.has_method("get_kingdom_id"):
		kid = str(cm.get_kingdom_id())
	var name_text: String = str(_profile.get("display_name", "Lord"))
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
	print("[CastlePopup] share requested user=%s kingdom=%s x=%s y=%s" % [uid, kid, str(x), str(y)])
	_status.text = "Sharing to Kingdom Chat…"
	var result: Dictionary = await cm.send_map_location(payload, "kingdom")
	if bool(result.get("ok", false)):
		_status.text = "Castle location shared to Kingdom Chat."
		_status.add_theme_color_override("font_color", COL_OK)
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(result.get("error", "Share failed."))


func _add_stat_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
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
	panel.add_theme_stylebox_override("panel", _panel_style())
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
