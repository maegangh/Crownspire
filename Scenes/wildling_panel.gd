extends Control

@export var wheat_icon: Texture2D
@export var wood_icon: Texture2D
@export var stone_icon: Texture2D
@export var iron_icon: Texture2D
@export var diamond_icon: Texture2D
@export var hero_xp_icon: Texture2D

var selected_wildling: Node2D = null

func _ready():
	visible = false
	$AttackButton.pressed.connect(_on_attack_pressed)

func open_panel(card_texture: Texture2D, level: int, power: int, wildling_node: Node2D = null, stamina: int = -1):
	print("OPEN PANEL CALLED")

	selected_wildling = wildling_node

	visible = true
	position = Vector2(250, 50)

	$CardImage.texture = card_texture
	$LevelNumberLabel.text = str(level)
	$PowerNumberLabel.text = str(power)

	if stamina == -1:
		stamina = get_stamina_for_level(level)

	$StaminaCostLabel.text = str(stamina)
	show_drops(level)

func _on_attack_pressed():
	print("ATTACK clicked")

	var world = get_tree().current_scene
	var castle = world.get_node_or_null("MainCastle")
	var target = selected_wildling
	var march = world.get_node_or_null("MarchIcon") as AnimatedSprite2D

	if castle == null:
		print("ERROR: MainCastle not found")
		return
	if target == null:
		print("ERROR: No selected wildling target")
		return
	if march == null:
		print("ERROR: MarchIcon not found or not AnimatedSprite2D")
		return

	visible = false

	var battle_pos = target.global_position + Vector2(80, 20)
	var attack_pos = target.global_position + Vector2(25, 10)

	march.global_position = castle.global_position
	march.visible = true
	march.z_index = 100
	march.rotation_degrees = 0
	march.flip_h = target.global_position.x < castle.global_position.x
	march.play("walk")

	var out_tween = create_tween()
	out_tween.tween_property(march, "global_position", battle_pos, 5.0)
	await out_tween.finished

	print("Battle won")

	var original_march_pos = march.global_position

	var attack_tween = create_tween()
	attack_tween.tween_property(march, "global_position", attack_pos, 0.18)
	attack_tween.tween_property(march, "global_position", original_march_pos, 0.18)
	await attack_tween.finished

	var original_target_pos = target.global_position

	var hit_tween = create_tween()
	hit_tween.tween_property(target, "global_position", original_target_pos + Vector2(12, 0), 0.05)
	hit_tween.tween_property(target, "global_position", original_target_pos + Vector2(-12, 0), 0.05)
	hit_tween.tween_property(target, "global_position", original_target_pos, 0.05)
	await hit_tween.finished

	target.visible = false

	var area = target.get_node_or_null("Area2D")
	if area:
		area.input_pickable = false

	respawn_wildling_later(target, area)

	await get_tree().create_timer(0.4).timeout

	march.flip_h = castle.global_position.x < target.global_position.x
	march.play("walk")

	var return_tween = create_tween()
	return_tween.tween_property(march, "global_position", castle.global_position, 5.0)
	await return_tween.finished

	march.stop()
	march.visible = false
	print("March returned")

func respawn_wildling_later(target: Node2D, area: Area2D):
	await get_tree().create_timer(10.0).timeout

	target.visible = true

	if area:
		area.input_pickable = true

	print("Wildling respawned")

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
	else:
		return 20

func show_drops(level: int):
	for child in $PossibleDrops/DropRow.get_children():
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
		drop_icon.custom_minimum_size = Vector2(54, 54)
		drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$PossibleDrops/DropRow.add_child(drop_icon)

func close_panel():
	visible = false
