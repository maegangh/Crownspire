extends Control

## Alliance Home hub UI.
## Phase 4: membership/roster/ranks/applications use AllianceBackend when online.
## Research/Help remain on local AllianceState (unmigrated) and are labeled accordingly.

const MobileScrollUtil = preload("res://Scripts/UI/MobileScroll.gd")

enum ViewMode {
	LOBBY,
	CREATE,
	JOIN,
	HOME,
	MEMBERS,
	MEMBER_DETAIL,
	HELP,
	APPLICATIONS,
	RESEARCH,
	COMING_SOON,
	INVITES,
	SETTINGS,
}

var _view: ViewMode = ViewMode.LOBBY
var _coming_soon_title: String = ""
var _status_label: Label
var _title_label: Label
var _back_button: Button
var _content: VBoxContainer
var _name_edit: LineEdit
var _tag_edit: LineEdit
var _desc_edit: TextEdit
var _lang_option: OptionButton
var _join_type_option: OptionButton
var _min_citadel_spin: SpinBox
var _create_button: Button
var _create_error_label: Label
var _settings_announce_edit: TextEdit
var _join_id_edit: LineEdit
var _invite_user_edit: LineEdit
var _selected_member_id: String = ""
var _research_category: String = "Growth"
var _selected_research_id: String = ""
var _backend_loading: bool = false
var _flash_status: String = ""
var _search_query_edit: LineEdit
var _search_query: String = ""

const CREATE_LANGS: Array[Dictionary] = [
	{"id": "en", "label": "English"},
	{"id": "es", "label": "Spanish"},
	{"id": "fr", "label": "French"},
	{"id": "de", "label": "German"},
	{"id": "pt", "label": "Portuguese"},
	{"id": "ru", "label": "Russian"},
	{"id": "zh", "label": "Chinese"},
	{"id": "ja", "label": "Japanese"},
	{"id": "ko", "label": "Korean"},
]


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _chat_manager() -> Node:
	return get_node_or_null("/root/ChatManager")


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


const NAV_CARDS: Array[Dictionary] = [
	{"id": "members", "title": "Members", "subtitle": "Roster & ranks", "live": true},
	{"id": "help", "title": "Help", "subtitle": "Local / Coming Soon", "live": true},
	{"id": "research", "title": "Research", "subtitle": "Local / Coming Soon", "live": true},
	{"id": "applications", "title": "Applications", "subtitle": "Review joins", "live": true},
	{"id": "gifts", "title": "Gifts", "subtitle": "Coming Soon", "live": false},
	{"id": "territory", "title": "Territory", "subtitle": "Coming Soon", "live": false},
	{"id": "shop", "title": "Shop", "subtitle": "Coming Soon", "live": false},
	{"id": "rankings", "title": "Rankings", "subtitle": "Coming Soon", "live": false},
	{"id": "settings", "title": "Settings", "subtitle": "Banner & rules", "live": true},
]


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()

	if has_node("/root/AllianceState"):
		if not AllianceState.alliance_changed.is_connected(_on_local_alliance_changed):
			AllianceState.alliance_changed.connect(_on_local_alliance_changed)
	if has_node("/root/AllianceBackend"):
		if not _alliance_backend().alliance_changed.is_connected(_on_backend_alliance_changed):
			_alliance_backend().alliance_changed.connect(_on_backend_alliance_changed)
		if not _alliance_backend().roster_changed.is_connected(_on_backend_roster_changed):
			_alliance_backend().roster_changed.connect(_on_backend_roster_changed)
		if not _alliance_backend().applications_changed.is_connected(_on_backend_apps_changed):
			_alliance_backend().applications_changed.connect(_on_backend_apps_changed)
		if not _alliance_backend().invites_changed.is_connected(_on_backend_invites_changed):
			_alliance_backend().invites_changed.connect(_on_backend_invites_changed)
		if not _alliance_backend().help_requests_changed.is_connected(_on_backend_help_changed):
			_alliance_backend().help_requests_changed.connect(_on_backend_help_changed)
		if not _alliance_backend().auto_help_status_changed.is_connected(_on_backend_auto_help_changed):
			_alliance_backend().auto_help_status_changed.connect(_on_backend_auto_help_changed)
		if not _alliance_backend().operation_failed.is_connected(_on_backend_operation_failed):
			_alliance_backend().operation_failed.connect(_on_backend_operation_failed)
		if not _alliance_backend().profile_changed.is_connected(_on_backend_profile_changed):
			_alliance_backend().profile_changed.connect(_on_backend_profile_changed)
	var nc_bind: Node = _nakama_connection()
	if nc_bind != null and nc_bind.has_signal("connection_state_changed"):
		if not nc_bind.connection_state_changed.is_connected(_on_nakama_connection_state_changed):
			nc_bind.connection_state_changed.connect(_on_nakama_connection_state_changed)


func _on_backend_operation_failed(reason: String) -> void:
	if not visible or _status_label == null:
		return
	var msg: String = str(reason).strip_edges()
	if msg != "":
		_status_label.text = msg


func _set_flash_status(text: String) -> void:
	_flash_status = text.strip_edges()


func _is_multiplayer_online() -> bool:
	## Network connectivity only — never requires Crownspire profile.
	var nc: Node = _nakama_connection()
	return (
		nc != null
		and nc.has_method("is_authenticated")
		and nc.has_method("is_socket_connected")
		and nc.is_authenticated()
		and nc.is_socket_connected()
	)


func _use_backend() -> bool:
	## Server-backed Alliance membership/profile readiness (not connectivity).
	var ab: Node = _alliance_backend()
	return ab != null and ab.is_membership_authority()


func _log_alliance_ui_state(context: String = "") -> void:
	var nc: Node = _nakama_connection()
	var ab: Node = _alliance_backend()
	var authenticated: bool = nc != null and nc.has_method("is_authenticated") and nc.is_authenticated()
	var socket: bool = nc != null and nc.has_method("is_socket_connected") and nc.is_socket_connected()
	var has_profile: bool = ab != null and ab.has_method("has_profile") and ab.has_profile()
	var membership_authority: bool = ab != null and ab.has_method("is_membership_authority") and ab.is_membership_authority()
	var suffix: String = (" context=%s" % context) if context.strip_edges() != "" else ""
	print(
		"[AllianceUI] authenticated=%s socket=%s has_profile=%s membership_authority=%s%s"
		% [authenticated, socket, has_profile, membership_authority, suffix]
	)


func _is_in_alliance() -> bool:
	## Backend membership is authoritative when profile/membership authority is ready.
	if _use_backend():
		return _alliance_backend().is_in_backend_alliance()
	return has_node("/root/AllianceState") and AllianceState.is_in_alliance()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_selected_member_id = ""
	_coming_soon_title = ""
	_selected_research_id = ""
	_research_category = "Growth"
	_log_alliance_ui_state("on_open_start")
	var nc: Node = _nakama_connection()
	if has_node("/root/AllianceBackend") and nc != null and nc.is_authenticated():
		var result: Dictionary = await _alliance_backend().refresh_profile()
		if not bool(result.get("ok", false)):
			print("[AllianceUI] refresh_profile failed: %s" % str(result.get("error", "unknown")))
		if _alliance_backend().is_in_backend_alliance():
			await _alliance_backend().refresh_membership_caches()
		else:
			await _alliance_backend().list_my_invites()
	if _is_in_alliance():
		_view = ViewMode.HOME
	else:
		_view = ViewMode.LOBBY
	_log_alliance_ui_state("on_open_ready")
	_refresh()
	if has_node("/root/GameEvents"):
		GameEvents.emit_alliance_opened()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = ViewMode.LOBBY
	_selected_member_id = ""
	_coming_soon_title = ""
	_selected_research_id = ""


func _on_local_alliance_changed() -> void:
	## Ignore local membership churn when backend is authority.
	if _use_backend():
		return
	if not visible:
		return
	if not AllianceState.is_in_alliance():
		_view = ViewMode.LOBBY
		_selected_member_id = ""
		_coming_soon_title = ""
		_selected_research_id = ""
	elif _view in [ViewMode.LOBBY, ViewMode.CREATE, ViewMode.JOIN, ViewMode.INVITES]:
		_view = ViewMode.HOME
	_refresh()


func _on_backend_alliance_changed(_alliance: Dictionary) -> void:
	if not visible:
		return
	if not _alliance_backend().is_in_backend_alliance():
		_view = ViewMode.LOBBY
		_selected_member_id = ""
	elif _view in [ViewMode.LOBBY, ViewMode.CREATE, ViewMode.JOIN, ViewMode.INVITES]:
		_view = ViewMode.HOME
	_refresh()


func _on_backend_profile_changed(_profile: Dictionary) -> void:
	## Profile arrival flips membership_authority — refresh lobby so UI leaves "loading profile".
	if not visible:
		return
	_log_alliance_ui_state("profile_changed")
	if _is_in_alliance() and _view in [ViewMode.LOBBY, ViewMode.CREATE, ViewMode.JOIN, ViewMode.INVITES]:
		_view = ViewMode.HOME
	_refresh()


func _on_nakama_connection_state_changed(_state: String = "") -> void:
	if not visible:
		return
	_log_alliance_ui_state("connection_state")
	if _view == ViewMode.LOBBY or not _is_in_alliance():
		_refresh()


func _on_backend_roster_changed(_members: Array) -> void:
	if visible and _view in [ViewMode.MEMBERS, ViewMode.MEMBER_DETAIL, ViewMode.HOME]:
		_refresh()


func _on_backend_apps_changed(_apps: Array) -> void:
	if visible and _view == ViewMode.APPLICATIONS:
		_refresh()


func _on_backend_invites_changed(_invites: Array) -> void:
	if visible and _view in [ViewMode.LOBBY, ViewMode.INVITES]:
		_refresh()


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()

	var dim: ColorRect = ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.05, 0.04, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_bottom = -190.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window: PanelContainer = PanelContainer.new()
	window.name = "AllianceWindow"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.custom_minimum_size = Vector2(660, 940)
	window.offset_left = -330
	window.offset_top = -470
	window.offset_right = 330
	window.offset_bottom = 470
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(window)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 12)
	window.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(96, 52)
	_back_button.visible = false
	_back_button.pressed.connect(_on_back_pressed)
	header.add_child(_back_button)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "ALLIANCE"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(64, 52)
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	MobileScrollUtil.ensure(self, scroll, "MobileScrollAlliance")

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)


