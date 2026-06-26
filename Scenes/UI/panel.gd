extends Node2D

func _ready():
	$Panel/TitleLabel.text = "Castle"
	$Panel/LevelLabel.text = "Level: 1"

	$Panel/CostLabel.text = "Cost:\nFood: 1000\nWood: 500\nStone: 200\nIron: 50"

	$Panel/OwnedLabel.text = "Owned:\nFood: 800\nWood: 500\nStone: 100\nIron: 25"

	$Panel/MissingLabel.text = "Missing:\nFood: 200\nStone: 100\nIron: 25"

	$Panel/CloseButton.pressed.connect(_on_close_pressed)

func _on_close_pressed():
	queue_free()
