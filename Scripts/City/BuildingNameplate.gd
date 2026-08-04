extends Control

## Visual-only City building nameplate. Never owns input / gameplay.
## Attach once via BuildingNameplate.attach_to(host).

const NODE_NAME := "BuildingNameplate"
const BUILDINGS_JSON := "res://data/buildings.json"

@export var zoom_visible_min: float = 1.2
@export var reference_zoom: float = 1.6
@export var min_scale_factor: float = 0.70
@export var max_scale_factor: float = 1.30
@export var vertical_gap_px: float = 8.0
## Extra local offset applied after automatic placement (orphan buildings, etc.).
@export var anchor_offset: Vector2 = Vector2.ZERO

var _label: Label
var _host: Node2D
var _camera: Camera2D
var _base_font_size: int = 14

static var _name_by_id: Dictionary = {}
static var _names_loaded: bool = false


static func attach_to(host: Node, local_offset: Vector2 = Vector2.ZERO) -> void:
	if host == null or not is_instance_valid(host):
		return
	if host.has_node(NODE_NAME):
		return
	if not (host is Node2D):
		return
	var packed: PackedScene = load("res://Scenes/City/BuildingNameplate.tscn") as PackedScene
	if packed == null:
		push_error("BuildingNameplate: missing Scenes/City/BuildingNameplate.tscn")
		return
	var plate: Control = packed.instantiate() as Control
	plate.name = NODE_NAME
	if "anchor_offset" in plate:
		plate.set("anchor_offset", local_offset)
	host.add_child(plate)
	if plate.has_method("configure"):
		plate.call("configure", host)


## Attach display-only plates to intentional City buildings that lack ResourceManager/Castle.
## Skips nodes that already have a plate. Requires a Sprite2D (building art present).
static func attach_missing_under_buildings_root(buildings_root: Node) -> void:
	if buildings_root == null:
		return
	for child: Node in buildings_root.get_children():
		if not (child is Node2D):
			continue
		if child.has_node(NODE_NAME):
			continue
		if child.get_node_or_null("Sprite2D") == null:
			continue
		# Sprite-only hosts use lower-sprite anchoring; no special offset required
		# after the shared sprite placement fix.
		attach_to(child)


static func resolve_display_name(building_id: String, building_name: String, node_name: String) -> String:
	_ensure_name_cache()
	var id_key: String = building_id.strip_edges().to_lower()
	if id_key != "" and _name_by_id.has(id_key):
		return str(_name_by_id[id_key])
	var named: String = building_name.strip_edges()
	if named != "":
		return _humanize_spaces(named)
	return _humanize_node_name(node_name)


