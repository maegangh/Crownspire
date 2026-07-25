extends Control

## Compact World Map search — find nearest live Wildling / resource tile.

const RESOURCE_LEVEL_MIN := 1
const RESOURCE_LEVEL_MAX := 7
const WILDLING_LEVEL_MIN := 1
const WILDLING_LEVEL_MAX := 30

enum Category { WILDLINGS, FOOD, WOOD, STONE, IRON }

var _category: int = Category.WILDLINGS
var _level: int = 1

var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _level_label: Label
var _status_label: Label
var _minus_btn: Button
var _plus_btn: Button
var _search_btn: Button
var _close_btn: Button
var _cat_buttons: Dictionary = {} # Category -> Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	_build_ui()
	close_panel()


func open_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 900
	_status_label.text = ""
	_status_label.visible = false
	_refresh_level_label()
	_refresh_category_styles()


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dim:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_card = PanelContainer.new()
	_card.name = "CardRoot"
	_card.position = Vector2(70, 220)
	_card.size = Vector2(580, 720)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.72, 0.62, 0.34, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.text = "WORLD SEARCH"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(56, 48)
	_close_btn.pressed.connect(close_panel)
	header.add_child(_close_btn)

	var hint := Label.new()
	hint.text = "Choose a target, set level, then Search."
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66, 1.0))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)

	var cats := [
		[Category.WILDLINGS, "Wildlings"],
		[Category.FOOD, "Food"],
		[Category.WOOD, "Wood"],
		[Category.STONE, "Stone"],
		[Category.IRON, "Iron"],
	]
	for entry: Array in cats:
		var cat: int = int(entry[0])
		var label: String = str(entry[1])
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_category_pressed.bind(cat))
		col.add_child(btn)
		_cat_buttons[cat] = btn

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 12)
	col.add_child(level_row)

	var level_title := Label.new()
	level_title.text = "Level"
	level_title.custom_minimum_size = Vector2(90, 0)
	level_title.add_theme_font_size_override("font_size", 22)
	level_title.add_theme_color_override("font_color", Color(0.90, 0.86, 0.74, 1.0))
	level_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.add_child(level_title)

	_minus_btn = Button.new()
	_minus_btn.text = "−"
	_minus_btn.custom_minimum_size = Vector2(72, 64)
	_minus_btn.pressed.connect(_on_level_delta.bind(-1))
	level_row.add_child(_minus_btn)

	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.custom_minimum_size = Vector2(80, 0)
	_level_label.add_theme_font_size_override("font_size", 28)
	_level_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82, 1.0))
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.add_child(_level_label)

	_plus_btn = Button.new()
	_plus_btn.text = "+"
	_plus_btn.custom_minimum_size = Vector2(72, 64)
	_plus_btn.pressed.connect(_on_level_delta.bind(1))
	level_row.add_child(_plus_btn)

	_status_label = Label.new()
	_status_label.visible = false
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45, 1.0))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status_label)

	_search_btn = Button.new()
	_search_btn.text = "SEARCH"
	_search_btn.custom_minimum_size = Vector2(0, 72)
	_search_btn.pressed.connect(_on_search_pressed)
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color(0.28, 0.45, 0.30, 1.0)
	search_style.border_color = Color(0.72, 0.88, 0.42, 1.0)
	search_style.set_border_width_all(2)
	search_style.set_corner_radius_all(12)
	_search_btn.add_theme_stylebox_override("normal", search_style)
	col.add_child(_search_btn)

	_refresh_level_label()
	_refresh_category_styles()


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
	elif event is InputEventScreenTouch and event.pressed:
		close_panel()


func _on_category_pressed(cat: int) -> void:
	_category = cat
	_level = clampi(_level, _level_min(), _level_max())
	_refresh_level_label()
	_refresh_category_styles()
	_status_label.visible = false


func _on_level_delta(delta: int) -> void:
	_level = clampi(_level + delta, _level_min(), _level_max())
	_refresh_level_label()
	_status_label.visible = false


func _level_min() -> int:
	return WILDLING_LEVEL_MIN if _category == Category.WILDLINGS else RESOURCE_LEVEL_MIN


func _level_max() -> int:
	return WILDLING_LEVEL_MAX if _category == Category.WILDLINGS else RESOURCE_LEVEL_MAX


func _refresh_level_label() -> void:
	if _level_label:
		_level_label.text = str(_level)


