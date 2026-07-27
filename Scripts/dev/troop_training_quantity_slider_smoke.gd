extends SceneTree

## Troop training quantity slider: whole-number HSlider + ±1 for all three buildings.
##   Godot --headless --path <project> -s res://scripts/dev/troop_training_quantity_slider_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i(417, 742)
	DisplayServer.window_set_size(Vector2i(417, 742))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[QTY SLIDER] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var screen: Control = hud.get_node_or_null("ScreenRoot/TroopTrainingScreen") as Control if hud else null
	var gs: Node = root.get_node_or_null("/root/GameState")
	var db: Node = root.get_node_or_null("/root/TroopDatabase")
	var ts: Node = root.get_node_or_null("/root/TroopState")
	if screen == null or gs == null or db == null or ts == null:
		push_error("[QTY SLIDER] missing nodes")
		quit(1)
		return

	# Plenty of resources so max is capacity-bound for clean asserts.
	gs.set("food", 50_000_000)
	gs.set("wood", 50_000_000)
	gs.set("stone", 50_000_000)
	gs.set("iron", 50_000_000)
	_clear_all_jobs(ts)

	for troop: String in ["Infantry", "Marksmen", "Cavalry"]:
		await _exercise_troop(screen, db, ts, troop)
		_clear_all_jobs(ts)
		await process_frame

	# Promotion path (Infantry): seed lower-tier troops.
	ts.call("add_tier_troops", "Infantry", 1, 80)
	await process_frame
	screen.call("open_for_building", "Infantry", "infantry_barracks", 5)
	await process_frame
	await process_frame
	screen.call("_set_mode", "promote")
	await process_frame
	var slider: HSlider = screen.find_child("QuantitySlider", true, false) as HSlider
	_assert(slider != null and slider.visible, "promote slider missing")
	var max_p: int = int(screen.call("_max_for_mode"))
	_assert(max_p > 0, "promote max should be > 0 with seeded troops")
	slider.value = mini(17, max_p)
	await process_frame
	_assert(int(screen.get("_amount")) == mini(17, max_p), "promote slider amount")
	print("[QTY SLIDER] promote max=", max_p, " amount=", screen.get("_amount"))

	if _fail.is_empty():
		print("[QTY SLIDER] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[QTY SLIDER] FAIL: %s" % f)
		quit(1)


