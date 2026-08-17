extends Control

## World Map resource information card — Gather opens March Setup.
## Architectural reference: WildlingPanel (do not convert that panel).

const DISPLAY_NAME_BY_TYPE := {
	"food": "Fertile Wheat Farm",
	"wood": "Cedar Lumber Camp",
	"stone": "Granite Stone Quarry",
	"iron": "Magnetic Iron Lode",
}

const TYPE_LABEL_BY_ID := {
	"food": "Food",
	"wood": "Wood",
	"stone": "Stone",
	"iron": "Iron",
}
const ModalOutsideDismiss := preload("res://Scripts/UI/ModalOutsideDismiss.gd")

var selected_resource: Node2D = null
var selected_type: String = "food"
var selected_level: int = 1
var selected_amount: int = 0
var selected_tile_id: String = ""
var selected_texture: Texture2D = null

@onready var _dim: ColorRect = $DimBackground
@onready var _card_root: PanelContainer = $CardRoot
@onready var _portrait: TextureRect = $CardRoot/CardMargin/CardColumn/Portrait
@onready var _name_label: Label = $CardRoot/CardMargin/CardColumn/NameLabel
@onready var _level_label: Label = $CardRoot/CardMargin/CardColumn/LevelLabel
@onready var _type_label: Label = $CardRoot/CardMargin/CardColumn/TypeLabel
@onready var _available_label: Label = $CardRoot/CardMargin/CardColumn/AvailableLabel
@onready var _gather_button: Button = $CardRoot/CardMargin/CardColumn/GatherButton
@onready var _close_button: Button = $CardRoot/CardMargin/CardColumn/HeaderRow/CloseButton
@onready var _error_label: Label = $CardRoot/CardMargin/CardColumn/ErrorLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_nodes()
	_style_card()

	if _dim:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
		ModalOutsideDismiss.bind(_dim, _card_root, close_panel)
	if _gather_button:
		_gather_button.pressed.connect(_on_gather_pressed)
	if _close_button:
		_close_button.pressed.connect(_on_close_pressed)
	if _portrait:
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.custom_minimum_size = Vector2(0, 220)
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _error_label:
		_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lbl: Label in [_name_label, _level_label, _type_label, _available_label]:
		if lbl:
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _bind_nodes() -> void:
	if _dim == null:
		_dim = get_node_or_null("DimBackground") as ColorRect
	if _card_root == null:
		_card_root = get_node_or_null("CardRoot") as PanelContainer
	if _portrait == null:
		_portrait = get_node_or_null("CardRoot/CardMargin/CardColumn/Portrait") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("CardRoot/CardMargin/CardColumn/NameLabel") as Label
	if _level_label == null:
		_level_label = get_node_or_null("CardRoot/CardMargin/CardColumn/LevelLabel") as Label
	if _type_label == null:
		_type_label = get_node_or_null("CardRoot/CardMargin/CardColumn/TypeLabel") as Label
	if _available_label == null:
		_available_label = get_node_or_null("CardRoot/CardMargin/CardColumn/AvailableLabel") as Label
	if _gather_button == null:
		_gather_button = get_node_or_null("CardRoot/CardMargin/CardColumn/GatherButton") as Button
	if _close_button == null:
		_close_button = get_node_or_null("CardRoot/CardMargin/CardColumn/HeaderRow/CloseButton") as Button
	if _error_label == null:
		_error_label = get_node_or_null("CardRoot/CardMargin/CardColumn/ErrorLabel") as Label


func _style_card() -> void:
	if _card_root == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.55, 0.72, 0.42, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	_card_root.add_theme_stylebox_override("panel", style)
	_card_root.mouse_filter = Control.MOUSE_FILTER_STOP

	if _name_label:
		_name_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	if _level_label:
		_level_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.58, 1.0))
	if _type_label:
		_type_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.70, 1.0))
	if _available_label:
		_available_label.add_theme_color_override("font_color", Color(0.70, 0.90, 0.62, 1.0))
	if _gather_button:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.28, 0.52, 0.30, 1.0)
		fill.border_color = Color(0.72, 0.88, 0.42, 1.0)
		fill.set_border_width_all(2)
		fill.set_corner_radius_all(12)
		_gather_button.add_theme_stylebox_override("normal", fill)
		_gather_button.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88, 1.0))
	if _close_button:
		var close_style := StyleBoxFlat.new()
		close_style.bg_color = Color(0.16, 0.14, 0.20, 1.0)
		close_style.border_color = Color(0.70, 0.58, 0.30, 0.9)
		close_style.set_border_width_all(2)
		close_style.set_corner_radius_all(10)
		_close_button.add_theme_stylebox_override("normal", close_style)
		_close_button.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80, 1.0))


