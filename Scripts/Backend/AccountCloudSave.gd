extends Node

## Crownspire Phase 3 — cloud save / restore foundation.
## Stores account-owned partition progression in Nakama Storage under the
## authenticated session user_id. Does not deploy server RPCs.
## Never uploads __unbound__ or another user's partition.

signal cloud_sync_completed(result: Dictionary)
signal cloud_conflict(code: String, detail: Dictionary)
signal cloud_restore_completed(result: Dictionary)

const COLLECTION := "crownspire_player_save"
const STORAGE_KEY := "progression_v1"
const SCHEMA_VERSION := 1
const META_FILE := "_cloud_sync_meta.cfg"
const CONFLICT_AMBIGUOUS := "CLOUD_SAVE_CONFLICT_AMBIGUOUS"
const CONFLICT_CORRUPT := "CLOUD_SAVE_CORRUPT"
const CONFLICT_OWNER := "CLOUD_SAVE_OWNER_MISMATCH"
const CONFLICT_SCHEMA := "CLOUD_SAVE_SCHEMA_UNSUPPORTED"
const ERR_UNBOUND := "CLOUD_SAVE_REJECT_UNBOUND"
const ERR_FOREIGN := "CLOUD_SAVE_REJECT_FOREIGN_PARTITION"
const ERR_NOT_AUTH := "CLOUD_SAVE_NOT_AUTHENTICATED"

## Progression files uploaded/restored. Excludes shared-world + server-authoritative caches.
const CLOUD_FILES: PackedStringArray = [
	"buildings.cfg",
	"resources.cfg",
	"troops.cfg",
	"heroes.cfg",
	"research_queue.cfg",
	"quests.cfg",
	"bag.cfg",
	"construction_queue.cfg",
	"marches.cfg",
	"mail.cfg",
	"tutorial.cfg",
	"tutorial_grants.cfg",
	"wildling_spawns.cfg",
	"sanctuary.cfg",
	"healing_queue.cfg",
	"events.cfg",
	"savegame.save",
]

## Explicitly excluded from cloud blob (local-only or server-derived).
const CLOUD_EXCLUDED: PackedStringArray = [
	"resource_tiles.cfg", ## shared/world-derived occupancy
	"alliance.cfg", ## Nakama Groups / AllianceBackend authoritative
	"alliance_lairs_runtime.cfg", ## kingdom shared runtime
	"chat_display_name.cfg",
	"chat_moderation_local.cfg",
	"chat_reports_pending.cfg",
	"dm_conversations.cfg",
]

const UPLOAD_DEBOUNCE_SEC := 45.0
const PERIODIC_SYNC_SEC := 300.0
const ERR_OCC := "CLOUD_SAVE_OCC_CONFLICT"

## Nakama Storage object soft limit guidance (bytes). Official docs historically ~16MB;
## keep a conservative operational budget for single-object growth.
const NAKAMA_STORAGE_SOFT_LIMIT_BYTES := 16 * 1024 * 1024
const COMFORTABLE_PAYLOAD_BUDGET_BYTES := 2 * 1024 * 1024

var _smoke_mode: bool = false
var _smoke_cloud: Dictionary = {} ## in-memory fake storage for smokes {value, version}
var _smoke_version_seq: int = 0
var _upload_timer: Timer = null
var _periodic_timer: Timer = null
var _dirty: bool = false
var _syncing: bool = false
var _last_result: Dictionary = {}
var _blocked_conflict: Dictionary = {}
var _pending_flush: bool = false ## set on pause/close; local disk remains source of truth
var _bootstrap_complete: bool = false


func _ready() -> void:
	_ensure_timers()
	call_deferred("_bind_signals")


func begin_smoke_isolation() -> void:
	_smoke_mode = true
	_smoke_cloud.clear()
	_smoke_version_seq = 0
	_dirty = false
	_syncing = false
	_pending_flush = false
	_bootstrap_complete = true ## smokes drive sync explicitly
	_last_result = {}
	_blocked_conflict = {}
	if _upload_timer != null:
		_upload_timer.stop()


func end_smoke_isolation() -> void:
	_smoke_mode = false
	_smoke_cloud.clear()
	_dirty = false
	_pending_flush = false
	_blocked_conflict = {}


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_blocked_conflict() -> Dictionary:
	return _blocked_conflict.duplicate(true)


func has_blocked_conflict() -> bool:
	return not _blocked_conflict.is_empty()


func list_cloud_files() -> PackedStringArray:
	return CLOUD_FILES.duplicate()


func list_excluded_files() -> PackedStringArray:
	return CLOUD_EXCLUDED.duplicate()


## True once empty-partition cloud bootstrap has finished (or local already had progress).
func is_gameplay_live() -> bool:
	if has_blocked_conflict():
		return false
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return false
	if bool(asp.call("is_cloud_bootstrap_hold")):
		return false
	return true


