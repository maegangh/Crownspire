extends Control

## Presentation-only FTUE overlay. Reads TutorialState; never mutates gameplay.

const Resolver = preload("res://scripts/UI/TutorialTargetResolver.gd")
const LOG_PREFIX := "[TUTORIAL UI]"

const COLOR_DIM := Color(0.04, 0.08, 0.16, 0.72)
const COLOR_PANEL := Color(0.07, 0.12, 0.22, 0.96)
const COLOR_GOLD := Color(0.85, 0.72, 0.38, 1.0)
const COLOR_SAPPHIRE := Color(0.22, 0.45, 0.78, 1.0)
const COLOR_MARBLE := Color(0.93, 0.94, 0.96, 1.0)
const BOTTOM_HUD_RESERVE := 200.0
const TOP_SAFE := 96.0
## Dim/blockers stay under interactive chrome so STOP dims never steal button clicks.
const Z_DIM := 0
const Z_HIGHLIGHT := 1
const Z_CHROME := 20
const Z_SKIP_CONFIRM := 30

var _hud: Node = null
var _blocker_top: ColorRect
var _blocker_bottom: ColorRect
var _blocker_left: ColorRect
var _blocker_right: ColorRect
var _full_dim: ColorRect
var _highlight: Panel
var _pointer: Control
var _panel: PanelContainer
var _title: Label
var _body: Label
var _btn_row: HBoxContainer
var _continue_btn: Button
var _skip_btn: Button
var _guide_badge: Label

var _skip_layer: Control
var _skip_title: Label
var _skip_cancel: Button
var _skip_confirm: Button

var _current_step_id: String = ""
var _pending_step: Dictionary = {}
var _focus_result: Dictionary = {}
var _hole: Rect2 = Rect2()
var _showing_completion: bool = false
var _built: bool = false
var _is_ack_mode: bool = false
var _debug_start_token: int = 0
var _awaiting_dynamic_target: bool = false


func _ready() -> void:
	_hud = get_parent()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 250
	visible = false
	_build_ui()
	_connect_tutorial_signals()
	set_process(false)
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	if not has_node("/root/TutorialState"):
		return
	if TutorialState.is_ftue_active():
		_show_current_step()
		return
	if TutorialState.is_ftue_complete() and str(TutorialState.get_current_step_id()) == "ftue_complete":
		# Completed sessions stay quiet unless just finished this launch.
		return
	if TutorialState.should_auto_start_ftue():
		_log("First-run auto-start")
		TutorialState.begin_ftue()
		_show_current_step()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# F9 — debug reset + begin FTUE (tutorial save only).
		if event.keycode == KEY_F9:
			_debug_restart_ftue()
			get_viewport().set_input_as_handled()
		# F10 — emergency skip (debug only).
		elif event.keycode == KEY_F10 and has_node("/root/TutorialState"):
			TutorialState.skip_ftue()
			_log("Debug skip FTUE (F10)")
			get_viewport().set_input_as_handled()


func _debug_restart_ftue() -> void:
	if not has_node("/root/TutorialState"):
		return
	# Clear stale dim/blocker/skip state BEFORE restart so the first Welcome is interactive.
	_reset_presentation_input_state()
	TutorialState.debug_reset_ftue()
	_debug_start_token += 1
	var token: int = _debug_start_token
	TutorialState.begin_ftue()
	_log("Debug restart FTUE (F9)")
	# Signals already refresh the step; finalize next frame so chrome hit-targets are valid.
	call_deferred("_finalize_debug_ftue_start", token)


func _finalize_debug_ftue_start(token: int) -> void:
	if token != _debug_start_token:
		return
	if not has_node("/root/TutorialState") or not TutorialState.is_ftue_active():
		return
	_ensure_overlay_on_top()
	_show_current_step()
	_ensure_ack_chrome_interactive()
	# Second pass after Control size/anchors settle (first-press dead-input fix).
	call_deferred("_ensure_ack_chrome_interactive")


func _reset_presentation_input_state() -> void:
	_skip_layer.visible = false
	_skip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awaiting_dynamic_target = false
	_focus_result = {}
	_hole = Rect2()
	_set_spotlight_visible(false)
	_clear_blockers()
	_apply_full_dim(false)
	_full_dim.visible = false
	_full_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.visible = false
	set_process(false)


func _ensure_overlay_on_top() -> void:
	var parent: Node = get_parent()
	if parent != null:
		parent.move_child(self, parent.get_child_count() - 1)
	z_index = 250
	visible = true


func _ensure_ack_chrome_interactive() -> void:
	if not visible or not _is_ack_mode:
		# Still raise skip if visible on action steps.
		_raise_interactive_chrome()
		return
	_ensure_overlay_on_top()
	_apply_full_dim(true)
	_place_acknowledge_panel(_viewport_size())
	_continue_btn.visible = true
	_continue_btn.disabled = false
	_continue_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if _btn_row != null:
		_btn_row.visible = true
	_skip_btn.visible = not _showing_completion
	_skip_btn.disabled = false
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_raise_interactive_chrome()


