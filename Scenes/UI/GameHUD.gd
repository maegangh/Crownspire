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
const PlayerAvatarCatalog = preload("res://Scripts/UI/PlayerAvatarCatalog.gd")
@onready var shop_button: TextureButton = $Control/RightFeatureButtons/ShopButton
@onready var events_button: Button = $Control/RightFeatureButtons/EventsButton
@onready var events_claim_badge: Label = $Control/RightFeatureButtons/EventsButton/ClaimBadge
var _chat_preview: Control = null
var _castle_popup: Control = null
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
var _world_home_button: Button
var _world_search_panel: Control = null
var _active_marches_hud: Control = null

func _ready():
	add_to_group("game_hud")
	_apply_screen_context()
	_configure_bottom_nav()
	call_deferred("_apply_safe_area_insets")
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
	_bind_account_login_gate()
	_bind_social_notifications()
	_refresh_portrait_avatar()
	_refresh_mail_badge()
	_refresh_events_badge()
	_refresh_localized_labels()
	if has_node("/root/LocaleSettings") and not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)
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
	# Root must IGNORE — only queue cards own taps. STOP here ate ChatPreview taps
	# on Android where QueueStatusHUD shares the lower-left band at z_index 40.
	_queue_status_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	call_deferred("_position_chrome_above_chat")


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
		# Hit ownership lives on ChatPreview's internal button; keep root IGNORE.
		_chat_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
		_help_button.z_index = 61
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
	_help_button.z_index = 61
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
		_world_search_button.text = "🔍\n%s" % tr("HUD_SEARCH")
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
	# Size kept; Y is resolved against ChatPreview top in _position_chrome_above_chat().
	_world_search_button.custom_minimum_size = Vector2(96, 96)
	_world_search_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_world_search_button.anchor_left = 0.0
	_world_search_button.anchor_top = 1.0
	_world_search_button.anchor_right = 0.0
	_world_search_button.anchor_bottom = 1.0
	_world_search_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_world_search_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if not _world_search_button.pressed.is_connected(_on_world_search_pressed):
		_world_search_button.pressed.connect(_on_world_search_pressed)

	# Locate My Castle / Return Home button
	_world_home_button = host.get_node_or_null("WorldHomeButton") as Button
	if _world_home_button == null:
		_world_home_button = Button.new()
		_world_home_button.name = "WorldHomeButton"
		_world_home_button.text = "🏰\n%s" % tr("HUD_CASTLE")
		_world_home_button.focus_mode = Control.FOCUS_NONE

		var home_fill := StyleBoxFlat.new()
		home_fill.bg_color = Color(0.12, 0.11, 0.16, 0.92)
		home_fill.border_color = Color(0.78, 0.66, 0.34, 0.95)
		home_fill.set_border_width_all(2)
		home_fill.set_corner_radius_all(14)

		_world_home_button.add_theme_stylebox_override("normal", home_fill)
		_world_home_button.add_theme_font_size_override("font_size", 16)
		_world_home_button.add_theme_color_override(
			"font_color",
			Color(0.96, 0.92, 0.82, 1.0)
		)

		host.add_child(_world_home_button)

	_world_home_button.custom_minimum_size = Vector2(96, 96)
	_world_home_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_world_home_button.anchor_left = 0.0
	_world_home_button.anchor_top = 1.0
	_world_home_button.anchor_right = 0.0
	_world_home_button.anchor_bottom = 1.0
	_world_home_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_world_home_button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	if not _world_home_button.pressed.is_connected(_on_world_home_pressed):
		_world_home_button.pressed.connect(_on_world_home_pressed)

	# Regularly checks whether the castle has moved outside the visible map area.
	var home_update_timer: Timer = host.get_node_or_null("WorldHomeUpdateTimer") as Timer
	if home_update_timer == null:
		home_update_timer = Timer.new()
		home_update_timer.name = "WorldHomeUpdateTimer"
		home_update_timer.wait_time = 0.10
		home_update_timer.one_shot = false
		host.add_child(home_update_timer)

	if not home_update_timer.timeout.is_connected(_update_world_home_button):
		home_update_timer.timeout.connect(_update_world_home_button)

	home_update_timer.start()		

	_world_search_panel = host.get_node_or_null("WorldSearchPanel") as Control
	if _world_search_panel == null and WorldSearchPanelScene != null:
		_world_search_panel = WorldSearchPanelScene.instantiate() as Control
		_world_search_panel.name = "WorldSearchPanel"
		host.add_child(_world_search_panel)
	_sync_world_search_visibility()
	call_deferred("_position_chrome_above_chat")


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

	_update_world_home_button()

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

func _update_world_home_button() -> void:
	if _world_home_button == null or not is_instance_valid(_world_home_button):
		return

	# Castle button never appears outside the Kingdom Map.
	if not is_world_screen:
		_set_world_home_visible(false)
		return

	# Hide it while another full UI screen is open.
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open"):
		if bool(manager.is_screen_open()):
			_set_world_home_visible(false)
			return

	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		_set_world_home_visible(false)
		return

	var marker: Node2D = scene_tree.root.find_child(
		"PlayerCastleMarker",
		true,
		false
	) as Node2D

	var camera: Camera2D = scene_tree.root.find_child(
		"MapCamera",
		true,
		false
	) as Camera2D

	if camera == null:
		camera = scene_tree.root.find_child(
			"Camera2D",
			true,
			false
		) as Camera2D

	if marker == null or camera == null:
		_set_world_home_visible(false)
		return

	# Calculate the visible world area using the current camera zoom.
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	var half_visible_world: Vector2 = (viewport_size * 0.5) / camera.zoom

	var castle_offset: Vector2 = marker.global_position - camera.global_position

	var castle_is_visible: bool = (
		absf(castle_offset.x) <= half_visible_world.x
		and absf(castle_offset.y) <= half_visible_world.y
	)

	# Hide the button whenever the castle is on-screen.
	if castle_is_visible:
		_set_world_home_visible(false)
		return

	var distance: float = camera.global_position.distance_to(marker.global_position)

	_world_home_button.text = "🏰\n%s" % _format_world_distance(distance)
	_set_world_home_visible(true)