func _refresh() -> void:
	if _content == null:
		return

	for child: Node in _content.get_children():
		child.queue_free()

	_status_label.text = ""
	_update_header()

	# Never expose internal debug copy. Always show a usable lobby when offline / not joined.
	match _view:
		ViewMode.CREATE:
			_build_create_view()
		ViewMode.JOIN:
			_build_join_view()
		ViewMode.INVITES:
			_build_invites_view()
		ViewMode.HOME:
			if _is_in_alliance():
				_build_home_view()
			else:
				_view = ViewMode.LOBBY
				_build_unjoined_view()
		ViewMode.MEMBERS:
			if _is_in_alliance():
				_build_members_view()
			else:
				_view = ViewMode.LOBBY
				_build_unjoined_view()
		ViewMode.MEMBER_DETAIL:
			if _is_in_alliance():
				_build_member_detail_view()
			else:
				_view = ViewMode.LOBBY
				_build_unjoined_view()
		ViewMode.HELP:
			_build_help_view()
		ViewMode.APPLICATIONS:
			if _is_in_alliance():
				_build_applications_view()
			else:
				_view = ViewMode.LOBBY
				_build_unjoined_view()
		ViewMode.SETTINGS:
			if _is_in_alliance():
				_build_settings_view()
			else:
				_view = ViewMode.LOBBY
				_build_unjoined_view()
		ViewMode.RESEARCH:
			_build_research_view()
		ViewMode.COMING_SOON:
			_build_coming_soon_view()
		_:
			if _is_in_alliance():
				_view = ViewMode.HOME
				_build_home_view()
			else:
				_build_unjoined_view()

	if _flash_status != "":
		_status_label.text = _flash_status
		_flash_status = ""


func _update_header() -> void:
	var show_back: bool = _view not in [ViewMode.LOBBY, ViewMode.HOME]
	_back_button.visible = show_back

	match _view:
		ViewMode.LOBBY:
			_title_label.text = "ALLIANCE"
		ViewMode.CREATE:
			_title_label.text = "CREATE"
		ViewMode.JOIN:
			_title_label.text = "JOIN"
		ViewMode.INVITES:
			_title_label.text = "INVITES"
		ViewMode.HOME:
			_title_label.text = "ALLIANCE HOME"
		ViewMode.MEMBERS, ViewMode.MEMBER_DETAIL:
			_title_label.text = "MEMBERS"
		ViewMode.HELP:
			_title_label.text = "HELP" if _use_backend() else "HELP (LOCAL)"
		ViewMode.APPLICATIONS:
			_title_label.text = "APPLICATIONS"
		ViewMode.SETTINGS:
			_title_label.text = "SETTINGS"
		ViewMode.RESEARCH:
			_title_label.text = "RESEARCH (LOCAL)"
		ViewMode.COMING_SOON:
			_title_label.text = _coming_soon_title.to_upper()
		_:
			_title_label.text = "ALLIANCE"


func _on_back_pressed() -> void:
	match _view:
		ViewMode.MEMBER_DETAIL:
			_selected_member_id = ""
			_view = ViewMode.MEMBERS
		ViewMode.CREATE, ViewMode.JOIN, ViewMode.INVITES:
			_view = ViewMode.LOBBY
		ViewMode.MEMBERS, ViewMode.HELP, ViewMode.APPLICATIONS, ViewMode.RESEARCH, ViewMode.COMING_SOON, ViewMode.SETTINGS:
			_coming_soon_title = ""
			_selected_research_id = ""
			_view = ViewMode.HOME
		_:
			_view = ViewMode.HOME if _is_in_alliance() else ViewMode.LOBBY
	_refresh()


func _go_home() -> void:
	_selected_member_id = ""
	_coming_soon_title = ""
	_selected_research_id = ""
	_view = ViewMode.HOME
	_refresh()


func _open_nav_card(card_id: String) -> void:
	match card_id:
		"members":
			_view = ViewMode.MEMBERS
		"help":
			_view = ViewMode.HELP
		"applications":
			_view = ViewMode.APPLICATIONS
		"research":
			_open_research_screen()
			return
		"gifts":
			_coming_soon_title = "Gifts"
			_view = ViewMode.COMING_SOON
		"territory":
			_coming_soon_title = "Territory"
			_view = ViewMode.COMING_SOON
		"shop":
			_coming_soon_title = "Shop"
			_view = ViewMode.COMING_SOON
		"rankings":
			_coming_soon_title = "Rankings"
			_view = ViewMode.COMING_SOON
		"settings":
			_view = ViewMode.SETTINGS
		_:
			return
	_refresh()


func _build_unjoined_view() -> void:
	var nc: Node = _nakama_connection()
	var mp_online: bool = _is_multiplayer_online()
	var membership_ready: bool = _use_backend()
	var connecting: bool = false
	if nc != null and nc.has_method("get_connection_state"):
		var st: String = str(nc.get_connection_state())
		connecting = st == "connecting" or st == "reconnecting"
	_log_alliance_ui_state("unjoined_view")

	if connecting and not mp_online:
		# A — Nakama connecting / reconnecting
		_add_banner_panel("Connecting…", "Multiplayer")
		_add_body_label("Connecting to Crownspire servers. Alliance Create / Join will unlock when ready.")
	elif mp_online and membership_ready:
		# B — authenticated + socket + profile/membership ready
		_add_banner_panel("Join the Realms", "Create or join an Alliance")
		_add_body_label("Build with allies — create a new Alliance, search existing ones, or check your invitations.")
	elif mp_online:
		# C — connected, but Crownspire profile not loaded yet
		_add_banner_panel("Connected", "Multiplayer")
		_add_body_label("Connected · Loading player profile… Create / Join unlock once your profile is ready.")
	else:
		# D — actually disconnected / offline
		_add_banner_panel("Alliance", "Offline")
		var reason: String = ""
		if nc != null and nc.has_method("get_last_fail_reason"):
			reason = str(nc.get_last_fail_reason()).strip_edges()
		if reason != "":
			_add_body_label("Can't reach multiplayer right now. Check your connection and try again.")
		else:
			_add_body_label("Multiplayer is offline. You can still browse Alliance options once connected.")

	var create_btn: Button = Button.new()
	create_btn.text = "Create Alliance"
	create_btn.custom_minimum_size = Vector2(0, 64)
	## Mutations require membership authority (profile ready). Never equate this with offline.
	create_btn.disabled = not membership_ready
	create_btn.pressed.connect(func() -> void:
		_view = ViewMode.CREATE
		_refresh()
	)
	_content.add_child(create_btn)

	var join_btn: Button = Button.new()
	join_btn.text = "Join Alliance"
	join_btn.custom_minimum_size = Vector2(0, 64)
	join_btn.disabled = not membership_ready
	join_btn.pressed.connect(func() -> void:
		_view = ViewMode.JOIN
		_refresh()
	)
	_content.add_child(join_btn)

	var search_btn: Button = Button.new()
	search_btn.text = "Search Alliances"
	search_btn.custom_minimum_size = Vector2(0, 56)
	search_btn.disabled = not membership_ready
	search_btn.pressed.connect(func() -> void:
		_view = ViewMode.JOIN
		_refresh()
	)
	_content.add_child(search_btn)

	var invites_btn: Button = Button.new()
	invites_btn.text = "Invitations"
	invites_btn.custom_minimum_size = Vector2(0, 56)
	invites_btn.disabled = not membership_ready
	invites_btn.pressed.connect(func() -> void:
		_view = ViewMode.INVITES
		_refresh()
	)
	_content.add_child(invites_btn)

	if mp_online and not membership_ready:
		var retry_profile: Button = Button.new()
		retry_profile.text = "Retry Profile Load"
		retry_profile.custom_minimum_size = Vector2(0, 52)
		retry_profile.pressed.connect(func() -> void:
			_status_label.text = "Loading profile…"
			if has_node("/root/AllianceBackend"):
				await _alliance_backend().refresh_profile()
			_log_alliance_ui_state("retry_profile")
			_refresh()
		)
		_content.add_child(retry_profile)

	if not mp_online and not connecting and nc != null and nc.has_method("reconnect_now"):
		var retry: Button = Button.new()
		retry.text = "Retry Connection"
		retry.custom_minimum_size = Vector2(0, 52)
		retry.pressed.connect(func() -> void:
			nc.reconnect_now()
			_status_label.text = "Connecting…"
		)
		_content.add_child(retry)

	_add_roles_hint()


func _build_home_view() -> void:
	if _use_backend():
		_build_backend_home_view()
		return

	var current: Dictionary = AllianceState.get_current_alliance()
	var tag: String = str(current.get("tag", AllianceState.alliance_tag))
	var name_text: String = str(current.get("name", AllianceState.alliance_name))
	var member_count: int = int(current.get("member_count", AllianceState.get_members().size()))
	var player_pts: int = AllianceState.get_player_contribution_points()

	_add_banner_panel("[%s]" % tag, name_text)

	var meta: PanelContainer = _make_info_panel()
	_content.add_child(meta)
	var meta_box: VBoxContainer = VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 6)
	meta.add_child(meta_box)
	_add_panel_label(meta_box, "Your Role: %s (%s)" % [
		AllianceState.role,
		AllianceState.get_role_display_name(AllianceState.role),
	])
	_add_panel_label(meta_box, "Members: %d" % member_count)
	_add_panel_label(meta_box, "Mode: LOCAL PROTOTYPE", true)

	_build_home_shared_tail(player_pts)


