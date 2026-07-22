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
var selected_stamina: int = 10

var _error_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if has_node("CardRoot/AttackButton"):
		$CardRoot/AttackButton.pressed.connect(_on_attack_pressed)
	else:
		push_error("WildlingPanel missing CardRoot/AttackButton")

	_ensure_error_label()


func _ensure_error_label() -> void:
	if _error_label != null and is_instance_valid(_error_label):
		return
	_error_label = Label.new()
	_error_label.name = "AttackErrorLabel"
	_error_label.visible = false
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_error_label.add_theme_font_size_override("font_size", 16)
	_error_label.position = Vector2(40, 620)
	_error_label.size = Vector2(340, 80)
	$CardRoot.add_child(_error_label)


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
	if stamina == -1:
		stamina = get_stamina_for_level(level)
	selected_stamina = stamina

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 999
	position = Vector2(80, 220)
	size = Vector2(560, 760)

	$CardRoot/Background.texture = card_texture
	$CardRoot/Background.visible = true
	$CardRoot/LevelNumberLabel.text = str(level)
	$CardRoot/PowerNumberLabel.text = str(power)
	$CardRoot/StaminaCostLabel.text = str(stamina)
	_hide_error()
	show_drops(level)


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
		_show_error("March Setup screen missing.")
		# Reopen panel so the player is not stuck.
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
	_ensure_error_label()
	_error_label.text = message
	_error_label.visible = true


func _hide_error() -> void:
	if _error_label != null:
		_error_label.visible = false
		_error_label.text = ""


func get_stamina_for_level(level: int) -> int:
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
	for child in $CardRoot/PossibleDrops/DropRow.get_children():
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
		drop_icon.custom_minimum_size = Vector2(60, 60)
		drop_icon.size = Vector2(140, 140)
		drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$CardRoot/PossibleDrops/DropRow.add_child(drop_icon)


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_error()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rect := Rect2(global_position, size)
		if not rect.has_point(get_global_mouse_position()):
			close_panel()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
