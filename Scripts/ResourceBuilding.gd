extends Node2D

@export var building_level: int = 1
@export var building_name: String = "Farm"
@export var ready_to_collect: bool = true
@export var collect_amount: int = 100

func _ready():
	$LevelLabel.text = str(building_level)
	set_ready_to_collect(ready_to_collect)
	$ClickArea.input_event.connect(_on_click_area_input_event)

func set_ready_to_collect(is_ready: bool):
	ready_to_collect = is_ready
	$CollectIcon.visible = is_ready

func _on_click_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if ready_to_collect:
			if building_name == "Farm":
				GameState.food += collect_amount
				print("Food: ", GameState.food)

			elif building_name == "LumberMill":
				GameState.wood += collect_amount
				print("Wood: ", GameState.wood)

			elif building_name == "Quarry":
				GameState.stone += collect_amount
				print("Stone: ", GameState.stone)

			elif building_name == "IronMine":
				GameState.iron += collect_amount
				print("Iron: ", GameState.iron)

			set_ready_to_collect(false)

			await get_tree().create_timer(5.0).timeout
			set_ready_to_collect(true)
