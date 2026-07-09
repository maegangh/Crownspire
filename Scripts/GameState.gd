extends Node

var castle_level = 1

var food = 1000
var wood = 1000
var stone = 1000
var iron = 1000

var farm_level = 1
var lumber_mill_level = 1
var quarry_level = 1
var iron_mine_level = 1

var warehouse_level = 1
var academy_level = 1
var hospital_level = 1
var embassy_level = 1
var trading_post_level = 1
var watchtower_level = 1
var hall_of_heroes_level = 1

var infantry_barracks_level = 1
var marksmen_camp_level = 1
var cavalry_stable_level = 1
var popup_open: bool = false
var diamonds = 0
var power = 1614990
var vip_level = 1

var ui_blocking_input: bool = false

func _ready():
	load_resources()

func add_food(amount: int):
	food += amount
	save_resources()

func add_wood(amount: int):
	wood += amount
	save_resources()

func add_stone(amount: int):
	stone += amount
	save_resources()

func add_iron(amount: int):
	iron += amount
	save_resources()

func spend_resources(food_cost: int, wood_cost: int, stone_cost: int, iron_cost: int):
	food -= food_cost
	wood -= wood_cost
	stone -= stone_cost
	iron -= iron_cost
	save_resources()

func save_resources():
	var save = ConfigFile.new()
	save.load("user://resources.cfg")
	save.set_value("resources", "food", food)
	save.set_value("resources", "wood", wood)
	save.set_value("resources", "stone", stone)
	save.set_value("resources", "iron", iron)
	save.set_value("resources", "diamonds", diamonds)
	save.set_value("resources", "power", power)
	save.set_value("resources", "vip_level", vip_level)
	save.save("user://resources.cfg")

func load_resources():
	var save = ConfigFile.new()
	if save.load("user://resources.cfg") == OK:
		food = save.get_value("resources", "food", 1000)
		wood = save.get_value("resources", "wood", 1000)
		stone = save.get_value("resources", "stone", 1000)
		iron = save.get_value("resources", "iron", 1000)
		power = save.get_value("resources", "power", 1614990)
		vip_level = save.get_value("resources", "vip_level", 1)
		diamonds = save.get_value("resources", "diamonds", 0)
