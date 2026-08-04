extends Control

## Wildling information card — Attack opens March Setup.


@export var wheat_icon: Texture2D
@export var wood_icon: Texture2D
@export var stone_icon: Texture2D
@export var iron_icon: Texture2D
@export var diamond_icon: Texture2D
@export var hero_xp_icon: Texture2D

var selected_wildling: Node2D = null
var selected_species: String = "wolf"
var selected_level: int = 1
var selected_power: int = 100
var selected_card: Texture2D = null
var selected_creature: Texture2D = null
var selected_stamina: int = 10

const CREATURE_ART_BY_SPECIES := {
	"wolf": "res://assets/Wildlings/wildling_wolf.png",
	"bear": "res://assets/Wildlings/wildling_bear.png",
	"boar": "res://assets/Wildlings/wildling_boar.png",
	"spider": "res://assets/Wildlings/wildling_spider.png",
	"troll": "res://assets/Wildlings/wildling_troll.png",
	"dragon": "res://assets/Wildlings/wildling_dragon.png",
}

@onready var _card_root: PanelContainer = $CardRoot
@onready var _portrait: TextureRect = $CardRoot/CardMargin/CardColumn/Background
@onready var _name_label: Label = $CardRoot/CardMargin/CardColumn/NameLabel
@onready var _level_label: Label = $CardRoot/CardMargin/CardColumn/LevelLabel
@onready var _power_label: Label = $CardRoot/CardMargin/CardColumn/PowerNumberLabel
@onready var _stamina_label: Label = $CardRoot/CardMargin/CardColumn/StaminaRow/StaminaCostLabel
@onready var _drops_row: HBoxContainer = $CardRoot/CardMargin/CardColumn/PossibleDrops
@onready var _attack_button: Button = $CardRoot/CardMargin/CardColumn/AttackButton
@onready var _close_button: Button = $CardRoot/CardMargin/CardColumn/HeaderRow/CloseButton
@onready var _error_label: Label = $CardRoot/CardMargin/CardColumn/AttackErrorLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_nodes()
	_style_card()

	if _attack_button:
		_attack_button.pressed.connect(_on_attack_pressed)
	else:
		push_error("WildlingPanel missing AttackButton")

	if _close_button:
		_close_button.pressed.connect(_on_close_pressed)

	if _portrait:
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.custom_minimum_size = Vector2(0, 260)


func _bind_nodes() -> void:
	if _card_root == null:
		_card_root = get_node_or_null("CardRoot") as PanelContainer
	if _portrait == null:
		_portrait = get_node_or_null("CardRoot/CardMargin/CardColumn/Background") as TextureRect
	if _name_label == null:
		_name_label = get_node_or_null("CardRoot/CardMargin/CardColumn/NameLabel") as Label
	if _level_label == null:
		_level_label = get_node_or_null("CardRoot/CardMargin/CardColumn/LevelLabel") as Label
	if _power_label == null:
		_power_label = get_node_or_null("CardRoot/CardMargin/CardColumn/PowerNumberLabel") as Label
	if _stamina_label == null:
		_stamina_label = get_node_or_null("CardRoot/CardMargin/CardColumn/StaminaRow/StaminaCostLabel") as Label
	if _drops_row == null:
		_drops_row = get_node_or_null("CardRoot/CardMargin/CardColumn/PossibleDrops") as HBoxContainer
	if _attack_button == null:
		_attack_button = get_node_or_null("CardRoot/CardMargin/CardColumn/AttackButton") as Button
	if _close_button == null:
		_close_button = get_node_or_null("CardRoot/CardMargin/CardColumn/HeaderRow/CloseButton") as Button
	if _error_label == null:
		_error_label = get_node_or_null("CardRoot/CardMargin/CardColumn/AttackErrorLabel") as Label


func _style_card() -> void:
	if _card_root == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.72, 0.58, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	_card_root.add_theme_stylebox_override("panel", style)

	if _name_label:
		_name_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	if _level_label:
		_level_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.58, 1.0))
	if _power_label:
		_power_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35, 1.0))
	if _stamina_label:
		_stamina_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	if _attack_button:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.72, 0.28, 0.18, 1.0)
		fill.border_color = Color(0.95, 0.72, 0.28, 1.0)
		fill.set_border_width_all(2)
		fill.set_corner_radius_all(12)
		_attack_button.add_theme_stylebox_override("normal", fill)
		_attack_button.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88, 1.0))
	if _close_button:
		var close_style := StyleBoxFlat.new()
		close_style.bg_color = Color(0.16, 0.14, 0.20, 1.0)
		close_style.border_color = Color(0.70, 0.58, 0.30, 0.9)
		close_style.set_border_width_all(2)
		close_style.set_corner_radius_all(10)
		_close_button.add_theme_stylebox_override("normal", close_style)
		_close_button.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80, 1.0))


