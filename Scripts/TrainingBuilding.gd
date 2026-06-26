extends Node2D

@export var troop_type: String = "Infantry"

func _ready():
	if has_node("UpgradeArea"):
		$UpgradeArea.input_event.connect(_on_click)

func _on_click(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			get_tree().current_scene.get_node("TroopTrainingPanel").open_for_troop(troop_type)

func _input(event):
	if visible:
		get_viewport().set_input_as_handled()
