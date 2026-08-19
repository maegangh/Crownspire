extends PanelContainer

## Reusable Crownspire storefront product card.
## Live purchases stay on ShopScreen → CommerceAuthority. This node is display + Buy emit only.

const STATE_READY := "READY"
const STATE_LOADING := "LOADING"
const STATE_PURCHASING := "PURCHASING"
const STATE_PENDING := "PENDING"
const STATE_SUCCESS := "SUCCESS"
const STATE_FAILED := "FAILED"
const STATE_UNAVAILABLE := "UNAVAILABLE"

const COL_INK := Color(0.95, 0.90, 0.80, 1.0)
const COL_MUTED := Color(0.74, 0.66, 0.58, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.34, 1.0)
const COL_GEM := Color(0.72, 0.48, 0.92, 1.0)
const COL_CARD := Color(0.09, 0.06, 0.14, 0.96)
const COL_BORDER := Color(0.62, 0.48, 0.22, 0.95)
const COL_PURPLE := Color(0.32, 0.16, 0.48, 1.0)

signal buy_pressed(product_id: String)

var product_id: String = ""
var purchasable: bool = false
var card_state: String = STATE_LOADING

var _icon: TextureRect = null
var _amount_label: Label = null
var _price_label: Label = null
var _badge_label: Label = null
var _bonus_label: Label = null
var _state_label: Label = null
var _buy_button: Button = null


func configure(config: Dictionary) -> void:
	product_id = str(config.get("product_id", "")).strip_edges()
	purchasable = bool(config.get("purchasable", false))
	_ensure_built()
	name = str(config.get("node_name", "ShopProductCard"))
	_amount_label.text = str(config.get("title", "Diamonds"))
	_set_optional_label(_badge_label, str(config.get("value_badge", "")).strip_edges())
	_set_optional_label(_bonus_label, str(config.get("bonus_label", "")).strip_edges())
	_load_icon(str(config.get("icon_path", "")).strip_edges())
	if _buy_button != null:
		_buy_button.name = str(config.get("buy_button_name", "BuyButton"))
		_buy_button.visible = purchasable
		if not _buy_button.pressed.is_connected(_on_buy_pressed):
			_buy_button.pressed.connect(_on_buy_pressed)
	if _price_label != null:
		_price_label.name = str(config.get("price_label_name", "PriceLabel"))
	set_price(str(config.get("price_text", "")))
	set_card_state(str(config.get("state", STATE_LOADING)))


func set_price(text: String) -> void:
	if _price_label == null:
		return
	var shown: String = text.strip_edges()
	_price_label.text = shown if not shown.is_empty() else "Loading price…"


func get_price_text() -> String:
	if _price_label == null:
		return ""
	return _price_label.text


func set_card_state(state: String) -> void:
	card_state = state.strip_edges().to_upper()
	if card_state.is_empty():
		card_state = STATE_LOADING
	_apply_state_visuals()


func set_buy_enabled(enabled: bool) -> void:
	if _buy_button == null:
		return
	_buy_button.disabled = (not enabled) or (not purchasable) or card_state == STATE_UNAVAILABLE or card_state == STATE_LOADING or card_state == STATE_PURCHASING or card_state == STATE_PENDING


func set_buy_text(text: String) -> void:
	if _buy_button == null:
		return
	var shown: String = text.strip_edges()
	_buy_button.text = shown if not shown.is_empty() else "Buy"


func set_buy_visible(show: bool) -> void:
	if _buy_button == null:
		return
	_buy_button.visible = show and purchasable


func set_helper_text(text: String) -> void:
	if _state_label == null:
		return
	var shown: String = text.strip_edges()
	_state_label.text = shown
	_state_label.visible = not shown.is_empty()


func get_buy_button() -> Button:
	return _buy_button


func _ensure_built() -> void:
	if _amount_label != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 268)
	add_theme_stylebox_override("panel", _style(COL_CARD, COL_BORDER, 14, 2))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 12)
	_badge_label.add_theme_color_override("font_color", COL_GEM)
	col.add_child(_badge_label)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(96, 96)
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_icon)

	_amount_label = Label.new()
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_amount_label.add_theme_font_size_override("font_size", 20)
	_amount_label.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(_amount_label)

	_bonus_label = Label.new()
	_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bonus_label.add_theme_font_size_override("font_size", 13)
	_bonus_label.add_theme_color_override("font_color", COL_GEM)
	col.add_child(_bonus_label)

	_price_label = Label.new()
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_price_label.add_theme_font_size_override("font_size", 16)
	_price_label.add_theme_color_override("font_color", COL_INK)
	col.add_child(_price_label)

	_state_label = Label.new()
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_label.add_theme_font_size_override("font_size", 13)
	_state_label.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(_state_label)

	_buy_button = Button.new()
	_buy_button.text = "Buy"
	_buy_button.custom_minimum_size = Vector2(0, 48)
	_buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_button.add_theme_font_size_override("font_size", 18)
	_buy_button.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0))
	_buy_button.add_theme_stylebox_override("normal", _style(COL_GOLD, COL_PURPLE, 10, 1))
	_buy_button.add_theme_stylebox_override("hover", _style(Color(0.96, 0.82, 0.42, 1.0), COL_PURPLE, 10, 1))
	_buy_button.add_theme_stylebox_override("disabled", _style(Color(0.28, 0.24, 0.22, 1.0), Color(0.35, 0.30, 0.22, 1.0), 10, 1))
	col.add_child(_buy_button)


func _on_buy_pressed() -> void:
	if not purchasable or _buy_button == null or _buy_button.disabled:
		return
	buy_pressed.emit(product_id)


func _load_icon(path: String) -> void:
	if _icon == null:
		return
	if path.is_empty() or not ResourceLoader.exists(path):
		_icon.visible = false
		return
	var tex: Texture2D = load(path) as Texture2D
	_icon.texture = tex
	_icon.visible = tex != null


func _set_optional_label(label: Label, text: String) -> void:
	if label == null:
		return
	label.text = text
	label.visible = not text.is_empty()


func _apply_state_visuals() -> void:
	var copy := ""
	match card_state:
		STATE_LOADING:
			copy = "Loading store…"
		STATE_READY:
			copy = ""
		STATE_PURCHASING:
			copy = "Purchase in progress…"
		STATE_PENDING:
			copy = "Payment pending…"
		STATE_SUCCESS:
			copy = "Delivered"
		STATE_FAILED:
			copy = "Purchase failed"
		STATE_UNAVAILABLE:
			copy = "Unavailable"
		_:
			copy = ""
	if _state_label != null:
		_state_label.text = copy
		_state_label.visible = not copy.is_empty()
	set_buy_enabled(card_state == STATE_READY or card_state == STATE_FAILED or card_state == STATE_SUCCESS)


func _style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(border_w))
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
