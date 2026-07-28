extends CanvasLayer

const WorldSearchPanelScene: PackedScene = preload("res://Scenes/UI/WorldSearchPanel.tscn")

@export var is_world_screen: bool = false
@export var bottom_bar_home: Texture2D
@export var bottom_bar_world: Texture2D

@onready var bottom_bar_texture: TextureRect = $Control/BottomBarTexture

@onready var food_label: Label = $Control/TopBarTexture/TopLabels/FoodLabel
@onready var wood_label: Label = $Control/TopBarTexture/TopLabels/WoodLabel
@onready var stone_label: Label = $Control/TopBarTexture/TopLabels/StoneLabel
@onready var iron_label: Label = $Control/TopBarTexture/TopLabels/IronLabel
@onready var diamond_label: Label = $Control/TopBarTexture/TopLabels/DiamondLabel
@onready var power_label: Label = $Control/TopBarTexture/TopLabels/PowerLabel
@onready var vip_label: Label = $Control/TopBarTexture/TopLabels/VipLabel

@onready var portrait_button: TextureButton = $Control/PlayerPortraitButton
@onready var right_feature_buttons: VBoxContainer = $Control/RightFeatureButtons
var _profile_screen: Control = null
const PlayerAvatarCatalog = preload("res://scripts/UI/PlayerAvatarCatalog.gd")
@onready var shop_button: TextureButton = $Control/RightFeatureButtons/ShopButton
@onready var events_button: Button = $Control/RightFeatureButtons/EventsButton
@onready var events_claim_badge: Label = $Control/RightFeatureButtons/EventsButton/ClaimBadge
var _chat_preview: Control = null
var _help_button: Button = null
var _help_count_label: Label = null
@onready var mail_button: TextureButton = $Control/MailButton
@onready var mail_unread_badge: Label = $Control/MailButton/UnreadBadge

var _event_toast_label: Label = null
var _event_toast_timer: float = 0.0

@onready var heroes_button: Button = $Control/BottomBarTexture/BottomButtons/HeroesButton
@onready var wayfinder_button: Button = $Control/BottomBarTexture/BottomButtons/WayfinderButton
@onready var bag_button: Button = $Control/BottomBarTexture/BottomButtons/BagButton
@onready var quest_button: Button = $Control/BottomBarTexture/BottomButtons/QuestButton
@onready var alliance_button: Button = $Control/BottomBarTexture/BottomButtons/AllianceButton
@onready var world_city_button: Button = $Control/BottomBarTexture/BottomButtons/WorldCityButton

var _queue_status_hud: Control = null
var _world_search_button: Button = null
var _world_search_panel: Control = null
var _active_marches_hud: Control = null

func _ready():
	add_to_group("game_hud")
	_apply_screen_context()
	_configure_bottom_nav()
	_setup_queue_status_hud()
	# Search before ActiveMarches so a marches HUD fault cannot skip the SEARCH button.
	_setup_world_search_ui()
	_setup_active_marches_hud()
	_apply_screen_context()
	update_resources()
	connect_buttons()
	_style_events_button()
	_remove_legacy_chat_button()
	_ensure_chat_screen()
	_ensure_chat_preview()
	_ensure_help_button()
	_ensure_profile_screen()
	_bind_profile_avatar()
	_refresh_portrait_avatar()
	_refresh_mail_badge()
	_refresh_events_badge()
	if has_node("/root/GameState") and not GameState.resources_changed.is_connected(_on_resources_changed):
		GameState.resources_changed.connect(_on_resources_changed)
	call_deferred("_validate_bottom_nav_hitboxes")
	call_deferred("_validate_mail_hitbox")
	call_deferred("_run_hud_navigation_smoke_test_if_headless")
	if has_node("/root/MarchState"):
		if not MarchState.march_battle_resolved.is_connected(_on_wildling_march_battle):
			MarchState.march_battle_resolved.connect(_on_wildling_march_battle)
		if is_world_screen and MarchState.has_method("resync_map_visuals"):
			call_deferred("_resync_marches")
	if has_node("/root/MailManager") and not MailManager.mail_changed.is_connected(_on_mail_changed):
		MailManager.mail_changed.connect(_on_mail_changed)
	if has_node("/root/EventState"):
		if not EventState.event_changed.is_connected(_on_event_state_changed):
			EventState.event_changed.connect(_on_event_state_changed)
		if not EventState.points_awarded.is_connected(_on_event_points_awarded):
			EventState.points_awarded.connect(_on_event_points_awarded)
	# Canonical nav events after this screen successfully loaded.
	if has_node("/root/GameEvents"):
		if is_world_screen:
			GameEvents.emit_world_opened()
		else:
			GameEvents.emit_city_opened()
	# Ensure tutorial overlay exists even if scene instance omitted it.
	call_deferred("_ensure_tutorial_overlay")
	call_deferred("_refresh_portrait_avatar")


