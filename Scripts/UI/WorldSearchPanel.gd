extends Control

## Compact World Map Search / Finder.
## Finds nearest live AVAILABLE resource tile or matching Wildling.
## Does not spawn targets. Camera focus reuses MapCamera.focus_world_position.

const RESOURCE_LEVEL_MIN := 1
const RESOURCE_LEVEL_MAX := 7
## Live KingdomMap / WorldAutoSpawner range: rng.randi_range(1, 30).
const WILDLING_LEVEL_MIN := 1
const WILDLING_LEVEL_MAX := 30
## Wildling Lairs catalog: data/wildling_lairs.json Lv.1–10.
const LAIR_LEVEL_MIN := 1
const LAIR_LEVEL_MAX := 10

const FALLBACK_TOP_INSET := 180.0
const FALLBACK_BOTTOM_INSET := 190.0
const SIDE_INSET := 20.0
const CONTENT_GAP := 12.0
const PANEL_WIDTH := 640.0
const PANEL_HEIGHT := 620.0
const HIGHLIGHT_SEC := 2.0

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_GOLD_BRIGHT := Color(1.0, 0.86, 0.42, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_SAPPHIRE := Color(0.22, 0.38, 0.62, 1.0)
const COL_WARN := Color(0.95, 0.55, 0.45, 1.0)
const ModalOutsideDismiss := preload("res://Scripts/UI/ModalOutsideDismiss.gd")
const MobileSafeArea := preload("res://Scripts/UI/MobileSafeArea.gd")

enum Category { WILDLINGS, FOOD, WOOD, STONE, IRON, WILDLING_LAIRS }

## Remembered while World HUD stays alive (no permanent save).
var _category: int = Category.FOOD
var _level: int = 1

var _dim: ColorRect
var _window: PanelContainer
var _selected_label: Label
var _level_label: Label
var _status_label: Label
var _minus_btn: Button
var _plus_btn: Button
var _search_btn: Button
var _close_btn: Button
var _cat_buttons: Dictionary = {} # Category -> Button
var _found_marker: Node2D = null
var _found_timer: SceneTreeTimer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	_build_ui()
	close_panel()


func open_panel() -> void:
	_level = clampi(_level, _level_min(), _level_max())
	_apply_safe_area()
	_refresh_all()
	if _status_label != null:
		_status_label.text = ""
		_status_label.visible = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 900
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if _window != null:
		_window.mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("/root/UiLayerStack"):
		UiLayerStack.push_layer("modal:WorldSearch", close_panel, UiLayerStack.KIND_MODAL)


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _window != null:
		_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("modal:WorldSearch")


func _on_resized() -> void:
	if visible:
		_apply_safe_area()


func _build_ui() -> void:
	while get_child_count() > 0:
		var old: Node = get_child(0)
		remove_child(old)
		old.free()
	_cat_buttons.clear()

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0.04, 0.03, 0.06, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "SearchWindow"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_GOLD, 16, 2))
	add_child(_window)
	ModalOutsideDismiss.bind(_dim, _window, close_panel)

	var margin := MarginContainer.new()
	margin.name = "Margins"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_window.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Shell"
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	var title := Label.new()
	title.text = "WORLD SEARCH"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	_close_btn = _chrome_button("X", Vector2(72, 54))
	_close_btn.name = "CloseButton"
	_close_btn.pressed.connect(close_panel)
	header.add_child(_close_btn)

	var grid := GridContainer.new()
	grid.name = "CategoryGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)

	var cats := [
		[Category.WILDLINGS, "WILDLINGS"],
		[Category.WILDLING_LAIRS, "WILDLING LAIRS"],
		[Category.FOOD, "FOOD"],
		[Category.WOOD, "WOOD"],
		[Category.STONE, "STONE"],
		[Category.IRON, "IRON"],
	]
	for entry: Array in cats:
		var cat: int = int(entry[0])
		var btn := _chrome_button(str(entry[1]), Vector2(0, 52))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_category_pressed.bind(cat))
		grid.add_child(btn)
		_cat_buttons[cat] = btn

	_selected_label = Label.new()
	_selected_label.name = "SelectedLabel"
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_label.add_theme_font_size_override("font_size", 20)
	_selected_label.add_theme_color_override("font_color", COL_INK)
	_selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_selected_label)

	var level_title := Label.new()
	level_title.text = "Level"
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_title.add_theme_font_size_override("font_size", 18)
	level_title.add_theme_color_override("font_color", COL_MUTED)
	level_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(level_title)

	var level_row := HBoxContainer.new()
	level_row.name = "LevelRow"
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	level_row.add_theme_constant_override("separation", 16)
	col.add_child(level_row)

	_minus_btn = _chrome_button("−", Vector2(88, 68))
	_minus_btn.pressed.connect(_on_level_delta.bind(-1))
	level_row.add_child(_minus_btn)

	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.custom_minimum_size = Vector2(140, 68)
	_level_label.add_theme_font_size_override("font_size", 30)
	_level_label.add_theme_color_override("font_color", COL_GOLD_BRIGHT)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.add_child(_level_label)

	_plus_btn = _chrome_button("+", Vector2(88, 68))
	_plus_btn.pressed.connect(_on_level_delta.bind(1))
	level_row.add_child(_plus_btn)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.visible = false
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", COL_WARN)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_search_btn = Button.new()
	_search_btn.name = "SearchButton"
	_search_btn.text = "SEARCH"
	_search_btn.custom_minimum_size = Vector2(0, 72)
	_search_btn.focus_mode = Control.FOCUS_NONE
	_search_btn.pressed.connect(_on_search_pressed)
	_search_btn.add_theme_stylebox_override("normal", _button_style(COL_SAPPHIRE, COL_GOLD_BRIGHT))
	_search_btn.add_theme_stylebox_override("hover", _button_style(Color(0.28, 0.46, 0.72, 1.0), COL_GOLD_BRIGHT))
	_search_btn.add_theme_stylebox_override("pressed", _button_style(Color(0.18, 0.30, 0.52, 1.0), COL_GOLD))
	_search_btn.add_theme_font_size_override("font_size", 24)
	_search_btn.add_theme_color_override("font_color", COL_INK)
	col.add_child(_search_btn)

	_apply_safe_area()
	_refresh_all()