func _process(_delta: float) -> void:
	if not visible or _current_step_id.is_empty():
		return
	if _awaiting_dynamic_target:
		_retry_dynamic_target()
		return
	if bool(_focus_result.get("ok", false)) and _focus_result.get("node2d") != null:
		_refresh_focus_rect()
		_layout_spotlight(_hole)


func _retry_dynamic_target() -> void:
	if _pending_step.is_empty():
		return
	var result: Dictionary = Resolver.resolve(_hud, _pending_step)
	if not bool(result.get("ok", false)):
		return
	_focus_result = result
	_hole = Resolver.rect_for_result(_focus_result, 14.0)
	_awaiting_dynamic_target = false
	_log("Dynamic target became available: %s" % str(_focus_result.get("label", "")))
	var block: bool = bool(_pending_step.get("block_unrelated_input", false))
	var show_pointer: bool = bool(_pending_step.get("show_pointer", false))
	if block and _hole.size.x > 0.0:
		_apply_full_dim(false)
		_set_spotlight_visible(true)
		_layout_spotlight(_hole)
		_pointer.visible = show_pointer
		_place_panel(str(_pending_step.get("preferred_panel_position", "auto")), _hole)
		_raise_interactive_chrome()
	set_process(_focus_result.get("node2d") != null)


func _connect_tutorial_signals() -> void:
	if not has_node("/root/TutorialState"):
		return
	var ts: Node = TutorialState
	if not ts.step_changed.is_connected(_on_step_changed):
		ts.step_changed.connect(_on_step_changed)
	if not ts.tutorial_started.is_connected(_on_tutorial_started):
		ts.tutorial_started.connect(_on_tutorial_started)
	if not ts.tutorial_completed.is_connected(_on_tutorial_completed):
		ts.tutorial_completed.connect(_on_tutorial_completed)
	if not ts.tutorial_skipped.is_connected(_on_tutorial_skipped):
		ts.tutorial_skipped.connect(_on_tutorial_skipped)


func _on_tutorial_started() -> void:
	_show_current_step()


func _on_step_changed(step_id: String) -> void:
	_log("Step changed: %s" % step_id)
	_show_step(step_id)


func _on_tutorial_completed() -> void:
	if TutorialState.get("skipped"):
		_close_overlay()
		return
	_show_step("ftue_complete")


func _on_tutorial_skipped() -> void:
	_close_overlay()


func _show_current_step() -> void:
	if not has_node("/root/TutorialState"):
		return
	_show_step(TutorialState.get_current_step_id())


func _show_step(step_id: String) -> void:
	if step_id.is_empty():
		_close_overlay()
		return
	_current_step_id = step_id
	var step: Dictionary = {}
	if has_node("/root/TutorialState"):
		if step_id == TutorialState.get_current_step_id():
			step = TutorialState.get_current_step()
		else:
			# Completion display may request ftue_complete while state already there.
			step = TutorialState.get_current_step()
			if str(step.get("step_id", "")) != step_id:
				step = _find_step_def(step_id)
	if step.is_empty():
		step = _find_step_def(step_id)
	if step.is_empty():
		_log("Missing step def: %s" % step_id)
		return

	_log("Showing step: %s" % step_id)
	visible = true
	_ensure_overlay_on_top()
	_skip_layer.visible = false
	_skip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showing_completion = step_id == "ftue_complete"
	_pending_step = step.duplicate(true)
	_awaiting_dynamic_target = false

	var mode: String = str(step.get("mode", "action"))
	_title.text = str(step.get("title", "TUTORIAL"))
	_body.text = str(step.get("instruction", ""))
	var cont_label: String = str(step.get("continue_label", "CONTINUE"))
	_continue_btn.text = cont_label

	_is_ack_mode = mode == "acknowledge" or step_id == "intro_welcome" or step_id == "ftue_complete"
	# Acknowledge: CONTINUE visible. Action: player uses the real highlighted target.
	_continue_btn.visible = _is_ack_mode
	_continue_btn.disabled = false
	if _btn_row != null:
		_btn_row.visible = _is_ack_mode
	_skip_btn.visible = not _showing_completion and bool(step.get("can_skip", true))
	_skip_btn.disabled = false
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	_focus_result = {}
	_hole = Rect2()
	var block: bool = bool(step.get("block_unrelated_input", false))
	var show_pointer: bool = bool(step.get("show_pointer", false))
	var ttype: String = str(step.get("target_type", "")).strip_edges()

	if not ttype.is_empty():
		_focus_result = Resolver.resolve(_hud, step)
		if bool(_focus_result.get("ok", false)):
			_log("Focus: %s" % str(_focus_result.get("label", "")))
			_hole = Resolver.rect_for_result(_focus_result, 14.0)
		else:
			_log("Target unresolved: %s/%s" % [ttype, str(step.get("target_id", ""))])
			# Dynamic targets (collect icon) may appear later — retry, never fall back to building art.
			if ttype == "resource_collect_icon":
				_awaiting_dynamic_target = true

	if _is_ack_mode:
		# Visual full-screen dim blocks gameplay, but stays UNDER chrome (z_index).
		_apply_full_dim(true)
		_set_spotlight_visible(false)
		_pointer.visible = false
		set_process(false)
		call_deferred("_ensure_ack_chrome_interactive")
	elif block and _hole.size.x > 0.0:
		_apply_full_dim(false)
		_set_spotlight_visible(true)
		_layout_spotlight(_hole)
		_pointer.visible = show_pointer
		set_process(_focus_result.get("node2d") != null or _awaiting_dynamic_target)
	elif _awaiting_dynamic_target:
		# Instruction only — no incorrect Farm-building spotlight.
		_apply_full_dim(false)
		_set_spotlight_visible(false)
		_full_dim.visible = false
		_clear_blockers()
		_pointer.visible = false
		set_process(true)
	else:
		_apply_full_dim(false)
		_set_spotlight_visible(false)
		_full_dim.visible = false
		_clear_blockers()
		_pointer.visible = false
		set_process(false)

	_place_panel(str(step.get("preferred_panel_position", "auto")), _hole)
	_raise_interactive_chrome()
	# If the next FTUE target lives in City/World/HUD, close obsolete screen modals
	# that would cover the spotlight (e.g. BuildingUpgradeWindow over Farm CollectIcon).
	_dismiss_obstructing_modals_for_step(step)


