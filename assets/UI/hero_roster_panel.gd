extends CanvasLayer

@onready var list := $Panel/ScrollContainer/VBoxContainer

func _ready():
	load_heroes()

func load_heroes():
	var file := FileAccess.open("res://data/heroes.json", FileAccess.READ)
	if file == null:
		print("Could not open heroes.json")
		return

	var text := file.get_as_text()
	var data = JSON.parse_string(text)

	if data == null:
		print("Could not parse heroes.json")
		return

	for hero in data:
		var row := Button.new()
		row.text = "%s | %s | %s | %s" % [
			hero.get("name", "Unknown"),
			hero.get("rarity", ""),
			hero.get("role", ""),
			hero.get("troopType", "")
		]
		list.add_child(row)
