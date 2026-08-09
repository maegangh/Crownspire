extends Node

## City building actions. Tap activation is owned by City camera physics-query dispatch
## (activate_building_tap / activate_collect_tap). Area2D signals only help begin the gesture
## when picking is not blocked by Controls.

const CityGestureUtil = preload("res://Scripts/City/CityGesture.gd")
const BuildingNameplateUtil = preload("res://Scripts/City/BuildingNameplate.gd")
const BuildingActionPopupScript = preload("res://Scripts/UI/BuildingActionPopup.gd")

@export var building_level: int = 1
@export var building_name: String = "Farm"
@export var ready_to_collect: bool = true
@export var collect_amount: int = 100
@export var opens_troop_training: bool = false
@export var troop_type: String = ""
@export var building_id: String = ""

var upgrading := false
var upgrade_finish_time := 0

func _ready():
	load_building_level()
	check_upgrade_finished()
	update_level_label()
	set_ready_to_collect(ready_to_collect)
	_ignore_decor_controls()

	if has_node("ClickArea"):
		$ClickArea.input_pickable = true
		if not $ClickArea.input_event.is_connected(_on_click_area_input_event):
			$ClickArea.input_event.connect(_on_click_area_input_event)

	if has_node("UpgradeArea"):
		$UpgradeArea.input_pickable = true
		if not $UpgradeArea.input_event.is_connected(_on_upgrade_area_input_event):
			$UpgradeArea.input_event.connect(_on_upgrade_area_input_event)

	call_deferred("_attach_building_nameplate")


func _attach_building_nameplate() -> void:
	BuildingNameplateUtil.attach_to(self)


func _ignore_decor_controls() -> void:
	# ColorRect/Label badges default to STOP and can swallow Area2D picking.
	_ignore_controls_recursive(self)


