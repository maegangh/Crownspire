extends Control

## Wildling march setup — production UI. March logic stays in MarchState.

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_SLOT := Color(0.08, 0.07, 0.10, 0.95)
const COL_SLOT_BORDER := Color(0.48, 0.40, 0.28, 0.85)

const UI_LAYOUT_VERSION: int = 4
## Keep chrome clear of World top resource bar + bottom nav (720×1280).
const TOP_SAFE_MARGIN: float = 188.0
const BOTTOM_SAFE_MARGIN: float = 200.0

var _target: Dictionary = {}
var _selected_heroes: Array[String] = []
var _infantry: int = 0
var _marksmen: int = 0
var _cavalry: int = 0
var _built_layout_version: int = -1

var _target_name_label: Label
var _target_meta_label: Label
var _power_value_label: Label
var _capacity_value_label: Label
var _status_label: Label
var _hero_slots: Array[Button] = []
var _hero_portraits: Array[TextureRect] = []
var _hero_captions: Array[Label] = []
var _troop_qty_labels: Dictionary = {} # kind -> Label
var _troop_avail_labels: Dictionary = {} # kind -> Label
var _march_button: Button
var _placeholder_texture: Texture2D
var _heroes_hint: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func on_open() -> void:
	_ensure_current_layout()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_for_target(target: Dictionary) -> void:
	_target = target.duplicate(true)
	_selected_heroes.clear()
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	_auto_pick_first_hero()
	_ensure_current_layout()
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.open_screen("MarchSetupScreen")
	else:
		on_open()
		_refresh()


func _ensure_current_layout() -> void:
	# Always rebuild on open — prevents stale troop rows / missing +/- after hot-reload.
	_build_ui()