## Player-facing conflict resolution after ambiguous local/cloud divergence.
## Does not auto-overwrite: requires explicit "use_cloud" or "use_local".
func apply_conflict_choice(choice: String) -> Dictionary:
	var pick: String = choice.strip_edges().to_lower()
	if pick == "keep_local" or pick == "keep_device":
		pick = "use_local"
	if pick != "use_cloud" and pick != "use_local":
		return {"ok": false, "error": "invalid_choice", "message": "Choose use_cloud or use_local."}
	if not has_blocked_conflict():
		return {"ok": false, "error": "no_conflict", "message": "No blocked cloud conflict to resolve."}
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return _fail(ERR_UNBOUND)
	var uid: String = str(asp.call("get_active_user_id"))
	if uid.is_empty() or uid == AccountSavePaths.UNBOUND_SENTINEL:
		return _fail(ERR_UNBOUND)
	if not _smoke_mode:
		var auth: String = _session_user_id()
		if auth.is_empty():
			return _fail(ERR_NOT_AUTH)
		if auth != uid:
			return _fail(ERR_FOREIGN)

	# Clear sticky block so restore/upload can proceed; restore only on use_cloud.
	var prior: Dictionary = _blocked_conflict.duplicate(true)
	_blocked_conflict.clear()

	if pick == "use_cloud":
		var cloud: Dictionary = await download_cloud_save(uid)
		if not bool(cloud.get("ok", false)):
			_blocked_conflict = prior
			return {"ok": false, "error": str(cloud.get("error", "download_failed")), "choice": pick, "download": cloud}
		if not bool(cloud.get("exists", false)):
			_blocked_conflict = prior
			return {"ok": false, "error": "cloud_missing", "choice": pick}
		var payload: Dictionary = cloud.get("payload", {})
		var restored: Dictionary = restore_payload_to_partition(payload, uid)
		if not bool(restored.get("ok", false)):
			_blocked_conflict = prior
			return {"ok": false, "error": str(restored.get("error", "restore_failed")), "choice": pick, "restore": restored}
		if str(cloud.get("version", "")) != "":
			var m: Dictionary = _read_local_meta(uid)
			m["storage_version"] = str(cloud.get("version", ""))
			_write_local_meta(uid, m)
		_finish_bootstrap(true)
		var ok_cloud := {
			"ok": true,
			"choice": "use_cloud",
			"action": "use_cloud",
			"restore": restored,
			"gameplay_live": is_gameplay_live(),
		}
		_last_result = ok_cloud
		cloud_sync_completed.emit(ok_cloud)
		return ok_cloud

	# use_local — keep device partition; adopt cloud OCC version then upload local as newer.
	var cloud_l: Dictionary = await download_cloud_save(uid)
	if bool(cloud_l.get("ok", false)) and bool(cloud_l.get("exists", false)):
		var cloud_payload: Dictionary = cloud_l.get("payload", {})
		var cloud_rev: int = int(cloud_payload.get("revision", 0))
		var m2: Dictionary = _read_local_meta(uid)
		if str(cloud_l.get("version", "")) != "":
			m2["storage_version"] = str(cloud_l.get("version", ""))
		var local_rev: int = int(m2.get("local_revision", 0))
		m2["local_revision"] = maxi(local_rev, cloud_rev) + 1
		m2["local_updated_unix"] = int(Time.get_unix_time_from_system())
		_write_local_meta(uid, m2)
	var up: Dictionary = await upload_user_partition(uid)
	if not bool(up.get("ok", false)):
		# Upload may re-block; preserve whatever block state upload set, else restore prior.
		if not has_blocked_conflict():
			_blocked_conflict = prior
		return {
			"ok": false,
			"error": str(up.get("error", CONFLICT_AMBIGUOUS)),
			"choice": "use_local",
			"upload": up,
			"blocked": has_blocked_conflict(),
		}
	_finish_bootstrap(true)
	var ok_local := {
		"ok": true,
		"choice": "use_local",
		"action": "upload",
		"upload": up,
		"gameplay_live": is_gameplay_live(),
	}
	_last_result = ok_local
	cloud_sync_completed.emit(ok_local)
	return ok_local


## Smoke / UI helper — clear sticky block only (does not mutate saves).
func clear_blocked_conflict() -> void:
	_blocked_conflict.clear()


## Smoke-only: simulate another device writing cloud without updating this device's meta.
func smoke_force_remote_write(payload: Dictionary) -> Dictionary:
	if not _smoke_mode:
		return {"ok": false, "error": "not_smoke"}
	_smoke_version_seq += 1
	var ver: String = "smoke-remote-%d" % _smoke_version_seq
	_smoke_cloud = {
		"value": payload.duplicate(true),
		"version": ver,
	}
	return {"ok": true, "version": ver}


## Measure payload sizes without printing file contents.
func measure_payload_sizes(payload: Dictionary = {}) -> Dictionary:
	var p: Dictionary = payload
	if p.is_empty():
		var built: Dictionary = build_payload_from_active_partition()
		if not bool(built.get("ok", false)):
			return built
		p = built.get("payload", {})
	var files: Dictionary = p.get("files", {})
	var raw_bytes: int = 0
	var b64_bytes: int = 0
	for k: Variant in files.keys():
		var b64: String = str(files[k])
		b64_bytes += b64.length()
		raw_bytes += Marshalls.base64_to_raw(b64).size()
	var json_text: String = JSON.stringify(p)
	var encoded_object_bytes: int = json_text.length()
	return {
		"ok": true,
		"file_count": files.size(),
		"raw_progression_bytes": raw_bytes,
		"base64_files_bytes": b64_bytes,
		"encoded_object_bytes": encoded_object_bytes,
		"nakama_soft_limit_bytes": NAKAMA_STORAGE_SOFT_LIMIT_BYTES,
		"comfortable_budget_bytes": COMFORTABLE_PAYLOAD_BUDGET_BYTES,
		"headroom_vs_soft_limit": NAKAMA_STORAGE_SOFT_LIMIT_BYTES - encoded_object_bytes,
		"within_comfortable_budget": encoded_object_bytes < COMFORTABLE_PAYLOAD_BUDGET_BYTES,
	}