func _ignore_controls_recursive(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and not (child is BaseButton):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Do not recurse into Area2D trees (no Controls expected); keep badges only.
		if child is Control or (child is Node2D and not (child is Area2D)):
			_ignore_controls_recursive(child)


func _process(_delta):
	check_upgrade_finished()

func set_ready_to_collect(is_ready: bool):
	ready_to_collect = is_ready
	if has_node("CollectIcon"):
		$CollectIcon.visible = is_ready


## Called by City camera on a classified TAP (physics query hit ClickArea).
func activate_collect_tap() -> void:
	if GameState.popup_open or _is_main_screen_open():
		return
	_on_collect_tap()


## Called by City camera on a classified TAP (physics query hit UpgradeArea).
func activate_building_tap() -> void:
	if GameState.popup_open or _is_main_screen_open():
		return
	if has_node("/root/GameEvents") and not building_id.strip_edges().is_empty():
		GameEvents.emit_building_selected(building_id)
	_on_upgrade_tap()


func _on_click_area_input_event(_viewport, event, _shape_idx):
	# Backup path if Area2D picking works (camera _input usually owns activation).
	if GameState.popup_open or _is_main_screen_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			CityGestureUtil.begin_press(CityGestureUtil.viewport_pointer_pos(get_viewport()))
		elif CityGestureUtil.consume_release_as_tap():
			activate_collect_tap()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			CityGestureUtil.begin_press((event as InputEventScreenTouch).position)
		elif CityGestureUtil.consume_release_as_tap():
			activate_collect_tap()


func _on_upgrade_area_input_event(_viewport, event, _shape_idx):
	if GameState.popup_open or _is_main_screen_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			CityGestureUtil.begin_press(CityGestureUtil.viewport_pointer_pos(get_viewport()))
		elif CityGestureUtil.consume_release_as_tap():
			activate_building_tap()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			CityGestureUtil.begin_press((event as InputEventScreenTouch).position)
		elif CityGestureUtil.consume_release_as_tap():
			activate_building_tap()


func _on_collect_tap() -> void:
	if not ready_to_collect:
		return
	var collected_type: String = ""
	if building_name == "Farm":
		GameState.add_food(collect_amount)
		collected_type = "food"
	elif building_name == "LumberMill":
		GameState.add_wood(collect_amount)
		collected_type = "wood"
	elif building_name == "Quarry":
		GameState.add_stone(collect_amount)
		collected_type = "stone"
	elif building_name == "IronMine":
		GameState.add_iron(collect_amount)
		collected_type = "iron"
	else:
		return

	set_ready_to_collect(false)
	if has_node("/root/GameEvents") and not collected_type.is_empty():
		GameEvents.emit_resource_collected(collected_type, collect_amount)
	get_tree().create_timer(5.0).timeout.connect(func():
		set_ready_to_collect(true)
	)


func _on_upgrade_tap() -> void:
	if opens_troop_training:
		_open_troop_building_actions()
		return
	if building_id == "tavern" or building_name == "Tavern":
		_open_tavern_actions()
		return
	if building_id == "academy" or building_name == "Academy":
		_open_research_hall_actions()
		return
	if _is_hospital_building():
		_open_hospital_actions()
		return
	if _is_sanctuary_building():
		_open_sanctuary_screen()
		return
	if _is_wall_building():
		_open_wall_actions()
		return
	open_upgrade_window()


func _is_wall_building() -> bool:
	var id_key: String = building_id.strip_edges().to_lower()
	if id_key == "wall":
		return true
	return building_name.strip_edges().to_lower() == "wall"


func _is_hospital_building() -> bool:
	var id_key: String = building_id.strip_edges().to_lower()
	if id_key in ["hospital", "medical_tent", "infirmary"]:
		return true
	var nm: String = building_name.strip_edges().to_lower()
	return nm == "hospital" or nm == "sacred hospital"


func _is_sanctuary_building() -> bool:
	var id_key: String = building_id.strip_edges().to_lower()
	if id_key in ["sanctuary", "grave_sanctuary"]:
		return true
	var nm: String = building_name.strip_edges().to_lower()
	return nm == "sanctuary" or nm == "grave sanctuary"


## Troop building tap → Train / Upgrade chooser (shared BuildingActionPopup).
func _open_troop_building_actions() -> void:
	var hud: Node = _get_game_hud()
	var parent_n: Node = hud if hud != null else get_tree().current_scene
	if parent_n == null:
		parent_n = get_tree().root

	BuildingActionPopupScript.present(
		parent_n,
		_resolve_building_action_title(),
		[
			{"id": "train", "label": "Train"},
			{"id": "upgrade", "label": "Upgrade"},
		],
		func(action_id: String) -> void:
			match action_id:
				"train":
					_open_troop_training()
				"upgrade":
					open_upgrade_window()
	)


func _resolve_building_action_title() -> String:
	var id_key: String = building_id.strip_edges().to_lower()
	var titles := {
		"infantry_barracks": "INFANTRY BARRACKS",
		"marksmen_camp": "MARKSMEN CAMP",
		"cavalry_stable": "CAVALRY STABLE",
		"academy": "RESEARCH HALL",
		"hospital": "HOSPITAL",
		"medical_tent": "HOSPITAL",
		"infirmary": "HOSPITAL",
		"wall": "WALL",
		"tavern": "TAVERN",
	}
	if titles.has(id_key):
		return str(titles[id_key])
	# Prefer buildings.json display name when present.
	if FileAccess.file_exists("res://data/buildings.json"):
		var file := FileAccess.open("res://data/buildings.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has(id_key):
				var entry: Variant = (parsed as Dictionary)[id_key]
				if typeof(entry) == TYPE_DICTIONARY:
					var nm: String = str((entry as Dictionary).get("name", "")).strip_edges()
					if nm != "":
						return nm.to_upper()
	if building_name.strip_edges() != "":
		return building_name.strip_edges().to_upper()
	return id_key.replace("_", " ").to_upper()


func _open_troop_training() -> void:
	var hud: Node = get_tree().current_scene.get_node_or_null("GameHUD")
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		push_error("ResourceManager: GameHUD not found for troop training.")
		return
	var screen: Node = hud.get_node_or_null("ScreenRoot/TroopTrainingScreen")
	if screen == null:
		push_error("ResourceManager: TroopTrainingScreen missing under GameHUD/ScreenRoot.")
		return
	if screen.has_method("open_for_building"):
		screen.call("open_for_building", troop_type, building_id, building_level)
	else:
		push_error("ResourceManager: TroopTrainingScreen missing open_for_building().")


func _is_main_screen_open() -> bool:
	var hud: Node = get_tree().current_scene.get_node_or_null("GameHUD")
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return false
	var mgr: Node = hud.get_node_or_null("UIManager")
	if mgr == null or not mgr.has_method("is_screen_open") or not bool(mgr.is_screen_open()):
		return false
	# Stale ownership after visual-only closes must not block building taps.
	var screen_name: String = ""
	if mgr.has_method("get_current_screen_name"):
		screen_name = str(mgr.call("get_current_screen_name"))
	if not screen_name.is_empty():
		var screen: CanvasItem = hud.get_node_or_null("ScreenRoot/" + screen_name) as CanvasItem
		if screen != null and not screen.visible:
			if mgr.has_method("close_current_screen"):
				mgr.call("close_current_screen")
			return false
	return true


## Tavern tap → Recruit / Upgrade chooser (Recruit preserves legacy TavernWindow path).
func _open_tavern_actions() -> void:
	var hud: Node = _get_game_hud()
	var parent_n: Node = hud if hud != null else get_tree().current_scene
	if parent_n == null:
		parent_n = get_tree().root

	BuildingActionPopupScript.present(
		parent_n,
		_resolve_building_action_title(),
		[
			{"id": "recruit", "label": "Recruit"},
			{"id": "upgrade", "label": "Upgrade"},
		],
		func(action_id: String) -> void:
			match action_id:
				"recruit":
					_open_tavern_recruit()
				"upgrade":
					open_upgrade_window()
	)


func _open_tavern_recruit() -> void:
	var tavern: Node = get_tree().current_scene.get_node_or_null("TavernWindow")
	if tavern == null:
		tavern = get_tree().root.find_child("TavernWindow", true, false)
	if tavern == null:
		var packed: PackedScene = load("res://Scenes/UI/TavernWindow.tscn") as PackedScene
		if packed == null:
			push_error("ResourceManager: TavernWindow.tscn missing.")
			return
		tavern = packed.instantiate()
		tavern.name = "TavernWindow"
		get_tree().current_scene.add_child(tavern)

	if tavern.has_method("open_tavern"):
		tavern.call("open_tavern")
	else:
		push_error("ResourceManager: TavernWindow missing open_tavern().")


## Hospital tap → Heal Troops / Upgrade chooser.
func _open_hospital_actions() -> void:
	var hud: Node = _get_game_hud()
	var parent_n: Node = hud if hud != null else get_tree().current_scene
	if parent_n == null:
		parent_n = get_tree().root

	BuildingActionPopupScript.present(
		parent_n,
		_resolve_building_action_title(),
		[
			{"id": "heal", "label": "Heal Troops"},
			{"id": "upgrade", "label": "Upgrade"},
		],
		func(action_id: String) -> void:
			match action_id:
				"heal":
					_open_hospital_screen()
				"upgrade":
					open_upgrade_window()
	)


func _open_hospital_screen() -> void:
	var hud: Node = _get_game_hud()
	if hud == null:
		push_error("ResourceManager: GameHUD not found for Hospital.")
		return
	var screen: Node = hud.get_node_or_null("ScreenRoot/HospitalScreen")
	if screen == null:
		push_error("ResourceManager: HospitalScreen missing under GameHUD/ScreenRoot.")
		return
	var manager: Node = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.call("open_screen", "HospitalScreen")
	elif screen.has_method("on_open"):
		screen.call("on_open")


## Wall tap → Defense / Upgrade chooser.
func _open_wall_actions() -> void:
	var hud: Node = _get_game_hud()
	var parent_n: Node = hud if hud != null else get_tree().current_scene
	if parent_n == null:
		parent_n = get_tree().root

	BuildingActionPopupScript.present(
		parent_n,
		_resolve_building_action_title(),
		[
			{"id": "defense", "label": "Defense"},
			{"id": "upgrade", "label": "Upgrade"},
		],
		func(action_id: String) -> void:
			match action_id:
				"defense":
					# Deferred so BuildingActionPopup can finish freeing mid-signal.
					call_deferred("_open_wall_defense_screen")
				"upgrade":
					# Deferred: open after chooser signal completes; uses canonical BuildingUpgradeWindow.
					call_deferred("open_upgrade_window")
	)


func _open_wall_defense_screen() -> void:
	var hud: Node = _get_game_hud()
	if hud == null:
		push_error("ResourceManager: GameHUD not found for Wall Defense.")
		return
	var screen: Node = hud.get_node_or_null("ScreenRoot/WallDefenseScreen")
	if screen == null:
		push_error("ResourceManager: WallDefenseScreen missing under GameHUD/ScreenRoot.")
		return
	var manager: Node = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.call("open_screen", "WallDefenseScreen")
	elif screen.has_method("on_open"):
		screen.call("on_open")


## Sanctuary is not upgradeable in Phase 5 — open recovery screen only.
func _open_sanctuary_screen() -> void:
	var hud: Node = _get_game_hud()
	if hud == null:
		push_error("ResourceManager: GameHUD not found for Sanctuary.")
		return
	var screen: Node = hud.get_node_or_null("ScreenRoot/SanctuaryScreen")
	if screen == null:
		push_error("ResourceManager: SanctuaryScreen missing under GameHUD/ScreenRoot.")
		return
	var manager: Node = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.call("open_screen", "SanctuaryScreen")
	elif screen.has_method("on_open"):
		screen.call("on_open")


## Research Hall tap → small action chooser (Research / Upgrade), not direct research.
func _open_research_hall_actions() -> void:
	var hud: Node = _get_game_hud()
	var parent_n: Node = hud if hud != null else get_tree().current_scene
	if parent_n == null:
		parent_n = get_tree().root

	BuildingActionPopupScript.present(
		parent_n,
		_resolve_building_action_title(),
		[
			{"id": "research", "label": "Research"},
			{"id": "upgrade", "label": "Upgrade"},
		],
		func(action_id: String) -> void:
			match action_id:
				"research":
					_open_research_hall()
				"upgrade":
					open_upgrade_window()
	)


func _get_game_hud() -> Node:
	var scene: Node = get_tree().current_scene
	var hud: Node = scene.get_node_or_null("GameHUD") if scene else null
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	return hud


## Opens AcademyResearchWindow under GameHUD (CanvasLayer), never under City Node2D.
func _open_research_hall() -> void:
	var scene: Node = get_tree().current_scene
	var hud: Node = _get_game_hud()

	var research: Node = null
	if hud != null:
		research = hud.get_node_or_null("AcademyResearchWindow")
	if research == null and scene != null:
		research = scene.get_node_or_null("AcademyResearchWindow")
	if research == null:
		research = get_tree().root.find_child("AcademyResearchWindow", true, false)

	if research == null:
		var packed: PackedScene = load("res://Scenes/AcademyResearchWindow.tscn") as PackedScene
		if packed == null:
			push_error("ResourceManager: AcademyResearchWindow.tscn missing.")
			return
		research = packed.instantiate()
		research.name = "AcademyResearchWindow"
		if research is Control:
			(research as Control).visible = false
			(research as Control).z_index = 200
		var parent_n: Node = hud if hud != null else scene
		if parent_n == null:
			parent_n = get_tree().root
		parent_n.add_child(research)

	if research.has_method("open_research"):
		research.call("open_research")
	elif research is Control:
		(research as Control).visible = true
		if has_node("/root/GameState"):
			GameState.popup_open = true
	else:
		push_error("ResourceManager: AcademyResearchWindow missing open_research().")

## Phase 0B3-B: obsolete legacy upgrade path. Does not start jobs, timers, or spends.
## Active City upgrades go through BuildingUpgradeWindow → ConstructionState only.
func start_upgrade_timer():
	push_warning(
		"ResourceManager.start_upgrade_timer: obsolete legacy path disabled (0B3-B); "
		+ "refusing job/timer for building_id=%s. Use BuildingUpgradeWindow."
		% building_id
	)
	return

func check_upgrade_finished():
	if not upgrading:
		return
	# Phase 0B3-A: ConstructionState is the sole completion authority.
	# Never independently increment building_level, write completed levels, or emit rewards.
	if not has_node("/root/ConstructionState"):
		# Fail safely: keep upgrading/upgrade_finish_time so UI does not falsely show
		# completion. Do not invent a timer/queue, raise a level, or consult display sections.
		push_warning(
			"ResourceManager.check_upgrade_finished: ConstructionState unavailable; "
			+ "refusing independent completion for building_id=%s (status left unchanged)."
			% building_id
		)
		return
	if ConstructionState.is_building_upgrading(building_id):
		return
	# Job finished (or absent) under ConstructionState — refresh scene display from
	# canonical completed level only. Do not write completed level.
	load_building_level()
	if not ConstructionState.is_building_upgrading(building_id):
		upgrading = false
		upgrade_finish_time = 0
		save_building_level() # flags-only under canonical building_id
	update_level_label()

func get_upgrade_time_left() -> int:
	if not upgrading:
		return 0

	var now: int = int(Time.get_unix_time_from_system())
	return max(0, upgrade_finish_time - now)
	
func update_level_label():
	if has_node("LevelLabel"):
		$LevelLabel.text = str(building_level)

## Phase 0B3-A: construction-status persistence only.
## Does NOT save a completed building level. Completed levels are written solely by
## ConstructionState._write_building_level / _complete_job_at.
## Persists only `upgrading` and `upgrade_finish_time` under the canonical building_id section.
## Never writes display-name sections or any `level` key.
func save_building_level():
	var id_key: String = building_id.strip_edges()
	if id_key.is_empty():
		push_warning("ResourceManager.save_building_level: empty building_id; skipping status persist.")
		return
	if has_node("/root/ConstructionState") and ConstructionState.has_method("normalize_building_id"):
		id_key = ConstructionState.normalize_building_id(id_key)
	var save = ConfigFile.new()
	save.load("user://buildings.cfg")
	save.set_value(id_key, "upgrading", upgrading)
	save.set_value(id_key, "upgrade_finish_time", upgrade_finish_time)
	save.save("user://buildings.cfg")

func load_building_level():
	# Phase 0B2-A: completed level from ConstructionState canonical authority only.
	# Never treat display-name cfg sections or GameState mirrors as level authority.
	var id_key: String = building_id.strip_edges()
	if not id_key.is_empty() and has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		building_level = maxi(1, int(ConstructionState.get_canonical_building_level(id_key)))
	else:
		building_level = 1
	# Upgrade-job flags only (not completed level). Prefer canonical id section when present.
	var save = ConfigFile.new()
	if save.load("user://buildings.cfg") == OK:
		var flag_section: String = building_name
		if not id_key.is_empty() and save.has_section(id_key):
			flag_section = id_key
		upgrading = bool(save.get_value(flag_section, "upgrading", false))
		upgrade_finish_time = int(save.get_value(flag_section, "upgrade_finish_time", 0))

func open_upgrade_window() -> void:
	if building_id.is_empty():
		push_error("ResourceManager: building_id is empty on " + name)
		return

	var window := get_tree().current_scene.find_child(
		"BuildingUpgradeWindow",
		true,
		false
	)

	if window == null:
		push_error("ResourceManager: BuildingUpgradeWindow not found.")
		return

	if not window.has_method("open_for_building"):
		push_error("ResourceManager: Upgrade window is missing open_for_building().")
		return

	window.open_for_building(building_id)
	# Surface missing buildings.json entries (e.g. wall) instead of a silent no-op.
	if window is CanvasItem and not (window as CanvasItem).visible:
		push_error(
			"ResourceManager: BuildingUpgradeWindow did not open for '%s' (missing buildings.json entry?)."
			% building_id
		)
		var hud: Node = _get_game_hud()
		if hud != null:
			var ui: Node = hud.get_node_or_null("UIManager")
			if ui != null and ui.has_method("show_toast"):
				ui.call("show_toast", "Upgrade data missing for %s" % building_id)
