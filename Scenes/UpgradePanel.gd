extends CanvasLayer

var current_building = null

@onready var title_label = $UpgradePanel/Panel/TitleLabel
@onready var level_label = $UpgradePanel/Panel/LevelLabel
@onready var prerequisite_label = $UpgradePanel/Panel/PrerequisiteLabel
@onready var food_label = $UpgradePanel/Panel/FoodLabel
@onready var wood_label = $UpgradePanel/Panel/WoodLabel
@onready var stone_label = $UpgradePanel/Panel/StoneLabel
@onready var iron_label = $UpgradePanel/Panel/IronLabel
@onready var missing_label = $UpgradePanel/Panel/MissingLabel
@onready var upgrade_button = $UpgradePanel/Panel/UpgradeButton
@onready var close_button = $UpgradePanel/Panel/CloseButton

func _ready():
	hide()
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_button.pressed.connect(_on_close_pressed)

func _process(_delta):
	if visible and current_building != null:
		update_panel()

func open_for_building(building):
	GameState.popup_open = true
	current_building = building
	update_panel()
	show()

func update_panel():
	var lvl = current_building.building_level
	var food_cost = lvl * 100
	var wood_cost = lvl * 75
	var stone_cost = lvl * 50
	var iron_cost = lvl * 25

	title_label.text = current_building.building_name
	level_label.text = "Lv." + str(lvl) + " >> Lv." + str(lvl + 1)
	prerequisite_label.text = "Prerequisites: None"

	food_label.text = "Food: " + str(GameState.food) + " / " + str(food_cost)
	wood_label.text = "Wood: " + str(GameState.wood) + " / " + str(wood_cost)
	stone_label.text = "Stone: " + str(GameState.stone) + " / " + str(stone_cost)
	iron_label.text = "Iron: " + str(GameState.iron) + " / " + str(iron_cost)

	missing_label.text = ""

	if current_building.upgrading:
		missing_label.text = "Upgrading... " + str(current_building.get_upgrade_time_left()) + "s left"
		upgrade_button.disabled = true
		upgrade_button.text = "UPGRADING"
		return

	upgrade_button.disabled = false
	upgrade_button.text = "UPGRADE"

	if GameState.food < food_cost:
		missing_label.text = "Missing Food"
	elif GameState.wood < wood_cost:
		missing_label.text = "Missing Wood"
	elif GameState.stone < stone_cost:
		missing_label.text = "Missing Stone"
	elif GameState.iron < iron_cost:
		missing_label.text = "Missing Iron"

func _on_upgrade_pressed():
	# Phase 0B3-B: residual UpgradePanel must not spend, start timers, or create jobs.
	# Active City upgrades use BuildingUpgradeWindow → ConstructionState.
	if current_building != null and bool(current_building.get("upgrading")):
		return
	push_warning(
		"UpgradePanel: obsolete legacy upgrade path disabled (0B3-B); "
		+ "refusing spend/timer/job. Use BuildingUpgradeWindow."
	)
	if missing_label != null:
		missing_label.text = "Upgrade unavailable — use City Building Upgrade window"
	if upgrade_button != null:
		upgrade_button.disabled = true
		upgrade_button.text = "UNAVAILABLE"
	return

func _on_close_pressed():
	GameState.popup_open = false
	hide()
