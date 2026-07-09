extends PanelContainer

signal action_pressed()

@onready var req_icon: TextureRect = %ReqIcon
@onready var req_name_label: Label = %ReqNameLabel
@onready var current_amount_label: Label = %CurrentAmountLabel
@onready var slash_label: Label = %SlashLabel
@onready var required_amount_label: Label = %RequiredAmountLabel
@onready var missing_amount_label: Label = %MissingAmountLabel
@onready var status_label: Label = %StatusLabel # Elegant unicode status (✔ / ✘) with custom coloring
@onready var action_button: Button = %ActionButton

func _ready() -> void:
	if action_button:
		action_button.pressed.connect(_on_action_button_pressed)

# Setup method to bind dynamic cost/prerequisite data
func setup(req_name: String, icon_path: String, current_amt: String, required_amt: String, missing_amt: String, is_met: bool, button_text: String = "Obtain") -> void:
	if req_name_label:
		req_name_label.text = req_name
		
	if req_icon:
		if icon_path != "" and ResourceLoader.exists(icon_path):
			req_icon.texture = load(icon_path)
			req_icon.visible = true
		else:
			req_icon.visible = false
			
	if current_amount_label:
		current_amount_label.text = current_amt
		
	if required_amount_label:
		required_amount_label.text = required_amt
		
	if slash_label:
		slash_label.visible = required_amt != ""
		
	if missing_amount_label:
		if missing_amt != "" and not is_met:
			missing_amount_label.text = "Need " + missing_amt + " More"
			missing_amount_label.visible = true
			missing_amount_label.add_theme_color_override("font_color", Color(0.93, 0.27, 0.27)) # Red missing text
		else:
			missing_amount_label.visible = false
			
	if status_label:
		if is_met:
			status_label.text = "✔"
			status_label.add_theme_color_override("font_color", Color(0.18, 0.8, 0.44)) # Emerald green check
		else:
			status_label.text = "✖"
			status_label.add_theme_color_override("font_color", Color(0.93, 0.27, 0.27)) # Royal ruby cross
			
	if action_button:
		if button_text != "" and not is_met:
			action_button.text = button_text
			action_button.visible = true
		else:
			action_button.visible = false

	# Apply styling tweaks depending on meeting requirements
	if is_met:
		# Muted, completed look
		modulate = Color(0.75, 0.82, 0.9, 0.8)
	else:
		# Alerting attention look
		modulate = Color(1, 1, 1, 1)

func _on_action_button_pressed() -> void:
	action_pressed.emit()
