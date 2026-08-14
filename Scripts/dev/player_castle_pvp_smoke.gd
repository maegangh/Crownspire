extends SceneTree

## Player-castle PvP foundation smoke — fail-closed authority hardening.
## Godot --headless --path . -s res://Scripts/dev/player_castle_pvp_smoke.gd

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("[PVP-CASTLE] FAIL: %s" % msg)
	print("[PVP-CASTLE] FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("[PVP-CASTLE] OK: %s" % msg)


func _finish() -> void:
	if _failed == 0:
		print("[PVP-CASTLE] PASS")
		quit(0)
	else:
		print("[PVP-CASTLE] FAILED count=%d" % _failed)
		quit(1)


func _enemy_target(overrides: Dictionary = {}) -> Dictionary:
	var t := {
		"user_id": "enemy_user_001",
		"display_name": "RivalLord",
		"alliance_id": "ally_enemy",
		"alliance_tag": "RVL",
		"kingdom_id": "k1",
		"world_x": 4200.0,
		"world_y": 3800.0,
		"power": 12000,
		"citadel_level": 8,
		"peace_shield_active": false,
		"anti_scout_active": false,
		"beginner_protection_active": false,
		"resolved": true,
	}
	for k: Variant in overrides.keys():
		t[k] = overrides[k]
	return t


func _attacker(alliance_id: String = "ally_self") -> Dictionary:
	return {"user_id": "local_user_self", "alliance_id": alliance_id}


func _run() -> void:
	await process_frame
	var gate: Node = root.get_node_or_null("/root/HostileActionGate")
	var cps: Node = root.get_node_or_null("/root/CityProtectionState")
	var ms: Node = root.get_node_or_null("/root/MarchState")
	var ts: Node = root.get_node_or_null("/root/TroopState")
	var mail: Node = root.get_node_or_null("/root/MailManager")
	var ab: Node = root.get_node_or_null("/root/AllianceBackend")
	if gate == null or cps == null or ms == null or ts == null or mail == null:
		_fail("Required autoloads missing")
		_finish()
		return

	cps.call("begin_smoke_isolation")
	ms.call("begin_smoke_isolation")
	mail.call("begin_smoke_isolation")

	# --- Local UI gate scenarios (feedback only) ---
	var enemy: Dictionary = _enemy_target()
	var atk_ok: Dictionary = gate.call("evaluate", "attack", enemy, _attacker())
	var scout_ok: Dictionary = gate.call("evaluate", "scout", enemy, _attacker())
	if not bool(atk_ok.get("ok", false)) or not bool(scout_ok.get("ok", false)):
		_fail("enemy should allow scout/attack locally: %s / %s" % [atk_ok, scout_ok])
	else:
		_ok("enemy unshielded allows scout+attack (local UI gate)")

	var self_t: Dictionary = _enemy_target({"user_id": "local_user_self"})
	var self_atk: Dictionary = gate.call("evaluate", "attack", self_t, _attacker())
	if bool(self_atk.get("ok", false)) or str(self_atk.get("code", "")) != "self":
		_fail("own castle must block")
	else:
		_ok("own castle blocks scout+attack")

	var ally_t: Dictionary = _enemy_target({"alliance_id": "ally_self"})
	var ally_atk: Dictionary = gate.call("evaluate", "attack", ally_t, _attacker())
	if bool(ally_atk.get("ok", false)) or "alliance member" not in str(ally_atk.get("reason", "")).to_lower():
		_fail("alliance mate must block with reason")
	else:
		_ok("same-alliance blocks with clear reason")

	var shield_t: Dictionary = _enemy_target({"peace_shield_active": true})
	var sh_atk: Dictionary = gate.call("evaluate", "attack", shield_t, _attacker())
	if bool(sh_atk.get("ok", false)) or "Peace Shield" not in str(sh_atk.get("reason", "")):
		_fail("shield reason missing")
	else:
		_ok("peace shield blocks with correct reason")

	var beg_t: Dictionary = _enemy_target({"beginner_protection_active": true})
	var beg_atk: Dictionary = gate.call("evaluate", "attack", beg_t, _attacker())
	if bool(beg_atk.get("ok", false)) or "Beginner Protection" not in str(beg_atk.get("reason", "")):
		_fail("beginner reason missing")
	else:
		_ok("beginner protection blocks")

	# --- A. Server unavailable → hostile dispatch BLOCKED ---
	var open_target: Dictionary = ms.call("build_player_castle_target", enemy)
	var no_auth: Dictionary = ms.call("dispatch_scout_march", open_target, {})
	if bool(no_auth.get("ok", false)):
		_fail("A: empty authority must not launch scout")
	elif "Unable to verify" not in str(no_auth.get("reason", "")):
		_fail("A: expected unavailable message got %s" % no_auth)
	else:
		_ok("A: server unavailable blocks hostile dispatch")

	if ab != null and ab.has_method("validate_hostile_action"):
		var offline: Dictionary = await ab.call("validate_hostile_action", "attack", "enemy_user_001")
		if bool(offline.get("ok", false)) or bool(offline.get("authority_verified", false)):
			_fail("A2: AllianceBackend offline must fail-closed")
		elif "Unable to verify" not in str(offline.get("reason", "")):
			_fail("A2: AllianceBackend message wrong: %s" % offline)
		else:
			_ok("A2: AllianceBackend fail-closed when unauthenticated")

	# Seed troops
	var bak := {
		"infantry_by_tier": (ts.get("infantry_by_tier") as Dictionary).duplicate(true),
		"marksmen_by_tier": (ts.get("marksmen_by_tier") as Dictionary).duplicate(true),
		"cavalry_by_tier": (ts.get("cavalry_by_tier") as Dictionary).duplicate(true),
	}
	ts.set("infantry_by_tier", {5: 2000})
	ts.set("marksmen_by_tier", {4: 500})
	ts.set("cavalry_by_tier", {})
	if ts.has_method("_resync_totals"):
		ts.call("_resync_totals")
	var troops_before_inf: int = int(ts.call("get_tier_count", "infantry", 5))
	var troops := {
		"infantry": 200,
		"marksmen": 50,
		"cavalry": 0,
		"tier_composition": {
			"infantry": {"5": 200},
			"marksmen": {"4": 50},
			"cavalry": {},
		},
	}

	# --- B. Client allowed, server same-alliance → BLOCKED, no troops ---
	var ally_auth: Dictionary = ms.call(
		"make_smoke_hostile_authority",
		false,
		open_target,
		"same_alliance",
		"Cannot attack an alliance member."
	)
	var b_res: Dictionary = ms.call("dispatch_pvp_attack_march", open_target, troops, [], ally_auth)
	var troops_after_b: int = int(ts.call("get_tier_count", "infantry", 5))
	if bool(b_res.get("ok", false)):
		_fail("B: server same-alliance must block")
	elif troops_after_b != troops_before_inf:
		_fail("B: troops reserved despite deny")
	else:
		_ok("B: server same-alliance blocks; no troop reservation")

	# --- C. Client allowed, server shielded → BLOCKED ---
	var sh_auth: Dictionary = ms.call(
		"make_smoke_hostile_authority",
		false,
		open_target,
		"peace_shield",
		"This city is protected by a Peace Shield."
	)
	var c_res: Dictionary = ms.call("dispatch_pvp_attack_march", open_target, troops, [], sh_auth)
	if bool(c_res.get("ok", false)) or "Peace Shield" not in str(c_res.get("reason", "")):
		_fail("C: server shield must block with reason")
	elif int(ts.call("get_tier_count", "infantry", 5)) != troops_before_inf:
		_fail("C: troops reserved on shield deny")
	else:
		_ok("C: server shield blocks; no troop reservation")

	# --- E. Failed final validation creates no march ---
	if not (ms.get("active_marches") as Array).is_empty():
		_fail("E: marches existed after failed validations")
	else:
		_ok("E: failed final validation creates no march")

	# --- F. Forged target/user ID rejected ---
	var forged: Dictionary = open_target.duplicate(true)
	forged["user_id"] = ""
	var forged_auth: Dictionary = ms.call("make_smoke_hostile_authority", true, forged)
	var f_res: Dictionary = ms.call("dispatch_scout_march", forged, forged_auth)
	if bool(f_res.get("ok", false)):
		_fail("F: forged empty user_id must reject")
	else:
		_ok("F: forged target rejected")

	# --- Valid scout with authority ---
	var ok_auth: Dictionary = ms.call("make_smoke_hostile_authority", true, open_target)
	var scout_res: Dictionary = ms.call("dispatch_scout_march", open_target, ok_auth)
	if not bool(scout_res.get("ok", false)):
		_fail("scout dispatch failed: %s" % scout_res)
	else:
		var scout_id: String = str(scout_res.get("march_id", ""))
		_force_arrive_and_tick(ms, scout_id)
		await process_frame
		if not bool(mail.call("has_scout_report_for_march", scout_id)):
			_fail("scout report missing")
		else:
			_ok("valid scout completed with authority + report")

	ms.set("active_marches", [])
	ms.call("save_marches")

	# --- Valid PvP attack ---
	var atk_res: Dictionary = ms.call("dispatch_pvp_attack_march", open_target, troops, [], ok_auth)
	if not bool(atk_res.get("ok", false)):
		_fail("pvp attack dispatch failed: %s" % atk_res)
	else:
		var mid: String = str(atk_res.get("march_id", ""))
		# --- D. Shield AFTER dispatch → existing attack remains valid ---
		var marches: Array = ms.get("active_marches")
		var found_pre: Dictionary = {}
		for m: Variant in marches:
			if typeof(m) == TYPE_DICTIONARY and str(m.get("march_id", "")) == mid:
				found_pre = m
				break
		if found_pre.is_empty():
			_fail("D: march missing after dispatch")
		else:
			# Simulate defender activating shield after launch — must not remove march.
			found_pre["target_data"]["peace_shield_active"] = true
			found_pre["target_data"]["peace_shield_expires_at"] = int(Time.get_unix_time_from_system()) + 99999
			_force_arrive_and_tick(ms, mid)
			_force_combat_end_and_tick(ms, mid)
			await process_frame
			if not bool(mail.call("has_pvp_report_for_march", mid)):
				_fail("D: mid-flight shield cancelled combat / no report")
			else:
				_ok("D: shield after dispatch — attack still resolves + report")

	# Restore troops
	ts.set("infantry_by_tier", bak.get("infantry_by_tier", {}))
	ts.set("marksmen_by_tier", bak.get("marksmen_by_tier", {}))
	ts.set("cavalry_by_tier", bak.get("cavalry_by_tier", {}))
	if ts.has_method("_resync_totals"):
		ts.call("_resync_totals")

	ms.call("end_smoke_isolation")
	mail.call("end_smoke_isolation")
	cps.call("end_smoke_isolation")
	_finish()


func _force_arrive_and_tick(ms: Node, march_id: String) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var marches: Array = ms.get("active_marches")
	for i: int in range(marches.size()):
		var m: Dictionary = marches[i]
		if str(m.get("march_id", "")) != march_id:
			continue
		m["arrival_timestamp"] = now - 1
		marches[i] = m
	ms.set("active_marches", marches)
	ms.call("_tick_marches")


func _force_combat_end_and_tick(ms: Node, march_id: String) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var marches: Array = ms.get("active_marches")
	for i: int in range(marches.size()):
		var m: Dictionary = marches[i]
		if str(m.get("march_id", "")) != march_id:
			continue
		m["combat_end_unix"] = now - 1
		m["status"] = "IN_COMBAT"
		marches[i] = m
	ms.set("active_marches", marches)
	ms.call("_tick_marches")
	marches = ms.get("active_marches")
	for i2: int in range(marches.size()):
		var m2: Dictionary = marches[i2]
		if str(m2.get("march_id", "")) != march_id:
			continue
		m2["return_arrival_timestamp"] = now - 1
		marches[i2] = m2
	ms.set("active_marches", marches)
	ms.call("_tick_marches")