func _measure_hud_insets() -> Vector2:
	var top_inset: float = FALLBACK_TOP_INSET
	var bottom_inset: float = FALLBACK_BOTTOM_INSET
	var chrome: Control = get_parent() as Control
	if chrome == null:
		return Vector2(top_inset, bottom_inset)
	var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control
	var bottom_bar: Control = chrome.get_node_or_null("BottomBarTexture") as Control
	var local_origin: Vector2 = global_position
	var view_h: float = size.y if size.y > 1.0 else float(get_viewport_rect().size.y)
	if top_bar != null:
		var top_rect: Rect2 = top_bar.get_global_rect()
		top_inset = maxf(FALLBACK_TOP_INSET, (top_rect.position.y + top_rect.size.y) - local_origin.y + CONTENT_GAP)
	if bottom_bar != null:
		var bot_rect: Rect2 = bottom_bar.get_global_rect()
		var from_bottom: float = view_h - (bot_rect.position.y - local_origin.y)
		bottom_inset = maxf(FALLBACK_BOTTOM_INSET, from_bottom + CONTENT_GAP)
	top_inset = maxf(top_inset, MobileSafeArea.top(self) + 8.0)
	bottom_inset = maxf(bottom_inset, MobileSafeArea.bottom(self) + 8.0)
	return Vector2(top_inset, bottom_inset)