func _build_backend_home_view() -> void:
	var alliance: Dictionary = _alliance_backend().get_cached_alliance()
	if alliance.is_empty():
		alliance = {
			"tag": _alliance_backend().get_alliance_tag(),
			"name": _alliance_backend().get_alliance_name(),
			"member_count": _alliance_backend().get_cached_members().size(),
		}
	var tag: String = str(alliance.get("tag", _alliance_backend().get_alliance_tag()))
	var name_text: String = str(alliance.get("name", _alliance_backend().get_alliance_name()))
	var member_count: int = int(alliance.get("member_count", _alliance_backend().get_cached_members().size()))
	var rank: String = _alliance_backend().get_crownspire_rank()

	_add_banner_panel("[%s]" % tag, name_text)

	var meta: PanelContainer = _make_info_panel()
	_content.add_child(meta)
	var meta_box: VBoxContainer = VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 6)
	meta.add_child(meta_box)
	_add_panel_label(meta_box, "Your Rank: %s (%s)" % [rank, _alliance_backend().get_role_display_name(rank)])
	_add_panel_label(meta_box, "Members: %d / %d" % [
		member_count,
		int(alliance.get("member_limit", 100)),
	])
	var jt: String = str(alliance.get("join_type", "apply"))
	_add_panel_label(meta_box, "Join: %s" % ("Open" if jt == "open" else "Approval Required" if jt == "apply" else "Invite Only"))
	_add_panel_label(meta_box, "Language: %s" % str(alliance.get("language", "en")).to_upper())
	var min_cit: int = int(alliance.get("min_citadel_level", 0))
	if min_cit > 0:
		_add_panel_label(meta_box, "Min Citadel: %d" % min_cit)
	var desc: String = str(alliance.get("description", "")).strip_edges()
	_add_panel_label(meta_box, desc if desc != "" else "No description set.")
	var announce: String = str(alliance.get("announcement", "")).strip_edges()
	if announce != "":
		_add_panel_label(meta_box, "Announcement: %s" % announce)
	var power: int = int(alliance.get("alliance_power_placeholder", 0))
	if power > 0:
		_add_panel_label(meta_box, "Power: %d" % power)

	var chat_btn: Button = Button.new()
	chat_btn.text = "Open Alliance Chat"
	chat_btn.custom_minimum_size = Vector2(0, 56)
	chat_btn.pressed.connect(func() -> void:
		var hud := get_tree().root.find_child("GameHUD", true, false)
		if hud != null and hud.has_method("open_chat"):
			hud.call("open_chat", "alliance")
		elif has_node("/root/ChatManager"):
			_chat_manager().ensure_alliance_joined()
			_set_flash_status("Alliance Chat joining…")
			_refresh()
	)
	_content.add_child(chat_btn)

	if _alliance_backend().has_permission("invite"):
		_invite_user_edit = LineEdit.new()
		_invite_user_edit.placeholder_text = "Invite player user ID"
		_invite_user_edit.custom_minimum_size = Vector2(0, 48)
		_content.add_child(_invite_user_edit)
		var invite_btn: Button = Button.new()
		invite_btn.text = "Send Invite"
		invite_btn.custom_minimum_size = Vector2(0, 48)
		invite_btn.pressed.connect(_on_invite_pressed)
		_content.add_child(invite_btn)

	_build_home_shared_tail(0)


func _build_home_shared_tail(player_pts: int) -> void:
	if has_node("/root/AllianceState") and not _use_backend():
		var announcement: String = AllianceState.get_announcement()
		if announcement == "":
			announcement = "No announcement posted."
		var announce_panel: PanelContainer = _make_info_panel()
		_content.add_child(announce_panel)
		var announce_box: VBoxContainer = VBoxContainer.new()
		announce_box.add_theme_constant_override("separation", 6)
		announce_panel.add_child(announce_box)
		_add_panel_label(announce_box, "Announcement", true)
		_add_panel_label(announce_box, announcement)

	var research_panel: PanelContainer = _make_info_panel()
	_content.add_child(research_panel)
	var research_box: VBoxContainer = VBoxContainer.new()
	research_box.add_theme_constant_override("separation", 8)
	research_panel.add_child(research_box)
	_add_panel_label(research_box, "Alliance Research (LOCAL)", true)
	if has_node("/root/AllianceState"):
		var active_id: String = AllianceState.get_active_research_id()
		var current_name: String = "None" if active_id == "" else str(DataManager.get_alliance_research_def(active_id).get("name", active_id))
		_add_panel_label(research_box, "Current: %s" % current_name)
		_add_panel_label(research_box, "Personal Contribution: %s" % _format_commas(player_pts if player_pts > 0 else AllianceState.get_player_contribution_points()))
	else:
		_add_panel_label(research_box, "Local AllianceState unavailable.")

	var open_research: Button = Button.new()
	open_research.text = "Open Research (Local)"
	open_research.custom_minimum_size = Vector2(0, 56)
	open_research.pressed.connect(_open_research_screen)
	research_box.add_child(open_research)

	_add_section_label("Alliance Hall")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)

	for card: Dictionary in NAV_CARDS:
		var card_id: String = str(card.get("id", ""))
		var nav_btn: Button = Button.new()
		nav_btn.text = "%s\n%s" % [str(card.get("title", "")), str(card.get("subtitle", ""))]
		nav_btn.custom_minimum_size = Vector2(0, 88)
		nav_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_btn.pressed.connect(_open_nav_card.bind(card_id))
		grid.add_child(nav_btn)

	var leave_btn: Button = Button.new()
	leave_btn.text = "Leave Alliance"
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.pressed.connect(_on_leave_pressed)
	_content.add_child(leave_btn)


func _build_coming_soon_view() -> void:
	_add_banner_panel(_coming_soon_title, "Coming Soon")
	_add_body_label("This hall is sealed for now. Crownspire will open it in a later sprint.")

	var back_home: Button = Button.new()
	back_home.text = "Back to Alliance Home"
	back_home.custom_minimum_size = Vector2(0, 56)
	back_home.pressed.connect(_go_home)
	_content.add_child(back_home)


func _build_research_view() -> void:
	_add_banner_panel("Alliance Research", "Unlock the tree. One project at a time.")

	_add_attempts_summary(_content)

	var active_id: String = AllianceState.get_active_research_id()
	_build_active_research_panel(active_id)

	var cat_row: HBoxContainer = HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 8)
	_content.add_child(cat_row)
	for entry: Dictionary in AllianceState.get_research_ui_categories():
		var ui_name: String = str(entry.get("ui", ""))
		var cat_btn: Button = Button.new()
		cat_btn.text = ui_name
		cat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_btn.custom_minimum_size = Vector2(0, 56)
		cat_btn.disabled = (_research_category == ui_name)
		cat_btn.pressed.connect(func() -> void:
			_research_category = ui_name
			_refresh()
		)
		cat_row.add_child(cat_btn)

	_add_body_label("Alliance Level %d" % AllianceState.get_alliance_level())

	var tiers: Dictionary = AllianceState.get_research_tiers_for_ui_category(_research_category)
	if tiers.is_empty():
		_add_body_label("No technologies in this category.")
		return

	var tier_keys: Array = tiers.keys()
	tier_keys.sort()
	for i: int in range(tier_keys.size()):
		var tier: int = int(tier_keys[i])
		var defs: Array = tiers[tier]
		_add_section_label("Tier %d" % tier)

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_content.add_child(row)

		for def: Variant in defs:
			if typeof(def) != TYPE_DICTIONARY:
				continue
			row.add_child(_make_research_tree_node(def))

		if i < tier_keys.size() - 1:
			var connector: Label = Label.new()
			connector.text = "│\n└────────┬────────┘\n         │"
			connector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			connector.add_theme_font_size_override("font_size", 14)
			connector.add_theme_color_override("font_color", Color(0.72, 0.62, 0.38, 0.85))
			connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(connector)

	if _selected_research_id != "":
		_build_research_detail_panel(_selected_research_id)


func _make_research_tree_node(def: Dictionary) -> Button:
	var research_id: String = str(def.get("id", ""))
	var runtime: Dictionary = AllianceState.get_research_node_runtime(research_id)
	var level: int = int(runtime.get("level", 0))
	var max_level: int = int(def.get("maxLevel", 1))
	var status: String = AllianceState.get_research_status(research_id)

	var node_btn: Button = Button.new()
	node_btn.text = "%s\n%s\nLv %d/%d" % [
		status,
		str(def.get("name", research_id)),
		level,
		max_level,
	]
	node_btn.custom_minimum_size = Vector2(190, 96)
	node_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_btn.add_theme_stylebox_override("normal", _research_node_style(status))
	node_btn.add_theme_stylebox_override("hover", _research_node_style(status, true))
	node_btn.add_theme_stylebox_override("pressed", _research_node_style(status, true))
	node_btn.pressed.connect(func() -> void:
		_selected_research_id = research_id
		_refresh()
	)
	return node_btn


func _research_node_style(status: String, highlight: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	match status:
		"ACTIVE":
			style.bg_color = Color(0.12, 0.22, 0.38, 0.95)
			style.border_color = Color(0.45, 0.72, 1.0, 1.0)
			if highlight:
				style.border_color = Color(0.65, 0.85, 1.0, 1.0)
		"AVAILABLE":
			style.bg_color = Color(0.16, 0.14, 0.10, 0.94)
			style.border_color = Color(0.78, 0.64, 0.28, 0.95)
		"COMPLETED":
			style.bg_color = Color(0.10, 0.18, 0.12, 0.92)
			style.border_color = Color(0.45, 0.72, 0.42, 0.9)
		_:
			style.bg_color = Color(0.08, 0.07, 0.10, 0.88)
			style.border_color = Color(0.35, 0.32, 0.38, 0.75)
	return style


func _build_active_research_panel(active_id: String) -> void:
	var panel: PanelContainer = _make_info_panel()
	_content.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_add_panel_label(box, "Current Alliance Research", true)
	if active_id == "":
		_add_panel_label(box, "None selected.")
		if AllianceState.has_permission("select_research"):
			_add_panel_label(box, "Choose a technology below and set it active.")
		else:
			_add_panel_label(box, "Waiting for leadership to select the next project.")
		return

	var def: Dictionary = DataManager.get_alliance_research_def(active_id)
	var runtime: Dictionary = AllianceState.get_research_node_runtime(active_id)
	var level: int = int(runtime.get("level", 0))
	var max_level: int = int(def.get("maxLevel", 1))
	var progress: int = int(runtime.get("progress", 0))
	var required: int = AllianceState.get_research_requirement(active_id, level) if level < max_level else 0
	var target_level: int = mini(level + 1, max_level)

	_add_panel_label(box, "%s %s" % [str(def.get("name", active_id)), _to_roman(target_level)], true)
	_add_panel_label(box, "Progress: %s / %s" % [_format_commas(progress), _format_commas(required)])
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1.0, float(required))
	bar.value = float(progress)
	bar.custom_minimum_size = Vector2(0, 24)
	bar.show_percentage = false
	box.add_child(bar)

	_add_contribute_panel(box, active_id)

	var details_btn: Button = Button.new()
	details_btn.text = "View Active Details"
	details_btn.custom_minimum_size = Vector2(0, 52)
	details_btn.pressed.connect(func() -> void:
		_selected_research_id = active_id
		_research_category = _ui_category_for_research(active_id)
		_refresh()
	)
	box.add_child(details_btn)


