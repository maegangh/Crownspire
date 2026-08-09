extends PanelContainer

# Signal emitted when player selects this node
signal selected(node_id: String)

@export var research_id: String = ""

# Internal states
var node_name: String = ""
var max_level: int = 1
var current_level: int = 0
var status: String = "unlocked" # locked, unlocked, ready, researching, queued, max
var is_affordable: bool = false

# UI References
@onready var node_button: Button = $NodeButton
@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var level_label: Label = %LevelLabel
@onready var status_label: Label = %StatusLabel
@onready var highlight_border: ReferenceRect = %HighlightBorder
@onready var border_overlay: Panel = %BorderOverlay
@onready var badge_rect: PanelContainer = %BadgeRect
@onready var badge_label: Label = %BadgeLabel

func _ready() -> void:
	if node_button:
		node_button.pressed.connect(_on_node_pressed)
		node_button.mouse_entered.connect(_on_mouse_entered)
		node_button.mouse_exited.connect(_on_mouse_exited)
	
	highlight_border.visible = false
	_update_visuals()

# Setup properties and load from DB
func setup(data: Dictionary, state_level: int, state_status: String, affordable: bool) -> void:
	research_id = data.get("id", "")
	node_name = data.get("name", "Technology")
	max_level = int(data.get("maxLevel", 10))
	current_level = state_level
	status = state_status
	is_affordable = affordable
	
	_update_visuals()

func set_selected(is_sel: bool) -> void:
	if highlight_border:
		highlight_border.visible = is_sel

func _update_visuals() -> void:
	if not is_inside_tree():
		return
		
	if name_label:
		name_label.text = node_name
	
	if level_label:
		level_label.text = "Lvl %d/%d" % [current_level, max_level]

	# Set status indicators and styles
	_apply_style_status()

func _apply_style_status() -> void:
	if not is_inside_tree():
		return
		
	# Setup badges and colors based on status
	badge_rect.visible = false
	status_label.visible = true
	
	match status:
		"locked":
			modulate = Color(0.4, 0.4, 0.4, 1.0)
			status_label.text = "🔒 Locked"
			status_label.add_theme_color_override("font_color", Color(0.7, 0.2, 0.2))
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(0.2, 0.2, 0.2)))
		"unlocked": # Unlocked but not affordable
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			status_label.text = "● Available"
			status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(0.4, 0.4, 0.4)))
		"ready": # Unlocked and fully affordable
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			status_label.text = "● Ready"
			status_label.add_theme_color_override("font_color", Color(0.1, 0.8, 0.4))
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(0.1, 0.8, 0.4)))
		"researching":
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			status_label.text = "⚡ Resear..."
			status_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
			badge_rect.visible = true
			badge_label.text = "🔬"
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(0.4, 0.6, 1.0)))
		"queued":
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			status_label.text = "● Queued"
			status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.1))
			badge_rect.visible = true
			badge_label.text = "Q"
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(0.8, 0.6, 0.1), true))
		"max":
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			status_label.text = "★ Complete"
			status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			badge_rect.visible = true
			badge_label.text = "MAX"
			if border_overlay:
				border_overlay.add_theme_stylebox_override("panel", _get_border_style(Color(1.0, 0.84, 0.0)))

func _get_border_style(color: Color, dashed: bool = false) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = color
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	return sb

func _on_node_pressed() -> void:
	selected.emit(research_id)

func _on_mouse_entered() -> void:
	if status != "locked":
		scale = Vector2(1.03, 1.03)

func _on_mouse_exited() -> void:
	scale = Vector2(1.0, 1.0)
