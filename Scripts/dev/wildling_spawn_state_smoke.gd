extends SceneTree

## Isolated WildlingSpawnState cooldown smoke.
## Uses begin_smoke_isolation() so user://wildling_spawns.cfg is never touched.
## Run:
##   Godot --headless --path <project> -s res://Scripts/dev/wildling_spawn_state_smoke.gd

var _fail: Array[String] = []
var _wss: Node = null
var _now: int = 0


func _initialize() -> void:
	print("[WSS SMOKE] start")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_wss = root.get_node_or_null("/root/WildlingSpawnState")
	if _wss == null:
		push_error("[WSS SMOKE] WildlingSpawnState autoload missing")
		quit(1)
		return

	_now = int(Time.get_unix_time_from_system())
	_wss.call("begin_smoke_isolation")
	if str(_wss.call("get_save_path")) != "user://wildling_spawns_smoke_test.cfg":
		_fail.append("save path not isolated: %s" % str(_wss.call("get_save_path")))

	_test_a_stable_slot_id()
	_test_b_claim_and_duplicate()
	_test_c_persistence_and_block()
	_test_d_expiry_clears()
	_test_e_malformed_ignored()
	_test_f_tutorial_l1_clear_scoped()
	_test_g_no_broad_clear_api()

	_wss.call("end_smoke_isolation")

	if _fail.is_empty():
		print("[WSS SMOKE] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[WSS SMOKE] FAIL: %s" % f)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _test_a_stable_slot_id() -> void:
	print("[WSS SMOKE] A stable slot id")
	var a: String = str(_wss.call("make_slot_id", "kingdom_test", 0))
	var b: String = str(_wss.call("make_slot_id", "kingdom_test", 0))
	var c: String = str(_wss.call("make_slot_id", "kingdom_test", 5))
	_assert(a == "kingdom_test:wildling:0", "A: unexpected id '%s'" % a)
	_assert(a == b, "A: slot id not stable across calls")
	_assert(a != c, "A: different indices must differ")
	var tut: String = str(_wss.call("tutorial_l1_slot_id", "kingdom_test"))
	_assert(tut == a, "A: tutorial L1 must be slot index 0")


func _test_b_claim_and_duplicate() -> void:
	print("[WSS SMOKE] B claim + duplicate rejection")
	var sid: String = str(_wss.call("make_slot_id", "kingdom_test", 3))
	var c1: Dictionary = _wss.call("try_claim_defeat", sid, "march_a", _now)
	_assert(bool(c1.get("ok", false)), "B: first claim failed: %s" % str(c1))
	_assert(int(c1.get("defeated_until", 0)) == _now + 600, "B: 10-minute until expected")
	_assert(bool(_wss.call("is_slot_on_cooldown", sid, _now + 1)), "B: slot should be on cooldown")

	var c2: Dictionary = _wss.call("try_claim_defeat", sid, "march_b", _now + 1)
	_assert(not bool(c2.get("ok", false)), "B: duplicate claim by other march must fail")
	_assert(str(c2.get("reason", "")) == "already_defeated", "B: expected already_defeated")

	# Same march re-call is allowed (idempotent self-claim) but must not re-grant a new window.
	var c_self: Dictionary = _wss.call("try_claim_defeat", sid, "march_a", _now + 2)
	_assert(bool(c_self.get("ok", false)), "B: same-march reclaim should be ok")
	_assert(bool(c_self.get("already_claimed_by_self", false)), "B: same-march should flag already_claimed_by_self")
	_assert(int(c_self.get("defeated_until", 0)) == _now + 600, "B: same-march must not extend cooldown")


func _test_c_persistence_and_block() -> void:
	print("[WSS SMOKE] C persistence reload")
	var sid: String = str(_wss.call("make_slot_id", "kingdom_test", 3))
	_wss.call("save_state")
	_wss.call("load_state")
	_assert(bool(_wss.call("is_slot_on_cooldown", sid, _now + 1)), "C: cooldown lost after reload")
	_assert(int(_wss.call("get_defeated_until", sid)) == _now + 600, "C: defeated_until wrong after reload")


