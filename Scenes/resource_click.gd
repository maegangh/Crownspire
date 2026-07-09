extends Area2D

@export var resource_type: String = "food"
@export var level: int = 1
@export var amount: int = 1000
@export var card_texture: Texture2D

var resource_node: Node2D

func _ready() -> void:
	input_pickable = true
	monitoring = true
	resource_node = get_parent()

func _input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_open_panel()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_panel()

func _open_panel() -> void:
	print("RESOURCE CLICKED: ", resource_type, " Lv.", level, " amount: ", amount)
