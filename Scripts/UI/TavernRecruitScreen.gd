extends CanvasLayer

## Crownspire Hero Recruitment — Royal / Mythic UI.
## Draws award shards only; pools must be configured in data/hero_recruitment_pools.json.

const MobileScrollUtil = preload("res://Scripts/UI/MobileScroll.gd")

const COL_INK := Color(0.96, 0.95, 0.92, 1.0)
const COL_MUTED := Color(0.72, 0.78, 0.88, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.32, 1.0)
const COL_SAPPHIRE := Color(0.22, 0.42, 0.78, 1.0)
const COL_SAPPHIRE_DEEP := Color(0.08, 0.14, 0.28, 0.96)
const COL_MARBLE := Color(0.88, 0.90, 0.94, 0.12)
const COL_WARN := Color(1.0, 0.58, 0.42, 1.0)
const COL_OK := Color(0.55, 0.85, 0.62, 1.0)
const MobileSafeArea := preload("res://Scripts/UI/MobileSafeArea.gd")

var _root: Control
var _royal_tickets_label: Label
var _mythic_tickets_label: Label
var _diamonds_label: Label
var _status_label: Label
var _royal_timer_label: Label
var _mythic_timer_label: Label
var _preview_layer: Control
var _result_layer: Control
var _timer: Timer


func _ready() -> void:
	layer = 120
	visible = false
	_build_ui()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_refresh_timers)
	add_child(_timer)


func open_tavern() -> void:
	if GameState.popup_open and visible:
		return
	GameState.popup_open = true
	visible = true
	if _root:
		_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()
	_timer.start()
	if has_node("/root/UiLayerStack"):
		UiLayerStack.push_layer("overlay:TavernRecruit", request_back, UiLayerStack.KIND_SCREEN)


func close_tavern() -> void:
	visible = false
	if _root:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _preview_layer:
		_preview_layer.visible = false
	if _result_layer:
		_result_layer.visible = false
	_timer.stop()
	GameState.popup_open = false
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("overlay:TavernRecruit")


func request_back() -> bool:
	if _result_layer != null and _result_layer.visible:
		_result_layer.visible = false
		return true
	if _preview_layer != null and _preview_layer.visible:
		_preview_layer.visible = false
		return true
	close_tavern()
	return false


