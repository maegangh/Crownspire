extends SceneTree

## Headless smoke: City/World HUD context + resource signal refresh + Events under Shop.
## Run:
##   Godot --headless --path <project> -s res://scripts/dev/city_hud_context_smoke.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: int = 0

	# --- Resource HUD signal ---
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("[CITY HUD SMOKE] GameState missing")
		quit(1)
		return
	if not gs.has_signal("resources_changed"):
		push_error("[CITY HUD SMOKE] resources_changed missing")
		failed += 1

	var hud_script: GDScript = load("res://Scenes/UI/GameHUD.gd") as GDScript
	var city_hud: CanvasLayer = hud_script.new() as CanvasLayer
	city_hud.set("is_world_screen", false)
	# Minimal Control tree expected by @onready is not present — instantiate packed scene instead.
	city_hud.queue_free()

	var packed: PackedScene = load("res://Scenes/UI/GameHUD.tscn") as PackedScene
	if packed == null:
		push_error("[CITY HUD SMOKE] GameHUD.tscn missing")
		quit(1)
		return

	var city: CanvasLayer = packed.instantiate() as CanvasLayer
	city.set("is_world_screen", false)
	root.add_child(city)
	await process_frame
	await process_frame

	var food_before: int = int(gs.get("food"))
	var food_label: Label = city.get_node_or_null("Control/TopBarTexture/TopLabels/FoodLabel") as Label
	if food_label == null:
		push_error("[CITY HUD SMOKE] FoodLabel missing")
		failed += 1
	else:
		gs.call("add_food", 5000)
		await process_frame
		var expected: String = str(city.call("format_number", food_before + 5000))
		if food_label.text != expected:
			push_error("[CITY HUD SMOKE] Food HUD stale got=%s expected=%s" % [food_label.text, expected])
			failed += 1
		else:
			print("[CITY HUD SMOKE] Food HUD sync OK %s" % food_label.text)

	# City context visibility
	var queue: Control = city.get_node_or_null("Control/QueueStatusHUD") as Control
	var marches: Control = city.get_node_or_null("Control/ActiveMarchesHUD") as Control
	if queue == null or not queue.visible:
		push_error("[CITY HUD SMOKE] QueueStatusHUD should be visible on City")
		failed += 1
	else:
		print("[CITY HUD SMOKE] City queues visible OK")
	if marches != null and marches.visible:
		push_error("[CITY HUD SMOKE] ActiveMarchesHUD should be HIDDEN on City")
		failed += 1
	else:
		print("[CITY HUD SMOKE] City marches hidden OK")

	# Right feature stack
	var right: Node = city.get_node_or_null("Control/RightFeatureButtons")
	var shop: Control = city.get_node_or_null("Control/RightFeatureButtons/ShopButton") as Control
	var events: Control = city.get_node_or_null("Control/RightFeatureButtons/EventsButton") as Control
	if right == null or shop == null or events == null:
		push_error("[CITY HUD SMOKE] RightFeatureButtons/Shop/Events missing")
		failed += 1
	else:
		if events.get_global_rect().position.y < shop.get_global_rect().position.y:
			push_error("[CITY HUD SMOKE] Events should be below Shop")
			failed += 1
		else:
			print("[CITY HUD SMOKE] Shop/Events stack OK")
		# Open Events
		var ui: Node = city.get_node_or_null("UIManager")
		if ui != null and ui.has_method("open_screen"):
			ui.call("open_screen", "EventsScreen")
			await process_frame
			if str(ui.call("get_current_screen_name")) != "EventsScreen":
				push_error("[CITY HUD SMOKE] EventsScreen open failed")
				failed += 1
			else:
				print("[CITY HUD SMOKE] Events open OK")
			ui.call("close_current_screen")

	# World context
	city.queue_free()
	await process_frame
	var world: CanvasLayer = packed.instantiate() as CanvasLayer
	world.set("is_world_screen", true)
	root.add_child(world)
	await process_frame
	await process_frame
	queue = world.get_node_or_null("Control/QueueStatusHUD") as Control
	marches = world.get_node_or_null("Control/ActiveMarchesHUD") as Control
	if queue != null and queue.visible:
		push_error("[CITY HUD SMOKE] QueueStatusHUD should be HIDDEN on World")
		failed += 1
	else:
		print("[CITY HUD SMOKE] World queues hidden OK")
	if marches == null or not marches.visible:
		push_error("[CITY HUD SMOKE] ActiveMarchesHUD should be visible on World")
		failed += 1
	else:
		print("[CITY HUD SMOKE] World marches visible OK")

	# Scene export checks
	var city_txt: String = FileAccess.get_file_as_string("res://Scenes/City/City.tscn")
	if "is_world_screen = null" in city_txt:
		push_error("[CITY HUD SMOKE] City.tscn still has is_world_screen = null")
		failed += 1
	elif "is_world_screen = false" not in city_txt:
		push_error("[CITY HUD SMOKE] City.tscn missing is_world_screen = false")
		failed += 1
	else:
		print("[CITY HUD SMOKE] City.tscn is_world_screen=false OK")

	var map_txt: String = FileAccess.get_file_as_string("res://Scenes/World/KingdomMap.tscn")
	if "is_world_screen = true" not in map_txt:
		push_error("[CITY HUD SMOKE] KingdomMap.tscn missing is_world_screen = true")
		failed += 1
	else:
		print("[CITY HUD SMOKE] KingdomMap.tscn is_world_screen=true OK")

	# Wall data audit (expected missing until design provides entry)
	var bfile := FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if bfile != null:
		var parsed: Variant = JSON.parse_string(bfile.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and not (parsed as Dictionary).has("wall"):
			print("[CITY HUD SMOKE] AUDIT: buildings.json has NO wall entry (upgrade window cannot open until data added)")
		elif typeof(parsed) == TYPE_DICTIONARY:
			print("[CITY HUD SMOKE] wall entry present")

	if failed == 0:
		print("[CITY HUD SMOKE] PASSED")
		quit(0)
	else:
		push_error("[CITY HUD SMOKE] FAILED (%d)" % failed)
		quit(1)
