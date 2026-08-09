# ==============================================================================
# Crownspire MMO - Resource Node Script
# Godot 4.6 / GDScript 2.0 Clickable Resource Node for Map Exploration
# ==============================================================================

extends Node2D

signal clicked(node: ResourceNode)

@export var resource_type: String = "food"
@export var level: int = 1
@export var amount: int = 10000

@onready var sprite: Sprite2D = $Sprite2D
@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D

var _hovered: bool = false

func _ready() -> void:
	if click_area:
		click_area.input_event.connect(_on_input_event)
		click_area.mouse_entered.connect(_on_mouse_entered)
		click_area.mouse_exited.connect(_on_mouse_exited)

# Set node data and update appearance dynamically
func setup_node(type: String, lvl: int, amt: int, texture: Texture2D) -> void:
	resource_type = type
	level = lvl
	amount = amt
	
	if texture:
		sprite.texture = texture
	else:
		push_error("ResourceNode: Null texture passed for type " + type)
		
	# Subtle random scaling for organic, beautiful variety on the maps
	scale = Vector2.ONE * randf_range(0.9, 1.1)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Support tapping on Mobile (ScreenTouch) and clicks on PC (MouseButton)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_trigger_click()
	elif event is InputEventScreenTouch and event.pressed:
		_trigger_click()

func _trigger_click() -> void:
	# Visual feed-forward bounce effect
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", scale * 1.15, 0.08)
	tween.tween_property(self, "scale", scale, 0.1)
	
	clicked.emit(self)

func _on_mouse_entered() -> void:
	_hovered = true
	# Highlight outline shader or modulation
	modulate = Color(1.1, 1.1, 1.1, 1.0)

func _on_mouse_exited() -> void:
	_hovered = false
	modulate = Color(1.0, 1.0, 1.0, 1.0)
