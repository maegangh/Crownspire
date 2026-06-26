extends Node2D

var building_id := "castle"
var level := 1

func setup(id: String):
	building_id = id
	refresh()

func _ready():
	$Panel/CloseButton.pressed.connect(_on_close_pressed)
	$Panel/UpgradeButton.pressed.connect(_on_upgrade_pressed)
	refresh()

func refresh():
	$Panel/TitleLabel.text = building_id.capitalize()
	$Panel/LevelLabel.text = "Level: " + str(level)
	$Panel/CostLabel.text = "Cost:\nFood: 1000\nWood: 500\nStone: 200\nIron: 50"
	$Panel/ShortLabel.text = "Missing:\nNone"

func _on_upgrade_pressed():
	level += 1
	refresh()
	print(building_id, " upgraded to level ", level)

func _on_close_pressed():
	queue_free()