func _build_research_detail_panel(research_id: String) -> void:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return

	var runtime: Dictionary = AllianceState.get_research_node_runtime(research_id)
	var level: int = int(runtime.get("level", 0))
	var max_level: int = int(def.get("maxLevel", 1))
	var progress: int = int(runtime.get("progress", 0))
	var required: int = AllianceState.get_research_requirement(research_id, level) if level < max_level else 0
	var status: String = AllianceState.get_research_status(research_id)
	var is_active: bool = status == "ACTIVE"

	var panel: PanelContainer = _make_info_panel()
	_content.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_add_panel_label(box, str(def.get("name", research_id)), true)
	_add_panel_label(box, str(def.get("description", "")))
	_add_panel_label(box, "Current Level: %d" % level)
	_add_panel_label(box, "Max Level: %d" % max_level)
	_add_panel_label(box, "Current Bonus: %s" % AllianceState.get_research_effect_text(research_id, level))
	if level < max_level:
		_add_panel_label(box, "Next Bonus: %s" % AllianceState.get_research_effect_text(research_id, level + 1))
		_add_panel_label(box, "Progress: %s / %s" % [_format_commas(progress), _format_commas(required)])
		_add_panel_label(box, "Contribution Required: %s" % _format_commas(required))
	else:
		_add_panel_label(box, "Next Bonus: —")
		_add_panel_label(box, "Progress: Complete")
		_add_panel_label(box, "Contribution Required: —")

	_add_panel_label(box, "Tier %d · %s" % [int(def.get("tier", 1)), str(def.get("branch", ""))])
	_add_panel_label(box, "Status: %s" % status, true)

	match status:
		"LOCKED":
			_add_panel_label(box, "LOCKED", true)
			_add_panel_label(box, "Requirements:")
			var unmet: Array[String] = AllianceState.get_research_unmet_requirements(research_id)
			if unmet.is_empty():
				_add_panel_label(box, "- Complete the previous tier first")
			else:
				for reason: String in unmet:
					_add_panel_label(box, "- %s" % reason)
		"AVAILABLE":
			if AllianceState.has_permission("select_research"):
				var set_btn: Button = Button.new()
				set_btn.text = "Set Active Research"
				set_btn.custom_minimum_size = Vector2(0, 56)
				set_btn.pressed.connect(_on_set_active_research_pressed.bind(research_id))
				box.add_child(set_btn)
			else:
				_add_panel_label(box, "Waiting for Alliance leadership to select this research.")
			_add_panel_label(box, "Only the current Alliance Research may receive contributions.")
		"ACTIVE":
			if AllianceState.has_permission("select_research"):
				var active_btn: Button = Button.new()
				active_btn.text = "Active Research"
				active_btn.disabled = true
				active_btn.custom_minimum_size = Vector2(0, 56)
				box.add_child(active_btn)
			if level < max_level:
				_add_contribute_panel(box, research_id)
		"COMPLETED":
			_add_panel_label(box, "COMPLETED")
			_add_panel_label(box, "This technology is fully researched.")
		_:
			_add_panel_label(box, "Only the current Alliance Research may receive contributions.")


func _add_attempts_summary(parent: Control) -> void:
	var state: Dictionary = AllianceState.get_research_attempt_state()
	var cur: int = int(state.get("current_attempts", 0))
	var mx: int = int(state.get("max_attempts", 25))
	_add_panel_label(parent, "Attempts", true)
	_add_panel_label(parent, "%d / %d" % [cur, mx])
	if state.get("is_full", false):
		_add_panel_label(parent, "FULL")
	else:
		_add_panel_label(parent, "Next Recovery")
		_add_panel_label(parent, _format_seconds(int(state.get("next_recovery_seconds", 0))))


func _add_contribute_panel(parent: Control, research_id: String) -> void:
	var cost: Dictionary = AllianceState.get_research_contribution_cost(research_id)
	var resource_id: String = str(cost.get("resource", "food"))
	var amount: int = int(cost.get("amount", 0))
	var rewards: Dictionary = AllianceState.get_research_contribution_rewards(research_id)
	var research_points: int = AllianceState.get_research_points_per_contribution(research_id)
	var state: Dictionary = AllianceState.get_research_attempt_state()
	var cur: int = int(state.get("current_attempts", 0))
	var mx: int = int(state.get("max_attempts", 25))
	var diamond_cost: int = AllianceState.get_research_diamond_bypass_cost()

	_add_attempts_summary(parent)
	_add_panel_label(parent, "Contribute", true)
	_add_panel_label(parent, "Contribution Cost")
	_add_panel_label(parent, "%s %s" % [resource_id.capitalize(), _format_commas(amount)])
	_add_panel_label(parent, "Attempt Cost")
	_add_panel_label(parent, "1")
	_add_panel_label(parent, "Rewards")
	_add_panel_label(parent, "Research Progress +%s" % _format_commas(research_points))
	_add_panel_label(parent, "Personal Contribution +%s" % _format_commas(int(rewards.get("personal_contribution", 0))))
	_add_panel_label(parent, "Alliance Coins +%s" % _format_commas(int(rewards.get("alliance_coins", 0))))

	if has_node("/root/GameState"):
		_add_panel_label(parent, "You have %s %s  ◆ %s" % [
			resource_id.capitalize(),
			_format_power(int(GameState.get(resource_id))),
			_format_commas(int(GameState.diamonds)),
		])

	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(0, 72)
	if cur > 0:
		btn.text = "CONTRIBUTE"
		btn.pressed.connect(_on_research_contribute_pressed.bind(research_id, false))
	else:
		_add_panel_label(parent, "Attempts")
		_add_panel_label(parent, "%d / %d" % [cur, mx])
		_add_panel_label(parent, "Next Recovery")
		_add_panel_label(parent, _format_seconds(int(state.get("next_recovery_seconds", 0))))
		btn.text = "CONTRIBUTE FOR %d💎" % diamond_cost
		btn.pressed.connect(_on_research_contribute_pressed.bind(research_id, true))
	parent.add_child(btn)


func _open_research_screen() -> void:
	var active_id: String = AllianceState.get_active_research_id()
	_selected_research_id = active_id
	_research_category = _ui_category_for_research(active_id) if active_id != "" else "Growth"
	_view = ViewMode.RESEARCH
	_refresh()


func _ui_category_for_research(research_id: String) -> String:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	var source_cat: String = str(def.get("category", ""))
	for entry: Dictionary in AllianceState.get_research_ui_categories():
		var sources: Array = entry.get("sources", [])
		if source_cat in sources:
			return str(entry.get("ui", "Growth"))
	return "Growth"