func _auto_pick_first_hero() -> void:
	if not has_node("/root/HeroState"):
		return
	if HeroState.recruited_heroes.is_empty():
		return
	for hero: Dictionary in HeroState.get_available_heroes():
		_selected_heroes.append(str(hero.get("id", "")))
		break


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	_hero_slots.clear()
	_hero_portraits.clear()
	_hero_captions.clear()
	_troop_qty_labels.clear()
	_troop_avail_labels.clear()
	_march_button = null
	_built_layout_version = UI_LAYOUT_VERSION

	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.04, 0.03, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE_MARGIN
	dim.offset_bottom = -BOTTOM_SAFE_MARGIN
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "MarchWindow"
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 12.0
	window.offset_top = TOP_SAFE_MARGIN
	window.offset_right = -12.0
	window.offset_bottom = -BOTTOM_SAFE_MARGIN
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 18, 2))
	add_child(window)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 10)
	window.add_child(outer)

	var shell := VBoxContainer.new()
	shell.name = "Shell"
	shell.add_theme_constant_override("separation", 8)
	outer.add_child(shell)

	# ---- Fixed header (chrome + target) ----
	var header_block := VBoxContainer.new()
	header_block.name = "FixedHeader"
	header_block.add_theme_constant_override("separation", 6)
	shell.add_child(header_block)

	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.add_theme_constant_override("separation", 10)
	header_block.add_child(header)

	var back_btn := _make_chrome_button("BACK", Vector2(110, 52))
	back_btn.name = "BackButton"
	back_btn.pressed.connect(_on_back)
	header.add_child(back_btn)

	var title := Label.new()
	title.text = "MARCH SETUP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	var close_btn := _make_chrome_button("X", Vector2(64, 52))
	close_btn.name = "CloseButton"
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	var target_card := PanelContainer.new()
	target_card.name = "TargetSummary"
	target_card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 12, 1))
	header_block.add_child(target_card)

	var target_margin := MarginContainer.new()
	target_margin.add_theme_constant_override("margin_left", 12)
	target_margin.add_theme_constant_override("margin_right", 12)
	target_margin.add_theme_constant_override("margin_top", 8)
	target_margin.add_theme_constant_override("margin_bottom", 8)
	target_card.add_child(target_margin)

	var target_col := VBoxContainer.new()
	target_col.add_theme_constant_override("separation", 2)
	target_margin.add_child(target_col)

	_target_name_label = Label.new()
	_target_name_label.text = "Target"
	_target_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_name_label.add_theme_font_size_override("font_size", 20)
	_target_name_label.add_theme_color_override("font_color", COL_INK)
	_target_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_col.add_child(_target_name_label)

	_target_meta_label = Label.new()
	_target_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_meta_label.add_theme_font_size_override("font_size", 14)
	_target_meta_label.add_theme_color_override("font_color", COL_MUTED)
	_target_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_col.add_child(_target_meta_label)

	# ---- Scrollable middle (heroes + troops + summary) ----
	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shell.add_child(scroll)
	MobileScrollUtil.ensure(self, scroll, "MobileScrollMarchSetup")

	var root := VBoxContainer.new()
	root.name = "ContentRoot"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	root.add_child(_section_label("HEROES"))

	var heroes_hint := Label.new()
	heroes_hint.text = "Tap a slot to assign or clear a hero"
	heroes_hint.add_theme_font_size_override("font_size", 14)
	heroes_hint.add_theme_color_override("font_color", COL_MUTED)
	heroes_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heroes_hint)
	_heroes_hint = heroes_hint

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(slots_row)

	var max_heroes: int = 3
	if has_node("/root/MarchState"):
		max_heroes = MarchState.MAX_HEROES_PER_MARCH
	for i: int in range(max_heroes):
		slots_row.add_child(_make_hero_slot(i))

	var hero_actions := HBoxContainer.new()
	hero_actions.name = "HeroGlobalActions"
	hero_actions.add_theme_constant_override("separation", 10)
	hero_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(hero_actions)
	var select_all_heroes := _make_chrome_button("SELECT ALL HEROES", Vector2(240, 50))
	select_all_heroes.pressed.connect(_on_select_all_heroes)
	hero_actions.add_child(select_all_heroes)
	var clear_heroes := _make_chrome_button("CLEAR", Vector2(120, 50))
	clear_heroes.pressed.connect(_on_clear_heroes)
	hero_actions.add_child(clear_heroes)

	root.add_child(_section_label("TROOPS"))

	var troops_card := PanelContainer.new()
	troops_card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_BORDER, 14, 1))
	root.add_child(troops_card)

	var troops_margin := MarginContainer.new()
	troops_margin.add_theme_constant_override("margin_left", 10)
	troops_margin.add_theme_constant_override("margin_right", 10)
	troops_margin.add_theme_constant_override("margin_top", 10)
	troops_margin.add_theme_constant_override("margin_bottom", 10)
	troops_card.add_child(troops_margin)

	var troops_col := VBoxContainer.new()
	troops_col.name = "TroopRows"
	troops_col.add_theme_constant_override("separation", 14)
	troops_margin.add_child(troops_col)

	_add_troop_row(troops_col, "infantry", "Infantry")
	_add_troop_row(troops_col, "marksmen", "Marksmen")
	_add_troop_row(troops_col, "cavalry", "Cavalry")

	var troop_actions := HBoxContainer.new()
	troop_actions.name = "TroopGlobalActions"
	troop_actions.add_theme_constant_override("separation", 10)
	troop_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	troops_col.add_child(troop_actions)
	var select_all_troops := _make_chrome_button("SELECT ALL", Vector2(200, 52))
	select_all_troops.pressed.connect(_on_select_all_troops)
	troop_actions.add_child(select_all_troops)
	var clear_troops := _make_chrome_button("CLEAR", Vector2(140, 52))
	clear_troops.pressed.connect(_on_clear_troops)
	troop_actions.add_child(clear_troops)

	var summary_card := PanelContainer.new()
	summary_card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_GOLD, 14, 1))
	root.add_child(summary_card)

	var summary_margin := MarginContainer.new()
	summary_margin.add_theme_constant_override("margin_left", 12)
	summary_margin.add_theme_constant_override("margin_right", 12)
	summary_margin.add_theme_constant_override("margin_top", 10)
	summary_margin.add_theme_constant_override("margin_bottom", 10)
	summary_card.add_child(summary_margin)

	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 12)
	summary_margin.add_child(summary_row)

	var power_block := _make_stat_block("MARCH POWER")
	_power_value_label = power_block.get_node("Value") as Label
	summary_row.add_child(power_block)

	var cap_block := _make_stat_block("CAPACITY")
	_capacity_value_label = cap_block.get_node("Value") as Label
	summary_row.add_child(cap_block)

	# ---- Fixed footer ----
	var footer := VBoxContainer.new()
	footer.name = "FixedFooter"
	footer.add_theme_constant_override("separation", 6)
	shell.add_child(footer)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_status_label)

	_march_button = Button.new()
	_march_button.name = "MarchButton"
	_march_button.text = "MARCH"
	_march_button.custom_minimum_size = Vector2(0, 68)
	_march_button.add_theme_font_size_override("font_size", 28)
	_march_button.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0))
	_march_button.add_theme_color_override("font_disabled_color", Color(0.35, 0.32, 0.28, 1.0))
	_march_button.add_theme_stylebox_override("normal", _button_style(Color(0.78, 0.58, 0.18, 1.0), Color(0.95, 0.82, 0.42, 1.0)))
	_march_button.add_theme_stylebox_override("hover", _button_style(Color(0.88, 0.68, 0.26, 1.0), Color(1.0, 0.90, 0.55, 1.0)))
	_march_button.add_theme_stylebox_override("pressed", _button_style(Color(0.62, 0.46, 0.14, 1.0), Color(0.82, 0.68, 0.30, 1.0)))
	_march_button.add_theme_stylebox_override("disabled", _button_style(Color(0.22, 0.20, 0.18, 1.0), Color(0.35, 0.32, 0.28, 0.8)))
	_march_button.pressed.connect(_on_march_pressed)
	footer.add_child(_march_button)

	print("[MarchSetupScreen] layout v%d built from res://scripts/UI/MarchSetupScreen.gd" % UI_LAYOUT_VERSION)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", COL_GOLD)
	return label


