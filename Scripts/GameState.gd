extends Node

## Emitted after Food/Wood/Stone/Iron (or diamonds/power/vip) change and save.
signal resources_changed

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
var power = 0
var vip_level = 1

var ui_blocking_input: bool = false

## Phase 0B1: GameState building levels are derived mirrors of buildings.cfg authority.
const BUILDING_LEVEL_MIRROR_FIELDS := {
	"castle": "castle_level",
	"farm": "farm_level",
	"lumber_mill": "lumber_mill_level",
	"quarry": "quarry_level",
	"iron_mine": "iron_mine_level",
	"warehouse": "warehouse_level",
	"academy": "academy_level",
	"hospital": "hospital_level",
	"embassy": "embassy_level",
	"trading_post": "trading_post_level",
	"watchtower": "watchtower_level",
	"hall_of_heroes": "hall_of_heroes_level",
	"infantry_barracks": "infantry_barracks_level",
	"marksmen_camp": "marksmen_camp_level",
	"cavalry_stable": "cavalry_stable_level",
}

func _ready():
	load_resources()


## Apply verified canonical building levels into runtime mirrors (no disk write).
func apply_building_level_mirrors(levels: Dictionary) -> void:
	if levels == null or levels.is_empty():
		return
	for raw_id in levels.keys():
		var bid: String = str(raw_id).strip_edges()
		if not BUILDING_LEVEL_MIRROR_FIELDS.has(bid):
			continue
		var field: String = str(BUILDING_LEVEL_MIRROR_FIELDS[bid])
		var lv: int = maxi(1, int(levels[raw_id]))
		set(field, lv)


func snapshot_building_level_mirrors() -> Dictionary:
	var snap: Dictionary = {}
	for bid in BUILDING_LEVEL_MIRROR_FIELDS.keys():
		var field: String = str(BUILDING_LEVEL_MIRROR_FIELDS[bid])
		snap[bid] = int(get(field))
	return snap


func restore_building_level_mirrors(snap: Dictionary) -> void:
	if snap == null or snap.is_empty():
		return
	apply_building_level_mirrors(snap)

func can_afford_resources(food_cost: int, wood_cost: int, stone_cost: int, iron_cost: int) -> bool:
	return (
		food >= food_cost
		and wood >= wood_cost
		and stone >= stone_cost
		and iron >= iron_cost
	)

func add_food(amount: int):
	food += amount
	save_resources()
	resources_changed.emit()

func add_wood(amount: int):
	wood += amount
	save_resources()
	resources_changed.emit()

func add_stone(amount: int):
	stone += amount
	save_resources()
	resources_changed.emit()

func add_iron(amount: int):
	iron += amount
	save_resources()
	resources_changed.emit()

## Canonical spend for Food/Wood/Stone/Iron. Returns false if unaffordable (no change).
func spend_resources(food_cost: int, wood_cost: int, stone_cost: int, iron_cost: int) -> bool:
	if not can_afford_resources(food_cost, wood_cost, stone_cost, iron_cost):
		return false
	food -= food_cost
	wood -= wood_cost
	stone -= stone_cost
	iron -= iron_cost
	save_resources()
	resources_changed.emit()
	return true

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
		power = save.get_value("resources", "power", 0)
		vip_level = save.get_value("resources", "vip_level", 1)
		diamonds = save.get_value("resources", "diamonds", 0)
