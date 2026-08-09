extends Node

## Canonical player inventory (runtime + persist).
## Phase 0A: single authority for item grants/consumption. Persist: user://bag.cfg

const SAVE_PATH := "user://bag.cfg"
const META_SECTION := "meta"
## One-time: in-memory InventoryState leftovers → bag (boot).
const MIGRATE_INV_FLAG_KEY := "inventory_state_merged_v1"
## One-time: user://savegame.save InventoryState.items → bag.
## Prevents a consumed (count=0) item from being restored on every legacy load_game().
const MIGRATE_SAVEGAME_FLAG_KEY := "savegame_inventory_merged_v1"

var items: Dictionary = {}
var _migrated_from_inventory: bool = false
var _migrated_from_savegame: bool = false


func _ready() -> void:
	load_bag()
	# Autoload order: InventoryState then BagState. Deferred runs after both _ready().
	call_deferred("_deferred_boot_migration")


func _deferred_boot_migration() -> void:
	if not is_inside_tree():
		return
	if not has_node("/root/InventoryState") or not has_node("/root/BagState"):
		push_warning("[BagState] boot migration deferred — autoloads not ready")
		return
	migrate_from_inventory_state_once()


func add_item(item_id: String, amount: int = 1) -> void:
	var id: String = str(item_id).strip_edges()
	if id == "":
		return
	## Server-authoritative teleport charges — never grant locally after reconcile path.
	if id == "teleport_advanced_compass":
		push_warning("[BagState] teleport_advanced_compass is server-authoritative; local add blocked")
		return
	var add_amt: int = maxi(0, amount)
	if add_amt <= 0:
		return
	if not items.has(id):
		items[id] = 0
	items[id] = int(items[id]) + add_amt
	if not save_bag():
		push_error("[BagState] add_item save failed for %s" % id)


func get_item_count(item_id: String) -> int:
	return int(items.get(str(item_id), 0))


func remove_item(item_id: String, amount: int = 1) -> bool:
	var id: String = str(item_id).strip_edges()
	## Server-authoritative teleport charges — never consume locally.
	if id == "teleport_advanced_compass":
		push_warning("[BagState] teleport_advanced_compass is server-authoritative; local remove blocked")
		return false
	var safe_amount: int = maxi(0, amount)
	if safe_amount <= 0:
		return true
	if get_item_count(id) < safe_amount:
		return false
	items[id] = get_item_count(id) - safe_amount
	if int(items[id]) <= 0:
		items.erase(id)
	if not save_bag():
		push_error("[BagState] remove_item save failed for %s" % id)
		return false
	return true


## Mirror server balance into local bag display (teleport inventory).
func set_item_count_authoritative(item_id: String, count: int) -> void:
	var id: String = str(item_id).strip_edges()
	if id == "":
		return
	var n: int = maxi(0, count)
	if n <= 0:
		items.erase(id)
	else:
		items[id] = n
	save_bag()


func save_bag() -> bool:
	var save := ConfigFile.new()
	save.set_value(META_SECTION, MIGRATE_INV_FLAG_KEY, _migrated_from_inventory)
	save.set_value(META_SECTION, MIGRATE_SAVEGAME_FLAG_KEY, _migrated_from_savegame)
	for item_id in items.keys():
		var count: int = int(items[item_id])
		if count > 0:
			save.set_value("items", str(item_id), count)
	var err: Error = save.save(SAVE_PATH)
	if err != OK:
		push_error("[BagState] save_bag failed path=%s err=%s" % [SAVE_PATH, str(err)])
		return false
	return true


func load_bag() -> void:
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) != OK:
		items.clear()
		_migrated_from_inventory = false
		_migrated_from_savegame = false
		return
	_migrated_from_inventory = bool(save.get_value(META_SECTION, MIGRATE_INV_FLAG_KEY, false))
	_migrated_from_savegame = bool(save.get_value(META_SECTION, MIGRATE_SAVEGAME_FLAG_KEY, false))
	items.clear()
	if save.has_section("items"):
		for item_id in save.get_section_keys("items"):
			var count: int = int(save.get_value("items", item_id, 0))
			if count > 0:
				items[str(item_id)] = count


func has_completed_savegame_inventory_migration() -> bool:
	return _migrated_from_savegame


## One-time boot merge from InventoryState shim (no independent store anymore).
## Marks complete even when source is empty so we do not re-run forever.
func migrate_from_inventory_state_once() -> void:
	if _migrated_from_inventory:
		return
	var source := {}
	# Shim exposes BagState.items via getter — not an independent dict.
	# Capture only if InventoryState still exposes a private orphan (it should not).
	if has_node("/root/InventoryState"):
		var inv: Node = get_node("/root/InventoryState")
		if inv.has_method("get_orphan_items_for_migration"):
			var orphan: Variant = inv.call("get_orphan_items_for_migration")
			if typeof(orphan) == TYPE_DICTIONARY:
				source = orphan as Dictionary
	var snapshot: Dictionary = items.duplicate()
	_merge_missing_into_memory(source)
	_migrated_from_inventory = true
	if not save_bag():
		items = snapshot
		_migrated_from_inventory = false
		push_error("[BagState] InventoryState migration NOT marked complete — save failed; will retry next boot")
		return
	print("[BagState] Phase0A inventory_state_merged_v1=true (saved)")


## One-time import from user://savegame.save InventoryState.items.
## Safe after consume-to-zero: later load_game() calls are no-ops once flagged.
func import_legacy_savegame_inventory_once(source: Dictionary) -> bool:
	if _migrated_from_savegame:
		print("[BagState] skip savegame inventory import (savegame_inventory_merged_v1 already set)")
		return false
	var src: Dictionary = source if source != null else {}
	var snapshot: Dictionary = items.duplicate()
	_merge_missing_into_memory(src)
	_migrated_from_savegame = true
	if not save_bag():
		items = snapshot
		_migrated_from_savegame = false
		push_error("[BagState] savegame inventory import NOT marked complete — save failed; source retained for retry")
		return false
	print("[BagState] Phase0A savegame_inventory_merged_v1=true (saved)")
	return true


## Unrestricted merge helper (does NOT set one-time flags).
## Prefer import_legacy_savegame_inventory_once() for savegame.save paths.
func merge_missing_from_dict(source: Dictionary, source_label: String = "legacy") -> bool:
	if source.is_empty():
		return false
	var snapshot: Dictionary = items.duplicate()
	var changed: bool = _merge_missing_into_memory(source)
	if not changed:
		return false
	if not save_bag():
		items = snapshot
		push_error("[BagState] merge_missing_from_dict save failed (%s) — memory rolled back" % source_label)
		return false
	print("[BagState] merged items from %s (missing keys only)" % source_label)
	return true


func _merge_missing_into_memory(source: Dictionary) -> bool:
	## For each source id: if bag count == 0, copy source count; else keep bag.
	## Note: count==0 after a real consume must NOT be refilled by a flagged one-time import.
	if source.is_empty():
		return false
	var changed: bool = false
	for raw_key in source.keys():
		var id: String = str(raw_key).strip_edges()
		if id == "":
			continue
		if id == "teleport_advanced_compass":
			continue
		var src_count: int = int(source[raw_key])
		if src_count <= 0:
			continue
		if get_item_count(id) > 0:
			continue
		items[id] = src_count
		changed = true
	return changed
