extends Node

## Shared player-facing speedups for Construction / Research / Training timers.
## Consumes BagState items and reduces canonical queue end times.
## Future-compatible with healing (category supported; UI not wired this sprint).

signal speedup_applied(category: String, target_id: String, result: Dictionary)

const CAT_CONSTRUCTION := "construction"
const CAT_RESEARCH := "research"
const CAT_TRAINING := "training"
const CAT_HEALING := "healing"

const LOG_PREFIX := "[SPEEDUP]"

var _popup: Control = null
var _duration_regex: RegEx


func _ready() -> void:
	_duration_regex = RegEx.new()
	_duration_regex.compile("_(\\d+)(h|m|s)$")


# --- Eligibility / catalog ----------------------------------------------------

func get_timer_subcategories(timer_category: String) -> PackedStringArray:
	match timer_category.strip_edges().to_lower():
		CAT_CONSTRUCTION:
			return PackedStringArray(["universal", "construction"])
		CAT_RESEARCH:
			return PackedStringArray(["universal", "research"])
		CAT_TRAINING:
			return PackedStringArray(["universal", "training"])
		CAT_HEALING:
			return PackedStringArray(["universal", "healing"])
		_:
			return PackedStringArray()


func is_eligible_speedup(item_id: String, timer_category: String) -> bool:
	if not has_node("/root/ItemDatabase"):
		return false
	var item: Dictionary = ItemDatabase.get_item(item_id)
	if item.is_empty():
		return false
	if str(item.get("category", "")) != "speedup":
		return false
	var sub: String = str(item.get("subcategory", "")).strip_edges().to_lower()
	if get_speedup_seconds(item_id) <= 0:
		return false
	return get_timer_subcategories(timer_category).has(sub)


func get_speedup_seconds(item_id: String) -> int:
	var id: String = item_id.strip_edges()
	if id.is_empty() or _duration_regex == null:
		return 0
	var m: RegExMatch = _duration_regex.search(id)
	if m == null:
		return 0
	var n: int = int(m.get_string(1))
	match m.get_string(2):
		"h":
			return n * 3600
		"m":
			return n * 60
		"s":
			return n
		_:
			return 0


