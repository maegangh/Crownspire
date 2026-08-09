extends SceneTree

## Headless smoke: Wall Defense picker must not free locked Buttons mid-pressed.
## Run:
##   Godot --headless --path <project> -s res://Scripts/dev/wall_defense_picker_refresh_smoke.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: int = 0
	var hs: Node = root.get_node_or_null("/root/HeroState")
	if hs == null:
		push_error("[WALL DEF SMOKE] HeroState autoload missing")
		quit(1)
		return

	var owned: Dictionary = hs.call("get_owned_hero", "maegan") as Dictionary
	if owned.is_empty():
		hs.call("grant_starter_maegan")

	var screen: Control = (load("res://Scripts/UI/WallDefenseScreen.gd") as GDScript).new() as Control
	root.add_child(screen)
	await process_frame
	screen.call("on_open")
	await process_frame

	screen.set("_editing", true)
	screen.set("_draft_ids", [])
	screen.call("_refresh")
	await process_frame

	var picker: VBoxContainer = screen.get("_picker_list") as VBoxContainer
	if picker == null:
		push_error("[WALL DEF SMOKE] picker missing")
		quit(1)
		return

	var assign_btn: Button = null
	for child: Node in picker.get_children():
		if child is Button and not (child as Button).disabled:
			assign_btn = child as Button
			break
	if assign_btn == null:
		push_error("[WALL DEF SMOKE] no assignable picker button")
		failed += 1
	else:
		# Previously crashed: pressed → assign → sync refresh → free() emitting Button.
		assign_btn.emit_signal("pressed")
		await process_frame
		await process_frame
		var draft: Array = screen.get("_draft_ids") as Array
		if draft.is_empty():
			push_error("[WALL DEF SMOKE] assign did not update draft")
			failed += 1
		else:
			print("[WALL DEF SMOKE] assign OK draft=%s" % str(draft))

		screen.call("_on_slot_pressed", 0)
		await process_frame
		await process_frame
		draft = screen.get("_draft_ids") as Array
		if not draft.is_empty():
			push_error("[WALL DEF SMOKE] remove did not clear draft")
			failed += 1
		else:
			print("[WALL DEF SMOKE] remove OK")

	for _i: int in range(5):
		screen.call("_request_refresh")
	if not bool(screen.get("_refresh_pending")):
		push_error("[WALL DEF SMOKE] refresh_pending should be true")
		failed += 1
	await process_frame
	if bool(screen.get("_refresh_pending")):
		push_error("[WALL DEF SMOKE] refresh_pending stuck")
		failed += 1
	else:
		print("[WALL DEF SMOKE] coalesce OK")

	var before: Array = hs.call("get_wall_defender_ids") as Array
	var save_res: Dictionary = hs.call("set_wall_defenders", ["maegan"]) as Dictionary
	if bool(save_res.get("ok", false)):
		var after_set: Array = hs.call("get_wall_defender_ids") as Array
		if "maegan" not in after_set:
			push_error("[WALL DEF SMOKE] save did not stick in memory")
			failed += 1
		elif bool(hs.call("is_hero_available_for_march", "maegan")):
			push_error("[WALL DEF SMOKE] wall hero still available for march")
			failed += 1
		else:
			print("[WALL DEF SMOKE] save + march unavailable OK")
		var restore: Array = []
		for v: Variant in before:
			restore.append(str(v))
		hs.call("set_wall_defenders", restore)
		if not bool(hs.call("is_hero_wall_defender", "maegan")):
			if bool(hs.call("is_hero_on_march", "maegan")):
				print("[WALL DEF SMOKE] march restore soft-skip (on march)")
			elif not bool(hs.call("is_hero_available_for_march", "maegan")):
				push_error("[WALL DEF SMOKE] march availability not restored")
				failed += 1
			else:
				print("[WALL DEF SMOKE] march available again OK")
		else:
			print("[WALL DEF SMOKE] prior wall assignment restored")
	else:
		print("[WALL DEF SMOKE] set_wall_defenders skipped: %s" % str(save_res.get("error", "")))

	if failed == 0:
		print("[WALL DEF SMOKE] PASSED")
		quit(0)
	else:
		push_error("[WALL DEF SMOKE] FAILED (%d)" % failed)
		quit(1)