func _build_help_view() -> void:
	if _use_backend():
		_build_backend_help_view()
		return

	_add_body_label("Backend Alliance Help unavailable. Showing local-only queue (not multiplayer).")
	_add_body_label("Embassy capacity: %d  |  Active: %d" % [
		AllianceState.get_embassy_help_capacity(),
		AllianceState.get_help_requests().size(),
	])

	var help_all_btn: Button = Button.new()
	help_all_btn.text = "Help All (Local)"
	help_all_btn.custom_minimum_size = Vector2(0, 56)
	help_all_btn.pressed.connect(_on_help_all_pressed)
	_content.add_child(help_all_btn)

	var requests: Array[Dictionary] = AllianceState.get_help_requests()
	if requests.is_empty():
		_add_body_label("No local help requests.")
		return

	for req: Dictionary in requests:
		var request_id: String = str(req.get("request_id", ""))
		var block: PanelContainer = _make_info_panel()
		_content.add_child(block)
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		block.add_child(box)
		var info: Label = Label.new()
		info.text = "%s\n%s · %s left" % [
			str(req.get("player_name", "?")),
			str(req.get("help_type", "?")).capitalize(),
			_format_seconds(int(req.get("remaining_time", 0))),
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(info)
		var help_btn: Button = Button.new()
		help_btn.text = "Help"
		help_btn.custom_minimum_size = Vector2(0, 48)
		help_btn.pressed.connect(_on_help_pressed.bind(request_id))
		box.add_child(help_btn)


func _build_backend_help_view() -> void:
	var ab: Node = _alliance_backend()
	if ab == null or not ab.is_authenticated_for_help():
		_add_body_label("Alliance Help unavailable — reconnect to Nakama.")
		return

	# Refresh without blocking forever; UI rebuilds on help_requests_changed.
	ab.refresh_help_requests()

	var auto_status: Dictionary = ab.get_auto_help_status()
	var auto_title := "Alliance Auto-Help"
	var auto_label := "Inactive"
	if bool(auto_status.get("active", false)):
		# Beta-only copy — never claim Ultra Value Monthly Card.
		auto_label = str(auto_status.get("ui_label", "Beta Testing Enabled"))
	_add_body_label("%s\n🧪 %s" % [auto_title, auto_label])

	_add_body_label("Alliance Requests")
	var eligible: Array = ab.get_eligible_help_requests()
	if eligible.is_empty():
		_add_body_label("No eligible requests to help.")
	else:
		for req_v in eligible:
			if typeof(req_v) != TYPE_DICTIONARY:
				continue
			var req: Dictionary = req_v
			var request_id: String = str(req.get("request_id", ""))
			var block: PanelContainer = _make_info_panel()
			_content.add_child(block)
			var box: VBoxContainer = VBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			block.add_child(box)
			var info: Label = Label.new()
			info.text = "%s\n%s · %s\nHelp %d / %d · %s left" % [
				str(req.get("owner_display_name", "?")),
				str(req.get("project_type", "?")),
				str(req.get("project_display_name", "?")),
				int(req.get("help_count", 0)),
				int(req.get("help_limit", 0)),
				_format_seconds(int(req.get("remaining_seconds", 0))),
			]
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(info)
			var help_btn: Button = Button.new()
			help_btn.text = "HELP"
			help_btn.custom_minimum_size = Vector2(0, 48)
			help_btn.pressed.connect(_on_backend_help_one_pressed.bind(request_id))
			box.add_child(help_btn)

	_add_body_label("Your Active Projects")
	_append_my_help_project_rows(ab)

	var help_all_btn: Button = Button.new()
	help_all_btn.text = "HELP ALL"
	help_all_btn.custom_minimum_size = Vector2(0, 64)
	help_all_btn.pressed.connect(_on_backend_help_all_pressed)
	_content.add_child(help_all_btn)


func _append_my_help_project_rows(ab: Node) -> void:
	var mine: Array = ab.get_my_active_help_requests()
	var shown_ids: Dictionary = {}
	for req_v in mine:
		if typeof(req_v) != TYPE_DICTIONARY:
			continue
		var req: Dictionary = req_v
		shown_ids[str(req.get("project_type", "")) + "|" + str(req.get("project_id", ""))] = true
		var block: PanelContainer = _make_info_panel()
		_content.add_child(block)
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		block.add_child(box)
		var info: Label = Label.new()
		var help_count: int = int(req.get("help_count", 0))
		var help_limit: int = int(req.get("help_limit", 1))
		info.text = "%s\n%s left · Help %d / %d · Progress %d%%" % [
			str(req.get("project_display_name", req.get("project_id", "?"))),
			_format_seconds(int(req.get("remaining_seconds", 0))),
			help_count,
			help_limit,
			int((float(help_count) / float(maxi(1, help_limit))) * 100.0),
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(info)

	# Expose Request Help for local active projects without a backend request yet.
	if has_node("/root/ConstructionState"):
		for job_v in ConstructionState.get_active_construction_jobs():
			if typeof(job_v) != TYPE_DICTIONARY:
				continue
			var job: Dictionary = job_v
			var pid: String = str(job.get("building_id", ""))
			var key: String = "CONSTRUCTION|" + pid
			if shown_ids.has(key) or pid == "":
				continue
			_add_request_help_row("CONSTRUCTION", pid, "Build %s → Lv %s" % [pid, str(job.get("target_level", "?"))], int(job.get("end_unix", 0)))
	if has_node("/root/ResearchState"):
		for job_v2 in ResearchState.get_active_research_jobs():
			if typeof(job_v2) != TYPE_DICTIONARY:
				continue
			var rjob: Dictionary = job_v2
			var rid: String = str(rjob.get("research_id", ""))
			var rkey: String = "RESEARCH|" + rid
			if shown_ids.has(rkey) or rid == "":
				continue
			var rem: float = float(rjob.get("time_remaining", 0.0))
			var finish: int = int(Time.get_unix_time_from_system()) + int(ceil(rem))
			_add_request_help_row("RESEARCH", rid, "Research %s" % rid, finish)
	if has_node("/root/HealingState") and HealingState.has_active_job():
		var hjob: Dictionary = HealingState.get_active_job()
		var hid: String = str(hjob.get("job_id", ""))
		var hkey: String = "HEALING|" + hid
		if not shown_ids.has(hkey) and hid != "":
			_add_request_help_row("HEALING", hid, "Healing batch %s" % hid, int(hjob.get("end_unix", 0)))


func _add_request_help_row(project_type: String, project_id: String, display_name: String, finish_unix: int) -> void:
	var block: PanelContainer = _make_info_panel()
	_content.add_child(block)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	block.add_child(box)
	var info: Label = Label.new()
	info.text = "%s\nNo Alliance Help requested yet · %s left" % [
		display_name,
		_format_seconds(maxi(0, finish_unix - int(Time.get_unix_time_from_system()))),
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(info)
	var req_btn: Button = Button.new()
	req_btn.text = "Request Alliance Help"
	req_btn.custom_minimum_size = Vector2(0, 48)
	req_btn.pressed.connect(_on_backend_request_help_pressed.bind(project_type, project_id, display_name, finish_unix))
	box.add_child(req_btn)


func _build_members_view() -> void:
	if _use_backend():
		if not _alliance_backend().has_permission("view_members"):
			_add_body_label("You cannot view the roster.")
			return
		var members: Array = _alliance_backend().get_cached_members()
		if members.is_empty():
			_add_body_label("No members found (refreshing…)")
			_alliance_backend().list_members()
			return
		for member_v in members:
			if typeof(member_v) != TYPE_DICTIONARY:
				continue
			var member: Dictionary = member_v
			var member_id: String = str(member.get("user_id", ""))
			_content.add_child(_make_member_row(member, member_id, true))
		return

	if not AllianceState.has_permission("view_members"):
		_add_body_label("You cannot view the roster.")
		return

	var local_members: Array[Dictionary] = AllianceState.get_members()
	if local_members.is_empty():
		_add_body_label("No members found.")
		return

	for member: Dictionary in local_members:
		var member_id: String = str(member.get("member_id", member.get("id", "")))
		_content.add_child(_make_member_row(member, member_id, false))


func _make_member_row(member: Dictionary, member_id: String, backend: bool) -> Control:
	const PlayerAvatarCatalog = preload("res://Scripts/UI/PlayerAvatarCatalog.gd")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 84)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.14, 0.95)
	style.border_color = Color(0.55, 0.45, 0.28, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 10)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(wrap)

	var avatar_id: String = str(member.get("avatar_id", "avatar_01"))
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(56, 56)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture = PlayerAvatarCatalog.get_texture(avatar_id, 64)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(avatar)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)

	var name_text: String = str(member.get("display_name", member.get("player_name", member.get("name", "?"))))
	var rank_text: String = str(member.get("rank", member.get("role", "?")))
	if backend:
		rank_text = "%s (%s)" % [rank_text, str(member.get("rank_display", rank_text))]
	else:
		rank_text = AllianceState.get_role_display_name(rank_text)
	var power: int = int(member.get("power", member.get("power_placeholder", 0)))
	var citadel: int = int(member.get("citadel_level", 1))
	var online: String = str(member.get("online_status", "offline"))
	var last_online: int = int(member.get("last_online", 0))
	var status_line: String = "🟢 Online" if online == "online" else "⚫ Last Online · %s" % _format_relative_time(last_online)

	var title := Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var meta := Label.new()
	meta.text = "%s · Power %s · Citadel %d\n%s" % [rank_text, _format_power(power), citadel, status_line]
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 12)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta)

	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if backend:
				_open_member_profile_or_detail(member_id)
			else:
				_selected_member_id = member_id
				_view = ViewMode.MEMBER_DETAIL
				_refresh()
		elif e is InputEventScreenTouch and e.pressed:
			if backend:
				_open_member_profile_or_detail(member_id)
			else:
				_selected_member_id = member_id
				_view = ViewMode.MEMBER_DETAIL
				_refresh()
	)
	return panel


func _open_member_profile_or_detail(member_id: String) -> void:
	## Tap opens player profile; management actions remain on Member Detail via long path.
	var hud := get_tree().get_first_node_in_group("game_hud")
	if hud != null and hud.has_method("open_player_profile"):
		hud.open_player_profile(member_id)
		return
	_selected_member_id = member_id
	_view = ViewMode.MEMBER_DETAIL
	_refresh()


func _format_relative_time(unix_ts: int) -> String:
	if unix_ts <= 0:
		return "Unknown"
	var now: int = int(Time.get_unix_time_from_system())
	var delta: int = maxi(0, now - unix_ts)
	if delta < 60:
		return "Just now"
	if delta < 3600:
		var mins: int = int(delta / 60.0)
		return "%d minute%s ago" % [mins, "" if mins == 1 else "s"]
	if delta < 86400:
		var hours: int = int(delta / 3600.0)
		return "%d hour%s ago" % [hours, "" if hours == 1 else "s"]
	var days: int = int(delta / 86400.0)
	if days == 1:
		return "1 day ago"
	return "%d days ago" % days


func _build_member_detail_view() -> void:
	if _use_backend():
		_build_backend_member_detail()
		return

	var member: Dictionary = AllianceState.get_member(_selected_member_id)
	if member.is_empty():
		_status_label.text = "Member not found."
		_view = ViewMode.MEMBERS
		_build_members_view()
		return

	var member_id: String = str(member.get("member_id", member.get("id", "")))
	var member_role: String = str(member.get("role", "R1"))

	_add_section_label(str(member.get("player_name", member.get("name", "?"))))
	_add_body_label("Rank: %s (%s)" % [member_role, AllianceState.get_role_display_name(member_role)])
	_add_body_label("Power: %s" % _format_power(int(member.get("power", 0))))
	_add_body_label("Status: %s" % str(member.get("online_status", "offline")).capitalize())

	var is_self: bool = member_id == AllianceState.LOCAL_PLAYER_ID

	if not is_self and AllianceState.has_permission("promote_members"):
		var promote_btn: Button = Button.new()
		promote_btn.text = "Promote"
		promote_btn.custom_minimum_size = Vector2(0, 52)
		promote_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.promote_member(member_id)
			_status_label.text = str(result.get("error", "Promoted.")) if not result.get("ok", false) else "Promoted."
			_refresh()
		)
		_content.add_child(promote_btn)

	if not is_self and AllianceState.has_permission("demote_members"):
		var demote_btn: Button = Button.new()
		demote_btn.text = "Demote"
		demote_btn.custom_minimum_size = Vector2(0, 52)
		demote_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.demote_member(member_id)
			_status_label.text = str(result.get("error", "Demoted.")) if not result.get("ok", false) else "Demoted."
			_refresh()
		)
		_content.add_child(demote_btn)

	if not is_self and AllianceState.has_permission("remove_members"):
		var remove_btn: Button = Button.new()
		remove_btn.text = "Remove"
		remove_btn.custom_minimum_size = Vector2(0, 52)
		remove_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.remove_member(member_id)
			if result.get("ok", false):
				_selected_member_id = ""
				_view = ViewMode.MEMBERS
				_status_label.text = "Member removed."
			else:
				_status_label.text = str(result.get("error", "Remove failed."))
			_refresh()
		)
		_content.add_child(remove_btn)

	if not is_self and AllianceState.has_permission("transfer_leadership"):
		var transfer_btn: Button = Button.new()
		transfer_btn.text = "Transfer Leadership"
		transfer_btn.custom_minimum_size = Vector2(0, 52)
		transfer_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.transfer_leadership(member_id)
			if result.get("ok", false):
				_status_label.text = "Leadership transferred."
			else:
				_status_label.text = str(result.get("error", "Transfer failed."))
			_refresh()
		)
		_content.add_child(transfer_btn)

	if is_self:
		_add_body_label("This is you. Use Leave Alliance from Alliance Home to leave.")