static func _ensure_name_cache() -> void:
	if _names_loaded:
		return
	_names_loaded = true
	_name_by_id.clear()
	if not FileAccess.file_exists(BUILDINGS_JSON):
		return
	var file := FileAccess.open(BUILDINGS_JSON, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key: Variant in (parsed as Dictionary).keys():
		var entry: Variant = (parsed as Dictionary)[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var display: String = str((entry as Dictionary).get("name", "")).strip_edges()
		if display != "":
			_name_by_id[str(key).to_lower()] = display


static func _humanize_spaces(raw: String) -> String:
	if " " in raw:
		return raw
	var out := ""
	for i: int in range(raw.length()):
		var ch: String = raw[i]
		if i > 0 and ch >= "A" and ch <= "Z":
			out += " "
		out += ch
	return out


static func _humanize_node_name(node_name: String) -> String:
	var cleaned: String = node_name.strip_edges()
	if cleaned.is_empty():
		return "Building"
	var spaced: String = _humanize_spaces(cleaned.replace("_", " "))
	# Prefer natural title casing for common small words.
	var parts: PackedStringArray = spaced.split(" ")
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(parts.size()):
		var w: String = parts[i]
		if i > 0 and w.to_lower() in ["of", "the", "and", "a", "an"]:
			out.append(w.to_lower())
		else:
			out.append(w)
	return " ".join(out)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_ui()
	_apply_ignore_filters(self)
	set_process(true)


func configure(host: Node) -> void:
	_host = host as Node2D
	_ensure_ui()
	_apply_ignore_filters(self)
	var bid: String = ""
	var bname: String = ""
	if host.get("building_id") != null:
		bid = str(host.get("building_id"))
	if host.get("building_name") != null:
		bname = str(host.get("building_name"))
	_label.text = resolve_display_name(bid, bname, host.name)
	call_deferred("_place_above_badge")
	_refresh_camera_ref()
	_update_zoom_visuals()


func _ensure_ui() -> void:
	if _label != null and is_instance_valid(_label):
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20

	var panel := PanelContainer.new()
	panel.name = "Backdrop"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _backdrop_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	panel.add_child(margin)

	_label = Label.new()
	_label.name = "NameLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", _base_font_size)
	_label.add_theme_color_override("font_color", Color(0.94, 0.90, 0.78, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.04, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	margin.add_child(_label)


func _backdrop_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.72)
	style.border_color = Color(0.55, 0.44, 0.26, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _apply_ignore_filters(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_apply_ignore_filters(child)


func _place_above_badge() -> void:
	if _host == null or _label == null:
		return
	var mid_x: float = 0.0
	var top_y: float = 0.0
	var found: bool = false

	var level: Control = _host.get_node_or_null("LevelLabel") as Control
	if level != null:
		mid_x = (level.offset_left + level.offset_right) * 0.5
		top_y = minf(level.offset_top, level.position.y)
		found = true
	else:
		var badge: Control = _host.get_node_or_null("ColorRect") as Control
		if badge != null:
			mid_x = (badge.offset_left + badge.offset_right) * 0.5
			top_y = minf(badge.offset_top, badge.position.y)
			found = true

	if not found:
		var sprite: Sprite2D = _host.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			# Match ResourceManager buildings: name sits just above the lower
			# "badge zone" near the bottom of the art — NOT above the sprite top.
			# (Using sprite.top made PetDen / HallOfLegends labels float far above.)
			mid_x = sprite.position.x
			var visual_h: float = 80.0
			if sprite.texture != null:
				visual_h = absf(float(sprite.texture.get_height()) * sprite.scale.y)
			var half_h: float = visual_h * 0.5
			if sprite.centered:
				# Lower third of the sprite (badge-equivalent band).
				top_y = sprite.position.y + half_h * 0.42
			else:
				top_y = sprite.position.y + visual_h * 0.72
			found = true

	if not found:
		mid_x = 0.0
		top_y = -40.0

	mid_x += anchor_offset.x
	top_y += anchor_offset.y

	var text_w: float = _label.get_minimum_size().x + 20.0
	var h: float = 26.0
	custom_minimum_size = Vector2(text_w, h)
	size = Vector2(text_w, h)
	# Anchor so scale pivots from bottom-center above the badge.
	pivot_offset = Vector2(text_w * 0.5, h)
	position = Vector2(mid_x - text_w * 0.5, top_y - h - vertical_gap_px)


func _refresh_camera_ref() -> void:
	_camera = null
	if _host == null or not is_instance_valid(_host):
		return
	var tree: SceneTree = _host.get_tree()
	if tree == null:
		return
	var scene: Node = tree.current_scene
	if scene != null:
		var cam2: Node = scene.get_node_or_null("Camera2D")
		if cam2 is Camera2D:
			_camera = cam2 as Camera2D
			return
	var cam_n: Node = tree.root.find_child("Camera2D", true, false)
	if cam_n is Camera2D:
		_camera = cam_n as Camera2D


func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	if _camera == null or not is_instance_valid(_camera):
		_refresh_camera_ref()
	_update_zoom_visuals()


func _update_zoom_visuals() -> void:
	var zoom_x: float = reference_zoom
	if _camera != null and is_instance_valid(_camera):
		zoom_x = _camera.zoom.x

	visible = zoom_x >= zoom_visible_min
	if not visible:
		return

	var factor: float = reference_zoom / maxf(0.05, zoom_x)
	factor = clampf(factor, min_scale_factor, max_scale_factor)
	scale = Vector2(factor, factor)
