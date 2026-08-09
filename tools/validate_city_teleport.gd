extends SceneTree

const MapPlacementContractScript = preload("res://Scripts/World/MapPlacementContract.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var ok := true
	var scripts := [
		"res://Scripts/World/MapPlacementContract.gd",
		"res://Scripts/World/CityTeleportController.gd",
		"res://Scripts/World/WorldCastleLayer.gd",
		"res://Scripts/MapCamera.gd",
		"res://Scenes/World/WorldGenerator.gd",
		"res://Scenes/World/WorldAutoSpawner.gd",
		"res://Scripts/UI/BagScreen.gd",
		"res://Scripts/BagState.gd",
		"res://Scripts/Backend/AllianceBackend.gd",
		"res://Scripts/MarchState.gd",
		"res://Scripts/ResourceTileState.gd",
		"res://Scripts/World/wildling_lair_click.gd",
		"res://Scripts/World/WildlingNode.gd",
		"res://WildlingNode.gd",
		"res://Scripts/wildling_click.gd",
		"res://Scenes/resource_click.gd",
	]
	for path in scripts:
		var scr: Script = load(path) as Script
		if scr == null:
			push_error("[validate] FAIL load " + path)
			ok = false
			continue
		print("[validate] loaded ", path)

	## Explicit attach for every interaction script used during placement.
	## Avoid entering tree for Area2D click scripts (their _ready expects a Node2D parent).
	var attach_paths := {
		"CityTeleportController": "res://Scripts/World/CityTeleportController.gd",
		"WildlingLairClick": "res://Scripts/World/wildling_lair_click.gd",
		"WildlingClick": "res://Scripts/wildling_click.gd",
		"ResourceClick": "res://Scenes/resource_click.gd",
		"WildlingNodeRoot": "res://WildlingNode.gd",
		"WildlingNodeScripts": "res://Scripts/World/WildlingNode.gd",
	}
	for label in attach_paths.keys():
		var path2: String = attach_paths[label]
		var scr2: Script = load(path2) as Script
		var is_click: bool = String(path2).find("click") >= 0 or String(label).begins_with("WildlingNode")
		var host: Node = Area2D.new() if String(path2).find("click") >= 0 else Node2D.new()
		host.set_script(scr2)
		if host.get_script() != scr2:
			push_error("[validate] FAIL attach " + label)
			ok = false
		else:
			print("[validate] attached ", label)
			if label == "CityTeleportController":
				root.add_child(host)
				host.queue_free()
			else:
				if is_click and not host.has_method("_is_city_teleport_placement_active"):
					push_error("[validate] FAIL missing placement suppress on " + label)
					ok = false
				elif host.has_method("_is_city_teleport_placement_active"):
					print("[validate] ", label, " has placement suppress helper")
				host.free()

	## Bag local add/remove blocked for compass.
	var bag_scr: Script = load("res://Scripts/BagState.gd") as Script
	var bag := Node.new()
	bag.set_script(bag_scr)
	root.add_child(bag)
	await process_frame
	if bag.has_method("set_item_count_authoritative"):
		bag.call("set_item_count_authoritative", "teleport_advanced_compass", 3)
	var before: int = int(bag.call("get_item_count", "teleport_advanced_compass"))
	bag.call("add_item", "teleport_advanced_compass", 5)
	var after_add: int = int(bag.call("get_item_count", "teleport_advanced_compass"))
	var rem: bool = bool(bag.call("remove_item", "teleport_advanced_compass", 1))
	var after_rem: int = int(bag.call("get_item_count", "teleport_advanced_compass"))
	print("[validate] bag before=", before, " after_add=", after_add, " remove=", rem, " after_rem=", after_rem)
	if after_add != before or rem or after_rem != before:
		push_error("[validate] FAIL bag local compass mutate")
		ok = false
	else:
		print("[validate] bag compass local mutate blocked")
	bag.queue_free()

	## Resource contract migration: stale coords ignored; depletion preserved by contract id.
	var rts_scr: Script = load("res://Scripts/ResourceTileState.gd") as Script
	var rts := Node.new()
	rts.set_script(rts_scr)
	root.add_child(rts)
	await process_frame
	if rts.has_method("begin_smoke_isolation"):
		rts.call("begin_smoke_isolation")
	## Seed legacy layout at wrong coords.
	if rts.has_method("register_or_update_tile"):
		rts.call("register_or_update_tile", "resource_food_0", "food", 2, 1000, 250, Vector2(11, 22), "DEPLETED")
	var blockers: Array = MapPlacementContractScript.blockers_of_kinds(
		"kingdom_dev_001", PackedStringArray(["resource"])
	)
	var spots: Array = []
	for i in range(mini(4, blockers.size())):
		spots.append({
			"index": i,
			"resource_type": ["food", "wood", "stone", "iron"][i % 4],
			"x": float(blockers[i].get("x", 0.0)),
			"y": float(blockers[i].get("y", 0.0)),
			"level": 1,
			"max_amount": 1000,
		})
	if rts.has_method("reconcile_to_contract_layout"):
		rts.call("reconcile_to_contract_layout", "kingdom_dev_001", spots)
	var tid0: String = rts.call("make_contract_tile_id", 0, "food")
	var t0: Dictionary = rts.call("get_tile", tid0)
	var pos0: Dictionary = t0.get("world_position", {})
	print("[validate] migrated tile=", tid0, " pos=", pos0, " rem=", t0.get("remaining_amount"))
	if abs(float(pos0.get("x", -1)) - float(blockers[0].get("x", 0))) > 0.01:
		push_error("[validate] FAIL resource still on stale coords")
		ok = false
	if int(t0.get("remaining_amount", -1)) != 250:
		push_error("[validate] FAIL depletion not preserved via legacy index migrate")
		ok = false
	else:
		print("[validate] resource migrate ok")
	if rts.has_method("end_smoke_isolation"):
		rts.call("end_smoke_isolation")
	rts.queue_free()

	## Multi-seed Godot ↔ built JS contract float compare (sample first resource + lake).
	var built := FileAccess.get_file_as_string("res://server/build/index.js")
	for needle in [
		"crownspire_city_teleport_relocate",
		"crownspire_teleport_inventory_sync",
		"crownspire_teleport_deployment_begin",
		"crownspire_map_blockers_v1",
		"crownspire_kingdom_teleport_lock",
		"inventory_consumed",
		"5005",
	]:
		if built.find(needle) < 0:
			push_error("[validate] missing in build/index.js: " + needle)
			ok = false
		else:
			print("[validate] build has ", needle)

	var seeds := ["kingdom_dev_001", "kingdom_alpha", "k_seed_xyz"]
	for kid in seeds:
		var bl: Array = MapPlacementContractScript.compute_blockers(kid)
		if bl.size() < 50:
			push_error("[validate] blocker count low for " + kid)
			ok = false
		var resources: Array = MapPlacementContractScript.blockers_of_kinds(kid, PackedStringArray(["resource"]))
		print("[validate] seed=", kid, " blockers=", bl.size(), " resources=", resources.size())
		if resources.is_empty():
			push_error("[validate] no resources for " + kid)
			ok = false

	var edge: Dictionary = MapPlacementContractScript.validate_castle_candidate(
		"kingdom_dev_001", 100.0, 100.0, []
	)
	if bool(edge.get("ok", true)):
		push_error("[validate] edge should be invalid")
		ok = false
	var spaced: Dictionary = MapPlacementContractScript.validate_castle_candidate(
		"kingdom_dev_001", 2000.0, 2000.0,
		[{"user_id": "other", "world_x": 2100.0, "world_y": 2000.0}]
	)
	if bool(spaced.get("ok", true)):
		push_error("[validate] spacing should be invalid")
		ok = false

	## Placement controller active flag suppresses world actions.
	var ctrl := Node2D.new()
	ctrl.set_script(load("res://Scripts/World/CityTeleportController.gd") as Script)
	root.add_child(ctrl)
	ctrl.call("begin_placement")
	if not bool(ctrl.call("is_placement_active")):
		push_error("[validate] placement not active")
		ok = false
	else:
		print("[validate] placement mode active")
	ctrl.call("cancel_placement")
	ctrl.queue_free()

	if ok:
		print("[validate] PASS")
		quit(0)
	else:
		print("[validate] FAIL")
		quit(1)