## Mark local progression dirty → debounced upload.
func mark_dirty(reason: String = "") -> void:
	if not _can_sync_now():
		return
	_dirty = true
	var asp: Node = _asp()
	if asp != null and bool(asp.call("is_bound")):
		var uid: String = str(asp.call("get_active_user_id"))
		var meta: Dictionary = _read_local_meta(uid)
		var rev: int = maxi(1, int(meta.get("local_revision", 0)) + 1)
		_write_local_meta(uid, {
			"local_revision": rev,
			"local_updated_unix": int(Time.get_unix_time_from_system()),
			"last_uploaded_revision": int(meta.get("last_uploaded_revision", 0)),
			"last_cloud_revision": int(meta.get("last_cloud_revision", 0)),
			"last_cloud_updated_unix": int(meta.get("last_cloud_updated_unix", 0)),
			"storage_version": str(meta.get("storage_version", "")),
		})
	if reason != "":
		print("[AccountCloudSave] dirty (%s)" % reason)
	_ensure_timers()
	_upload_timer.start(UPLOAD_DEBOUNCE_SEC)


func request_upload_now() -> Dictionary:
	return await upload_current_partition()


## Build canonical payload from the active bound partition only.
func build_payload_from_active_partition() -> Dictionary:
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return {"ok": false, "error": ERR_UNBOUND}
	var uid: String = str(asp.call("get_active_user_id")).strip_edges()
	if uid.is_empty() or uid == AccountSavePaths.UNBOUND_SENTINEL:
		return {"ok": false, "error": ERR_UNBOUND}
	var root: String = str(asp.call("partition_root", uid))
	if root.find(AccountSavePaths.UNBOUND_SENTINEL) >= 0:
		return {"ok": false, "error": ERR_UNBOUND}
	return _build_payload_for_user(uid)


func build_payload_for_user(user_id: String) -> Dictionary:
	return _build_payload_for_user(user_id.strip_edges())


func validate_payload(payload: Dictionary, expected_user_id: String = "") -> Dictionary:
	if payload.is_empty():
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "empty"}
	if not payload.has("schema_version") or not payload.has("files"):
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "missing_fields"}
	var schema: int = int(payload.get("schema_version", 0))
	if schema < 1:
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "bad_schema"}
	if schema > SCHEMA_VERSION:
		return {"ok": false, "error": CONFLICT_SCHEMA, "schema": schema}
	var owner: String = str(payload.get("user_id", "")).strip_edges()
	var expect: String = expected_user_id.strip_edges()
	if expect != "" and owner != "" and owner != expect:
		return {"ok": false, "error": CONFLICT_OWNER, "payload_user": owner, "expected": expect}
	var files = payload.get("files", {})
	if typeof(files) != TYPE_DICTIONARY:
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "files_not_dict"}
	var checksum: String = str(payload.get("checksum", ""))
	if checksum != "":
		var calc: String = _checksum_files(files as Dictionary)
		if calc != checksum:
			return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "checksum_mismatch"}
	var rev: int = int(payload.get("revision", 0))
	if rev < 1:
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "bad_revision"}
	return {"ok": true, "schema_version": schema, "revision": rev, "user_id": owner}


## Deterministic conflict decision (no I/O).
## Returns {action: use_local|use_cloud|upload|noop|block, code?}
func resolve_conflict(local_meta: Dictionary, cloud_payload: Dictionary) -> Dictionary:
	var local_rev: int = int(local_meta.get("local_revision", 0))
	var local_updated: int = int(local_meta.get("local_updated_unix", 0))
	var uploaded_rev: int = int(local_meta.get("last_uploaded_revision", 0))
	var cloud_rev: int = int(cloud_payload.get("revision", 0))
	var cloud_updated: int = int(cloud_payload.get("updated_unix", 0))
	var local_empty: bool = bool(local_meta.get("local_empty", false))

	if local_empty and cloud_rev >= 1:
		return {"action": "use_cloud", "reason": "empty_local"}
	if cloud_rev < 1:
		return {"action": "upload" if local_rev >= 1 or not local_empty else "noop", "reason": "no_cloud"}

	if cloud_rev > local_rev:
		# Cloud claims newer revision.
		if local_updated > cloud_updated and local_rev >= uploaded_rev and local_rev > 0:
			# Local wall-clock newer but revision behind → ambiguous.
			return {"action": "block", "code": CONFLICT_AMBIGUOUS, "reason": "rev_cloud_higher_but_local_newer_time"}
		return {"action": "use_cloud", "reason": "cloud_newer_revision"}

	if local_rev > cloud_rev:
		return {"action": "upload", "reason": "local_newer_revision"}

	# Same revision.
	if local_updated > cloud_updated + 2:
		return {"action": "upload", "reason": "same_rev_local_newer_time"}
	if cloud_updated > local_updated + 2:
		# Same rev but cloud timestamp ahead without rev bump — ambiguous.
		return {"action": "block", "code": CONFLICT_AMBIGUOUS, "reason": "same_rev_cloud_newer_time"}
	return {"action": "noop", "reason": "in_sync"}


