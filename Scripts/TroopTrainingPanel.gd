extends CanvasLayer

var troop_type: String = "Infantry"
var selected_amount: int = 1
var max_train_amount: int = 100
var selected_tier: int = 1

@onready var title_label: Label = $Panel/TitleLabel
@onready var count_label: Label = $Panel/CountLabel
@onready var max_label: Label = $Panel/MaxLabel
@onready var amount_label: Label = $Panel/AmountLabel
@onready var amount_slider: HSlider = $Panel/AmountSlider
@onready var cost_label: Label = $Panel/CostLabel
@onready var train_button: Button = $Panel/TrainButton
@onready var close_button: Button = $Panel/CloseButton


func _ready() -> void:
	hide()

	amount_slider.min_value = 1
	amount_slider.max_value = max_train_amount
	amount_slider.step = 1
	amount_slider.value = 1

	amount_slider.value_changed.connect(_on_amount_slider_changed)
	train_button.pressed.connect(_on_train_pressed)
	close_button.pressed.connect(_on_close_pressed)


func _process(_delta: float) -> void:
	if visible:
		update_panel()


func open_for_troop(type: String, tier: int = 1) -> void:
	# Legacy City popup — redirect to production ScreenRoot training UI.
	var hud: Node = get_tree().current_scene.get_node_or_null("GameHUD")
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	var screen: Node = hud.get_node_or_null("ScreenRoot/TroopTrainingScreen") if hud else null
	if screen != null and screen.has_method("open_for_building"):
		var level: int = 1
		# Prefer live building level from city nodes when available.
		var building: Node = get_tree().current_scene.find_child(
			_legacy_building_node_name(type), true, false
		)
		if building != null and "building_level" in building:
			level = int(building.get("building_level"))
		screen.call("open_for_building", type, "", level)
		hide()
		return

	# Fallback: keep old debug panel only if production screen is missing.
	GameState.popup_open = true
	troop_type = type
	selected_tier = tier
	selected_amount = 1
	amount_slider.value = 1
	update_panel()
	show()


func _legacy_building_node_name(type: String) -> String:
	match type.to_lower():
		"infantry":
			return "InfantryBarracks"
		"marksmen", "marksman":
			return "MarksmenCamp"
		"cavalry":
			return "CavalryStable"
		_:
			return ""


func update_panel() -> void:
	var troop: Dictionary = _get_selected_troop()
	var display_name: String = str(troop.get("name", troop_type))
	var clean_type: String = _get_clean_troop_type()
	var cost: Dictionary = TroopDatabase.get_training_cost(clean_type, selected_tier, selected_amount)
	var training_time: int = TroopDatabase.get_training_time(clean_type, selected_tier, selected_amount)
	var power_gain: int = TroopDatabase.get_power_gain(clean_type, selected_tier, selected_amount)

	title_label.text = "Train " + display_name
	count_label.text = display_name + " Owned: " + str(TroopState.get_troop_count(troop_type))
	max_label.text = "Max Train: " + str(max_train_amount)
	amount_label.text = "Amount: " + str(selected_amount)

	if TroopState.is_training_active(troop_type):
		cost_label.text = "Training... " + str(int(TroopState.get_training_time_left(troop_type))) + "s left"
		train_button.disabled = true
		return

	train_button.disabled = false

	var missing_text: String = TroopDatabase.get_missing_cost_text(cost)
	var cost_text: String = TroopDatabase.format_cost(cost)

	if missing_text != "":
		cost_label.text = cost_text + "\n" + missing_text
	else:
		cost_label.text = cost_text + "\nTime: " + str(training_time) + "s | Power: +" + str(power_gain)


func _on_amount_slider_changed(value: float) -> void:
	selected_amount = int(value)
	update_panel()


func _on_train_pressed() -> void:
	var clean_type: String = _get_clean_troop_type()
	var cost: Dictionary = TroopDatabase.get_training_cost(clean_type, selected_tier, selected_amount)

	if not TroopDatabase.can_afford(cost):
		cost_label.text = TroopDatabase.format_cost(cost) + "\n" + TroopDatabase.get_missing_cost_text(cost)
		return

	var started: bool = TroopState.start_training(troop_type, selected_amount)

	if not started:
		cost_label.text = "Already training"
		return

	var spent: bool = TroopDatabase.spend_training_cost(cost)

	if not spent:
		cost_label.text = TroopDatabase.get_missing_cost_text(cost)
		return

	if has_node("/root/GameEvents"):
			update_panel()


func _on_close_pressed() -> void:
	GameState.popup_open = false
	hide()


func _get_selected_troop() -> Dictionary:
	if has_node("/root/TroopDatabase"):
		var clean_type: String = _get_clean_troop_type()
		var troop: Dictionary = TroopDatabase.get_troop(clean_type, selected_tier)
		if not troop.is_empty():
			return troop

	return {
		"name": troop_type,
		"trainingCost": {
			"food": 0,
			"wood": 0,
			"stone": 0,
			"iron": 0
		},
		"trainingTimeSec": 1,
		"power": 0
	}


func _get_clean_troop_type() -> String:
	match troop_type.to_lower():
		"infantry":
			return "infantry"
		"marksmen", "marksman", "archer", "archers":
			return "marksmen"
		"cavalry":
			return "cavalry"
		_:
			return troop_type.to_lower()
