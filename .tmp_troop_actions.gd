extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	await process_frame
	await process_frame
	var city = load("res://Scenes/City/City.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	for i in 6: await process_frame
	var cases = [
		["InfantryBarracks", "infantry_barracks", "Infantry"],
		["MarksmenCamp", "marksmen_camp", "Marksmen"],
		["CavalryStable", "cavalry_stable", "Cavalry"],
	]
	# find nodes by building_id
	var ok = true
	for c in cases:
		var bid = c[1]
		var expected_type = c[2]
		var node = null
		for n in city.find_children("*", "Node", true, false):
			if n.get("building_id") != null and str(n.get("building_id")) == bid:
				node = n
				break
		print("[TB] node_", bid, "=", node != null)
		if node == null:
			ok = false
			continue
		node.call("activate_building_tap")
		for i in 3: await process_frame
		var popup = city.get_node_or_null("GameHUD/BuildingActionPopup")
		var labels = []
		if popup:
			for b in popup.find_children("*", "Button", true, false):
				labels.append(b.text)
		print("[TB] popup_", bid, "=", labels)
		if popup == null or not ("Train" in labels) or not ("Upgrade" in labels):
			ok = false
			continue
		# Train
		popup.call("_choose", "train")
		for i in 5: await process_frame
		var screen = city.get_node_or_null("GameHUD/ScreenRoot/TroopTrainingScreen")
		var typ = screen.get("_troop_type") if screen else "?"
		var vis = screen.visible if screen else false
		print("[TB] train_", bid, " type=", typ, " vis=", vis)
		if typ != expected_type or not vis:
			ok = false
		# close training if possible
		if screen and screen.has_method("close"):
			screen.call("close")
		elif screen and screen.has_method("_on_close_pressed"):
			screen.call("_on_close_pressed")
		elif screen:
			screen.visible = false
			root.get_node("GameState").popup_open = false
		for i in 3: await process_frame
		# Upgrade
		node.call("activate_building_tap")
		for i in 3: await process_frame
		popup = city.get_node("GameHUD/BuildingActionPopup")
		popup.call("_choose", "upgrade")
		for i in 5: await process_frame
		var up = city.find_child("BuildingUpgradeWindow", true, false)
		print("[TB] upgrade_", bid, " win_bid=", up.building_id if up else "null", " vis=", up.visible if up else false)
		if up == null or not up.visible or str(up.building_id) != bid:
			ok = false
		if up:
			up.visible = false
			root.get_node("GameState").popup_open = false
		for i in 2: await process_frame
	print("[TB] ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 2)