func upload_current_partition() -> Dictionary:
	if _syncing:
		return {"ok": false, "error": "busy"}
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return _fail(ERR_UNBOUND)
	var uid: String = str(asp.call("get_active_user_id"))
	return await upload_user_partition(uid)


func upload_user_partition(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	var asp: Node = _asp()
	if asp == null:
		return _fail("missing_AccountSavePaths")
	if uid.is_empty() or uid == AccountSavePaths.UNBOUND_SENTINEL:
		return _fail(ERR_UNBOUND)
	if str(asp.call("partition_root", uid)).find(AccountSavePaths.UNBOUND_SENTINEL) >= 0:
		return _fail(ERR_UNBOUND)
	if bool(asp.call("is_bound")) and str(asp.call("get_active_user_id")) != uid:
		return _fail(ERR_FOREIGN)

	var auth_uid: String = _session_user_id()
	if not _smoke_mode:
		if auth_uid.is_empty():
			return _fail(ERR_NOT_AUTH)
		if auth_uid != uid:
			return _fail(ERR_FOREIGN)

	var built: Dictionary = _build_payload_for_user(uid)
	if not bool(built.get("ok", false)):
		return built
	var payload: Dictionary = built.get("payload", {})
	# Force ownership to bound partition user in smoke; session user in live.
	if _smoke_mode:
		payload["user_id"] = uid
	elif auth_uid != "":
		payload["user_id"] = auth_uid

	var valid: Dictionary = validate_payload(payload, uid if _smoke_mode else auth_uid)
	if not bool(valid.get("ok", false)):
		return valid

	_syncing = true
	var write_res: Dictionary
	if _smoke_mode:
		write_res = _smoke_write(payload)
	else:
		write_res = await _nakama_write(payload)
	_syncing = false

	if bool(write_res.get("conflict", false)):
		# Never force-write with empty version. Re-download and apply conflict policy.
		var resolved: Dictionary = await _handle_occ_conflict(uid, payload)
		_last_result = resolved
		cloud_sync_completed.emit(resolved)
		return resolved

	if not bool(write_res.get("ok", false)):
		_last_result = write_res
		cloud_sync_completed.emit(write_res)
		return write_res

	_write_local_meta(uid, {
		"local_revision": int(payload.get("revision", 0)),
		"local_updated_unix": int(payload.get("updated_unix", 0)),
		"last_uploaded_revision": int(payload.get("revision", 0)),
		"last_cloud_revision": int(payload.get("revision", 0)),
		"last_cloud_updated_unix": int(payload.get("updated_unix", 0)),
		"storage_version": str(write_res.get("version", "")),
		"last_sync_unix": int(Time.get_unix_time_from_system()),
	})
	_dirty = false
	_pending_flush = false
	_blocked_conflict.clear()
	var ok_res := {
		"ok": true,
		"uploaded": true,
		"revision": int(payload.get("revision", 0)),
		"user_id": str(payload.get("user_id", "")),
		"file_count": int((payload.get("files", {}) as Dictionary).size()),
		"storage_version": str(write_res.get("version", "")),
	}
	_last_result = ok_res
	print(
		"[AccountCloudSave] uploaded revision=%d files=%d user=%s"
		% [int(ok_res.get("revision", 0)), int(ok_res.get("file_count", 0)), _short(str(ok_res.get("user_id", "")))]
	)
	cloud_sync_completed.emit(ok_res)
	return ok_res


func download_cloud_save(user_id: String = "") -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		uid = _session_user_id()
	if uid.is_empty() and _smoke_mode:
		var asp: Node = _asp()
		if asp != null:
			uid = str(asp.call("get_active_user_id"))
	if uid.is_empty():
		return _fail(ERR_NOT_AUTH)
	if not _smoke_mode:
		var auth: String = _session_user_id()
		if auth != uid:
			return _fail(ERR_FOREIGN)

	if _smoke_mode:
		if _smoke_cloud.is_empty():
			return {"ok": true, "exists": false}
		return {
			"ok": true,
			"exists": true,
			"payload": (_smoke_cloud.get("value", {}) as Dictionary).duplicate(true),
			"version": str(_smoke_cloud.get("version", "")),
		}

	return await _nakama_read(uid)


## Restore cloud payload into the bound user's partition (or explicit uid when smoke).
func restore_payload_to_partition(payload: Dictionary, user_id: String = "") -> Dictionary:
	var asp: Node = _asp()
	if asp == null:
		return _fail("missing_AccountSavePaths")
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		uid = str(asp.call("get_active_user_id"))
	if uid.is_empty() or uid == AccountSavePaths.UNBOUND_SENTINEL:
		return _fail(ERR_UNBOUND)
	if bool(asp.call("is_bound")) and str(asp.call("get_active_user_id")) != uid:
		return _fail(ERR_FOREIGN)

	var valid: Dictionary = validate_payload(payload, uid)
	if not bool(valid.get("ok", false)):
		return valid

	var files: Dictionary = payload.get("files", {})
	asp.call("ensure_partition", uid)
	var written: PackedStringArray = []
	for file_name: Variant in files.keys():
		var name: String = str(file_name)
		if name not in CLOUD_FILES:
			continue
		if name in CLOUD_EXCLUDED:
			continue
		var b64: String = str(files[name])
		if b64.is_empty():
			continue
		var path: String = str(asp.call("partition_path", name, uid))
		if path.is_empty() or path.find(AccountSavePaths.UNBOUND_SENTINEL) >= 0:
			return _fail(ERR_UNBOUND)
		var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
		var err: Error = _write_bytes(path, bytes)
		if err != OK:
			return {"ok": false, "error": "write_failed", "file": name, "code": err}
		written.append(name)

	_write_local_meta(uid, {
		"local_revision": int(payload.get("revision", 0)),
		"local_updated_unix": int(payload.get("updated_unix", 0)),
		"last_uploaded_revision": int(payload.get("revision", 0)),
		"last_cloud_revision": int(payload.get("revision", 0)),
		"last_cloud_updated_unix": int(payload.get("updated_unix", 0)),
		"last_restore_unix": int(Time.get_unix_time_from_system()),
	})
	var res := {
		"ok": true,
		"restored": true,
		"user_id": uid,
		"revision": int(payload.get("revision", 0)),
		"files": written,
	}
	_last_result = res
	print(
		"[AccountCloudSave] restored revision=%d files=%d user=%s"
		% [int(res.get("revision", 0)), written.size(), _short(uid)]
	)
	cloud_restore_completed.emit(res)
	return res


## After auth + partition bind: restore / upload / conflict as needed.
## Releases cloud bootstrap hold when finished so gameplay can go live without restart.
func sync_after_auth() -> Dictionary:
	if has_blocked_conflict():
		# Sticky conflict awaits explicit player choice — do not release hold / auto-overwrite.
		return {
			"ok": false,
			"error": CONFLICT_AMBIGUOUS,
			"blocked": _blocked_conflict.duplicate(true),
			"conflict": true,
			"needs_resolution": true,
		}
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return _fail(ERR_UNBOUND)
	var uid: String = str(asp.call("get_active_user_id"))
	if not _smoke_mode and _session_user_id() != uid:
		# Wait until auth user matches bound partition.
		return {"ok": false, "error": "auth_partition_mismatch", "retry": true}

	var local_empty: bool = not bool(asp.call("has_account_gameplay_progress", uid))
	var meta: Dictionary = _read_local_meta(uid)
	meta["local_empty"] = local_empty
	if int(meta.get("local_revision", 0)) < 1 and not local_empty:
		meta["local_revision"] = 1
		meta["local_updated_unix"] = _partition_newest_mtime(uid)

	var cloud: Dictionary = await download_cloud_save(uid)
	if not bool(cloud.get("ok", false)):
		# Network failure: if local already had progress, go live; if empty, stay held only when
		# we still expect a possible cloud restore — release hold so offline first-run can proceed.
		_finish_bootstrap(local_empty == false)
		return cloud
	# Persist OCC version from read when present.
	if bool(cloud.get("exists", false)) and str(cloud.get("version", "")) != "":
		var m2: Dictionary = _read_local_meta(uid)
		m2["storage_version"] = str(cloud.get("version", ""))
		_write_local_meta(uid, m2)

	if not bool(cloud.get("exists", false)):
		if local_empty:
			var noop := {"ok": true, "action": "noop", "reason": "empty_local_no_cloud"}
			_finish_bootstrap(true)
			return noop
		var up_res: Dictionary = await upload_user_partition(uid)
		_finish_bootstrap(true)
		return up_res

	var payload: Dictionary = cloud.get("payload", {})
	var valid: Dictionary = validate_payload(payload, uid)
	if not bool(valid.get("ok", false)):
		_blocked_conflict = valid
		cloud_conflict.emit(str(valid.get("error", CONFLICT_CORRUPT)), valid)
		return {
			"ok": false,
			"error": str(valid.get("error", CONFLICT_CORRUPT)),
			"conflict": true,
			"needs_resolution": true,
			"blocked": valid,
		}

	var decision: Dictionary = resolve_conflict(meta, payload)
	var action: String = str(decision.get("action", "noop"))
	match action:
		"use_cloud":
			var restored: Dictionary = restore_payload_to_partition(payload, uid)
			if bool(restored.get("ok", false)):
				# Capture storage version from download for future OCC writes.
				if str(cloud.get("version", "")) != "":
					var m3: Dictionary = _read_local_meta(uid)
					m3["storage_version"] = str(cloud.get("version", ""))
					_write_local_meta(uid, m3)
				_finish_bootstrap(true) ## releases hold + reloads once
			else:
				_finish_bootstrap(false)
			return {"ok": bool(restored.get("ok", false)), "action": "use_cloud", "restore": restored, "decision": decision, "gameplay_live": is_gameplay_live()}
		"upload":
			var up2: Dictionary = await upload_user_partition(uid)
			_finish_bootstrap(true)
			return up2
		"block":
			_blocked_conflict = decision
			cloud_conflict.emit(str(decision.get("code", CONFLICT_AMBIGUOUS)), decision)
			push_warning("[AccountCloudSave] %s — refusing automatic overwrite" % str(decision.get("code", CONFLICT_AMBIGUOUS)))
			# Keep bootstrap hold if active; do not auto-release while unresolved.
			return {
				"ok": false,
				"error": str(decision.get("code", CONFLICT_AMBIGUOUS)),
				"decision": decision,
				"conflict": true,
				"needs_resolution": true,
				"gameplay_live": is_gameplay_live(),
			}
		_:
			_finish_bootstrap(true)
			return {"ok": true, "action": "noop", "decision": decision, "gameplay_live": is_gameplay_live()}


func _finish_bootstrap(should_reload: bool) -> void:
	var asp: Node = _asp()
	var was_hold: bool = false
	if asp != null and asp.has_method("is_cloud_bootstrap_hold"):
		was_hold = bool(asp.call("is_cloud_bootstrap_hold"))
		asp.call("set_cloud_bootstrap_hold", false)
	_bootstrap_complete = true
	# Reload when cloud restore/upload changed partition files, or when leaving quarantine hold
	# so path_for switches from quarantine → real partition without requiring an app restart.
	if should_reload or was_hold:
		_reload_gameplay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _dirty:
			return
		_pending_flush = true
		# Local disk is already authoritative via each system's save_*. Network upload is
		# best-effort only: Godot does not guarantee async RPCs finish after pause/terminate.
		# Do NOT await here — awaiting in notification is unsafe and still won't finish on
		# abrupt mobile kill. Debounce timer may also be suspended while backgrounded.
		if _can_sync_now() and not _syncing:
			upload_current_partition()


func _bind_signals() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("account_state_changed"):
		if not identity.account_state_changed.is_connected(_on_account_state_changed):
			identity.account_state_changed.connect(_on_account_state_changed)
	var asp: Node = _asp()
	if asp != null and asp.has_signal("save_context_changed"):
		if not asp.save_context_changed.is_connected(_on_save_context_changed):
			asp.save_context_changed.connect(_on_save_context_changed)
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_signal("authenticated"):
		if not nc.authenticated.is_connected(_on_authenticated):
			nc.authenticated.connect(_on_authenticated)


func _on_authenticated() -> void:
	call_deferred("_deferred_auth_sync")


func _on_account_state_changed() -> void:
	pass


func _on_save_context_changed(user_id: String) -> void:
	if user_id.strip_edges() == "":
		return
	# Meaningful bind → consider sync after auth settles.
	call_deferred("_deferred_auth_sync")


func _deferred_auth_sync() -> void:
	if _smoke_mode:
		return
	# Email login owns sync_after_auth while AUTHENTICATING — avoid parallel race.
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_method("get_auth_phase"):
		if str(identity.call("get_auth_phase")) == "AUTHENTICATING":
			return
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return
	if str(asp.call("get_active_user_id")) != str(nc.call("get_user_id")):
		return
	var result: Dictionary = await sync_after_auth()
	_last_result = result
	if bool(result.get("ok", false)) and str(result.get("action", "")) != "use_cloud":
		# Keep periodic sync armed for progressed accounts.
		_ensure_timers()
		if not _periodic_timer.is_stopped():
			pass
		_periodic_timer.start(PERIODIC_SYNC_SEC)


func _ensure_timers() -> void:
	if _upload_timer == null:
		_upload_timer = Timer.new()
		_upload_timer.one_shot = true
		_upload_timer.name = "CloudSaveDebounce"
		add_child(_upload_timer)
		_upload_timer.timeout.connect(_on_upload_debounce)
	if _periodic_timer == null:
		_periodic_timer = Timer.new()
		_periodic_timer.one_shot = false
		_periodic_timer.name = "CloudSavePeriodic"
		add_child(_periodic_timer)
		_periodic_timer.timeout.connect(_on_periodic_sync)


func _on_upload_debounce() -> void:
	if _dirty:
		upload_current_partition()


func _on_periodic_sync() -> void:
	if _can_sync_now():
		mark_dirty("periodic")


func _can_sync_now() -> bool:
	var asp: Node = _asp()
	if asp == null or not bool(asp.call("is_bound")):
		return false
	if str(asp.call("get_active_user_id")) == AccountSavePaths.UNBOUND_SENTINEL:
		return false
	if asp.has_method("is_cloud_bootstrap_hold") and bool(asp.call("is_cloud_bootstrap_hold")):
		# Empty-device bootstrap: do not upload quarantine defaults before restore.
		if not _smoke_mode:
			return false
	if _smoke_mode:
		return true
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	return nc != null and bool(nc.call("is_authenticated"))


func _build_payload_for_user(uid: String) -> Dictionary:
	if uid.is_empty() or uid == AccountSavePaths.UNBOUND_SENTINEL:
		return {"ok": false, "error": ERR_UNBOUND}
	var asp: Node = _asp()
	if asp == null:
		return {"ok": false, "error": "missing_AccountSavePaths"}
	var root: String = str(asp.call("partition_root", uid))
	if root.is_empty() or root.find(AccountSavePaths.UNBOUND_SENTINEL) >= 0:
		return {"ok": false, "error": ERR_UNBOUND}

	var files: Dictionary = {}
	for file_name: String in CLOUD_FILES:
		var path: String = str(asp.call("partition_path", file_name, uid))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
		files[file_name] = Marshalls.raw_to_base64(raw)

	var meta: Dictionary = _read_local_meta(uid)
	var rev: int = maxi(1, int(meta.get("local_revision", 0)) + 1)
	# If packing unchanged content after prior upload, keep revision stable for noop callers —
	# upload path always bumps via this builder when intentionally uploading.
	var updated: int = int(Time.get_unix_time_from_system())
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"user_id": uid,
		"revision": rev,
		"updated_unix": updated,
		"files": files,
		"checksum": _checksum_files(files),
		"file_names": files.keys(),
	}
	return {"ok": true, "payload": payload}