func _build_backend_member_detail() -> void:
	var member: Dictionary = {}
	for m in _alliance_backend().get_cached_members():
		if typeof(m) == TYPE_DICTIONARY and str(m.get("user_id", "")) == _selected_member_id:
			member = m
			break
	if member.is_empty():
		_status_label.text = "Member not found."
		_view = ViewMode.MEMBERS
		_build_members_view()
		return

	var member_id: String = str(member.get("user_id", ""))
	var member_role: String = str(member.get("rank", "R1"))
	var local_uid: String = _nakama_connection().get_user_id() if has_node("/root/NakamaConnection") else ""
	var is_self: bool = member_id == local_uid

	_add_section_label(str(member.get("display_name", "?")))
	_add_body_label("Rank: %s (%s)" % [member_role, str(member.get("rank_display", _alliance_backend().get_role_display_name(member_role)))])
	_add_body_label("Power: %s" % _format_power(int(member.get("power", 0))))
	_add_body_label("Citadel: %d" % int(member.get("citadel_level", 1)))
	var online: String = str(member.get("online_status", "offline"))
	if online == "online":
		_add_body_label("Status: 🟢 Online")
	else:
		_add_body_label("Status: ⚫ Last Online · %s" % _format_relative_time(int(member.get("last_online", 0))))

	if not is_self:
		var profile_btn: Button = Button.new()
		profile_btn.text = "View Profile"
		profile_btn.custom_minimum_size = Vector2(0, 52)
		profile_btn.pressed.connect(func() -> void:
			_open_member_profile_or_detail(member_id)
		)
		_content.add_child(profile_btn)
		var msg_btn: Button = Button.new()
		msg_btn.text = "Message"
		msg_btn.custom_minimum_size = Vector2(0, 52)
		msg_btn.pressed.connect(func() -> void:
			var hud := get_tree().get_first_node_in_group("game_hud")
			if hud != null and hud.has_method("open_private_chat"):
				hud.open_private_chat(member_id, str(member.get("display_name", "Player")))
		)
		_content.add_child(msg_btn)
	_add_body_label("Kingdom: %s" % str(member.get("kingdom_id", "")))

	if not is_self and _alliance_backend().has_permission("promote"):
		var promote_btn: Button = Button.new()
		promote_btn.text = "Promote"
		promote_btn.custom_minimum_size = Vector2(0, 52)
		promote_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().promote_member(member_id)
			_set_flash_status("Promoted." if bool(result.get("ok", false)) else str(result.get("error", "Promote failed.")))
			_refresh()
		)
		_content.add_child(promote_btn)

	if not is_self and _alliance_backend().has_permission("demote"):
		var demote_btn: Button = Button.new()
		demote_btn.text = "Demote"
		demote_btn.custom_minimum_size = Vector2(0, 52)
		demote_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().demote_member(member_id)
			_set_flash_status("Demoted." if bool(result.get("ok", false)) else str(result.get("error", "Demote failed.")))
			_refresh()
		)
		_content.add_child(demote_btn)

	if not is_self and _alliance_backend().has_permission("kick"):
		var remove_btn: Button = Button.new()
		remove_btn.text = "Kick"
		remove_btn.custom_minimum_size = Vector2(0, 52)
		remove_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().kick_member(member_id)
			if bool(result.get("ok", false)):
				_selected_member_id = ""
				_view = ViewMode.MEMBERS
				_status_label.text = "Member kicked."
			else:
				_status_label.text = str(result.get("error", "Kick failed."))
			_refresh()
		)
		_content.add_child(remove_btn)

	if not is_self and _alliance_backend().has_permission("transfer_leadership"):
		var transfer_btn: Button = Button.new()
		transfer_btn.text = "Transfer Leadership"
		transfer_btn.custom_minimum_size = Vector2(0, 52)
		transfer_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().transfer_leadership(member_id)
			_set_flash_status("Leadership transferred." if bool(result.get("ok", false)) else str(result.get("error", "Transfer failed.")))
			_refresh()
		)
		_content.add_child(transfer_btn)

	if is_self:
		_add_body_label("This is you. Use Leave Alliance from Alliance Home to leave.")


func _build_applications_view() -> void:
	if _use_backend():
		if not _alliance_backend().has_permission("view_applications") and not _alliance_backend().has_permission("approve"):
			_add_body_label("You do not have permission to review applications.")
			return
		_add_section_label("Pending Applications")
		await _alliance_backend().list_join_requests()
		var apps: Array = _alliance_backend().get_cached_applications()
		if apps.is_empty():
			_add_body_label("No pending applications.")
			return
		for app_v in apps:
			if typeof(app_v) != TYPE_DICTIONARY:
				continue
			var app: Dictionary = app_v
			var uid: String = str(app.get("user_id", ""))
			var block: PanelContainer = _make_info_panel()
			_content.add_child(block)
			var box: VBoxContainer = VBoxContainer.new()
			box.add_theme_constant_override("separation", 8)
			block.add_child(box)
			var display: String = str(app.get("display_name", uid)).strip_edges()
			if display == "":
				display = uid
			_add_panel_label(box, display, true)
			_add_panel_label(box, "Power: %d" % int(app.get("power", app.get("power_placeholder", 0))))
			_add_panel_label(box, "Citadel: %d" % int(app.get("citadel_level", 1)))
			var actions: HBoxContainer = HBoxContainer.new()
			actions.add_theme_constant_override("separation", 8)
			box.add_child(actions)
			var accept_btn: Button = Button.new()
			accept_btn.text = "Approve"
			accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			accept_btn.custom_minimum_size = Vector2(0, 48)
			accept_btn.pressed.connect(func() -> void:
				var result: Dictionary = await _alliance_backend().approve_application(uid)
				_set_flash_status("Application approved." if bool(result.get("ok", false)) else str(result.get("error", "Approve failed.")))
				_refresh()
			)
			actions.add_child(accept_btn)
			var reject_btn: Button = Button.new()
			reject_btn.text = "Reject"
			reject_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			reject_btn.custom_minimum_size = Vector2(0, 48)
			reject_btn.pressed.connect(func() -> void:
				var result: Dictionary = await _alliance_backend().reject_application(uid)
				_set_flash_status("Application rejected." if bool(result.get("ok", false)) else str(result.get("error", "Reject failed.")))
				_refresh()
			)
			actions.add_child(reject_btn)
		return

	if not AllianceState.has_permission("review_applications"):
		_add_body_label("You do not have permission to review applications.")
		return

	var local_apps: Array[Dictionary] = AllianceState.get_pending_applications()
	if local_apps.is_empty():
		_add_body_label("No pending applications.")
		return

	for app: Dictionary in local_apps:
		var app_id: String = str(app.get("application_id", ""))
		var block: PanelContainer = _make_info_panel()
		_content.add_child(block)
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		block.add_child(box)

		var info: Label = Label.new()
		info.text = "%s\nPower %s" % [
			str(app.get("player_name", "?")),
			_format_power(int(app.get("player_power", 0))),
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(info)

		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		box.add_child(actions)

		var accept_btn: Button = Button.new()
		accept_btn.text = "Accept"
		accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accept_btn.custom_minimum_size = Vector2(0, 48)
		accept_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.accept_application(app_id)
			_status_label.text = str(result.get("error", "Accepted.")) if not result.get("ok", false) else "Application accepted."
			_refresh()
		)
		actions.add_child(accept_btn)

		var reject_btn: Button = Button.new()
		reject_btn.text = "Reject"
		reject_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reject_btn.custom_minimum_size = Vector2(0, 48)
		reject_btn.pressed.connect(func() -> void:
			var result: Dictionary = AllianceState.reject_application(app_id)
			_status_label.text = str(result.get("error", "Rejected.")) if not result.get("ok", false) else "Application rejected."
			_refresh()
		)
		actions.add_child(reject_btn)


func _build_settings_view() -> void:
	_add_section_label("Alliance Settings")
	if not _use_backend():
		_add_body_label("Settings require a live multiplayer Alliance.")
		return
	if not _alliance_backend().has_permission("edit_profile"):
		_add_body_label("Only the Leader can edit Alliance settings.")
		return

	var alliance: Dictionary = _alliance_backend().get_cached_alliance()
	_add_body_label("Changes sync immediately for all members.")

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_content.add_child(name_row)
	var name_caption: Label = Label.new()
	name_caption.text = "Name"
	name_caption.custom_minimum_size = Vector2(110, 0)
	name_row.add_child(name_caption)
	_name_edit = LineEdit.new()
	_name_edit.text = str(alliance.get("name", _alliance_backend().get_alliance_name()))
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 24
	name_row.add_child(_name_edit)

	var desc_caption: Label = Label.new()
	desc_caption.text = "Description"
	_content.add_child(desc_caption)
	_desc_edit = TextEdit.new()
	_desc_edit.text = str(alliance.get("description", ""))
	_desc_edit.custom_minimum_size = Vector2(0, 88)
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content.add_child(_desc_edit)

	var announce_caption: Label = Label.new()
	announce_caption.text = "Announcement"
	_content.add_child(announce_caption)
	_settings_announce_edit = TextEdit.new()
	_settings_announce_edit.text = str(alliance.get("announcement", ""))
	_settings_announce_edit.custom_minimum_size = Vector2(0, 72)
	_settings_announce_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content.add_child(_settings_announce_edit)

	var lang_row: HBoxContainer = HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	_content.add_child(lang_row)
	var lang_caption: Label = Label.new()
	lang_caption.text = "Language"
	lang_caption.custom_minimum_size = Vector2(110, 0)
	lang_row.add_child(lang_caption)
	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_option.custom_minimum_size = Vector2(0, 44)
	var cur_lang: String = str(alliance.get("language", "en"))
	var lang_sel: int = 0
	for i in range(CREATE_LANGS.size()):
		var lang_v: Dictionary = CREATE_LANGS[i]
		_lang_option.add_item(str(lang_v.get("label", "")), i)
		_lang_option.set_item_metadata(i, str(lang_v.get("id", "en")))
		if str(lang_v.get("id", "")) == cur_lang:
			lang_sel = i
	_lang_option.select(lang_sel)
	lang_row.add_child(_lang_option)

	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_content.add_child(join_row)
	var join_caption: Label = Label.new()
	join_caption.text = "Join Type"
	join_caption.custom_minimum_size = Vector2(110, 0)
	join_row.add_child(join_caption)
	_join_type_option = OptionButton.new()
	_join_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_type_option.custom_minimum_size = Vector2(0, 44)
	_join_type_option.add_item("Open", 0)
	_join_type_option.set_item_metadata(0, "open")
	_join_type_option.add_item("Approval Required", 1)
	_join_type_option.set_item_metadata(1, "apply")
	var cur_jt: String = str(alliance.get("join_type", "apply"))
	_join_type_option.select(0 if cur_jt == "open" else 1)
	join_row.add_child(_join_type_option)

	var cit_row: HBoxContainer = HBoxContainer.new()
	cit_row.add_theme_constant_override("separation", 8)
	_content.add_child(cit_row)
	var cit_caption: Label = Label.new()
	cit_caption.text = "Min Citadel"
	cit_caption.custom_minimum_size = Vector2(110, 0)
	cit_row.add_child(cit_caption)
	_min_citadel_spin = SpinBox.new()
	_min_citadel_spin.min_value = 0
	_min_citadel_spin.max_value = 100
	_min_citadel_spin.value = int(alliance.get("min_citadel_level", 0))
	_min_citadel_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cit_row.add_child(_min_citadel_spin)

	_add_body_label("Alliance emblem — Coming Soon")

	var save_btn: Button = Button.new()
	save_btn.text = "Save Settings"
	save_btn.custom_minimum_size = Vector2(0, 56)
	save_btn.pressed.connect(_on_save_settings_pressed)
	_content.add_child(save_btn)


