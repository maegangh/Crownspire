extends Control

## Alliance Home hub UI refactor.
## Navigation only — reuses Sprint 1A/1B/1C AllianceState APIs unchanged.

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
}

var _view: ViewMode = ViewMode.LOBBY
var _coming_soon_title: String = ""
var _status_label: Label
var _title_label: Label
var _back_button: Button
var _content: VBoxContainer
var _name_edit: LineEdit
var _tag_edit: LineEdit
var _selected_member_id: String = ""
var _research_category: String = "Growth"
var _selected_research_id: String = ""

const NAV_CARDS: Array[Dictionary] = [
	{"id": "members", "title": "Members", "subtitle": "Roster & ranks", "live": true},
	{"id": "help", "title": "Help", "subtitle": "Aid allies", "live": true},
	{"id": "research", "title": "Research", "subtitle": "Alliance tech", "live": true},
	{"id": "applications", "title": "Applications", "subtitle": "Review joins", "live": true},
	{"id": "gifts", "title": "Gifts", "subtitle": "Coming Soon", "live": false},
	{"id": "territory", "title": "Territory", "subtitle": "Coming Soon", "live": false},
	{"id": "shop", "title": "Shop", "subtitle": "Coming Soon", "live": false},
	{"id": "rankings", "title": "Rankings", "subtitle": "Coming Soon", "live": false},
	{"id": "settings", "title": "Settings", "subtitle": "Coming Soon", "live": false},
]


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()

	if has_node("/root/AllianceState"):
		if not AllianceState.alliance_changed.is_connected(_on_alliance_changed):
			AllianceState.alliance_changed.connect(_on_alliance_changed)


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_selected_member_id = ""
	_coming_soon_title = ""
	_selected_research_id = ""
	_research_category = "Growth"
	if AllianceState.is_in_alliance():
		_view = ViewMode.HOME
	else:
		_view = ViewMode.LOBBY
	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = ViewMode.LOBBY
	_selected_member_id = ""
	_coming_soon_title = ""
	_selected_research_id = ""


func _on_alliance_changed() -> void:
	if not visible:
		return
	if not AllianceState.is_in_alliance():
		_view = ViewMode.LOBBY
		_selected_member_id = ""
		_coming_soon_title = ""
		_selected_research_id = ""
	elif _view in [ViewMode.LOBBY, ViewMode.CREATE, ViewMode.JOIN]:
		_view = ViewMode.HOME
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

	if not has_node("/root/AllianceState"):
		_status_label.text = "AllianceState is not loaded."
		return

	match _view:
		ViewMode.CREATE:
			_build_create_view()
		ViewMode.JOIN:
			_build_join_view()
		ViewMode.HOME:
			_build_home_view()
		ViewMode.MEMBERS:
			_build_members_view()
		ViewMode.MEMBER_DETAIL:
			_build_member_detail_view()
		ViewMode.HELP:
			_build_help_view()
		ViewMode.APPLICATIONS:
			_build_applications_view()
		ViewMode.RESEARCH:
			_build_research_view()
		ViewMode.COMING_SOON:
			_build_coming_soon_view()
		_:
			if AllianceState.is_in_alliance():
				_view = ViewMode.HOME
				_build_home_view()
			else:
				_build_unjoined_view()


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
		ViewMode.HOME:
			_title_label.text = "ALLIANCE HOME"
		ViewMode.MEMBERS, ViewMode.MEMBER_DETAIL:
			_title_label.text = "MEMBERS"
		ViewMode.HELP:
			_title_label.text = "HELP"
		ViewMode.APPLICATIONS:
			_title_label.text = "APPLICATIONS"
		ViewMode.RESEARCH:
			_title_label.text = "ALLIANCE RESEARCH"
		ViewMode.COMING_SOON:
			_title_label.text = _coming_soon_title.to_upper()
		_:
			_title_label.text = "ALLIANCE"


func _on_back_pressed() -> void:
	match _view:
		ViewMode.MEMBER_DETAIL:
			_selected_member_id = ""
			_view = ViewMode.MEMBERS
		ViewMode.CREATE, ViewMode.JOIN:
			_view = ViewMode.LOBBY
		ViewMode.MEMBERS, ViewMode.HELP, ViewMode.APPLICATIONS, ViewMode.RESEARCH, ViewMode.COMING_SOON:
			_coming_soon_title = ""
			_selected_research_id = ""
			_view = ViewMode.HOME
		_:
			_view = ViewMode.HOME if AllianceState.is_in_alliance() else ViewMode.LOBBY
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
			_coming_soon_title = "Settings"
			_view = ViewMode.COMING_SOON
		_:
			return
	_refresh()


