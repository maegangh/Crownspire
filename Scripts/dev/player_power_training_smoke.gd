extends SceneTree

## Power recalculation + normalized training-time regression smoke.
##   Godot --headless --path <project> -s res://Scripts/dev/player_power_training_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame

	var gs: Node = root.get_node_or_null("/root/GameState")
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	var ts: Node = root.get_node_or_null("/root/TroopState")
	var db: Node = root.get_node_or_null("/root/TroopDatabase")
	var dm: Node = root.get_node_or_null("/root/DataManager")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if gs == null or cs == null or ts == null or db == null or dm == null:
		push_error("[POWER/TRAIN] ABORT — required autoloads missing")
		quit(2)
		return

	print("[POWER/TRAIN] A trainingTimeSec normalized across classes")
	for tier: int in [1, 5, 12]:
		var inf: int = int(db.call("get_training_time", "Infantry", tier, 100))
		var mrk: int = int(db.call("get_training_time", "Marksmen", tier, 100))
		var cav: int = int(db.call("get_training_time", "Cavalry", tier, 100))
		_assert(inf == mrk and mrk == cav, "A: T%d 100-qty mismatch inf=%d mrk=%d cav=%d" % [tier, inf, mrk, cav])
	var t1: int = int(db.call("get_training_time", "Infantry", 1, 100))
	var t5: int = int(db.call("get_training_time", "Infantry", 5, 100))
	_assert(t1 == 400, "A: T1×100 expected 400 got %d" % t1)
	_assert(t5 > t1, "A: higher tier should be longer")
	var qty1: int = int(db.call("get_training_time", "Infantry", 1, 1))
	var qty50: int = int(db.call("get_training_time", "Infantry", 1, 50))
	_assert(qty50 == qty1 * 50, "A: quantity should scale linearly")

	print("[POWER/TRAIN] B isolate account partition for power tests")
	if asp != null:
		asp.call("begin_smoke_isolation")
	if identity != null:
		identity.call("begin_smoke_isolation")
		identity.call("claim_local_saves_for_user", "power_user")
	if asp != null:
		asp.call("open_save_context", "power_user", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
		if asp.has_method("enable_smoke_bootstrap_hold"):
			asp.call("enable_smoke_bootstrap_hold", false)

	# Seed a clean L1 city authority file with catalog buildings at level 1.
	# Non-catalog known ids (wall, tavern, …) also default to L1 when absent — pin them to 0 power
	# by writing level 1 only for catalog; power calc uses data powerGained at that level.
	var bpath: String = str(asp.call("path_for", "buildings.cfg")) if asp != null else "user://buildings.cfg"
	var bcfg := ConfigFile.new()
	for bid: String in ["castle", "farm", "lumber_mill", "quarry", "iron_mine", "warehouse", "academy",
			"hospital", "embassy", "trading_post", "watchtower", "hall_of_heroes",
			"infantry_barracks", "marksmen_camp", "cavalry_stable", "sanctuary",
			"wall", "tavern", "dragon_roost", "rune_forge", "valor_shine", "arcane_tower"]:
		bcfg.set_value(bid, "level", 1)
	bcfg.save(bpath)
	if cs.has_method("refresh_account_save_paths"):
		cs.call("refresh_account_save_paths")

	# Clear troops to isolate building power first.
	_clear_troops(ts)
	ts.call("load_troops")

	print("[POWER/TRAIN] C L1 city power non-zero from buildings")
	var p_l1: int = int(gs.call("recalculate_player_power", true))
	_assert(p_l1 > 0, "C: L1 city power still 0")
	var castle_l1: int = int(dm.call("get_building_power_gain", "castle", 1))
	_assert(castle_l1 == 250, "C: castle L1 powerGained expected 250 got %d" % castle_l1)
	_assert(p_l1 >= castle_l1, "C: total should include castle L1")

	print("[POWER/TRAIN] D Citadel L1→L2 changes power by cumulative delta")
	bcfg.set_value("castle", "level", 2)
	bcfg.save(bpath)
	var castle_l2: int = int(dm.call("get_building_power_gain", "castle", 2))
	_assert(castle_l2 == 288, "D: castle L2 powerGained expected 288")
	var p_l2: int = int(gs.call("recalculate_player_power", true))
	_assert(p_l2 == p_l1 + (castle_l2 - castle_l1), "D: L1→L2 delta wrong p_l1=%d p_l2=%d" % [p_l1, p_l2])
	_assert(int(gs.get("power")) == p_l2, "D: GameState.power cache not updated")

	print("[POWER/TRAIN] E troop training completion increases power")
	var before_troops: int = p_l2
	var unit_power: int = int(db.call("get_power_gain", "Infantry", 1, 1))
	_assert(unit_power > 0, "E: infantry T1 power missing")
	ts.call("add_tier_troops", "Infantry", 1, 10)
	ts.call("save_troops")
	var after_troops: int = int(gs.call("recalculate_player_power", true))
	_assert(after_troops == before_troops + unit_power * 10, "E: troop power delta wrong")

	print("[POWER/TRAIN] F troop loss updates power")
	ts.call("remove_tier_troops", "Infantry", 1, 4)
	ts.call("save_troops")
	var after_loss: int = int(gs.call("recalculate_player_power", true))
	_assert(after_loss == after_troops - unit_power * 4, "F: loss delta wrong")

	print("[POWER/TRAIN] G stale persisted power cannot override calc")
	gs.set("power", 0)
	gs.call("save_resources")
	var restored_calc: int = int(gs.call("recalculate_player_power", true))
	_assert(restored_calc == after_loss, "G: recalc did not restore authoritative power")
	_assert(int(gs.get("power")) != 0, "G: cache still 0 after recalc")

	print("[POWER/TRAIN] H account reload recalculates (cloud-restore style)")
	# Poison cache again then reload systems.
	gs.set("power", 999999)
	gs.call("save_resources")
	if asp != null and asp.has_method("reload_bound_gameplay_systems"):
		asp.call("reload_bound_gameplay_systems")
	await process_frame
	var after_reload: int = int(gs.get("power"))
	_assert(after_reload == after_loss, "H: reload trusted stale power=%d expected=%d" % [after_reload, after_loss])

	# Cleanup
	if identity != null:
		identity.call("end_smoke_isolation")
	if asp != null:
		asp.call("end_smoke_isolation")

	if _fail.is_empty():
		print("[POWER/TRAIN] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[POWER/TRAIN] FAIL: %s" % f)
		quit(1)


func _clear_troops(ts: Node) -> void:
	for troop_class: String in ["Infantry", "Marksmen", "Cavalry"]:
		for tier: int in range(1, 13):
			var have: int = int(ts.call("get_tier_count", troop_class, tier))
			if have > 0:
				ts.call("remove_tier_troops", troop_class, tier, have)
	ts.call("save_troops")