func _set_world_home_visible(should_show: bool) -> void:
	if _world_home_button == null or not is_instance_valid(_world_home_button):
		return

	_world_home_button.visible = should_show
	_world_home_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if should_show
		else Control.MOUSE_FILTER_IGNORE
	)


func _format_world_distance(distance: float) -> String:
	if distance >= 1000.0:
		return "%.1fK" % (distance / 1000.0)

	return str(int(round(distance)))

func _on_world_home_pressed() -> void:
	if not is_world_screen:
		return

	var marker: Node2D = get_tree().root.find_child(
		"PlayerCastleMarker",
		true,
		false
	) as Node2D

	if marker == null:
		push_warning("[WorldHome] PlayerCastleMarker not found")
		return

	var camera: Node = get_tree().root.find_child(
		"MapCamera",
		true,
		false
	)

	if camera == null:
		camera = get_tree().root.find_child(
			"Camera2D",
			true,
			false
		)

	if camera != null and camera.has_method("focus_world_position"):
		camera.call("focus_world_position", marker.global_position)
		print("[WorldHome] focused castle at %s" % str(marker.global_position))
	else:
		push_warning("[WorldHome] World camera/focus_world_position not found")

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
	events_button.text = tr("HUD_EVENTS")

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.12, 0.16, 0.24, 0.94)
	fill.border_color = Color(0.78, 0.66, 0.34, 0.95)
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(14)

	events_button.add_theme_stylebox_override("normal", fill)
	events_button.add_theme_stylebox_override("pressed", fill)
	events_button.add_theme_stylebox_override("hover", fill)
	events_button.add_theme_font_size_override("font_size", 14)
	events_button.add_theme_color_override(
		"font_color",
		Color(0.96, 0.92, 0.82, 1.0)
	)
	events_button.focus_mode = Control.FOCUS_NONE

	# Keep Events underneath Shop instead of overlapping it.
	if right_feature_buttons != null:
		right_feature_buttons.add_theme_constant_override("separation", 12)

	if shop_button != null:
		shop_button.custom_minimum_size = Vector2(96, 96)

	events_button.custom_minimum_size = Vector2(96, 64)


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