func _build_ui() -> void:
	for child: Node in get_children():
		if child is Timer:
			continue
		child.queue_free()

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.14, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_bottom = -190.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var m: Dictionary = MobileSafeArea.margins(_root)
	var top_pad: float = maxf(18.0, float(m.get("top", 0.0)) + 8.0)
	var side_pad: float = maxf(20.0, float(m.get("left", 0.0)) + 8.0)
	var right_pad: float = maxf(20.0, float(m.get("right", 0.0)) + 8.0)

	var accent := ColorRect.new()
	accent.color = COL_MARBLE
	accent.set_anchors_preset(Control.PRESET_FULL_RECT)
	accent.offset_left = side_pad + 4.0
	accent.offset_right = -(right_pad + 4.0)
	accent.offset_top = top_pad + 6.0
	accent.offset_bottom = -210
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(accent)

	var shell := MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = side_pad
	shell.offset_right = -right_pad
	shell.offset_top = top_pad
	shell.offset_bottom = -200
	shell.add_theme_constant_override("margin_left", 8)
	shell.add_theme_constant_override("margin_right", 8)
	shell.add_theme_constant_override("margin_top", 8)
	shell.add_theme_constant_override("margin_bottom", 8)
	_root.add_child(shell)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 12)
	shell.add_child(root_col)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root_col.add_child(header)

	var title := Label.new()
	title.text = "HERO RECRUITMENT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)

	var close_btn := _chrome_button("X", Vector2(64, 52))
	close_btn.pressed.connect(close_tavern)
	header.add_child(close_btn)

	# Resource bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	root_col.add_child(bar)
	_royal_tickets_label = _resource_chip(bar, "Royal Tickets")
	_mythic_tickets_label = _resource_chip(bar, "Mythic Tickets")
	_diamonds_label = _resource_chip(bar, "Diamonds")

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	root_col.add_child(_status_label)

	var cards := VBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	root_col.add_child(cards)

	var royal_card := _make_tier_card(
		"royal",
		"ROYAL RECRUITMENT",
		Color(0.12, 0.22, 0.42, 0.96),
		COL_SAPPHIRE,
		false
	)
	cards.add_child(royal_card)

	var mythic_card := _make_tier_card(
		"mythic",
		"MYTHIC RECRUITMENT",
		Color(0.18, 0.12, 0.28, 0.97),
		COL_GOLD,
		true
	)
	cards.add_child(mythic_card)

	var chest := PanelContainer.new()
	chest.add_theme_stylebox_override("panel", _style(Color(0.10, 0.12, 0.18, 0.9), Color(0.55, 0.60, 0.70, 0.6)))
	root_col.add_child(chest)
	var chest_btn := Button.new()
	chest_btn.text = "Recruitment Chest  —  Coming Soon"
	chest_btn.custom_minimum_size = Vector2(0, 56)
	chest_btn.disabled = true
	chest_btn.add_theme_font_size_override("font_size", 18)
	chest.add_child(chest_btn)

	if OS.is_debug_build():
		var debug_row := HBoxContainer.new()
		debug_row.add_theme_constant_override("separation", 8)
		root_col.add_child(debug_row)
		var debug_tag := Label.new()
		debug_tag.text = "DEBUG"
		debug_tag.add_theme_font_size_override("font_size", 14)
		debug_tag.add_theme_color_override("font_color", COL_WARN)
		debug_row.add_child(debug_tag)
		var debug_btn := Button.new()
		debug_btn.text = "+10 TEST TICKETS"
		debug_btn.tooltip_text = "DEBUG ONLY — grants +10 Royal and +10 Mythic tickets for recruitment testing."
		debug_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		debug_btn.custom_minimum_size = Vector2(0, 48)
		debug_btn.add_theme_font_size_override("font_size", 16)
		debug_btn.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0))
		debug_btn.add_theme_stylebox_override("normal", _style(Color(0.72, 0.42, 0.18, 1.0), COL_WARN))
		debug_btn.add_theme_stylebox_override("hover", _style(Color(0.82, 0.50, 0.22, 1.0), COL_GOLD))
		debug_btn.pressed.connect(_on_debug_grant_test_tickets)
		debug_row.add_child(debug_btn)

	_preview_layer = Control.new()
	_preview_layer.visible = false
	_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_preview_layer)

	_result_layer = Control.new()
	_result_layer.visible = false
	_result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_result_layer)


func _resource_chip(parent: HBoxContainer, title: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(COL_SAPPHIRE_DEEP, COL_GOLD))
	parent.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(t)
	var v := Label.new()
	v.text = "0"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", COL_INK)
	col.add_child(v)
	return v


func _make_tier_card(
	tier_id: String,
	title_text: String,
	bg: Color,
	border: Color,
	prestige: bool
) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(bg, border))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24 if prestige else 22)
	title.add_theme_color_override("font_color", COL_GOLD if prestige else COL_INK)
	col.add_child(title)

	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 110 if prestige else 90)
	art.add_theme_stylebox_override(
		"panel",
		_style(Color(0.16, 0.20, 0.32, 0.85), Color(0.75, 0.80, 0.90, 0.35))
	)
	col.add_child(art)
	var art_label := Label.new()
	art_label.text = "Featured Hero Artwork"
	art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_label.add_theme_color_override("font_color", COL_MUTED)
	art.add_child(art_label)

	var timer := Label.new()
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.add_theme_font_size_override("font_size", 16)
	timer.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(timer)
	if tier_id == "royal":
		_royal_timer_label = timer
	else:
		_mythic_timer_label = timer

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var once := _action_button("RECRUIT ONCE\n1 Ticket", prestige)
	once.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	once.pressed.connect(func() -> void: _on_recruit(tier_id, 1, false))
	row.add_child(once)

	var ten := _action_button("RECRUIT 10x\n10 Tickets", prestige)
	ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ten.pressed.connect(func() -> void: _on_recruit(tier_id, 10, false))
	row.add_child(ten)

	var free_btn := _chrome_button("Free Recruit", Vector2(0, 48))
	free_btn.pressed.connect(func() -> void: _on_recruit(tier_id, 1, true))
	col.add_child(free_btn)

	var preview := _chrome_button("Recruitment Preview", Vector2(0, 48))
	preview.pressed.connect(func() -> void: _open_preview(tier_id))
	col.add_child(preview)

	return card


