extends Node

@export var building_level: int = 1
@export var building_name: String = "Farm"
@export var ready_to_collect: bool = true
@export var collect_amount: int = 100
@export var opens_troop_training: bool = false
@export var troop_type: String = ""
@export var building_id: String = ""

var press_position := Vector2.ZERO
var upgrading := false
var upgrade_finish_time := 0

func _ready():
	load_building_level()
	check_upgrade_finished()
	update_level_label()
	set_ready_to_collect(ready_to_collect)

	if has_node("ClickArea"):
		$ClickArea.input_event.connect(_on_click_area_input_event)

	if has_node("UpgradeArea"):
		$UpgradeArea.input_pickable = true
		$UpgradeArea.input_event.connect(_on_upgrade_area_input_event)

func _process(_delta):
	check_upgrade_finished()

func set_ready_to_collect(is_ready: bool):
	ready_to_collect = is_ready
	if has_node("CollectIcon"):
		$CollectIcon.visible = is_ready

func _on_click_area_input_event(_viewport, event, _shape_idx):
	if GameState.popup_open:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_position = event.position
			return

		if press_position.distance_to(event.position) > 15:
			return

		if ready_to_collect:
			if building_name == "Farm":
				GameState.add_food(collect_amount)
			elif building_name == "LumberMill":
				GameState.add_wood(collect_amount)
			elif building_name == "Quarry":
				GameState.add_stone(collect_amount)
			elif building_name == "IronMine":
				GameState.add_iron(collect_amount)

			set_ready_to_collect(false)

			get_tree().create_timer(5.0).timeout.connect(func():
				set_ready_to_collect(true)
			)

func _on_upgrade_area_input_event(_viewport, event, _shape_idx):
	if GameState.popup_open:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_position = event.position
			return

		if press_position.distance_to(event.position) > 15:
			return

		if opens_troop_training:
			get_tree().current_scene.get_node("TroopTrainingPanel").open_for_troop(troop_type)
			return

		open_upgrade_window()

func start_upgrade_timer():
	upgrading = true
	var seconds_needed: int = building_level * 10
	upgrade_finish_time = int(Time.get_unix_time_from_system()) + seconds_needed
	save_building_level()

func check_upgrade_finished():
	if not upgrading:
		return

	var now: int = int(Time.get_unix_time_from_system())

	if now >= upgrade_finish_time:
		upgrading = false
		upgrade_finish_time = 0
		building_level += 1
		update_level_label()
		save_building_level()

func get_upgrade_time_left() -> int:
	if not upgrading:
		return 0

	var now: int = int(Time.get_unix_time_from_system())
	return max(0, upgrade_finish_time - now)
	
func update_level_label():
	if has_node("LevelLabel"):
		$LevelLabel.text = str(building_level)

func save_building_level():
	var save = ConfigFile.new()
	save.load("user://buildings.cfg")
	save.set_value(building_name, "level", building_level)
	save.set_value(building_name, "upgrading", upgrading)
	save.set_value(building_name, "upgrade_finish_time", upgrade_finish_time)
	save.save("user://buildings.cfg")

func load_building_level():
	var save = ConfigFile.new()
	if save.load("user://buildings.cfg") == OK:
		building_level = save.get_value(building_name, "level", 1)
		upgrading = save.get_value(building_name, "upgrading", false)
		upgrade_finish_time = save.get_value(building_name, "upgrade_finish_time", 0)

func open_upgrade_window() -> void:
	if building_id.is_empty():
		push_error("ResourceManager: building_id is empty on " + name)
		return

	var window := get_tree().current_scene.find_child(
		"BuildingUpgradeWindow",
		true,
		false
	)

	if window == null:
		push_error("ResourceManager: BuildingUpgradeWindow not found.")
		return

	if not window.has_method("open_for_building"):
		push_error("ResourceManager: Upgrade window is missing open_for_building().")
		return

	window.open_for_building(building_id)
