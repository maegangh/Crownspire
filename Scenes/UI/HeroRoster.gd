extends Control

## Hero Roster — Recruited (owned) + Shards (progress, not owned).
## Presentation-only layout. Ownership / shard / unlock APIs unchanged.

const MobileScrollUtil = preload("res://Scripts/UI/MobileScroll.gd")

const COL_INK := Color(0.96, 0.94, 0.88, 1.0)
const COL_MUTED := Color(0.78, 0.74, 0.64, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.32, 1.0)
const COL_PANEL := Color(0.07, 0.09, 0.14, 0.82)
const COL_PANEL_LOCKED := Color(0.08, 0.08, 0.11, 0.88)
const COL_BORDER := Color(0.62, 0.52, 0.30, 0.85)
const COL_OK := Color(0.55, 0.85, 0.62, 1.0)
const COL_LOCK := Color(0.78, 0.58, 0.48, 1.0)

const RARITY_FRAMES := {
	"Mythic": "res://images/HeroCard/mythic43.png",
	"Legendary": "res://images/HeroCard/Legendary.png",
	"Epic": "res://images/HeroCard/Epic.png",
	"Rare": "res://images/HeroCard/Rare.png",
	"Common": "res://images/HeroCard/Common.png",
}

const CARD_SIZE := Vector2(318, 430)
const PORTRAIT_SIZE := Vector2(286, 300)

@onready var hero_grid: GridContainer = get_node_or_null("ScrollContainer/HeroGrid")
@onready var hero_details_panel: Control = get_node_or_null("HeroDetails")
@onready var back_button: TextureButton = get_node_or_null("BackButton")
@onready var scroll: ScrollContainer = get_node_or_null("ScrollContainer")

var _content: VBoxContainer
var _empty_label: Label
var _title_label: Label
var _mobile_scroll # MobileScroll


func _ready() -> void:
	if hero_grid == null:
		push_error("HeroRoster ERROR: Missing node ScrollContainer/HeroGrid")
		return
	if hero_details_panel == null:
		push_error("HeroRoster ERROR: Missing node HeroDetails")
		return
	if back_button == null:
		push_error("HeroRoster ERROR: Missing node BackButton")
		return

	hero_details_panel.visible = false
	_polish_shell_layout()
	_setup_content_root()
	if scroll != null:
		_mobile_scroll = MobileScrollUtil.ensure(self, scroll, "MobileScrollRoster")
	_ensure_empty_label()
	_populate_roster()

	if not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	if has_node("/root/HeroState") and not HeroState.heroes_changed.is_connected(_on_heroes_changed):
		HeroState.heroes_changed.connect(_on_heroes_changed)


func _polish_shell_layout() -> void:
	## Fill the full usable viewport (Android expand stretch can exceed 720×1280).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill: ColorRect = get_node_or_null("FillColor") as ColorRect
	if fill != null:
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: TextureRect = get_node_or_null("Background") as TextureRect
	if bg != null:
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.offset_left = 0.0
		bg.offset_top = 0.0
		bg.offset_right = 0.0
		bg.offset_bottom = 0.0
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_label = get_node_or_null("TitleLabel") as Label
	if _title_label:
		_title_label.text = "HEROES"
		_title_label.add_theme_font_size_override("font_size", 36)
		_title_label.add_theme_color_override("font_color", COL_GOLD)
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_title_label.offset_left = 24.0
		_title_label.offset_right = -24.0
		_title_label.offset_top = 24.0
		_title_label.offset_bottom = 72.0

	if scroll:
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 24.0
		scroll.offset_right = -24.0
		scroll.offset_top = 92.0
		scroll.offset_bottom = -24.0
		MobileScrollUtil.configure(scroll)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_polish_shell_layout()


func _setup_content_root() -> void:
	if scroll == null:
		return
	hero_grid.visible = false
	_content = scroll.get_node_or_null("RosterContent") as VBoxContainer
	if _content != null:
		return
	_content = VBoxContainer.new()
	_content.name = "RosterContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 22)
	scroll.add_child(_content)


func _on_heroes_changed() -> void:
	_populate_roster()


func _ensure_empty_label() -> void:
	if _empty_label != null and is_instance_valid(_empty_label):
		return
	_empty_label = Label.new()
	_empty_label.name = "EmptyRosterLabel"
	_empty_label.visible = false
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 24)
	_empty_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70, 1.0))
	_empty_label.text = "No Heroes Recruited\n\nRecruit heroes from the Tavern.\nDraws award shards — unlock at 10/10."
	_empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_label.offset_left = 48
	_empty_label.offset_right = -48
	_empty_label.offset_top = 220
	_empty_label.offset_bottom = -220
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_empty_label)