func _step_needs_external_target_access(step: Dictionary) -> bool:
	var ttype: String = str(step.get("target_type", "")).strip_edges()
	match ttype:
		"city_building", "resource_collect_icon", "world_target", "hud_control":
			return true
		_:
			return false


func _dismiss_obstructing_modals_for_step(step: Dictionary) -> void:
	## Targeted only — do not nuke every popup on every step change.
	var ttype: String = str(step.get("target_type", "")).strip_edges()
	var tid: String = str(step.get("target_id", "")).strip_edges()
	var step_id: String = str(step.get("step_id", "")).strip_edges()
	var needs_external: bool = _step_needs_external_target_access(step)
	# After upgrade-start, complete/collect steps also need the city surface.
	if step_id in ["complete_building_upgrade", "collect_resources"]:
		needs_external = true

	if needs_external:
		# Must clear GameHUD/UIManager ownership — visual-only on_close leaves
		# is_screen_open() true and PopupBackground STOP-blocking city taps.
		_safe_close_hud_screen_if_open()
		_safe_close_building_action_popup()
		_safe_close_building_upgrade_window()
		_safe_close_academy_research_window()
		_safe_close_troop_training_screen()
		_safe_close_march_setup_screen()

	# screen_control steps keep their own screen; close unrelated city modals only.
	if ttype == "screen_control":
		if not tid.begins_with("TroopTraining"):
			_safe_close_troop_training_screen()
		if tid.findn("Academy") < 0 and tid.findn("Research") < 0:
			_safe_close_academy_research_window()
		_safe_close_building_upgrade_window()


func _hud_ui_manager() -> Node:
	## GameHUD child owns ScreenRoot navigation. Autoload /root/UIManager does NOT.
	if _hud == null:
		return null
	return _hud.get_node_or_null("UIManager")


func _safe_close_hud_screen_if_open() -> void:
	var mgr: Node = _hud_ui_manager()
	if mgr == null or not mgr.has_method("is_screen_open"):
		return
	if not bool(mgr.call("is_screen_open")):
		return
	var name_now: String = ""
	if mgr.has_method("get_current_screen_name"):
		name_now = str(mgr.call("get_current_screen_name"))
	_log("Closing obstructing HUD screen via GameHUD/UIManager: %s" % name_now)
	if mgr.has_method("close_current_screen"):
		mgr.call("close_current_screen")
	if has_node("/root/GameState"):
		GameState.popup_open = false


func _safe_close_building_action_popup() -> void:
	var popup: Node = _find_hud_child("BuildingActionPopup")
	if popup == null:
		return
	_log("Closing obstructing BuildingActionPopup for external FTUE target")
	if popup.has_method("dismiss"):
		popup.call("dismiss")
	else:
		popup.queue_free()
	if has_node("/root/GameState"):
		GameState.popup_open = false


