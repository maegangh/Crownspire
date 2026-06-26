extends Area2D

var monster_data = {}

func _ready():
	print("MONSTER READY")
	input_pickable = true
	input_event.connect(_on_area_clicked)

func setup(data):
	monster_data = data
	var x = data.get("x", randi_range(300, 1200))
	var y = data.get("y", randi_range(300, 900))
	position = Vector2(x, y)
	z_index = 100
	scale = Vector2(0.4, 0.4)

	var level = int(data.get("level", 1))
	if has_node("Label"):
		$Label.position = Vector2(-40, -160)
		$Label.text = "Lv.%d" % level

func _on_area_clicked(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var popup = get_tree().current_scene.find_child("MonsterPopUp", true, false)
		if popup:
			popup.open_for_monster(self)