func _populate_roster() -> void:
	if _content == null:
		_setup_content_root()
	if _content == null:
		return

	for child in _content.get_children():
		child.queue_free()

	var owned: Array[Dictionary] = []
	var shard_heroes: Array[Dictionary] = []
	if has_node("/root/HeroState"):
		owned = HeroState.get_owned_heroes()
		shard_heroes = HeroState.get_shard_progress_heroes()

	var show_empty: bool = owned.is_empty() and shard_heroes.is_empty()
	if _empty_label:
		_empty_label.visible = show_empty
	if show_empty:
		return

	_content.add_child(_section_header("RECRUITED"))
	if owned.is_empty():
		_content.add_child(_muted_label("No recruited heroes yet."))
	else:
		var grid := _make_card_grid()
		_content.add_child(grid)
		for owned_hero: Dictionary in owned:
			var hero_id: String = str(owned_hero.get("id", ""))
			if hero_id.is_empty():
				continue
			grid.add_child(_make_recruited_card(hero_id, owned_hero))

	_content.add_child(_section_header("SHARDS"))
	if shard_heroes.is_empty():
		_content.add_child(_muted_label("No shard progress yet."))
	else:
		var shard_grid := _make_card_grid()
		_content.add_child(shard_grid)
		for entry: Dictionary in shard_heroes:
			shard_grid.add_child(_make_shard_card(entry))


func _make_card_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	return grid


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COL_GOLD)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_MUTED)
	return label


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _make_recruited_card(hero_id: String, owned_hero: Dictionary) -> PanelContainer:
	var template: Dictionary = _hero_template(hero_id)
	var display_name: String = str(template.get("name", owned_hero.get("name", hero_id.capitalize())))
	var rarity: String = str(template.get("rarity", ""))
	var level: int = int(owned_hero.get("level", 1))
	var on_march: bool = bool(owned_hero.get("on_march", false))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(_make_portrait(hero_id, template, rarity))

	var name_l := Label.new()
	name_l.text = display_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", COL_INK)
	col.add_child(name_l)

	var rarity_l := Label.new()
	rarity_l.text = rarity
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_font_size_override("font_size", 16)
	rarity_l.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(rarity_l)

	var meta := Label.new()
	meta.text = "Lv. %d" % level
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 17)
	meta.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(meta)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 15)
	if on_march:
		status.text = "On March"
		status.add_theme_color_override("font_color", COL_LOCK)
	else:
		status.text = "Available"
		status.add_theme_color_override("font_color", COL_OK)
	col.add_child(status)

	var open_btn := Button.new()
	open_btn.text = "VIEW"
	open_btn.custom_minimum_size = Vector2(0, 44)
	open_btn.add_theme_font_size_override("font_size", 16)
	_wire_roster_tap(open_btn, func() -> void: _on_hero_selected(hero_id))
	col.add_child(open_btn)

	# Whole card opens details on tap — not on swipe.
	_wire_roster_tap(panel, func() -> void: _on_hero_selected(hero_id))

	return panel


