# ==============================================================================
# Crownspire MMO - World Root & HUD Manager Script
# Godot 4.6 / GDScript 2.0 Responsive Mobile Overlay Controller & Action Dispatcher
# ==============================================================================

extends Node2D

@export_category("System Links")
@export var kingdom_manager: KingdomManager
@export var camera: MapCamera2D

@export_group("UI Overlay Elements")
@export var detail_panel: PanelContainer
@export var panel_title: Label
@export var panel_description: Label
@export var panel_action_button: Button

# Keep track of current selected target node
var _selected_target: Node2D = null

func _ready() -> void:
	print("[WorldRoot] Scene loaded. Connecting event signals...")
	
	# Close panel on start
	if detail_panel:
		detail_panel.visible = false
		
	# Connecting signal handlers
	if kingdom_manager:
		kingdom_manager.display_resource_panel.connect(_on_display_resource_panel)
		kingdom_manager.display_wildling_panel.connect(_on_display_wildling_panel)
	else:
		push_error("[WorldRoot] Fatal: KingdomManager path is not linked in Inspector!")
		
	if panel_action_button:
		panel_action_button.pressed.connect(_on_action_button_pressed)

func _on_display_resource_panel(node: ResourceNode) -> void:
	_selected_target = node
	if not detail_panel:
		return
		
	panel_title.text = "👑 " + node.resource_type.capitalize() + " Deposit"
	panel_description.text = "Level: %d\nAvailable Supply: %s\nCoordinates: (%.1f, %.1f)" % [
		node.level, 
		_format_number(node.amount),
		node.global_position.x,
		node.global_position.y
	]
	
	panel_action_button.text = "DISPATCH GATHERERS"
	_show_panel()

func _on_display_wildling_panel(node: WildlingNode) -> void:
	_selected_target = node
	if not detail_panel:
		return
		
	panel_title.text = "⚔️ " + node.species + " Troop"
	panel_description.text = "Level: %d\nCombat Rating: %s CR\nCoordinates: (%.1f, %.1f)" % [
		node.level, 
		_format_number(node.power_rating),
		node.global_position.x,
		node.global_position.y
	]
	
	panel_action_button.text = "LAUNCH EXPEDITION"
	_show_panel()

func _on_action_button_pressed() -> void:
	if is_instance_valid(_selected_target):
		print("[WorldRoot] Launching active expedition toward node: ", _selected_target.name)
		if kingdom_manager:
			kingdom_manager.dispatch_march_to_node(_selected_target)
			
		# Automatically minimize the panel after starting march to prevent screen clutter
		_hide_panel()
	else:
		_hide_panel()

func _show_panel() -> void:
	if not detail_panel:
		return
	detail_panel.visible = true
	# Elegant slide-up animation for mobile HUD immersion
	var target_y = get_viewport_rect().size.y - detail_panel.size.y - 16.0
	detail_panel.global_position.y = get_viewport_rect().size.y
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(detail_panel, "global_position:y", target_y, 0.25)

func _hide_panel() -> void:
	if detail_panel:
		detail_panel.visible = false

# Utility number formatting (e.g. 100K, 1.2M)
func _format_number(num: int) -> String:
	if num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	return str(num)
