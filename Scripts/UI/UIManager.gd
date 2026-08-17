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

## Phase 0B3-C: obsolete mock upgrade path. Does not spend, mutate levels, or complete buildings.
## Production upgrades: BuildingUpgradeWindow → ConstructionState only.
## HUD navigation (open_screen / close_current_screen) is unchanged.
func upgrade_building(building_id: String) -> Dictionary:
	push_warning(
		(
			"UI/UIManager.upgrade_building: obsolete mock path disabled (0B3-C); "
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

# --- HUD Screen Navigation (GameHUD ScreenRoot) ---

const HUD_CHROME_Z: int = 100
const SCREEN_ROOT_Z: int = 0
const SCREEN_ROOT_OVERLAY_Z: int = 220
const BOTTOM_SAFE_MARGIN: float = 190.0

var _overlay_name: String = ""


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
		_raise_screen_root(true)
		_notify_secondary_hud(false)
		_register_hud_screen_layer()
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
	_raise_screen_root(true)
	_notify_secondary_hud(false)
	_register_hud_screen_layer()


func request_current_screen_back() -> bool:
	if _current_screen != null and _current_screen.has_method("request_back"):
		var handled: Variant = _current_screen.call("request_back")
		if typeof(handled) == TYPE_BOOL and bool(handled):
			return true
	close_current_screen()
	return false


func _register_hud_screen_layer() -> void:
	if not has_node("/root/UiLayerStack"):
		return
	UiLayerStack.push_layer("hud_screen", request_current_screen_back, UiLayerStack.KIND_SCREEN)


func close_current_screen() -> void:
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("hud_screen")
	if _current_screen != null:
		_set_screen_active(_current_screen, false)
		_current_screen = null

	_hide_all_screens()
	_set_popup_background_active(false)
	if _overlay_name == "":
		_raise_screen_root(false)
		_notify_secondary_hud(true)


func notify_overlay_opened(overlay_name: String) -> void:
	## Full-screen overlays (Player Profile) that are not ordinary open_screen targets.
	_overlay_name = overlay_name.strip_edges()
	_raise_screen_root(true)
	_notify_secondary_hud(false)
	var hud: Node = get_parent()
	if hud != null and hud.has_method("set_gameplay_hud_visible"):
		hud.call("set_gameplay_hud_visible", false)


func notify_overlay_closed() -> void:
	if has_node("/root/UiLayerStack") and _overlay_name != "":
		UiLayerStack.remove_layer("overlay:%s" % _overlay_name)
	_overlay_name = ""
	if _current_screen == null:
		_raise_screen_root(false)
		_notify_secondary_hud(true)
		var hud: Node = get_parent()
		if hud != null and hud.has_method("set_gameplay_hud_visible"):
			hud.call("set_gameplay_hud_visible", true)


func _raise_screen_root(raised: bool) -> void:
	if _screen_root == null:
		return
	_screen_root.z_index = SCREEN_ROOT_OVERLAY_Z if raised else SCREEN_ROOT_Z


func _notify_secondary_hud(is_visible: bool) -> void:
	var hud: Node = get_parent()
	if hud != null and hud.has_method("set_secondary_hud_visible"):
		hud.set_secondary_hud_visible(is_visible)
	if hud != null and hud.has_method("set_gameplay_hud_visible") and is_visible and _overlay_name == "" and _current_screen == null:
		# Only restore full chrome when nothing is open.
		pass


func is_screen_open() -> bool:
	return _current_screen != null or _overlay_name != ""


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
	else:
		var mail: Control = _screen_root.get_node_or_null("MailScreen") as Control
		if mail != null:
			# Force layout pass so global rects match portrait viewport.
			mail.queue_redraw()
			if mail.has_method("_apply_safe_area"):
				mail.call("_apply_safe_area")
			var close_btn: Button = mail.find_child("MailCloseButton", true, false) as Button
			if close_btn == null:
				push_error("[UIManager] Smoke test failed: MailCloseButton missing")
				ok = false
			elif not close_btn.visible or close_btn.disabled:
				push_error("[UIManager] Smoke test failed: MailCloseButton not usable")
				ok = false
			else:
				# X must sit BELOW permanent top HUD (chrome z=100 covers ScreenRoot).
				var chrome: Control = get_parent().get_node_or_null("Control") as Control
				var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control if chrome else null
				var bottom_bar: Control = chrome.get_node_or_null("BottomBarTexture") as Control if chrome else null
				var close_rect: Rect2 = close_btn.get_global_rect()
				if top_bar != null:
					var top_rect: Rect2 = top_bar.get_global_rect()
					var top_bottom: float = top_rect.position.y + top_rect.size.y
					if close_rect.position.y < top_bottom:
						push_error("[UIManager] Smoke test failed: Mail X under top HUD (X.y=%.1f top_bar.bottom=%.1f)" % [
							close_rect.position.y, top_bottom
						])
						ok = false
					else:
						print("[UIManager] Mail X clear of top HUD (X.y=%.1f > top_bar.bottom=%.1f)" % [
							close_rect.position.y, top_bottom
						])
				if bottom_bar != null and mail.has_method("get_layout_debug"):
					var dbg: Dictionary = mail.call("get_layout_debug")
					var win: Rect2 = dbg.get("window", Rect2())
					var bot_top: float = bottom_bar.get_global_rect().position.y
					if win.size.y > 0.0 and (win.position.y + win.size.y) > bot_top + 1.0:
						push_error("[UIManager] Smoke test failed: Mail window overlaps bottom HUD")
						ok = false
					else:
						print("[UIManager] Mail window above bottom HUD (window.bottom=%.1f bot_top=%.1f insets t=%.1f b=%.1f)" % [
							win.position.y + win.size.y,
							bot_top,
							float(dbg.get("top_inset", 0.0)),
							float(dbg.get("bottom_inset", 0.0)),
						])
				# Header X must not live inside a ScrollContainer.
				var p: Node = close_btn.get_parent()
				while p != null and p != mail:
					if p is ScrollContainer:
						push_error("[UIManager] Smoke test failed: Mail X is inside ScrollContainer")
						ok = false
						break
					p = p.get_parent()
				close_btn.pressed.emit()
				if is_screen_open() and get_current_screen_name() == "MailScreen":
					push_error("[UIManager] Smoke test failed: Mail X did not close screen")
					ok = false
				else:
					print("[UIManager] Mail X close OK")
	# Ensure closed before continuing (idempotent if X already closed).
	if is_screen_open() and get_current_screen_name() == "MailScreen":
		close_current_screen()
	if is_screen_open() or _popup_background.visible:
		push_error("[UIManager] Smoke test failed: Mail close")
		ok = false

	# Secondary HUD (Mail) must hide while a screen is open and restore after close.
	var hud: Node = get_parent()
	if hud != null and hud.has_method("set_secondary_hud_visible"):
		open_screen("BagScreen")
		var mail_btn: Control = hud.get_node_or_null("Control/MailButton") as Control
		if mail_btn != null and mail_btn.visible:
			push_error("[UIManager] Smoke test failed: Mail still visible over Bag")
			ok = false
		close_current_screen()
		if mail_btn != null and not mail_btn.visible:
			push_error("[UIManager] Smoke test failed: Mail did not restore after Bag close")
			ok = false

	open_screen("AllianceScreen")
	close_current_screen()
	if is_screen_open():
		push_error("[UIManager] Smoke test failed: Alliance close")
		ok = false

	# Troop Training screen open/close + safe header X.
	var train: Control = _screen_root.get_node_or_null("TroopTrainingScreen") as Control
	if train == null:
		push_error("[UIManager] Smoke test failed: TroopTrainingScreen missing")
		ok = false
	elif train.has_method("open_for_building"):
		train.call("open_for_building", "Infantry", "infantry_barracks", 1)
		if get_current_screen_name() != "TroopTrainingScreen" or not _is_only_screen_visible("TroopTrainingScreen"):
			push_error("[UIManager] Smoke test failed: TroopTraining open")
			ok = false
		else:
			var close_btn: Button = train.find_child("CloseButton", true, false) as Button
			var chrome: Control = get_parent().get_node_or_null("Control") as Control
			var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control if chrome else null
			if close_btn == null or not close_btn.visible:
				push_error("[UIManager] Smoke test failed: TroopTraining CloseButton")
				ok = false
			elif top_bar != null:
				var top_bottom: float = top_bar.get_global_rect().position.y + top_bar.get_global_rect().size.y
				if close_btn.get_global_rect().position.y < top_bottom:
					push_error("[UIManager] Smoke test failed: TroopTraining X under top HUD")
					ok = false
				else:
					print("[UIManager] TroopTraining X clear of top HUD")
			close_btn.pressed.emit()
			if is_screen_open() and get_current_screen_name() == "TroopTrainingScreen":
				close_current_screen()
			if is_screen_open():
				push_error("[UIManager] Smoke test failed: TroopTraining close")
				ok = false
			else:
				print("[UIManager] TroopTraining close OK")

	# Canonical training job API + spend-before-start path (Marksmen T1).
	if has_node("/root/TroopState") and has_node("/root/TroopDatabase") and has_node("/root/GameState"):
		if TroopState.is_training_ready("Marksmen"):
			TroopState.collect_training("Marksmen")
		if not TroopState.is_training_active("Marksmen"):
			GameState.food = maxi(int(GameState.food), 50000)
			GameState.wood = maxi(int(GameState.wood), 50000)
			GameState.stone = maxi(int(GameState.stone), 50000)
			GameState.iron = maxi(int(GameState.iron), 50000)
			var cost: Dictionary = TroopDatabase.get_training_cost("marksmen", 1, 5)
			var duration: int = TroopDatabase.get_training_time("marksmen", 1, 5)
			if TroopDatabase.spend_training_cost(cost) and TroopState.start_training("Marksmen", 5, duration, 1):
				var job: Dictionary = TroopState.get_training_job("Marksmen")
				if job.is_empty() or int(job.get("quantity", 0)) != 5 or str(job.get("job_type", "")) != "train":
					push_error("[UIManager] Smoke test failed: training job API")
					ok = false
				else:
					print("[UIManager] Troop training job API OK (Marksmen T1 x5, %ds)" % duration)
					TroopState.marksmen_finish_time = int(Time.get_unix_time_from_system()) - 1
					TroopState.check_finished_training()
					var before_t1: int = TroopState.get_tier_count("Marksmen", 1)
					TroopState.collect_training("Marksmen")
					if TroopState.get_tier_count("Marksmen", 1) != before_t1 + 5:
						push_error("[UIManager] Smoke test failed: collect did not add T1 troops")
						ok = false
					else:
						print("[UIManager] Troop collect OK")
			else:
				push_error("[UIManager] Smoke test failed: could not start Marksmen training")
				ok = false

		# Promotion: seed T1, promote to T2 with cost-delta formula.
		if TroopState.has_active_job("Infantry"):
			if TroopState.is_training_ready("Infantry"):
				TroopState.collect_training("Infantry")
		if not TroopState.has_active_job("Infantry"):
			TroopState.add_tier_troops("Infantry", 1, 20)
			var before_src: int = TroopState.get_tier_count("Infantry", 1)
			var before_dst: int = TroopState.get_tier_count("Infantry", 2)
			var pcost: Dictionary = TroopDatabase.get_promotion_cost("infantry", 1, 2, 8)
			var pdur: int = TroopDatabase.get_promotion_time("infantry", 1, 2, 8)
			GameState.food = maxi(int(GameState.food), int(pcost.get("food", 0)) + 1000)
			GameState.wood = maxi(int(GameState.wood), int(pcost.get("wood", 0)) + 1000)
			if TroopDatabase.spend_training_cost(pcost) and TroopState.start_promotion("Infantry", 8, pdur, 1, 2):
				if TroopState.get_tier_count("Infantry", 1) != before_src - 8:
					push_error("[UIManager] Smoke test failed: promote did not reserve source")
					ok = false
				else:
					var pjob: Dictionary = TroopState.get_training_job("Infantry")
					if str(pjob.get("job_type", "")) != "promote":
						push_error("[UIManager] Smoke test failed: promote job_type")
						ok = false
					else:
						TroopState.infantry_finish_time = int(Time.get_unix_time_from_system()) - 1
						TroopState.check_finished_training()
						TroopState.collect_training("Infantry")
						if TroopState.get_tier_count("Infantry", 2) != before_dst + 8:
							push_error("[UIManager] Smoke test failed: promote collect target")
							ok = false
						elif TroopState.get_tier_count("Infantry", 1) != before_src - 8:
							push_error("[UIManager] Smoke test failed: promote duplicated source")
							ok = false
						else:
							print("[UIManager] Troop promote OK (T1→T2 x8, formula %s)" % TroopDatabase.PROMOTION_FORMULA_VERSION)
			else:
				push_error("[UIManager] Smoke test failed: could not start promotion")
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