func _make_shard_card(entry: Dictionary) -> PanelContainer:
	var hero_id: String = str(entry.get("id", ""))
	var template: Dictionary = _hero_template(hero_id)
	var display_name: String = str(entry.get("name", template.get("name", hero_id.capitalize())))
	var rarity: String = str(entry.get("rarity", template.get("rarity", "")))
	var shards: int = int(entry.get("shards", 0))
	var need: int = int(entry.get("shards_required", 10))
	var can_unlock: bool = bool(entry.get("can_unlock", false))
	var ratio: float = clampf(float(shards) / float(maxi(1, need)), 0.0, 1.0)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg: Color = COL_PANEL if can_unlock else COL_PANEL_LOCKED
	panel.add_theme_stylebox_override("panel", _panel_style(bg, COL_BORDER))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var portrait := _make_portrait(hero_id, template, rarity)
	if not can_unlock:
		portrait.modulate = Color(0.72, 0.72, 0.78, 1.0)
	col.add_child(portrait)

	var name_l := Label.new()
	name_l.text = display_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", COL_INK)
	col.add_child(name_l)

	var rarity_l := Label.new()
	rarity_l.text = rarity
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_font_size_override("font_size", 16)
	rarity_l.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(rarity_l)

	var progress_label := Label.new()
	progress_label.text = "%d / %d shards" % [shards, need]
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 17)
	progress_label.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(progress_label)

	var bar_bg := ProgressBar.new()
	bar_bg.min_value = 0
	bar_bg.max_value = 100
	bar_bg.value = ratio * 100.0
	bar_bg.show_percentage = false
	bar_bg.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.62, 0.22, 1.0) if can_unlock else Color(0.45, 0.48, 0.58, 1.0)
	fill.set_corner_radius_all(8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	track.set_corner_radius_all(8)
	bar_bg.add_theme_stylebox_override("fill", fill)
	bar_bg.add_theme_stylebox_override("background", track)
	col.add_child(bar_bg)

	if can_unlock:
		var recruit_btn := Button.new()
		recruit_btn.text = "RECRUIT HERO"
		recruit_btn.custom_minimum_size = Vector2(0, 48)
		recruit_btn.add_theme_font_size_override("font_size", 17)
		_wire_roster_tap(recruit_btn, func() -> void: _on_unlock_from_shards(hero_id))
		col.add_child(recruit_btn)
	else:
		var locked := Label.new()
		locked.text = "LOCKED"
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked.add_theme_font_size_override("font_size", 16)
		locked.add_theme_color_override("font_color", COL_LOCK)
		col.add_child(locked)

	return panel


func _make_portrait(hero_id: String, template: Dictionary, rarity: String) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _load_hero_portrait(hero_id, template, rarity)
	return portrait


func _hero_template(hero_id: String) -> Dictionary:
	if has_node("/root/DataManager"):
		return DataManager.get_hero(hero_id)
	return {}


func _load_hero_portrait(hero_id: String, template: Dictionary, rarity: String) -> Texture2D:
	var name_value: String = str(template.get("name", hero_id.capitalize()))
	var candidates: Array[String] = []
	for key: String in ["portrait", "portraitPath", "portrait_path", "fullbodyPath", "fullbody"]:
		var path: String = str(template.get(key, ""))
		if not path.is_empty():
			candidates.append(path)
	# Canonical + common alternate filenames used by launch art folders.
	for folder_name: String in [name_value, hero_id.capitalize(), name_value.capitalize()]:
		candidates.append("res://Art/Heroes/%s/portrait.png" % folder_name)
		candidates.append("res://Art/Heroes/%s/fullbody.png" % folder_name)
		candidates.append("res://Art/Heroes/%s/%sPortrait.png" % [folder_name, folder_name])
		candidates.append("res://Art/Heroes/%s/%sFull.png" % [folder_name, folder_name])
		candidates.append("res://Art/Heroes/%s/%s Head.png" % [folder_name, folder_name])

	for path: String in candidates:
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			return loaded as Texture2D

	var frame: String = str(RARITY_FRAMES.get(rarity, RARITY_FRAMES["Rare"]))
	if ResourceLoader.exists(frame):
		var frame_tex: Resource = load(frame)
		if frame_tex is Texture2D:
			return frame_tex as Texture2D

	var image := Image.create(64, 80, false, Image.FORMAT_RGB8)
	image.fill(Color(0.18, 0.22, 0.30))
	return ImageTexture.create_from_image(image)


func _on_unlock_from_shards(hero_id: String) -> void:
	if not has_node("/root/HeroState"):
		return
	var result: Dictionary = HeroState.unlock_hero_from_shards(hero_id)
	if not result.get("ok", false):
		push_warning("HeroRoster unlock failed: %s" % str(result.get("error", "")))
		return
	_populate_roster()


func _on_hero_selected(hero_id: String) -> void:
	if hero_id.is_empty():
		return
	if has_node("/root/HeroState") and not HeroState.is_hero_owned(hero_id):
		push_warning("HeroRoster: ignoring unrecruited hero selection.")
		return
	if _mobile_scroll != null:
		_mobile_scroll.set_enabled(false)
	if hero_details_panel.has_method("show_hero_by_id"):
		hero_details_panel.show_hero_by_id(hero_id)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/City/City.tscn")


func _wire_roster_tap(control: Control, action: Callable) -> void:
	if _mobile_scroll != null:
		_mobile_scroll.wire_tap(control, action)
		return
	if control is BaseButton:
		(control as BaseButton).pressed.connect(action)
	else:
		control.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				action.call()
		)


func _process(_delta: float) -> void:
	# Re-enable roster swipe when Hero Details closes.
	if _mobile_scroll == null or hero_details_panel == null:
		return
	var details_open: bool = hero_details_panel.visible
	_mobile_scroll.set_enabled(not details_open)
