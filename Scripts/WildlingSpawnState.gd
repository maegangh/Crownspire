extends Node

## Local beta Wildling defeat cooldowns (client-authoritative).
## Persist: user://wildling_spawns.cfg
## Identity: kingdom_id + contract spawn-slot index — never Godot instance_id / node_path.

signal cooldown_changed
signal slot_ready_to_respawn(slot_id: String, kingdom_id: String, slot_index: int)

const SAVE_PATH := "user://wildling_spawns.cfg"
const SMOKE_SAVE_PATH := "user://wildling_spawns_smoke_test.cfg"
const META_SECTION := "meta"
const DEFEATED_SECTION := "defeated"
const SAVE_VERSION := 1

## Beta: 10-minute same-slot cooldown after a confirmed victory.
const BETA_DEFEAT_COOLDOWN_SEC: int = 600

## Contract loop index 0 → level 1 + (0 % 30) = L1 (sole FTUE Level 1 wildling).
const TUTORIAL_L1_SLOT_INDEX: int = 0

## slot_id -> { kingdom_id, slot_index, defeated_until, claimed_by_march }
var _defeated: Dictionary = {}
var _save_path_override: String = ""


func _ready() -> void:
	load_state()
	purge_expired()


func _process(_delta: float) -> void:
	_emit_ready_slots()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	_defeated.clear()
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_state()


func make_slot_id(kingdom_id: String, slot_index: int) -> String:
	var kid: String = kingdom_id.strip_edges()
	if kid.is_empty():
		kid = "kingdom_dev_001"
	return "%s:wildling:%d" % [kid, maxi(0, slot_index)]


func resolve_kingdom_id() -> String:
	if has_node("/root/AllianceLairState") and AllianceLairState.has_method("get_kingdom_id"):
		var from_lair: String = str(AllianceLairState.get_kingdom_id()).strip_edges()
		if not from_lair.is_empty():
			return from_lair
	if has_node("/root/AllianceBackend") and AllianceBackend.has_method("get_profile"):
		var kid: String = str(AllianceBackend.get_profile().get("kingdom_id", "")).strip_edges()
		if kid != "":
			return kid
	return "kingdom_dev_001"


func tutorial_l1_slot_id(kingdom_id: String = "") -> String:
	var kid: String = kingdom_id.strip_edges()
	if kid.is_empty():
		kid = resolve_kingdom_id()
	return make_slot_id(kid, TUTORIAL_L1_SLOT_INDEX)


func is_slot_on_cooldown(slot_id: String, now_unix: int = -1) -> bool:
	var sid: String = slot_id.strip_edges()
	if sid.is_empty():
		return false
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if not _defeated.has(sid):
		return false
	var rec: Variant = _defeated[sid]
	if typeof(rec) != TYPE_DICTIONARY:
		_defeated.erase(sid)
		return false
	var until: int = int((rec as Dictionary).get("defeated_until", 0))
	if until <= now:
		_defeated.erase(sid)
		save_state()
		return false
	return true


func get_defeated_until(slot_id: String) -> int:
	var sid: String = slot_id.strip_edges()
	if sid.is_empty() or not _defeated.has(sid):
		return 0
	var rec: Variant = _defeated[sid]
	if typeof(rec) != TYPE_DICTIONARY:
		return 0
	return int((rec as Dictionary).get("defeated_until", 0))


func is_tutorial_l1_on_cooldown(kingdom_id: String = "") -> bool:
	return is_slot_on_cooldown(tutorial_l1_slot_id(kingdom_id))


## Atomically mark a slot defeated for this march. Call before granting rewards.
## Returns ok=false when another march already claimed an active cooldown.
func try_claim_defeat(slot_id: String, march_id: String, now_unix: int = -1) -> Dictionary:
	var sid: String = slot_id.strip_edges()
	var mid: String = march_id.strip_edges()
	if sid.is_empty():
		# No stable slot (smoke / legacy) — allow one-shot reward via march flags only.
		return {"ok": true, "ephemeral": true, "slot_id": ""}
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if _defeated.has(sid):
		var existing: Variant = _defeated[sid]
		if typeof(existing) != TYPE_DICTIONARY:
			_defeated.erase(sid)
		else:
			var rec: Dictionary = existing
			var until: int = int(rec.get("defeated_until", 0))
			if until > now:
				var prior_march: String = str(rec.get("claimed_by_march", ""))
				if prior_march != "" and prior_march == mid:
					return {
						"ok": true,
						"already_claimed_by_self": true,
						"slot_id": sid,
						"defeated_until": until,
					}
				return {
					"ok": false,
					"reason": "already_defeated",
					"slot_id": sid,
					"claimed_by_march": prior_march,
					"defeated_until": until,
				}
			_defeated.erase(sid)

	var parts: PackedStringArray = sid.split(":")
	var kingdom_id: String = parts[0] if parts.size() >= 1 else resolve_kingdom_id()
	var slot_index: int = 0
	if parts.size() >= 3 and parts[1] == "wildling":
		slot_index = int(parts[2])
	var until_ts: int = now + BETA_DEFEAT_COOLDOWN_SEC
	_defeated[sid] = {
		"kingdom_id": kingdom_id,
		"slot_index": slot_index,
		"defeated_until": until_ts,
		"claimed_by_march": mid,
	}
	save_state()
	cooldown_changed.emit()
	return {
		"ok": true,
		"slot_id": sid,
		"defeated_until": until_ts,
		"kingdom_id": kingdom_id,
		"slot_index": slot_index,
	}