func _checksum_files(files: Dictionary) -> String:
	var keys: Array = files.keys()
	keys.sort()
	var acc := ""
	for k: Variant in keys:
		acc += str(k) + ":" + str(files[k]) + ";"
	return acc.sha256_text()


func _read_local_meta(user_id: String) -> Dictionary:
	var asp: Node = _asp()
	if asp == null:
		return {}
	var path: String = str(asp.call("partition_path", META_FILE, user_id))
	var cfg := ConfigFile.new()
	if path.is_empty() or cfg.load(path) != OK:
		return {
			"local_revision": 0,
			"local_updated_unix": 0,
			"last_uploaded_revision": 0,
			"last_cloud_revision": 0,
			"last_cloud_updated_unix": 0,
		}
	return {
		"local_revision": int(cfg.get_value("sync", "local_revision", 0)),
		"local_updated_unix": int(cfg.get_value("sync", "local_updated_unix", 0)),
		"last_uploaded_revision": int(cfg.get_value("sync", "last_uploaded_revision", 0)),
		"last_cloud_revision": int(cfg.get_value("sync", "last_cloud_revision", 0)),
		"last_cloud_updated_unix": int(cfg.get_value("sync", "last_cloud_updated_unix", 0)),
		"storage_version": str(cfg.get_value("sync", "storage_version", "")),
	}


