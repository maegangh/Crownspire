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
	call_deferred("_bind_power_recalc_signals")
	call_deferred("recalculate_player_power")


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


## Deterministic kingdom Power from authoritative progression.
## `power` is a cache only — never trust persisted power alone after restore.
func recalculate_player_power(persist: bool = true) -> int:
	var buildings_power: int = _calc_buildings_power()
	var troops_power: int = _calc_troops_power()
	# Heroes: excluded — no data-backed kingdom power; get_hero_display_power is UI-only.
	# Research: no powerGained in research data yet — excluded.
	var total: int = buildings_power + troops_power
	power = total
	if persist:
		save_resources()
	resources_changed.emit()
	return total


func get_player_power() -> int:
	return int(power)


func _bind_power_recalc_signals() -> void:
	var cs: Node = get_node_or_null("/root/ConstructionState")
	if cs != null and cs.has_signal("construction_completed"):
		if not cs.construction_completed.is_connected(_on_power_progression_event):
			cs.construction_completed.connect(_on_power_progression_event)
	var ts: Node = get_node_or_null("/root/TroopState")
	if ts != null and ts.has_signal("training_updated"):
		if not ts.training_updated.is_connected(_on_power_progression_event):
			ts.training_updated.connect(_on_power_progression_event)
	var ms: Node = get_node_or_null("/root/MarchState")
	if ms != null and ms.has_signal("marches_changed"):
		if not ms.marches_changed.is_connected(_on_power_progression_event):
			ms.marches_changed.connect(_on_power_progression_event)
	var ge: Node = get_node_or_null("/root/GameEvents")
	if ge != null and ge.has_signal("building_upgraded"):
		if not ge.building_upgraded.is_connected(_on_power_building_upgraded):
			ge.building_upgraded.connect(_on_power_building_upgraded)
	if ge != null and ge.has_signal("troop_training_completed"):
		if not ge.troop_training_completed.is_connected(_on_power_troop_training_completed):
			ge.troop_training_completed.connect(_on_power_troop_training_completed)


func _on_power_progression_event(_a = null, _b = null, _c = null) -> void:
	recalculate_player_power(true)


func _on_power_building_upgraded(_building_id: String, _new_level: int) -> void:
	recalculate_player_power(true)


func _on_power_troop_training_completed(_troop_type: String, _tier: int, _amount: int) -> void:
	recalculate_player_power(true)


## buildings.json powerGained = cumulative total power of that building AT its current level
## (not incremental). Description: "adding N overall power to your Citadel realm."
func _calc_buildings_power() -> int:
	var total: int = 0
	var cs: Node = get_node_or_null("/root/ConstructionState")
	var dm: Node = get_node_or_null("/root/DataManager")
	if cs == null or dm == null or not dm.has_method("get_building_power_gain"):
		return 0
	var ids: PackedStringArray = PackedStringArray()
	if cs.has_method("get_known_building_ids"):
		ids = cs.call("get_known_building_ids")
	for bid_v: Variant in ids:
		var bid: String = str(bid_v)
		var level: int = 1
		if cs.has_method("get_canonical_building_level"):
			level = int(cs.call("get_canonical_building_level", bid))
		if level < 1:
			continue
		total += int(dm.call("get_building_power_gain", bid, level))
	return total


## Owned troop power = home + wounded + sanctuary + active marches (no double-count).
## Training-in-progress is excluded until collect grants ownership.
func _calc_troops_power() -> int:
	var total: int = 0
	var ts: Node = get_node_or_null("/root/TroopState")
	var db: Node = get_node_or_null("/root/TroopDatabase")
	if ts == null or db == null or not db.has_method("get_power_gain"):
		return 0
	for troop_class: String in ["Infantry", "Marksmen", "Cavalry"]:
		for tier: int in range(1, 13):
			var home: int = 0
			if ts.has_method("get_tier_count"):
				home = int(ts.call("get_tier_count", troop_class, tier))
			if home > 0:
				total += int(db.call("get_power_gain", troop_class, tier, home))
	# Wounded + sanctuary still belong to the player.
	total += _troop_power_from_tier_maps(ts, db, "get_wounded_by_tiers")
	total += _troop_power_from_tier_maps(ts, db, "get_sanctuary_by_tiers")
	# Marching troops were removed from home pools — still count toward kingdom Power.
	var ms: Node = get_node_or_null("/root/MarchState")
	if ms != null and ms.has_method("get_active_marches"):
		var marches: Array = ms.call("get_active_marches")
		for m_v: Variant in marches:
			if typeof(m_v) != TYPE_DICTIONARY:
				continue
			var march: Dictionary = m_v
			var comp: Dictionary = march.get("troop_tiers", {}) as Dictionary
			if typeof(comp) != TYPE_DICTIONARY:
				continue
			total += _troop_power_from_composition(db, comp)
	return total


func _troop_power_from_tier_maps(ts: Node, db: Node, method_name: String) -> int:
	if not ts.has_method(method_name):
		return 0
	var maps: Dictionary = ts.call(method_name)
	return _troop_power_from_composition(db, maps)


func _troop_power_from_composition(db: Node, composition: Dictionary) -> int:
	var total: int = 0
	var map_names := {
		"infantry": "Infantry",
		"marksmen": "Marksmen",
		"cavalry": "Cavalry",
		"Infantry": "Infantry",
		"Marksmen": "Marksmen",
		"Cavalry": "Cavalry",
	}
	for key: Variant in composition.keys():
		var class_key: String = str(key)
		var display: String = str(map_names.get(class_key, class_key.capitalize()))
		var by_tier: Variant = composition[key]
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		for tk: Variant in (by_tier as Dictionary).keys():
			var amt: int = int((by_tier as Dictionary)[tk])
			var tier: int = int(tk)
			if amt > 0 and tier > 0:
				total += int(db.call("get_power_gain", display, tier, amt))
	return total


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
	var path: String = get_resources_path()
	var save = ConfigFile.new()
	save.load(path)
	save.set_value("resources", "food", food)
	save.set_value("resources", "wood", wood)
	save.set_value("resources", "stone", stone)
	save.set_value("resources", "iron", iron)
	save.set_value("resources", "diamonds", diamonds)
	save.set_value("resources", "power", power)
	save.set_value("resources", "vip_level", vip_level)
	save.save(path)
	if has_node("/root/AccountCloudSave"):
		AccountCloudSave.mark_dirty("resources")

func load_resources():
	var save = ConfigFile.new()
	if save.load(get_resources_path()) == OK:
		food = save.get_value("resources", "food", 1000)
		wood = save.get_value("resources", "wood", 1000)
		stone = save.get_value("resources", "stone", 1000)
		iron = save.get_value("resources", "iron", 1000)
		# Stale cache only — recalculate_player_power() is authoritative after load/restore.
		power = save.get_value("resources", "power", 0)
		vip_level = save.get_value("resources", "vip_level", 1)
		diamonds = save.get_value("resources", "diamonds", 0)


func get_resources_path() -> String:
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("resources.cfg")
	return "user://resources.cfg"