func _make_chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.13, 0.18, 1.0), COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.18, 0.24, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.10, 0.14, 1.0), COL_BORDER))
	return btn


func _make_stat_block(title: String) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 4)

	var title_l := Label.new()
	title_l.text = title
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.add_theme_font_size_override("font_size", 13)
	title_l.add_theme_color_override("font_color", COL_MUTED)
	block.add_child(title_l)

	var value := Label.new()
	value.name = "Value"
	value.text = "—"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 28)
	value.add_theme_color_override("font_color", COL_INK)
	block.add_child(value)
	return block


func _make_hero_slot(index: int) -> Control:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(140, 168)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.clip_contents = true
	slot.add_theme_stylebox_override("normal", _panel_style(COL_SLOT, COL_SLOT_BORDER, 12, 2))
	slot.add_theme_stylebox_override("hover", _panel_style(Color(0.12, 0.10, 0.14, 0.98), COL_GOLD, 12, 2))
	slot.add_theme_stylebox_override("pressed", _panel_style(Color(0.07, 0.06, 0.09, 0.98), COL_BORDER, 12, 2))
	slot.pressed.connect(func() -> void: _on_hero_slot_pressed(index))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_top = 10
	col.offset_right = -10
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(col)

	var portrait_frame := PanelContainer.new()
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.06, 0.05, 0.08, 1.0), Color(0.40, 0.34, 0.24, 0.75), 10, 1)
	)
	col.add_child(portrait_frame)

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _get_placeholder_texture()
	portrait.custom_minimum_size = Vector2(120, 120)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)

	var caption := Label.new()
	caption.text = "Empty"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", COL_MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(caption)

	_hero_slots.append(slot)
	_hero_portraits.append(portrait)
	_hero_captions.append(caption)
	return slot


