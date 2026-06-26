extends Area2D

@export var card_texture: Texture2D
@export var level: int = 1
@export var power: int = 100

func _ready():
	input_pickable = true
	monitoring = true
	print("Wildling Area2D ready: ", name)

func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("WILDLING CLICKED")

		var panel = get_tree().current_scene.get_node_or_null("CanvasLayer/WildlingPanel")
		if panel == null:
			print("ERROR: WildlingPanel not found")
			return

		if card_texture == null:
			print("ERROR: Card texture is empty")
			return

		panel.open_panel(card_texture, level, power, get_parent())
		
func respawn():
	visible = false
	$CollisionShape2D.disabled = true

	await get_tree().create_timer(10.0).timeout

	visible = true
	$CollisionShape2D.disabled = false

	print(name + " respawned")
