extends SceneTree

## Phase 3 cloud save / restore foundation smoke (hardened).
##   Godot --headless --path <project> -s res://Scripts/dev/account_cloud_save_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame

	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if cloud == null or asp == null or identity == null:
		push_error("[ACCOUNT P3] ABORT — AccountCloudSave/AccountSavePaths/Identity missing")
		quit(2)
		return

	print("[ACCOUNT P3] A exclusions + allowlist")
	var included: PackedStringArray = cloud.call("list_cloud_files")
	var excluded: PackedStringArray = cloud.call("list_excluded_files")
	_assert(included.has("buildings.cfg"), "A: buildings missing from cloud files")
	_assert(included.has("resources.cfg"), "A: resources missing")
	_assert(included.has("quests.cfg"), "A: quests missing")
	_assert(included.has("tutorial.cfg"), "A: tutorial missing")
	_assert(included.has("tutorial_grants.cfg"), "A: tutorial_grants missing")
	_assert(included.has("healing_queue.cfg"), "A: healing missing")
	_assert(included.has("sanctuary.cfg"), "A: sanctuary missing")
	_assert(included.has("events.cfg"), "A: events missing")
	_assert(included.has("mail.cfg"), "A: mail missing")
	_assert(included.has("marches.cfg"), "A: marches missing")
	_assert(included.has("wildling_spawns.cfg"), "A: wildling missing")
	_assert(excluded.has("resource_tiles.cfg"), "A: resource_tiles should be excluded")
	_assert(excluded.has("alliance.cfg"), "A: alliance.cfg should be excluded")
	_assert(excluded.has("alliance_lairs_runtime.cfg"), "A: lairs should be excluded")

	asp.call("begin_smoke_isolation")
	asp.call("enable_smoke_bootstrap_hold", true)
	identity.call("begin_smoke_isolation")
	cloud.call("begin_smoke_isolation")

	print("[ACCOUNT P3] B reject unbound / foreign upload")
	asp.call("close_save_context")
	var unbound_build: Dictionary = cloud.call("build_payload_from_active_partition")
	_assert(not bool(unbound_build.get("ok", false)), "B: unbound build should fail")
	_assert(str(unbound_build.get("error", "")) == "CLOUD_SAVE_REJECT_UNBOUND", "B: wrong unbound code")
	var unbound_up: Dictionary = await cloud.call("upload_current_partition")
	_assert(not bool(unbound_up.get("ok", false)), "B: unbound upload should fail")

	identity.call("claim_local_saves_for_user", "user_a")
	# Skip legacy flat migration into smoke root so Device A starts truly empty.
	asp.call("open_save_context", "user_a", {"legacy_owner": "other_device", "legacy_mismatch": true, "reload": false})
	# Empty Device A start → bootstrap hold routes path_for to quarantine.
	_assert(bool(asp.call("is_cloud_bootstrap_hold")), "B: empty bind should hold bootstrap")
	_assert(not bool(cloud.call("is_gameplay_live")), "B: gameplay should not be live under hold")
	# Seed Device A progression directly into the real partition (not quarantine).
	var a_buildings: String = str(asp.call("partition_path", "buildings.cfg", "user_a"))
	var a_res: String = str(asp.call("partition_path", "resources.cfg", "user_a"))
	var seed := ConfigFile.new()
	seed.set_value("castle", "level", 8)
	seed.set_value("p3", "marker", "city_a_cloud")
	seed.save(a_buildings)
	var seed_r := ConfigFile.new()
	seed_r.set_value("resources", "food", 5555)
	seed_r.save(a_res)
	# Intentional first-device progress: release hold so path_for is live for subsequent steps.
	asp.call("set_cloud_bootstrap_hold", false)
	_assert(bool(cloud.call("is_gameplay_live")), "B: gameplay live after hold release")

	var foreign: Dictionary = await cloud.call("upload_user_partition", "user_other")
	_assert(not bool(foreign.get("ok", false)), "B: foreign partition upload should fail")
	_assert(str(foreign.get("error", "")) == "CLOUD_SAVE_REJECT_FOREIGN_PARTITION", "B: wrong foreign code")

	print("[ACCOUNT P3] C upload current partition (smoke store)")
	var up: Dictionary = await cloud.call("upload_current_partition")
	_assert(bool(up.get("ok", false)), "C: upload failed: %s" % str(up))
	_assert(int(up.get("revision", 0)) >= 1, "C: revision missing")
	_assert(int(up.get("file_count", 0)) >= 2, "C: expected buildings+resources")
	_assert(str(up.get("storage_version", "")) != "", "C: storage version missing")

	print("[ACCOUNT P3] D schema / corrupt rejection")
	var bad_schema := {"schema_version": 99, "user_id": "user_a", "revision": 1, "files": {}, "checksum": ""}
	var v_bad: Dictionary = cloud.call("validate_payload", bad_schema, "user_a")
	_assert(not bool(v_bad.get("ok", false)), "D: future schema should fail")
	_assert(str(v_bad.get("error", "")) == "CLOUD_SAVE_SCHEMA_UNSUPPORTED", "D: wrong schema code")
	var corrupt := {"schema_version": 1, "user_id": "user_a", "revision": 1, "files": {"buildings.cfg": "aaa"}, "checksum": "nope"}
	var v_c: Dictionary = cloud.call("validate_payload", corrupt, "user_a")
	_assert(not bool(v_c.get("ok", false)), "D: corrupt checksum should fail")
	_assert(str(v_c.get("error", "")) == "CLOUD_SAVE_CORRUPT", "D: wrong corrupt code")
	var built: Dictionary = cloud.call("build_payload_for_user", "user_a")
	_assert(bool(built.get("ok", false)), "D: rebuild failed")
	var good_payload: Dictionary = (built.get("payload", {}) as Dictionary).duplicate(true)
	good_payload["user_id"] = "user_x"
	var v_own: Dictionary = cloud.call("validate_payload", good_payload, "user_a")
	_assert(not bool(v_own.get("ok", false)), "D: owner mismatch should fail")
	_assert(str(v_own.get("error", "")) == "CLOUD_SAVE_OWNER_MISMATCH", "D: wrong owner code")

	print("[ACCOUNT P3] E conflict policy matrix")
	var d1: Dictionary = cloud.call("resolve_conflict", {"local_empty": true, "local_revision": 0}, {"revision": 3, "updated_unix": 100})
	_assert(str(d1.get("action", "")) == "use_cloud", "E: empty local should use cloud")
	var d2: Dictionary = cloud.call("resolve_conflict", {"local_empty": false, "local_revision": 5, "local_updated_unix": 50, "last_uploaded_revision": 4}, {"revision": 3, "updated_unix": 40})
	_assert(str(d2.get("action", "")) == "upload", "E: local newer should upload")
	var d3: Dictionary = cloud.call("resolve_conflict", {"local_empty": false, "local_revision": 2, "local_updated_unix": 50, "last_uploaded_revision": 2}, {"revision": 5, "updated_unix": 90})
	_assert(str(d3.get("action", "")) == "use_cloud", "E: cloud newer should use cloud")
	var d4: Dictionary = cloud.call("resolve_conflict", {"local_empty": false, "local_revision": 2, "local_updated_unix": 200, "last_uploaded_revision": 2}, {"revision": 5, "updated_unix": 90})
	_assert(str(d4.get("action", "")) == "block", "E: ambiguous should block")
	_assert(str(d4.get("code", "")) == "CLOUD_SAVE_CONFLICT_AMBIGUOUS", "E: wrong ambiguous code")

	print("[ACCOUNT P3] F Device B empty partition restores before gameplay live (no restart)")
	# Wipe ALL local progress markers so partition is truly empty (migration may have copied many).
	for fname: String in cloud.call("list_cloud_files"):
		var p: String = str(asp.call("partition_path", str(fname), "user_a"))
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for extra: String in ["alliance.cfg", "resource_tiles.cfg", "bag.cfg", "troops.cfg", "heroes.cfg", "quests.cfg", "marches.cfg", "construction_queue.cfg", "research_queue.cfg"]:
		var pe: String = str(asp.call("partition_path", extra, "user_a"))
		if pe != "" and FileAccess.file_exists(pe):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(pe))
	var meta_path: String = str(asp.call("partition_path", "_cloud_sync_meta.cfg", "user_a"))
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	# Re-bind as Device B first launch: empty → bootstrap hold, not live.
	asp.call("close_save_context")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other_device", "legacy_mismatch": true, "reload": false})
	_assert(not bool(asp.call("has_account_gameplay_progress", "user_a")), "F: local should be empty")
	_assert(bool(asp.call("is_cloud_bootstrap_hold")), "F: Device B should hold until restore")
	_assert(not bool(cloud.call("is_gameplay_live")), "F: not live before sync")
	# path_for must not target the real partition while held (prevents empty overwrite).
	var held_path: String = str(asp.call("path_for", "buildings.cfg"))
	var real_path: String = str(asp.call("partition_path", "buildings.cfg", "user_a"))
	_assert(held_path != real_path, "F: path_for must quarantine under hold")
	# Quarantine defaults writing here must not clobber cloud restore target.
	var poison := ConfigFile.new()
	poison.set_value("p3", "marker", "empty_device_b_poison")
	poison.save(held_path)
	_assert(not FileAccess.file_exists(real_path) or _marker(real_path) != "empty_device_b_poison", "F: poison leaked into partition")

	var sync_b: Dictionary = await cloud.call("sync_after_auth")
	_assert(bool(sync_b.get("ok", false)), "F: sync_after_auth failed: %s" % str(sync_b))
	_assert(str(sync_b.get("action", "")) == "use_cloud", "F: expected use_cloud got %s" % str(sync_b))
	_assert(not bool(asp.call("is_cloud_bootstrap_hold")), "F: hold released after restore")
	_assert(bool(cloud.call("is_gameplay_live")), "F: gameplay live after restore without restart")
	_assert(bool(sync_b.get("gameplay_live", false)), "F: sync result should report gameplay_live")
	var restored_cfg := ConfigFile.new()
	_assert(restored_cfg.load(a_buildings) == OK, "F: buildings not restored")
	_assert(str(restored_cfg.get_value("p3", "marker", "")) == "city_a_cloud", "F: marker mismatch")
	_assert(int(restored_cfg.get_value("castle", "level", 0)) == 8, "F: castle level mismatch")
	var restored_r := ConfigFile.new()
	restored_r.load(a_res)
	_assert(int(restored_r.get_value("resources", "food", 0)) == 5555, "F: food not restored")
	# Empty-state poison must not have been uploaded / restored as authoritative.
	_assert(str(restored_cfg.get_value("p3", "marker", "")) != "empty_device_b_poison", "F: empty overwrite occurred")

	print("[ACCOUNT P3] G progress B, upload newer, A gets newer cloud")
	seed.set_value("p3", "marker", "city_a_cloud_v2")
	seed.set_value("castle", "level", 11)
	seed.save(a_buildings)
	cloud.call("mark_dirty", "device_b_progress")
	var up2: Dictionary = await cloud.call("upload_current_partition")
	_assert(bool(up2.get("ok", false)), "G: second upload failed: %s" % str(up2))
	# Wipe local again and restore — should get v2.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(a_buildings))
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	asp.call("close_save_context")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other_device", "legacy_mismatch": true, "reload": false})
	var sync_c: Dictionary = await cloud.call("sync_after_auth")
	_assert(bool(sync_c.get("ok", false)), "G: restore v2 failed: %s" % str(sync_c))
	var v2 := ConfigFile.new()
	v2.load(a_buildings)
	_assert(str(v2.get_value("p3", "marker", "")) == "city_a_cloud_v2", "G: v2 marker missing")
	_assert(int(v2.get_value("castle", "level", 0)) == 11, "G: v2 level missing")

	print("[ACCOUNT P3] H switching accounts does not cross-restore")
	asp.call("open_save_context", "user_b", {"legacy_owner": "user_a", "legacy_mismatch": true, "reload": false})
	for fname2: String in ["buildings.cfg", "resources.cfg"]:
		var pb: String = str(asp.call("partition_path", fname2, "user_b"))
		if FileAccess.file_exists(pb):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(pb))
	var dl: Dictionary = await cloud.call("download_cloud_save", "user_a")
	_assert(bool(dl.get("exists", false)), "H: cloud missing")
	var cross: Dictionary = cloud.call("restore_payload_to_partition", dl.get("payload", {}), "user_b")
	_assert(not bool(cross.get("ok", false)), "H: cross-restore into B should fail owner check")
	_assert(str(cross.get("error", "")) == "CLOUD_SAVE_OWNER_MISMATCH", "H: expected owner mismatch")
	_assert(not FileAccess.file_exists(str(asp.call("partition_path", "buildings.cfg", "user_b"))) \
		or _marker(str(asp.call("partition_path", "buildings.cfg", "user_b"))) != "city_a_cloud_v2",
		"H: B received A city")

	print("[ACCOUNT P3] I ambiguous conflict blocks overwrite")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other_device", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	var amb: Dictionary = cloud.call(
		"resolve_conflict",
		{"local_empty": false, "local_revision": 2, "local_updated_unix": 500, "last_uploaded_revision": 2},
		{"revision": 9, "updated_unix": 100}
	)
	_assert(str(amb.get("action")) == "block", "I: expected block")

	print("[ACCOUNT P3] I2 Device A/B stale OCC write does not silent-overwrite")
	# Ensure partition has progress + known cloud version from last upload.
	seed.set_value("p3", "marker", "city_before_occ")
	seed.save(a_buildings)
	var up_occ_base: Dictionary = await cloud.call("upload_current_partition")
	_assert(bool(up_occ_base.get("ok", false)), "I2: base upload failed: %s" % str(up_occ_base))
	var stale_version: String = str(up_occ_base.get("storage_version", ""))
	_assert(stale_version != "", "I2: missing base version")
	# Device A remote write advances cloud version without updating this device's meta.
	var remote_payload: Dictionary = (cloud.call("build_payload_for_user", "user_a").get("payload", {}) as Dictionary).duplicate(true)
	remote_payload["revision"] = int(remote_payload.get("revision", 1)) + 10
	remote_payload["updated_unix"] = int(Time.get_unix_time_from_system()) + 100
	remote_payload["user_id"] = "user_a"
	var files_rp: Dictionary = remote_payload.get("files", {})
	# Mark remote city distinctly.
	var remote_b := ConfigFile.new()
	remote_b.set_value("castle", "level", 99)
	remote_b.set_value("p3", "marker", "device_a_won")
	var tmp_remote: String = "user://_p3_occ_remote_buildings.cfg"
	remote_b.save(tmp_remote)
	files_rp["buildings.cfg"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(tmp_remote))
	remote_payload["files"] = files_rp
	remote_payload["checksum"] = _checksum(files_rp)
	var forced: Dictionary = cloud.call("smoke_force_remote_write", remote_payload)
	_assert(bool(forced.get("ok", false)), "I2: force remote failed")
	_assert(str(forced.get("version", "")) != stale_version, "I2: remote version should advance")
	# Local still thinks stale_version — attempt upload must OCC-resolve, not blank-overwrite.
	seed.set_value("p3", "marker", "stale_device_b_attempt")
	seed.set_value("castle", "level", 3)
	seed.save(a_buildings)
	cloud.call("mark_dirty", "stale_b")
	var stale_up: Dictionary = await cloud.call("upload_current_partition")
	# Policy: cloud revision higher → use_cloud (Device A wins). Must not leave B's stale city as cloud.
	_assert(bool(stale_up.get("occ_resolved", false)) or str(stale_up.get("action", "")) == "use_cloud" \
		or str(stale_up.get("error", "")) == "CLOUD_SAVE_OCC_CONFLICT" \
		or bool(stale_up.get("ok", false)), "I2: unexpected OCC result: %s" % str(stale_up))
	var after_dl: Dictionary = await cloud.call("download_cloud_save", "user_a")
	_assert(bool(after_dl.get("exists", false)), "I2: cloud missing after OCC")
	var after_payload: Dictionary = after_dl.get("payload", {})
	var after_files: Dictionary = after_payload.get("files", {})
	_assert(after_files.has("buildings.cfg"), "I2: buildings missing in cloud")
	var decoded: PackedByteArray = Marshalls.base64_to_raw(str(after_files["buildings.cfg"]))
	var dec_path := "user://_p3_occ_decoded.cfg"
	var df := FileAccess.open(dec_path, FileAccess.WRITE)
	df.store_buffer(decoded)
	df.close()
	var after_cfg := ConfigFile.new()
	after_cfg.load(dec_path)
	_assert(str(after_cfg.get_value("p3", "marker", "")) != "stale_device_b_attempt", "I2: stale B silently overwrote A")
	_assert(str(after_cfg.get_value("p3", "marker", "")) == "device_a_won" \
		or bool(stale_up.get("occ_resolved", false)), "I2: expected A cloud preserved or OCC resolve")

	print("[ACCOUNT P3] J payload size metrics (no player data dump)")
	var sizes: Dictionary = cloud.call("measure_payload_sizes", after_payload)
	_assert(bool(sizes.get("ok", false)), "J: size measure failed: %s" % str(sizes))
	print(
		"[ACCOUNT P3] J raw_bytes=%s b64_files=%s encoded_object=%s soft_limit=%s headroom=%s comfortable=%s"
		% [
			str(sizes.get("raw_progression_bytes", 0)),
			str(sizes.get("base64_files_bytes", 0)),
			str(sizes.get("encoded_object_bytes", 0)),
			str(sizes.get("nakama_soft_limit_bytes", 0)),
			str(sizes.get("headroom_vs_soft_limit", 0)),
			str(sizes.get("within_comfortable_budget", false)),
		]
	)

	# Cleanup smoke isolation and rebind live account.
	cloud.call("end_smoke_isolation")
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	if nc != null and bool(nc.call("is_authenticated")):
		identity.call("on_authenticated", str(nc.call("get_user_id")), str(nc.call("get_last_auth_source")))

	print("[ACCOUNT P3] K live optional download + size (same user; no mutate unless already bound)")
	if nc != null and bool(nc.call("is_authenticated")) and asp != null and bool(asp.call("is_bound")):
		var live_uid: String = str(nc.call("get_user_id"))
		if str(asp.call("get_active_user_id")) == live_uid:
			var live_dl: Dictionary = await cloud.call("download_cloud_save", live_uid)
			_assert(bool(live_dl.get("ok", false)), "K: live download failed: %s" % str(live_dl))
			print("[ACCOUNT P3] K live exists=%s user=%s collection=crownspire_player_save key=progression_v1" \
				% [str(live_dl.get("exists", false)), live_uid.substr(0, 8)])
			if bool(live_dl.get("exists", false)):
				var live_sizes: Dictionary = cloud.call("measure_payload_sizes", live_dl.get("payload", {}))
				if bool(live_sizes.get("ok", false)):
					print(
						"[ACCOUNT P3] K live raw_bytes=%s b64_files=%s encoded_object=%s headroom=%s comfortable=%s"
						% [
							str(live_sizes.get("raw_progression_bytes", 0)),
							str(live_sizes.get("base64_files_bytes", 0)),
							str(live_sizes.get("encoded_object_bytes", 0)),
							str(live_sizes.get("headroom_vs_soft_limit", 0)),
							str(live_sizes.get("within_comfortable_budget", false)),
						]
					)
			# Non-destructive: do not upload in hardening run (preserve production test object as-is).
		else:
			print("[ACCOUNT P3] K skipped — auth/partition mismatch")
	else:
		print("[ACCOUNT P3] K skipped — not authenticated")

	if _fail.is_empty():
		print("[ACCOUNT P3] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ACCOUNT P3] FAIL: %s" % f)
		quit(1)


func _marker(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value("p3", "marker", ""))


func _checksum(files: Dictionary) -> String:
	var keys: Array = files.keys()
	keys.sort()
	var acc := ""
	for k: Variant in keys:
		acc += str(k) + ":" + str(files[k]) + ";"
	return acc.sha256_text()