func _action_button(text: String, prestige: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 72)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0) if prestige else COL_INK)
	var fill := Color(0.86, 0.68, 0.24, 1.0) if prestige else Color(0.28, 0.48, 0.86, 1.0)
	btn.add_theme_stylebox_override("normal", _style(fill, COL_GOLD))
	btn.add_theme_stylebox_override("hover", _style(fill.lightened(0.08), COL_GOLD))
	btn.add_theme_stylebox_override("disabled", _style(Color(0.2, 0.2, 0.24, 1.0), Color(0.35, 0.35, 0.4)))
	return btn


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _style(Color(0.14, 0.18, 0.28, 1.0), COL_SAPPHIRE))
	btn.add_theme_stylebox_override("hover", _style(Color(0.18, 0.24, 0.36, 1.0), COL_GOLD))
	return btn


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _on_debug_grant_test_tickets() -> void:
	if not OS.is_debug_build():
		return
	if not has_node("/root/HeroState"):
		return
	var before_r: int = HeroState.royal_tickets
	var before_m: int = HeroState.mythic_tickets
	var result: Dictionary = HeroState.debug_grant_test_tickets(10, 10)
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", "Debug grant failed."))
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	_status_label.text = "DEBUG: +10 Royal / +10 Mythic tickets (%d → %d Royal, %d → %d Mythic)." % [
		before_r,
		HeroState.royal_tickets,
		before_m,
		HeroState.mythic_tickets,
	]
	_status_label.add_theme_color_override("font_color", COL_OK)
	_refresh()


func _refresh() -> void:
	if not has_node("/root/HeroState"):
		_status_label.text = "HeroState unavailable."
		return
	_royal_tickets_label.text = str(HeroState.royal_tickets)
	_mythic_tickets_label.text = str(HeroState.mythic_tickets)
	_diamonds_label.text = str(GameState.diamonds if has_node("/root/GameState") else 0)
	_refresh_timers()

	var pools: Dictionary = HeroState.get_recruitment_pools()
	if str(pools.get("status", "")) == "awaiting_launch_pool":
		_status_label.text = "Recruitment pools await launch hero list. Preview shows empty active pools."
		_status_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_status_label.text = "First drop active. Draws award shards. Unlock at 10/10 with Recruit Hero."
		_status_label.add_theme_color_override("font_color", COL_MUTED)


func _refresh_timers() -> void:
	if not has_node("/root/HeroState"):
		return
	if _royal_timer_label:
		_royal_timer_label.text = "Next Free: %s" % _format_eta(HeroState.get_free_seconds_remaining("royal"))
	if _mythic_timer_label:
		_mythic_timer_label.text = "Next Free: %s" % _format_eta(HeroState.get_free_seconds_remaining("mythic"))
	if _royal_tickets_label:
		_royal_tickets_label.text = str(HeroState.royal_tickets)
	if _mythic_tickets_label:
		_mythic_tickets_label.text = str(HeroState.mythic_tickets)


func _format_eta(seconds: int) -> String:
	if seconds <= 0:
		return "Ready"
	var h: int = int(seconds / 3600.0)
	var m: int = int((seconds % 3600) / 60.0)
	var s: int = seconds % 60
	return "%02d:%02d:%02d" % [h, m, s]


func _on_recruit(tier_id: String, count: int, use_free: bool) -> void:
	if not has_node("/root/HeroState"):
		return
	var payload: Dictionary
	if use_free:
		payload = HeroState.draw_recruitment(tier_id, true)
		if payload.get("ok", false):
			_show_results([payload])
		else:
			_status_label.text = str(payload.get("error", "Recruit failed."))
			_status_label.add_theme_color_override("font_color", COL_WARN)
	elif count <= 1:
		payload = HeroState.draw_recruitment(tier_id, false)
		if payload.get("ok", false):
			_show_results([payload])
		else:
			_status_label.text = str(payload.get("error", "Recruit failed."))
			_status_label.add_theme_color_override("font_color", COL_WARN)
	else:
		payload = HeroState.draw_recruitment_multi(tier_id, count)
		if payload.get("ok", false):
			_show_results(payload.get("results", []))
		else:
			_status_label.text = str(payload.get("error", "Recruit failed."))
			_status_label.add_theme_color_override("font_color", COL_WARN)
	_refresh()