func _test_d_expiry_clears() -> void:
	print("[WSS SMOKE] D expiry clears")
	var sid: String = str(_wss.call("make_slot_id", "kingdom_test", 3))
	var removed: int = int(_wss.call("purge_expired", _now + 600))
	_assert(removed >= 1, "D: purge at expiry should remove record")
	_assert(not bool(_wss.call("is_slot_on_cooldown", sid, _now + 600)), "D: slot still blocked after expiry")
	# Fresh claim after expiry must succeed (spawnable again).
	var c_fresh: Dictionary = _wss.call("try_claim_defeat", sid, "march_fresh", _now + 600)
	_assert(bool(c_fresh.get("ok", false)), "D: claim after expiry failed")
	_wss.call("clear_slot", sid)


func _test_e_malformed_ignored() -> void:
	print("[WSS SMOKE] E malformed rows ignored")
	# Seed one good record, then poison the cfg with bad rows and reload.
	var good: String = str(_wss.call("make_slot_id", "kingdom_test", 7))
	_wss.call("try_claim_defeat", good, "march_good", _now)
	_wss.call("save_state")

	var path: String = str(_wss.call("get_save_path"))
	var cfg := ConfigFile.new()
	_assert(cfg.load(path) == OK, "E: could not load smoke cfg")
	cfg.set_value("defeated", "bad_slot", "not-json")
	cfg.set_value("defeated", "no_until", JSON.stringify({"kingdom_id": "k", "slot_index": 1}))
	_assert(cfg.save(path) == OK, "E: could not save poisoned cfg")

	_wss.call("load_state")
	_assert(bool(_wss.call("is_slot_on_cooldown", good, _now + 1)), "E: good record destroyed by malformed neighbors")
	_assert(not bool(_wss.call("is_slot_on_cooldown", "bad_slot", _now + 1)), "E: bad_slot should not load")
	_assert(not bool(_wss.call("is_slot_on_cooldown", "no_until", _now + 1)), "E: no_until should not load")
	_wss.call("clear_slot", good)


func _test_f_tutorial_l1_clear_scoped() -> void:
	print("[WSS SMOKE] F tutorial L1 clear scoped")
	var kid: String = "kingdom_dev_001"
	var tut: String = str(_wss.call("tutorial_l1_slot_id", kid))
	var other: String = str(_wss.call("make_slot_id", kid, 5))
	_wss.call("try_claim_defeat", tut, "m_tut", _now)
	_wss.call("try_claim_defeat", other, "m_other", _now)
	_assert(bool(_wss.call("is_tutorial_l1_on_cooldown", kid)), "F: tutorial L1 should be on cooldown")
	_assert(bool(_wss.call("is_slot_on_cooldown", other, _now + 1)), "F: other slot should be on cooldown")

	var cleared: bool = bool(_wss.call("debug_clear_tutorial_l1_cooldown"))
	_assert(cleared, "F: debug_clear_tutorial_l1_cooldown failed (need debug build)")
	_assert(not bool(_wss.call("is_tutorial_l1_on_cooldown", kid)), "F: tutorial L1 still on cooldown")
	_assert(bool(_wss.call("is_slot_on_cooldown", other, _now + 1)), "F: other slot cleared by L1 debug clear")


func _test_g_no_broad_clear_api() -> void:
	print("[WSS SMOKE] G no broad clear-all API")
	# Production surface must not expose a wipe-all-cooldowns helper.
	_assert(not _wss.has_method("clear_all_cooldowns"), "G: clear_all_cooldowns must not exist")
	_assert(not _wss.has_method("clear_all"), "G: clear_all must not exist")
	_assert(not _wss.has_method("reset_all_defeats"), "G: reset_all_defeats must not exist")
	_assert(_wss.has_method("clear_slot"), "G: clear_slot (single) should exist")
	_assert(_wss.has_method("debug_clear_tutorial_l1_cooldown"), "G: L1-only debug clear should exist")
