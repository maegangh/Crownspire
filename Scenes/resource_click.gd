extends Area2D

## World resource tile click area. Opens ResourcePanel on TAP only (drag-safe).

const WorldGestureUtil = preload("res://scripts/World/WorldGesture.gd")

@export var resource_type: String = "food"
@export var level: int = 1
@export var amount: int = 1000
@export var tile_id: String = ""
@export var card_texture: Texture2D

var resource_node: Node2D


func _ready() -> void:
	input_pickable = true
	monitoring = true
	monitorable = true
	resource_node = get_parent()
	_ensure_click_shape_matches_sprite()


func _ensure_click_shape_matches_sprite() -> void:
	## Safety net: ResourceNode.tscn ships a 20×20 shape; at 0.10 scale that is unusable.
	var node: Node2D = resource_node if resource_node != null else get_parent() as Node2D
	if node == null:
		return
	var sprite: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if sprite == null or sprite.texture == null or shape_node == null:
		return
	var desired: Vector2 = sprite.texture.get_size() * sprite.scale.abs()
	var current: RectangleShape2D = shape_node.shape as RectangleShape2D
	if current == null or current.size.x < desired.x * 0.5 or current.size.y < desired.y * 0.5:
		var rect := RectangleShape2D.new()
		rect.size = desired
		shape_node.shape = rect
	shape_node.position = sprite.position
	shape_node.disabled = false
	input_pickable = true


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Do not mark handled on press — MapCamera must still receive drag-start for pan-from-tile.
	if event is InputEventScreenTouch:
		if event.pressed:
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			_open_panel()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			_open_panel()


func _open_panel() -> void:
	# Crystal tiles may still exist from older content; popup can show them but Gather is gated.
	var panel: Node = _find_resource_panel()
	if panel == null:
		push_error("ResourcePanel not found under HUD/")
		return
	if not panel.has_method("open_panel"):
		push_error("ResourcePanel missing open_panel()")
		return

	var node: Node2D = resource_node if resource_node != null else get_parent() as Node2D
	var tex: Texture2D = card_texture
	if tex == null and node != null:
		var sprite: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			tex = sprite.texture

	var show_level: int = level
	var show_amount: int = amount
	var show_tile_id: String = tile_id
	if show_tile_id == "" and node != null and "tile_id" in node:
		show_tile_id = str(node.get("tile_id"))
	if has_node("/root/ResourceTileState") and show_tile_id != "":
		var state: Dictionary = ResourceTileState.get_tile(show_tile_id)
		if not state.is_empty():
			show_level = int(state.get("level", show_level))
			show_amount = int(state.get("remaining_amount", show_amount))

	panel.call("open_panel", node, resource_type, show_level, show_amount, tex, show_tile_id)
	if has_node("/root/GameEvents"):
		GameEvents.emit_resource_tile_selected(str(resource_type))


func _find_resource_panel() -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var panel: Node = scene.get_node_or_null("HUD/ResourcePanel")
	if panel != null:
		return panel
	return get_tree().root.find_child("ResourcePanel", true, false)