func _on_save_settings_pressed() -> void:
	if not _use_backend():
		return
	var language: String = "en"
	if _lang_option != null and _lang_option.selected >= 0:
		language = str(_lang_option.get_item_metadata(_lang_option.selected))
	var join_type: String = "apply"
	if _join_type_option != null and _join_type_option.selected >= 0:
		join_type = str(_join_type_option.get_item_metadata(_join_type_option.selected))
	var fields: Dictionary = {
		"name": _name_edit.text.strip_edges() if _name_edit else "",
		"description": _desc_edit.text.strip_edges() if _desc_edit else "",
		"announcement": _settings_announce_edit.text.strip_edges() if _settings_announce_edit else "",
		"language": language,
		"join_type": join_type,
		"min_citadel_level": int(_min_citadel_spin.value) if _min_citadel_spin else 0,
	}
	var result: Dictionary = await _alliance_backend().update_alliance_profile(fields)
	if bool(result.get("ok", false)):
		_set_flash_status("Settings saved.")
	else:
		_set_flash_status(str(result.get("error", "Save failed.")))
	_refresh()


func _build_create_view() -> void:
	_add_section_label("Raise a New Banner")
	_add_body_label("Choose a name and tag for your Alliance. You become Leader (R5) on creation.")

	if not _use_backend():
		var nc: Node = _nakama_connection()
		if nc != null and nc.is_authenticated():
			_add_body_label("Loading your profile… Create unlocks once multiplayer is ready.")
			var wait_btn: Button = Button.new()
			wait_btn.text = "Retry"
			wait_btn.custom_minimum_size = Vector2(0, 48)
			wait_btn.pressed.connect(func() -> void:
				await _alliance_backend().refresh_profile()
				_refresh()
			)
			_content.add_child(wait_btn)
			return
		_add_body_label("Connect to multiplayer to create a real Alliance.")
		return

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_content.add_child(name_row)
	var name_caption: Label = Label.new()
	name_caption.text = "Name"
	name_caption.custom_minimum_size = Vector2(110, 0)
	name_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_caption)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Alliance name (3–24)"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 24
	_name_edit.text_changed.connect(func(_t: String) -> void: _update_create_form_validity())
	name_row.add_child(_name_edit)

	var tag_row: HBoxContainer = HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	_content.add_child(tag_row)
	var tag_caption: Label = Label.new()
	tag_caption.text = "Tag"
	tag_caption.custom_minimum_size = Vector2(110, 0)
	tag_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(tag_caption)
	_tag_edit = LineEdit.new()
	_tag_edit.placeholder_text = "3–4 letters/numbers"
	_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_edit.max_length = 4
	_tag_edit.text_changed.connect(func(_t: String) -> void: _update_create_form_validity())
	tag_row.add_child(_tag_edit)

	var desc_caption: Label = Label.new()
	desc_caption.text = "Description (optional)"
	desc_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(desc_caption)
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 88)
	_desc_edit.placeholder_text = "Tell knights what your banner stands for…"
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content.add_child(_desc_edit)

	var lang_row: HBoxContainer = HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	_content.add_child(lang_row)
	var lang_caption: Label = Label.new()
	lang_caption.text = "Language"
	lang_caption.custom_minimum_size = Vector2(110, 0)
	lang_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lang_row.add_child(lang_caption)
	_lang_option = OptionButton.new()
	_lang_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_option.custom_minimum_size = Vector2(0, 44)
	for lang_v in CREATE_LANGS:
		_lang_option.add_item(str(lang_v.get("label", "")), _lang_option.item_count)
		_lang_option.set_item_metadata(_lang_option.item_count - 1, str(lang_v.get("id", "en")))
	_lang_option.select(0)
	lang_row.add_child(_lang_option)

	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_content.add_child(join_row)
	var join_caption: Label = Label.new()
	join_caption.text = "Join Type"
	join_caption.custom_minimum_size = Vector2(110, 0)
	join_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	join_row.add_child(join_caption)
	_join_type_option = OptionButton.new()
	_join_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_type_option.custom_minimum_size = Vector2(0, 44)
	_join_type_option.add_item("Open — anyone meeting requirements joins", 0)
	_join_type_option.set_item_metadata(0, "open")
	_join_type_option.add_item("Approval Required — apply to join", 1)
	_join_type_option.set_item_metadata(1, "apply")
	_join_type_option.select(1)
	join_row.add_child(_join_type_option)

	var cit_row: HBoxContainer = HBoxContainer.new()
	cit_row.add_theme_constant_override("separation", 8)
	_content.add_child(cit_row)
	var cit_caption: Label = Label.new()
	cit_caption.text = "Min Citadel"
	cit_caption.custom_minimum_size = Vector2(110, 0)
	cit_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cit_row.add_child(cit_caption)
	_min_citadel_spin = SpinBox.new()
	_min_citadel_spin.min_value = 0
	_min_citadel_spin.max_value = 100
	_min_citadel_spin.value = 0
	_min_citadel_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_min_citadel_spin.custom_minimum_size = Vector2(0, 44)
	cit_row.add_child(_min_citadel_spin)

	_create_error_label = Label.new()
	_create_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_create_error_label.modulate = Color(1.0, 0.55, 0.45)
	_create_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_create_error_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_content.add_child(actions)
	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.custom_minimum_size = Vector2(0, 56)
	cancel_btn.pressed.connect(func() -> void:
		_view = ViewMode.LOBBY
		_refresh()
	)
	actions.add_child(cancel_btn)
	_create_button = Button.new()
	_create_button.text = "Create Alliance"
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button.custom_minimum_size = Vector2(0, 56)
	_create_button.pressed.connect(_on_create_pressed)
	actions.add_child(_create_button)
	_update_create_form_validity()


func _update_create_form_validity() -> void:
	if _create_button == null:
		return
	var err: String = _validate_create_fields()
	if _create_error_label:
		_create_error_label.text = err
	_create_button.disabled = err != ""


func _validate_create_fields() -> String:
	var name_text: String = _name_edit.text.strip_edges() if _name_edit else ""
	var tag_text: String = _tag_edit.text.strip_edges().to_upper() if _tag_edit else ""
	if name_text.length() < 3 or name_text.length() > 24:
		return "Alliance name must be 3–24 characters."
	if RegEx.create_from_string("[<>{}\\\\`]").search(name_text) != null:
		return "Alliance name contains illegal characters."
	if tag_text.length() < 3 or tag_text.length() > 4:
		return "Tag must be 3–4 characters."
	if RegEx.create_from_string("^[A-Z0-9]+$").search(tag_text) == null:
		return "Tag may only use letters and numbers."
	return ""


func _build_join_view() -> void:
	if _use_backend():
		_add_section_label("Find an Alliance")
		_add_body_label("Open alliances join instantly. Approval Required alliances need an application.")

		var search_row: HBoxContainer = HBoxContainer.new()
		search_row.add_theme_constant_override("separation", 8)
		_content.add_child(search_row)
		_search_query_edit = LineEdit.new()
		_search_query_edit.placeholder_text = "Search by name or tag…"
		_search_query_edit.text = _search_query
		_search_query_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search_query_edit.custom_minimum_size = Vector2(0, 48)
		search_row.add_child(_search_query_edit)
		var search_btn: Button = Button.new()
		search_btn.text = "Search"
		search_btn.custom_minimum_size = Vector2(110, 48)
		search_btn.pressed.connect(func() -> void:
			_search_query = _search_query_edit.text.strip_edges() if _search_query_edit else ""
			_refresh()
		)
		search_row.add_child(search_btn)

		if OS.is_debug_build():
			_join_id_edit = LineEdit.new()
			_join_id_edit.placeholder_text = "Dev: Alliance ID"
			_join_id_edit.custom_minimum_size = Vector2(0, 44)
			_content.add_child(_join_id_edit)
			var apply_btn: Button = Button.new()
			apply_btn.text = "Join / Apply by ID"
			apply_btn.custom_minimum_size = Vector2(0, 48)
			apply_btn.pressed.connect(func() -> void:
				var aid: String = _join_id_edit.text if _join_id_edit else ""
				await _on_join_pressed(aid.strip_edges())
			)
			_content.add_child(apply_btn)

		var query: String = _search_query
		var listed: Dictionary = await _alliance_backend().list_alliances(query)
		var alliances: Array = listed.get("alliances", []) if bool(listed.get("ok", false)) else []
		if alliances.is_empty():
			_add_body_label("No alliances found. Create one to raise the first banner.")
		else:
			for entry_v in alliances:
				if typeof(entry_v) != TYPE_DICTIONARY:
					continue
				_add_alliance_search_card(entry_v)
		return

	_add_section_label("Join an Alliance")
	_add_body_label("Connect to multiplayer to browse live alliances.")


func _add_alliance_search_card(entry: Dictionary) -> void:
	var entry_id: String = str(entry.get("alliance_id", ""))
	var name_text: String = str(entry.get("name", "")).strip_edges()
	var tag: String = str(entry.get("tag", "")).strip_edges()
	if name_text == "" or name_text.to_lower().begins_with("placeholder"):
		if not OS.is_debug_build():
			return
	var join_type: String = str(entry.get("join_type", "apply"))
	var is_open: bool = join_type == "open" or bool(entry.get("open", false))
	var members: int = int(entry.get("member_count", 0))
	var limit: int = int(entry.get("member_limit", 100))
	var lang: String = str(entry.get("language", "en")).to_upper()
	var min_cit: int = int(entry.get("min_citadel_level", 0))
	var preview: String = str(entry.get("description_preview", entry.get("description", ""))).strip_edges()
	var power: int = int(entry.get("alliance_power_placeholder", 0))

	var block: PanelContainer = _make_info_panel()
	_content.add_child(block)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	block.add_child(box)
	_add_panel_label(box, "[%s] %s" % [tag, name_text], true)
	_add_panel_label(box, "Members: %d/%d" % [members, limit])
	_add_panel_label(box, ("%s OPEN" % "🌍") if is_open else ("%s Approval Required" % "🔒"))
	_add_panel_label(box, "Language: %s · Min Citadel: %d" % [lang, min_cit])
	if power > 0:
		_add_panel_label(box, "Power: %d" % power)
	if preview != "":
		_add_panel_label(box, preview)
	var action_btn: Button = Button.new()
	action_btn.text = "Join" if is_open else "Apply"
	action_btn.custom_minimum_size = Vector2(0, 52)
	action_btn.pressed.connect(_on_join_pressed.bind(entry_id))
	box.add_child(action_btn)