func open_panel(
	card_texture: Texture2D,
	level: int,
	power: int,
	wildling_node: Node2D = null,
	species: String = "wolf",
	stamina: int = -1
) -> void:
	selected_wildling = wildling_node
	selected_species = species
	selected_level = level
	selected_power = power
	selected_card = card_texture
	selected_creature = _resolve_creature_texture(species, wildling_node)
	if stamina == -1:
		stamina = get_stamina_for_level(level)
	selected_stamina = stamina

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 999
	position = Vector2(80, 160)
	size = Vector2(440, 720)
	if _card_root:
		_card_root.position = Vector2.ZERO
		_card_root.size = Vector2(420, 680)

	if _portrait:
		# Never show the baked full card UI art — creature/portrait only.
		_portrait.texture = selected_creature
		_portrait.visible = selected_creature != null
	if _name_label:
		_name_label.text = _species_display_name(species)
	if _level_label:
		_level_label.text = "Lv. %d" % level
	if _power_label:
		_power_label.text = _format_number(power)
	if _stamina_label:
		_stamina_label.text = str(stamina)
	_hide_error()
	show_drops(level)


func _resolve_creature_texture(species: String, wildling_node: Node2D) -> Texture2D:
	# Prefer the live world-map sprite texture (already creature-only art).
	if wildling_node != null and is_instance_valid(wildling_node):
		var sprite: Sprite2D = wildling_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null and sprite.texture != null:
			return sprite.texture

	var key: String = species.strip_edges().to_lower()
	if CREATURE_ART_BY_SPECIES.has(key):
		var path: String = str(CREATURE_ART_BY_SPECIES[key])
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is Texture2D:
				return loaded as Texture2D

	push_warning("WildlingPanel: no creature art for species '%s'." % species)
	return null


func reopen_last() -> void:
	if selected_wildling == null or not is_instance_valid(selected_wildling):
		return
	open_panel(
		selected_card,
		selected_level,
		selected_power,
		selected_wildling,
		selected_species,
		selected_stamina
	)


func _on_close_pressed() -> void:
	close_panel()


func _on_attack_pressed() -> void:
	_hide_error()

	if selected_wildling == null or not is_instance_valid(selected_wildling):
		_show_error("No Wildling selected.")
		return
	if not selected_wildling.visible:
		_show_error("That Wildling is no longer available.")
		return
	if not has_node("/root/MarchState"):
		_show_error("March system unavailable.")
		return

	var target: Dictionary = MarchState.build_wildling_target(
		selected_wildling,
		selected_species,
		selected_level,
		selected_power
	)
	if target.is_empty():
		_show_error("Could not lock Wildling target.")
		return

	var gate: Dictionary = MarchState.can_start_wildling_march()
	if not gate.get("ok", false):
		_show_error(str(gate.get("error", "Cannot start march.")))
		return

	close_panel()

	var setup: Node = _find_march_setup()
	if setup == null or not setup.has_method("open_for_target"):
		reopen_last()
		_show_error("March Setup screen missing.")
		return

	setup.open_for_target(target)


func _find_march_setup() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var setup: Node = world.get_node_or_null("GameHUD/ScreenRoot/MarchSetupScreen")
	if setup != null:
		return setup
	return get_tree().root.get_node_or_null("GameHUD/ScreenRoot/MarchSetupScreen")


func _show_error(message: String) -> void:
	if _error_label == null:
		return
	_error_label.text = message
	_error_label.visible = true


func _hide_error() -> void:
	if _error_label != null:
		_error_label.visible = false
		_error_label.text = ""


func get_stamina_for_level(level: int) -> int:
	# Display-only energy/stamina cost for attacking this Wildling tier.
	if level <= 5:
		return 5
	elif level <= 10:
		return 8
	elif level <= 15:
		return 10
	elif level <= 20:
		return 12
	elif level <= 25:
		return 15
	return 20


func show_drops(level: int) -> void:
	if _drops_row == null:
		return
	for child in _drops_row.get_children():
		child.queue_free()

	var drops: Array[Texture2D] = []
	if level <= 5:
		drops = [wheat_icon, wood_icon, stone_icon, iron_icon]
	elif level <= 10:
		drops = [wheat_icon, wood_icon, stone_icon, iron_icon, hero_xp_icon]
	elif level <= 15:
		drops = [wheat_icon, wood_icon, stone_icon, iron_icon, hero_xp_icon, diamond_icon]
	elif level <= 20:
		drops = [stone_icon, iron_icon, hero_xp_icon, diamond_icon]
	elif level <= 25:
		drops = [iron_icon, hero_xp_icon, diamond_icon]
	else:
		drops = [hero_xp_icon, diamond_icon]

	for icon in drops:
		if icon == null:
			continue
		var drop_icon := TextureRect.new()
		drop_icon.texture = icon
		drop_icon.custom_minimum_size = Vector2(56, 56)
		drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drops_row.add_child(drop_icon)


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_error()


func _species_display_name(species: String) -> String:
	var cleaned: String = species.strip_edges()
	if cleaned.is_empty():
		return "Wildling"
	return "Wildling %s" % cleaned.capitalize()


func _format_number(value: int) -> String:
	var text: String = str(value)
	if text.length() <= 3:
		return text
	var parts: PackedStringArray = []
	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	if not text.is_empty():
		parts.insert(0, text)
	return ",".join(parts)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rect := Rect2(global_position, size if size.x > 1.0 else Vector2(440, 720))
		if _card_root:
			rect = Rect2(_card_root.global_position, _card_root.size)
		if not rect.has_point(get_global_mouse_position()):
			close_panel()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
