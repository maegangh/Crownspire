extends Control

## Full-screen Player Profile — Crownspire fantasy presentation.
## Opened from HUD avatar, Alliance Members, and chat context menus.
## Mobile layout: Profile | Stats | Settings tabs (do not cram everything onto one page).

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
const COL_TAB_IDLE := Color(0.12, 0.12, 0.18, 0.95)
const COL_TAB_ACTIVE := Color(0.22, 0.18, 0.10, 0.98)

## Mobile-readable typography (viewport px @ 720×1280 stretch).
const FONT_TITLE: int = 24
const FONT_NAME: int = 22
const FONT_NAV: int = 18
const FONT_TAB: int = 18
const FONT_BUTTON: int = 18
const FONT_SECTION: int = 18
const FONT_BODY: int = 18
const FONT_SECONDARY: int = 16
const TOUCH_H: int = 52
const TOUCH_H_SM: int = 48
const SLOT_W: int = 108
const SLOT_H: int = 84
const HERO_MIN_H: int = 420

const TAB_PROFILE: String = "profile"
const TAB_STATS: String = "stats"
const TAB_SETTINGS: String = "settings"

signal message_requested(user_id: String, display_name: String)
signal share_location_requested(profile: Dictionary)
signal closed

var _target_user_id: String = ""
var _is_self: bool = true
var _profile: Dictionary = {}
var _built: bool = false
var _active_tab: String = TAB_PROFILE

var _root: VBoxContainer
var _status: Label
var _header_back: Button = null
var _header_title: Label = null
var _header_close: Button = null

var _tab_row: HBoxContainer = null
var _tab_btns: Dictionary = {} # tab_id -> Button

var _pages: Control = null
var _page_profile: VBoxContainer = null
var _page_stats: VBoxContainer = null
var _page_settings: VBoxContainer = null

var _hero_stage: Control = null
var _hero_tex: TextureRect = null
var _identity_box: VBoxContainer = null
var _profile_actions: VBoxContainer = null
var _profile_extra: VBoxContainer = null

var _stats_scroll: ScrollContainer = null
var _stats_content: VBoxContainer = null
var _settings_scroll: ScrollContainer = null
var _settings_content: VBoxContainer = null

var _avatar_tex: TextureRect = null
var _pending_avatar_id: String = ""
var _lang_option: OptionButton = null
var _lang_label: Label = null
var _settings_title: Label = null
var _suppress_lang_signal: bool = false
var _equip_slot_btns: Array = [] # Button nodes for locale refresh

const EQUIP_SLOTS: Array[Dictionary] = [
	{"id": "head", "label_key": "PROFILE_SLOT_HEAD", "pos": Vector2(0.08, 0.18)},
	{"id": "weapon", "label_key": "PROFILE_SLOT_WEAPON", "pos": Vector2(0.08, 0.42)},
	{"id": "accessory", "label_key": "PROFILE_SLOT_ACCESSORY", "pos": Vector2(0.08, 0.66)},
	{"id": "chest", "label_key": "PROFILE_SLOT_CHEST", "pos": Vector2(0.78, 0.18)},
	{"id": "legs", "label_key": "PROFILE_SLOT_LEGS", "pos": Vector2(0.78, 0.42)},
	{"id": "charm", "label_key": "PROFILE_SLOT_CHARM", "pos": Vector2(0.78, 0.66)},
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
	if has_node("/root/LocaleSettings") and not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)


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
	_status.text = tr("PROFILE_LOADING")
	_active_tab = TAB_PROFILE
	await _load_profile()
	if not _is_self:
		var fb: Node = _friends_backend()
		if fb != null and fb.has_method("refresh_friends"):
			await fb.refresh_friends()
	_rebuild_content()
	_show_tab(TAB_PROFILE)