func _run_chat_preview_input_smoke_if_headless() -> void:
	if DisplayServer.get_name() != "headless":
		return
	_ensure_chat_preview()
	_ensure_chat_screen()
	_sync_chat_preview_visibility()
	if _chat_preview == null or not is_instance_valid(_chat_preview):
		push_error("[GameHUD] ChatPreview smoke failed: preview missing")
		return
	if not _chat_preview.visible:
		# Force visible for input routing check (no modal open in headless smoke).
		if _chat_preview.has_method("set_force_hidden"):
			_chat_preview.call("set_force_hidden", false)
		if _chat_preview.has_method("set_chat_session_open"):
			_chat_preview.call("set_chat_session_open", false)
		_chat_preview.visible = true
	if _chat_preview.has_method("refresh_layout_after_nav"):
		await _chat_preview.refresh_layout_after_nav()
	elif _chat_preview.has_method("refresh_layout"):
		_chat_preview.call("refresh_layout")
	_position_chrome_above_chat()
	await get_tree().process_frame
	var rect: Rect2 = _chat_preview.get_global_rect()
	var preview_hit: Control = _chat_preview.get_node_or_null("PreviewHitButton") as Control
	var preview_hit_rect: Rect2 = preview_hit.get_global_rect() if preview_hit != null else Rect2()
	var has_envelope: bool = false
	for child in _chat_preview.find_children("*", "TextureRect", true, false):
		var tr: TextureRect = child as TextureRect
		if tr != null and tr.texture != null and str(tr.texture.resource_path).find("mail_envelope") >= 0:
			has_envelope = true
			break
	print("[GameHUD] ChatPreview smoke rect=%s hit=%s h=%.1f envelope=%s" % [
		str(rect), str(preview_hit_rect), rect.size.y, str(has_envelope),
	])
	if has_envelope:
		push_error("[GameHUD] ChatPreview still contains mail envelope icon.")
	# Prove bottom-anchoring survives chrome height change (Android safe-area analogue).
	var chrome: Control = get_node_or_null("Control") as Control
	if chrome != null and bottom_bar_texture != null:
		var prev_bottom: float = chrome.offset_bottom
		chrome.offset_bottom = -48.0
		await get_tree().process_frame
		if _chat_preview.has_method("refresh_layout"):
			_chat_preview.call("refresh_layout")
		await get_tree().process_frame
		var chat2: Rect2 = _chat_preview.get_global_rect()
		var nav2: Rect2 = bottom_bar_texture.get_global_rect()
		var gap2: float = nav2.position.y - chat2.end.y
		print("[GameHUD] safe-area-sim gap after chrome inset=%.2f chat=%s nav=%s" % [gap2, str(chat2), str(nav2)])
		# City + World tuck behind nav (negative gap) — Kingdom screenshot is the reference.
		var gap_ok: bool = gap2 >= -40.0 and gap2 <= 4.0
		if not gap_ok:
			push_error("[GameHUD] ChatPreview did not follow BottomBarTexture after chrome inset (gap=%.2f)." % gap2)
		chrome.offset_bottom = prev_bottom
		if _chat_preview.has_method("refresh_layout"):
			_chat_preview.call("refresh_layout")
		await get_tree().process_frame
		rect = _chat_preview.get_global_rect()
		preview_hit_rect = preview_hit.get_global_rect() if preview_hit != null else Rect2()
	if rect.size.x < 80.0 or rect.size.y < 85.0:
		push_error("[GameHUD] ChatPreview smoke failed: panel too small %s (want ~90–105px tall)" % str(rect))
		return
	# Hit target must match width but end above the tucked overlap (~28px).
	if preview_hit != null:
		if absf(preview_hit_rect.size.x - rect.size.x) > 2.0:
			push_error("[GameHUD] PreviewHitButton width mismatch.")
		if preview_hit_rect.size.y > rect.size.y + 1.0 or preview_hit_rect.size.y < rect.size.y - 45.0:
			push_error("[GameHUD] PreviewHitButton height not clipped for nav tuck: hit=%.1f panel=%.1f" % [
				preview_hit_rect.size.y, rect.size.y,
			])
	if bottom_bar_texture != null and is_instance_valid(bottom_bar_texture):
		var nav_rect: Rect2 = bottom_bar_texture.get_global_rect()
		var left_delta: float = absf(rect.position.x - nav_rect.position.x)
		var right_delta: float = absf(rect.end.x - nav_rect.end.x)
		var gap_px: float = nav_rect.position.y - rect.end.y
		print("[GameHUD] ChatPreview↔nav leftΔ=%.2f rightΔ=%.2f gap=%.2f chatZ=%d barZ=%d" % [
			left_delta, right_delta, gap_px, _chat_preview.z_index, bottom_bar_texture.z_index,
		])
		print("[GameHUD] rects Search=%s Mail=%s Chat=%s Nav=%s Hit=%s" % [
			str(_world_search_button.get_global_rect() if _world_search_button != null else Rect2()),
			str(mail_button.get_global_rect() if mail_button != null else Rect2()),
			str(rect),
			str(nav_rect),
			str(preview_hit_rect),
		])
		if left_delta > 1.5 or right_delta > 1.5:
			push_error("[GameHUD] ChatPreview width does not match bottom nav edges.")
		# Intentional tuck: chat end below nav top (overlap ~25–35px).
		if gap_px < -40.0 or gap_px > 4.0:
			push_error("[GameHUD] ChatPreview tuck/gap out of range: %.2f" % gap_px)
		if bottom_bar_texture.z_index <= _chat_preview.z_index:
			push_error("[GameHUD] BottomBarTexture z_index must be above ChatPreview.")
		if preview_hit != null and preview_hit_rect.end.y > nav_rect.position.y + 2.0:
			push_error("[GameHUD] PreviewHitButton extends into bottom navigation hit area.")
		if mail_button != null and is_instance_valid(mail_button) and mail_button.visible:
			var mail_r: Rect2 = mail_button.get_global_rect()
			if mail_r.intersects(rect):
				push_error("[GameHUD] Mail overlaps ChatPreview.")
			if mail_r.end.y > rect.position.y - 6.0:
				push_error("[GameHUD] Mail clearance above ChatPreview too small.")
		if is_world_screen and _world_search_button != null and _world_search_button.visible:
			var search_r: Rect2 = _world_search_button.get_global_rect()
			if search_r.intersects(rect):
				push_error("[GameHUD] Search overlaps ChatPreview.")
			if search_r.end.y > rect.position.y - 6.0:
				push_error("[GameHUD] Search clearance above ChatPreview too small.")

	# 1) Signal / callback path (proves GameHUD ↔ ChatPreview wiring).
	if _chat_preview.has_method("debug_activate_for_test"):
		_chat_preview.call("debug_activate_for_test")
	else:
		_chat_preview.emit_signal("open_chat_requested")
	await get_tree().process_frame
	await get_tree().process_frame
	var manager: Node = get_node_or_null("UIManager")
	var opened_via_signal: bool = (
		manager != null
		and manager.has_method("is_screen_open")
		and bool(manager.is_screen_open())
		and str(manager.get_current_screen_name()) == "ChatScreen"
	)
	if not opened_via_signal:
		push_error("[GameHUD] ChatPreview smoke failed: signal path did not open ChatScreen")
	else:
		print("[GameHUD] ChatPreview signal→open_chat OK")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	await get_tree().create_timer(0.3).timeout
	_sync_chat_preview_visibility()

	# 2) Hit-button pressed signal (Android BaseButton activation path).
	if _chat_preview.has_method("set_force_hidden"):
		_chat_preview.call("set_force_hidden", false)
	if _chat_preview.has_method("set_chat_session_open"):
		_chat_preview.call("set_chat_session_open", false)
	_chat_preview.visible = true
	var hit_btn: Button = _chat_preview.get_node_or_null("PreviewHitButton") as Button
	if hit_btn == null:
		push_error("[GameHUD] ChatPreview smoke failed: PreviewHitButton missing")
	else:
		hit_btn.disabled = false
		hit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		hit_btn.visible = true
		print("[GameHUD] ChatPreview hit button rect=%s filter=%s disabled=%s owner_at_center=%s" % [
			str(hit_btn.get_global_rect()), str(hit_btn.mouse_filter), str(hit_btn.disabled),
			_diagnose_control_at(rect.get_center()),
		])
		if _chat_preview.has_method("debug_reset_activate_guard"):
			_chat_preview.call("debug_reset_activate_guard")
		hit_btn.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var opened_via_button: bool = (
			manager != null
			and manager.has_method("is_screen_open")
			and bool(manager.is_screen_open())
			and str(manager.get_current_screen_name()) == "ChatScreen"
		)
		if not opened_via_button:
			push_error("[GameHUD] ChatPreview smoke failed: PreviewHitButton.pressed did not open ChatScreen")
		else:
			print("[GameHUD] ChatPreview button.pressed→open_chat OK")
		if manager != null and manager.has_method("close_current_screen"):
			manager.close_current_screen()
		await get_tree().create_timer(0.3).timeout
		_sync_chat_preview_visibility()

	# 3) Desktop mouse + Android-equivalent at preview center (informational in headless).
	_push_preview_pointer_click(rect.get_center(), false)
	await get_tree().process_frame
	await get_tree().process_frame
	var opened_via_mouse: bool = (
		manager != null
		and manager.has_method("is_screen_open")
		and bool(manager.is_screen_open())
		and str(manager.get_current_screen_name()) == "ChatScreen"
	)
	if opened_via_mouse:
		print("[GameHUD] ChatPreview mouse click→open_chat OK")
		if manager != null and manager.has_method("close_current_screen"):
			manager.close_current_screen()
		await get_tree().create_timer(0.3).timeout
	else:
		print("[GameHUD] ChatPreview mouse push_input skipped/failed in headless (owner=%s) — device uses real GUI delivery" % _diagnose_control_at(rect.get_center()))

	_sync_chat_preview_visibility()
	_push_preview_pointer_click(rect.get_center(), true)
	await get_tree().process_frame
	await get_tree().process_frame
	var opened_via_touch: bool = (
		manager != null
		and manager.has_method("is_screen_open")
		and bool(manager.is_screen_open())
		and str(manager.get_current_screen_name()) == "ChatScreen"
	)
	if opened_via_touch:
		print("[GameHUD] ChatPreview ScreenTouch/mouse→open_chat OK")
		if manager != null and manager.has_method("close_current_screen"):
			manager.close_current_screen()
		await get_tree().create_timer(0.3).timeout
	else:
		print("[GameHUD] ChatPreview ScreenTouch push_input informational-only in headless")

	_sync_chat_preview_visibility()
	if _chat_preview != null and is_instance_valid(_chat_preview) and _chat_preview.visible:
		print("[GameHUD] ChatPreview restored visible after close OK")
	print("[GameHUD] ChatPreview input smoke done")