func _build_invites_view() -> void:
	_add_section_label("Alliance Invites")
	if not _use_backend():
		_add_body_label("Invites require Nakama authentication.")
		return
	await _alliance_backend().list_my_invites()
	var invites: Array = _alliance_backend().get_cached_invites()
	if invites.is_empty():
		_add_body_label("No pending invites.")
		return
	for inv_v in invites:
		if typeof(inv_v) != TYPE_DICTIONARY:
			continue
		var inv: Dictionary = inv_v
		var invite_id: String = str(inv.get("invite_id", ""))
		var block: PanelContainer = _make_info_panel()
		_content.add_child(block)
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		block.add_child(box)
		_add_panel_label(box, "[%s] %s" % [str(inv.get("alliance_tag", "")), str(inv.get("alliance_name", ""))], true)
		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		box.add_child(actions)
		var accept_btn: Button = Button.new()
		accept_btn.text = "Accept"
		accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accept_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().accept_invite(invite_id)
			_status_label.text = str(result.get("error", "Joined.")) if not bool(result.get("ok", false)) else "Invite accepted."
			if bool(result.get("ok", false)):
				_view = ViewMode.HOME
			_refresh()
		)
		actions.add_child(accept_btn)
		var reject_btn: Button = Button.new()
		reject_btn.text = "Reject"
		reject_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reject_btn.pressed.connect(func() -> void:
			var result: Dictionary = await _alliance_backend().reject_invite(invite_id)
			_status_label.text = str(result.get("error", "Rejected.")) if not bool(result.get("ok", false)) else "Invite rejected."
			_refresh()
		)
		actions.add_child(reject_btn)


func _on_create_pressed() -> void:
	var err: String = _validate_create_fields()
	if err != "":
		if _create_error_label:
			_create_error_label.text = err
		_set_flash_status(err)
		_status_label.text = err
		return

	var name_text: String = _name_edit.text.strip_edges() if _name_edit else ""
	var tag_text: String = _tag_edit.text.strip_edges().to_upper() if _tag_edit else ""
	var description: String = _desc_edit.text.strip_edges() if _desc_edit else ""
	var language: String = "en"
	if _lang_option != null and _lang_option.selected >= 0:
		language = str(_lang_option.get_item_metadata(_lang_option.selected))
	var join_type: String = "apply"
	if _join_type_option != null and _join_type_option.selected >= 0:
		join_type = str(_join_type_option.get_item_metadata(_join_type_option.selected))
	var min_citadel: int = int(_min_citadel_spin.value) if _min_citadel_spin else 0

	if _create_button:
		_create_button.disabled = true
	_set_flash_status("Creating alliance…")
	_status_label.text = "Creating alliance…"

	var nc: Node = _nakama_connection()
	if nc != null and nc.is_authenticated():
		var result_b: Dictionary = await _alliance_backend().create_alliance(name_text, tag_text, {
			"description": description,
			"language": language,
			"join_type": join_type,
			"min_citadel_level": min_citadel,
		})
		if not bool(result_b.get("ok", false)):
			var fail: String = str(result_b.get("error", "Create failed."))
			if _create_error_label:
				_create_error_label.text = fail
			_set_flash_status(fail)
			_status_label.text = fail
			if _create_button:
				_update_create_form_validity()
			return
		if has_node("/root/ChatManager"):
			await _chat_manager().ensure_alliance_joined()
		_view = ViewMode.HOME
		_set_flash_status("Alliance created. You are Leader (R5).")
		_refresh()
		return

	_set_flash_status("Connect to multiplayer to create an Alliance.")
	_status_label.text = "Connect to multiplayer to create an Alliance."
	if _create_button:
		_update_create_form_validity()


func _on_join_pressed(target_id: String) -> void:
	if target_id.strip_edges() == "":
		_set_flash_status("Select an alliance to join.")
		_status_label.text = "Select an alliance to join."
		return
	if _use_backend() or (_nakama_connection() != null and _nakama_connection().is_authenticated()):
		var result_b: Dictionary = await _alliance_backend().join_alliance(target_id)
		if not bool(result_b.get("ok", false)):
			_set_flash_status(str(result_b.get("error", "Join failed.")))
			_status_label.text = str(result_b.get("error", "Join failed."))
			return
		if bool(result_b.get("pending", false)):
			_set_flash_status(str(result_b.get("message", "Application sent.")))
			_refresh()
			return
		if has_node("/root/ChatManager"):
			await _chat_manager().ensure_alliance_joined()
		_view = ViewMode.HOME
		_set_flash_status(str(result_b.get("message", "Joined alliance.")))
		_refresh()
		return

	_set_flash_status("Connect to multiplayer to join an Alliance.")
	_status_label.text = "Connect to multiplayer to join an Alliance."


func _on_leave_pressed() -> void:
	if _use_backend():
		var result_b: Dictionary = await _alliance_backend().leave_alliance()
		if not bool(result_b.get("ok", false)):
			_set_flash_status(str(result_b.get("error", "Leave failed.")))
			_status_label.text = str(result_b.get("error", "Leave failed."))
			return
		_selected_member_id = ""
		_coming_soon_title = ""
		_view = ViewMode.LOBBY
		_set_flash_status("Left alliance.")
		_refresh()
		return

	var result: Dictionary = AllianceState.leave_alliance()
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Leave failed."))
		return
	_selected_member_id = ""
	_coming_soon_title = ""
	_view = ViewMode.LOBBY
	_set_flash_status("Left alliance.")
	_refresh()


func _on_invite_pressed() -> void:
	if not _use_backend() or _invite_user_edit == null:
		return
	var uid: String = _invite_user_edit.text.strip_edges()
	var result: Dictionary = await _alliance_backend().invite_player(uid)
	_status_label.text = str(result.get("error", "Invite sent.")) if not bool(result.get("ok", false)) else "Invite sent."


func _on_set_active_research_pressed(research_id: String) -> void:
	var result: Dictionary = AllianceState.set_active_research(research_id)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Could not set active research."))
		return
	_refresh()
	_status_label.text = "Active research updated."


func _on_research_contribute_pressed(research_id: String, use_diamond_bypass: bool) -> void:
	var result: Dictionary = AllianceState.contribute_to_research(research_id, use_diamond_bypass)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Contribution failed."))
		return
	if result.get("needs_next_selection", false):
		_selected_research_id = ""
	_refresh()
	var msg: String = "Contribution applied (+%s research, +%s personal, +%s coins)." % [
		str(result.get("research_points", 0)),
		str(result.get("personal_contribution", result.get("points", 0))),
		str(result.get("alliance_coins", 0)),
	]
	if result.get("used_diamond_bypass", false):
		msg = "Diamond contribution applied (+%s research, +%s personal, +%s coins)." % [
			str(result.get("research_points", 0)),
			str(result.get("personal_contribution", result.get("points", 0))),
			str(result.get("alliance_coins", 0)),
		]
	if int(result.get("levels_gained", 0)) > 0:
		msg += " Level complete!"
		if result.get("maxed", false):
			msg += " Technology maxed."
		else:
			msg += " Leadership must select the next project."
	_status_label.text = msg


func _on_help_pressed(request_id: String) -> void:
	var result: Dictionary = AllianceState.help_request(request_id)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Help failed."))
		return
	_refresh()
	_status_label.text = "Helped an alliance member."


func _on_help_all_pressed() -> void:
	var result: Dictionary = AllianceState.help_all_requests()
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Help All failed."))
		return
	_refresh()
	_status_label.text = "Helped all (%s)." % str(result.get("removed", 0))


func _on_create_help_pressed(help_type: String) -> void:
	var result: Dictionary = AllianceState.create_help_request(help_type)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Request failed."))
		return
	_refresh()
	_status_label.text = "Help request posted."


func _on_backend_help_one_pressed(request_id: String) -> void:
	var ab: Node = _alliance_backend()
	if ab == null:
		_status_label.text = "Alliance Help unavailable."
		return
	var result: Dictionary = await ab.help_one(request_id)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Help failed."))
		return
	_status_label.text = "Helped (−%ss)." % str(result.get("seconds_reduced", 0))
	_refresh()


func _on_backend_help_all_pressed() -> void:
	var ab: Node = _alliance_backend()
	if ab == null:
		_status_label.text = "Alliance Help unavailable."
		return
	var result: Dictionary = await ab.help_all(false)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Help All failed."))
		return
	_status_label.text = "Helped all (%s)." % str(result.get("helped_count", 0))
	_refresh()


func _on_backend_request_help_pressed(project_type: String, project_id: String, display_name: String, finish_unix: int) -> void:
	var ab: Node = _alliance_backend()
	if ab == null:
		_status_label.text = "Alliance Help unavailable."
		return
	var result: Dictionary = await ab.create_help_request(project_type, project_id, display_name, finish_unix)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Request failed."))
		return
	_status_label.text = "Alliance Help requested."
	_refresh()


func _on_backend_help_changed(_eligible: Array, _mine: Array) -> void:
	if visible and _view == ViewMode.HELP:
		_refresh()


func _on_backend_auto_help_changed(_status: Dictionary) -> void:
	if visible and _view == ViewMode.HELP:
		_refresh()


func _add_banner_panel(eyebrow: String, title: String) -> void:
	var banner: PanelContainer = _make_info_panel()
	_content.add_child(banner)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	banner.add_child(box)

	var eye: Label = Label.new()
	eye.text = eyebrow
	eye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eye.add_theme_font_size_override("font_size", 18)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(eye)

	var title_lbl: Label = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_lbl)


func _make_info_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.16, 0.92)
	style.border_color = Color(0.55, 0.45, 0.28, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_panel_label(parent: Control, text: String, emphasize: bool = false) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if emphasize:
		label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)


func _format_seconds(seconds: int) -> String:
	var safe: int = max(0, seconds)
	var mins: int = int(safe / 60.0)
	var secs: int = safe % 60
	if mins >= 60:
		var hours: int = int(mins / 60.0)
		mins = mins % 60
		return "%dh %dm" % [hours, mins]
	return "%dm %ds" % [mins, secs]


func _format_power(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)


func _format_commas(value: int) -> String:
	var negative: bool = value < 0
	var n: int = abs(value)
	var s: String = str(n)
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	if negative:
		return "-" + out
	return out


func _to_roman(value: int) -> String:
	var n: int = clampi(value, 1, 20)
	var numerals: Array[Array] = [
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
	]
	var result: String = ""
	for pair: Array in numerals:
		var v: int = int(pair[0])
		var sym: String = str(pair[1])
		while n >= v:
			result += sym
			n -= v
	return result


func _add_section_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)


func _add_body_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)


func _add_roles_hint() -> void:
	if not has_node("/root/DataManager"):
		return
	var data: Dictionary = DataManager.get_alliance_data()
	var roles: Dictionary = data.get("allianceRoles", {})
	if roles.is_empty():
		return
	var role_keys: PackedStringArray = PackedStringArray()
	for key: Variant in roles.keys():
		role_keys.append("%s %s" % [str(key), AllianceState.get_role_display_name(str(key))])
	_add_body_label("Ranks: %s" % ", ".join(role_keys))


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