func _panel_style(bg: Color = COL_PANEL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _style_button(btn: Button, font_size: int = FONT_BUTTON, min_h: int = TOUCH_H) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = Vector2(maxi(int(btn.custom_minimum_size.x), 0), min_h)
	btn.clip_text = false


func _style_label(lbl: Label, font_size: int, color: Color = COL_INK) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.clip_text = false


func _tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_TAB_ACTIVE if active else COL_TAB_IDLE
	style.border_color = COL_GOLD if active else Color(0.45, 0.40, 0.28, 0.85)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _build() -> void:
	if _built:
		return
	_built = true
	for c in get_children():
		c.queue_free()

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

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, TOUCH_H)
	header.add_theme_constant_override("separation", 8)
	_root.add_child(header)
	_header_back = Button.new()
	_header_back.text = "← %s" % tr("UI_BACK")
	_header_back.custom_minimum_size = Vector2(120, TOUCH_H)
	_style_button(_header_back, FONT_NAV, TOUCH_H)
	_header_back.pressed.connect(on_close)
	header.add_child(_header_back)
	_header_title = Label.new()
	_header_title.text = tr("UI_PLAYER_PROFILE")
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_header_title, FONT_TITLE, COL_GOLD)
	header.add_child(_header_title)
	_header_close = Button.new()
	_header_close.text = tr("UI_CLOSE")
	_header_close.custom_minimum_size = Vector2(120, TOUCH_H)
	_style_button(_header_close, FONT_NAV, TOUCH_H)
	_header_close.pressed.connect(on_close)
	header.add_child(_header_close)

	_status = Label.new()
	_style_label(_status, FONT_SECONDARY, COL_MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)

	# Tabs
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	_tab_row.custom_minimum_size = Vector2(0, TOUCH_H)
	_root.add_child(_tab_row)
	_tab_btns.clear()
	_add_tab_button(TAB_PROFILE, tr("UI_TAB_PROFILE"))
	_add_tab_button(TAB_STATS, tr("UI_TAB_STATS"))
	_add_tab_button(TAB_SETTINGS, tr("UI_TAB_SETTINGS"))

	# Pages host
	_pages = Control.new()
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_pages)

	_page_profile = _make_page_vbox()
	_pages.add_child(_page_profile)
	_page_stats = _make_page_vbox()
	_pages.add_child(_page_stats)
	_page_settings = _make_page_vbox()
	_pages.add_child(_page_settings)

	_build_profile_page_shell()
	_build_stats_page_shell()
	_build_settings_page_shell()
	_show_tab(TAB_PROFILE)


func _make_page_vbox() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	page.visible = false
	return page


func _add_tab_button(tab_id: String, label: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, FONT_TAB, TOUCH_H)
	btn.add_theme_stylebox_override("normal", _tab_style(false))
	btn.add_theme_stylebox_override("pressed", _tab_style(true))
	btn.add_theme_stylebox_override("hover", _tab_style(false))
	btn.pressed.connect(_on_tab_pressed.bind(tab_id))
	_tab_row.add_child(btn)
	_tab_btns[tab_id] = btn


func _on_tab_pressed(tab_id: String) -> void:
	_show_tab(tab_id)


func _show_tab(tab_id: String) -> void:
	_active_tab = tab_id
	if _page_profile != null:
		_page_profile.visible = tab_id == TAB_PROFILE
	if _page_stats != null:
		_page_stats.visible = tab_id == TAB_STATS
	if _page_settings != null:
		_page_settings.visible = tab_id == TAB_SETTINGS
	for id: Variant in _tab_btns.keys():
		var btn: Button = _tab_btns[id] as Button
		if btn == null:
			continue
		var active: bool = str(id) == tab_id
		btn.button_pressed = active
		btn.add_theme_stylebox_override("normal", _tab_style(active))
		btn.add_theme_stylebox_override("pressed", _tab_style(true))
		btn.add_theme_color_override("font_color", COL_GOLD if active else COL_INK)