func _diagnose_control_at(screen_pos: Vector2) -> String:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return "no-host"
	var best: Control = null
	var best_z: int = -999999
	for child in host.get_children():
		if not (child is Control):
			continue
		var c: Control = child as Control
		if not c.visible:
			continue
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(screen_pos):
			if best == null or c.z_index >= best_z:
				best = c
				best_z = c.z_index
		# Descend into IGNORE parents (ChatPreview root ignores; hit button stops).
		for sub in c.find_children("*", "Control", true, false):
			var s: Control = sub as Control
			if s == null or not s.visible or s.mouse_filter != Control.MOUSE_FILTER_STOP:
				continue
			if s.get_global_rect().has_point(screen_pos):
				var z: int = s.z_index
				var p: Node = s.get_parent()
				while p != null and p != host:
					if p is CanvasItem:
						z += (p as CanvasItem).z_index
					p = p.get_parent()
				if best == null or z >= best_z:
					best = s
					best_z = z
	if best == null:
		return "none"
	return "%s(z~%d filter=%d)" % [str(best.get_path()), best_z, best.mouse_filter]


func _push_preview_pointer_click(screen_pos: Vector2, as_touch: bool) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	# BaseButton needs hover before press in some headless/GUI paths.
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	vp.push_input(motion)
	if as_touch:
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.pressed = true
		down.position = screen_pos
		vp.push_input(down)
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.pressed = false
		up.position = screen_pos
		vp.push_input(up)
	# Android GUI uses emulate_mouse_from_touch → MouseButton on BaseButton.
	var mb_down := InputEventMouseButton.new()
	mb_down.button_index = MOUSE_BUTTON_LEFT
	mb_down.pressed = true
	mb_down.position = screen_pos
	mb_down.global_position = screen_pos
	mb_down.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(mb_down)
	var mb_up := InputEventMouseButton.new()
	mb_up.button_index = MOUSE_BUTTON_LEFT
	mb_up.pressed = false
	mb_up.position = screen_pos
	mb_up.global_position = screen_pos
	mb_up.button_mask = 0
	vp.push_input(mb_up)


func _run_hud_navigation_smoke_test_if_headless() -> void:
	if DisplayServer.get_name() != "headless":
		return

	await _run_chat_preview_input_smoke_if_headless()

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


## Hide / restore gameplay-only HUD while full-screen profile / major modals are open.
func set_gameplay_hud_visible(is_visible: bool) -> void:
	var chrome: Control = get_node_or_null("Control") as Control
	if chrome != null:
		chrome.visible = is_visible
		chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_visible else Control.MOUSE_FILTER_IGNORE
	if _queue_status_hud != null and is_instance_valid(_queue_status_hud):
		if not is_visible:
			_queue_status_hud.visible = false
	if events_button != null and is_instance_valid(events_button) and not is_visible:
		events_button.visible = false
	if right_feature_buttons != null and is_instance_valid(right_feature_buttons):
		right_feature_buttons.visible = is_visible
	if _chat_preview != null and is_instance_valid(_chat_preview):
		if _chat_preview.has_method("set_force_hidden"):
			_chat_preview.call("set_force_hidden", not is_visible)
		else:
			_chat_preview.visible = is_visible
	if _help_button != null and is_instance_valid(_help_button) and not is_visible:
		_help_button.visible = false
	if is_visible:
		_sync_queue_status_visibility()
		_sync_chat_preview_visibility()
		_sync_help_button_visibility()
		_sync_right_feature_visibility()