func _safe_close_building_upgrade_window() -> void:
	var win: Node = _find_hud_child("BuildingUpgradeWindow")
	if win == null:
		return
	if win is CanvasItem and not (win as CanvasItem).visible:
		return
	_log("Closing obstructing BuildingUpgradeWindow for external FTUE target")
	if has_node("/root/GameState"):
		GameState.popup_open = false
	if win.has_method("_on_close_button_pressed"):
		win.call("_on_close_button_pressed")
	elif win.has_method("hide"):
		win.call("hide")
	elif win is CanvasItem:
		(win as CanvasItem).visible = false


func _safe_close_academy_research_window() -> void:
	var win: Node = _find_hud_child("AcademyResearchWindow")
	if win == null and _hud != null and _hud.get_tree() != null:
		win = _hud.get_tree().root.find_child("AcademyResearchWindow", true, false)
	if win == null:
		return
	if win is CanvasItem and not (win as CanvasItem).visible:
		return
	_log("Closing obstructing AcademyResearchWindow for external FTUE target")
	# Prefer hide over queue_free so the window can reopen later.
	if win is Control:
		(win as Control).visible = false
		(win as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif win.has_method("hide"):
		win.call("hide")
	if has_node("/root/GameState"):
		GameState.popup_open = false


func _safe_close_troop_training_screen() -> void:
	var mgr: Node = _hud_ui_manager()
	if mgr != null and mgr.has_method("get_current_screen_name"):
		if str(mgr.call("get_current_screen_name")) == "TroopTrainingScreen":
			_log("Closing obstructing TroopTrainingScreen via GameHUD/UIManager")
			mgr.call("close_current_screen")
			if has_node("/root/GameState"):
				GameState.popup_open = false
			return

	var screen: Node = null
	if _hud != null:
		screen = _hud.get_node_or_null("ScreenRoot/TroopTrainingScreen")
	if screen == null:
		screen = _find_hud_child("TroopTrainingScreen")
	if screen == null:
		return
	if screen is CanvasItem and not (screen as CanvasItem).visible:
		return
	_log("Closing obstructing TroopTrainingScreen (fallback visual close)")
	if screen.has_method("on_close"):
		screen.call("on_close")
	elif screen is Control:
		(screen as Control).visible = false
		(screen as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("/root/GameState"):
		GameState.popup_open = false


func _safe_close_march_setup_screen() -> void:
	var mgr: Node = _hud_ui_manager()
	if mgr != null and mgr.has_method("get_current_screen_name"):
		var name_now: String = str(mgr.call("get_current_screen_name"))
		if name_now == "MarchSetupScreen" or name_now == "RallySetupScreen":
			_log("Closing obstructing %s via GameHUD/UIManager" % name_now)
			mgr.call("close_current_screen")
			if has_node("/root/GameState"):
				GameState.popup_open = false
			return

	var screen: Node = null
	if _hud != null:
		screen = _hud.get_node_or_null("ScreenRoot/MarchSetupScreen")
	if screen == null:
		return
	if screen is CanvasItem and not (screen as CanvasItem).visible:
		return
	_log("Closing obstructing MarchSetupScreen (fallback visual close)")
	if screen.has_method("on_close"):
		screen.call("on_close")
	elif screen is Control:
		(screen as Control).visible = false
		(screen as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("/root/GameState"):
		GameState.popup_open = false


func _find_hud_child(node_name: String) -> Node:
	if _hud == null:
		return null
	var direct: Node = _hud.get_node_or_null(node_name)
	if direct != null:
		return direct
	return _hud.find_child(node_name, true, false)


func _find_step_def(step_id: String) -> Dictionary:
	if not has_node("/root/TutorialState"):
		return {}
	# TutorialState keeps private map; use get_current or reload from file lightly.
	var path := "res://data/tutorial_ftue.json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	for item: Variant in (parsed as Dictionary).get("steps", []):
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("step_id", "")) == step_id:
			return (item as Dictionary).duplicate(true)
	return {}


func _refresh_focus_rect() -> void:
	if not bool(_focus_result.get("ok", false)):
		return
	_hole = Resolver.rect_for_result(_focus_result, 14.0)


func _on_continue_pressed() -> void:
	if _showing_completion or _current_step_id == "ftue_complete":
		_close_overlay()
		return
	if _current_step_id == "intro_welcome" and has_node("/root/TutorialState"):
		TutorialState.acknowledge_intro()
		# step_changed will refresh UI


func _on_skip_pressed() -> void:
	_skip_layer.visible = true
	_raise_interactive_chrome()
	_skip_layer.move_to_front()


func _on_skip_cancel() -> void:
	_skip_layer.visible = false


func _on_skip_confirm() -> void:
	_skip_layer.visible = false
	if has_node("/root/TutorialState"):
		TutorialState.skip_ftue()
	_close_overlay()


func _close_overlay() -> void:
	visible = false
	_current_step_id = ""
	_focus_result = {}
	_hole = Rect2()
	_set_spotlight_visible(false)
	_apply_full_dim(false)
	_full_dim.visible = false
	_clear_blockers()
	_pointer.visible = false
	_skip_layer.visible = false
	set_process(false)
	_log("Overlay closed")


# --- Layout / spotlight -------------------------------------------------------

func _viewport_size() -> Vector2:
	var vp: Vector2 = size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = get_viewport_rect().size
	return vp


func _raise_interactive_chrome() -> void:
	## Keep panel / skip / confirm above FullDim + blockers regardless of prior move_to_front.
	if _panel != null:
		_panel.z_index = Z_CHROME
		# Acknowledge: panel/CONTINUE must receive taps.
		# Action: instruction card is display-only — STOP here swallows city building taps
		# (especially when measure/layout briefly inflates the panel rect).
		_panel.mouse_filter = (
			Control.MOUSE_FILTER_STOP if _is_ack_mode else Control.MOUSE_FILTER_IGNORE
		)
		_panel.move_to_front()
	if _skip_btn != null:
		_skip_btn.z_index = Z_CHROME + 1
		_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_skip_btn.move_to_front()
	if _skip_layer != null and _skip_layer.visible:
		_skip_layer.z_index = Z_SKIP_CONFIRM
		_skip_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		_skip_layer.move_to_front()


func _apply_full_dim(on: bool) -> void:
	_full_dim.visible = on
	_full_dim.z_index = Z_DIM
	# STOP so gameplay under the overlay is blocked; chrome uses higher z_index.
	_full_dim.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		_clear_blockers()
		# Ensure dim sits under chrome in tree order too.
		move_child(_full_dim, 0)


func _set_spotlight_visible(on: bool) -> void:
	_highlight.visible = on
	_blocker_top.visible = on
	_blocker_bottom.visible = on
	_blocker_left.visible = on
	_blocker_right.visible = on
	var filt: Control.MouseFilter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	for b: ColorRect in [_blocker_top, _blocker_bottom, _blocker_left, _blocker_right]:
		b.mouse_filter = filt
		b.z_index = Z_DIM
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.z_index = Z_HIGHLIGHT
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.z_index = Z_HIGHLIGHT


func _clear_blockers() -> void:
	for b: ColorRect in [_blocker_top, _blocker_bottom, _blocker_left, _blocker_right]:
		b.visible = false
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false


func _layout_spotlight(hole: Rect2) -> void:
	var vp: Vector2 = _viewport_size()
	hole = hole.intersection(Rect2(Vector2.ZERO, vp))
	if hole.size.x < 8.0 or hole.size.y < 8.0:
		# Keep the last good spotlight — camera canvas transforms can lag one frame
		# after focus_world_position, and clearing here blanks the hole (and its
		# input pass-through) for that frame.
		if _highlight != null and _highlight.visible and _highlight.size.x >= 8.0:
			_raise_interactive_chrome()
			return
		_clear_blockers()
		return

	# Shrink hole so it never covers Skip (top-right) or the instruction panel.
	hole = _hole_excluding_chrome(hole, vp)

	# Restore visibility if a prior off-screen frame called _clear_blockers().
	if not _highlight.visible or not _blocker_top.visible:
		_set_spotlight_visible(true)

	_blocker_top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_blocker_top.position = Vector2.ZERO
	_blocker_top.size = Vector2(vp.x, maxf(0.0, hole.position.y))

	_blocker_bottom.position = Vector2(0.0, hole.end.y)
	_blocker_bottom.size = Vector2(vp.x, maxf(0.0, vp.y - hole.end.y))

	_blocker_left.position = Vector2(0.0, hole.position.y)
	_blocker_left.size = Vector2(maxf(0.0, hole.position.x), hole.size.y)

	_blocker_right.position = Vector2(hole.end.x, hole.position.y)
	_blocker_right.size = Vector2(maxf(0.0, vp.x - hole.end.x), hole.size.y)

	_highlight.position = hole.position
	_highlight.size = hole.size

	if _pointer.visible:
		_pointer.position = Vector2(hole.get_center().x - 18.0, hole.end.y + 6.0)

	_raise_interactive_chrome()


func _hole_excluding_chrome(hole: Rect2, vp: Vector2) -> Rect2:
	## Chrome sits above blockers via z_index; only clamp hole to the viewport.
	return hole.intersection(Rect2(Vector2.ZERO, vp))


func _place_panel(pref: String, hole: Rect2) -> void:
	var vp: Vector2 = _viewport_size()
	if _is_ack_mode:
		_place_acknowledge_panel(vp)
		return
	_place_action_panel(pref, hole, vp)


func _place_acknowledge_panel(vp: Vector2) -> void:
	## Compact upper welcome / completion card for short portrait windows (e.g. 383×682).
	## Do NOT call reset_size() here — zero-width autowrap can explode panel height.
	var side_pad: float = maxf(16.0, vp.x * 0.05)
	var panel_w: float = minf(520.0, vp.x - side_pad * 2.0)
	var panel_h: float = clampf(vp.y * 0.30, 150.0, 210.0)
	_title.add_theme_font_size_override("font_size", 20 if vp.y < 800.0 else 24)
	_body.add_theme_font_size_override("font_size", 14 if vp.y < 800.0 else 16)
	# Give labels a real wrap width before layout.
	_title.custom_minimum_size = Vector2(panel_w - 70.0, 0.0)
	_body.custom_minimum_size = Vector2(panel_w - 36.0, 0.0)
	_continue_btn.visible = true
	if _btn_row != null:
		_btn_row.visible = true
	_continue_btn.custom_minimum_size = Vector2(minf(180.0, panel_w - 48.0), 44.0)
	_panel.custom_minimum_size = Vector2(panel_w, panel_h)
	_panel.size = Vector2(panel_w, panel_h)

	var x: float = (vp.x - panel_w) * 0.5
	# Upper band: below top HUD — avoid old center*0.42 which sat too low.
	var top_pad: float = 12.0 + minf(TOP_SAFE, vp.y * 0.12)
	if vp.y < 720.0:
		top_pad = maxf(10.0, vp.y * 0.08)
	var max_y: float = maxf(8.0, vp.y - panel_h - maxf(20.0, vp.y * 0.06))
	var y: float = clampf(top_pad, 8.0, max_y)
	_panel.position = Vector2(x, y)


func _place_action_panel(pref: String, hole: Rect2, vp: Vector2) -> void:
	## Compact content-driven instruction card — never a tall full-screen panel.
	var side_pad: float = maxf(16.0, vp.x * 0.05)
	var panel_w: float = minf(640.0, vp.x - side_pad * 2.0)
	_title.add_theme_font_size_override("font_size", 18 if vp.y < 800.0 else 20)
	_body.add_theme_font_size_override("font_size", 13 if vp.y < 800.0 else 15)

	_continue_btn.visible = false
	_continue_btn.custom_minimum_size = Vector2.ZERO
	if _btn_row != null:
		_btn_row.visible = false
		_btn_row.custom_minimum_size = Vector2.ZERO

	# Explicit wrap width BEFORE height measure (avoids zero-width autowrap blow-up).
	var title_w: float = maxf(80.0, panel_w - 70.0)
	var body_w: float = maxf(80.0, panel_w - 36.0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 2
	_body.max_lines_visible = 4
	_title.custom_minimum_size = Vector2(title_w, 0.0)
	_body.custom_minimum_size = Vector2(body_w, 0.0)

	var content_h: float = _measure_action_panel_height(panel_w)
	# Target ~90–150px on short portrait; hard-cap so action cards stay compact.
	var max_h: float = minf(150.0, maxf(120.0, vp.y * 0.22))
	var panel_h: float = clampf(content_h, 88.0, max_h)
	# Cap label minimums so PanelContainer cannot expand past the compact card.
	var title_cap: float = 36.0
	var body_cap: float = maxf(40.0, panel_h - 56.0)
	_title.custom_minimum_size = Vector2(title_w, minf(_title.get_minimum_size().y, title_cap))
	_body.custom_minimum_size = Vector2(body_w, minf(_body.get_minimum_size().y, body_cap))
	_panel.clip_contents = true
	_panel.custom_minimum_size = Vector2(panel_w, panel_h)
	_panel.size = Vector2(panel_w, panel_h)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var x: float = (vp.x - panel_w) * 0.5
	var y: float = _action_panel_y(pref, hole, panel_w, panel_h, vp)
	_panel.position = Vector2(x, y)
	_panel.size = Vector2(panel_w, panel_h)
	_log(
		"Action card size=%s pos=%s hole_cy=%.0f" % [
			str(_panel.size),
			str(_panel.position),
			hole.get_center().y if hole.size.x > 0.0 else -1.0,
		]
	)


func _measure_action_panel_height(panel_w: float) -> float:
	## Title + instruction + padding only (no CONTINUE row).
	var pad_v: float = 28.0 # StyleBox content margins 14+14
	var sep: float = 8.0
	var title_w: float = maxf(80.0, panel_w - 70.0)
	var body_w: float = maxf(80.0, panel_w - 36.0)
	var title_h: float = _label_wrapped_height(_title, title_w)
	var body_h: float = _label_wrapped_height(_body, body_w)
	var header_h: float = maxf(32.0, title_h)
	return pad_v + header_h + sep + body_h


func _label_wrapped_height(label: Label, wrap_w: float) -> float:
	if label == null:
		return 18.0
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	if font == null:
		return float(font_size) + 4.0
	var sz: Vector2 = font.get_multiline_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap_w,
		font_size
	)
	return maxf(sz.y, float(font_size) + 2.0)


func _action_panel_y(pref: String, hole: Rect2, panel_w: float, panel_h: float, vp: Vector2) -> float:
	var top_y: float = TOP_SAFE + 12.0
	var bottom_y: float = vp.y - BOTTOM_HUD_RESERVE - panel_h - 12.0
	bottom_y = maxf(top_y, bottom_y)

	var place: String = pref
	if place == "auto":
		if hole.size.x <= 0.0:
			place = "top"
		else:
			var cy: float = hole.get_center().y
			if cy < vp.y * 0.40:
				place = "bottom"
			elif cy > vp.y * 0.60:
				place = "top"
			else:
				var room_above: float = hole.position.y - TOP_SAFE
				var room_below: float = (vp.y - BOTTOM_HUD_RESERVE) - hole.end.y
				place = "top" if room_above >= room_below else "bottom"

	var y: float = top_y
	match place:
		"bottom":
			y = bottom_y
		"center":
			y = clampf((vp.y - panel_h) * 0.28, top_y, bottom_y)
		_:
			y = top_y

	var x: float = (vp.x - panel_w) * 0.5
	var panel_rect := Rect2(Vector2(x, y), Vector2(panel_w, panel_h))
	if hole.size.x > 0.0 and panel_rect.intersects(hole.grow(12.0)):
		# Flip to the side with more clearance; never sit on the spotlight.
		var alt_top: float = top_y
		var alt_bottom: float = bottom_y
		var top_hits: bool = Rect2(Vector2(x, alt_top), Vector2(panel_w, panel_h)).intersects(hole.grow(12.0))
		var bot_hits: bool = Rect2(Vector2(x, alt_bottom), Vector2(panel_w, panel_h)).intersects(hole.grow(12.0))
		if place == "bottom" and not top_hits:
			y = alt_top
		elif place != "bottom" and not bot_hits:
			y = alt_bottom
		elif not top_hits:
			y = alt_top
		elif not bot_hits:
			y = alt_bottom
		else:
			# Both collide (tall hole) — park just above bottom HUD without covering more than needed.
			y = bottom_y

	return clampf(y, top_y, bottom_y)


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	if _built:
		return
	_built = true

	_full_dim = ColorRect.new()
	_full_dim.name = "FullDim"
	_full_dim.color = COLOR_DIM
	_full_dim.z_index = Z_DIM
	_full_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_dim.visible = false
	add_child(_full_dim)

	_blocker_top = _make_blocker("BlockerTop")
	_blocker_bottom = _make_blocker("BlockerBottom")
	_blocker_left = _make_blocker("BlockerLeft")
	_blocker_right = _make_blocker("BlockerRight")

	_highlight = Panel.new()
	_highlight.name = "HighlightHole"
	_highlight.z_index = Z_HIGHLIGHT
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	var hl_sb := StyleBoxFlat.new()
	hl_sb.bg_color = Color(0, 0, 0, 0)
	hl_sb.border_color = COLOR_GOLD
	hl_sb.set_border_width_all(3)
	hl_sb.corner_radius_top_left = 10
	hl_sb.corner_radius_top_right = 10
	hl_sb.corner_radius_bottom_left = 10
	hl_sb.corner_radius_bottom_right = 10
	hl_sb.shadow_color = Color(COLOR_SAPPHIRE.r, COLOR_SAPPHIRE.g, COLOR_SAPPHIRE.b, 0.45)
	hl_sb.shadow_size = 8
	_highlight.add_theme_stylebox_override("panel", hl_sb)
	add_child(_highlight)

	_pointer = _make_pointer()
	add_child(_pointer)

	_panel = PanelContainer.new()
	_panel.name = "InstructionPanel"
	_panel.z_index = Z_CHROME
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var psb := StyleBoxFlat.new()
	psb.bg_color = COLOR_PANEL
	psb.border_color = COLOR_GOLD
	psb.set_border_width_all(2)
	psb.corner_radius_top_left = 14
	psb.corner_radius_top_right = 14
	psb.corner_radius_bottom_left = 14
	psb.corner_radius_bottom_right = 14
	psb.content_margin_left = 18
	psb.content_margin_right = 18
	psb.content_margin_top = 14
	psb.content_margin_bottom = 14
	psb.shadow_color = Color(0, 0, 0, 0.35)
	psb.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", psb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_guide_badge = Label.new()
	_guide_badge.text = "♛"
	_guide_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_badge.add_theme_font_size_override("font_size", 24)
	_guide_badge.add_theme_color_override("font_color", COLOR_GOLD)
	_guide_badge.custom_minimum_size = Vector2(32, 32)
	_guide_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_guide_badge)

	_title = Label.new()
	_title.name = "StepTitle"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", COLOR_GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)

	_body = Label.new()
	_body.name = "InstructionText"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", COLOR_MARBLE)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(_body)

	_btn_row = HBoxContainer.new()
	_btn_row.name = "ButtonRow"
	_btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_btn_row)

	_continue_btn = _make_gold_button("CONTINUE")
	_continue_btn.name = "ContinueButton"
	_continue_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_btn.pressed.connect(_on_continue_pressed)
	_btn_row.add_child(_continue_btn)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipButton"
	_skip_btn.text = "SKIP"
	_skip_btn.z_index = Z_CHROME + 1
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_btn.custom_minimum_size = Vector2(96, 40)
	_skip_btn.add_theme_color_override("font_color", COLOR_MARBLE)
	_skip_btn.add_theme_color_override("font_hover_color", COLOR_GOLD)
	var skip_sb := StyleBoxFlat.new()
	skip_sb.bg_color = Color(0.12, 0.16, 0.24, 0.9)
	skip_sb.border_color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.55)
	skip_sb.set_border_width_all(1)
	skip_sb.corner_radius_top_left = 8
	skip_sb.corner_radius_top_right = 8
	skip_sb.corner_radius_bottom_left = 8
	skip_sb.corner_radius_bottom_right = 8
	_skip_btn.add_theme_stylebox_override("normal", skip_sb)
	_skip_btn.add_theme_stylebox_override("hover", skip_sb)
	_skip_btn.add_theme_stylebox_override("pressed", skip_sb)
	_skip_btn.pressed.connect(_on_skip_pressed)
	# Floating skip near top-right, above HUD chrome.
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -120.0
	_skip_btn.offset_top = 56.0
	_skip_btn.offset_right = -16.0
	_skip_btn.offset_bottom = 96.0
	add_child(_skip_btn)

	_build_skip_confirm()
	_raise_interactive_chrome()