func _build_profile_page_shell() -> void:
	_identity_box = VBoxContainer.new()
	_identity_box.add_theme_constant_override("separation", 6)
	_page_profile.add_child(_identity_box)

	# Large hero + equipment — owns most of the Profile tab height.
	_hero_stage = Control.new()
	_hero_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_stage.custom_minimum_size = Vector2(0, HERO_MIN_H)
	_page_profile.add_child(_hero_stage)

	var stage_panel := PanelContainer.new()
	stage_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_panel.add_theme_stylebox_override("panel", _panel_style(Color(COL_SAPPHIRE.r, COL_SAPPHIRE.g, COL_SAPPHIRE.b, 0.55)))
	_hero_stage.add_child(stage_panel)

	var stage_inner := Control.new()
	stage_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_panel.add_child(stage_inner)

	_hero_tex = TextureRect.new()
	_hero_tex.set_anchors_preset(Control.PRESET_CENTER)
	_hero_tex.offset_left = -150
	_hero_tex.offset_right = 150
	_hero_tex.offset_top = -190
	_hero_tex.offset_bottom = 190
	_hero_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_inner.add_child(_hero_tex)

	_equip_slot_btns.clear()
	for slot_v in EQUIP_SLOTS:
		var slot: Dictionary = slot_v
		var label_key: String = str(slot.get("label_key", "PROFILE_SLOT_GENERIC"))
		var btn := Button.new()
		btn.set_meta("label_key", label_key)
		btn.text = tr(label_key)
		btn.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = false
		var rel: Vector2 = slot.get("pos", Vector2(0.1, 0.2))
		btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.anchor_left = rel.x
		btn.anchor_top = rel.y
		btn.anchor_right = rel.x
		btn.anchor_bottom = rel.y
		btn.offset_right = float(SLOT_W)
		btn.offset_bottom = float(SLOT_H)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = COL_SLOT
		slot_style.border_color = COL_GOLD
		slot_style.set_border_width_all(2)
		slot_style.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", slot_style)
		btn.add_theme_font_size_override("font_size", FONT_SECONDARY)
		btn.pressed.connect(func():
			var key: String = str(btn.get_meta("label_key", "PROFILE_SLOT_GENERIC"))
			_status.text = tr("PROFILE_EQUIP_COMING_SOON_FMT") % tr(key)
		)
		stage_inner.add_child(btn)
		_equip_slot_btns.append(btn)

	_profile_actions = VBoxContainer.new()
	_profile_actions.add_theme_constant_override("separation", 8)
	_page_profile.add_child(_profile_actions)

	_profile_extra = VBoxContainer.new()
	_profile_extra.add_theme_constant_override("separation", 8)
	_page_profile.add_child(_profile_extra)


func _build_stats_page_shell() -> void:
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style())
	_page_stats.add_child(card)
	_stats_scroll = ScrollContainer.new()
	_stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_stats_scroll)
	_stats_content = VBoxContainer.new()
	_stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_content.add_theme_constant_override("separation", 12)
	_stats_scroll.add_child(_stats_content)


func _build_settings_page_shell() -> void:
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style())
	_page_settings.add_child(card)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_settings_scroll)
	_settings_content = VBoxContainer.new()
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", 12)
	_settings_scroll.add_child(_settings_content)


func _load_profile() -> void:
	var ab: Node = _alliance_backend()
	if ab == null:
		_profile = _local_fallback_profile()
		_status.text = tr("PROFILE_OFFLINE_PROFILE")
		return
	if _is_self:
		if ab.has_method("sync_identity_from_local"):
			await ab.sync_identity_from_local()
		await ab.refresh_profile()
		_profile = ab.get_profile()
		if _profile.is_empty():
			_profile = _local_fallback_profile()
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
			_status.text = str(res.get("error", tr("PROFILE_UNAVAILABLE")))


func _local_canonical_castle_level() -> int:
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
	_clear_container(_identity_box)
	_clear_container(_profile_actions)
	_clear_container(_profile_extra)
	_clear_container(_stats_content)
	_clear_container(_settings_content)

	var avatar_id: String = PlayerAvatarCatalog.normalize_id(str(_profile.get("avatar_id", "avatar_01")))
	_pending_avatar_id = avatar_id
	if _hero_tex != null:
		_hero_tex.texture = PlayerAvatarCatalog.get_texture(avatar_id, 512)

	_rebuild_profile_tab(avatar_id)
	_rebuild_stats_tab()
	_rebuild_settings_tab()
	_show_tab(_active_tab)


