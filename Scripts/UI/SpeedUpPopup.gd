extends Control

## Shared mobile Speed Up popup. Presentation only — applies via SpeedupService.

const COL_DIM := Color(0.02, 0.04, 0.08, 0.72)
const COL_PANEL := Color(0.08, 0.11, 0.18, 0.97)
const COL_GOLD := Color(0.85, 0.72, 0.38, 1.0)
const COL_INK := Color(0.93, 0.94, 0.96, 1.0)
const COL_MUTED := Color(0.72, 0.74, 0.78, 1.0)
const ModalOutsideDismiss := preload("res://Scripts/UI/ModalOutsideDismiss.gd")

var _category: String = ""
var _target_id: String = ""
var _built: bool = false

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _remaining: Label
var _list: VBoxContainer
var _empty: Label
var _close_btn: Button
var _debug_btn: Button
var _scroll: ScrollContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 280
	visible = false
	_build_ui()
	if has_node("/root/SpeedupService"):
		if not SpeedupService.speedup_applied.is_connected(_on_speedup_applied):
			SpeedupService.speedup_applied.connect(_on_speedup_applied)


func open_for(timer_category: String, target_id: String) -> void:
	_category = timer_category.strip_edges().to_lower()
	_target_id = target_id.strip_edges()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if _debug_btn != null:
		_debug_btn.visible = OS.is_debug_build()
	_refresh()
	move_to_front()
	if has_node("/root/UiLayerStack"):
		UiLayerStack.push_layer("modal:SpeedUp", close, UiLayerStack.KIND_MODAL)


func close() -> void:
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("modal:SpeedUp")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dim != null:
		_dim.visible = false
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel != null:
		_panel.visible = false


func _on_speedup_applied(_cat: String, _tid: String, _result: Dictionary) -> void:
	if visible:
		_refresh()
		# Close when timer is gone / completed / ready for collect.
		if has_node("/root/SpeedupService"):
			var rem: float = SpeedupService.get_remaining_seconds(_category, _target_id)
			if rem <= 0.0:
				close()


func _refresh() -> void:
	if not has_node("/root/SpeedupService"):
		return
	var rem: float = SpeedupService.get_remaining_seconds(_category, _target_id)
	_remaining.text = "Remaining Time\n%s" % SpeedupService.format_remaining(rem)

	for child: Node in _list.get_children():
		child.queue_free()

	var rows: Array[Dictionary] = SpeedupService.list_owned_eligible(_category)
	_empty.visible = rows.is_empty()
	_scroll.visible = not rows.is_empty()
	for row: Dictionary in rows:
		_list.add_child(_make_item_row(row))


func _make_item_row(row: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	sb.border_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.45)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	wrap.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	wrap.add_child(h)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = str(row.get("icon", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		icon.texture = load(path) as Texture2D
	h.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)

	var name_l := Label.new()
	name_l.text = str(row.get("name", ""))
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", COL_INK)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_l)

	var meta := Label.new()
	meta.text = "Owned: %d  ·  -%s" % [
		int(row.get("owned", 0)),
		SpeedupService.format_remaining(float(row.get("seconds", 0))),
	]
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", COL_MUTED)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta)

	var use_btn := Button.new()
	use_btn.text = "USE"
	use_btn.custom_minimum_size = Vector2(88, 48)
	use_btn.add_theme_font_size_override("font_size", 16)
	use_btn.pressed.connect(func() -> void:
		_on_use_pressed(str(row.get("item_id", "")))
	)
	h.add_child(use_btn)
	return wrap


func _on_use_pressed(item_id: String) -> void:
	if not has_node("/root/SpeedupService"):
		return
	var result: Dictionary = SpeedupService.apply_speedup_item(_category, _target_id, item_id, 1)
	if not bool(result.get("ok", false)):
		print("[SPEEDUP UI] Use failed: %s" % str(result.get("reason", "")))
		return
	_refresh()


func _on_close_pressed() -> void:
	close()


func _on_debug_pressed() -> void:
	if has_node("/root/SpeedupService"):
		SpeedupService.grant_debug_test_speedups()
		_refresh()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = COL_DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.anchor_left = 0.06
	_panel.anchor_right = 0.94
	_panel.anchor_top = 0.14
	_panel.anchor_bottom = 0.78
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	var psb := StyleBoxFlat.new()
	psb.bg_color = COL_PANEL
	psb.border_color = COL_GOLD
	psb.set_border_width_all(2)
	psb.corner_radius_top_left = 16
	psb.corner_radius_top_right = 16
	psb.corner_radius_bottom_left = 16
	psb.corner_radius_bottom_right = 16
	psb.content_margin_left = 16
	psb.content_margin_right = 16
	psb.content_margin_top = 14
	psb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	ModalOutsideDismiss.bind(_dim, _panel, close)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_title = Label.new()
	_title.text = "SPEED UP"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", COL_GOLD)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(48, 48)
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)

	_remaining = Label.new()
	_remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remaining.add_theme_font_size_override("font_size", 18)
	_remaining.add_theme_color_override("font_color", COL_INK)
	_remaining.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_remaining)

	var avail := Label.new()
	avail.text = "Available Speedups"
	avail.add_theme_font_size_override("font_size", 15)
	avail.add_theme_color_override("font_color", COL_MUTED)
	avail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(avail)

	_empty = Label.new()
	_empty.text = "NO SPEEDUPS AVAILABLE\n\nEarn or obtain Speedups to reduce this timer."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_font_size_override("font_size", 15)
	_empty.add_theme_color_override("font_color", COL_MUTED)
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_empty)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)

	if OS.is_debug_build():
		_debug_btn = Button.new()
		_debug_btn.text = "DEBUG: + TEST SPEEDUPS"
		_debug_btn.custom_minimum_size = Vector2(0, 44)
		_debug_btn.pressed.connect(_on_debug_pressed)
		root.add_child(_debug_btn)