func _add_troop_row(parent: VBoxContainer, kind: String, display_name: String) -> void:
	var block := VBoxContainer.new()
	block.name = "TroopRow_%s" % kind
	block.add_theme_constant_override("separation", 6)
	parent.add_child(block)

	var name_l := Label.new()
	name_l.text = display_name.to_upper()
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.add_theme_color_override("font_color", COL_INK)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(name_l)

	var avail := Label.new()
	avail.text = "Available: 0"
	avail.add_theme_font_size_override("font_size", 14)
	avail.add_theme_color_override("font_color", COL_MUTED)
	avail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(avail)
	_troop_avail_labels[kind] = avail

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_child(controls)

	var minus_big := _make_chrome_button("−100", Vector2(88, 58))
	minus_big.pressed.connect(_on_troop_adjust.bind(kind, -100))
	controls.add_child(minus_big)

	var minus := _make_chrome_button("−", Vector2(64, 58))
	minus.pressed.connect(_on_troop_adjust.bind(kind, -1))
	controls.add_child(minus)

	var qty := Label.new()
	qty.text = "0"
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.custom_minimum_size = Vector2(120, 0)
	qty.add_theme_font_size_override("font_size", 26)
	qty.add_theme_color_override("font_color", COL_GOLD)
	qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(qty)
	_troop_qty_labels[kind] = qty

	var plus := _make_chrome_button("+", Vector2(64, 58))
	plus.pressed.connect(_on_troop_adjust.bind(kind, 1))
	controls.add_child(plus)

	var plus_big := _make_chrome_button("+100", Vector2(88, 58))
	plus_big.pressed.connect(_on_troop_adjust.bind(kind, 100))
	controls.add_child(plus_big)


func _panel_style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_w))
	style.set_corner_radius_all(int(radius))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(bg, border, 12, 2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _get_placeholder_texture() -> Texture2D:
	if _placeholder_texture == null:
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.18, 0.16, 0.22, 1.0))
		# Soft vignette frame so empty slots read as portrait frames.
		for y: int in range(128):
			for x: int in range(128):
				if x < 6 or y < 6 or x > 121 or y > 121:
					image.set_pixel(x, y, Color(0.42, 0.34, 0.22, 1.0))
		_placeholder_texture = ImageTexture.create_from_image(image)
	return _placeholder_texture


func _load_hero_portrait(hero_id: String) -> Texture2D:
	var candidates: Array[String] = [
		"res://Art/Heroes/%s/portrait.png" % hero_id,
		"res://Art/Heroes/%s/portrait1.png" % hero_id,
	]
	# Title-case folder names used by several hero assets.
	var titled: String = hero_id.capitalize()
	candidates.append("res://Art/Heroes/%s/portrait.png" % titled)
	candidates.append("res://Art/Heroes/%s/portrait1.png" % titled)
	for path: String in candidates:
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is Texture2D:
				return loaded as Texture2D
	return _get_placeholder_texture()


## Fill Infantry → Marksmen → Cavalry in order, respecting availability + capacity.
func _on_select_all_troops() -> void:
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	var capacity: int = MarchState.get_march_capacity() if has_node("/root/MarchState") else 0
	var remaining: int = capacity
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		if remaining <= 0:
			_set_troop(kind, 0)
			continue
		var available: int = _available_for_kind(kind)
		var take: int = mini(available, remaining)
		_set_troop(kind, take)
		remaining -= take
	_refresh()


func _on_clear_troops() -> void:
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	_refresh()


func _on_troop_adjust(kind: String, delta: int) -> void:
	var current: int = _get_troop(kind)
	var available: int = _available_for_kind(kind)
	var capacity: int = MarchState.get_march_capacity() if has_node("/root/MarchState") else 0
	var others: int = (_infantry + _marksmen + _cavalry) - current
	var room: int = maxi(0, capacity - others)
	var max_allowed: int = mini(available, room)
	var next: int = clampi(current + delta, 0, max_allowed)
	_set_troop(kind, next)
	_refresh_summary()