func _apply_safe_area_insets() -> void:
	## Align top HUD / bottom nav with device safe areas (notches / home indicators).
	## Safe-area is applied ONCE on GameHUD/Control. Children (TopBarTexture) must not
	## add a second top inset — that creates a City-visible gap above the HUD art.
	var chrome: Control = get_node_or_null("Control") as Control
	if chrome == null:
		return
	var safe: Rect2 = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		_align_city_top_hud()
		call_deferred("_log_top_hud_geometry")
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var top_inset: float = maxf(0.0, float(safe.position.y) * (vp_size.y / float(win.y)))
	var bottom_inset: float = maxf(0.0, float(win.y - (safe.position.y + safe.size.y)) * (vp_size.y / float(win.y)))
	# Keep at least a few px on modern phones; ignore tiny values on desktop.
	if top_inset < 8.0 and bottom_inset < 8.0 and OS.get_name() != "Android":
		_align_city_top_hud()
		call_deferred("_log_top_hud_geometry")
		return
	chrome.offset_top = top_inset
	chrome.offset_bottom = -bottom_inset
	# Portrait is a chrome child — use local offsets only (do NOT add top_inset again).
	if portrait_button != null:
		portrait_button.offset_top = 20.0
		portrait_button.offset_bottom = 108.0
	_align_city_top_hud()
	# ChatPreview must re-measure AFTER safe-area changes chrome height (bottom-anchored nav moves).
	if _chat_preview != null and is_instance_valid(_chat_preview):
		if _chat_preview.has_method("refresh_layout_after_nav"):
			_chat_preview.call_deferred("refresh_layout_after_nav")
		elif _chat_preview.has_method("refresh_layout"):
			_chat_preview.call_deferred("refresh_layout")
	call_deferred("_position_chrome_above_chat")
	call_deferred("_log_top_hud_geometry")


func _align_city_top_hud() -> void:
	## Kingdom top HUD is the visual reference and must stay untouched.
	## City only: cancel TopBarTexture's baked editor drop (offset_top=80 with negative
	## anchors) plus the top_bar.png transparent pad so opaque HUD art meets chrome top
	## (chrome top == safe-area top after _apply_safe_area_insets).
	if is_world_screen:
		return
	var top: TextureRect = get_node_or_null("Control/TopBarTexture") as TextureRect
	if top == null:
		return
	var bar_h: float = maxf(1.0, top.offset_bottom - top.offset_top)
	if bar_h < 8.0:
		bar_h = 179.0
	# Measured: top_bar.png (~250px) stays nearly transparent until ~row 40.
	var tex_pad_src: float = 40.0
	var tex_h: float = float(top.texture.get_height()) if top.texture != null else 250.0
	var pad: float = tex_pad_src * (bar_h / maxf(1.0, tex_h))
	# Pin to chrome top (anchor 0) — safe-area lives on chrome, not here.
	top.anchor_top = 0.0
	top.anchor_bottom = 0.0
	top.offset_top = -pad
	top.offset_bottom = bar_h - pad
	# Keep portrait in the TopBar portrait hole (was ~31px below old TopBar top).
	if portrait_button != null:
		var hole: float = 31.0
		portrait_button.offset_top = top.offset_top + hole
		portrait_button.offset_bottom = portrait_button.offset_top + 88.0
		portrait_button.offset_left = 20.0
		portrait_button.offset_right = 108.0


func _log_top_hud_geometry() -> void:
	var vp: Rect2 = get_viewport().get_visible_rect() if get_viewport() != null else Rect2()
	var safe: Rect2 = DisplayServer.get_display_safe_area()
	var chrome: Control = get_node_or_null("Control") as Control
	var top: Control = get_node_or_null("Control/TopBarTexture") as Control
	var bar: Control = bottom_bar_texture
	var chat_r: Rect2 = _chat_preview.get_global_rect() if _chat_preview != null else Rect2()
	var top_r: Rect2 = top.get_global_rect() if top != null else Rect2()
	var bar_r: Rect2 = bar.get_global_rect() if bar != null else Rect2()
	var overlap: float = 0.0
	if chat_r.size.y > 1.0 and bar_r.size.y > 1.0:
		overlap = chat_r.end.y - bar_r.position.y
	print("[GameHUD] topHUD screen=%s vp=%s safe=%s chrome=%s top=%s topY=%.2f chat=%s bar=%s chatZ=%s barZ=%s overlap=%.2f chromeTopOff=%.2f" % [
		"WORLD" if is_world_screen else "CITY",
		str(vp),
		str(safe),
		str(chrome.get_global_rect() if chrome != null else Rect2()),
		str(top_r),
		top_r.position.y,
		str(chat_r),
		str(bar_r),
		str(_chat_preview.z_index) if _chat_preview != null else "?",
		str(bar.z_index) if bar != null else "?",
		overlap,
		chrome.offset_top if chrome != null else 0.0,
	])


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
	## City and Kingdom use different bar textures. City keeps KEEP_ASPECT_CENTERED
	## (letterboxed width is intentional for that art). Kingdom scales to full bleed.
	## Both raise BottomBarTexture above ChatPreview so nav paints/taps on top.
	if bottom_bar_texture == null:
		return
	if is_world_screen:
		bottom_bar_texture.texture = bottom_bar_home
		bottom_bar_texture.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		bottom_bar_texture.texture = bottom_bar_world
		bottom_bar_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bottom_bar_texture.z_index = 70 ## ChatPreview uses z=40 — nav always in front
	call_deferred("_log_bottom_bar_geometry")
	call_deferred("_align_city_top_hud")
	call_deferred("_log_top_hud_geometry")


