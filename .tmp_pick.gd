extends SceneTree
func _initialize():
	call_deferred("_run")
func _path(n: Node) -> String:
	return str(n.get_path()) if n else "null"
func _run():
	await process_frame
	await process_frame
	var city = load("res://Scenes/City/City.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	for i in 6: await process_frame
	DisplayServer.window_set_size(Vector2i(720, 1280))
	root.get_viewport().size = Vector2i(720, 1280)
	await process_frame
	var packed = load("res://Scenes/AcademyResearchWindow.tscn")
	var research = packed.instantiate()
	city.get_node("GameHUD").add_child(research)
	research.call("open_research")
	for i in 8: await process_frame
	var shell = research.get("_mobile_shell")
	var home = research.get("_mobile_home")
	var cat = research.get("_mobile_category")
	var det = research.get("_mobile_detail")
	var grid = research.get("_mobile_home_grid")
	var content = research.get_node("MainPanel/VBox/ContentArea")
	var tabs = research.get_node("MainPanel/VBox/CategoryTabs")
	print("[Pick] shell size=", shell.size, " pos=", shell.position, " vis=", shell.visible, " mf=", shell.mouse_filter)
	print("[Pick] home size=", home.size, " vis=", home.visible, " mf=", home.mouse_filter)
	print("[Pick] cat size=", cat.size, " vis=", cat.visible, " mf=", cat.mouse_filter)
	print("[Pick] det size=", det.size, " vis=", det.visible, " mf=", det.mouse_filter)
	print("[Pick] content vis=", content.visible, " size=", content.size, " mf=", content.mouse_filter)
	print("[Pick] tabs vis=", tabs.visible, " size=", tabs.size)
	print("[Pick] grid size=", grid.size, " children=", grid.get_child_count())
	if grid.get_child_count() > 0:
		var card = grid.get_child(0)
		print("[Pick] card0 class=", card.get_class(), " size=", card.size, " global=", card.global_position, " disabled=", card.disabled if card is BaseButton else "?")
		print("[Pick] card0 children=", card.get_child_count(), " mf=", card.mouse_filter)
		for ch in card.get_children():
			print("[Pick]  child=", ch.name, " class=", ch.get_class(), " mf=", ch.mouse_filter, " size=", ch.size if ch is Control else "?")
		# Center of first card
		var gp = card.global_position + card.size * 0.5
		print("[Pick] probe=", gp)
		var hovered = root.get_viewport().gui_get_hovered_control()
		# Force mouse position then check
		var ev = InputEventMouseMotion.new()
		ev.position = gp
		ev.global_position = gp
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
		hovered = root.get_viewport().gui_get_hovered_control()
		print("[Pick] hovered=", _path(hovered), " class=", hovered.get_class() if hovered else "null")
		# Also walk who would get click - list controls containing point
		_dump_at(research, gp)
		# Try synthetic click
		var pressed_flag = {"ok": false}
		card.pressed.connect(func(): pressed_flag["ok"] = true)
		var down = InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = gp
		down.global_position = gp
		Input.parse_input_event(down)
		await process_frame
		var up = InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = gp
		up.global_position = gp
		Input.parse_input_event(up)
		await process_frame
		await process_frame
		print("[Pick] synthetic_pressed=", pressed_flag["ok"], " page=", research.get("_mobile_page"))
	quit(0)
func _dump_at(root_n: Node, gp: Vector2) -> void:
	print("[Pick] controls containing point:")
	_walk(root_n, gp, 0)
func _walk(n: Node, gp: Vector2, depth: int) -> void:
	if n is Control:
		var c: Control = n
		if c.is_visible_in_tree():
			var r = Rect2(c.global_position, c.size)
			if r.has_point(gp):
				print("[Pick] ", "  ".repeat(depth), c.name, " mf=", c.mouse_filter, " z=", c.z_index, " size=", c.size, " vis=", c.visible)
	for ch in n.get_children():
		_walk(ch, gp, depth + 1)