func _refresh_category_styles() -> void:
	for cat: Variant in _cat_buttons.keys():
		var btn: Button = _cat_buttons[cat]
		var selected: bool = int(cat) == _category
		btn.disabled = false
		btn.modulate = Color(1.15, 1.1, 0.85, 1.0) if selected else Color(1, 1, 1, 1)


func _category_label() -> String:
	match _category:
		Category.WILDLINGS:
			return "Wildling"
		Category.FOOD:
			return "Food"
		Category.WOOD:
			return "Wood"
		Category.STONE:
			return "Stone"
		Category.IRON:
			return "Iron"
		_:
			return "target"


func _on_search_pressed() -> void:
	var result: Dictionary = {}
	if _category == Category.WILDLINGS:
		result = _find_nearest_wildling(_level)
	else:
		var rtype: String = _resource_type_for_category(_category)
		result = _find_nearest_resource(rtype, _level)

	if not bool(result.get("ok", false)):
		_status_label.text = "No Level %d %s found nearby." % [_level, _category_label()]
		_status_label.visible = true
		return

	var target_pos: Vector2 = result.get("position", Vector2.ZERO)
	var target_node: Node2D = result.get("node", null) as Node2D
	close_panel()
	_focus_camera(target_pos)
	if target_node != null and is_instance_valid(target_node):
		_pulse_target(target_node)


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
	if scene != null and scene.get_node_or_null("ResourceSpawns") != null:
		return scene
	var n: Node = self
	while n != null:
		if n.get_node_or_null("ResourceSpawns") != null:
			return n
		n = n.get_parent()
	return scene


func _castle_position() -> Vector2:
	var scene: Node = _world_root()
	if scene != null:
		var castle: Node2D = scene.get_node_or_null("PlayerCastleMarker") as Node2D
		if castle != null:
			return castle.global_position
	if get_tree() != null and get_tree().root.get_node_or_null("MarchState") != null:
		if MarchState.has_method("get_castle_world_position"):
			return MarchState.get_castle_world_position()
	return Vector2.ZERO


func _find_nearest_wildling(level: int) -> Dictionary:
	var scene: Node = _world_root()
	if scene == null:
		return {"ok": false}
	var root_spawns: Node2D = scene.get_node_or_null("WildlingSpawns") as Node2D
	if root_spawns == null:
		return {"ok": false}
	var origin: Vector2 = _castle_position()
	var best: Node2D = null
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
		var dist: float = origin.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return {"ok": false}
	return {"ok": true, "node": best, "position": best.global_position}


func _find_nearest_resource(resource_type: String, level: int) -> Dictionary:
	var scene: Node = _world_root()
	if scene == null:
		return {"ok": false}
	var root_spawns: Node2D = scene.get_node_or_null("ResourceSpawns") as Node2D
	if root_spawns == null:
		return {"ok": false}
	var origin: Vector2 = _castle_position()
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
		if rtype != resource_type:
			continue
		var tile_level: int = int(click.get("level"))
		var tile_id: String = str(click.get("tile_id")) if "tile_id" in click else ""
		if has_node("/root/ResourceTileState") and tile_id != "":
			var state: Dictionary = ResourceTileState.get_tile(tile_id)
			if state.is_empty():
				continue
			if str(state.get("status", "")) == ResourceTileState.STATUS_DEPLETED:
				continue
			tile_level = int(state.get("level", tile_level))
			rtype = str(state.get("resource_type", rtype))
			if rtype != resource_type:
				continue
		if tile_level != level:
			continue
		var dist: float = origin.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return {"ok": false}
	return {"ok": true, "node": best, "position": best.global_position}


func _focus_camera(world_pos: Vector2) -> void:
	var scene: Node = _world_root()
	if scene == null:
		return
	var cam: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if cam.has_method("focus_world_position"):
		cam.call("focus_world_position", world_pos)
	else:
		cam.global_position = world_pos


func _pulse_target(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var sprite: CanvasItem = node.get_node_or_null("Sprite2D") as CanvasItem
	if sprite == null:
		sprite = node
	var original: Color = sprite.modulate
	var tween: Tween = create_tween()
	tween.set_loops(2)
	tween.tween_property(sprite, "modulate", Color(1.35, 1.25, 0.75, 1.0), 0.18)
	tween.tween_property(sprite, "modulate", original, 0.18)