func _ensure_tutorial_overlay() -> void:
	if get_node_or_null("TutorialOverlay") != null:
		return
	var packed: PackedScene = load("res://Scenes/UI/TutorialOverlay.tscn") as PackedScene
	if packed == null:
		push_warning("[GameHUD] TutorialOverlay.tscn missing")
		return
	var overlay: Control = packed.instantiate() as Control
	overlay.name = "TutorialOverlay"
	add_child(overlay)
	move_child(overlay, get_child_count() - 1)


func _setup_queue_status_hud() -> void:
	# City-only persistent queue strip. World map keeps the same GameHUD scene but hides this.
	_queue_status_hud = get_node_or_null("Control/QueueStatusHUD") as Control
	if _queue_status_hud == null:
		var packed: PackedScene = load("res://Scenes/UI/QueueStatusHUD.tscn") as PackedScene
		if packed == null:
			push_warning("[GameHUD] QueueStatusHUD.tscn missing.")
			return
		_queue_status_hud = packed.instantiate() as Control
		_queue_status_hud.name = "QueueStatusHUD"
		var host: Node = get_node_or_null("Control")
		if host == null:
			host = self
		host.add_child(_queue_status_hud)
	_sync_queue_status_visibility()


## Brief highlight when a queue-full attempt fails (beta UX).
func pulse_queue_status(kind: String) -> void:
	if _queue_status_hud != null and _queue_status_hud.has_method("pulse_queue"):
		_queue_status_hud.call("pulse_queue", kind)


func _sync_queue_status_visibility() -> void:
	if _queue_status_hud == null or not is_instance_valid(_queue_status_hud):
		return
	var show_queue: bool = not is_world_screen
	var manager: Node = get_node_or_null("UIManager")
	if show_queue and manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		# Hide under full ScreenRoot screens (Bag/Alliance/etc). Keep visible during city popups.
		show_queue = false
	_queue_status_hud.visible = show_queue
	_queue_status_hud.mouse_filter = (
		Control.MOUSE_FILTER_STOP if show_queue else Control.MOUSE_FILTER_IGNORE
	)


func _setup_active_marches_hud() -> void:
	# World-only march status. Separate from City QueueStatusHUD.
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	_active_marches_hud = host.get_node_or_null("ActiveMarchesHUD") as Control
	if _active_marches_hud == null:
		var packed: PackedScene = load("res://Scenes/UI/ActiveMarchesHUD.tscn") as PackedScene
		if packed == null:
			push_warning("[GameHUD] ActiveMarchesHUD.tscn missing.")
			return
		_active_marches_hud = packed.instantiate() as Control
		_active_marches_hud.name = "ActiveMarchesHUD"
		host.add_child(_active_marches_hud)
	_sync_active_marches_visibility()


func _sync_active_marches_visibility() -> void:
	if _active_marches_hud == null or not is_instance_valid(_active_marches_hud):
		return
	var show_marches: bool = is_world_screen
	var manager: Node = get_node_or_null("UIManager")
	if show_marches and manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_marches = false
	_active_marches_hud.visible = show_marches
	# Never intercept City taps; ignore on World empty space too.
	_active_marches_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Single screen-context apply for City vs World HUD chrome.
func _apply_screen_context() -> void:
	setup_bottom_bar()
	_sync_queue_status_visibility()
	_sync_active_marches_visibility()
	_sync_world_search_visibility()
	_sync_right_feature_visibility()
	_sync_chat_preview_visibility()


func _on_resources_changed() -> void:
	update_resources()


func _sync_right_feature_visibility() -> void:
	# Shop + Events stay on the right stack; hide only under main ScreenRoot screens.
	var show_right: bool = true
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_right = false
	if right_feature_buttons != null and is_instance_valid(right_feature_buttons):
		right_feature_buttons.visible = show_right
	if shop_button != null and is_instance_valid(shop_button):
		shop_button.mouse_filter = Control.MOUSE_FILTER_STOP if show_right else Control.MOUSE_FILTER_IGNORE
	if events_button != null and is_instance_valid(events_button):
		events_button.mouse_filter = Control.MOUSE_FILTER_STOP if show_right else Control.MOUSE_FILTER_IGNORE
		if events_claim_badge != null and is_instance_valid(events_claim_badge):
			events_claim_badge.visible = show_right and events_claim_badge.text != ""
			events_claim_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _sync_chat_preview_visibility() -> void:
	if _chat_preview == null or not is_instance_valid(_chat_preview):
		return
	var hide_preview: bool = false
	var chat_open: bool = false
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		hide_preview = true
		if manager.has_method("get_current_screen_name") and str(manager.get_current_screen_name()) == "ChatScreen":
			chat_open = true
	elif has_node("/root/GameState") and bool(GameState.popup_open):
		hide_preview = true
	elif has_node("/root/TutorialState") and TutorialState.has_method("is_blocking_hud") and bool(TutorialState.is_blocking_hud()):
		hide_preview = true
	if _chat_preview.has_method("set_chat_session_open"):
		_chat_preview.call("set_chat_session_open", chat_open)
	if _chat_preview.has_method("set_force_hidden"):
		_chat_preview.call("set_force_hidden", hide_preview and not chat_open)
	else:
		_chat_preview.visible = not hide_preview
		_chat_preview.mouse_filter = Control.MOUSE_FILTER_STOP if not hide_preview else Control.MOUSE_FILTER_IGNORE