func _clear_container(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		c.queue_free()


func _rebuild_profile_tab(avatar_id: String) -> void:
	if _identity_box == null:
		return
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	_identity_box.add_child(identity)

	_avatar_tex = TextureRect.new()
	_avatar_tex.custom_minimum_size = Vector2(88, 88)
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
	_style_label(name_lbl, FONT_NAME, COL_INK)
	id_col.add_child(name_lbl)

	# Small high-value summary only (full table lives on Stats).
	var summary := Label.new()
	summary.text = tr("PROFILE_SUMMARY_FMT") % [
		_format_num(int(_profile.get("power", 0))),
		int(_profile.get("vip_level", 0)),
	]
	_style_label(summary, FONT_SECONDARY, COL_MUTED)
	id_col.add_child(summary)

	if _is_self:
		var rename_btn := Button.new()
		rename_btn.text = tr("PROFILE_RENAME")
		rename_btn.custom_minimum_size = Vector2(160, TOUCH_H_SM)
		_style_button(rename_btn, FONT_BUTTON, TOUCH_H_SM)
		rename_btn.pressed.connect(_on_rename_pressed)
		id_col.add_child(rename_btn)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_profile_actions.add_child(actions)

	if _is_self:
		var avatar_btn := Button.new()
		avatar_btn.text = tr("PROFILE_CHANGE_AVATAR")
		avatar_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(avatar_btn, FONT_BUTTON, TOUCH_H)
		avatar_btn.pressed.connect(_show_avatar_picker)
		actions.add_child(avatar_btn)
		var share_self := Button.new()
		share_self.text = tr("PROFILE_SHARE_LOCATION")
		share_self.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(share_self, FONT_BUTTON, TOUCH_H)
		share_self.pressed.connect(_on_share_location)
		actions.add_child(share_self)
	else:
		var view_all := Button.new()
		view_all.text = tr("PROFILE_VIEW_ALLIANCE")
		view_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(view_all, FONT_BUTTON, TOUCH_H)
		view_all.pressed.connect(_on_view_alliance)
		actions.add_child(view_all)
		var msg_btn := Button.new()
		msg_btn.text = tr("PROFILE_MESSAGE")
		msg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(msg_btn, FONT_BUTTON, TOUCH_H)
		msg_btn.pressed.connect(func():
			message_requested.emit(str(_profile.get("user_id", "")), str(_profile.get("display_name", "Player")))
			on_close()
		)
		actions.add_child(msg_btn)
		_add_friend_action_row(_profile_actions)
		var share_other := Button.new()
		share_other.text = tr("PROFILE_SHARE_LOCATION")
		_style_button(share_other, FONT_BUTTON, TOUCH_H)
		share_other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share_other.pressed.connect(_on_share_location)
		_profile_actions.add_child(share_other)
		var mod_row := HBoxContainer.new()
		mod_row.add_theme_constant_override("separation", 8)
		_profile_actions.add_child(mod_row)
		var uid: String = str(_profile.get("user_id", ""))
		var fb_block: Node = _friends_backend()
		var blocked: bool = fb_block != null and fb_block.has_method("is_blocked") and bool(fb_block.is_blocked(uid))
		var block_btn := Button.new()
		block_btn.text = tr("PROFILE_UNBLOCK") if blocked else tr("PROFILE_BLOCK")
		block_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(block_btn, FONT_BUTTON, TOUCH_H)
		block_btn.pressed.connect(func(): await _on_block_pressed())
		mod_row.add_child(block_btn)
		var report_btn := Button.new()
		report_btn.text = tr("PROFILE_REPORT")
		report_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(report_btn, FONT_BUTTON, TOUCH_H)
		report_btn.pressed.connect(_on_report_pressed)
		mod_row.add_child(report_btn)


func _rebuild_stats_tab() -> void:
	if _stats_content == null:
		return
	var tag: String = str(_profile.get("alliance_tag", "")).strip_edges()
	_add_section(_stats_content, tr("PROFILE_ACCOUNT"))
	_add_stat_row(_stats_content, tr("PROFILE_POWER"), _format_num(int(_profile.get("power", 0))))
	var highest: int = int(_profile.get("highest_power", _profile.get("power", 0)))
	_add_stat_row(_stats_content, tr("PROFILE_HIGHEST_POWER"), _format_num(highest))
	_add_stat_row(_stats_content, tr("PROFILE_KILLS"), _format_num(int(_profile.get("kills", 0))))
	_add_stat_row(_stats_content, tr("PROFILE_KINGDOM"), str(_profile.get("kingdom_id", "—")))
	var alliance: String = str(_profile.get("alliance_name", "")).strip_edges()
	if alliance == "":
		alliance = tr("PROFILE_NONE")
	elif tag != "":
		alliance = "[%s] %s" % [tag, alliance]
	_add_stat_row(_stats_content, tr("PROFILE_ALLIANCE"), alliance)
	_add_stat_row(_stats_content, tr("PROFILE_CITADEL"), tr("PROFILE_LEVEL_FMT") % int(_profile.get("citadel_level", 1)))
	_add_stat_row(_stats_content, tr("PROFILE_VIP"), tr("PROFILE_LEVEL_FMT") % int(_profile.get("vip_level", 0)))
	var online: String = str(_profile.get("online_status", "offline"))
	_add_stat_row(_stats_content, tr("PROFILE_STATUS"), tr("PROFILE_ONLINE") if online == "online" else tr("PROFILE_OFFLINE"))
	_add_public_gear_section(_stats_content)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 24)
	_stats_content.add_child(pad)


