extends MarginContainer

@export var purple_button_texture: Texture2D
@export var green_button_texture: Texture2D
@export var check_texture: Texture2D

@onready var requirement_name: Label = find_child("RequirementName", true, false)
@onready var current_amount: Label = find_child("CurrentAmount", true, false)
@onready var slash: Label = find_child("Slash", true, false)
@onready var required_amount: Label = find_child("RequiredAmount", true, false)
@onready var status_icon: TextureRect = find_child("StatusIcon", true, false)
@onready var action_button: TextureButton = find_child("ActionButton", true, false)
@onready var button_label: Label = find_child("ButtonLabel", true, false)

func setup(data: Dictionary) -> void:
	requirement_name.text = data.get("name", "")
	current_amount.text = str(data.get("current", ""))
	slash.text = "/"
	required_amount.text = str(data.get("required", ""))

	var met: bool = data.get("met", false)

	status_icon.visible = met
	action_button.visible = not met

	if met:
		if check_texture:
			status_icon.texture = check_texture
		return

	var action: String = data.get("action", "Go")
	button_label.text = action

	if action == "Obtain":
		action_button.texture_normal = green_button_texture
	else:
		action_button.texture_normal = purple_button_texture
