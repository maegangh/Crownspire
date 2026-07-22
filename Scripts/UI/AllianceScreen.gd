extends Control

## Alliance Lobby shell (Sprint 1A).
## Create / Join / Leave membership via AllianceState; static defs via DataManager.

enum ViewMode { LOBBY, CREATE, JOIN }

var _view: ViewMode = ViewMode.LOBBY
var _status_label: Label
var _content: VBoxContainer
var _name_edit: LineEdit
var _tag_edit: LineEdit


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
	_view = ViewMode.LOBBY
	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = ViewMode.LOBBY


func _on_alliance_changed() -> void:
	if visible:
		_view = ViewMode.LOBBY
		_refresh()


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()

	var dim: ColorRect = ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_bottom = -190.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window: PanelContainer = PanelContainer.new()
	window.name = "AllianceWindow"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.custom_minimum_size = Vector2(640, 900)
	window.offset_left = -320
	window.offset_top = -450
	window.offset_right = 320
	window.offset_bottom = 450
	add_child(window)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 12)
	window.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	root.add_child(header)

	var title_label: Label = Label.new()
	title_label.name = "Title"
	title_label.text = "ALLIANCE"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(64, 48)
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)


func _refresh() -> void:
	if _content == null:
		return

	for child: Node in _content.get_children():
		child.queue_free()

	_status_label.text = ""

	if not has_node("/root/AllianceState"):
		_status_label.text = "AllianceState is not loaded."
		return

	match _view:
		ViewMode.CREATE:
			_build_create_view()
		ViewMode.JOIN:
			_build_join_view()
		_:
			if AllianceState.is_in_alliance():
				_build_member_view()
			else:
				_build_unjoined_view()


func _build_unjoined_view() -> void:
	_add_section_label("You are not in an Alliance.")
	_add_body_label("Create a new Alliance or join one from the local registry.")

	var create_btn: Button = Button.new()
	create_btn.text = "Create Alliance"
	create_btn.custom_minimum_size = Vector2(0, 56)
	create_btn.pressed.connect(func() -> void:
		_view = ViewMode.CREATE
		_refresh()
	)
	_content.add_child(create_btn)

	var join_btn: Button = Button.new()
	join_btn.text = "Join Alliance"
	join_btn.custom_minimum_size = Vector2(0, 56)
	join_btn.pressed.connect(func() -> void:
		_view = ViewMode.JOIN
		_refresh()
	)
	_content.add_child(join_btn)

	_add_roles_hint()


func _build_member_view() -> void:
	var current: Dictionary = AllianceState.get_current_alliance()
	var tag: String = str(current.get("tag", AllianceState.alliance_tag))
	var name_text: String = str(current.get("name", AllianceState.alliance_name))
	var member_count: int = int(current.get("member_count", 1))

	_add_section_label("[%s] %s" % [tag, name_text])
	_add_body_label("Your rank: %s" % AllianceState.role)
	_add_body_label("Members: %d" % member_count)

	var members: Array = current.get("members", [])
	if not members.is_empty():
		_add_section_label("Roster")
		for member: Variant in members:
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var row: Label = Label.new()
			row.text = "%s  —  %s" % [str(member.get("name", "?")), str(member.get("role", "?"))]
			_content.add_child(row)

	var leave_btn: Button = Button.new()
	leave_btn.text = "Leave Alliance"
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.pressed.connect(_on_leave_pressed)
	_content.add_child(leave_btn)

	_add_roles_hint()


func _build_create_view() -> void:
	_add_section_label("Create Alliance")

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_content.add_child(name_row)

	var name_caption: Label = Label.new()
	name_caption.text = "Name"
	name_caption.custom_minimum_size = Vector2(80, 0)
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

	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void:
		_view = ViewMode.LOBBY
		_refresh()
	)
	_content.add_child(back)


func _build_join_view() -> void:
	_add_section_label("Join Alliance")
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
			info.text = "[%s] %s  (%d members)" % [
				str(entry.get("tag", "")),
				str(entry.get("name", "")),
				int(entry.get("member_count", 0)),
			]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(info)

			var join_btn: Button = Button.new()
			join_btn.text = "Join"
			join_btn.custom_minimum_size = Vector2(100, 48)
			join_btn.pressed.connect(_on_join_pressed.bind(entry_id))
			row.add_child(join_btn)

	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void:
		_view = ViewMode.LOBBY
		_refresh()
	)
	_content.add_child(back)


func _on_create_pressed() -> void:
	var name_text: String = _name_edit.text if _name_edit else ""
	var tag_text: String = _tag_edit.text if _tag_edit else ""
	var result: Dictionary = AllianceState.create_alliance(name_text, tag_text)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Create failed."))
		return
	_view = ViewMode.LOBBY
	_refresh()
	_status_label.text = "Alliance created."


func _on_join_pressed(target_id: String) -> void:
	var result: Dictionary = AllianceState.join_alliance(target_id)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Join failed."))
		return
	_view = ViewMode.LOBBY
	_refresh()
	_status_label.text = "Joined alliance."


func _on_leave_pressed() -> void:
	var result: Dictionary = AllianceState.leave_alliance()
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Leave failed."))
		return
	_view = ViewMode.LOBBY
	_refresh()
	_status_label.text = "Left alliance."


func _add_section_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	_content.add_child(label)


func _add_body_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		role_keys.append(str(key))
	role_keys.sort()
	_add_body_label("Ranks defined: %s" % ", ".join(role_keys))


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
