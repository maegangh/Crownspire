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

# HUD screen navigation (GameHUD ScreenRoot sibling)
var _screen_root: Control = null
var _popup_background: ColorRect = null
var _current_screen: Control = null

func _ready() -> void:
	_load_buildings_data()
	call_deferred("_init_screen_navigation")

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

# --- HUD Screen Navigation (GameHUD ScreenRoot) ---

const HUD_CHROME_Z: int = 100
const SCREEN_ROOT_Z: int = 0
const BOTTOM_SAFE_MARGIN: float = 190.0

func _init_screen_navigation() -> void:
	var hud := get_parent()
	if hud == null:
		return

	var chrome := hud.get_node_or_null("Control") as Control
	if chrome != null:
		chrome.z_index = HUD_CHROME_Z
		chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_screen_root = hud.get_node_or_null("ScreenRoot") as Control
	if _screen_root == null:
		return

	_screen_root.z_index = SCREEN_ROOT_Z
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_popup_background = _screen_root.get_node_or_null("PopupBackground") as ColorRect
	if _popup_background != null:
		_screen_root.move_child(_popup_background, 0)
		_popup_background.color = Color(0, 0, 0, 0.45)
		# Leave bottom HUD strip uncovered so nav stays reachable even if z-order fails.
		_popup_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_popup_background.offset_bottom = -BOTTOM_SAFE_MARGIN

	_hide_all_screens()
	_set_popup_background_active(false)
	_current_screen = null


func _hide_all_screens() -> void:
	if _screen_root == null:
		return

	for child in _screen_root.get_children():
		if child == _popup_background:
			continue
		if child is Control:
			_set_screen_active(child as Control, false)


func _set_screen_active(screen: Control, active: bool) -> void:
	var was_visible: bool = screen.visible
	screen.visible = active
	# Hidden screens must never eat input.
	screen.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if not active and was_visible and screen.has_method("on_close"):
		screen.on_close()


func _set_popup_background_active(active: bool) -> void:
	if _popup_background == null:
		return

	_popup_background.visible = active
	_popup_background.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if active:
		_screen_root.move_child(_popup_background, 0)


func open_screen(screen_name: String) -> void:
	if _screen_root == null:
		_init_screen_navigation()
	if _screen_root == null:
		push_warning("[Crownspire UIManager] ScreenRoot not found; cannot open '%s'." % screen_name)
		return

	var screen := _screen_root.get_node_or_null(screen_name) as Control
	if screen == null:
		push_warning("[Crownspire UIManager] Screen not found: %s" % screen_name)
		return

	# One main screen at a time: always tear down whatever is open first.
	if _current_screen == screen:
		_set_screen_active(screen, true)
		_set_popup_background_active(true)
		_screen_root.move_child(screen, _screen_root.get_child_count() - 1)
		if screen.has_method("on_open"):
			screen.on_open()
		return

	close_current_screen()
	_hide_all_screens()

	_current_screen = screen
	_set_popup_background_active(true)
	_set_screen_active(screen, true)
	# Keep blocker behind the active screen so its buttons receive clicks.
	_screen_root.move_child(_popup_background, 0)
	_screen_root.move_child(screen, _screen_root.get_child_count() - 1)

	if screen.has_method("on_open"):
		screen.on_open()


func close_current_screen() -> void:
	if _current_screen != null:
		_set_screen_active(_current_screen, false)
		_current_screen = null

	_hide_all_screens()
	_set_popup_background_active(false)


func is_screen_open() -> bool:
	return _current_screen != null


func get_current_screen_name() -> String:
	if _current_screen == null:
		return ""
	return _current_screen.name


## Headless/runtime smoke test for one-screen navigation + close.
func run_navigation_smoke_test() -> bool:
	if _screen_root == null:
		_init_screen_navigation()
	if _screen_root == null:
		push_error("[UIManager] Smoke test failed: no ScreenRoot")
		return false

	var ok: bool = true

	open_screen("BagScreen")
	if get_current_screen_name() != "BagScreen" or not _is_only_screen_visible("BagScreen"):
		push_error("[UIManager] Smoke test failed: Bag open")
		ok = false

	open_screen("AllianceScreen")
	if get_current_screen_name() != "AllianceScreen" or not _is_only_screen_visible("AllianceScreen"):
		push_error("[UIManager] Smoke test failed: Bag→Alliance switch")
		ok = false

	open_screen("QuestScreen")
	if get_current_screen_name() != "QuestScreen" or not _is_only_screen_visible("QuestScreen"):
		push_error("[UIManager] Smoke test failed: Alliance→Quest switch")
		ok = false

	close_current_screen()
	if is_screen_open() or _popup_background.visible:
		push_error("[UIManager] Smoke test failed: Quest close")
		ok = false

	open_screen("ShopScreen")
	if get_current_screen_name() != "ShopScreen" or not _is_only_screen_visible("ShopScreen"):
		push_error("[UIManager] Smoke test failed: Shop open")
		ok = false

	close_current_screen()
	if is_screen_open() or _popup_background.visible:
		push_error("[UIManager] Smoke test failed: Shop close")
		ok = false

	open_screen("MailScreen")
	if get_current_screen_name() != "MailScreen" or not _is_only_screen_visible("MailScreen"):
		push_error("[UIManager] Smoke test failed: Mail open")
		ok = false

	close_current_screen()
	if is_screen_open() or _popup_background.visible:
		push_error("[UIManager] Smoke test failed: Mail close")
		ok = false

	open_screen("AllianceScreen")
	close_current_screen()
	if is_screen_open():
		push_error("[UIManager] Smoke test failed: Alliance close")
		ok = false

	if ok:
		print("[UIManager] HUD navigation smoke test PASSED")
	return ok


func _is_only_screen_visible(screen_name: String) -> bool:
	for child in _screen_root.get_children():
		if child == _popup_background:
			continue
		if child is Control:
			var control := child as Control
			if control.name == screen_name:
				if not control.visible:
					return false
			elif control.visible:
				return false
	return true
