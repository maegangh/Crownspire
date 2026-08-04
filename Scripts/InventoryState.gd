extends Node

## OBSOLETE (Phase 0A) — recoverable shim only. No independent item store.
## Canonical inventory: BagState → user://bag.cfg
## Autoload retained so legacy scenes do not crash. Do not add new call sites.

## Compatibility accessor — always BagState (no second dictionary).
var items: Dictionary:
	get:
		if has_node("/root/BagState"):
			return BagState.items
		return {}
	set(value):
		_assign_legacy_items(value)


func _ready() -> void:
	print("[InventoryState] OBSOLETE shim active — inventory authority is BagState")


func add_item(item_name: String, amount := 1) -> void:
	if has_node("/root/BagState"):
		BagState.add_item(str(item_name), amount)
		return
	push_warning("[InventoryState] BagState missing; add_item dropped for %s" % item_name)


func get_item_count(item_name: String) -> int:
	if has_node("/root/BagState"):
		return BagState.get_item_count(str(item_name))
	return 0


func remove_item(item_name: String, amount := 1) -> bool:
	if has_node("/root/BagState"):
		return BagState.remove_item(str(item_name), amount)
	return false


## No orphan store — InventoryState never keeps a parallel items dict.
func get_orphan_items_for_migration() -> Dictionary:
	return {}


func _assign_legacy_items(value: Variant) -> void:
	## Legacy: InventoryState.items = save_data["InventoryState.items"]
	## Must use one-time savegame import (not unbounded merge_missing).
	if typeof(value) != TYPE_DICTIONARY:
		return
	if not has_node("/root/BagState"):
		return
	BagState.import_legacy_savegame_inventory_once(value as Dictionary)