func _open_preview(tier_id: String) -> void:
	for child: Node in _preview_layer.get_children():
		child.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 900)
	panel.offset_left = -320
	panel.offset_top = -450
	panel.offset_right = 320
	panel.offset_bottom = 450
	panel.add_theme_stylebox_override("panel", _style(COL_SAPPHIRE_DEEP, COL_GOLD))
	_preview_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "%s Preview" % tier_id.capitalize()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COL_GOLD)
	head.add_child(title)
	var close_btn := _chrome_button("Close", Vector2(90, 44))
	close_btn.pressed.connect(func() -> void: _preview_layer.visible = false)
	head.add_child(close_btn)

	# Shared shard odds (independent of hero selection).
	var shard_box := PanelContainer.new()
	shard_box.add_theme_stylebox_override("panel", _style(Color(0.10, 0.14, 0.22, 0.95), COL_SAPPHIRE))
	col.add_child(shard_box)
	var shard_col := VBoxContainer.new()
	shard_col.add_theme_constant_override("separation", 4)
	shard_box.add_child(shard_col)
	var shard_title := Label.new()
	shard_title.text = "Possible Shard Rewards"
	shard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shard_title.add_theme_font_size_override("font_size", 18)
	shard_title.add_theme_color_override("font_color", COL_GOLD)
	shard_col.add_child(shard_title)
	if has_node("/root/HeroState"):
		for chance: Dictionary in HeroState.get_shard_reward_chances():
			var line := Label.new()
			line.text = "×%d  —  %s" % [
				int(chance.get("amount", 0)),
				_format_percent(float(chance.get("percent", 0.0))),
			]
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.add_theme_font_size_override("font_size", 16)
			line.add_theme_color_override("font_color", COL_INK)
			shard_col.add_child(line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	MobileScrollUtil.configure(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var rows: Array[Dictionary] = []
	if has_node("/root/HeroState"):
		rows = HeroState.get_pool_hero_chances(tier_id)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No heroes in this active pool yet."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", COL_WARN)
		list.add_child(empty)
	else:
		for row: Dictionary in rows:
			list.add_child(_make_preview_hero_card(row))

	_preview_layer.visible = true
	_preview_layer.move_to_front()


func _make_preview_hero_card(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color(0.12, 0.16, 0.26, 0.95), COL_SAPPHIRE))
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 12)
	card.add_child(row_box)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 120)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _load_hero_portrait(str(row.get("id", "")), row.get("template", {}))
	row_box.add_child(portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row_box.add_child(info)

	var name_l := Label.new()
	name_l.text = str(row.get("name", row.get("id", "Hero")))
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", COL_INK)
	info.add_child(name_l)

	var rarity := Label.new()
	rarity.text = str(row.get("rarity", ""))
	rarity.add_theme_color_override("font_color", COL_GOLD)
	info.add_child(rarity)

	var chance := Label.new()
	chance.text = "Hero Chance: %s" % _format_percent(float(row.get("percent", 0.0)))
	chance.add_theme_font_size_override("font_size", 16)
	chance.add_theme_color_override("font_color", COL_MUTED)
	info.add_child(chance)

	var shard_note := Label.new()
	shard_note.text = "Shard rewards roll separately (×1 / ×5 / ×10)."
	shard_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shard_note.add_theme_font_size_override("font_size", 13)
	shard_note.add_theme_color_override("font_color", COL_MUTED)
	info.add_child(shard_note)

	return card


func _show_results(results: Array) -> void:
	for child: Node in _result_layer.get_children():
		child.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var tall: bool = results.size() <= 1
	panel.custom_minimum_size = Vector2(620, 860 if tall else 920)
	panel.offset_left = -310
	panel.offset_top = -430 if tall else -460
	panel.offset_right = 310
	panel.offset_bottom = 430 if tall else 460
	panel.add_theme_stylebox_override("panel", _style(COL_SAPPHIRE_DEEP, COL_GOLD))
	_result_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Recruitment Results"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	MobileScrollUtil.configure(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for item_v: Variant in results:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		list.add_child(_make_result_card(item_v, tall))

	var close_btn := _action_button("CONTINUE", true)
	close_btn.pressed.connect(func() -> void: _result_layer.visible = false)
	col.add_child(close_btn)

	_result_layer.visible = true
	_result_layer.move_to_front()


func _make_result_card(result: Dictionary, large: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color(0.12, 0.16, 0.26, 0.95), COL_SAPPHIRE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var hero_id: String = str(result.get("hero_id", ""))
	var template: Dictionary = {}
	if has_node("/root/DataManager"):
		template = DataManager.get_hero(hero_id)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(220 if large else 120, 280 if large else 150)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _load_hero_portrait(hero_id, template)
	col.add_child(portrait)

	var name_l := Label.new()
	name_l.text = str(result.get("name", hero_id)).to_upper()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 28 if large else 20)
	name_l.add_theme_color_override("font_color", COL_INK)
	col.add_child(name_l)

	var rarity := Label.new()
	rarity.text = str(result.get("rarity", ""))
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity.add_theme_font_size_override("font_size", 18)
	rarity.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(rarity)

	var shards := Label.new()
	shards.text = "HERO SHARDS ×%d" % int(result.get("shard_amount", 0))
	shards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shards.add_theme_font_size_override("font_size", 20 if large else 16)
	shards.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(shards)

	var progress := Label.new()
	progress.text = "%d / %d" % [
		int(result.get("shards_total", 0)),
		int(result.get("shards_required", 10)),
	]
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_theme_font_size_override("font_size", 22 if large else 18)
	progress.add_theme_color_override("font_color", COL_OK if bool(result.get("was_unlock_ready", false)) else COL_INK)
	col.add_child(progress)

	if bool(result.get("already_owned", false)):
		var owned := Label.new()
		owned.text = "Already Owned — shards banked"
		owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned.add_theme_color_override("font_color", COL_MUTED)
		col.add_child(owned)

	if bool(result.get("was_unlock_ready", false)) and not bool(result.get("already_owned", false)):
		var unlock := _action_button("RECRUIT HERO", true)
		unlock.pressed.connect(func() -> void: _on_unlock_pressed(hero_id))
		col.add_child(unlock)

	return card


func _load_hero_portrait(hero_id: String, template: Dictionary = {}) -> Texture2D:
	var candidates: Array[String] = []
	var name_value: String = str(template.get("name", hero_id.capitalize()))
	for key: String in ["portrait", "portraitPath", "portrait_path", "fullbodyPath", "fullbody"]:
		var path: String = str(template.get(key, ""))
		if not path.is_empty():
			candidates.append(path)
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

	# Existing project fallback: rarity card frame / muted placeholder.
	var rarity: String = str(template.get("rarity", "Rare"))
	var frame_paths := {
		"Mythic": "res://images/HeroCard/mythic43.png",
		"Legendary": "res://images/HeroCard/Legendary.png",
		"Epic": "res://images/HeroCard/Epic.png",
		"Rare": "res://images/HeroCard/Rare.png",
		"Common": "res://images/HeroCard/Common.png",
	}
	var frame: String = str(frame_paths.get(rarity, "res://images/HeroCard/Rare.png"))
	if ResourceLoader.exists(frame):
		var frame_tex: Resource = load(frame)
		if frame_tex is Texture2D:
			return frame_tex as Texture2D

	var image := Image.create(64, 80, false, Image.FORMAT_RGB8)
	image.fill(Color(0.18, 0.22, 0.30))
	return ImageTexture.create_from_image(image)


func _format_percent(value: float) -> String:
	var rounded: float = snapped(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d%%" % int(roundf(rounded))
	return "%.2f%%" % rounded


func _on_unlock_pressed(hero_id: String) -> void:
	if not has_node("/root/HeroState"):
		return
	var result: Dictionary = HeroState.unlock_hero_from_shards(hero_id)
	if result.get("ok", false):
		_status_label.text = "Recruited %s!" % hero_id
		_status_label.add_theme_color_override("font_color", COL_OK)
		_result_layer.visible = false
	else:
		_status_label.text = str(result.get("error", "Unlock failed."))
		_status_label.add_theme_color_override("font_color", COL_WARN)
	_refresh()
