extends Button

signal item_selected(item_id: String)

@onready var icon_texture: TextureRect = $Icon
@onready var quantity_label: Label = $QuantityLabel
@onready var new_badge: Label = $NewBadge
@onready var selected_frame: TextureRect = $SelectedFrame

var item_id: String = ""


func setup(new_item_id: String, amount: int, item_icon: Texture2D = null) -> void:
	item_id = new_item_id
	quantity_label.text = "x" + str(amount)
	icon_texture.texture = item_icon
	new_badge.visible = false
	selected_frame.visible = false


func set_selected(is_selected: bool) -> void:
	selected_frame.visible = is_selected


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	item_selected.emit(item_id)
