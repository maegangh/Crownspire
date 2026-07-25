extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	await process_frame
	var cs = root.get_node("ConstructionState")
	while int(cs.call("get_used_construction_queues"))>0:
		var jobs=cs.call("get_active_construction_jobs")
		if jobs.is_empty(): break
		cs.call("cancel_construction", str(jobs[0].get("building_id")))
	var city = load("res://Scenes/City/City.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	for i in 5: await process_frame
	# Watchtower
	var wt = city.find_child("WatchTower", true, false)
	if wt == null: wt = city.find_child("Watchtower", true, false)
	print("[B] watchtower=", wt != null, " id=", wt.get("building_id") if wt else "")
	wt.call("open_upgrade_window")
	for i in 3: await process_frame
	var up = city.find_child("BuildingUpgradeWindow", true, false)
	var ui = root.get_node_or_null("UIManager")
	if ui:
		for k in ["food","wood","stone","iron","gold","royal_crystals"]:
			if k in ui: ui.set(k, 9999999)
	var cfg=ConfigFile.new(); cfg.load("user://buildings.cfg")
	var bid = up.building_id
	var before = int(cfg.get_value(bid, "level", 1))
	up.call("_on_upgrade_button_pressed")
	await process_frame
	cfg.load("user://buildings.cfg")
	print("[B] ", bid, " before=", before, " after=", int(cfg.get_value(bid,"level",1)), " job=", cs.call("is_building_upgrading", bid))
	cs.call("cancel_construction", bid)
	# Academy via action popup Upgrade
	var academy = city.find_child("Academy", true, false)
	academy.call("activate_building_tap")
	for i in 3: await process_frame
	city.get_node("GameHUD/BuildingActionPopup").call("_choose", "upgrade")
	for i in 4: await process_frame
	up = city.find_child("BuildingUpgradeWindow", true, false)
	print("[B] academy_window bid=", up.building_id if up else "null", " vis=", up.visible if up else false)
	if up:
		cfg.load("user://buildings.cfg")
		var ab = int(cfg.get_value("academy","level",1))
		up.call("_on_upgrade_button_pressed")
		await process_frame
		cfg.load("user://buildings.cfg")
		print("[B] academy before=", ab, " after=", int(cfg.get_value("academy","level",1)), " job=", cs.call("is_building_upgrading","academy"))
		cs.call("cancel_construction", "academy")
	# Castle
	var castle = city.find_child("Castle", true, false)
	if castle and castle.has_method("activate_building_tap"):
		castle.call("activate_building_tap")
	elif castle and castle.has_method("_open_upgrade_window"):
		castle.call("_open_upgrade_window")
	for i in 4: await process_frame
	up = city.find_child("BuildingUpgradeWindow", true, false)
	print("[B] castle_window bid=", up.building_id if up and up.visible else "closed/null")
	if up and up.visible:
		cfg.load("user://buildings.cfg")
		var cb = int(cfg.get_value(up.building_id,"level",1))
		up.call("_on_upgrade_button_pressed")
		await process_frame
		cfg.load("user://buildings.cfg")
		print("[B] castle before=", cb, " after=", int(cfg.get_value(up.building_id,"level",1)), " job=", cs.call("is_building_upgrading", up.building_id))
	print("[B] DONE")
	quit(0)
