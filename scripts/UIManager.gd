extends Node

# Minimal production-safe UIManager for Crownspire Godot 4.6+
# Handles live building databases, player currency registers, and fallback window actions safely.

signal currency_changed(currency_id: String, new_amount: float)

# Player Resources (Reactive states)
var food: int = 45600
var wood: int = 202000
var stone: int = 27000
var iron: int = 7700
var royal_crystals: int = 3200

# Building data cache
var _buildings_cache: Array = []

func _ready() -> void:
	_load_buildings_data()

# Dynamic loader for buildings database
func _load_buildings_data() -> void:
	var path = "res://data/buildings.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data = json.get_data()
				if data is Array:
					_buildings_cache = data
					print("[Crownspire UIManager] Successfully loaded buildings database.")
					return
	
	# Fail-safe mock data matching standard scheme if file missing
	_buildings_cache = [
		{
			"id": "citadel",
			"name": "Crystal Citadel",
			"level": 1,
			"max_level": 30,
			"base_power": 10000,
			"power_per_level": 2500,
			"resources_required": {"food": 50000, "wood": 60000, "stone": 30000, "iron": 10000},
			"upgrade_time_seconds": 300,
			"current_bonus": "Max Troop Tier: I",
			"next_bonus": "Max Troop Tier: II"
		},
		{
			"id": "farm",
			"name": "Imperial Wheatlands",
			"level": 1,
			"max_level": 30,
			"base_power": 1000,
			"power_per_level": 200,
			"resources_required": {"food": 10000, "wood": 15000, "stone": 5000},
			"upgrade_time_seconds": 120,
			"current_bonus": "1.5K Food / Hour",
			"next_bonus": "2.2K Food / Hour"
		}
	]
	print("[Crownspire UIManager] Fallback buildings loaded.")

# --- Core Building API ---

func get_building(building_id: String) -> Dictionary:
	for b in _buildings_cache:
		if b is Dictionary and b.get("id", "") == building_id:
			return b
	return {}

## Phase 0B3-C: obsolete mock upgrade path. Does not spend, mutate levels, or complete buildings.
## Production upgrades: BuildingUpgradeWindow → ConstructionState only.
func upgrade_building(building_id: String) -> Dictionary:
	push_warning(
		(
			"UIManager.upgrade_building: obsolete mock path disabled (0B3-C); "
			+ "refusing spend/level mutation for building_id=%s. Use BuildingUpgradeWindow."
		) % building_id
	)
	return {"success": false, "error": "Obsolete mock upgrade path disabled (0B3-C)"}

func close_popup(popup_node: Node) -> void:
	if is_instance_valid(popup_node):
		popup_node.queue_free()
		print("[Crownspire UIManager] Popup closed safely.")

# --- Required Behavior and Helper Methods (Godot 4.6 compliant) ---

func show_toast(message: String) -> void:
	print("[Crownspire UIManager - TOAST] %s" % message)

func open_shop() -> void:
	print("[Crownspire UIManager] Opening Royal Treasury Shop.")

func open_building(building_id: String) -> void:
	print("[Crownspire UIManager] Opening window for building: %s" % building_id)

func close_window(window: Node) -> void:
	if is_instance_valid(window):
		window.queue_free()
		print("[Crownspire UIManager] Window closed.")

func open_window(window: Node) -> void:
	if is_instance_valid(window):
		print("[Crownspire UIManager] Displaying window: %s" % window.name)

func show_success(message: String) -> void:
	print("[Crownspire UIManager - SUCCESS] %s" % message)

func show_error(message: String) -> void:
	print("[Crownspire UIManager - ERROR] %s" % message)