func _available_for_kind(kind: String) -> int:
	if not has_node("/root/TroopState"):
		return 0
	return maxi(0, TroopState.get_available_count(_troop_type_name(kind)))


func _on_select_all_heroes() -> void:
	_selected_heroes.clear()
	if not has_node("/root/HeroState"):
		_refresh()
		return
	var max_heroes: int = MarchState.MAX_HEROES_PER_MARCH if has_node("/root/MarchState") else 3
	for hero: Dictionary in HeroState.get_available_heroes():
		if _selected_heroes.size() >= max_heroes:
			break
		var hid: String = str(hero.get("id", ""))
		if hid.is_empty():
			continue
		if not HeroState.is_hero_owned(hid):
			continue
		if HeroState.is_hero_on_march(hid):
			continue
		_selected_heroes.append(hid)
	_refresh()


func _on_clear_heroes() -> void:
	_selected_heroes.clear()
	_refresh()


func _troop_type_name(kind: String) -> String:
	match kind:
		"infantry":
			return "Infantry"
		"marksmen":
			return "Marksmen"
		"cavalry":
			return "Cavalry"
	return kind.capitalize()


func _get_troop(kind: String) -> int:
	match kind:
		"infantry":
			return _infantry
		"marksmen":
			return _marksmen
		"cavalry":
			return _cavalry
	return 0


func _set_troop(kind: String, amount: int) -> void:
	var safe: int = max(0, amount)
	match kind:
		"infantry":
			_infantry = safe
		"marksmen":
			_marksmen = safe
		"cavalry":
			_cavalry = safe


func _on_hero_slot_pressed(index: int) -> void:
	# Occupied slot → clear. Empty slot → assign next available hero (left-packed).
	if index < _selected_heroes.size():
		_selected_heroes.remove_at(index)
		_refresh_hero_slots()
		_refresh_summary()
		return

	if not has_node("/root/MarchState"):
		return
	if _selected_heroes.size() >= MarchState.MAX_HEROES_PER_MARCH:
		_status_label.text = "All hero slots are filled."
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return

	var next_id: String = _next_available_hero_id()
	if next_id == "":
		_status_label.text = "No available heroes."
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return

	_selected_heroes.append(next_id)
	_refresh_hero_slots()
	_refresh_summary()


func _next_available_hero_id() -> String:
	if not has_node("/root/HeroState"):
		return ""
	for hero: Dictionary in HeroState.get_available_heroes():
		var hid: String = str(hero.get("id", ""))
		if hid == "" or hid in _selected_heroes:
			continue
		return hid
	return ""


func _refresh() -> void:
	var is_resource: bool = str(_target.get("target_type", "")) == "resource"
	var castle: Vector2 = MarchState.get_castle_world_position() if has_node("/root/MarchState") else Vector2.ZERO
	var pos: Dictionary = _target.get("position", {})
	if pos.is_empty() and _target.has("world_position"):
		pos = _target.get("world_position", {})
	var target_pos := Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
	var travel: int = MarchState.estimate_travel_seconds(castle, target_pos) if has_node("/root/MarchState") else 0
	var dist: int = int(castle.distance_to(target_pos))

	if is_resource:
		var display: String = str(_target.get("display_name", _target.get("resource_type", "Resource")))
		var level: int = int(_target.get("resource_level", _target.get("level", 1)))
		var rtype: String = str(_target.get("resource_type", "")).capitalize()
		var amount: int = int(_target.get("resource_amount", 0))
		_target_name_label.text = "%s  ·  Lv.%d" % [display, level]
		_target_meta_label.text = "Resource  %s\nAvailable  %s\nDistance  %d    ·    Travel  %s" % [
			rtype,
			_format_number(amount),
			dist,
			_format_travel(travel),
		]
		if _march_button:
			_march_button.text = "GATHER"
	else:
		var species: String = str(_target.get("species", "Wildling")).capitalize()
		var level_w: int = int(_target.get("level", 1))
		var power: int = int(_target.get("power", 0))
		_target_name_label.text = "%s  ·  Lv.%d" % [species, level_w]
		_target_meta_label.text = "Recommended Power  %s\nDistance  %d    ·    Travel  %s" % [
			_format_power(power),
			dist,
			_format_travel(travel),
		]
		if _march_button:
			_march_button.text = "MARCH"

	_refresh_hero_slots()
	_refresh_summary()