func _apply_safe_area() -> void:
	var insets: Vector2 = _measure_hud_insets()
	var view_w: float = size.x if size.x > 1.0 else float(get_viewport_rect().size.x)
	var view_h: float = size.y if size.y > 1.0 else float(get_viewport_rect().size.y)
	if _dim != null:
		_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _window == null:
		return
	var usable_top: float = insets.x
	var usable_bottom: float = view_h - insets.y
	var usable_h: float = maxf(280.0, usable_bottom - usable_top)
	var win_w: float = minf(PANEL_WIDTH, maxf(300.0, view_w - SIDE_INSET * 2.0))
	var win_h: float = PANEL_HEIGHT if usable_h >= PANEL_HEIGHT + 24.0 else maxf(280.0, usable_h - 24.0)
	var center_x: float = view_w * 0.5
	var center_y: float = usable_top + usable_h * 0.5
	_window.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_window.anchor_left = 0.0
	_window.anchor_top = 0.0
	_window.anchor_right = 0.0
	_window.anchor_bottom = 0.0
	_window.offset_left = center_x - win_w * 0.5
	_window.offset_right = center_x + win_w * 0.5
	_window.offset_top = center_y - win_h * 0.5
	_window.offset_bottom = center_y + win_h * 0.5
	_window.custom_minimum_size = Vector2(win_w, win_h)


func _on_category_pressed(cat: int) -> void:
	_category = cat
	_level = clampi(_level, _level_min(), _level_max())
	_refresh_all()
	if _status_label != null:
		_status_label.visible = false


func _on_level_delta(delta: int) -> void:
	_level = clampi(_level + delta, _level_min(), _level_max())
	_refresh_level_label()
	if _status_label != null:
		_status_label.visible = false


func _level_min() -> int:
	match _category:
		Category.WILDLINGS:
			return WILDLING_LEVEL_MIN
		Category.WILDLING_LAIRS:
			return LAIR_LEVEL_MIN
		_:
			return RESOURCE_LEVEL_MIN


func _level_max() -> int:
	match _category:
		Category.WILDLINGS:
			return WILDLING_LEVEL_MAX
		Category.WILDLING_LAIRS:
			return LAIR_LEVEL_MAX
		_:
			return RESOURCE_LEVEL_MAX


func _refresh_all() -> void:
	_refresh_level_label()
	_refresh_selected_label()
	_refresh_category_styles()


func _refresh_level_label() -> void:
	if _level_label != null:
		_level_label.text = "Lv. %d" % _level


func _refresh_selected_label() -> void:
	if _selected_label != null:
		_selected_label.text = "Selected:\n%s" % _category_display_name().to_upper()


func _refresh_category_styles() -> void:
	for cat: Variant in _cat_buttons.keys():
		var btn: Button = _cat_buttons[cat]
		var selected: bool = int(cat) == _category
		if selected:
			btn.add_theme_stylebox_override("normal", _button_style(Color(0.42, 0.32, 0.12, 1.0), COL_GOLD_BRIGHT))
			btn.add_theme_stylebox_override("hover", _button_style(Color(0.50, 0.38, 0.14, 1.0), Color(1.0, 0.92, 0.55, 1.0)))
			btn.add_theme_stylebox_override("pressed", _button_style(Color(0.34, 0.26, 0.10, 1.0), COL_GOLD))
			btn.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72, 1.0))
		else:
			btn.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.10, 0.14, 1.0), Color(0.35, 0.30, 0.24, 0.85)))
			btn.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.15, 0.20, 1.0), Color(0.55, 0.45, 0.30, 0.95)))
			btn.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.08, 0.12, 1.0), COL_GOLD))
			btn.add_theme_color_override("font_color", COL_MUTED)


func _category_display_name() -> String:
	match _category:
		Category.WILDLINGS:
			return "Wildlings"
		Category.WILDLING_LAIRS:
			return "Wildling Lairs"
		Category.FOOD:
			return "Food"
		Category.WOOD:
			return "Wood"
		Category.STONE:
			return "Stone"
		Category.IRON:
			return "Iron"
		_:
			return "Target"


func _no_result_message() -> String:
	if _category == Category.WILDLINGS:
		return "No Lv.%d Wildlings found." % _level
	if _category == Category.WILDLING_LAIRS:
		return "No Lv.%d Wildling Lairs found." % _level
	return "No Lv.%d %s tiles found." % [_level, _category_display_name()]