func _rebuild_settings_tab() -> void:
	if _settings_content == null:
		return
	if _is_self:
		_add_language_settings_section(_settings_content)
		_add_account_settings_section(_settings_content)
	else:
		var note := Label.new()
		note.text = tr("PROFILE_SETTINGS_OTHER_NOTE")
		_style_label(note, FONT_BODY, COL_MUTED)
		_settings_content.add_child(note)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 24)
	_settings_content.add_child(pad)


func _add_account_settings_section(parent: VBoxContainer) -> void:
	var section := Label.new()
	section.text = "Account"
	_style_label(section, FONT_SECTION, COL_GOLD)
	parent.add_child(section)
	var panel_script: GDScript = load("res://Scripts/UI/AccountSettingsPanel.gd") as GDScript
	if panel_script == null:
		var missing := Label.new()
		missing.text = "Account settings unavailable."
		_style_label(missing, FONT_BODY, COL_MUTED)
		parent.add_child(missing)
		return
	var panel: Control = panel_script.new() as Control
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)


func _show_avatar_picker() -> void:
	_clear_container(_profile_extra)
	_add_section(_profile_extra, tr("PROFILE_CHOOSE_AVATAR"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_profile_extra.add_child(grid)
	for aid in PlayerAvatarCatalog.AVATAR_IDS:
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(72, 72)
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
		_status.text = tr("PROFILE_NO_ALLIANCE")
		return
	on_close()
	var hud := get_tree().root.find_child("GameHUD", true, false)
	if hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null and mgr.has_method("open_screen"):
			mgr.call("open_screen", "AllianceScreen")


func _add_friend_action_row(parent: VBoxContainer) -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var fb: Node = _friends_backend()
	if uid == "" or fb == null or not fb.has_method("get_relationship"):
		return
	var rel: String = str(fb.get_relationship(uid))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	match rel:
		"friend":
			var friends_lbl := Button.new()
			friends_lbl.text = tr("PROFILE_FRIENDS")
			friends_lbl.disabled = true
			friends_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(friends_lbl, FONT_BUTTON, TOUCH_H)
			row.add_child(friends_lbl)
			var remove_btn := Button.new()
			remove_btn.text = tr("PROFILE_REMOVE_FRIEND")
			remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(remove_btn, FONT_BUTTON, TOUCH_H)
			remove_btn.pressed.connect(func(): await _friend_op("remove"))
			row.add_child(remove_btn)
		"invite_sent":
			var pending := Button.new()
			pending.text = tr("PROFILE_PENDING")
			pending.disabled = true
			pending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(pending, FONT_BUTTON, TOUCH_H)
			row.add_child(pending)
			var cancel_btn := Button.new()
			cancel_btn.text = tr("PROFILE_CANCEL_REQUEST")
			cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(cancel_btn, FONT_BUTTON, TOUCH_H)
			cancel_btn.pressed.connect(func(): await _friend_op("cancel"))
			row.add_child(cancel_btn)
		"invite_received":
			var accept_btn := Button.new()
			accept_btn.text = tr("PROFILE_ACCEPT_FRIEND")
			accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(accept_btn, FONT_BUTTON, TOUCH_H)
			accept_btn.pressed.connect(func(): await _friend_op("accept"))
			row.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = tr("PROFILE_DECLINE")
			decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(decline_btn, FONT_BUTTON, TOUCH_H)
			decline_btn.pressed.connect(func(): await _friend_op("decline"))
			row.add_child(decline_btn)
		"blocked":
			var blocked_lbl := Button.new()
			blocked_lbl.text = tr("PROFILE_BLOCKED")
			blocked_lbl.disabled = true
			blocked_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(blocked_lbl, FONT_BUTTON, TOUCH_H)
			row.add_child(blocked_lbl)
		_:
			var add_btn := Button.new()
			add_btn.text = tr("PROFILE_ADD_FRIEND")
			add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_button(add_btn, FONT_BUTTON, TOUCH_H)
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
		_status.text = tr("PROFILE_FRIENDS_UPDATED")
		await _open_async()
	else:
		_status.text = str(result.get("error", tr("PROFILE_FRIENDS_FAILED")))


func _on_block_pressed() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var fb: Node = _friends_backend()
	if uid == "" or fb == null:
		_status.text = tr("PROFILE_BLOCK_UNAVAILABLE")
		return
	var result: Dictionary
	if bool(fb.is_blocked(uid)):
		result = await fb.unblock_player(uid)
		_status.text = tr("PROFILE_PLAYER_UNBLOCKED") if bool(result.get("ok", false)) else str(result.get("error", tr("PROFILE_UNBLOCK_FAILED")))
	else:
		result = await fb.block_player(uid)
		_status.text = tr("PROFILE_PLAYER_BLOCKED") if bool(result.get("ok", false)) else str(result.get("error", tr("PROFILE_BLOCK_FAILED")))
	if bool(result.get("ok", false)):
		await _open_async()


func _on_report_pressed() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	if uid == "" or not has_node("/root/AllianceBackend"):
		_status.text = tr("PROFILE_REPORT_UNAVAILABLE")
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = tr("UI_CONFIRM")
	confirm.dialog_text = tr("PROFILE_REPORT_CONFIRM")
	confirm.ok_button_text = tr("UI_YES")
	confirm.cancel_button_text = tr("UI_NO")
	add_child(confirm)
	confirm.confirmed.connect(func():
		confirm.queue_free()
		_show_report_reasons(uid)
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	confirm.popup_centered()


func _show_report_reasons(uid: String) -> void:
	_clear_container(_profile_extra)
	_show_tab(TAB_PROFILE)
	var ab: Node = _alliance_backend()
	var reasons: Array = ab.REPORT_REASONS.duplicate() if ab != null else ["spam", "harassment", "other"]
	_add_section(_profile_extra, tr("PROFILE_REPORT_REASON"))
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	_profile_extra.add_child(grid)
	for reason_v in reasons:
		var reason: String = str(reason_v)
		var btn := Button.new()
		btn.text = _localize_report_reason(reason)
		_style_button(btn, FONT_BUTTON, TOUCH_H)
		btn.pressed.connect(func(): await _submit_profile_report(uid, reason))
		grid.add_child(btn)


func _localize_report_reason(reason: String) -> String:
	match reason.strip_edges().to_lower():
		"spam":
			return tr("PROFILE_REPORT_REASON_SPAM")
		"harassment":
			return tr("PROFILE_REPORT_REASON_HARASSMENT")
		"other":
			return tr("PROFILE_REPORT_REASON_OTHER")
		_:
			# Unknown server reason codes stay as raw identifiers.
			return reason.replace("_", " ").capitalize()


func _submit_profile_report(user_id: String, reason: String) -> void:
	if not has_node("/root/AllianceBackend"):
		return
	var payload := {
		"reported_user_id": user_id,
		"message_id": "profile_%s_%d" % [user_id, int(Time.get_unix_time_from_system())],
		"channel_id": "player_profile",
		"message_type": "PROFILE",
		# Server payload text — keep English for moderation tooling.
		"message_text": "Profile report: %s" % str(_profile.get("display_name", "Player")),
		"create_time": Time.get_datetime_string_from_system(true),
		"reason": reason,
	}
	var result: Dictionary = await _alliance_backend().submit_chat_report(payload)
	if bool(result.get("ok", false)):
		_status.text = tr("PROFILE_REPORT_SUBMITTED")
	else:
		_status.text = str(result.get("error", tr("PROFILE_REPORT_FAILED")))


func _add_public_gear_section(parent: VBoxContainer) -> void:
	_add_section(parent, tr("PROFILE_PUBLIC_GEAR"))
	var gear: Array = []
	if typeof(_profile.get("public_equipment")) == TYPE_ARRAY:
		gear = _profile.get("public_equipment", [])
	if gear.is_empty():
		var empty := Label.new()
		empty.text = tr("PROFILE_NO_PUBLIC_GEAR")
		_style_label(empty, FONT_SECONDARY, COL_MUTED)
		parent.add_child(empty)
		return
	for item_v in gear:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		# Slot / item / rarity names are server/content values — leave raw.
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
		_style_label(row, FONT_BODY, COL_INK)
		parent.add_child(row)


func _on_share_location() -> void:
	var uid: String = str(_profile.get("user_id", "")).strip_edges()
	var x: float = float(_profile.get("world_x", 0))
	var y: float = float(_profile.get("world_y", 0))
	if x == 0.0 and y == 0.0 and has_node("/root/MarchState") and MarchState.has_method("get_castle_world_position"):
		var pos: Vector2 = MarchState.get_castle_world_position()
		x = pos.x
		y = pos.y
	if not has_node("/root/ChatManager"):
		_status.text = tr("PROFILE_CHAT_UNAVAILABLE")
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
		"label": tr("PROFILE_CASTLE_SHARE_LABEL_FMT") % name_text,
		"target_type": "player_castle",
		"target_id": uid,
		"owner_user_id": uid,
		"display_name": name_text,
	}
	print("[CastlePopup] share requested user=%s kingdom=%s x=%s y=%s" % [uid, kid, str(x), str(y)])
	_status.text = tr("PROFILE_SHARING_LOCATION")
	var result: Dictionary = await cm.send_map_location(payload, "kingdom")
	if bool(result.get("ok", false)):
		_status.text = tr("PROFILE_LOCATION_SHARED")
		_status.add_theme_color_override("font_color", COL_OK)
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(result.get("error", tr("PROFILE_SHARE_FAILED")))


func _add_stat_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 32)
	var a := Label.new()
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(a, FONT_BODY, COL_MUTED)
	row.add_child(a)
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(b, FONT_BODY, COL_INK)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	parent.add_child(row)


func _add_section(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	_style_label(l, FONT_SECTION, COL_GOLD)
	parent.add_child(l)


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
		_status.text = tr("PROFILE_RENAME_UNAVAILABLE")
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
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -110
	panel.offset_bottom = 110
	panel.add_theme_stylebox_override("panel", _panel_style())
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var tip := Label.new()
	tip.text = tr("PROFILE_NEW_NAME_TIP")
	_style_label(tip, FONT_SECTION, COL_GOLD)
	box.add_child(tip)
	var edit := LineEdit.new()
	edit.text = str(_profile.get("display_name", ""))
	edit.custom_minimum_size = Vector2(0, TOUCH_H)
	edit.add_theme_font_size_override("font_size", FONT_BODY)
	box.add_child(edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = tr("UI_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(cancel, FONT_BUTTON, TOUCH_H)
	cancel.pressed.connect(func(): overlay.queue_free())
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = tr("UI_SAVE")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(ok, FONT_BUTTON, TOUCH_H)
	ok.pressed.connect(func():
		var name: String = edit.text.strip_edges()
		overlay.queue_free()
		_apply_rename(name)
	)
	row.add_child(ok)
	edit.grab_focus()


func _add_language_settings_section(parent: VBoxContainer) -> void:
	_settings_title = Label.new()
	_settings_title.text = tr("UI_SETTINGS")
	_style_label(_settings_title, FONT_SECTION, COL_GOLD)
	parent.add_child(_settings_title)

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(block)

	_lang_label = Label.new()
	_lang_label.text = tr("UI_LANGUAGE")
	_style_label(_lang_label, FONT_BODY, COL_INK)
	block.add_child(_lang_label)

	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_option.custom_minimum_size = Vector2(0, TOUCH_H)
	_lang_option.add_theme_font_size_override("font_size", FONT_BUTTON)
	_lang_option.clip_text = false
	_lang_option.add_item(tr("LANGUAGE_ENGLISH"), 0)
	_lang_option.set_item_metadata(0, "en")
	_lang_option.add_item(tr("LANGUAGE_TURKISH"), 1)
	_lang_option.set_item_metadata(1, "tr")
	_suppress_lang_signal = true
	var cur: String = "en"
	if has_node("/root/LocaleSettings"):
		cur = str(LocaleSettings.get_current_locale())
	_lang_option.select(1 if cur == "tr" else 0)
	_suppress_lang_signal = false
	if not _lang_option.item_selected.is_connected(_on_language_item_selected):
		_lang_option.item_selected.connect(_on_language_item_selected)
	block.add_child(_lang_option)


func _on_language_item_selected(index: int) -> void:
	if _suppress_lang_signal or _lang_option == null:
		return
	var meta: Variant = _lang_option.get_item_metadata(index)
	var locale: String = str(meta) if meta != null else "en"
	if has_node("/root/LocaleSettings"):
		LocaleSettings.set_player_locale(locale)
	else:
		TranslationServer.set_locale(locale)


func _on_locale_changed(_locale: String) -> void:
	_refresh_locale_chrome()
	if visible and _settings_content != null:
		# Keep current tab; refresh labels/options without dropping profile data.
		_rebuild_content()


func _refresh_locale_chrome() -> void:
	if _header_back != null and is_instance_valid(_header_back):
		_header_back.text = "← %s" % tr("UI_BACK")
	if _header_title != null and is_instance_valid(_header_title):
		_header_title.text = tr("UI_PLAYER_PROFILE")
	if _header_close != null and is_instance_valid(_header_close):
		_header_close.text = tr("UI_CLOSE")
	if _tab_btns.has(TAB_PROFILE):
		(_tab_btns[TAB_PROFILE] as Button).text = tr("UI_TAB_PROFILE")
	if _tab_btns.has(TAB_STATS):
		(_tab_btns[TAB_STATS] as Button).text = tr("UI_TAB_STATS")
	if _tab_btns.has(TAB_SETTINGS):
		(_tab_btns[TAB_SETTINGS] as Button).text = tr("UI_TAB_SETTINGS")
	for btn_v in _equip_slot_btns:
		var btn: Button = btn_v as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var key: String = str(btn.get_meta("label_key", "PROFILE_SLOT_GENERIC"))
		btn.text = tr(key)


func _apply_rename(name: String) -> void:
	var ab: Node = _alliance_backend()
	_status.text = tr("PROFILE_SAVING_NAME")
	var res: Dictionary = await ab.set_display_name(name)
	if bool(res.get("ok", false)):
		_status.text = tr("PROFILE_NAME_UPDATED")
		_status.add_theme_color_override("font_color", COL_OK)
		await _load_profile()
		_rebuild_content()
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(res.get("error", tr("PROFILE_RENAME_FAILED")))


func _on_avatar_picked(avatar_id: String) -> void:
	var ab: Node = _alliance_backend()
	if ab == null or not ab.has_method("update_player_identity"):
		_status.text = tr("PROFILE_AVATAR_SAVE_UNAVAILABLE")
		return
	_status.text = tr("PROFILE_SAVING_AVATAR")
	var res: Dictionary = await ab.update_player_identity({"avatar_id": avatar_id})
	if bool(res.get("ok", false)):
		_status.text = tr("PROFILE_AVATAR_UPDATED")
		_status.add_theme_color_override("font_color", COL_OK)
		await _load_profile()
		_rebuild_content()
	else:
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_status.text = str(res.get("error", tr("PROFILE_AVATAR_SAVE_FAILED")))
