extends Node2D

@export var wildling_name: String = "Wildling Wolf"
@export var wildling_level: int = 1
@export var wildling_image: Texture2D
@export var card_image: Texture2D
@export var recommended_power: int = 100
@export var stamina_cost: int = 10

func _ready():
	$Sprite2D.texture = wildling_image
	$LevelBadge.text = str(wildling_level)
	$ClickArea.input_event.connect(_on_click)

func _on_click(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed:
		var panel = get_tree().current_scene.get_node("CanvasLayer/WildlingPanel")
		panel.open_panel(wildling_name, wildling_level, card_image, recommended_power, stamina_cost)