func _log_bottom_bar_geometry() -> void:
	var vp: Rect2 = get_viewport().get_visible_rect() if get_viewport() != null else Rect2()
	var chrome: Control = get_node_or_null("Control") as Control
	var bar_r: Rect2 = bottom_bar_texture.get_global_rect() if bottom_bar_texture != null else Rect2()
	var chat_r: Rect2 = _chat_preview.get_global_rect() if _chat_preview != null else Rect2()
	var drawn: Rect2 = _compute_drawn_bar_rect()
	print("[GameHUD] bottomBar screen=%s vp=%s chrome=%s bar=%s drawn≈%s chat=%s stretch=%s" % [
		"WORLD" if is_world_screen else "CITY",
		str(vp),
		str(chrome.get_global_rect() if chrome != null else Rect2()),
		str(bar_r),
		str(drawn),
		str(chat_r),
		str(bottom_bar_texture.stretch_mode) if bottom_bar_texture != null else "?",
	])
	if vp.size.x > 1.0 and drawn.size.x > 1.0:
		print("[GameHUD] bottomBar edgeΔ left=%.2f right=%.2f (drawn vs viewport)" % [
			drawn.position.x - vp.position.x,
			(vp.position.x + vp.size.x) - drawn.end.x,
		])


func _compute_drawn_bar_rect() -> Rect2:
	## Approximate the player-visible painted bar inside BottomBarTexture.
	if bottom_bar_texture == null:
		return Rect2()
	var bar_r: Rect2 = bottom_bar_texture.get_global_rect()
	var tex: Texture2D = bottom_bar_texture.texture
	if tex == null:
		return bar_r
	var mode: int = bottom_bar_texture.stretch_mode
	if mode == TextureRect.STRETCH_SCALE or mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		return bar_r
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 1.0 or tex_size.y <= 1.0 or bar_r.size.y <= 1.0:
		return bar_r
	var scale: float = minf(bar_r.size.x / tex_size.x, bar_r.size.y / tex_size.y)
	var drawn: Vector2 = tex_size * scale
	var origin: Vector2 = bar_r.position + (bar_r.size - drawn) * 0.5
	return Rect2(origin, drawn)


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

	# Must sit in the lower HUD band (above ChatPreview / bottom bar), not near top resources.
	if mail_rect.position.y < 700.0:
		push_error("[GameHUD] Mail not bottom-anchored (y=%.1f)." % mail_rect.position.y)
		return

	if shop_button != null and is_instance_valid(shop_button):
		var shop_rect: Rect2 = shop_button.get_global_rect()
		if mail_rect.intersects(shop_rect):
			push_error("[GameHUD] Mail overlaps Shop hitbox.")
			return

	if _chat_preview != null and is_instance_valid(_chat_preview) and _chat_preview.visible:
		var chat_r: Rect2 = _chat_preview.get_global_rect()
		if mail_rect.intersects(chat_r):
			push_error("[GameHUD] Mail overlaps ChatPreview.")
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
	vip_label.text = tr("HUD_VIP") % str(GameState.vip_level)

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


func open_player_profile(user_id: String = "", world_seed: Dictionary = {}) -> void:
	_ensure_profile_screen()
	if _profile_screen == null:
		return
	if _castle_popup != null and is_instance_valid(_castle_popup) and _castle_popup.has_method("close_panel"):
		_castle_popup.call("close_panel")
	if _chat_preview != null and _chat_preview.has_method("set_force_hidden"):
		_chat_preview.call("set_force_hidden", true)
	if has_node("/root/GameState"):
		GameState.popup_open = true
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("notify_overlay_opened"):
		manager.call("notify_overlay_opened", "PlayerProfileScreen")
	set_gameplay_hud_visible(false)
	if user_id.strip_edges() == "":
		await _profile_screen.open_self()
	else:
		await _profile_screen.open_user(user_id, world_seed)


func ensure_player_castle_popup() -> Control:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return null
	_castle_popup = host.get_node_or_null("PlayerCastlePopup") as Control
	if _castle_popup == null:
		_castle_popup = Control.new()
		_castle_popup.name = "PlayerCastlePopup"
		_castle_popup.set_script(load("res://Scripts/UI/PlayerCastlePopup.gd"))
		host.add_child(_castle_popup)
	_castle_popup.z_index = 120
	return _castle_popup


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
		_profile_screen.set_script(load("res://Scripts/UI/PlayerProfileScreen.gd"))
		_profile_screen.z_index = 80
		root.add_child(_profile_screen)
	if _profile_screen.has_signal("message_requested") and not _profile_screen.is_connected("message_requested", Callable(self, "_on_profile_message_requested")):
		_profile_screen.connect("message_requested", Callable(self, "_on_profile_message_requested"))
	if _profile_screen.has_signal("closed") and not _profile_screen.is_connected("closed", Callable(self, "_on_profile_closed")):
		_profile_screen.connect("closed", Callable(self, "_on_profile_closed"))


func _bind_account_login_gate() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		return
	if identity.has_signal("login_gate_requested") and not identity.login_gate_requested.is_connected(_on_login_gate_requested):
		identity.login_gate_requested.connect(_on_login_gate_requested)
	# Boot must not treat known-secured ownership as a login overlay.
	# Show only if restore already reached a terminal gate-required state with no live session.
	if identity.has_method("should_force_login_gate") and bool(identity.call("should_force_login_gate")):
		_on_login_gate_requested("boot")


func _on_login_gate_requested(reason: String) -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_method("should_force_login_gate") and not bool(identity.call("should_force_login_gate")):
		print("[CrownspireSession] gate_suppressed_live_session")
		return
	var gate_script: GDScript = load("res://Scripts/UI/AccountLoginGate.gd") as GDScript
	if gate_script == null or get_tree() == null or get_tree().root == null:
		return
	if get_tree().root.get_node_or_null("AccountLoginGate") != null:
		return
	print("[CrownspireSession] gate_shown reason=%s" % str(reason).strip_edges())
	var gate: CanvasLayer = gate_script.new() as CanvasLayer
	gate.name = "AccountLoginGate"
	get_tree().root.add_child(gate)