func _format_travel(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % seconds
	var mins: int = int(seconds / 60.0)
	var secs: int = seconds % 60
	if mins < 60:
		return "%dm %ds" % [mins, secs]
	var hours: int = int(mins / 60.0)
	mins = mins % 60
	return "%dh %dm" % [hours, mins]


func _format_power(value: int) -> String:
	var text: String = str(value)
	if text.length() <= 3:
		return text
	var parts: PackedStringArray = []
	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	if not text.is_empty():
		parts.insert(0, text)
	return ",".join(parts)


func _refresh_hero_slots() -> void:
	# Drop any stale selections that are no longer owned/available.
	var cleaned: Array[String] = []
	for hid: String in _selected_heroes:
		if has_node("/root/HeroState") and HeroState.is_hero_owned(hid) and not HeroState.is_hero_on_march(hid):
			cleaned.append(hid)
	_selected_heroes = cleaned

	var owned_count: int = 0
	if has_node("/root/HeroState"):
		owned_count = HeroState.get_owned_heroes().size()
	if _heroes_hint != null:
		if owned_count <= 0:
			_heroes_hint.text = "No recruited heroes available. Recruit at the Tavern."
		else:
			_heroes_hint.text = "Tap a slot to assign or clear a hero"

	for i: int in range(_hero_slots.size()):
		if i < _selected_heroes.size():
			var hid: String = _selected_heroes[i]
			_hero_portraits[i].texture = _load_hero_portrait(hid)
			var level: int = 1
			if has_node("/root/HeroState"):
				var idx: int = HeroState.get_hero_index(hid)
				if idx != -1:
					level = int(HeroState.recruited_heroes[idx].get("level", 1))
			_hero_captions[i].text = "%s\nLv.%d" % [hid, level]
			_hero_captions[i].add_theme_color_override("font_color", COL_INK)
		else:
			_hero_portraits[i].texture = _get_placeholder_texture()
			if owned_count <= 0:
				_hero_captions[i].text = "None"
			else:
				_hero_captions[i].text = "Empty"
			_hero_captions[i].add_theme_color_override("font_color", COL_MUTED)


func _troop_dict() -> Dictionary:
	return {
		"infantry": _infantry,
		"marksmen": _marksmen,
		"cavalry": _cavalry,
	}


func _refresh_summary() -> void:
	_set_troop_labels("infantry", _infantry, "Infantry")
	_set_troop_labels("marksmen", _marksmen, "Marksmen")
	_set_troop_labels("cavalry", _cavalry, "Cavalry")

	var total: int = _infantry + _marksmen + _cavalry
	var capacity: int = MarchState.get_march_capacity() if has_node("/root/MarchState") else 0
	var power: int = (
		MarchState.calculate_march_power(_troop_dict(), _selected_heroes)
		if has_node("/root/MarchState")
		else 0
	)

	_power_value_label.text = _format_number(power)
	_capacity_value_label.text = "%s / %s" % [_format_number(total), _format_number(capacity)]
	if total > capacity:
		_capacity_value_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_capacity_value_label.add_theme_color_override("font_color", COL_INK)

	var check: Dictionary = {"ok": false, "error": "MarchState unavailable."}
	if has_node("/root/MarchState"):
		if str(_target.get("target_type", "")) == "resource":
			check = MarchState.validate_resource_setup(_target, _troop_dict(), _selected_heroes)
		else:
			check = MarchState.validate_wildling_dispatch(_target, _troop_dict(), _selected_heroes)

	_march_button.disabled = not bool(check.get("ok", false))
	if check.get("ok", false):
		if str(_target.get("target_type", "")) == "resource":
			var composition: Dictionary = MarchState.build_troop_tier_composition(_troop_dict())
			var cargo: int = MarchState.calculate_troop_load(composition)
			var g_amt: int = mini(cargo, int(_target.get("resource_amount", 0)))
			_status_label.text = "Ready to gather · Cargo %s · Target %s" % [
				_format_number(cargo),
				_format_number(g_amt),
			]
		else:
			_status_label.text = "Ready to march."
		_status_label.add_theme_color_override("font_color", COL_OK)
	else:
		_status_label.text = str(check.get("error", "Cannot march."))
		_status_label.add_theme_color_override("font_color", COL_WARN)


func _set_troop_labels(kind: String, selected: int, troop_type: String) -> void:
	var avail: int = 0
	if has_node("/root/TroopState"):
		avail = maxi(0, TroopState.get_available_count(troop_type))
	if _troop_qty_labels.has(kind):
		(_troop_qty_labels[kind] as Label).text = _format_number(selected)
	if _troop_avail_labels.has(kind):
		(_troop_avail_labels[kind] as Label).text = "Available: %s" % _format_number(avail)


func _format_number(value: int) -> String:
	var raw: String = str(value)
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _on_march_pressed() -> void:
	if not has_node("/root/MarchState"):
		_status_label.text = "MarchState unavailable."
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return

	# Resource targets must never enter wildling combat dispatch.
	if str(_target.get("target_type", "")) == "resource":
		var gather_check: Dictionary = MarchState.validate_resource_setup(
			_target, _troop_dict(), _selected_heroes
		)
		if not bool(gather_check.get("ok", false)):
			_status_label.text = str(gather_check.get("error", "Cannot gather."))
			_status_label.add_theme_color_override("font_color", COL_WARN)
			_refresh_summary()
			return
		var gather_result: Dictionary = MarchState.dispatch_gather_march(
			_target, _troop_dict(), _selected_heroes
		)
		if not bool(gather_result.get("ok", false)):
			_status_label.text = str(gather_result.get("error", "Gather dispatch failed."))
			_status_label.add_theme_color_override("font_color", COL_WARN)
			_refresh_summary()
			return
		_close_to_map()
		return

	var result: Dictionary = MarchState.dispatch_wildling_march(_target, _troop_dict(), _selected_heroes)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Dispatch failed."))
		_status_label.add_theme_color_override("font_color", COL_WARN)
		_refresh_summary()
		return
	_close_to_map()


## BACK — close without dispatch; reopen source popup when possible.
func _on_back() -> void:
	# Closing never deploys troops / never reserves a resource tile.
	_close_screens()
	if str(_target.get("target_type", "")) == "resource":
		var rpanel: Node = _find_resource_panel()
		if rpanel != null and rpanel.has_method("reopen_last"):
			rpanel.reopen_last()
		return
	var panel: Node = _find_wildling_panel()
	if panel == null:
		return
	if panel.has_method("reopen_last"):
		panel.reopen_last()


## X — close setup and return to World Map only (no dispatch / no reservation).
func _on_close_pressed() -> void:
	_close_to_map()


func _close_to_map() -> void:
	_close_screens()


func _close_screens() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()
	# Belt-and-suspenders: never leave an invisible input trap.
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target = {}
	_infantry = 0
	_marksmen = 0
	_cavalry = 0
	_selected_heroes.clear()


func _find_wildling_panel() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var panel: Node = world.get_node_or_null("HUD/WildlingPanel")
	if panel != null:
		return panel
	return world.get_node_or_null("CanvasLayer/WildlingPanel")


func _find_resource_panel() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var panel: Node = world.get_node_or_null("HUD/ResourcePanel")
	if panel != null:
		return panel
	return get_tree().root.find_child("ResourcePanel", true, false)