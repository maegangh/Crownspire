extends CanvasLayer

var troop_type = "Infantry"
var selected_amount = 1
var max_train_amount = 100

@onready var title_label = $Panel/TitleLabel
@onready var count_label = $Panel/CountLabel
@onready var max_label = $Panel/MaxLabel
@onready var amount_label = $Panel/AmountLabel
@onready var amount_slider = $Panel/AmountSlider
@onready var cost_label = $Panel/CostLabel
@onready var train_button = $Panel/TrainButton
@onready var close_button = $Panel/CloseButton

func _ready():
	hide()
	amount_slider.min_value = 1
	amount_slider.max_value = max_train_amount
	amount_slider.step = 1
	amount_slider.value = 1

	amount_slider.value_changed.connect(_on_amount_slider_changed)
	train_button.pressed.connect(_on_train_pressed)
	close_button.pressed.connect(_on_close_pressed)

func _process(_delta):
	if visible:
		update_panel()

func open_for_troop(type):
	GameState.popup_open = true
	troop_type = type
	selected_amount = 1
	amount_slider.value = 1
	update_panel()
	show()

func update_panel():
	var food_cost = selected_amount * 10

	title_label.text = "Train " + troop_type
	count_label.text = troop_type + " Owned: " + str(TroopState.get_troop_count(troop_type))
	max_label.text = "Max Train: " + str(max_train_amount)
	amount_label.text = "Amount: " + str(selected_amount)

	if TroopState.is_training_active(troop_type):
		cost_label.text = "Training... " + str(int(TroopState.get_training_time_left(troop_type))) + "s left"
	else:
		cost_label.text = "Cost: " + str(food_cost) + " Food"

func _on_amount_slider_changed(value):
	selected_amount = int(value)
	update_panel()

func _on_train_pressed():
	var food_cost = selected_amount * 10

	if GameState.food < food_cost:
		cost_label.text = "Missing Food"
		return

	var started = TroopState.start_training(troop_type, selected_amount)

	if not started:
		cost_label.text = "Already training"
		return

	GameState.spend_resources(food_cost, 0, 0, 0)
	update_panel()

func _on_close_pressed():
	GameState.popup_open = false
	hide()
