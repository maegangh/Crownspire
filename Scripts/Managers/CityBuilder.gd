extends Node2D

var building_scale := Vector2(0.08, 0.08)

var building_positions = {
	"Castle": Vector2(600, 300),
	"Academy": Vector2(360, 220),
	"Embassy": Vector2(840, 220),
	"Farm": Vector2(280, 430),
	"LumberMill": Vector2(450, 500),
	"Quarry": Vector2(750, 500),
	"IronMine": Vector2(920, 430),
	"Hospital": Vector2(360, 360),
	"Sanctuary": Vector2(840, 360),
	"TradingPost": Vector2(500, 610),
	"Watchtower": Vector2(700, 610),
	"PetDen": Vector2(600, 470),
	"Tavern": Vector2(600, 170),
	"HallOfHeroes": Vector2(220, 290),
	"Barracks": Vector2(980, 290),
	"DragonRoost": Vector2(150, 520),
	"RuneForge": Vector2(1050, 520),
	"ArcaneTower": Vector2(150, 160),
	"ValorShrine": Vector2(1050, 160)
}

func _ready():
	for building_name in building_positions.keys():
		load_building(building_name)

func load_building(building_name):
	var path = "res://assets/Buildings/" + building_name + "/"
	var dir = DirAccess.open(path)

	if dir == null:
		print("Missing folder: ", path)
		return

	dir.list_dir_begin()
	var file = dir.get_next()

	while file != "":
		if !dir.current_is_dir() and file.to_lower().ends_with(".png"):
			var sprite = Sprite2D.new()
			sprite.texture = load(path + file)
			sprite.position = building_positions[building_name]
			sprite.scale = building_scale
			add_child(sprite)
			print("Loaded: ", building_name)
			break

		file = dir.get_next()

	dir.list_dir_end()