func _build_unjoined_view() -> void:
	_add_banner_panel("No Alliance", "Join a banner or raise your own.")
	_add_body_label("Create a new Alliance or join one from the local registry.")

	var create_btn: Button = Button.new()
	create_btn.text = "Create Alliance"
	create_btn.custom_minimum_size = Vector2(0, 64)
	create_btn.pressed.connect(func() -> void:
		_view = ViewMode.CREATE
		_refresh()
	)
	_content.add_child(create_btn)

	var join_btn: Button = Button.new()
	join_btn.text = "Join Alliance"
	join_btn.custom_minimum_size = Vector2(0, 64)
	join_btn.pressed.connect(func() -> void:
		_view = ViewMode.JOIN
		_refresh()
	)
	_content.add_child(join_btn)

	_add_roles_hint()


func _build_home_view() -> void:
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
	_add_panel_label(research_box, "Alliance Research", true)

	var active_id: String = AllianceState.get_active_research_id()
	var current_name: String = "None"
	var progress_text: String = "—"
	var progress_value: float = 0.0
	var progress_max: float = 1.0
	if active_id != "":
		var def: Dictionary = DataManager.get_alliance_research_def(active_id)
		var runtime: Dictionary = AllianceState.get_research_node_runtime(active_id)
		var level: int = int(runtime.get("level", 0))
		var max_level: int = int(def.get("maxLevel", 1))
		var target_level: int = mini(level + 1, max_level)
		current_name = "%s %s" % [str(def.get("name", active_id)), _to_roman(target_level)]
		if level >= max_level:
			progress_text = "Complete"
			progress_value = 1.0
			progress_max = 1.0
		else:
			var cur: int = int(runtime.get("progress", 0))
			var req: int = AllianceState.get_research_requirement(active_id, level)
			progress_text = "%s / %s" % [_format_commas(cur), _format_commas(req)]
			progress_value = float(cur)
			progress_max = max(1.0, float(req))

	_add_panel_label(research_box, "Current Research")
	_add_panel_label(research_box, current_name, true)
	_add_panel_label(research_box, "Progress")
	_add_panel_label(research_box, progress_text)

	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = progress_max
	bar.value = progress_value
	bar.custom_minimum_size = Vector2(0, 28)
	bar.show_percentage = false
	research_box.add_child(bar)

	_add_panel_label(research_box, "Personal Contribution")
	_add_panel_label(research_box, _format_commas(player_pts), true)

	var attempt_state: Dictionary = AllianceState.get_research_attempt_state()
	_add_panel_label(research_box, "Research Attempts")
	_add_panel_label(research_box, "%d / %d" % [
		int(attempt_state.get("current_attempts", 0)),
		int(attempt_state.get("max_attempts", 25)),
	])

	var open_research: Button = Button.new()
	open_research.text = "Open Research"
	open_research.custom_minimum_size = Vector2(0, 72)
	open_research.pressed.connect(_open_research_screen)
	research_box.add_child(open_research)

	_add_body_label("Embassy help capacity: %d" % AllianceState.get_embassy_help_capacity())

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
	_add_body_label("Embassy capacity: %d  |  Active: %d" % [
		AllianceState.get_embassy_help_capacity(),
		AllianceState.get_help_requests().size(),
	])

	var help_all_btn: Button = Button.new()
	help_all_btn.text = "Help All"
	help_all_btn.custom_minimum_size = Vector2(0, 56)
	help_all_btn.pressed.connect(_on_help_all_pressed)
	_content.add_child(help_all_btn)

	var request_row: HBoxContainer = HBoxContainer.new()
	request_row.add_theme_constant_override("separation", 6)
	_content.add_child(request_row)
	for help_type: String in [
		AllianceState.HELP_TYPE_CONSTRUCTION,
		AllianceState.HELP_TYPE_RESEARCH,
		AllianceState.HELP_TYPE_TRAINING,
		AllianceState.HELP_TYPE_HEALING,
	]:
		var req_btn: Button = Button.new()
		req_btn.text = "Request\n%s" % help_type.capitalize()
		req_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		req_btn.custom_minimum_size = Vector2(0, 64)
		req_btn.pressed.connect(_on_create_help_pressed.bind(help_type))
		request_row.add_child(req_btn)

	var requests: Array[Dictionary] = AllianceState.get_help_requests()
	if requests.is_empty():
		_add_body_label("No help requests in the queue.")
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


