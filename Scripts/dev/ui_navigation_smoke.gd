extends SceneTree

## Android Back / modal dismissal / Profile safe-area smoke.
##   Godot --headless --path <project> -s res://Scripts/dev/ui_navigation_smoke.gd

const MobileSafeArea := preload("res://Scripts/UI/MobileSafeArea.gd")
const ModalOutsideDismiss := preload("res://Scripts/UI/ModalOutsideDismiss.gd")

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame
	print("[UI NAV SMOKE] start")

	var stack: Node = root.get_node_or_null("/root/UiLayerStack")
	_assert(stack != null, "UiLayerStack autoload missing")
	if stack == null:
		_finish()
		return

	_assert(quit_on_go_back == false, "quit_on_go_back must be false so City/World Back does not quit")
	stack.call("reset_for_tests")
	_assert(int(stack.call("layer_count")) == 0, "stack should start empty after reset")
	_assert(bool(stack.call("handle_back")), "empty stack Back must be consumed")
	_assert(int(stack.call("layer_count")) == 0, "empty stack Back must not invent layers")
	await process_frame

	await _test_profile_back_and_safe_area(stack)
	await process_frame
	stack.call("reset_for_tests")
	await _test_speedup_popup(stack)
	await process_frame
	stack.call("reset_for_tests")
	await _test_outside_dismiss_and_leak()
	await process_frame
	stack.call("reset_for_tests")
	await _test_stacking_and_blocking(stack)
	await process_frame
	stack.call("reset_for_tests")
	await _test_building_action_popup(stack)
	await process_frame
	MobileSafeArea.clear_test_margins()
	stack.call("reset_for_tests")

	_finish()


func _finish() -> void:
	if _fail.is_empty():
		print("[UI NAV SMOKE] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[UI NAV SMOKE] FAIL: %s" % f)
		quit(1)


func _test_profile_back_and_safe_area(stack: Node) -> void:
	print("[UI NAV SMOKE] A/B/K Profile Back + Android Back + safe area")
	var profile_script: GDScript = load("res://Scripts/UI/PlayerProfileScreen.gd") as GDScript
	_assert(profile_script != null, "PlayerProfileScreen.gd failed to load")
	if profile_script == null:
		return
	MobileSafeArea.set_test_margins(12.0, 64.0, 10.0, 24.0)
	var profile: Control = profile_script.new() as Control
	profile.name = "NavSmokeProfile"
	profile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile.size = Vector2(720, 1280)
	root.add_child(profile)
	await process_frame
	profile.call("_apply_safe_area")
	await process_frame

	var back: Button = profile.find_child("ProfileBackButton", true, false) as Button
	var header: Control = profile.find_child("ProfileHeader", true, false) as Control
	var root_box: Control = profile.find_child("ProfileRoot", true, false) as Control
	_assert(back != null, "ProfileBackButton missing")
	_assert(header != null, "ProfileHeader missing")
	_assert(root_box != null, "ProfileRoot missing")
	if root_box != null:
		_assert(root_box.offset_top >= 72.0 - 0.5, "K: ProfileRoot offset_top %.1f does not clear 64px safe area" % root_box.offset_top)
	if back != null:
		_assert(back.size.y >= 44.0 or back.custom_minimum_size.y >= 44.0, "Profile back hit target too small")
		profile.visible = true
		profile.mouse_filter = Control.MOUSE_FILTER_STOP
		back.pressed.emit()
		_assert(not profile.visible, "A: visible Profile Back did not close Profile")

	profile.visible = true
	profile.mouse_filter = Control.MOUSE_FILTER_STOP
	stack.call("push_layer", "overlay:PlayerProfileScreen", profile.request_back, "screen", false)
	_assert(str(stack.call("top_id")) == "overlay:PlayerProfileScreen", "Profile layer not on stack")
	stack.call("handle_back")
	_assert(not profile.visible, "B: Android Back did not close Profile")
	await process_frame
	_assert(int(stack.call("layer_count")) == 0, "Profile layer remained after Back")

	profile.queue_free()
	MobileSafeArea.clear_test_margins()
	await process_frame


func _test_speedup_popup(stack: Node) -> void:
	print("[UI NAV SMOKE] C/D SpeedUpPopup X + Android Back")
	var speed_script: GDScript = load("res://Scripts/UI/SpeedUpPopup.gd") as GDScript
	_assert(speed_script != null, "SpeedUpPopup.gd failed to load")
	if speed_script == null:
		return
	var popup: Control = speed_script.new() as Control
	popup.name = "NavSmokeSpeedUp"
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(popup)
	await process_frame
	popup.call("open_for", "construction", "farm")
	await process_frame
	_assert(popup.visible, "SpeedUpPopup did not open")
	_assert(str(stack.call("top_id")) == "modal:SpeedUp", "SpeedUp layer missing")

	var close_btn: Button = popup.get("_close_btn") as Button
	_assert(close_btn != null, "C: SpeedUp visible X missing")
	if close_btn != null:
		close_btn.pressed.emit()
		_assert(not popup.visible, "C: visible X did not close SpeedUpPopup")
	await process_frame
	_assert(int(stack.call("layer_count")) == 0, "SpeedUp layer remained after X")

	popup.call("open_for", "construction", "farm")
	await process_frame
	stack.call("handle_back")
	_assert(not popup.visible, "D: Android Back did not close SpeedUpPopup")
	await process_frame
	popup.queue_free()
	await process_frame