func _on_profile_message_requested(user_id: String, display_name: String) -> void:
	open_private_chat(user_id, display_name)


func _on_profile_closed() -> void:
	if has_node("/root/GameState"):
		GameState.popup_open = false
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("notify_overlay_closed"):
		manager.call("notify_overlay_closed")
	set_gameplay_hud_visible(true)
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


func _bind_social_notifications() -> void:
	if has_node("/root/FriendsBackend"):
		var fb: Node = get_node("/root/FriendsBackend")
		if fb.has_signal("friend_request_received") and not fb.friend_request_received.is_connected(_on_friend_request_toast):
			fb.friend_request_received.connect(_on_friend_request_toast)
		if fb.has_signal("friend_accepted") and not fb.friend_accepted.is_connected(_on_friend_accepted_toast):
			fb.friend_accepted.connect(_on_friend_accepted_toast)
	if has_node("/root/ChatManager"):
		var cm: Node = get_node("/root/ChatManager")
		if cm.has_signal("private_message_notify") and not cm.private_message_notify.is_connected(_on_private_message_toast):
			cm.private_message_notify.connect(_on_private_message_toast)


func _on_friend_request_toast(user_id: String, display_name: String) -> void:
	if user_id.strip_edges() == "":
		return
	_show_event_points_toast("Friend request from %s" % (display_name if display_name != "" else "Player"))


func _on_friend_accepted_toast(user_id: String, display_name: String) -> void:
	if user_id.strip_edges() == "":
		return
	_show_event_points_toast("%s is now your friend" % (display_name if display_name != "" else "Player"))


func _on_private_message_toast(peer_user_id: String, display_name: String, preview: String) -> void:
	if peer_user_id.strip_edges() == "":
		return
	var name_text: String = display_name if display_name != "" else "Player"
	var body: String = preview.strip_edges()
	if body.length() > 36:
		body = body.substr(0, 33) + "…"
	if body == "":
		_show_event_points_toast("Message from %s" % name_text)
	else:
		_show_event_points_toast("%s: %s" % [name_text, body])


func _on_backend_profile_changed(_profile: Dictionary) -> void:
	_refresh_portrait_avatar()


func _refresh_portrait_avatar() -> void:
	if portrait_button == null:
		return
	# Replace empty black placeholder with the selected fantasy avatar.
	portrait_button.ignore_texture_size = true
	portrait_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
	# City TopBar is re-pinned in _align_city_top_hud(); don't stomp those offsets.
	if is_world_screen:
		portrait_button.offset_left = 20.0
		portrait_button.offset_top = 20.0
		portrait_button.offset_right = 108.0
		portrait_button.offset_bottom = 108.0
	else:
		_align_city_top_hud()
	var avatar_id: String = "avatar_01"
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		if ab.has_method("get_avatar_id"):
			avatar_id = str(ab.get_avatar_id())
	portrait_button.texture_normal = PlayerAvatarCatalog.get_texture(avatar_id, 128)
	portrait_button.texture_pressed = portrait_button.texture_normal
	portrait_button.texture_hover = portrait_button.texture_normal
	portrait_button.modulate = Color.WHITE
	portrait_button.tooltip_text = tr("HUD_PLAYER_PROFILE_TOOLTIP")

func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_labels()


func _refresh_localized_labels() -> void:
	if _world_search_button != null and is_instance_valid(_world_search_button):
		_world_search_button.text = "🔍\n%s" % tr("HUD_SEARCH")
	if _world_home_button != null and is_instance_valid(_world_home_button):
		# Keep numeric distance labels; only refresh the CASTLE word label.
		if not _is_distance_home_label(_world_home_button.text):
			_world_home_button.text = "🏰\n%s" % tr("HUD_CASTLE")
	if events_button != null and is_instance_valid(events_button):
		events_button.text = tr("HUD_EVENTS")
	if vip_label != null and is_instance_valid(vip_label) and has_node("/root/GameState"):
		vip_label.text = tr("HUD_VIP") % str(GameState.vip_level)
	if portrait_button != null and is_instance_valid(portrait_button):
		portrait_button.tooltip_text = tr("HUD_PLAYER_PROFILE_TOOLTIP")


func _is_distance_home_label(text: String) -> bool:
	# Distance labels look like "🏰\n1.2K" / "🏰\n850" — not the CASTLE word.
	var parts: PackedStringArray = text.split("\n")
	if parts.size() < 2:
		return false
	var tail: String = parts[1].strip_edges()
	return tail.is_valid_float() or tail.ends_with("K") or tail.ends_with("M")


func _on_shop_pressed():
	$UIManager.open_screen("ShopScreen")

func _on_events_pressed():
	$UIManager.open_screen("EventsScreen")


func _on_chat_pressed() -> void:
	open_chat()


func open_chat(preferred_tab: String = "kingdom") -> void:
	print("[GameHUD] open_chat requested: %s" % preferred_tab)
	_ensure_chat_screen()
	var chat: Control = get_node_or_null("ScreenRoot/ChatScreen") as Control
	if chat != null and chat.has_method("request_open_tab") and preferred_tab != "":
		chat.call("request_open_tab", preferred_tab)
	if _chat_preview != null and _chat_preview.has_method("set_chat_session_open"):
		_chat_preview.call("set_chat_session_open", true)
	print("[GameHUD] creating/opening ChatScreen")
	$UIManager.open_screen("ChatScreen")