func open_panel(
	resource_node: Node2D,
	resource_type: String,
	level: int,
	amount: int,
	icon_texture: Texture2D = null,
	tile_id: String = ""
) -> void:
	selected_resource = resource_node
	selected_type = resource_type.strip_edges().to_lower()
	selected_level = level
	selected_amount = amount
	selected_tile_id = tile_id
	selected_texture = icon_texture
	if selected_tile_id == "" and resource_node != null and is_instance_valid(resource_node):
		var click: Node = resource_node.get_node_or_null("ClickArea")
		if click != null and "tile_id" in click:
			selected_tile_id = str(click.get("tile_id"))
	_refresh_canonical_amount()
	if selected_texture == null and resource_node != null and is_instance_valid(resource_node):
		var sprite: Sprite2D = resource_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			selected_texture = sprite.texture

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 999
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	if _dim:
		_dim.visible = true
		_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP

	if _card_root:
		_card_root.position = Vector2(80, 160)
		_card_root.size = Vector2(420, 620)

	if _portrait:
		_portrait.texture = selected_texture
		_portrait.visible = selected_texture != null
	if _name_label:
		_name_label.text = display_name_for(selected_type)
	if _level_label:
		_level_label.text = "Lv. %d" % selected_level
	if _type_label:
		_type_label.text = "Resource type:\n%s" % type_label_for(selected_type)
	if _available_label:
		_available_label.text = "Available:\n%s" % _format_number(selected_amount)

	_hide_error()
	_update_gather_button_state()
	if has_node("/root/UiLayerStack"):
		UiLayerStack.push_layer("modal:ResourcePanel", close_panel, UiLayerStack.KIND_MODAL)


func reopen_last() -> void:
	if selected_resource == null or not is_instance_valid(selected_resource):
		return
	open_panel(
		selected_resource,
		selected_type,
		selected_level,
		selected_amount,
		selected_texture,
		selected_tile_id
	)


func _refresh_canonical_amount() -> void:
	if selected_tile_id == "" or not has_node("/root/ResourceTileState"):
		return
	var state: Dictionary = ResourceTileState.get_tile(selected_tile_id)
	if state.is_empty():
		return
	selected_level = int(state.get("level", selected_level))
	selected_amount = int(state.get("remaining_amount", selected_amount))
	selected_type = str(state.get("resource_type", selected_type))


func _update_gather_button_state() -> void:
	if _gather_button == null:
		return
	var can_gather: bool = selected_type in ["food", "wood", "stone", "iron"]
	var status: String = ""
	if has_node("/root/ResourceTileState") and selected_tile_id != "":
		status = ResourceTileState.get_status(selected_tile_id)
	if not can_gather:
		_gather_button.disabled = true
		_gather_button.text = "UNAVAILABLE"
		return
	if status == ResourceTileState.STATUS_RESERVED or status == ResourceTileState.STATUS_GATHERING:
		_gather_button.disabled = true
		_gather_button.text = "OCCUPIED"
		var status_text: String = "Gathering" if status == ResourceTileState.STATUS_GATHERING else "Occupied"
		if _available_label:
			_available_label.text = "Available:\n%s\nStatus: %s" % [_format_number(selected_amount), status_text]
		return
	if status == ResourceTileState.STATUS_DEPLETED or selected_amount <= 0:
		_gather_button.disabled = true
		_gather_button.text = "DEPLETED"
		return
	_gather_button.disabled = false
	_gather_button.text = "GATHER"


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dim:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_error()
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("modal:ResourcePanel")


func _on_close_pressed() -> void:
	close_panel()


func _on_gather_pressed() -> void:
	_hide_error()

	if selected_type not in ["food", "wood", "stone", "iron"]:
		_show_error("Only Food, Wood, Stone, and Iron can be gathered.")
		return
	if selected_resource == null or not is_instance_valid(selected_resource):
		_show_error("No resource selected.")
		return
	if not selected_resource.visible:
		_show_error("That resource is no longer available.")
		return
	if not has_node("/root/MarchState"):
		_show_error("March system unavailable.")
		return

	_refresh_canonical_amount()
	if has_node("/root/ResourceTileState") and selected_tile_id != "":
		var reserve_gate: Dictionary = ResourceTileState.can_reserve(selected_tile_id)
		if not bool(reserve_gate.get("ok", false)):
			_show_error(str(reserve_gate.get("error", "Resource tile is already occupied.")))
			_update_gather_button_state()
			return

	var target: Dictionary = MarchState.build_resource_target(
		selected_resource,
		selected_type,
		selected_level,
		selected_amount,
		selected_tile_id
	)
	if target.is_empty():
		_show_error("Could not lock resource target.")
		return

	var gate: Dictionary = MarchState.can_start_resource_setup()
	if not bool(gate.get("ok", false)):
		_show_error(str(gate.get("error", "Cannot open March Setup.")))
		return

	close_panel()

	var setup: Node = _find_march_setup()
	if setup == null or not setup.has_method("open_for_target"):
		reopen_last()
		_show_error("March Setup screen missing.")
		return

	setup.open_for_target(target)


func _find_march_setup() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var setup: Node = world.get_node_or_null("GameHUD/ScreenRoot/MarchSetupScreen")
	if setup != null:
		return setup
	return get_tree().root.get_node_or_null("GameHUD/ScreenRoot/MarchSetupScreen")


func _show_error(message: String) -> void:
	if _error_label == null:
		return
	_error_label.text = message
	_error_label.visible = true


func _hide_error() -> void:
	if _error_label != null:
		_error_label.visible = false
		_error_label.text = ""


static func display_name_for(resource_type: String) -> String:
	var key: String = resource_type.strip_edges().to_lower()
	return str(DISPLAY_NAME_BY_TYPE.get(key, key.capitalize()))


static func type_label_for(resource_type: String) -> String:
	var key: String = resource_type.strip_edges().to_lower()
	return str(TYPE_LABEL_BY_ID.get(key, key.capitalize()))


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