func _test_outside_dismiss_and_leak() -> void:
	print("[UI NAV SMOKE] E/F/G outside-tap dismissal + leak + inside tap")
	var host := Control.new()
	host.name = "NavSmokeHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(720, 1280)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(host)

	var leaked: Array = [false]
	var world_btn := Button.new()
	world_btn.name = "WorldButton"
	world_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_btn.pressed.connect(func() -> void: leaked[0] = true)
	host.add_child(world_btn)

	var closed: Array = [false]
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(160, 400)
	panel.size = Vector2(400, 280)
	panel.custom_minimum_size = Vector2(400, 280)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(panel)
	ModalOutsideDismiss.bind(dim, panel, func() -> void: closed[0] = true)
	await process_frame
	await process_frame

	_assert(dim.mouse_filter == Control.MOUSE_FILTER_STOP, "F: dim must STOP so world is not clicked")

	_pointer_on(dim, Vector2(20, 20), true)
	_pointer_on(dim, Vector2(20, 20), false)
	_assert(bool(closed[0]), "E: outside tap did not close eligible popup")
	_assert(not bool(leaked[0]), "F: outside dismissal activated underlying button")

	closed[0] = false
	var inside: Vector2 = panel.get_global_rect().get_center()
	_pointer_on(dim, inside, true)
	_pointer_on(dim, inside, false)
	_assert(not bool(closed[0]), "G: inside-popup tap dismissed it")

	host.queue_free()
	await process_frame


func _test_stacking_and_blocking(stack: Node) -> void:
	print("[UI NAV SMOKE] H/I/J stacking + one layer per Back + blocking")
	var closed: Array = []
	stack.call("push_layer", "modal:Bottom", func() -> void: closed.append("bottom"), "modal", false)
	stack.call("push_layer", "modal:Top", func() -> void: closed.append("top"), "modal", false)
	_assert(str(stack.call("top_id")) == "modal:Top", "H: top id wrong before Back")
	stack.call("handle_back")
	_assert(closed == ["top"], "H: first Back must close topmost only")
	_assert(int(stack.call("layer_count")) == 1, "I: one Back closed more than one layer")
	_assert(str(stack.call("top_id")) == "modal:Bottom", "H: bottom should remain")
	await process_frame
	stack.call("handle_back")
	_assert(closed == ["top", "bottom"], "second Back should close remaining layer")
	_assert(int(stack.call("layer_count")) == 0, "stack should be empty after two Backs")

	await process_frame
	var blocked: Array = [false]
	stack.call("push_layer", "blocking:Gate", func() -> void: blocked[0] = true, "modal", true)
	stack.call("handle_back")
	_assert(not bool(blocked[0]), "J: blocking modal close_cb must not run")
	_assert(int(stack.call("layer_count")) == 1, "J: blocking modal was popped")
	_assert(bool(stack.call("handle_back")), "J: blocking Back must still be consumed")
	await process_frame

	stack.call("push_layer", "modal:Skip", func() -> void: closed.append("skip"), "modal", false)
	stack.call("handle_back")
	_assert(closed.has("skip"), "skip confirm above blocking should close first")
	_assert(str(stack.call("top_id")) == "blocking:Gate", "blocking layer should remain under skip")


func _test_building_action_popup(stack: Node) -> void:
	print("[UI NAV SMOKE] BuildingActionPopup dismiss via Back")
	var action_script: GDScript = load("res://Scripts/UI/BuildingActionPopup.gd") as GDScript
	_assert(action_script != null, "BuildingActionPopup.gd failed to load")
	if action_script == null:
		return
	var host := Control.new()
	host.name = "ActionHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var popup: Control = action_script.call("present", host, "Hall", [{"id": "upgrade", "label": "Upgrade"}]) as Control
	await process_frame
	_assert(popup != null and is_instance_valid(popup), "BuildingActionPopup.present failed")
	_assert(str(stack.call("top_id")) == "modal:BuildingActionPopup", "action popup not on stack")
	stack.call("handle_back")
	await process_frame
	await process_frame
	_assert(not is_instance_valid(popup) or not popup.visible, "Android Back did not dismiss BuildingActionPopup")
	host.queue_free()
	await process_frame


func _pointer_on(dim: Control, global_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = dim.get_global_transform_with_canvas().affine_inverse() * global_pos
	ev.global_position = global_pos
	dim.gui_input.emit(ev)
