extends CanvasLayer

var current_monster = null

@onready var background = $Background
@onready var title_label = $Background/TitleLabel
@onready var scout_button = $Background/ScoutButton
@onready var attack_button = $Background/AttackButton
@onready var close_button = $Background/CloseButton

func _ready():
	print("MONSTER POPUP READY")
	hide()

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	scout_button.pressed.connect(_on_scout_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	close_button.pressed.connect(_on_close_pressed)

func open_for_monster(monster):
	current_monster = monster
	var level = int(monster.monster_data.get("level", 1))
	title_label.text = "Lv.%d Crystalfang Beast" % level
	show()

func _on_scout_pressed():
	title_label.text = "Power: Easy"

func _on_attack_pressed():
	var started = MarchState.start_march("Attack", "Crystalfang Beast", 10)

	if started:
		hide()

func _on_close_pressed():
	hide()
