extends Node2D

var building_scale := Vector2(0.10, 0.10)
var city_offset := Vector2(-250, 0)
var building_positions = {
	"Castle": Vector2(465, 325),

	"Academy": Vector2(310, 135),
	"ArcaneTower": Vector2(610, 135),

	"HallOfHeroes": Vector2(230, 260),
	"DragonRoost": Vector2(700, 260),

	"Hospital": Vector2(285, 385),
	"RuneForge": Vector2(635, 385),

	"Embassy": Vector2(205, 500),
	"ValorShrine": Vector2(725, 500),

	"Sanctuary": Vector2(465, 455),
	"PetDen": Vector2(465, 565),

	"Farm": Vector2(295, 620),
	"LumberMill": Vector2(390, 690),
	"Quarry": Vector2(540, 690),
	"IronMine": Vector2(635, 620),

	"InfantryBarracks": Vector2(300, 780),
	"MarksmenCamp": Vector2(465, 790),
	"CavalryStable": Vector2(630, 780),

	"MilitaryGrounds": Vector2(465, 700),

	"Warehouse": Vector2(330, 890),
	"TradingPost": Vector2(600, 890),

	"Watchtower": Vector2(205, 720),
	"Tavern": Vector2(725, 720),

	"HallOfLegends": Vector2(465, 95),
	"Wall": Vector2(465, 980)
}


func _ready():
	var buildings_node = get_node_or_null("Buildings")

	if buildings_node == null:
		print("Missing Buildings node")
		return

	for building_name in building_positions.keys():
		load_building(buildings_node, building_name)

func load_building(buildings_node: Node2D, building_name: String):
	var path := "res://assets/Buildings/" + building_name + "/"
	var dir := DirAccess.open(path)

	if dir == null:
		print("Missing folder: ", path)
		return

	dir.list_dir_begin()
	var file := dir.get_next()

	while file != "":
		if !dir.current_is_dir() and file.to_lower().ends_with(".png"):
			var sprite := Sprite2D.new()
			sprite.name = building_name
			sprite.texture = load(path + file)
			sprite.position = building_positions[building_name] + city_offset
			sprite.scale = building_scale
			buildings_node.add_child(sprite)
			print("Loaded building: ", building_name)
			break

		file = dir.get_next()

	dir.list_dir_end()