func _ensure_help_button() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	_help_button = host.get_node_or_null("AllianceHelpButton") as Button
	if _help_button == null:
		_help_button = Button.new()
		_help_button.name = "AllianceHelpButton"
		_help_button.focus_mode = Control.FOCUS_NONE
		_help_button.custom_minimum_size = Vector2(96, 52)
		_help_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_help_button.anchor_left = 0.5
		_help_button.anchor_right = 0.5
		_help_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_help_button.offset_left = -48.0
		_help_button.offset_right = 48.0
		_help_button.offset_top = -300.0
		_help_button.offset_bottom = -248.0
		_help_button.z_index = 41
		host.add_child(_help_button)
		_help_count_label = Label.new()
		_help_count_label.name = "HelpCount"
		_help_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_help_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_help_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_help_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_help_count_label.add_theme_font_size_override("font_size", 16)
		_help_count_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
		_help_button.add_child(_help_count_label)
	else:
		_help_count_label = _help_button.get_node_or_null("HelpCount") as Label
	_style_help_button()
	if not _help_button.pressed.is_connected(_on_help_all_hud_pressed):
		_help_button.pressed.connect(_on_help_all_hud_pressed)
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		if ab.has_signal("help_eligible_count_changed") and not ab.help_eligible_count_changed.is_connected(_on_help_count_changed):
			ab.help_eligible_count_changed.connect(_on_help_count_changed)
		if ab.has_signal("help_requests_changed") and not ab.help_requests_changed.is_connected(_on_help_requests_changed_hud):
			ab.help_requests_changed.connect(_on_help_requests_changed_hud)
	_sync_help_button_visibility()


func _style_help_button() -> void:
	if _help_button == null:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.10, 0.09, 0.12, 0.92)
	fill.border_color = Color(0.78, 0.66, 0.34, 1.0)
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(14)
	_help_button.add_theme_stylebox_override("normal", fill)
	_help_button.add_theme_stylebox_override("pressed", fill)
	_help_button.add_theme_stylebox_override("hover", fill)


func _on_help_count_changed(count: int) -> void:
	if _help_count_label != null:
		_help_count_label.text = "👍 %d" % count
	_sync_help_button_visibility()


func _on_help_requests_changed_hud(_eligible: Array, _mine: Array) -> void:
	var count: int = 0
	if has_node("/root/AllianceBackend"):
		count = int(get_node("/root/AllianceBackend").get_eligible_help_count())
	_on_help_count_changed(count)


func _sync_help_button_visibility() -> void:
	if _help_button == null or not is_instance_valid(_help_button):
		return
	var count: int = 0
	var show_help: bool = false
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		count = int(ab.get_eligible_help_count()) if ab.has_method("get_eligible_help_count") else 0
		show_help = ab.has_method("is_help_authority") and bool(ab.is_help_authority()) and count > 0
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_help = false
	elif has_node("/root/GameState") and bool(GameState.popup_open):
		show_help = false
	if _help_count_label != null:
		_help_count_label.text = "👍 %d" % count
	_help_button.visible = show_help
	_help_button.mouse_filter = Control.MOUSE_FILTER_STOP if show_help else Control.MOUSE_FILTER_IGNORE


func _on_help_all_hud_pressed() -> void:
	if not has_node("/root/AllianceBackend"):
		return
	var ab: Node = get_node("/root/AllianceBackend")
	if not ab.has_method("help_all"):
		return
	var result: Dictionary = await ab.help_all(false)
	_sync_help_button_visibility()
	if bool(result.get("ok", false)):
		print("[GameHUD] Help All applied count=%s" % str(result.get("helped_count", 0)))
	else:
		print("[GameHUD] Help All failed: %s" % str(result.get("error", "")))


