extends Node2D

@export var building_level: int = 1
var ready_to_collect := true

func _ready():
	$LevelLabel.text = str(building_level)
	set_ready_to_collect(true)

	$ClickArea.input_event.connect(_on_click_area_input_event)

func set_ready_to_collect(is_ready: bool):
	ready_to_collect = is_ready
	$CollectIcon.visible = is_ready

func _on_click_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if ready_to_collect:
			print("Collected farm resources!")
			set_ready_to_collect(false)