func _write_local_meta(user_id: String, data: Dictionary) -> void:
	var asp: Node = _asp()
	if asp == null:
		return
	asp.call("ensure_partition", user_id)
	var path: String = str(asp.call("partition_path", META_FILE, user_id))
	var cfg := ConfigFile.new()
	cfg.load(path)
	for k in data.keys():
		cfg.set_value("sync", str(k), data[k])
	cfg.save(path)


func _partition_newest_mtime(user_id: String) -> int:
	var asp: Node = _asp()
	if asp == null:
		return int(Time.get_unix_time_from_system())
	var newest: int = 0
	for file_name: String in CLOUD_FILES:
		var path: String = str(asp.call("partition_path", file_name, user_id))
		if path != "" and FileAccess.file_exists(path):
			newest = maxi(newest, int(FileAccess.get_modified_time(path)))
	if newest <= 0:
		return int(Time.get_unix_time_from_system())
	return newest


func _nakama_write(payload: Dictionary) -> Dictionary:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return _fail(ERR_NOT_AUTH)
	var client: NakamaClient = nc.call("get_client")
	var session: NakamaSession = nc.call("get_session")
	if client == null or session == null:
		return _fail(ERR_NOT_AUTH)
	# OCC: use last known storage version when available. Empty version only for first create.
	var meta: Dictionary = _read_local_meta(str(session.user_id))
	var version: String = str(meta.get("storage_version", ""))
	var json_text: String = JSON.stringify(payload)
	var write_obj := NakamaWriteStorageObject.new(COLLECTION, STORAGE_KEY, 1, 1, json_text, version)
	var result = await client.write_storage_objects_async(session, [write_obj])
	if result == null or result.is_exception():
		var msg: String = "write_failed"
		if result != null and result.get_exception() != null:
			msg = str(result.get_exception().message)
		var lower: String = msg.to_lower()
		if lower.find("version") >= 0 or lower.find("conflict") >= 0 or lower.find("occupied") >= 0:
			# Do NOT retry with empty version — that silently overwrites concurrent writers.
			return {"ok": false, "error": ERR_OCC, "conflict": true, "message": msg, "attempted_version": version}
		return {"ok": false, "error": "nakama_write_failed", "message": msg}
	var new_version: String = ""
	if result.has_method("get_acks") or ("acks" in result):
		var acks = result.acks if ("acks" in result) else []
		if typeof(acks) == TYPE_ARRAY and acks.size() > 0:
			var ack = acks[0]
			if ack != null and ("version" in ack):
				new_version = str(ack.version)
	return {"ok": true, "version": new_version}


