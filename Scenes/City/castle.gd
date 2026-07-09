extends Node2D

@export var building_id: String = "citadel"
@export var building_level: int = 1
@export var building_name: String = "Crystal Citadel"

var upgrading := false
var upgrade_finish_time := 0

func _ready() -> void:
	load_building_level()
	check_upgrade_finished()
	update_level_label()

	if has_node("UpgradeArea"):
		$UpgradeArea.input_pickable = true
		$UpgradeArea.input_event.connect(_on_upgrade_area_input_event)

	if has_node("Area2D"):
		$Area2D.input_pickable = true
		$Area2D.input_event.connect(_on_upgrade_area_input_event)

func _process(_delta: float) -> void:
	check_upgrade_finished()

func _on_upgrade_area_input_event(_viewport, event, _shape_idx) -> void:
	print("Castle clicked")

	if GameState.popup_open:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			open_building_upgrade_window()

func open_building_upgrade_window() -> void:
	var window = get_tree().current_scene.find_child("BuildingUpgradeWindow", true, false)

	if window:
		window.open_for_building(building_id)
	else:
		push_warning("BuildingUpgradeWindow not found. Make sure it is inside GameHUD.")
		
func start_upgrade_timer() -> void:
	upgrading = true
	var seconds_needed = building_level * 10
	upgrade_finish_time = Time.get_unix_time_from_system() + seconds_needed
	save_building_level()

func check_upgrade_finished() -> void:
	if not upgrading:
		return

	var now = Time.get_unix_time_from_system()

	if now >= upgrade_finish_time:
		upgrading = false
		upgrade_finish_time = 0
		building_level += 1
		update_level_label()
		save_building_level()

func get_upgrade_time_left() -> int:
	if not upgrading:
		return 0

	var now = Time.get_unix_time_from_system()
	return max(0, upgrade_finish_time - now)

func update_level_label() -> void:
	if has_node("LevelLabel"):
		$LevelLabel.text = str(building_level)

func save_building_level() -> void:
	var save = ConfigFile.new()
	save.load("user://buildings.cfg")
	save.set_value(building_name, "level", building_level)
	save.set_value(building_name, "upgrading", upgrading)
	save.set_value(building_name, "upgrade_finish_time", upgrade_finish_time)
	save.save("user://buildings.cfg")

func load_building_level() -> void:
	var save = ConfigFile.new()
	if save.load("user://buildings.cfg") == OK:
		building_level = save.get_value(building_name, "level", 1)
		upgrading = save.get_value(building_name, "upgrading", false)
		upgrade_finish_time = save.get_value(building_name, "upgrade_finish_time", 0)