func _setup_world_search_ui() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return

	_world_search_button = host.get_node_or_null("WorldSearchButton") as Button
	if _world_search_button == null:
		_world_search_button = Button.new()
		_world_search_button.name = "WorldSearchButton"
		_world_search_button.text = "🔍\nSEARCH"
		_world_search_button.focus_mode = Control.FOCUS_NONE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.12, 0.11, 0.16, 0.92)
		fill.border_color = Color(0.78, 0.66, 0.34, 0.95)
		fill.set_border_width_all(2)
		fill.set_corner_radius_all(14)
		_world_search_button.add_theme_stylebox_override("normal", fill)
		_world_search_button.add_theme_font_size_override("font_size", 16)
		_world_search_button.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
		host.add_child(_world_search_button)
	# Bottom-left above nav — clear of Mail (right) and ActiveMarchesHUD (top-left).
	_world_search_button.custom_minimum_size = Vector2(96, 96)
	_world_search_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_world_search_button.anchor_left = 0.0
	_world_search_button.anchor_top = 1.0
	_world_search_button.anchor_right = 0.0
	_world_search_button.anchor_bottom = 1.0
	# Bottom nav top ≈ offset -179; keep ~16px clearance above it.
	_world_search_button.offset_left = 14.0
	_world_search_button.offset_top = -291.0
	_world_search_button.offset_right = 110.0
	_world_search_button.offset_bottom = -195.0
	_world_search_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_world_search_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if not _world_search_button.pressed.is_connected(_on_world_search_pressed):
		_world_search_button.pressed.connect(_on_world_search_pressed)

	_world_search_panel = host.get_node_or_null("WorldSearchPanel") as Control
	if _world_search_panel == null and WorldSearchPanelScene != null:
		_world_search_panel = WorldSearchPanelScene.instantiate() as Control
		_world_search_panel.name = "WorldSearchPanel"
		host.add_child(_world_search_panel)
	_sync_world_search_visibility()


func _sync_world_search_visibility() -> void:
	var show_search: bool = is_world_screen
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_search = false
	if _world_search_button != null and is_instance_valid(_world_search_button):
		_world_search_button.visible = show_search
		_world_search_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if show_search else Control.MOUSE_FILTER_IGNORE
		)
	if not show_search and _world_search_panel != null and is_instance_valid(_world_search_panel):
		if _world_search_panel.has_method("close_panel"):
			_world_search_panel.call("close_panel")
		else:
			_world_search_panel.visible = false


func _on_world_search_pressed() -> void:
	if not is_world_screen:
		return
	if _world_search_panel == null or not is_instance_valid(_world_search_panel):
		return
	if _world_search_panel.has_method("open_panel"):
		_world_search_panel.call("open_panel")


func _resync_marches() -> void:
	if has_node("/root/MarchState") and MarchState.has_method("resync_map_visuals"):
		MarchState.resync_map_visuals()


## Battle results go to Mail — no interrupting AcceptDialog.
func _on_wildling_march_battle(_march_id: String, _result: Dictionary) -> void:
	_refresh_mail_badge()


func _on_mail_changed() -> void:
	_refresh_mail_badge()


func _refresh_mail_badge() -> void:
	if mail_unread_badge == null:
		return
	var count: int = 0
	if has_node("/root/MailManager"):
		count = MailManager.get_unread_count()
	if count <= 0:
		mail_unread_badge.text = ""
	elif count > 9:
		mail_unread_badge.text = "●9+"
	else:
		mail_unread_badge.text = "●%d" % count


func _style_events_button() -> void:
	if events_button == null:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.12, 0.16, 0.24, 0.94)
	fill.border_color = Color(0.78, 0.66, 0.34, 0.95)
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(14)
	events_button.add_theme_stylebox_override("normal", fill)
	events_button.add_theme_stylebox_override("pressed", fill)
	events_button.add_theme_stylebox_override("hover", fill)
	events_button.add_theme_font_size_override("font_size", 14)
	events_button.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	events_button.focus_mode = Control.FOCUS_NONE


func _on_event_state_changed() -> void:
	_refresh_events_badge()


func _refresh_events_badge() -> void:
	if events_claim_badge == null:
		return
	var show_dot: bool = false
	if has_node("/root/EventState") and EventState.has_method("has_unclaimed_milestones"):
		show_dot = bool(EventState.has_unclaimed_milestones())
	events_claim_badge.text = "●" if show_dot else ""
	events_claim_badge.visible = events_button != null and events_button.visible and show_dot


func _on_event_points_awarded(_event_id: String, points: int, _reason: String, _total: int) -> void:
	if points <= 0:
		return
	_show_event_points_toast("+%d Royal Ascension" % points)


func _show_event_points_toast(message: String) -> void:
	if _event_toast_label == null or not is_instance_valid(_event_toast_label):
		_event_toast_label = Label.new()
		_event_toast_label.name = "EventPointsToast"
		_event_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_event_toast_label.add_theme_font_size_override("font_size", 18)
		_event_toast_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40, 1.0))
		_event_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_event_toast_label.offset_top = 220.0
		_event_toast_label.offset_bottom = 250.0
		_event_toast_label.offset_left = -200.0
		_event_toast_label.offset_right = 200.0
		$Control.add_child(_event_toast_label)
	_event_toast_label.text = message
	_event_toast_label.visible = true
	_event_toast_label.modulate.a = 1.0
	_event_toast_timer = 1.6
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("show_toast"):
		manager.call("show_toast", message)