## Drop expired records safely (malformed entries removed individually).
func purge_expired(now_unix: int = -1) -> int:
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var removed: int = 0
	var keys: Array = _defeated.keys()
	for key_v: Variant in keys:
		var sid: String = str(key_v)
		var rec: Variant = _defeated.get(sid)
		if typeof(rec) != TYPE_DICTIONARY:
			_defeated.erase(sid)
			removed += 1
			continue
		var until: int = int((rec as Dictionary).get("defeated_until", 0))
		if until <= 0 or until <= now:
			_defeated.erase(sid)
			removed += 1
	if removed > 0:
		save_state()
		cooldown_changed.emit()
	return removed


func get_slots_ready_to_respawn(kingdom_id: String, now_unix: int = -1) -> Array:
	## Returns slot records whose cooldown just expired (caller should spawn then clear).
	var kid: String = kingdom_id.strip_edges()
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var ready: Array = []
	var keys: Array = _defeated.keys()
	for key_v: Variant in keys:
		var sid: String = str(key_v)
		var rec: Variant = _defeated.get(sid)
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = rec
		if str(d.get("kingdom_id", "")) != kid and not sid.begins_with("%s:" % kid):
			continue
		var until: int = int(d.get("defeated_until", 0))
		if until > 0 and until <= now:
			ready.append({
				"slot_id": sid,
				"kingdom_id": str(d.get("kingdom_id", kid)),
				"slot_index": int(d.get("slot_index", 0)),
			})
	return ready


func clear_slot(slot_id: String) -> bool:
	var sid: String = slot_id.strip_edges()
	if sid.is_empty() or not _defeated.has(sid):
		return false
	_defeated.erase(sid)
	save_state()
	cooldown_changed.emit()
	return true


## DEBUG ONLY — clear the tutorial Level 1 contract slot cooldown for the current kingdom.
func debug_clear_tutorial_l1_cooldown() -> bool:
	if not OS.is_debug_build():
		push_warning("[WildlingSpawnState] debug_clear_tutorial_l1_cooldown blocked (not a debug build)")
		return false
	var kid: String = resolve_kingdom_id()
	var sid: String = tutorial_l1_slot_id(kid)
	clear_slot(sid)
	# Always notify so a live World Map can (re)spawn the FTUE L1 slot only.
	slot_ready_to_respawn.emit(sid, kid, TUTORIAL_L1_SLOT_INDEX)
	return true


func save_state() -> void:
	var save := ConfigFile.new()
	save.set_value(META_SECTION, "save_version", SAVE_VERSION)
	# Persist each record as JSON so malformed rows can be skipped on load.
	for key_v: Variant in _defeated.keys():
		var sid: String = str(key_v)
		var rec: Variant = _defeated[sid]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		save.set_value(DEFEATED_SECTION, sid, JSON.stringify(rec))
	var err: Error = save.save(get_save_path())
	if err != OK:
		push_warning("[WildlingSpawnState] save failed: %s" % error_string(err))


func load_state() -> void:
	_defeated.clear()
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	if not save.has_section(DEFEATED_SECTION):
		return
	for key: String in save.get_section_keys(DEFEATED_SECTION):
		var raw: Variant = save.get_value(DEFEATED_SECTION, key, "")
		var parsed: Variant = null
		if typeof(raw) == TYPE_STRING:
			parsed = JSON.parse_string(str(raw))
		elif typeof(raw) == TYPE_DICTIONARY:
			parsed = raw
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("[WildlingSpawnState] skipping malformed record: %s" % key)
			continue
		var rec: Dictionary = parsed
		if not rec.has("defeated_until"):
			push_warning("[WildlingSpawnState] skipping record without defeated_until: %s" % key)
			continue
		_defeated[key] = {
			"kingdom_id": str(rec.get("kingdom_id", "")),
			"slot_index": int(rec.get("slot_index", 0)),
			"defeated_until": int(rec.get("defeated_until", 0)),
			"claimed_by_march": str(rec.get("claimed_by_march", "")),
		}
	purge_expired()


func _emit_ready_slots() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var keys: Array = _defeated.keys()
	var any_cleared: bool = false
	for key_v: Variant in keys:
		var sid: String = str(key_v)
		var rec: Variant = _defeated.get(sid)
		if typeof(rec) != TYPE_DICTIONARY:
			_defeated.erase(sid)
			any_cleared = true
			continue
		var d: Dictionary = rec
		var until: int = int(d.get("defeated_until", 0))
		if until > 0 and until <= now:
			var kid: String = str(d.get("kingdom_id", ""))
			var idx: int = int(d.get("slot_index", 0))
			_defeated.erase(sid)
			any_cleared = true
			slot_ready_to_respawn.emit(sid, kid, idx)
	if any_cleared:
		save_state()
		cooldown_changed.emit()
