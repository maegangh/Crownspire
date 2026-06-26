extends Control

func _process(_delta):
	$FoodLabel.text = str(GameState.food)
	$WoodLabel.text = str(GameState.wood)
	$StoneLabel.text = str(GameState.stone)
	$IronLabel.text = str(GameState.iron)
	$GemLabel.text = "0"
