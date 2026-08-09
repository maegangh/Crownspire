extends SceneTree

## Resource-locked quantity defaults + slider max.
##   Godot --headless --path <project> -s res://Scripts/dev/troop_training_resource_lock_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i(417, 742)
	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[RES LOCK] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var screen: Control = hud.get_node_or_null("ScreenRoot/TroopTrainingScreen") as Control
	var gs: Node = root.get_node("/root/GameState")
	var db: Node = root.get_node("/root/TroopDatabase")
	var ts: Node = root.get_node("/root/TroopState")
	if screen == null:
		push_error("[RES LOCK] screen missing")
		quit(1)
		return

	_clear_jobs(ts)

	# --- TEST A: resource-limited ---
	# Building level 19 → capacity = 100 + 18*50 = 1000. Pin T1 for stable costs.
	screen.call("open_for_building", "Infantry", "infantry_barracks", 19)
	await process_frame
	screen.set("_selected_tier", 1)
	screen.set("_mode", "train")
	var unit: Dictionary = db.call("get_training_cost", "infantry", 1, 1)
	var food_u: int = maxi(1, int(unit.get("food", 1)))
	var wood_u: int = maxi(0, int(unit.get("wood", 0)))
	var stone_u: int = maxi(0, int(unit.get("stone", 0)))
	var iron_u: int = maxi(0, int(unit.get("iron", 0)))
	# Afford exactly 637 on every resource that costs.
	gs.set("food", food_u * 637)
	gs.set("wood", (wood_u * 637) if wood_u > 0 else 50_000_000)
	gs.set("stone", (stone_u * 637) if stone_u > 0 else 50_000_000)
	gs.set("iron", (iron_u * 637) if iron_u > 0 else 50_000_000)
	screen.call("_select_default_amount")
	screen.call("_refresh_idle_summary")
	await process_frame

	var cap: int = int(screen.call("_capacity_max"))
	var aff: int = int(screen.call("_affordable_max"))
	var eff: int = int(screen.call("_max_for_mode"))
	var amt: int = int(screen.get("_amount"))
	var slider: HSlider = screen.find_child("QuantitySlider", true, false) as HSlider
	var lock: CanvasItem = screen.find_child("QtyResourceLock", true, false) as CanvasItem
	var limits: Label = screen.find_child("QtyLimitsLabel", true, false) as Label

	print("[RES LOCK] A cap=", cap, " aff=", aff, " eff=", eff, " amt=", amt, " unit=", unit)
	_assert(cap == 1000, "A capacity should be 1000 (got %d)" % cap)
	_assert(aff == 637, "A affordable should be 637 (got %d)" % aff)
	_assert(eff == 637, "A effective max 637")
	_assert(amt == 637, "A Selected default 637")
	_assert(slider != null and int(slider.max_value) == 637, "A slider max 637")
	_assert(lock != null and lock.visible, "A resource lock visible")
	_assert(limits != null and limits.text.find("1000") >= 0 and limits.text.find("637") >= 0, "A limits label")
	screen.call("_adjust_amount", 1)
	await process_frame
	_assert(int(screen.get("_amount")) == 637, "A + at max cannot increase")

	# --- TEST B: capacity-limited ---
	gs.set("food", 50_000_000)
	gs.set("wood", 50_000_000)
	gs.set("stone", 50_000_000)
	gs.set("iron", 50_000_000)
	screen.call("open_for_building", "Marksmen", "marksmen_camp", 19)
	await process_frame
	await process_frame
	cap = int(screen.call("_capacity_max"))
	aff = int(screen.call("_affordable_max"))
	eff = int(screen.call("_max_for_mode"))
	amt = int(screen.get("_amount"))
	lock = screen.find_child("QtyResourceLock", true, false) as CanvasItem
	print("[RES LOCK] B cap=", cap, " aff=", aff, " eff=", eff, " amt=", amt)
	_assert(cap == 1000, "B capacity 1000")
	_assert(aff >= 1000, "B affordable >= capacity")
	_assert(eff == 1000, "B effective = capacity")
	_assert(amt == 1000, "B Selected = 1000")
	_assert(lock != null and not lock.visible, "B no resource lock")

	# --- TEST C: zero affordable ---
	gs.set("food", 0)
	gs.set("wood", 0)
	gs.set("stone", 0)
	gs.set("iron", 0)
	screen.call("open_for_building", "Cavalry", "cavalry_stable", 19)
	await process_frame
	await process_frame
	amt = int(screen.get("_amount"))
	eff = int(screen.call("_max_for_mode"))
	slider = screen.find_child("QuantitySlider", true, false) as HSlider
	var action: Button = screen.find_child("ActionButton", true, false) as Button
	var status: Label = null
	for l: Node in screen.find_children("*", "Label", true, false):
		if l is Label and str((l as Label).text).find("Not enough resources") >= 0:
			status = l as Label
			break
	print("[RES LOCK] C amt=", amt, " eff=", eff)
	_assert(amt == 0 and eff == 0, "C Selected 0 / max 0")
	_assert(slider != null and not slider.editable, "C slider disabled")
	_assert(action != null and action.disabled, "C Train disabled")
	_assert(status != null, "C insufficient resources message")

	# --- TEST D: promotion ---
	gs.set("food", 50_000_000)
	gs.set("wood", 50_000_000)
	gs.set("stone", 50_000_000)
	gs.set("iron", 50_000_000)
	# Level 9 → capacity 500
	_clear_jobs(ts)
	ts.call("add_tier_troops", "Infantry", 1, 300)
	# Constrain promotion affordability to 225 via food delta cost
	screen.call("open_for_building", "Infantry", "infantry_barracks", 9)
	await process_frame
	screen.call("_set_mode", "promote")
	await process_frame
	# Pick highest unlocked as target; ensure source T1
	screen.set("_source_tier", 1)
	screen.set("_selected_tier", maxi(2, int(screen.get("_selected_tier"))))
	var punit: Dictionary = db.call("get_promotion_cost", "infantry", 1, int(screen.get("_selected_tier")), 1)
	var pfood: int = int(punit.get("food", 0))
	if pfood <= 0:
		# Free promote cost — force resource lock via zeroing and skip amount assert shape
		print("[RES LOCK] D free promo cost — using owned/capacity only")
		screen.call("_select_default_amount")
		await process_frame
		eff = int(screen.call("_max_for_mode"))
		_assert(eff == 300, "D effective = owned 300 when promo free (cap 500)")
		_assert(int(screen.get("_amount")) == 300, "D selected 300")
	else:
		gs.set("food", pfood * 225)
		screen.call("_select_default_amount")
		await process_frame
		cap = int(screen.call("_capacity_max"))
		aff = int(screen.call("_affordable_max"))
		eff = int(screen.call("_max_for_mode"))
		amt = int(screen.get("_amount"))
		print("[RES LOCK] D cap=", cap, " aff=", aff, " eff=", eff, " amt=", amt)
		_assert(cap == 500, "D capacity 500")
		_assert(aff == 225, "D affordable 225")
		_assert(eff == 225, "D effective 225")
		_assert(amt == 225, "D Selected 225")

	# Spot-check all three types open with default = effective max
	gs.set("food", 50_000_000)
	gs.set("wood", 50_000_000)
	gs.set("stone", 50_000_000)
	gs.set("iron", 50_000_000)
	for troop: String in ["Infantry", "Marksmen", "Cavalry"]:
		_clear_jobs(ts)
		screen.call("open_for_building", troop, "", 5)
		await process_frame
		_assert(int(screen.get("_amount")) == int(screen.call("_max_for_mode")), "%s default=max" % troop)
		_assert(int(screen.call("_max_for_mode")) <= int(screen.call("_capacity_max")), "%s eff<=cap" % troop)

	if _fail.is_empty():
		print("[RES LOCK] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[RES LOCK] FAIL: %s" % f)
		quit(1)


func _clear_jobs(ts: Node) -> void:
	for troop: String in ["Infantry", "Marksmen", "Cavalry"]:
		if ts.has_method("_clear_job"):
			ts.call("_clear_job", troop)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
