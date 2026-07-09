extends Node

# Minimal production-safe UIManager for Crownspire Godot 4.6+
# Handles live building databases, player currency registers, and fallback window actions safely.

signal currency_changed(currency_id: String, new_amount: float)

# Player Resources (Reactive states)
var food: int = 500000
var wood: int = 600000
var stone: int = 350000
var iron: int = 150000
var gold: int = 100000
var royal_crystals: int = 2500

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
			"name": "Crystal Citadels",
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

func upgrade_building(building_id: String) -> Dictionary:
	var b = get_building(building_id)
	if b.is_empty():
		return {"success": false, "error": "Building not found"}
	
	var lvl = int(b.get("level", 1))
	var max_lvl = int(b.get("max_level", 30))
	if lvl >= max_lvl:
		return {"success": false, "error": "Max level reached"}
	
	# Calculate structural costs
	var reqs = b.get("resources_required", {})
	var multiplier = 1.0 + lvl * 0.15
	
	# Verify and deduct
	for res in reqs.keys():
		var cost = int(reqs[res] * multiplier)
		var current_val = get(res)
		if current_val < cost:
			return {"success": false, "error": "Insufficient " + res}
	
	# Deduct costs
	for res in reqs.keys():
		var cost = int(reqs[res] * multiplier)
		set(res, get(res) - cost)
		currency_changed.emit(res, float(get(res)))
		
	# Upgrade level
	b["level"] = lvl + 1
	print("[Crownspire UIManager] Upgraded %s to level %d!" % [building_id, lvl + 1])
	return {"success": true}

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