func _make_blocker(blocker_name: String) -> ColorRect:
	var c := ColorRect.new()
	c.name = blocker_name
	c.color = COLOR_DIM
	c.z_index = Z_DIM
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	return c


func _make_pointer() -> Control:
	var wrap := Control.new()
	wrap.name = "Pointer"
	wrap.z_index = Z_HIGHLIGHT
	wrap.custom_minimum_size = Vector2(36, 48)
	wrap.size = Vector2(36, 48)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.visible = false
	var diamond := ColorRect.new()
	diamond.color = COLOR_GOLD
	diamond.position = Vector2(10, 0)
	diamond.size = Vector2(16, 16)
	diamond.rotation = deg_to_rad(45)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(diamond)
	var stem := ColorRect.new()
	stem.color = COLOR_SAPPHIRE
	stem.position = Vector2(14, 18)
	stem.size = Vector2(8, 22)
	stem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(stem)
	return wrap


func _make_gold_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(180, 44)
	btn.add_theme_color_override("font_color", Color(0.12, 0.1, 0.05, 1))
	btn.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_GOLD
	sb.border_color = Color(1, 0.92, 0.65, 1)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.95, 0.82, 0.48, 1)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	return btn


func _build_skip_confirm() -> void:
	_skip_layer = Control.new()
	_skip_layer.name = "SkipConfirm"
	_skip_layer.z_index = Z_SKIP_CONFIRM
	_skip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skip_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_layer.visible = false
	add_child(_skip_layer)

	var dim := ColorRect.new()
	dim.name = "SkipDim"
	dim.color = Color(0, 0, 0, 0.65)
	dim.z_index = 0
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Dim blocks outside clicks; dialog box is a later sibling so buttons stay clickable.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_layer.add_child(dim)

	var box := PanelContainer.new()
	box.name = "SkipDialog"
	box.z_index = 1
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_top = -120
	box.offset_right = 220
	box.offset_bottom = 120
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL
	sb.border_color = COLOR_GOLD
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", sb)
	_skip_layer.add_child(box)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	_skip_title = Label.new()
	_skip_title.text = "SKIP TUTORIAL?"
	_skip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_title.add_theme_font_size_override("font_size", 22)
	_skip_title.add_theme_color_override("font_color", COLOR_GOLD)
	v.add_child(_skip_title)

	var msg := Label.new()
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg.text = "You can continue playing normally, but guided tutorial steps will be disabled."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", COLOR_MARBLE)
	msg.add_theme_font_size_override("font_size", 15)
	v.add_child(msg)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)

	_skip_cancel = Button.new()
	_skip_cancel.text = "CANCEL"
	_skip_cancel.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_cancel.custom_minimum_size = Vector2(120, 44)
	_skip_cancel.pressed.connect(_on_skip_cancel)
	row.add_child(_skip_cancel)

	_skip_confirm = _make_gold_button("SKIP")
	_skip_confirm.custom_minimum_size = Vector2(120, 44)
	_skip_confirm.pressed.connect(_on_skip_confirm)
	row.add_child(_skip_confirm)


func _log(msg: String) -> void:
	print("%s %s" % [LOG_PREFIX, msg])
