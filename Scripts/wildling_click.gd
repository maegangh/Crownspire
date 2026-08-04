extends Area2D

@export var card_texture: Texture2D
@export var level: int = 1
@export var power: int = 100
@export var species: String = "wolf"

var wildling_node: Node2D

func _ready() -> void:
	input_pickable = true
	monitoring = true
	wildling_node = get_parent()

func _input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_open_wildling_panel()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_wildling_panel()

func _open_wildling_panel() -> void:
	var panel = get_tree().current_scene.get_node_or_null("HUD/WildlingPanel")

	if panel == null:
		print("ERROR: HUD/WildlingPanel not found")
		return

	if not panel.has_method("open_panel"):
		print("ERROR: WildlingPanel missing open_panel()")
		return

	panel.open_panel(card_texture, level, power, wildling_node, species)
	if has_node("/root/GameEvents"):
		var wid: String = ""
		if wildling_node != null and "instance_id" in wildling_node:
			wid = str(wildling_node.get("instance_id"))
		if wid.is_empty():
			wid = "%s_L%d" % [species.strip_edges().to_lower(), level]
		GameEvents.emit_wildling_selected(wid)