func _tick_event_toast(delta: float) -> void:
	if _event_toast_label == null or not is_instance_valid(_event_toast_label) or not _event_toast_label.visible:
		return
	_event_toast_timer -= delta
	if _event_toast_timer <= 0.0:
		_event_toast_label.visible = false
		return
	if _event_toast_timer < 0.45:
		_event_toast_label.modulate.a = clampf(_event_toast_timer / 0.45, 0.0, 1.0)


func _run_hud_navigation_smoke_test_if_headless() -> void:
	if DisplayServer.get_name() != "headless":
		return

	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("run_navigation_smoke_test"):
		manager.run_navigation_smoke_test()

	# Alliance smoke tests write saves — only when explicitly enabled, and always isolated.
	if OS.get_environment("CROWNSPIR_ALLIANCE_SMOKE") == "1":
		if has_node("/root/AllianceState") and AllianceState.has_method("run_sprint_1b_smoke_test"):
			AllianceState.run_sprint_1b_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_sprint_1c_smoke_test"):
			AllianceState.run_sprint_1c_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_persistence_smoke_test"):
			AllianceState.run_persistence_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_research_smoke_test"):
			AllianceState.run_research_smoke_test()
	else:
		print("[GameHUD] Skipping Alliance smoke tests (set CROWNSPIR_ALLIANCE_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_MARCH_SMOKE") == "1":
		if has_node("/root/MarchState") and MarchState.has_method("run_wildling_march_smoke_test"):
			MarchState.run_wildling_march_smoke_test()
	else:
		print("[GameHUD] Skipping March smoke tests (set CROWNSPIR_MARCH_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_RESOURCE_TILE_SMOKE") == "1":
		if has_node("/root/ResourceTileState") and ResourceTileState.has_method("run_resource_tile_step3_smoke_test"):
			ResourceTileState.run_resource_tile_step3_smoke_test()
		if has_node("/root/MarchState") and MarchState.has_method("run_gather_tile_sync_smoke_test"):
			MarchState.run_gather_tile_sync_smoke_test()
	else:
		print("[GameHUD] Skipping ResourceTile smoke tests (set CROWNSPIR_RESOURCE_TILE_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_HERO_SMOKE") == "1":
		if has_node("/root/HeroState") and HeroState.has_method("run_hero_roster_smoke_test"):
			HeroState.run_hero_roster_smoke_test()
	else:
		print("[GameHUD] Skipping Hero smoke tests (set CROWNSPIR_HERO_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_EVENT_SMOKE") == "1":
		if has_node("/root/EventState") and EventState.has_method("run_royal_ascension_smoke_test"):
			EventState.run_royal_ascension_smoke_test()
		var manager_ev: Node = get_node_or_null("UIManager")
		if manager_ev != null:
			manager_ev.open_screen("EventsScreen")
			if manager_ev.get_current_screen_name() != "EventsScreen":
				push_error("[GameHUD] EventsScreen open smoke failed")
			else:
				print("[GameHUD] EventsScreen open OK")
			manager_ev.close_current_screen()
	else:
		print("[GameHUD] Skipping Event smoke tests (set CROWNSPIR_EVENT_SMOKE=1 for isolated runs).")

	if has_node("/root/StatResolver"):
		if StatResolver.has_method("run_phase1_smoke_test"):
			StatResolver.run_phase1_smoke_test()
		if StatResolver.has_method("run_phase2_smoke_test"):
			StatResolver.run_phase2_smoke_test()
	if has_node("/root/WildlingCombatResolver") and WildlingCombatResolver.has_method("run_phase3_smoke_test"):
		WildlingCombatResolver.run_phase3_smoke_test()
	if has_node("/root/HealingState") and HealingState.has_method("run_phase4_smoke_test"):
		HealingState.run_phase4_smoke_test()
	if has_node("/root/SanctuaryState") and SanctuaryState.has_method("run_phase5_smoke_test"):
		SanctuaryState.run_phase5_smoke_test()

	_run_world_search_smoke_if_world()


func _run_world_search_smoke_if_world() -> void:
	if not is_world_screen:
		return
	if _world_search_panel == null or not is_instance_valid(_world_search_panel):
		push_warning("[GameHUD] WorldSearchPanel missing on World HUD.")
		return
	if not _world_search_panel.has_method("open_panel"):
		return
	_world_search_panel.call("open_panel")
	var win: Control = _world_search_panel.get_node_or_null("SearchWindow") as Control
	if win == null:
		push_error("[GameHUD] WorldSearch SearchWindow missing.")
	else:
		var w: float = win.offset_right - win.offset_left
		var h: float = win.offset_bottom - win.offset_top
		print("[GameHUD] WorldSearch open OK | window %.0fx%.0f" % [w, h])
		if w < 300.0 or h < 280.0:
			push_error("[GameHUD] WorldSearch window too small.")
		if win.offset_top < 140.0:
			push_error("[GameHUD] WorldSearch overlaps top HUD.")
	# Exercise live find helpers against current World scene.
	if _world_search_panel.has_method("_find_nearest_resource"):
		var food: Dictionary = _world_search_panel.call("_find_nearest_resource", "food", 1)
		print("[GameHUD] WorldSearch food L1 ok=%s" % str(bool(food.get("ok", false))))
	if _world_search_panel.has_method("_find_nearest_wildling"):
		var wild: Dictionary = _world_search_panel.call("_find_nearest_wildling", 1)
		print("[GameHUD] WorldSearch wildling L1 ok=%s" % str(bool(wild.get("ok", false))))
	_world_search_panel.call("close_panel")
	if bool(_world_search_panel.visible):
		push_error("[GameHUD] WorldSearch failed to close.")
	else:
		print("[GameHUD] WorldSearch close OK")