func _smoke_write(payload: Dictionary) -> Dictionary:
	var asp: Node = _asp()
	var uid: String = str(asp.call("get_active_user_id")) if asp != null else ""
	var meta: Dictionary = _read_local_meta(uid)
	var expected: String = str(meta.get("storage_version", ""))
	var current: String = str(_smoke_cloud.get("version", ""))
	if expected != "" and current != "" and expected != current:
		return {
			"ok": false,
			"error": ERR_OCC,
			"conflict": true,
			"message": "smoke version mismatch",
			"attempted_version": expected,
			"current_version": current,
		}
	_smoke_version_seq += 1
	var ver: String = "smoke-%d" % _smoke_version_seq
	_smoke_cloud = {
		"value": payload.duplicate(true),
		"version": ver,
	}
	return {"ok": true, "version": ver, "smoke": true}


## After OCC failure: download latest, re-run conflict policy, never blank-version overwrite.
func _handle_occ_conflict(uid: String, _attempted_payload: Dictionary) -> Dictionary:
	print("[AccountCloudSave] OCC conflict — re-download and resolve")
	var cloud: Dictionary = await download_cloud_save(uid)
	if not bool(cloud.get("ok", false)):
		return {"ok": false, "error": ERR_OCC, "resolve": cloud}
	if not bool(cloud.get("exists", false)):
		# Object vanished; clear version and allow a single create retry.
		var meta_clear: Dictionary = _read_local_meta(uid)
		meta_clear["storage_version"] = ""
		_write_local_meta(uid, meta_clear)
		return {"ok": false, "error": ERR_OCC, "reason": "cloud_missing_after_conflict"}

	var payload: Dictionary = cloud.get("payload", {})
	var ver: String = str(cloud.get("version", ""))
	if ver != "":
		var m: Dictionary = _read_local_meta(uid)
		m["storage_version"] = ver
		_write_local_meta(uid, m)

	var valid: Dictionary = validate_payload(payload, uid)
	if not bool(valid.get("ok", false)):
		_blocked_conflict = valid
		cloud_conflict.emit(str(valid.get("error", CONFLICT_CORRUPT)), valid)
		return valid

	var asp: Node = _asp()
	var local_empty: bool = asp != null and not bool(asp.call("has_account_gameplay_progress", uid))
	var meta: Dictionary = _read_local_meta(uid)
	meta["local_empty"] = local_empty
	var decision: Dictionary = resolve_conflict(meta, payload)
	var action: String = str(decision.get("action", "noop"))
	match action:
		"use_cloud":
			var restored: Dictionary = restore_payload_to_partition(payload, uid)
			if bool(restored.get("ok", false)):
				_reload_gameplay()
			return {
				"ok": bool(restored.get("ok", false)),
				"action": "use_cloud",
				"occ_resolved": true,
				"restore": restored,
				"decision": decision,
			}
		"upload":
			# Retry once with fresh OCC version from download (not empty).
			var rebuilt: Dictionary = _build_payload_for_user(uid)
			if not bool(rebuilt.get("ok", false)):
				return rebuilt
			var retry_payload: Dictionary = rebuilt.get("payload", {})
			retry_payload["user_id"] = uid if _smoke_mode else _session_user_id()
			_syncing = true
			var retry: Dictionary
			if _smoke_mode:
				retry = _smoke_write(retry_payload)
			else:
				retry = await _nakama_write(retry_payload)
			_syncing = false
			if bool(retry.get("conflict", false)) or not bool(retry.get("ok", false)):
				_blocked_conflict = {"code": CONFLICT_AMBIGUOUS, "reason": "occ_retry_failed", "decision": decision}
				cloud_conflict.emit(CONFLICT_AMBIGUOUS, _blocked_conflict)
				return {"ok": false, "error": CONFLICT_AMBIGUOUS, "occ_retry": retry, "decision": decision}
			_write_local_meta(uid, {
				"local_revision": int(retry_payload.get("revision", 0)),
				"local_updated_unix": int(retry_payload.get("updated_unix", 0)),
				"last_uploaded_revision": int(retry_payload.get("revision", 0)),
				"last_cloud_revision": int(retry_payload.get("revision", 0)),
				"last_cloud_updated_unix": int(retry_payload.get("updated_unix", 0)),
				"storage_version": str(retry.get("version", "")),
			})
			_dirty = false
			return {
				"ok": true,
				"uploaded": true,
				"occ_resolved": true,
				"revision": int(retry_payload.get("revision", 0)),
				"decision": decision,
			}
		"block":
			_blocked_conflict = decision
			cloud_conflict.emit(str(decision.get("code", CONFLICT_AMBIGUOUS)), decision)
			return {"ok": false, "error": str(decision.get("code", CONFLICT_AMBIGUOUS)), "decision": decision, "occ_resolved": true}
		_:
			return {"ok": true, "action": "noop", "occ_resolved": true, "decision": decision}