func _on_search_pressed() -> void:
	var result: Dictionary = {}
	if _category == Category.WILDLINGS:
		result = _find_nearest_wildling(_level)
	elif _category == Category.WILDLING_LAIRS:
		result = _find_nearest_wildling_lair(_level)
	else:
		result = _find_nearest_resource(_resource_type_for_category(_category), _level)

	if not bool(result.get("ok", false)):
		_status_label.text = _no_result_message()
		_status_label.visible = true
		return

	var target_pos: Vector2 = result.get("position", Vector2.ZERO)
	var target_node: Node2D = result.get("node", null) as Node2D
	close_panel()
	_focus_camera(target_pos)
	if target_node != null and is_instance_valid(target_node):
		_show_found_marker(target_node, target_pos)


func _resource_type_for_category(cat: int) -> String:
	match cat:
		Category.FOOD:
			return "food"
		Category.WOOD:
			return "wood"
		Category.STONE:
			return "stone"
		Category.IRON:
			return "iron"
		_:
			return ""


func _world_root() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene != null and (
		scene.get_node_or_null("ResourceSpawns") != null
		or scene.get_node_or_null("WildlingSpawns") != null
		or scene.get_node_or_null("WildlingLairSpawns") != null
	):
		return scene
	var n: Node = self
	while n != null:
		if (
			n.get_node_or_null("ResourceSpawns") != null
			or n.get_node_or_null("WildlingSpawns") != null
			or n.get_node_or_null("WildlingLairSpawns") != null
		):
			return n
		n = n.get_parent()
	return scene


func _reference_position() -> Vector2:
	var castle: Vector2 = _castle_position()
	if castle != Vector2.ZERO:
		return castle
	var cam: Camera2D = _map_camera()
	if cam != null:
		return cam.global_position
	return Vector2.ZERO


func _castle_position() -> Vector2:
	var scene: Node = _world_root()
	if scene != null:
		var castle: Node2D = scene.get_node_or_null("PlayerCastleMarker") as Node2D
		if castle != null:
			return castle.global_position
	if has_node("/root/MarchState") and MarchState.has_method("get_castle_world_position"):
		return MarchState.get_castle_world_position()
	return Vector2.ZERO


func _map_camera() -> Camera2D:
	var scene: Node = _world_root()
	if scene != null:
		var cam: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			return cam
	if get_viewport() != null:
		return get_viewport().get_camera_2d()
	return null


func _find_nearest_wildling(level: int) -> Dictionary:
	var scene: Node = _world_root()
	if scene == null:
		return {"ok": false}
	var root_spawns: Node2D = scene.get_node_or_null("WildlingSpawns") as Node2D
	if root_spawns == null:
		return {"ok": false}
	var origin: Vector2 = _reference_position()
	var best: Node2D = null
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = INF
	for child: Node in root_spawns.get_children():
		var node: Node2D = child as Node2D
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		var click: Node = node.get_node_or_null("ClickArea")
		if click == null or not ("level" in click):
			continue
		if int(click.get("level")) != level:
			continue
		var pos: Vector2 = node.global_position
		if has_node("/root/MarchState") and MarchState.has_method("get_wildling_aim_position"):
			pos = MarchState.get_wildling_aim_position(node)
		var dist: float = origin.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = node
			best_pos = pos
	if best == null:
		return {"ok": false}
	return {"ok": true, "node": best, "position": best_pos}


func _find_nearest_wildling_lair(level: int) -> Dictionary:
	var scene: Node = _world_root()
	if scene == null:
		return {"ok": false}
	var root_spawns: Node2D = scene.get_node_or_null("WildlingLairSpawns") as Node2D
	if root_spawns == null:
		return {"ok": false}
	var origin: Vector2 = _reference_position()
	var best: Node2D = null
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = INF
	for child: Node in root_spawns.get_children():
		var node: Node2D = child as Node2D
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		var lair_level: int = -1
		if "lair_level" in node:
			lair_level = int(node.get("lair_level"))
		else:
			var click: Node = node.get_node_or_null("ClickArea")
			if click != null and "lair_level" in click:
				lair_level = int(click.get("lair_level"))
		if lair_level != level:
			continue
		var pos: Vector2 = node.global_position
		if node.has_method("get_search_position"):
			pos = node.call("get_search_position")
		var dist: float = origin.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = node
			best_pos = pos
	if best == null:
		return {"ok": false}
	return {"ok": true, "node": best, "position": best_pos}