func _process(delta):
	# Resource labels primarily refresh via GameState.resources_changed.
	# Keep a light fallback sync for diamonds/power/vip and HUD chrome.
	update_resources()
	_sync_secondary_hud_visibility()
	_sync_queue_status_visibility()
	_sync_active_marches_visibility()
	_sync_world_search_visibility()
	_sync_right_feature_visibility()
	_sync_chat_preview_visibility()
	_sync_help_button_visibility()
	_tick_event_toast(delta)


## Secondary HUD chrome (Mail only). Shop/Events live in RightFeatureButtons.
func set_secondary_hud_visible(is_visible: bool) -> void:
	if mail_button == null or not is_instance_valid(mail_button):
		return
	mail_button.visible = is_visible
	# Hidden Mail must never leave an active hitbox over Close/X controls.
	mail_button.mouse_filter = Control.MOUSE_FILTER_STOP if is_visible else Control.MOUSE_FILTER_IGNORE
	if mail_unread_badge != null and is_instance_valid(mail_unread_badge):
		mail_unread_badge.visible = is_visible
		mail_unread_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _sync_secondary_hud_visibility() -> void:
	var show_secondary: bool = true
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_secondary = false
	elif has_node("/root/GameState") and bool(GameState.popup_open):
		# Tavern / building upgrade / other city popups.
		show_secondary = false
	set_secondary_hud_visible(show_secondary)

func setup_bottom_bar():
	if is_world_screen:
		bottom_bar_texture.texture = bottom_bar_home
	else:
		bottom_bar_texture.texture = bottom_bar_world


## Invisible equal-width hit targets over the bottom bar art.
## Resets any broken editor scale/anchors so Alliance no longer maps to Map/City.
func _configure_bottom_nav() -> void:
	var buttons_box: HBoxContainer = $Control/BottomBarTexture/BottomButtons

	bottom_bar_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	buttons_box.scale = Vector2.ONE
	buttons_box.modulate = Color(1, 1, 1, 0)
	buttons_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	buttons_box.offset_left = 28.0
	buttons_box.offset_top = 42.0
	buttons_box.offset_right = -28.0
	buttons_box.offset_bottom = -10.0
	buttons_box.add_theme_constant_override("separation", 2)
	buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var nav_buttons: Array[Button] = [
		heroes_button,
		wayfinder_button,
		bag_button,
		quest_button,
		alliance_button,
		world_city_button,
	]

	for button: Button in nav_buttons:
		if button == null:
			continue
		button.text = ""
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 1.0


func _validate_bottom_nav_hitboxes() -> void:
	var nav_buttons: Array[Button] = [
		heroes_button,
		wayfinder_button,
		bag_button,
		quest_button,
		alliance_button,
		world_city_button,
	]

	var rects: Array[Rect2] = []
	for button: Button in nav_buttons:
		if button == null:
			push_error("[GameHUD] Missing bottom nav button.")
			return
		rects.append(button.get_global_rect())

	for i: int in range(rects.size()):
		if rects[i].size.x < 8.0 or rects[i].size.y < 8.0:
			push_error("[GameHUD] Bottom nav hitbox too small: %s" % nav_buttons[i].name)
		for j: int in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				push_error("[GameHUD] Bottom nav overlap: %s vs %s" % [
					nav_buttons[i].name,
					nav_buttons[j].name,
				])

	# Left-to-right order must match visual art slots.
	for i: int in range(rects.size() - 1):
		if rects[i].position.x >= rects[i + 1].position.x:
			push_error("[GameHUD] Bottom nav order broken between %s and %s" % [
				nav_buttons[i].name,
				nav_buttons[i + 1].name,
			])

	print("[GameHUD] Bottom nav OK: Heroes→Wayfinder→Bag→Quest→Alliance→WorldCity (no overlaps).")


