extends SceneTree

## Regression: exact tier composition across wildling, gather, rally, lair paths.
## Godot --headless --path . -s res://Scripts/dev/march_tier_paths_smoke.gd

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("[MARCH-TIER-PATHS] FAIL: %s" % msg)
	print("[MARCH-TIER-PATHS] FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("[MARCH-TIER-PATHS] OK: %s" % msg)


func _tier_count(ts: Node, kind: String, tier: int) -> int:
	return int(ts.call("get_tier_count", kind, tier))


func _seed_troop_state(ts: Node) -> Dictionary:
	var bak: Dictionary = {
		"infantry_by_tier": (ts.get("infantry_by_tier") as Dictionary).duplicate(true),
		"marksmen_by_tier": (ts.get("marksmen_by_tier") as Dictionary).duplicate(true),
		"cavalry_by_tier": (ts.get("cavalry_by_tier") as Dictionary).duplicate(true),
	}
	ts.set("infantry_by_tier", {8: 8000, 9: 2000})
	ts.set("marksmen_by_tier", {7: 750})
	ts.set("cavalry_by_tier", {})
	if ts.has_method("_resync_totals"):
		ts.call("_resync_totals")
	return bak


func _restore_troop_state(ts: Node, bak: Dictionary) -> void:
	ts.set("infantry_by_tier", bak.get("infantry_by_tier", {}))
	ts.set("marksmen_by_tier", bak.get("marksmen_by_tier", {}))
	ts.set("cavalry_by_tier", bak.get("cavalry_by_tier", {}))
	if ts.has_method("_resync_totals"):
		ts.call("_resync_totals")


func _explicit_payload() -> Dictionary:
	return {
		"infantry": 1500,
		"marksmen": 750,
		"cavalry": 0,
		"tier_composition": {
			"infantry": {"8": 500, "9": 1000},
			"marksmen": {"7": 750},
			"cavalry": {},
		},
	}


func _run() -> void:
	await process_frame
	var ms: Node = root.get_node_or_null("/root/MarchState")
	var ts: Node = root.get_node_or_null("/root/TroopState")
	if ms == null or ts == null:
		_fail("MarchState/TroopState missing")
		_finish()
		return

	ms.call("begin_smoke_isolation")
	var bak: Dictionary = _seed_troop_state(ts)

	# --- resolve + availability ---
	var payload: Dictionary = _explicit_payload()
	var resolved: Dictionary = ms.call("resolve_troop_composition", payload)
	if int((resolved.get("infantry", {}) as Dictionary).get("8", 0)) != 500:
		_fail("resolve lost infantry T8")
	else:
		_ok("explicit tier composition preserved by resolve")
	var avail: Dictionary = ms.call("validate_tier_availability", resolved)
	if not bool(avail.get("ok", false)):
		_fail("validate_tier_availability: %s" % str(avail.get("error", "")))
	else:
		_ok("tier availability validates")

	var over: Dictionary = ms.call(
		"validate_tier_availability",
		{"infantry": {"8": 99999}, "marksmen": {}, "cavalry": {}}
	)
	if bool(over.get("ok", false)):
		_fail("over-availability should fail")
	else:
		_ok("over-availability rejected")

	var neg: Dictionary = ms.call(
		"normalize_tier_composition",
		{"infantry": {"8": -100}, "marksmen": {}, "cavalry": {}}
	)
	var neg_inf: Dictionary = neg.get("infantry", {}) as Dictionary
	if not neg_inf.is_empty():
		_fail("negative tier qty should normalize away")
	else:
		_ok("negative counts normalize to empty")

	# --- wildling zero heroes ---
	var wild_target: Dictionary = {
		"species": "wolf",
		"level": 1,
		"position": {"x": 10.0, "y": 10.0},
		"instance_id": 999999,
	}
	var wild_check: Dictionary = ms.call("validate_wildling_dispatch", wild_target, payload, [])
	if bool(wild_check.get("ok", false)):
		_ok("wildling zero-hero + exact tiers validate")
	else:
		var err: String = str(wild_check.get("error", ""))
		if err.find("hero") >= 0 or err.find("Hero") >= 0:
			_fail("wildling blocked by hero rule: %s" % err)
		else:
			_ok("wildling zero-hero not hero-blocked (%s)" % err)

	# --- gather zero heroes ---
	var rts: Node = root.get_node_or_null("/root/ResourceTileState")
	if rts != null:
		if rts.has_method("begin_smoke_isolation"):
			rts.call("begin_smoke_isolation")
		var tile_id: String = "smoke_food_tier_paths"
		rts.call(
			"register_or_update_tile",
			tile_id,
			"food",
			1,
			5000,
			5000,
			Vector2(50.0, 50.0),
			"available"
		)
		var gather_target: Dictionary = {
			"target_type": "resource",
			"resource_tile_id": tile_id,
			"resource_type": "food",
			"resource_level": 1,
			"resource_amount": 5000,
			"position": {"x": 50.0, "y": 50.0},
		}
		var gather_check: Dictionary = ms.call("validate_resource_setup", gather_target, payload, [])
		if bool(gather_check.get("ok", false)):
			_ok("gather zero-hero + exact tiers validate")
		elif str(gather_check.get("error", "")).find("Hero") >= 0:
			_fail("gather blocked by hero rule")
		else:
			_ok("gather zero-hero not hero-blocked (%s)" % str(gather_check.get("error", "")))
		if rts.has_method("end_smoke_isolation"):
			rts.call("end_smoke_isolation")

	# --- rally reserve zero heroes + exact tiers ---
	var before_t8: int = _tier_count(ts, "Infantry", 8)
	var before_t9: int = _tier_count(ts, "Infantry", 9)
	var before_m7: int = _tier_count(ts, "Marksmen", 7)
	var rid: String = "smoke_rally_%d" % Time.get_ticks_msec()
	var reserve: Dictionary = ms.call("reserve_for_rally", rid, payload, [])
	if not bool(reserve.get("ok", false)):
		_fail("reserve_for_rally zero-hero: %s" % str(reserve.get("error", "")))
	else:
		_ok("rally zero-hero reserve ok")
	var res_tiers: Dictionary = reserve.get("troop_tiers", {}) as Dictionary
	if int((res_tiers.get("infantry", {}) as Dictionary).get("8", 0)) != 500:
		_fail("rally reserve lost infantry T8")
	if int((res_tiers.get("infantry", {}) as Dictionary).get("9", 0)) != 1000:
		_fail("rally reserve lost infantry T9")
	if int((res_tiers.get("marksmen", {}) as Dictionary).get("7", 0)) != 750:
		_fail("rally reserve lost marksmen T7")
	if _tier_count(ts, "Infantry", 8) != before_t8 - 500:
		_fail("rally deploy wrong infantry T8 count")
	if _tier_count(ts, "Infantry", 9) != before_t9 - 1000:
		_fail("rally deploy wrong infantry T9 count")
	if _tier_count(ts, "Marksmen", 7) != before_m7 - 750:
		_fail("rally deploy wrong marksmen T7 count")
	else:
		_ok("rally exact tier deploy accounting")

	var dup: Dictionary = ms.call("reserve_for_rally", "dup_%s" % rid, payload, [])
	if bool(dup.get("ok", false)):
		_fail("duplicate reserve should fail when troops already deployed")
	else:
		_ok("duplicate reserve rejected")

	ms.call("refund_rally_reservation", rid)
	if _tier_count(ts, "Infantry", 8) != before_t8:
		_fail("rally refund wrong infantry T8")
	if _tier_count(ts, "Infantry", 9) != before_t9:
		_fail("rally refund wrong infantry T9")
	if _tier_count(ts, "Marksmen", 7) != before_m7:
		_fail("rally refund wrong marksmen T7")
	else:
		_ok("rally exact tier refund restores inventory")

	# --- lair solo exact tiers ---
	var lair: Dictionary = {
		"lair_id": "smoke_lair",
		"lair_level": 1,
		"species": "wolf",
		"world_position": {"x": 120.0, "y": 120.0},
	}
	var lair_result: Dictionary = ms.call("dispatch_lair_attack_march", lair, payload, [])
	if not bool(lair_result.get("ok", false)):
		_fail("lair dispatch: %s" % str(lair_result.get("error", "")))
	else:
		_ok("lair solo dispatch ok")
		var marches: Array = ms.get("active_marches") as Array
		if marches.is_empty():
			_fail("lair march not recorded")
		else:
			var march: Dictionary = marches[marches.size() - 1] as Dictionary
			var tiers: Dictionary = march.get("troop_tiers", {}) as Dictionary
			if int((tiers.get("infantry", {}) as Dictionary).get("9", 0)) != 1000:
				_fail("lair march lost infantry T9")
			else:
				_ok("lair march preserves exact tiers")
			var return_tiers: Dictionary = march.get("troop_tiers", {}) as Dictionary
			ts.call("return_troops_by_tiers", return_tiers)
			ms.set("active_marches", [])

	# --- legacy flat fallback ---
	_restore_troop_state(ts, bak)
	_seed_troop_state(ts)
	var flat_only: Dictionary = {"infantry": 100, "marksmen": 0, "cavalry": 0}
	var auto_comp: Dictionary = ms.call("resolve_troop_composition", flat_only)
	var inf_auto: Dictionary = auto_comp.get("infantry", {}) as Dictionary
	var inf_total: int = 0
	for v: Variant in inf_auto.values():
		inf_total += int(v)
	if inf_total != 100:
		_fail("legacy flat fallback allocation")
	else:
		_ok("legacy flat payload still resolves via lowest-tier-first")

	_restore_troop_state(ts, bak)
	ms.call("end_smoke_isolation")
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("[MARCH-TIER-PATHS] ALL PASSED")
		quit(0)
	else:
		print("[MARCH-TIER-PATHS] FAILED count=%d" % _failed)
		quit(1)
