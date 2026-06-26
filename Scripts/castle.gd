extends Node2D

@export var building_level: int = 1
@export var building_name: String = "Castle"

func _ready():
	load_building_level()
	update_level_label()

	if has_node("UpgradeArea"):
		$UpgradeArea.input_pickable = true
		$UpgradeArea.input_event.connect(_on_upgrade_click)

	if has_node("Area2D"):
		$Area2D.input_pickable = true
		$Area2D.input_event.connect(_on_upgrade_click)

func _on_upgrade_click(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("CASTLE CLICKED")
			get_tree().current_scene.get_node("UpgradePanel").open_for_building(self)

func update_level_label():
	if has_node("LevelLabel"):
		$LevelLabel.text = str(building_level)

func save_building_level():
	var save = ConfigFile.new()
	save.load("user://buildings.cfg")
	save.set_value(building_name, "level", building_level)
	save.save("user://buildings.cfg")
	print("Saved Castle level: ", building_level)

func load_building_level():
	var save = ConfigFile.new()
	if save.load("user://buildings.cfg") == OK:
		building_level = save.get_value(building_name, "level", 1)
		print("Loaded Castle level: ", building_level)