## Mail sits bottom-right, directly above the bottom nav bar.
func _validate_mail_hitbox() -> void:
	if mail_button == null or not is_instance_valid(mail_button):
		push_error("[GameHUD] Mail button missing.")
		return
	var mail_rect: Rect2 = mail_button.get_global_rect()
	if mail_rect.size.x < 40.0 or mail_rect.size.y < 40.0:
		push_error("[GameHUD] Mail hitbox too small: %s" % str(mail_rect))
		return

	# Must sit in the lower HUD band (above bottom bar), not near top resources.
	if mail_rect.position.y < 900.0:
		push_error("[GameHUD] Mail not bottom-anchored (y=%.1f)." % mail_rect.position.y)
		return

	if shop_button != null and is_instance_valid(shop_button):
		var shop_rect: Rect2 = shop_button.get_global_rect()
		if mail_rect.intersects(shop_rect):
			push_error("[GameHUD] Mail overlaps Shop hitbox.")
			return

	if bottom_bar_texture != null and is_instance_valid(bottom_bar_texture):
		var bar_rect: Rect2 = bottom_bar_texture.get_global_rect()
		if mail_rect.intersects(bar_rect):
			push_error("[GameHUD] Mail overlaps bottom navigation bar.")
			return

	if world_city_button != null and is_instance_valid(world_city_button):
		var world_rect: Rect2 = world_city_button.get_global_rect()
		if mail_rect.intersects(world_rect):
			push_error("[GameHUD] Mail overlaps World/City button.")
			return

	if alliance_button != null and is_instance_valid(alliance_button):
		var alliance_rect: Rect2 = alliance_button.get_global_rect()
		if mail_rect.intersects(alliance_rect):
			push_error("[GameHUD] Mail overlaps Alliance button.")
			return

	print("[GameHUD] Mail hitbox OK: %s (bottom-right above nav)." % str(mail_rect))


func update_resources():
	food_label.text = format_number(GameState.food)
	wood_label.text = format_number(GameState.wood)
	stone_label.text = format_number(GameState.stone)
	iron_label.text = format_number(GameState.iron)
	diamond_label.text = format_with_commas(GameState.diamonds)

	power_label.text = format_with_commas(GameState.power)
	vip_label.text = "VIP %d" % GameState.vip_level

func format_number(value: int) -> String:
	## Canonical compact resource display for HUD + upgrade requirements.
	## Absolute units: 999 → "999", 1000 → "1.0K", 1_000_000 → "1.0M", 1_000_000_000 → "1.0B".
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)

func connect_buttons():
	if portrait_button:
		portrait_button.pressed.connect(_on_portrait_pressed)
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
	if events_button:
		events_button.pressed.connect(_on_events_pressed)
	if mail_button:
		mail_button.pressed.connect(_on_mail_pressed)
	if heroes_button:
		heroes_button.pressed.connect(_on_heroes_pressed)
	if wayfinder_button:
		wayfinder_button.pressed.connect(_on_wayfinder_pressed)
	if bag_button:
		bag_button.pressed.connect(_on_bag_pressed)
	if quest_button:
		quest_button.pressed.connect(_on_quest_pressed)
	if alliance_button:
		alliance_button.pressed.connect(_on_alliance_pressed)
	if world_city_button:
		world_city_button.pressed.connect(_on_world_city_pressed)

func _on_portrait_pressed():
	open_player_profile()


func open_player_profile(user_id: String = "") -> void:
	_ensure_profile_screen()
	if _profile_screen == null:
		return
	if _chat_preview != null and _chat_preview.has_method("set_force_hidden"):
		_chat_preview.call("set_force_hidden", true)
	if user_id.strip_edges() == "":
		await _profile_screen.open_self()
	else:
		await _profile_screen.open_user(user_id)
	# Profile is a floating modal on ScreenRoot — keep UIManager aware if possible.
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("notify_overlay_opened"):
		manager.call("notify_overlay_opened", "PlayerProfileScreen")


func _ensure_profile_screen() -> void:
	var root: Control = get_node_or_null("ScreenRoot") as Control
	if root == null:
		return
	_profile_screen = root.get_node_or_null("PlayerProfileScreen") as Control
	if _profile_screen == null:
		_profile_screen = Control.new()
		_profile_screen.name = "PlayerProfileScreen"
		_profile_screen.visible = false
		_profile_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_profile_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_profile_screen.set_script(load("res://scripts/UI/PlayerProfileScreen.gd"))
		_profile_screen.z_index = 60
		root.add_child(_profile_screen)
	if _profile_screen.has_signal("message_requested") and not _profile_screen.is_connected("message_requested", Callable(self, "_on_profile_message_requested")):
		_profile_screen.connect("message_requested", Callable(self, "_on_profile_message_requested"))
	if _profile_screen.has_signal("closed") and not _profile_screen.is_connected("closed", Callable(self, "_on_profile_closed")):
		_profile_screen.connect("closed", Callable(self, "_on_profile_closed"))


func _on_profile_message_requested(user_id: String, display_name: String) -> void:
	open_private_chat(user_id, display_name)


func _on_profile_closed() -> void:
	_sync_chat_preview_visibility()
	_refresh_portrait_avatar()


