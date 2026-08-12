extends Node

## Crownspire Phase 2 — per-account local save namespace.
## Root: user://saves/<nakama_user_id>/
## Device-global files stay at flat user:// paths.

signal save_context_changed(user_id: String)
signal migration_completed(user_id: String, result: Dictionary)
signal load_blocked(code: String, detail: Dictionary)

const MISMATCH_CODE := "LOCAL_SAVE_ACCOUNT_MISMATCH"
const MIGRATION_VERSION := 1
const SAVES_ROOT := "user://saves"
const SMOKE_SAVES_ROOT := "user://saves_smoke_test"
const DEVICE_MIGRATION_PATH := "user://account_save_migration.cfg"
const SMOKE_DEVICE_MIGRATION_PATH := "user://account_save_migration_smoke_test.cfg"
const PARTITION_META_FILE := "_account_save_meta.cfg"
const UNBOUND_SENTINEL := "__unbound__"

## A — account-owned progression / per-user caches
const ACCOUNT_OWNED: PackedStringArray = [
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
	"resource_tiles.cfg",
	"alliance.cfg",
	"alliance_lairs_runtime.cfg",
	"savegame.save",
	"chat_display_name.cfg",
	"chat_moderation_local.cfg",
	"chat_reports_pending.cfg",
	"dm_conversations.cfg",
]

## B — device-global (never moved into saves/<uid>/)
const DEVICE_GLOBAL: PackedStringArray = [
	"nakama_config.cfg",
	"nakama_device_id.cfg",
	"account_session.cfg",
	"account_local_ownership.cfg",
	"account_save_migration.cfg",
	"locale.cfg",
]

## C — shared / world-derived (no local per-user city authority)
const SHARED_WORLD: PackedStringArray = []

## D — uncertain (treated as account-owned for isolation safety)
const UNCERTAIN_AS_ACCOUNT: PackedStringArray = [
	"alliance_lairs_runtime.cfg",
]

const GAMEPLAY_PROGRESS_MARKERS: PackedStringArray = [
	"resources.cfg",
	"buildings.cfg",
	"troops.cfg",
	"heroes.cfg",
	"quests.cfg",
	"research_queue.cfg",
	"construction_queue.cfg",
	"marches.cfg",
	"alliance.cfg",
	"bag.cfg",
]

var _root_override: String = ""
var _migration_path_override: String = ""
var _active_user_id: String = ""
var _legacy_mismatch: bool = false
var _legacy_owner_user_id: String = ""
var _last_migration_result: Dictionary = {}
var _context_token: int = 0
var _provisional_bind: bool = false
## When true, account-owned path_for returns quarantine so empty defaults cannot
## persist into the real partition before cloud restore completes.
var _cloud_bootstrap_hold: bool = false
## Phase 3 smoke only: allow empty-bind bootstrap hold under smoke root.
var _smoke_bootstrap_hold_enabled: bool = false


func _ready() -> void:
	# Bind BEFORE later autoloads (GameState, etc.) call path_for in their _ready.
	_try_provisional_bind_for_boot()
	call_deferred("_bind_identity")


func begin_smoke_isolation() -> void:
	close_save_context()
	_root_override = SMOKE_SAVES_ROOT
	_migration_path_override = SMOKE_DEVICE_MIGRATION_PATH
	_smoke_bootstrap_hold_enabled = false
	_cloud_bootstrap_hold = false
	_clear_dir_recursive(ProjectSettings.globalize_path(SMOKE_SAVES_ROOT))
	if FileAccess.file_exists(get_device_migration_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_device_migration_path()))


func enable_smoke_bootstrap_hold(enabled: bool) -> void:
	_smoke_bootstrap_hold_enabled = enabled
	if not enabled:
		_cloud_bootstrap_hold = false


func end_smoke_isolation() -> void:
	close_save_context()
	_clear_dir_recursive(ProjectSettings.globalize_path(SMOKE_SAVES_ROOT))
	if FileAccess.file_exists(get_device_migration_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_device_migration_path()))
	_root_override = ""
	_migration_path_override = ""
	_smoke_bootstrap_hold_enabled = false
	_cloud_bootstrap_hold = false


func get_saves_root() -> String:
	if _root_override != "":
		return _root_override
	return SAVES_ROOT


func get_device_migration_path() -> String:
	if _migration_path_override != "":
		return _migration_path_override
	return DEVICE_MIGRATION_PATH


func get_active_user_id() -> String:
	return _active_user_id


func is_bound() -> bool:
	return _active_user_id.strip_edges() != ""


func has_legacy_mismatch() -> bool:
	return _legacy_mismatch