func _exercise_troop(screen: Control, db: Node, ts: Node, troop: String) -> void:
	print("[QTY SLIDER] --- ", troop, " ---")
	_clear_all_jobs(ts)
	gs_boost()
	screen.call("open_for_building", troop, "", 3)
	await process_frame
	await process_frame
	# Ensure idle surface after any leftover job UI.
	if not bool((screen.find_child("IdleBlock", true, false) as CanvasItem).visible if screen.find_child("IdleBlock", true, false) else false):
		_clear_all_jobs(ts)
		screen.call("_refresh_view")
		await process_frame

	_assert(bool(screen.visible), "%s screen not visible" % troop)

	var idle: CanvasItem = screen.find_child("IdleBlock", true, false) as CanvasItem
	_assert(idle != null and idle.visible, "%s IdleBlock not visible" % troop)

	var slider: HSlider = screen.find_child("QuantitySlider", true, false) as HSlider
	var minus: Button = screen.find_child("QtyMinus", true, false) as Button
	var plus: Button = screen.find_child("QtyPlus", true, false) as Button
	var selected: Label = null
	for l: Node in screen.find_children("*", "Label", true, false):
		if l is Label and str((l as Label).text).begins_with("Selected:"):
			selected = l as Label
			break
	_assert(slider != null, "%s QuantitySlider missing" % troop)
	_assert(minus != null and plus != null, "%s ± buttons missing" % troop)
	_assert(selected != null, "%s Selected label missing" % troop)
	_assert(absf(slider.step - 1.0) < 0.001, "%s slider step must be 1" % troop)

	var max_qty: int = int(screen.call("_max_for_mode"))
	var cap: int = int(screen.call("_capacity"))
	print("[QTY SLIDER] ", troop, " max=", max_qty, " capacity=", cap, " default_amount=", screen.get("_amount"))
	_assert(max_qty > 0, "%s max_qty=0" % troop)
	_assert(max_qty <= cap, "%s max exceeds capacity" % troop)
	_assert(int(screen.get("_amount")) == max_qty, "%s default should be affordable max" % troop)

	# Drag to 1
	slider.value = 1
	await process_frame
	_assert(int(screen.get("_amount")) == 1, "%s amount after drag 1" % troop)
	_assert(selected.text.contains("1") or selected.text.ends_with("1"), "%s Selected label" % troop)

	# Non-round 137 (or max if smaller)
	var target: int = mini(137, max_qty)
	slider.value = float(target)
	await process_frame
	_assert(int(screen.get("_amount")) == target, "%s amount %d" % [troop, target])

	if target < max_qty:
		plus.pressed.emit()
		await process_frame
		_assert(int(screen.get("_amount")) == target + 1, "%s +1" % troop)
		minus.pressed.emit()
		await process_frame
		_assert(int(screen.get("_amount")) == target, "%s -1" % troop)

	# Max
	slider.value = float(max_qty)
	await process_frame
	_assert(int(screen.get("_amount")) == max_qty, "%s drag max" % troop)
	_assert(int(screen.get("_amount")) <= cap, "%s exceeds capacity" % troop)

	# Live cost/time from TroopDatabase
	var amt: int = int(screen.get("_amount"))
	var tier: int = int(screen.get("_selected_tier"))
	var cost: Dictionary = db.call("get_training_cost", troop.to_lower(), tier, amt)
	var tsec: int = int(db.call("get_training_time", troop.to_lower(), tier, amt))
	var cost_label: Label = null
	for l2: Node in screen.find_children("*", "Label", true, false):
		if l2 is Label and str((l2 as Label).text).begins_with("Cost"):
			cost_label = l2 as Label
			break
	_assert(cost_label != null and cost_label.text.find("Food") >= 0, "%s cost lines" % troop)
	_assert(tsec > 0, "%s training time" % troop)

	# Start training with a modest amount and verify queue quantity.
	var queue_amt: int = mini(13, max_qty)
	slider.value = float(queue_amt)
	await process_frame
	var action: Button = screen.find_child("ActionButton", true, false) as Button
	_assert(action != null and not action.disabled, "%s Train disabled" % troop)
	action.pressed.emit()
	await process_frame
	await process_frame
	_assert(bool(ts.call("is_training_active", troop)) or bool(ts.call("is_training_ready", troop)), "%s job not started" % troop)
	var job: Dictionary = ts.call("get_training_job", troop)
	_assert(int(job.get("quantity", -1)) == queue_amt, "%s queued qty=%s expected %d" % [troop, str(job.get("quantity")), queue_amt])

	# Active job: idle/slider hidden
	var slider_after: HSlider = screen.find_child("QuantitySlider", true, false) as HSlider
	var idle_visible: bool = false
	if slider_after != null:
		var p: Node = slider_after.get_parent()
		while p != null:
			if p.name == "IdleBlock" or (p is VBoxContainer and p.get_parent() != null):
				# Walk up to idle block via visibility of slider's ancestor that toggles with job.
				break
			p = p.get_parent()
	# After start, idle_block is hidden — QuantityRow should not be visible_in_tree for input.
	_assert(slider_after == null or not slider_after.is_visible_in_tree(), "%s slider still visible during job" % troop)
	var speed: Button = screen.find_child("SpeedUpButton", true, false) as Button
	_assert(speed != null and speed.visible, "%s SPEED UP missing" % troop)

	# Collect / clear job for next troop type (force-complete).
	if ts.has_method("debug_force_complete_training"):
		ts.call("debug_force_complete_training", troop)
	else:
		# Spend remaining time via speedup API or direct finish fields.
		_force_finish_job(ts, troop)
	await process_frame
	var collect: Button = screen.find_child("CollectButton", true, false) as Button
	if collect != null and collect.visible:
		collect.pressed.emit()
		await process_frame
	# Ensure clean for next type
	if bool(ts.call("has_active_job", troop)):
		_force_finish_job(ts, troop)
		await process_frame
		if collect != null:
			if screen.has_method("_on_collect_pressed"):
				screen.call("_on_collect_pressed")
			elif collect.visible:
				collect.pressed.emit()
		await process_frame


func _force_finish_job(ts: Node, troop: String) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	match troop:
		"Infantry":
			ts.set("infantry_finish_time", now - 1)
		"Marksmen":
			ts.set("marksmen_finish_time", now - 1)
		"Cavalry":
			ts.set("cavalry_finish_time", now - 1)
	if ts.has_method("check_finished_training"):
		ts.call("check_finished_training")


func _clear_all_jobs(ts: Node) -> void:
	for troop: String in ["Infantry", "Marksmen", "Cavalry"]:
		if ts.has_method("_clear_job"):
			ts.call("_clear_job", troop)
	if ts.has_method("save_troops"):
		ts.call("save_troops")
	if ts.has_signal("training_updated"):
		ts.emit_signal("training_updated")


func gs_boost() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.set("food", 50_000_000)
	gs.set("wood", 50_000_000)
	gs.set("stone", 50_000_000)
	gs.set("iron", 50_000_000)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