func _nakama_read(user_id: String) -> Dictionary:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return _fail(ERR_NOT_AUTH)
	var client: NakamaClient = nc.call("get_client")
	var session: NakamaSession = nc.call("get_session")
	if client == null or session == null:
		return _fail(ERR_NOT_AUTH)
	var obj_id := NakamaStorageObjectId.new(COLLECTION, STORAGE_KEY, user_id)
	var result = await client.read_storage_objects_async(session, [obj_id])
	if result == null or result.is_exception():
		var msg: String = "read_failed"
		if result != null and result.get_exception() != null:
			msg = str(result.get_exception().message)
		return {"ok": false, "error": "nakama_read_failed", "message": msg}
	var objects = result.objects if ("objects" in result) else []
	if typeof(objects) != TYPE_ARRAY or objects.is_empty():
		return {"ok": true, "exists": false}
	var obj = objects[0]
	var value_raw: String = str(obj.value) if obj != null else ""
	var parsed: Variant = JSON.parse_string(value_raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": CONFLICT_CORRUPT, "reason": "json_parse"}
	return {
		"ok": true,
		"exists": true,
		"payload": parsed,
		"version": str(obj.version) if obj != null and ("version" in obj) else "",
	}


func _reload_gameplay() -> void:
	var asp: Node = _asp()
	if asp != null and asp.has_method("reload_bound_gameplay_systems"):
		asp.call("reload_bound_gameplay_systems")


func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var abs_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return OK


func _asp() -> Node:
	return get_node_or_null("/root/AccountSavePaths")


func _session_user_id() -> String:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return ""
	return str(nc.call("get_user_id")).strip_edges()


func _fail(code: String) -> Dictionary:
	var res := {"ok": false, "error": code}
	_last_result = res
	return res


func _short(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid.length() <= 8:
		return uid
	return uid.substr(0, 8)