func open_private_chat(user_id: String, display_name: String = "") -> void:
	_ensure_chat_screen()
	var chat: Control = get_node_or_null("ScreenRoot/ChatScreen") as Control
	if chat != null and chat.has_method("request_open_private"):
		chat.call("request_open_private", user_id, display_name)
	if _chat_preview != null and _chat_preview.has_method("set_chat_session_open"):
		_chat_preview.call("set_chat_session_open", true)
	$UIManager.open_screen("ChatScreen")


func _bind_profile_avatar() -> void:
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		if ab.has_signal("profile_changed") and not ab.profile_changed.is_connected(_on_backend_profile_changed):
			ab.profile_changed.connect(_on_backend_profile_changed)


func _on_backend_profile_changed(_profile: Dictionary) -> void:
	_refresh_portrait_avatar()


func _refresh_portrait_avatar() -> void:
	if portrait_button == null:
		return
	# Replace empty black placeholder with the selected fantasy avatar.
	portrait_button.ignore_texture_size = true
	portrait_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
	# Keep a square-ish hit target in the top-left band.
	portrait_button.offset_left = 20.0
	portrait_button.offset_top = 20.0
	portrait_button.offset_right = 108.0
	portrait_button.offset_bottom = 108.0
	var avatar_id: String = "avatar_01"
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		if ab.has_method("get_avatar_id"):
			avatar_id = str(ab.get_avatar_id())
	portrait_button.texture_normal = PlayerAvatarCatalog.get_texture(avatar_id, 128)
	portrait_button.texture_pressed = portrait_button.texture_normal
	portrait_button.texture_hover = portrait_button.texture_normal
	portrait_button.modulate = Color.WHITE
	portrait_button.tooltip_text = "Player Profile"

func _on_shop_pressed():
	$UIManager.open_screen("ShopScreen")

func _on_events_pressed():
	$UIManager.open_screen("EventsScreen")


func _on_chat_pressed() -> void:
	open_chat()


func open_chat(preferred_tab: String = "kingdom") -> void:
	_ensure_chat_screen()
	var chat: Control = get_node_or_null("ScreenRoot/ChatScreen") as Control
	if chat != null and chat.has_method("request_open_tab") and preferred_tab != "":
		chat.call("request_open_tab", preferred_tab)
	if _chat_preview != null and _chat_preview.has_method("set_chat_session_open"):
		_chat_preview.call("set_chat_session_open", true)
	$UIManager.open_screen("ChatScreen")


func _remove_legacy_chat_button() -> void:
	if right_feature_buttons == null:
		return
	var legacy: Node = right_feature_buttons.get_node_or_null("ChatButton")
	if legacy != null:
		legacy.queue_free()
	# Restore compact Events/Shop stack height (no vertical Chat button).
	right_feature_buttons.offset_bottom = 220.0


func _ensure_chat_preview() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	_chat_preview = host.get_node_or_null("ChatPreview") as Control
	if _chat_preview == null:
		_chat_preview = Control.new()
		_chat_preview.name = "ChatPreview"
		_chat_preview.set_script(load("res://scripts/UI/ChatPreview.gd"))
		host.add_child(_chat_preview)
	# Keep preview above bottom nav, below ScreenRoot overlays.
	_chat_preview.z_index = 40
	if _chat_preview.has_signal("open_chat_requested"):
		if not _chat_preview.is_connected("open_chat_requested", Callable(self, "_on_chat_preview_open")):
			_chat_preview.connect("open_chat_requested", Callable(self, "_on_chat_preview_open"))
	_sync_chat_preview_visibility()


func _on_chat_preview_open() -> void:
	open_chat("kingdom")


func _ensure_chat_screen() -> void:
	var root: Control = get_node_or_null("ScreenRoot") as Control
	if root == null:
		return
	var existing: Control = root.get_node_or_null("ChatScreen") as Control
	if existing != null:
		return
	var chat := Control.new()
	chat.name = "ChatScreen"
	chat.visible = false
	chat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat.set_script(load("res://scripts/UI/ChatScreen.gd"))
	root.add_child(chat)


func _on_mail_pressed():
	$UIManager.open_screen("MailScreen")

func _on_heroes_pressed():
	print("Open Heroes")
	get_tree().change_scene_to_file.call_deferred("res://Scenes/UI/HeroRoster.tscn")

func _on_wayfinder_pressed():
	print("Wayfinder coming soon")

func _on_bag_pressed():
	$UIManager.open_screen("BagScreen")

func _on_quest_pressed():
	$UIManager.open_screen("QuestScreen")

func _on_alliance_pressed():
	$UIManager.open_screen("AllianceScreen")

func _on_world_city_pressed():
	print("World/City button clicked")

	if world_city_button:
		world_city_button.disabled = true

	if is_world_screen:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/City/City.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/World/KingdomMap.tscn")

func format_with_commas(value: int) -> String:
	var text := str(value)
	var result := ""

	while text.length() > 3:
		result = "," + text.substr(text.length() - 3, 3) + result
		text = text.substr(0, text.length() - 3)

	return text + result
	