func _remove_legacy_chat_button() -> void:
	if right_feature_buttons == null:
		return
	var legacy: Node = right_feature_buttons.get_node_or_null("ChatButton")
	if legacy != null:
		legacy.queue_free()
	# Restore compact Events/Shop stack height (no vertical Chat button).
	right_feature_buttons.offset_bottom = 270.0


func _ensure_chat_preview() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	_chat_preview = host.get_node_or_null("ChatPreview") as Control
	if _chat_preview == null:
		_chat_preview = Control.new()
		_chat_preview.name = "ChatPreview"
		_chat_preview.set_script(load("res://Scripts/UI/ChatPreview.gd"))
		host.add_child(_chat_preview)
	# Below BottomBarTexture (70). Mail/Search stay at 50 (above chat, below nav).
	_chat_preview.z_index = 40
	_chat_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ensure later tree order among same-layer chrome siblings.
	host.move_child(_chat_preview, host.get_child_count() - 1)
	if _chat_preview.has_signal("open_chat_requested"):
		if not _chat_preview.is_connected("open_chat_requested", Callable(self, "_on_chat_preview_open")):
			_chat_preview.connect("open_chat_requested", Callable(self, "_on_chat_preview_open"))
			print("[GameHUD] ChatPreview open_chat_requested connected")
	else:
		push_error("[GameHUD] ChatPreview missing open_chat_requested signal")
	if _chat_preview.has_signal("layout_changed"):
		if not _chat_preview.is_connected("layout_changed", Callable(self, "_on_chat_preview_layout_changed")):
			_chat_preview.connect("layout_changed", Callable(self, "_on_chat_preview_layout_changed"))
	if _chat_preview.has_method("refresh_layout_after_nav"):
		_chat_preview.call_deferred("refresh_layout_after_nav")
	elif _chat_preview.has_method("refresh_layout"):
		_chat_preview.call_deferred("refresh_layout")
	_sync_chat_preview_visibility()
	call_deferred("_position_chrome_above_chat")


func _on_chat_preview_open() -> void:
	print("[GameHUD] ChatPreview open_chat_requested received")
	open_chat("kingdom")


func _on_chat_preview_layout_changed(_rect: Rect2) -> void:
	_position_chrome_above_chat()


## Keep Search (world) + Mail above the ChatPreview panel (8–12px clearance).
## Does NOT call _ensure_chat_preview() — that would recurse via deferred layout hooks.
func _position_chrome_above_chat() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	if _chat_preview == null or not is_instance_valid(_chat_preview):
		return
	var chat_rect: Rect2 = _chat_preview.get_global_rect()
	if chat_rect.size.y < 8.0:
		return
	var host_rect: Rect2 = host.get_global_rect()
	var clearance: float = 10.0
	var btn_bottom_global: float = chat_rect.position.y - clearance
	# Bottom-anchored offsets: distance from host bottom to control bottom (negative = above).
	var offset_bottom: float = btn_bottom_global - host_rect.end.y

	# Mail — both City and World; sit above ChatPreview so the taller panel never covers it.
	if mail_button != null and is_instance_valid(mail_button):
		var mail_h: float = maxf(72.0, mail_button.size.y if mail_button.size.y > 1.0 else 80.0)
		mail_button.anchor_left = 1.0
		mail_button.anchor_top = 1.0
		mail_button.anchor_right = 1.0
		mail_button.anchor_bottom = 1.0
		mail_button.offset_right = -16.0
		mail_button.offset_left = -16.0 - mail_h
		mail_button.offset_bottom = offset_bottom
		mail_button.offset_top = offset_bottom - mail_h
		mail_button.z_index = 50

	# Search — World Map only.
	if is_world_screen and _world_search_button != null and is_instance_valid(_world_search_button):
		var search_h: float = 96.0
		_world_search_button.anchor_left = 0.0
		_world_search_button.anchor_top = 1.0
		_world_search_button.anchor_right = 0.0
		_world_search_button.anchor_bottom = 1.0
		_world_search_button.offset_left = 14.0
		_world_search_button.offset_right = 14.0 + search_h
		_world_search_button.offset_bottom = offset_bottom
		_world_search_button.offset_top = offset_bottom - search_h
		_world_search_button.z_index = 50

	# Locate Castle — beside Search on the World Map.
	if is_world_screen and _world_home_button != null and is_instance_valid(_world_home_button):
		var home_h: float = 96.0
		var button_gap: float = 10.0

		_world_home_button.anchor_left = 0.0
		_world_home_button.anchor_top = 1.0
		_world_home_button.anchor_right = 0.0
		_world_home_button.anchor_bottom = 1.0

		_world_home_button.offset_left = 14.0 + 96.0 + button_gap
		_world_home_button.offset_right = 14.0 + 96.0 + button_gap + home_h
		_world_home_button.offset_bottom = offset_bottom
		_world_home_button.offset_top = offset_bottom - home_h
		_world_home_button.z_index = 50

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
	chat.set_script(load("res://Scripts/UI/ChatScreen.gd"))
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
		# One-use enter-at-home: World Map must center on authoritative castle after placement.
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.set_meta("world_enter_at_home", true)
			if tree.has_meta("world_enter_at_home_settled"):
				tree.remove_meta("world_enter_at_home_settled")
			# Fresh KingdomMap load — do not inherit prior FTUE wildling focus tracking.
			if tree.has_meta("ftue_world_focused_wildling_iid"):
				tree.remove_meta("ftue_world_focused_wildling_iid")
		get_tree().change_scene_to_file.call_deferred("res://Scenes/World/KingdomMap.tscn")

func format_with_commas(value: int) -> String:
	var text := str(value)
	var result := ""

	while text.length() > 3:
		result = "," + text.substr(text.length() - 3, 3) + result
		text = text.substr(0, text.length() - 3)

	return text + result
	