func _build_members_view() -> void:
	if not AllianceState.has_permission("view_members"):
		_add_body_label("You cannot view the roster.")
		return

	var members: Array[Dictionary] = AllianceState.get_members()
	if members.is_empty():
		_add_body_label("No members found.")
		return

	for member: Dictionary in members:
		var member_id: String = str(member.get("member_id", member.get("id", "")))
		var row: Button = Button.new()
		var online: String = str(member.get("online_status", "offline"))
		row.text = "%s\n%s · %s · %s" % [
			str(member.get("player_name", member.get("name", "?"))),
			AllianceState.get_role_display_name(str(member.get("role", "?"))),
			_format_power(int(member.get("power", 0))),
			online.capitalize(),
		]
		row.custom_minimum_size = Vector2(0, 72)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(func() -> void:
			_selected_member_id = member_id
			_view = ViewMode.MEMBER_DETAIL
			_refresh()
		)
		_content.add_child(row)


func _build_member_detail_view() -> void:
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


func _build_applications_view() -> void:
	if not AllianceState.has_permission("review_applications"):
		_add_body_label("You do not have permission to review applications.")
		return

	var apps: Array[Dictionary] = AllianceState.get_pending_applications()
	if apps.is_empty():
		_add_body_label("No pending applications.")
		return

	for app: Dictionary in apps:
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


func _build_create_view() -> void:
	_add_section_label("Raise a New Banner")

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_content.add_child(name_row)

	var name_caption: Label = Label.new()
	name_caption.text = "Name"
	name_caption.custom_minimum_size = Vector2(80, 0)
	name_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_caption)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Alliance name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = AllianceState.MAX_NAME_LENGTH
	name_row.add_child(_name_edit)

	var tag_row: HBoxContainer = HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	_content.add_child(tag_row)

	var tag_caption: Label = Label.new()
	tag_caption.text = "Tag"
	tag_caption.custom_minimum_size = Vector2(80, 0)
	tag_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(tag_caption)

	_tag_edit = LineEdit.new()
	_tag_edit.placeholder_text = "TAG"
	_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_edit.max_length = AllianceState.MAX_TAG_LENGTH
	tag_row.add_child(_tag_edit)

	var confirm: Button = Button.new()
	confirm.text = "Confirm Create"
	confirm.custom_minimum_size = Vector2(0, 56)
	confirm.pressed.connect(_on_create_pressed)
	_content.add_child(confirm)


func _build_join_view() -> void:
	_add_section_label("Join an Alliance")
	_add_body_label("Select a local Alliance to join.")

	var joinable: Array[Dictionary] = AllianceState.get_joinable_alliances()
	if joinable.is_empty():
		_add_body_label("No alliances available. Create one instead.")
	else:
		for entry: Dictionary in joinable:
			var entry_id: String = str(entry.get("id", ""))
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_content.add_child(row)

			var info: Label = Label.new()
			info.text = "[%s] %s\n%d members" % [
				str(entry.get("tag", "")),
				str(entry.get("name", "")),
				int(entry.get("member_count", 0)),
			]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(info)

			var join_btn: Button = Button.new()
			join_btn.text = "Join"
			join_btn.custom_minimum_size = Vector2(110, 56)
			join_btn.pressed.connect(_on_join_pressed.bind(entry_id))
			row.add_child(join_btn)


func _on_create_pressed() -> void:
	var name_text: String = _name_edit.text if _name_edit else ""
	var tag_text: String = _tag_edit.text if _tag_edit else ""
	var result: Dictionary = AllianceState.create_alliance(name_text, tag_text)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Create failed."))
		return
	_view = ViewMode.HOME
	_refresh()
	_status_label.text = "Alliance created."


func _on_join_pressed(target_id: String) -> void:
	var result: Dictionary = AllianceState.join_alliance(target_id)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Join failed."))
		return
	_view = ViewMode.HOME
	_refresh()
	_status_label.text = "Joined alliance."


func _on_leave_pressed() -> void:
	var result: Dictionary = AllianceState.leave_alliance()
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Leave failed."))
		return
	_selected_member_id = ""
	_coming_soon_title = ""
	_view = ViewMode.LOBBY
	_refresh()
	_status_label.text = "Left alliance."


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