## Owned eligible speedups for a timer category. Each entry:
## { item_id, name, seconds, owned, icon, subcategory }
func list_owned_eligible(timer_category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_node("/root/ItemDatabase") or not has_node("/root/BagState"):
		return out
	for item: Variant in ItemDatabase.get_items_by_category("speedup"):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item as Dictionary
		var iid: String = str(d.get("id", ""))
		if not is_eligible_speedup(iid, timer_category):
			continue
		var owned: int = BagState.get_item_count(iid)
		if owned <= 0:
			continue
		out.append({
			"item_id": iid,
			"name": str(d.get("name", iid)),
			"seconds": get_speedup_seconds(iid),
			"owned": owned,
			"icon": str(d.get("icon", "")),
			"subcategory": str(d.get("subcategory", "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("seconds", 0)) < int(b.get("seconds", 0))
	)
	return out


func get_remaining_seconds(timer_category: String, target_id: String) -> float:
	var cat: String = timer_category.strip_edges().to_lower()
	var tid: String = target_id.strip_edges()
	match cat:
		CAT_CONSTRUCTION:
			if has_node("/root/ConstructionState"):
				return ConstructionState.get_remaining_seconds(tid)
		CAT_RESEARCH:
			if has_node("/root/ResearchState"):
				var job: Dictionary = ResearchState.get_job_for(tid)
				if job.is_empty() and tid.is_empty():
					job = ResearchState.get_primary_job()
				return float(job.get("time_remaining", 0.0))
		CAT_TRAINING:
			if has_node("/root/TroopState"):
				return float(TroopState.get_training_time_left(tid))
		CAT_HEALING:
			if has_node("/root/HealingState") and HealingState.has_method("get_remaining_seconds"):
				return float(HealingState.get_remaining_seconds())
	return 0.0


func format_remaining(seconds: float) -> String:
	var s: int = maxi(0, int(ceil(seconds)))
	var h: int = s / 3600
	var m: int = (s % 3600) / 60
	var r: int = s % 60
	if h > 0:
		return "%dh %02dm %02ds" % [h, m, r]
	if m > 0:
		return "%dm %02ds" % [m, r]
	return "%ds" % r


# --- Apply --------------------------------------------------------------------

## Consume one (or more) bag items and reduce the canonical timer.
func apply_speedup_item(
	timer_category: String,
	target_id: String,
	item_id: String,
	quantity: int = 1
) -> Dictionary:
	var cat: String = timer_category.strip_edges().to_lower()
	var tid: String = target_id.strip_edges()
	var iid: String = item_id.strip_edges()
	var qty: int = maxi(1, quantity)

	if not is_eligible_speedup(iid, cat):
		return {"ok": false, "reason": "Item not eligible for this timer."}
	var per: int = get_speedup_seconds(iid)
	if per <= 0:
		return {"ok": false, "reason": "Invalid speedup duration."}
	if not has_node("/root/BagState"):
		return {"ok": false, "reason": "Bag unavailable."}
	if BagState.get_item_count(iid) < qty:
		return {"ok": false, "reason": "Not enough items."}

	var remaining_before: float = get_remaining_seconds(cat, tid)
	if remaining_before <= 0.0:
		return {"ok": false, "reason": "No active timer."}

	if not BagState.remove_item(iid, qty):
		return {"ok": false, "reason": "Could not consume item."}

	var total_seconds: int = per * qty
	var reduce_result: Dictionary = _reduce_timer(cat, tid, total_seconds)
	if not bool(reduce_result.get("ok", false)):
		# Restore consumed items if queue mutation failed.
		BagState.add_item(iid, qty)
		return reduce_result

	var remaining_after: float = float(reduce_result.get("remaining", get_remaining_seconds(cat, tid)))
	# Actual accelerated time (never credit unused overshoot from a larger item).
	var seconds_actual: int = int(floor(maxi(0.0, remaining_before - remaining_after) + 0.5))
	var result: Dictionary = {
		"ok": true,
		"reason": "",
		"category": cat,
		"target_id": tid,
		"item_id": iid,
		"quantity": qty,
		"seconds_requested": total_seconds,
		"seconds_applied": seconds_actual,
		"seconds_actual": seconds_actual,
		"remaining_before": remaining_before,
		"remaining_after": remaining_after,
		"completed": bool(reduce_result.get("completed", false)),
		"ready": bool(reduce_result.get("ready", false)),
	}
	_log(
		"Applied %s x%d (req %ds / actual %ds) to %s/%s remaining=%.0f→%.0f completed=%s ready=%s" % [
			iid, qty, total_seconds, seconds_actual, cat, tid,
			remaining_before, remaining_after,
			str(result.get("completed", false)), str(result.get("ready", false)),
		]
	)
	speedup_applied.emit(cat, tid, result)
	if has_node("/root/GameEvents") and GameEvents.has_method("emit_speedup_used") and seconds_actual > 0:
		GameEvents.emit_speedup_used(cat, seconds_actual)
	return result


func _reduce_timer(cat: String, target_id: String, seconds: int) -> Dictionary:
	match cat:
		CAT_CONSTRUCTION:
			if not has_node("/root/ConstructionState"):
				return {"ok": false, "reason": "ConstructionState missing."}
			if ConstructionState.has_method("speedup_construction"):
				return ConstructionState.speedup_construction(target_id, seconds)
			return {"ok": false, "reason": "Construction speedup API missing."}
		CAT_RESEARCH:
			if not has_node("/root/ResearchState"):
				return {"ok": false, "reason": "ResearchState missing."}
			if ResearchState.has_method("speedup_research"):
				return ResearchState.speedup_research(target_id, float(seconds))
			return {"ok": false, "reason": "Research speedup API missing."}
		CAT_TRAINING:
			if not has_node("/root/TroopState"):
				return {"ok": false, "reason": "TroopState missing."}
			if not TroopState.is_training_active(target_id):
				return {"ok": false, "reason": "No active training."}
			TroopState.speedup_training(target_id, seconds)
			var rem: float = float(TroopState.get_training_time_left(target_id))
			var ready: bool = TroopState.is_training_ready(target_id)
			return {"ok": true, "remaining": rem, "completed": false, "ready": ready}
		CAT_HEALING:
			if has_node("/root/HealingState") and HealingState.has_method("speedup_healing"):
				return HealingState.speedup_healing(target_id, seconds)
			return {"ok": false, "reason": "Healing speedups not wired yet."}
		_:
			return {"ok": false, "reason": "Unknown timer category."}


# --- Popup --------------------------------------------------------------------

func open_speedup_popup(timer_category: String, target_id: String) -> void:
	var hud: Node = _find_game_hud()
	if hud == null:
		push_warning("%s No GameHUD — cannot open Speed Up popup" % LOG_PREFIX)
		return
	if _popup == null or not is_instance_valid(_popup):
		var script: Script = load("res://Scripts/UI/SpeedUpPopup.gd") as Script
		_popup = Control.new()
		_popup.set_script(script)
		_popup.name = "SpeedUpPopup"
		hud.add_child(_popup)
		hud.move_child(_popup, hud.get_child_count() - 1)
	if _popup.has_method("open_for"):
		_popup.call("open_for", timer_category, target_id)


func close_speedup_popup() -> void:
	if _popup != null and is_instance_valid(_popup) and _popup.has_method("close"):
		_popup.call("close")


func _find_game_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.find_child("GameHUD", true, false)


# --- Debug --------------------------------------------------------------------

func grant_debug_test_speedups() -> void:
	if not OS.is_debug_build():
		return
	if not has_node("/root/BagState"):
		return
	# Only EXISTING Items.json IDs.
	var grants: Dictionary = {
		"speedup_universal_1h": 10,
		"speedup_universal_8h": 3,
		"speedup_construction_24h": 5,
		"speedup_research_8h": 5,
		"speedup_training_3h": 5,
	}
	for iid: Variant in grants.keys():
		var id_str: String = str(iid)
		if has_node("/root/ItemDatabase") and not ItemDatabase.has_item(id_str):
			continue
		BagState.add_item(id_str, int(grants[iid]))
	_log("Debug granted test speedups")


func _log(msg: String) -> void:
	print("%s %s" % [LOG_PREFIX, msg])
