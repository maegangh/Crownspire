extends SceneTree

## Phase 2 local save isolation / account handoff smoke.
##   Godot --headless --path <project> -s res://Scripts/dev/account_save_isolation_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame

	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if asp == null or identity == null:
		push_error("[ACCOUNT P2] ABORT — AccountSavePaths or AccountIdentityState missing")
		quit(2)
		return

	print("[ACCOUNT P2] A classification inventory")
	_assert(str(asp.call("classify_file", "buildings.cfg")) == "account_owned", "A: buildings not account_owned")
	_assert(str(asp.call("classify_file", "locale.cfg")) == "device_global", "A: locale not device_global")
	_assert(str(asp.call("classify_file", "nakama_config.cfg")) == "device_global", "A: nakama_config not device_global")
	_assert(str(asp.call("classify_file", "account_session.cfg")) == "device_global", "A: session not device_global")

	asp.call("begin_smoke_isolation")
	identity.call("begin_smoke_isolation")

	var legacy_buildings := "user://buildings.cfg"
	var legacy_resources := "user://resources.cfg"
	var bak_b := "user://buildings.cfg.__p2_smoke_bak"
	var bak_r := "user://resources.cfg.__p2_smoke_bak"
	_backup_if_exists(legacy_buildings, bak_b)
	_backup_if_exists(legacy_resources, bak_r)

	# Seed legacy flat progression belonging to user_a.
	var seed_b := ConfigFile.new()
	seed_b.set_value("castle", "level", 7)
	seed_b.set_value("p2_smoke", "marker", "city_of_a")
	seed_b.save(legacy_buildings)
	var seed_r := ConfigFile.new()
	seed_r.set_value("resources", "food", 4242)
	seed_r.save(legacy_resources)
	var legacy_mtime := FileAccess.get_modified_time(legacy_buildings)

	print("[ACCOUNT P2] B legacy migrate once for matching owner")
	identity.call("claim_local_saves_for_user", "user_a")
	var open_a: Dictionary = asp.call(
		"open_save_context",
		"user_a",
		{"legacy_owner": "user_a", "legacy_mismatch": false}
	)
	_assert(bool(open_a.get("ok", false)), "B: open_a failed")
	var mig: Dictionary = open_a.get("migration", {})
	_assert(bool(mig.get("ok", false)), "B: migration not ok: %s" % str(mig))
	_assert(bool(mig.get("migrated", false)) or bool(mig.get("skipped", false)), "B: no migrate/skip")
	var part_b: String = str(asp.call("partition_path", "buildings.cfg", "user_a"))
	_assert(FileAccess.file_exists(part_b), "B: partition buildings missing")
	_assert(FileAccess.file_exists(legacy_buildings), "B: legacy buildings deleted")
	_assert(FileAccess.get_modified_time(legacy_buildings) == legacy_mtime, "B: legacy buildings altered")
	var part_cfg := ConfigFile.new()
	_assert(part_cfg.load(part_b) == OK, "B: partition buildings unreadable")
	_assert(str(part_cfg.get_value("p2_smoke", "marker", "")) == "city_of_a", "B: marker not migrated")
	_assert(int(part_cfg.get_value("castle", "level", 0)) == 7, "B: castle level not migrated")

	print("[ACCOUNT P2] C migration idempotent")
	var mig2: Dictionary = asp.call("migrate_legacy_into_user", "user_a")
	_assert(bool(mig2.get("ok", false)), "C: second migrate failed")
	_assert(bool(mig2.get("skipped", false)), "C: second migrate not skipped")
	_assert(not bool(mig2.get("migrated", false)), "C: second migrate recopied")

	print("[ACCOUNT P2] D matching user loads partition path")
	var resolved: String = str(asp.call("path_for", "buildings.cfg"))
	_assert(resolved == part_b, "D: path_for mismatch %s vs %s" % [resolved, part_b])
	var gs: Node = root.get_node_or_null("/root/GameState")
	_assert(gs != null and str(gs.call("get_resources_path")).find("user_a") >= 0, "D: GameState not on partition")

	print("[ACCOUNT P2] E second user cannot see first city; gets empty partition")
	# Simulate legacy ownership remaining user_a while auth is user_b.
	var open_b: Dictionary = asp.call(
		"open_save_context",
		"user_b",
		{"legacy_owner": "user_a", "legacy_mismatch": true}
	)
	_assert(bool(open_b.get("ok", false)), "E: open_b failed")
	_assert(bool(open_b.get("legacy_mismatch", false)), "E: mismatch not flagged")
	var mig_b: Dictionary = open_b.get("migration", {})
	_assert(str(mig_b.get("error", "")) == "LOCAL_SAVE_ACCOUNT_MISMATCH", "E: expected mismatch on legacy migrate")
	var b_buildings: String = str(asp.call("path_for", "buildings.cfg"))
	_assert(b_buildings.find("user_b") >= 0, "E: not on user_b partition")
	_assert(not FileAccess.file_exists(b_buildings) or _marker_of(b_buildings) != "city_of_a", "E: user_b sees user_a city")
	# Ensure user_a partition untouched.
	var a_again := ConfigFile.new()
	_assert(a_again.load(part_b) == OK, "E: user_a partition damaged")
	_assert(str(a_again.get_value("p2_smoke", "marker", "")) == "city_of_a", "E: user_a city overwritten")
	_assert(FileAccess.file_exists(legacy_buildings), "E: legacy deleted during b open")
	_assert(FileAccess.get_modified_time(legacy_buildings) == legacy_mtime, "E: legacy altered for b")

	print("[ACCOUNT P2] F write to user_b does not overwrite user_a")
	var b_cfg := ConfigFile.new()
	b_cfg.set_value("p2_smoke", "marker", "city_of_b")
	b_cfg.set_value("castle", "level", 1)
	b_cfg.save(b_buildings)
	var a_check := ConfigFile.new()
	a_check.load(part_b)
	_assert(str(a_check.get_value("p2_smoke", "marker", "")) == "city_of_a", "F: cross-account overwrite")

	print("[ACCOUNT P2] G switch back restores user_a")
	var reopen_a: Dictionary = asp.call(
		"open_save_context",
		"user_a",
		{"legacy_owner": "user_a", "legacy_mismatch": false}
	)
	_assert(bool(reopen_a.get("ok", false)), "G: reopen_a failed")
	var back: String = str(asp.call("path_for", "buildings.cfg"))
	_assert(back == part_b, "G: not back on user_a path")
	var restored := ConfigFile.new()
	restored.load(back)
	_assert(str(restored.get_value("p2_smoke", "marker", "")) == "city_of_a", "G: user_a data not restored")
	_assert(int(restored.get_value("castle", "level", 0)) == 7, "G: castle level lost")

	print("[ACCOUNT P2] H path_for_user blocks cross-account while bound")
	var blocked: String = str(asp.call("path_for_user", "user_b", "buildings.cfg"))
	_assert(blocked == "", "H: cross-account path_for_user should be empty while bound to a")

	print("[ACCOUNT P2] I device-global remains flat")
	_assert(str(asp.call("path_for", "locale.cfg")) == "user://locale.cfg", "I: locale namespaced")
	_assert(str(asp.call("path_for", "nakama_config.cfg")) == "user://nakama_config.cfg", "I: nakama_config namespaced")
	_assert(not bool(asp.call("is_legacy_flat_authoritative")), "I: legacy still authoritative")
	_assert(not bool(asp.call("is_legacy_flat_reachable_for_gameplay")), "I: legacy still gameplay-reachable")

	print("[ACCOUNT P2] K stale legacy must not win over newer partition")
	# Update A partition after migration; leave legacy snapshot stale.
	var updated := ConfigFile.new()
	updated.load(part_b)
	updated.set_value("p2_smoke", "marker", "city_of_a_v2")
	updated.set_value("castle", "level", 9)
	updated.save(part_b)
	# Poison legacy flat with old marker to prove it is ignored.
	var poison := ConfigFile.new()
	poison.set_value("p2_smoke", "marker", "stale_legacy_a")
	poison.set_value("castle", "level", 1)
	poison.save(legacy_buildings)
	asp.call("close_save_context")
	# Unbound must not resolve to legacy.
	var unbound_path: String = str(asp.call("path_for", "buildings.cfg"))
	_assert(unbound_path.find("__unbound__") >= 0, "K: unbound path_for not quarantine: %s" % unbound_path)
	_assert(unbound_path.find("user://buildings.cfg") < 0 or unbound_path != "user://buildings.cfg", "K: unbound returned flat legacy")
	_assert(str(asp.call("path_for", "buildings.cfg")) != "user://buildings.cfg", "K: exact legacy path returned while unbound")
	# Relaunch-style provisional bind as A (ownership claimed, no session in smoke store).
	var prov: Dictionary = asp.call("try_provisional_bind_for_boot")
	_assert(bool(prov.get("ok", false)), "K: provisional bind failed: %s" % str(prov))
	_assert(str(asp.call("get_active_user_id")) == "user_a", "K: provisional not user_a")
	var after_prov := ConfigFile.new()
	after_prov.load(str(asp.call("path_for", "buildings.cfg")))
	_assert(str(after_prov.get_value("p2_smoke", "marker", "")) == "city_of_a_v2", "K: stale legacy won over partition")
	_assert(int(after_prov.get_value("castle", "level", 0)) == 9, "K: partition level lost to legacy")

	print("[ACCOUNT P2] L Account B never reads A legacy/partition; tutorial detection isolated")
	# Wipe all progress markers for a truly empty B partition (earlier steps may have written).
	for marker: String in [
		"resources.cfg", "buildings.cfg", "troops.cfg", "heroes.cfg", "quests.cfg",
		"research_queue.cfg", "construction_queue.cfg", "marches.cfg", "alliance.cfg", "bag.cfg",
	]:
		var wipe: String = str(asp.call("partition_path", marker, "user_b"))
		if wipe != "" and FileAccess.file_exists(wipe):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(wipe))
	asp.call("close_save_context")
	# reload=false so boot-side saves cannot recreate empty marker files before the assert.
	var open_b2: Dictionary = asp.call(
		"open_save_context",
		"user_b",
		{"legacy_owner": "user_a", "legacy_mismatch": true, "reload": false}
	)
	_assert(bool(open_b2.get("ok", false)), "L: open_b2 failed")
	_assert(not bool(asp.call("has_account_gameplay_progress")), "L: empty B reported gameplay progress")
	var b_open_path: String = str(asp.call("path_for", "buildings.cfg"))
	_assert(b_open_path.find("user_b") >= 0, "L: not on B partition")
	_assert(not FileAccess.file_exists(b_open_path), "L: B unexpectedly has buildings file")
	_assert(_marker_of("user://buildings.cfg") == "stale_legacy_a" or _marker_of("user://buildings.cfg") != "city_of_a_v2", "L: sanity")
	# Bound B must not resolve gameplay path to legacy flat.
	_assert(str(asp.call("path_for", "buildings.cfg")) != "user://buildings.cfg", "L: B path_for returned legacy flat")
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	if ts != null and ts.has_method("load_tutorial_state"):
		ts.call("load_tutorial_state")
		_assert(not bool(ts.call("has_existing_gameplay_saves")), "L: TutorialState inherited A progress for B")
	# Write B data.
	var b_path2: String = str(asp.call("path_for", "buildings.cfg"))
	var b_write := ConfigFile.new()
	b_write.set_value("p2_smoke", "marker", "city_of_b_final")
	b_write.save(b_path2)
	_assert(bool(asp.call("has_account_gameplay_progress")), "L: B write not detected as progress")
	if ts != null:
		ts.call("load_tutorial_state")
		_assert(bool(ts.call("has_existing_gameplay_saves")), "L: TutorialState missed B progress after write")

	print("[ACCOUNT P2] M switch back to A — partition v2 wins; B untouched")
	asp.call("open_save_context", "user_a", {"legacy_owner": "user_a", "legacy_mismatch": false})
	var a_final := ConfigFile.new()
	a_final.load(str(asp.call("path_for", "buildings.cfg")))
	_assert(str(a_final.get_value("p2_smoke", "marker", "")) == "city_of_a_v2", "M: A lost v2 after switch")
	if ts != null:
		ts.call("load_tutorial_state")
		_assert(bool(ts.call("has_existing_gameplay_saves")), "M: A not recognized as progressed")
	var b_untouched := ConfigFile.new()
	b_untouched.load(b_path2)
	_assert(str(b_untouched.get_value("p2_smoke", "marker", "")) == "city_of_b_final", "M: B partition altered")

	print("[ACCOUNT P2] N GameState path never points at foreign legacy while unbound/B")
	asp.call("close_save_context")
	if gs != null:
		var gs_unbound: String = str(gs.call("get_resources_path"))
		_assert(gs_unbound.find("__unbound__") >= 0, "N: GameState unbound still on legacy: %s" % gs_unbound)
	asp.call("open_save_context", "user_b", {"legacy_owner": "user_a", "legacy_mismatch": true})
	if gs != null:
		var gs_b: String = str(gs.call("get_resources_path"))
		_assert(gs_b.find("user_b") >= 0, "N: GameState not on B partition")
		_assert(gs_b != "user://resources.cfg", "N: GameState still flat legacy on B")

	# Restore any pre-existing legacy files after smoke seeds.
	_restore_backup(bak_b, legacy_buildings)
	_restore_backup(bak_r, legacy_resources)
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")

	# Re-bind live authenticated account so editor userdata is not left unbound.
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	if nc != null and bool(nc.call("is_authenticated")):
		identity.call(
			"on_authenticated",
			str(nc.call("get_user_id")),
			str(nc.call("get_last_auth_source"))
		)

	print("[ACCOUNT P2] J switch primitives exist")
	_assert(asp.has_method("close_save_context"), "J: close_save_context missing")
	_assert(asp.has_method("open_save_context"), "J: open_save_context missing")
	_assert(asp.has_method("ensure_partition"), "J: ensure_partition missing")
	_assert(asp.has_method("migrate_legacy_into_user"), "J: migrate_legacy_into_user missing")
	_assert(asp.has_method("try_provisional_bind_for_boot"), "J: try_provisional_bind_for_boot missing")

	if _fail.is_empty():
		print("[ACCOUNT P2] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ACCOUNT P2] FAIL: %s" % f)
		quit(1)


func _marker_of(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value("p2_smoke", "marker", ""))


func _backup_if_exists(src: String, bak: String) -> void:
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
	if FileAccess.file_exists(src):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(bak))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))


func _restore_backup(bak: String, dst: String) -> void:
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
	if FileAccess.file_exists(bak):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(bak), ProjectSettings.globalize_path(dst))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