func get_legacy_owner_user_id() -> String:
	return _legacy_owner_user_id


func get_last_migration_result() -> Dictionary:
	return _last_migration_result.duplicate(true)


func classify_file(file_name: String) -> String:
	var name: String = _normalize_file_name(file_name)
	if name in DEVICE_GLOBAL:
		return "device_global"
	if name in SHARED_WORLD:
		return "shared_world"
	if name in ACCOUNT_OWNED or name in UNCERTAIN_AS_ACCOUNT:
		return "account_owned"
	# Unknown gameplay files default to account-owned for isolation safety.
	if name.ends_with(".cfg") or name.ends_with(".save"):
		return "uncertain_as_account"
	return "device_global"


func is_account_owned_file(file_name: String) -> bool:
	var c: String = classify_file(file_name)
	return c == "account_owned" or c == "uncertain_as_account"


func legacy_path(file_name: String) -> String:
	return "user://%s" % _normalize_file_name(file_name)


func quarantine_path(file_name: String) -> String:
	## Non-authoritative sink while unbound. Never a real account partition / legacy flat.
	var path: String = "%s/%s/%s" % [get_saves_root(), UNBOUND_SENTINEL, _normalize_file_name(file_name)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return path


func partition_root(user_id: String = "") -> String:
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		uid = _active_user_id
	if uid.is_empty():
		return ""
	return "%s/%s" % [get_saves_root(), uid]


func partition_path(file_name: String, user_id: String = "") -> String:
	var root: String = partition_root(user_id)
	if root.is_empty():
		return ""
	return "%s/%s" % [root, _normalize_file_name(file_name)]


## Legacy flat files are NEVER gameplay authority after Phase 2 hardening.
## They remain readable only as one-time migration sources inside migrate_legacy_into_user().
func is_legacy_flat_authoritative() -> bool:
	return false


func is_legacy_flat_reachable_for_gameplay() -> bool:
	return false


## Canonical resolver for gameplay systems.
## Bound → active user partition (or quarantine while cloud bootstrap hold is active).
## Unbound → quarantine (empty), NEVER legacy flat or another user's partition.
func path_for(file_name: String) -> String:
	var name: String = _normalize_file_name(file_name)
	if not is_account_owned_file(name):
		return legacy_path(name)
	if not is_bound():
		return quarantine_path(name)
	if _cloud_bootstrap_hold:
		# Hold real partition pristine until AccountCloudSave finishes restore/noop.
		return quarantine_path(name)
	return partition_path(name, _active_user_id)


func set_cloud_bootstrap_hold(active: bool) -> void:
	var prev: bool = _cloud_bootstrap_hold
	_cloud_bootstrap_hold = active
	if prev != active:
		print("[AccountSavePaths] cloud_bootstrap_hold=%s user=%s" % [str(active), _short(_active_user_id)])


func is_cloud_bootstrap_hold() -> bool:
	return _cloud_bootstrap_hold


func may_persist_account_files() -> bool:
	## False while empty-partition cloud bootstrap is in progress.
	if not is_bound():
		return false
	if _cloud_bootstrap_hold:
		return false
	return true


## Explicit cross-user path — only for switch/migration internals & tests.
func path_for_user(user_id: String, file_name: String) -> String:
	var uid: String = user_id.strip_edges()
	var name: String = _normalize_file_name(file_name)
	if uid.is_empty() or not is_account_owned_file(name):
		return ""
	if uid == UNBOUND_SENTINEL:
		return ""
	if is_bound() and uid != _active_user_id:
		# Refuse silent cross-account resolution while another context is active.
		load_blocked.emit(MISMATCH_CODE, {"requested": uid, "active": _active_user_id, "file": name})
		return ""
	return partition_path(name, uid)


func can_load_active_partition() -> bool:
	return is_bound()


func is_provisional_bind() -> bool:
	return _provisional_bind and is_bound()


## True when the active (or specified) account partition has progressed gameplay markers.
func has_account_gameplay_progress(user_id: String = "") -> bool:
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		if not is_bound():
			return false
		uid = _active_user_id
	for marker: String in GAMEPLAY_PROGRESS_MARKERS:
		var path: String = partition_path(marker, uid)
		if path != "" and FileAccess.file_exists(path):
			return true
	return false


func ensure_partition(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid.is_empty() or uid == UNBOUND_SENTINEL:
		return {"ok": false, "error": "empty_user_id"}
	var root: String = partition_root(uid)
	var abs_root: String = ProjectSettings.globalize_path(root)
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_root)
	if err != OK and not DirAccess.dir_exists_absolute(abs_root):
		return {"ok": false, "error": "mkdir_failed", "code": err}
	return {"ok": true, "root": root}


## Close current account save context (does not delete partitions).
func close_save_context() -> void:
	_active_user_id = ""
	_legacy_mismatch = false
	_legacy_owner_user_id = ""
	_provisional_bind = false
	_cloud_bootstrap_hold = false
	_context_token += 1
	save_context_changed.emit("")


## Bind a user partition. Creates empty partition when missing.
## Migrates legacy flat saves only when auth user owns them.
## opts.reload (default true): reload gameplay systems after bind.
## opts.provisional (default false): early boot bind before Nakama auth confirms.
func open_save_context(user_id: String, opts: Dictionary = {}) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid.is_empty() or uid == UNBOUND_SENTINEL:
		return {"ok": false, "error": "empty_user_id"}
	var legacy_owner: String = str(opts.get("legacy_owner", "")).strip_edges()
	var force_mismatch: bool = bool(opts.get("legacy_mismatch", false))
	var do_reload: bool = true if not opts.has("reload") else bool(opts.get("reload", true))
	var provisional: bool = bool(opts.get("provisional", false))
	if legacy_owner.is_empty():
		legacy_owner = _read_legacy_owner_hint()

	var ensured: Dictionary = ensure_partition(uid)
	if not bool(ensured.get("ok", false)):
		return ensured

	_legacy_owner_user_id = legacy_owner
	_legacy_mismatch = force_mismatch or (legacy_owner != "" and legacy_owner != uid)

	var migration: Dictionary = {"ok": true, "skipped": true, "migrated": false}
	if _legacy_mismatch:
		# Do not migrate or read another account's legacy flat progression.
		migration = {
			"ok": false,
			"error": MISMATCH_CODE,
			"migrated": false,
			"skipped": true,
			"reason": "legacy_owned_by_other",
			"legacy_owner": legacy_owner,
			"auth_user_id": uid,
		}
		load_blocked.emit(MISMATCH_CODE, migration)
	else:
		migration = migrate_legacy_into_user(uid)

	_last_migration_result = migration
	_active_user_id = uid
	_provisional_bind = provisional
	# Empty partition may need cloud restore before gameplay persists/presents as live.
	# Under Phase 1/2 smoke isolation, bootstrap hold stays off unless P3 enables it.
	var allow_hold: bool = (_root_override == "") or _smoke_bootstrap_hold_enabled
	if allow_hold and not has_account_gameplay_progress(uid):
		_cloud_bootstrap_hold = true
	else:
		_cloud_bootstrap_hold = false
	_context_token += 1
	save_context_changed.emit(uid)
	if do_reload and not _cloud_bootstrap_hold:
		_reload_bound_gameplay_systems()
	return {
		"ok": true,
		"user_id": uid,
		"root": partition_root(uid),
		"legacy_mismatch": _legacy_mismatch,
		"migration": migration,
		"provisional": provisional,
		"cloud_bootstrap_hold": _cloud_bootstrap_hold,
	}


func open_for_authenticated_user(user_id: String, ownership: Dictionary = {}) -> Dictionary:
	var opts := {
		"legacy_owner": str(ownership.get("owner_user_id", ownership.get("legacy_owner", ""))),
		"legacy_mismatch": bool(ownership.get("mismatch", false)),
		"reload": true,
		"provisional": false,
	}
	# Same user already bound (including provisional): confirm bind, reload once if provisional.
	var uid: String = user_id.strip_edges()
	if is_bound() and _active_user_id == uid:
		var was_provisional: bool = _provisional_bind
		_provisional_bind = false
		_legacy_mismatch = bool(opts.get("legacy_mismatch", false))
		_legacy_owner_user_id = str(opts.get("legacy_owner", ""))
		# Do not reload while cloud bootstrap hold is active — AccountCloudSave will.
		if was_provisional and not _cloud_bootstrap_hold:
			_reload_bound_gameplay_systems()
		return {
			"ok": true,
			"user_id": uid,
			"root": partition_root(uid),
			"legacy_mismatch": _legacy_mismatch,
			"migration": _last_migration_result,
			"confirmed_provisional": was_provisional,
			"cloud_bootstrap_hold": _cloud_bootstrap_hold,
		}
	return open_save_context(uid, opts)


## Early boot: bind only when ownership + stored session prove a safe identity.
## Never loads legacy flat as the unbound/unknown account's authority.
func try_provisional_bind_for_boot() -> Dictionary:
	return _try_provisional_bind_for_boot()


func _try_provisional_bind_for_boot() -> Dictionary:
	if is_bound():
		return {"ok": true, "already_bound": true, "user_id": _active_user_id}

	var owner: String = _read_legacy_owner_hint()
	var session_uid: String = _read_stored_session_user_id()

	if session_uid != "" and owner != "" and session_uid == owner:
		return open_save_context(
			session_uid,
			{"legacy_owner": owner, "legacy_mismatch": false, "reload": false, "provisional": true}
		)
	if session_uid != "" and owner != "" and session_uid != owner:
		# Known upcoming session differs from legacy owner — bind session partition empty.
		return open_save_context(
			session_uid,
			{"legacy_owner": owner, "legacy_mismatch": true, "reload": false, "provisional": true}
		)
	if session_uid != "" and owner == "":
		return open_save_context(
			session_uid,
			{"legacy_owner": "", "legacy_mismatch": false, "reload": false, "provisional": true}
		)
	if owner != "" and session_uid == "":
		# Stable device guest owner with no session file yet — bind owner partition only.
		return open_save_context(
			owner,
			{"legacy_owner": owner, "legacy_mismatch": false, "reload": false, "provisional": true}
		)

	# Unknown identity: stay unbound. path_for → quarantine (not legacy).
	print("[AccountSavePaths] Unbound boot — account saves quarantined until auth binds")
	return {"ok": true, "unbound": true}



## Idempotent copy of legacy flat account files → user://saves/<uid>/.
## Preserves originals. Refuses if legacy belongs to another recorded owner.
func migrate_legacy_into_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		return {"ok": false, "error": "empty_user_id"}

	var legacy_owner: String = _read_legacy_owner_hint()
	if legacy_owner != "" and legacy_owner != uid:
		return {
			"ok": false,
			"error": MISMATCH_CODE,
			"migrated": false,
			"legacy_owner": legacy_owner,
			"auth_user_id": uid,
		}

	var ensured: Dictionary = ensure_partition(uid)
	if not bool(ensured.get("ok", false)):
		return ensured

	if _partition_migration_done(uid):
		return {
			"ok": true,
			"skipped": true,
			"migrated": false,
			"version": MIGRATION_VERSION,
			"user_id": uid,
		}

	var copied: PackedStringArray = []
	var missing: PackedStringArray = []
	for file_name: String in ACCOUNT_OWNED:
		var src: String = legacy_path(file_name)
		var dst: String = partition_path(file_name, uid)
		if not FileAccess.file_exists(src):
			missing.append(file_name)
			continue
		if FileAccess.file_exists(dst):
			# Partition already has this file — keep it; still count as covered.
			continue
		var copy_err: Error = _copy_file(src, dst)
		if copy_err != OK:
			return {
				"ok": false,
				"error": "copy_failed",
				"file": file_name,
				"code": copy_err,
				"copied": copied,
			}
		copied.append(file_name)
		# Verify original still exists.
		if not FileAccess.file_exists(src):
			return {"ok": false, "error": "original_missing_after_copy", "file": file_name}

	_write_partition_meta(uid, {
		"migration_version": MIGRATION_VERSION,
		"legacy_migrated": true,
		"legacy_owner": uid if legacy_owner == "" else legacy_owner,
		"migrated_at": int(Time.get_unix_time_from_system()),
		"copied_count": copied.size(),
	})
	_write_device_migration_record(uid)

	var result := {
		"ok": true,
		"skipped": false,
		"migrated": true,
		"version": MIGRATION_VERSION,
		"user_id": uid,
		"copied": copied,
		"missing_legacy": missing,
	}
	migration_completed.emit(uid, result)
	print(
		"[AccountSavePaths] Legacy migration complete user=%s copied=%d"
		% [_short(uid), copied.size()]
	)
	return result


func list_account_owned_files() -> PackedStringArray:
	return ACCOUNT_OWNED.duplicate()


func list_device_global_files() -> PackedStringArray:
	return DEVICE_GLOBAL.duplicate()


func _bind_identity() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		return
	if identity.has_signal("account_state_changed") and not identity.account_state_changed.is_connected(_on_identity_changed):
		identity.account_state_changed.connect(_on_identity_changed)
	_on_identity_changed()


func _on_identity_changed() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		return
	var uid: String = str(identity.call("get_auth_user_id")).strip_edges()
	if uid.is_empty():
		return
	var mismatch: bool = bool(identity.call("has_local_save_mismatch"))
	var owner: String = str(identity.call("get_local_owner_user_id"))
	open_for_authenticated_user(
		uid,
		{
			"owner_user_id": owner,
			"mismatch": mismatch,
		}
	)


func reload_bound_gameplay_systems() -> void:
	_reload_bound_gameplay_systems()


func _reload_bound_gameplay_systems() -> void:
	# Refresh ConstructionState path vars before loads.
	var cs: Node = get_node_or_null("/root/ConstructionState")
	if cs != null and cs.has_method("refresh_account_save_paths"):
		cs.call("refresh_account_save_paths")
	_call_load("/root/GameState", "load_resources")
	_call_load("/root/TroopState", "load_troops")
	_call_load("/root/HeroState", "load_heroes")
	_call_load("/root/QuestState", "load_quests")
	_call_load("/root/ResearchState", "load_research_state")
	_call_load("/root/BagState", "load_bag")
	_call_load("/root/MarchState", "load_marches")
	_call_load("/root/MailManager", "load_mail")
	_call_load("/root/ConstructionState", "load_construction_state")
	_call_load("/root/TutorialState", "load_tutorial_state")
	_call_load("/root/WildlingSpawnState", "load_state")
	_call_load("/root/ResourceTileState", "load_tiles")
	_call_load("/root/HealingState", "load_healing_state")
	_call_load("/root/SanctuaryState", "load_sanctuary_state")
	_call_load("/root/EventState", "load_events")
	_call_load("/root/AllianceState", "load_alliance")
	var lair: Node = get_node_or_null("/root/AllianceLairState")
	if lair != null and lair.has_method("_load_runtime"):
		lair.call("_load_runtime")


func _call_load(node_path: String, method: String) -> void:
	var n: Node = get_node_or_null(node_path)
	if n != null and n.has_method(method):
		n.call(method)


func _normalize_file_name(file_name: String) -> String:
	var name: String = file_name.strip_edges()
	if name.begins_with("user://"):
		name = name.substr(7)
	if name.begins_with("/"):
		name = name.substr(1)
	# Reject path traversal into other partitions.
	name = name.replace("\\", "/")
	while name.begins_with("../") or name.contains("/../") or name.contains("/.."):
		name = name.replace("../", "").replace("/..", "")
	if name.contains("/"):
		name = name.get_file()
	return name


func _read_legacy_owner_hint() -> String:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_method("get_local_owner_user_id"):
		return str(identity.call("get_local_owner_user_id")).strip_edges()
	return _legacy_owner_user_id


func _read_stored_session_user_id() -> String:
	# Smoke isolation must not mix live device session identity into fake owners.
	if _root_override != "":
		return ""
	# Prefer live NakamaConnection store when present (honors connection smoke isolation).
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("get_session_store"):
		var store = nc.call("get_session_store")
		if store != null and store.has_method("load_session_data"):
			var data: Dictionary = store.load_session_data()
			return str(data.get("user_id", "")).strip_edges()
	var fallback := AccountSessionStore.new()
	var flat: Dictionary = fallback.load_session_data()
	return str(flat.get("user_id", "")).strip_edges()


func _partition_meta_path(user_id: String) -> String:
	return partition_path(PARTITION_META_FILE, user_id)


func _partition_migration_done(user_id: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_partition_meta_path(user_id)) != OK:
		return false
	return int(cfg.get_value("migration", "migration_version", 0)) >= MIGRATION_VERSION \
		and bool(cfg.get_value("migration", "legacy_migrated", false))


func _write_partition_meta(user_id: String, data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_partition_meta_path(user_id))
	for k in data.keys():
		cfg.set_value("migration", str(k), data[k])
	cfg.save(_partition_meta_path(user_id))


func _write_device_migration_record(user_id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(get_device_migration_path())
	cfg.set_value("legacy", "migrated_to_user_id", user_id)
	cfg.set_value("legacy", "version", MIGRATION_VERSION)
	cfg.set_value("legacy", "migrated_at", int(Time.get_unix_time_from_system()))
	cfg.save(get_device_migration_path())


func _copy_file(src: String, dst: String) -> Error:
	var abs_src: String = ProjectSettings.globalize_path(src)
	var abs_dst: String = ProjectSettings.globalize_path(dst)
	var dst_dir: String = abs_dst.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dst_dir)
	return DirAccess.copy_absolute(abs_src, abs_dst)


func _clear_dir_recursive(abs_path: String) -> void:
	if abs_path.strip_edges() == "" or abs_path == "/" or not DirAccess.dir_exists_absolute(abs_path):
		return
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var child: String = abs_path.path_join(name)
		if dir.current_is_dir():
			_clear_dir_recursive(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()


func _short(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid.length() <= 8:
		return uid
	return uid.substr(0, 8)
