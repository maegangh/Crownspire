extends Node

## Canonical notification bus for FTUE / quests / future analytics.
## Gameplay systems emit facts AFTER a successful action.
## Listeners must never drive gameplay from these signals.

# --- Legacy / quest-compatible ---
signal troops_trained(amount: int)
signal building_upgraded(building_id: String, level: int)
## QuestState listens; payload is research_id (progress +1 per completion).
signal research_completed(research_id: String)
## QuestState listens; payload is wildling_id (progress +1 per defeat).
signal wildling_defeated(wildling_id: String)

# --- Buildings ---
signal building_selected(building_id: String)
signal building_upgrade_started(building_id: String, target_level: int)

# --- Research ---
signal research_started(research_id: String)

# --- Training ---
signal troop_training_started(troop_type: String, tier: int, amount: int)
signal troop_training_completed(troop_type: String, tier: int, amount: int)

# --- Navigation ---
signal city_opened
signal world_opened

# --- World interaction ---
signal wildling_selected(wildling_id: String)
signal resource_tile_selected(resource_type: String)
signal march_dispatched(march_data: Dictionary)
signal gathering_started(resource_type: String)
signal gathering_completed(resource_type: String, amount: int)

# --- City economy ---
## City building collect (Farm/Mill/etc). Not world gathering.
signal resource_collected(resource_type: String, amount: int)

# --- UI / feature discovery ---
signal mail_opened
signal alliance_opened

# --- Speedups (actual seconds reduced, not item face duration) ---
signal speedup_used(category: String, seconds_actual: int)


func _log_event(message: String) -> void:
	print("[FTUE EVENT] %s" % message)


# --- Emit helpers (preferred call sites) ---

func emit_building_selected(building_id: String) -> void:
	var bid: String = building_id.strip_edges()
	if bid.is_empty():
		return
	building_selected.emit(bid)
	_log_event("building_selected: %s" % bid)


func emit_building_upgrade_started(building_id: String, target_level: int) -> void:
	var bid: String = building_id.strip_edges()
	if bid.is_empty():
		return
	building_upgrade_started.emit(bid, target_level)
	_log_event("building_upgrade_started: %s -> %d" % [bid, target_level])


func emit_building_upgraded(building_id: String, level: int) -> void:
	var bid: String = building_id.strip_edges()
	if bid.is_empty():
		return
	building_upgraded.emit(bid, level)
	_log_event("building_upgraded: %s -> %d" % [bid, level])


func emit_research_started(research_id: String) -> void:
	var rid: String = research_id.strip_edges()
	if rid.is_empty():
		return
	research_started.emit(rid)
	_log_event("research_started: %s" % rid)


func emit_research_completed(research_id: String = "") -> void:
	var rid: String = research_id.strip_edges()
	research_completed.emit(rid)
	_log_event("research_completed: %s" % (rid if not rid.is_empty() else "(unknown)"))


func emit_troop_training_started(troop_type: String, tier: int, amount: int) -> void:
	troop_training_started.emit(troop_type, tier, amount)
	_log_event("troop_training_started: %s T%d x%d" % [troop_type, tier, amount])


func emit_troop_training_completed(troop_type: String, tier: int, amount: int) -> void:
	troop_training_completed.emit(troop_type, tier, amount)
	# Legacy quest bus (amount only).
	troops_trained.emit(amount)
	_log_event("troop_training_completed: %s T%d x%d" % [troop_type, tier, amount])


func emit_troops_trained(amount: int) -> void:
	## Back-compat wrapper — prefer emit_troop_training_completed.
	troops_trained.emit(amount)
	_log_event("troops_trained: %d" % amount)


func emit_city_opened() -> void:
	city_opened.emit()
	_log_event("city_opened")


func emit_world_opened() -> void:
	world_opened.emit()
	_log_event("world_opened")


func emit_wildling_selected(wildling_id: String) -> void:
	var wid: String = wildling_id.strip_edges()
	if wid.is_empty():
		return
	wildling_selected.emit(wid)
	_log_event("wildling_selected: %s" % wid)


func emit_wildling_defeated(wildling_id: Variant = "") -> void:
	## Accepts String id, or legacy int/bool amount (maps to empty id + quest +1).
	var wid: String = ""
	if typeof(wildling_id) == TYPE_STRING:
		wid = str(wildling_id).strip_edges()
	wildling_defeated.emit(wid)
	_log_event("wildling_defeated: %s" % (wid if not wid.is_empty() else "(amount)"))


func emit_resource_tile_selected(resource_type: String) -> void:
	var rtype: String = resource_type.strip_edges().to_lower()
	if rtype.is_empty():
		return
	resource_tile_selected.emit(rtype)
	_log_event("resource_tile_selected: %s" % rtype)


func emit_march_dispatched(march_data: Dictionary) -> void:
	if march_data.is_empty():
		return
	march_dispatched.emit(march_data.duplicate(true))
	_log_event(
		"march_dispatched: %s type=%s" % [
			str(march_data.get("march_id", "")),
			str(march_data.get("march_type", "")),
		]
	)


func emit_gathering_started(resource_type: String) -> void:
	var rtype: String = resource_type.strip_edges().to_lower()
	gathering_started.emit(rtype)
	_log_event("gathering_started: %s" % rtype)


func emit_gathering_completed(resource_type: String, amount: int) -> void:
	var rtype: String = resource_type.strip_edges().to_lower()
	gathering_completed.emit(rtype, amount)
	_log_event("gathering_completed: %s x%d" % [rtype, amount])


func emit_resource_collected(resource_type: String, amount: int) -> void:
	var rtype: String = resource_type.strip_edges().to_lower()
	if rtype.is_empty() or amount <= 0:
		return
	resource_collected.emit(rtype, amount)
	_log_event("resource_collected: %s x%d" % [rtype, amount])


func emit_mail_opened() -> void:
	mail_opened.emit()
	_log_event("mail_opened")


func emit_alliance_opened() -> void:
	alliance_opened.emit()
	_log_event("alliance_opened")


func emit_speedup_used(category: String, seconds_actual: int) -> void:
	var cat: String = category.strip_edges().to_lower()
	var secs: int = maxi(0, seconds_actual)
	if cat.is_empty() or secs <= 0:
		return
	speedup_used.emit(cat, secs)
	_log_event("speedup_used: %s %ds" % [cat, secs])
