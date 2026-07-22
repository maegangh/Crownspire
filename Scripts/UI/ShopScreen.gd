extends Control

## Temporary Shop placeholder until the real shop ships.
## Close returns to city/world via GameHUD UIManager.


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var dim: ColorRect = ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_bottom = -190.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window: PanelContainer = PanelContainer.new()
	window.name = "ShopWindow"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.custom_minimum_size = Vector2(560, 420)
	window.offset_left = -280
	window.offset_top = -210
	window.offset_right = 280
	window.offset_bottom = 210
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(window)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	window.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)

	var title: Label = Label.new()
	title.text = "SHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	header.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(64, 48)
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	var body: Label = Label.new()
	body.text = "Shop coming soon."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 22)
	root.add_child(body)

	var close_main: Button = Button.new()
	close_main.text = "Close"
	close_main.custom_minimum_size = Vector2(0, 56)
	close_main.pressed.connect(_close)
	root.add_child(close_main)


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()
