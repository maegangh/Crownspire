extends Control

@export var bonus_row_scene: PackedScene
@export var requirement_row_scene: PackedScene

@onready var building_image = $BuildingDisplay/BuildingImage

@onready var building_name = $BuildingDisplay/TitleBar/TitleTextBox/BuildingName

@onready var current_level_label = $BuildingDisplay/TitleBar/TitleTextBox/LevelRow/CurrentLevelLabel

@onready var next_level_label = $BuildingDisplay/TitleBar/TitleTextBox/LevelRow/NextLevelLabel

@onready var bonus_container = find_child("BonusContainer", true, false)
@onready var requirements_container = find_child("RequirementsContainer", true, false)

@onready var finish_button = find_child("FinishButton", true, false)
@onready var upgrade_button = find_child("UpgradeButton", true, false)
@onready var close_button = find_child("CloseButton", true, false)

func _ready() -> void:
	print_tree_pretty()
	print("building_name: ", building_name)
	print("current_level_label: ", current_level_label)
	print("next_level_label: ", next_level_label)

	if close_button:
		close_button.pressed.connect(hide)

func show_building(data: Dictionary) -> void:
	visible = true

	var current_level := int(data.get("level", 1))

	building_name.text = data.get("name", "Building")
	current_level_label.text = "Lv. %d" % current_level
	next_level_label.text = "Lv. %d" % (current_level + 1)

	_clear_container(bonus_container)
	_clear_container(requirements_container)

	for bonus in data.get("bonuses", []):
		var row = bonus_row_scene.instantiate()
		bonus_container.add_child(row)
		row.setup(bonus)

	for requirement in data.get("requirements", []):
		var row = requirement_row_scene.instantiate()
		requirements_container.add_child(row)
		row.setup(requirement)

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
		
func _input(event):
	if event.is_action_pressed("ui_accept"):
		show_building({
			"name":"Crystal Citadel",
			"level":29,
			"bonuses":[
				{
					"name":"Power",
					"current":"125,040",
					"new":"143,200",
					"increase":"18,160"
				},
				{
					"name":"Hospital Capacity",
					"current":"26,500",
					"new":"32,000",
					"increase":"5,500"
				},
				{
					"name":"Food Production",
					"current":"5,200",
					"new":"5,800",
					"increase":"600"
				}
			],
			"requirements":[
				{
					"name":"Embassy",
					"current":"Lv.28",
					"required":"Lv.29",
					"met":false,
					"action":"Go"
				},
				{
					"name":"Food",
					"current":"45.6M",
					"required":"273M",
					"met":false,
					"action":"Obtain"
				},
				{
					"name":"Wood",
					"current":"202M",
					"required":"202M",
					"met":true
				},
				{
					"name":"Stone",
					"current":"27M",
					"required":"54M",
					"met":false,
					"action":"Obtain"
				},
				{
					"name":"Iron",
					"current":"7.7M",
					"required":"13M",
					"met":false,
					"action":"Obtain"
				}
			]
		})