func _find_nearest_resource(resource_type: String, level: int) -> Dictionary:
	var scene: Node = _world_root()
	if scene == null:
		return {"ok": false}
	var root_spawns: Node2D = scene.get_node_or_null("ResourceSpawns") as Node2D
	if root_spawns == null:
		return {"ok": false}
	var origin: Vector2 = _reference_position()
	var best: Node2D = null
	var best_dist: float = INF
	for child: Node in root_spawns.get_children():
		var node: Node2D = child as Node2D
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		var click: Node = node.get_node_or_null("ClickArea")
		if click == null:
			continue
		var rtype: String = str(click.get("resource_type")).strip_edges().to_lower()
		var tile_level: int = int(click.get("level")) if "level" in click else 1
		var tile_id: String = str(click.get("tile_id")) if "tile_id" in click else ""

		# Beta Search: only AVAILABLE live tiles (exclude DEPLETED / RESERVED / GATHERING).
		if has_node("/root/ResourceTileState") and tile_id != "":
			if ResourceTileState.get_status(tile_id) != ResourceTileState.STATUS_AVAILABLE:
				continue
			var state: Dictionary = ResourceTileState.get_tile(tile_id)
			if not state.is_empty():
				tile_level = int(state.get("level", tile_level))
				rtype = str(state.get("resource_type", rtype)).strip_edges().to_lower()
		elif has_node("/root/ResourceTileState"):
			# Unregistered tiles are not considered usable for Search.
			continue

		if rtype != resource_type or tile_level != level:
			continue

		var dist: float = origin.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return {"ok": false}
	return {"ok": true, "node": best, "position": best.global_position}


func _focus_camera(world_pos: Vector2) -> void:
	var cam: Camera2D = _map_camera()
	if cam == null:
		return
	if cam.has_method("focus_world_position"):
		cam.call("focus_world_position", world_pos)
	else:
		cam.global_position = world_pos


func _clear_found_marker() -> void:
	if _found_marker != null and is_instance_valid(_found_marker):
		_found_marker.queue_free()
	_found_marker = null
	_found_timer = null


func _show_found_marker(_target: Node2D, world_pos: Vector2) -> void:
	_clear_found_marker()
	var scene: Node = _world_root()
	if scene == null:
		return
	var host: Node2D = scene.get_node_or_null("Marches") as Node2D
	if host == null:
		host = Node2D.new()
		host.name = "Marches"
		scene.add_child(host)
		host.z_index = 250

	var marker := Node2D.new()
	marker.name = "WorldSearchFoundMarker"
	marker.z_index = 280
	host.add_child(marker)
	marker.global_position = world_pos + Vector2(0.0, -78.0)

	var label := Label.new()
	label.text = "FOUND"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-48, -18)
	label.size = Vector2(96, 36)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COL_GOLD_BRIGHT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)

	var ring := ColorRect.new()
	ring.color = Color(0.95, 0.82, 0.35, 0.55)
	ring.size = Vector2(56, 6)
	ring.position = Vector2(-28, 16)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(ring)

	_found_marker = marker
	# Pulse without permanently changing the target node.
	var tween: Tween = create_tween()
	tween.set_loops(4)
	tween.tween_property(marker, "modulate:a", 0.35, 0.25)
	tween.tween_property(marker, "modulate:a", 1.0, 0.25)

	_found_timer = get_tree().create_timer(HIGHLIGHT_SEC)
	_found_timer.timeout.connect(_clear_found_marker)


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.14, 0.20, 1.0), COL_GOLD))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.18, 0.26, 1.0), COL_GOLD_BRIGHT))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.10, 0.16, 1.0), COL_GOLD))
	return btn


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
