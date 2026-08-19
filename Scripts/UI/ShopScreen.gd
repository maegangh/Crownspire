extends Control

## Crownspire multi-page Shop. Diamonds is the live beta tab.
## Buy uses AndroidPlayBillingCoordinator / CommerceAuthority. Never grants locally.
## DEBUG IAP TEST harness remains debug-only and must not be the release store.

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const MobileScrollUtil := preload("res://Scripts/UI/MobileScroll.gd")
const MobileSafeAreaUtil := preload("res://Scripts/UI/MobileSafeArea.gd")
const ProductCardScript := preload("res://Scripts/UI/ShopProductCard.gd")

const DIAMOND_ART := "res://assets/Buildings/Diamonds/Diamond.png"
const PRICE_LOADING := "Loading price…"
const PRICE_UNAVAILABLE := "Price unavailable"
const STATUS_IDLE := "Ready to buy."
const STATUS_LOADING := "Loading store…"
const PAY_MODE_MONEY := "money"
const PAY_MODE_VOUCHERS := "vouchers"

const COL_INK := Color(0.95, 0.90, 0.80, 1.0)
const COL_MUTED := Color(0.74, 0.66, 0.58, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.34, 1.0)
const COL_GEM := Color(0.72, 0.48, 0.92, 1.0)
const COL_PANEL := Color(0.07, 0.04, 0.11, 0.97)
const COL_BORDER := Color(0.62, 0.48, 0.22, 0.95)
const COL_PURPLE := Color(0.28, 0.14, 0.42, 1.0)
const COL_TAB := Color(0.12, 0.07, 0.18, 1.0)

const TABS: Array[Dictionary] = [
	{"id": "diamonds", "label": "Diamonds"},
	{"id": "deals", "label": "Deals"},
	{"id": "growth", "label": "Growth"},
	{"id": "passes", "label": "Passes"},
	{"id": "offers", "label": "Special Offers"},
]

const HUD_TOP_FALLBACK := 168.0
const HUD_BOTTOM_FALLBACK := 188.0

var _status: Label = null
var _window: PanelContainer = null
var _dim: ColorRect = null
var _pages: Dictionary = {} ## tab_id -> Control
var _tab_buttons: Dictionary = {} ## tab_id -> Button
var _product_cards: Dictionary = {} ## product_id -> ShopProductCard
var _buy_buttons: Dictionary = {} ## product_id -> Button
var _price_labels: Dictionary = {} ## product_id -> Label
var _google_details_by_id: Dictionary = {} ## product_id -> Dictionary
var _active_tab: String = "diamonds"
var _purchase_busy: bool = false
var _billing_bound: bool = false
var _store_query_pending: bool = false
var _beta_panel: Control = null
var _beta_balance_label: Label = null
var _beta_redeem_input: LineEdit = null
var _beta_redeem_status: Label = null
var _protect_overlay: Control = null
var _wallet_signals_bound: bool = false
var _shop_wallet_refresh_gen: int = 0
var _pay_mode: String = PAY_MODE_MONEY
var _pay_money_btn: Button = null
var _pay_voucher_btn: Button = null
var _voucher_balance_label: Label = null
var _last_purchase_path: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_safe_area()
	_select_tab("diamonds")
	_set_pay_mode(PAY_MODE_MONEY)
	_bind_billing_signals()
	_bind_wallet_snapshot_signals()
	_refresh_product_presentation()
	_refresh_beta_voucher_ui()
	_query_live_products()
	_refresh_wallet_for_shop()


func on_close() -> void:
	_shop_wallet_refresh_gen += 1
	_unbind_wallet_snapshot_signals()
	_hide_protect_account_modal()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_release_product_ids() -> PackedStringArray:
	return Commerce.get_live_store_google_product_ids()


func get_active_tab() -> String:
	return _active_tab


func get_payment_mode() -> String:
	return _pay_mode


func set_payment_mode(mode: String) -> void:
	_set_pay_mode(mode)


func get_last_purchase_path_for_test() -> String:
	return _last_purchase_path


func select_tab(tab_id: String) -> void:
	_select_tab(tab_id)


func request_back() -> bool:
	if _purchase_busy:
		if _is_voucher_mode():
			_set_status("Please wait until this voucher purchase finishes.")
		else:
			_set_status("Please wait until Google Play finishes this purchase.")
		return true
	return false


func is_purchase_busy() -> bool:
	return _purchase_busy


func count_live_buy_buttons_in_active_page() -> int:
	var page: Control = _pages.get(_active_tab, null)
	if page == null:
		return 0
	return _count_named_buy_buttons(page)


func _count_named_buy_buttons(n: Node) -> int:
	var count: int = 0
	if n is Button:
		var btn := n as Button
		if str(btn.name).begins_with("BuyButton_") and btn.visible:
			count += 1
	for child: Node in n.get_children():
		count += _count_named_buy_buttons(child)
	return count


func _set_hud_blocking(busy: bool) -> void:
	var stack: Node = get_node_or_null("/root/UiLayerStack")
	if stack != null and stack.has_method("set_layer_blocking"):
		stack.call("set_layer_blocking", "hud_screen", busy)


func set_purchase_in_flight_for_test(busy: bool) -> void:
	_purchase_busy = busy
	_set_hud_blocking(busy)
	_set_buy_enabled(not busy)
	if busy:
		_set_card_states(ProductCardScript.STATE_PURCHASING)
	else:
		_refresh_product_presentation()


func apply_google_product_details(rows: Array) -> void:
	_ingest_product_detail_rows(rows)
	_refresh_product_presentation()


func _node_suffix(product_id: String) -> String:
	return product_id.replace(".", "_")


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	_buy_buttons.clear()
	_price_labels.clear()
	_product_cards.clear()
	_pages.clear()
	_tab_buttons.clear()
	_pay_money_btn = null
	_pay_voucher_btn = null
	_voucher_balance_label = null
	_pay_mode = PAY_MODE_MONEY
	_last_purchase_path = ""

	_dim = ColorRect.new()
	_dim.name = "DimBackground"
	_dim.color = Color(0.02, 0.01, 0.04, 0.82)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "ShopWindow"
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	_window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_tab_bar())
	root.add_child(_build_payment_mode_bar())

	_status = Label.new()
	_status.name = "ShopStatus"
	_status.text = STATUS_IDLE
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_status)

	var pages := Control.new()
	pages.name = "ShopPages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(pages)

	_pages["diamonds"] = _build_diamonds_page()
	_pages["deals"] = _build_coming_soon_page(
		"deals",
		"Royal Deals",
		"Limited-time Crownspire bundles will appear in this hall. Nothing is for sale here during beta."
	)
	_pages["growth"] = _build_coming_soon_page(
		"growth",
		"Growth",
		"Resource, speedup, and city-growth packs are being prepared for a later Crownspire release."
	)
	_pages["passes"] = _build_coming_soon_page(
		"passes",
		"Passes",
		"Season and Royal Pass tracks will open in this hall. No pass is available to buy yet."
	)
	_pages["offers"] = _build_coming_soon_page(
		"offers",
		"Special Offers",
		"Exclusive Crownspire offers will be unveiled here. There are no active promotions right now."
	)
	for tab_id: Variant in _pages.keys():
		var page: Control = _pages[tab_id]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages.add_child(page)

	var close_main := Button.new()
	close_main.name = "ShopCloseButton"
	close_main.text = "Close"
	close_main.custom_minimum_size = Vector2(0, 52)
	close_main.add_theme_font_size_override("font_size", 18)
	close_main.pressed.connect(_close)
	root.add_child(close_main)

	_apply_safe_area()
	_select_tab("diamonds")


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var back := Button.new()
	back.name = "ShopBackButton"
	back.text = "← BACK"
	back.custom_minimum_size = Vector2(110, 44)
	back.pressed.connect(_close)
	header.add_child(back)

	var title := Label.new()
	title.text = "ROYAL SHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)

	var close_x := Button.new()
	close_x.name = "ShopHeaderCloseButton"
	close_x.text = "X"
	close_x.custom_minimum_size = Vector2(64, 44)
	close_x.pressed.connect(_close)
	header.add_child(close_x)
	return header


func _build_tab_bar() -> ScrollContainer:
	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "ShopTabScroll"
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.custom_minimum_size = Vector2(0, 52)
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tabs := HBoxContainer.new()
	tabs.name = "ShopTabBar"
	tabs.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tabs)

	for item: Dictionary in TABS:
		var tab_id: String = str(item.get("id", ""))
		var btn := Button.new()
		btn.name = "ShopTab_%s" % tab_id
		btn.text = str(item.get("label", tab_id))
		btn.custom_minimum_size = Vector2(108, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_select_tab.bind(tab_id))
		tabs.add_child(btn)
		_tab_buttons[tab_id] = btn
	return tab_scroll


func _build_payment_mode_bar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.name = "ShopPaymentModeBar"
	wrap.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrap.add_child(row)

	_pay_money_btn = Button.new()
	_pay_money_btn.name = "ShopPayMode_money"
	_pay_money_btn.text = "Money"
	_pay_money_btn.custom_minimum_size = Vector2(0, 40)
	_pay_money_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pay_money_btn.add_theme_font_size_override("font_size", 14)
	_pay_money_btn.pressed.connect(_set_pay_mode.bind(PAY_MODE_MONEY))
	row.add_child(_pay_money_btn)

	_pay_voucher_btn = Button.new()
	_pay_voucher_btn.name = "ShopPayMode_vouchers"
	_pay_voucher_btn.text = "Vouchers"
	_pay_voucher_btn.custom_minimum_size = Vector2(0, 40)
	_pay_voucher_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pay_voucher_btn.add_theme_font_size_override("font_size", 14)
	_pay_voucher_btn.pressed.connect(_set_pay_mode.bind(PAY_MODE_VOUCHERS))
	row.add_child(_pay_voucher_btn)

	_voucher_balance_label = Label.new()
	_voucher_balance_label.name = "ShopVoucherBalance"
	_voucher_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voucher_balance_label.add_theme_font_size_override("font_size", 14)
	_voucher_balance_label.add_theme_color_override("font_color", COL_GOLD)
	_voucher_balance_label.visible = false
	wrap.add_child(_voucher_balance_label)
	_refresh_pay_mode_buttons()
	return wrap


func _set_pay_mode(mode: String) -> void:
	if _purchase_busy:
		return
	var next: String = mode.strip_edges().to_lower()
	if next != PAY_MODE_VOUCHERS:
		next = PAY_MODE_MONEY
	_pay_mode = next
	_refresh_pay_mode_buttons()
	_refresh_product_presentation()
	_refresh_beta_voucher_ui()


func _is_voucher_mode() -> bool:
	return _pay_mode == PAY_MODE_VOUCHERS


func _refresh_pay_mode_buttons() -> void:
	var voucher: bool = _is_voucher_mode()
	if _pay_money_btn != null:
		_pay_money_btn.disabled = _purchase_busy
		_pay_money_btn.add_theme_stylebox_override("normal", _style(COL_GOLD if not voucher else COL_TAB, COL_GOLD if not voucher else COL_PURPLE, 10, 2 if not voucher else 1))
		_pay_money_btn.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0) if not voucher else COL_INK)
	if _pay_voucher_btn != null:
		_pay_voucher_btn.disabled = _purchase_busy
		_pay_voucher_btn.add_theme_stylebox_override("normal", _style(COL_GOLD if voucher else COL_TAB, COL_GOLD if voucher else COL_PURPLE, 10, 2 if voucher else 1))
		_pay_voucher_btn.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0) if voucher else COL_INK)
	if _voucher_balance_label != null:
		_voucher_balance_label.visible = voucher
		_voucher_balance_label.text = "Vouchers: %s" % str(Commerce.get_voucher_balance())


func _build_diamonds_page() -> Control:
	var page := Control.new()
	page.name = "ShopPage_diamonds"

	var scroll := ScrollContainer.new()
	scroll.name = "DiamondScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MobileScrollUtil.configure(scroll)
	page.add_child(scroll)
	MobileScrollUtil.ensure(page, scroll, "DiamondMobileScroll")

	var body := VBoxContainer.new()
	body.name = "DiamondBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)

	var intro := Label.new()
	intro.text = "Diamonds"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", COL_GOLD)
	body.add_child(intro)

	var blurb := Label.new()
	blurb.text = "Premium currency for Crownspire. Purchases complete through Google Play and are granted only after the server delivers them."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", COL_MUTED)
	body.add_child(blurb)

	var grid := GridContainer.new()
	grid.name = "DiamondGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)

	var rows: Array = Commerce.get_live_store_catalog_rows()
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "ShopEmpty"
		empty.text = "No live store products are available."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", COL_MUTED)
		body.add_child(empty)
	else:
		grid.columns = 2 if rows.size() >= 2 else 1
		for item: Variant in rows:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var card: Control = _make_live_diamond_card(item)
			if card != null:
				grid.add_child(card)

	_build_beta_voucher_panel(body)
	if OS.is_debug_build():
		_build_iap_test_harness(body)
	return page


func _make_live_diamond_card(row: Dictionary) -> Control:
	var product_id: String = str(row.get("iap_product_id", "")).strip_edges()
	if product_id.is_empty():
		product_id = str(row.get("product_id", "")).strip_edges()
	if product_id.is_empty():
		return null
	if not Commerce.is_live_store_google_product(product_id):
		return null

	var suffix: String = _node_suffix(product_id)
	var card: Control = ProductCardScript.new()
	card.configure({
		"product_id": product_id,
		"purchasable": true,
		"node_name": "ReleaseProduct_%s" % suffix,
		"buy_button_name": "BuyButton_%s" % suffix,
		"price_label_name": "PriceLabel_%s" % suffix,
		"title": _live_product_title(row),
		"icon_path": DIAMOND_ART,
		"price_text": PRICE_LOADING,
		"state": ProductCardScript.STATE_LOADING,
		"value_badge": str(row.get("value_badge", "")).strip_edges(),
		"bonus_label": str(row.get("bonus_label", "")).strip_edges(),
	})
	if card.has_signal("buy_pressed") and not card.buy_pressed.is_connected(_on_buy_live_product):
		card.buy_pressed.connect(_on_buy_live_product)
	_product_cards[product_id] = card
	var buy: Button = card.get_buy_button() if card.has_method("get_buy_button") else null
	if buy != null:
		_buy_buttons[product_id] = buy
	var price_label: Label = card.find_child("PriceLabel_%s" % suffix, true, false)
	if price_label != null:
		_price_labels[product_id] = price_label
	return card


func _live_product_title(row: Dictionary) -> String:
	var named: String = str(row.get("name", "")).strip_edges()
	if not named.is_empty():
		return named
	var amount: int = int(row.get("diamond_amount", 0))
	if amount > 0:
		return "%s Diamonds" % str(amount)
	return str(row.get("iap_product_id", "Store product"))


func _build_coming_soon_page(tab_id: String, title: String, body_text: String) -> Control:
	var page := Control.new()
	page.name = "ShopPage_%s" % tab_id

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MobileScrollUtil.configure(scroll)
	page.add_child(scroll)
	MobileScrollUtil.ensure(page, scroll, "ComingSoonScroll_%s" % tab_id)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)

	var panel := PanelContainer.new()
	panel.name = "ComingSoon_%s" % tab_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color(0.10, 0.06, 0.16, 0.96), COL_GOLD, 14, 2))
	col.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 16)
	inner.add_theme_constant_override("margin_right", 16)
	inner.add_theme_constant_override("margin_top", 18)
	inner.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(inner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	inner.add_child(box)

	if ResourceLoader.exists(DIAMOND_ART):
		var icon := TextureRect.new()
		icon.texture = load(DIAMOND_ART) as Texture2D
		icon.custom_minimum_size = Vector2(120, 120)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(icon)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(heading)

	var soon := Label.new()
	soon.name = "ComingSoonLabel_%s" % tab_id
	soon.text = "Coming Soon"
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon.add_theme_font_size_override("font_size", 16)
	soon.add_theme_color_override("font_color", COL_GEM)
	box.add_child(soon)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", COL_INK)
	box.add_child(body)
	return page


func _build_beta_voucher_panel(root: VBoxContainer) -> void:
	_beta_panel = PanelContainer.new()
	_beta_panel.name = "BetaVoucherPanel"
	_beta_panel.visible = false
	_beta_panel.add_theme_stylebox_override("panel", _style(Color(0.10, 0.07, 0.16, 0.96), COL_GEM, 12, 2))
	root.add_child(_beta_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_beta_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Redeem Voucher Code"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_GEM)
	col.add_child(title)

	var note := Label.new()
	note.text = "Tester codes only. Zero cash value."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(note)

	_beta_balance_label = Label.new()
	_beta_balance_label.name = "BetaVoucherBalance"
	_beta_balance_label.text = "Vouchers: 0"
	_beta_balance_label.add_theme_font_size_override("font_size", 15)
	_beta_balance_label.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(_beta_balance_label)

	var redeem_row := HBoxContainer.new()
	redeem_row.add_theme_constant_override("separation", 8)
	col.add_child(redeem_row)

	_beta_redeem_input = LineEdit.new()
	_beta_redeem_input.name = "BetaVoucherRedeemInput"
	_beta_redeem_input.placeholder_text = "Enter voucher code"
	_beta_redeem_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_beta_redeem_input.secret = false
	redeem_row.add_child(_beta_redeem_input)

	var redeem_btn := Button.new()
	redeem_btn.name = "BetaVoucherRedeemButton"
	redeem_btn.text = "Redeem"
	redeem_btn.custom_minimum_size = Vector2(110, 44)
	redeem_btn.pressed.connect(_on_redeem_voucher_pressed)
	redeem_row.add_child(redeem_btn)

	_beta_redeem_status = Label.new()
	_beta_redeem_status.name = "BetaVoucherRedeemStatus"
	_beta_redeem_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_beta_redeem_status.add_theme_font_size_override("font_size", 13)
	_beta_redeem_status.add_theme_color_override("font_color", COL_MUTED)
	col.add_child(_beta_redeem_status)
	_refresh_beta_voucher_ui()


func _refresh_beta_voucher_ui() -> void:
	if _beta_panel == null:
		return
	var available: bool = Commerce.is_beta_voucher_available()
	_beta_panel.visible = available
	if _beta_balance_label != null:
		_beta_balance_label.text = "Vouchers: %s" % str(Commerce.get_voucher_balance())
	if _voucher_balance_label != null:
		_voucher_balance_label.text = "Vouchers: %s" % str(Commerce.get_voucher_balance())
		_voucher_balance_label.visible = _is_voucher_mode()
	_refresh_pay_mode_buttons()


func _on_redeem_voucher_pressed() -> void:
	if _beta_redeem_input == null:
		return
	var code: String = _beta_redeem_input.text.strip_edges()
	if code.is_empty():
		_set_redeem_status("Enter a code.")
		return
	_set_redeem_status("Redeeming…")
	var result: Dictionary = await Commerce.redeem_voucher_code(code)
	_refresh_beta_voucher_ui()
	if bool(result.get("ok", false)):
		if bool(result.get("already", false)):
			_set_redeem_status("This account already redeemed that code.")
		else:
			_set_redeem_status("Code accepted. Voucher balance updated.")
		return
	var err: String = str(result.get("error", "redeem_failed"))
	if err == "already_redeemed":
		_set_redeem_status("This account already redeemed that code.")
	elif err == "expired_code":
		_set_redeem_status("That code has expired.")
	elif err == "inactive_code":
		_set_redeem_status("That code is inactive.")
	elif err == "global_cap_reached":
		_set_redeem_status("That code can no longer be redeemed.")
	elif err == "invalid_code":
		_set_redeem_status("That code is not valid.")
	elif err == "beta_voucher_unavailable":
		_set_redeem_status("Beta voucher testing is not available on this account.")
	else:
		_set_redeem_status("Could not redeem that code.")


func _set_redeem_status(text: String) -> void:
	if _beta_redeem_status != null:
		_beta_redeem_status.text = text


func _on_buy_with_vouchers(product_id: String) -> void:
	if _purchase_busy:
		return
	var pid: String = product_id.strip_edges()
	if not Commerce.is_product_voucher_purchasable(pid):
		_set_status("Not available with Vouchers.")
		return
	var cost: int = Commerce.get_server_voucher_cost(pid)
	if Commerce.get_voucher_balance() < cost:
		_set_status("Not enough Vouchers.")
		_refresh_product_presentation()
		return
	_last_purchase_path = "voucher"
	_purchase_busy = true
	_set_hud_blocking(true)
	_set_buy_enabled(false)
	_set_card_state_for(pid, ProductCardScript.STATE_PURCHASING)
	_refresh_beta_voucher_ui()
	_set_status("Submitting voucher purchase to the server…")
	var nonce: String = Commerce.peek_or_create_voucher_purchase_key(pid)
	var result: Dictionary = await Commerce.purchase_with_vouchers(pid, nonce)
	Commerce.clear_voucher_purchase_key(pid)
	_purchase_busy = false
	_set_hud_blocking(false)
	_set_buy_enabled(true)
	if bool(result.get("ok", false)) and Commerce.is_nakama_authenticated():
		await Commerce.refresh_server_wallet()
	_refresh_beta_voucher_ui()
	_refresh_product_presentation()
	if bool(result.get("ok", false)):
		_set_status("Voucher purchase delivered. Diamonds updated from the server.")
		_set_card_state_for(pid, ProductCardScript.STATE_SUCCESS)
	else:
		var err: String = str(result.get("error", "failed"))
		if err == "Insufficient vouchers" or err == "voucher_purchase_in_progress":
			_set_status("Not enough Vouchers." if err == "Insufficient vouchers" else "Voucher purchase already in progress.")
		elif err == "product_not_voucher_purchasable" or err == "voucher_pack_not_voucher_purchasable":
			_set_status("Not available with Vouchers.")
		else:
			_set_status("Voucher purchase failed.")
		_refresh_product_presentation()


func _build_iap_test_harness(root: VBoxContainer) -> void:
	var banner := Label.new()
	banner.text = "IAP TEST — DEBUG ONLY. Queue SKUs are not in the release store."
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(banner)

	var query_btn := Button.new()
	query_btn.name = "DebugQueryButton"
	query_btn.text = "IAP TEST: Query products"
	query_btn.pressed.connect(_on_iap_query)
	root.add_child(query_btn)

	var buy_btn := Button.new()
	buy_btn.name = "DebugBuilderBuyButton"
	buy_btn.text = "IAP TEST: Buy Permanent Builder Queue"
	buy_btn.pressed.connect(_on_iap_buy_builder)
	root.add_child(buy_btn)

	var restore_btn := Button.new()
	restore_btn.name = "DebugRestoreButton"
	restore_btn.text = "IAP TEST: Restore purchases"
	restore_btn.pressed.connect(_on_iap_restore)
	root.add_child(restore_btn)


func _select_tab(tab_id: String) -> void:
	var id: String = tab_id.strip_edges()
	if not _pages.has(id):
		id = "diamonds"
	_active_tab = id
	for key: Variant in _pages.keys():
		var page: Control = _pages[key]
		page.visible = str(key) == id
	for key: Variant in _tab_buttons.keys():
		var btn: Button = _tab_buttons[key]
		var selected: bool = str(key) == id
		btn.add_theme_stylebox_override("normal", _style(COL_GOLD if selected else COL_TAB, COL_GOLD if selected else COL_PURPLE, 10, 2 if selected else 1))
		btn.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04, 1.0) if selected else COL_INK)


func _apply_safe_area() -> void:
	if _dim == null or _window == null:
		return
	var top: float = MobileSafeAreaUtil.max_top(self, HUD_TOP_FALLBACK)
	var bottom: float = MobileSafeAreaUtil.max_bottom(self, HUD_BOTTOM_FALLBACK)
	_dim.offset_top = top
	_dim.offset_bottom = -bottom
	_window.offset_left = 10.0
	_window.offset_top = top
	_window.offset_right = -10.0
	_window.offset_bottom = -bottom


func _bind_billing_signals() -> void:
	if _billing_bound:
		return
	var node: Node = Commerce.ensure_android_billing_node()
	if node == null or not node.has_signal("billing_status"):
		return
	if not node.billing_status.is_connected(_on_billing_status):
		node.billing_status.connect(_on_billing_status)
	_billing_bound = true


func _bind_wallet_snapshot_signals() -> void:
	if _wallet_signals_bound:
		return
	var bus: Object = Commerce.get_signal_bus()
	if bus.has_signal("wallet_snapshot_changed") and not bus.is_connected("wallet_snapshot_changed", _on_wallet_snapshot_changed):
		bus.connect("wallet_snapshot_changed", _on_wallet_snapshot_changed)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("account_state_changed"):
		if not identity.account_state_changed.is_connected(_on_account_state_changed_for_vouchers):
			identity.account_state_changed.connect(_on_account_state_changed_for_vouchers)
	_wallet_signals_bound = true


func _unbind_wallet_snapshot_signals() -> void:
	if not _wallet_signals_bound:
		return
	var bus: Object = Commerce.get_signal_bus()
	if bus.has_signal("wallet_snapshot_changed") and bus.is_connected("wallet_snapshot_changed", _on_wallet_snapshot_changed):
		bus.disconnect("wallet_snapshot_changed", _on_wallet_snapshot_changed)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("account_state_changed"):
		if identity.account_state_changed.is_connected(_on_account_state_changed_for_vouchers):
			identity.account_state_changed.disconnect(_on_account_state_changed_for_vouchers)
	_wallet_signals_bound = false


func _on_wallet_snapshot_changed() -> void:
	if not visible:
		return
	_refresh_beta_voucher_ui()
	_refresh_product_presentation()


func _on_account_state_changed_for_vouchers() -> void:
	if not visible:
		return
	_refresh_beta_voucher_ui()
	_refresh_product_presentation()


func _refresh_wallet_for_shop() -> void:
	_shop_wallet_refresh_gen += 1
	var token: int = _shop_wallet_refresh_gen
	if Commerce.is_nakama_authenticated():
		await Commerce.refresh_server_wallet()
	if token != _shop_wallet_refresh_gen or not visible:
		return
	_refresh_beta_voucher_ui()
	_refresh_product_presentation()


func _query_live_products() -> void:
	if _is_voucher_mode():
		_refresh_product_presentation()
		if Commerce.is_nakama_authenticated():
			Commerce.query_android_products()
		return
	if not Commerce.is_nakama_authenticated():
		_set_status("Sign in to buy Diamonds.")
		_set_unavailable_if_no_price()
		return
	var result: Dictionary = Commerce.query_android_products()
	var st: String = str(result.get("status", ""))
	if st == Commerce.STATUS_BILLING_UNAVAILABLE:
		_set_status("Google Play Billing is available on Android devices.")
		_set_unavailable_if_no_price()
		return
	if st == Commerce.STATUS_UNAUTHENTICATED:
		_set_status("Sign in to buy Diamonds.")
		_set_unavailable_if_no_price()
		return
	if bool(result.get("ok", false)):
		if _any_formatted_price_ready():
			_set_status(STATUS_IDLE)
			_store_query_pending = false
		else:
			_store_query_pending = true
			_set_status(STATUS_LOADING)


func _refresh_product_presentation() -> void:
	if _is_voucher_mode():
		_refresh_voucher_product_cards()
	else:
		_refresh_live_prices()


func _refresh_voucher_product_cards() -> void:
	var balance: int = Commerce.get_voucher_balance()
	for product_id: Variant in _product_cards.keys():
		var pid: String = str(product_id)
		var card: Control = _product_cards[pid]
		var purchasable: bool = Commerce.is_product_voucher_purchasable(pid)
		var cost: int = Commerce.get_server_voucher_cost(pid)
		if card.has_method("set_buy_text"):
			card.set_buy_text("Buy with Vouchers")
		if not purchasable:
			if card.has_method("set_price"):
				card.set_price("Not available with Vouchers")
			if _price_labels.has(pid):
				(_price_labels[pid] as Label).text = "Not available with Vouchers"
			if card.has_method("set_buy_visible"):
				card.set_buy_visible(false)
			if not _purchase_busy and card.has_method("set_card_state"):
				card.set_card_state(ProductCardScript.STATE_UNAVAILABLE)
			if card.has_method("set_helper_text"):
				card.set_helper_text("Not available with Vouchers")
			continue
		var price_text: String = "%s Vouchers" % str(cost)
		if card.has_method("set_price"):
			card.set_price(price_text)
		if _price_labels.has(pid):
			(_price_labels[pid] as Label).text = price_text
		if card.has_method("set_buy_visible"):
			card.set_buy_visible(true)
		var enough: bool = balance >= cost
		if not _purchase_busy and card.has_method("set_card_state"):
			card.set_card_state(ProductCardScript.STATE_READY if enough else ProductCardScript.STATE_UNAVAILABLE)
		if card.has_method("set_helper_text"):
			card.set_helper_text("" if enough else "Not enough Vouchers")
		if card.has_method("set_buy_enabled"):
			card.set_buy_enabled((not _purchase_busy) and enough)
	if _voucher_balance_label != null:
		_voucher_balance_label.text = "Vouchers: %s" % str(balance)
		_voucher_balance_label.visible = true


func _refresh_live_prices() -> void:
	for product_id: Variant in _product_cards.keys():
		var pid: String = str(product_id)
		var details: Dictionary = _details_for_product(pid)
		var formatted: String = Commerce.formatted_price_from_google_details(details)
		var card: Control = _product_cards[pid]
		if card.has_method("set_buy_text"):
			card.set_buy_text("Buy")
		if card.has_method("set_buy_visible"):
			card.set_buy_visible(true)
		if formatted.is_empty():
			if card.has_method("set_price"):
				card.set_price(PRICE_LOADING if _store_query_pending else PRICE_UNAVAILABLE)
			if _price_labels.has(pid):
				(_price_labels[pid] as Label).text = PRICE_LOADING if _store_query_pending else PRICE_UNAVAILABLE
			if not _purchase_busy and card.has_method("set_card_state"):
				card.set_card_state(ProductCardScript.STATE_LOADING if _store_query_pending else ProductCardScript.STATE_UNAVAILABLE)
		else:
			if card.has_method("set_price"):
				card.set_price(formatted)
			if _price_labels.has(pid):
				(_price_labels[pid] as Label).text = formatted
			if not _purchase_busy and card.has_method("set_card_state"):
				card.set_card_state(ProductCardScript.STATE_READY)
			if card.has_method("set_helper_text"):
				card.set_helper_text("")
	if _any_formatted_price_ready():
		_store_query_pending = false
		if not _purchase_busy:
			var cur: String = str(_status.text) if _status != null else ""
			if cur == STATUS_LOADING or cur.find("Loading store") >= 0:
				_set_status(STATUS_IDLE)


func _details_for_product(product_id: String) -> Dictionary:
	if _google_details_by_id.has(product_id) and typeof(_google_details_by_id[product_id]) == TYPE_DICTIONARY:
		return _google_details_by_id[product_id]
	return Commerce.get_google_product_details(product_id)


func _ingest_product_detail_rows(rows: Array) -> void:
	for item: Variant in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var pid: String = str(row.get("product_id", "")).strip_edges()
		if pid.is_empty():
			pid = str(row.get("productId", "")).strip_edges()
		if pid.is_empty():
			continue
		_google_details_by_id[pid] = row


func _any_formatted_price_ready() -> bool:
	for product_id: Variant in _product_cards.keys():
		var formatted: String = Commerce.formatted_price_from_google_details(_details_for_product(str(product_id)))
		if not formatted.is_empty():
			return true
	return false


func _set_unavailable_if_no_price() -> void:
	_store_query_pending = false
	if _any_formatted_price_ready():
		return
	_set_card_states(ProductCardScript.STATE_UNAVAILABLE)
	for product_id: Variant in _product_cards.keys():
		var card: Control = _product_cards[product_id]
		if card.has_method("set_price"):
			card.set_price(PRICE_UNAVAILABLE)


func _set_card_states(state: String) -> void:
	for product_id: Variant in _product_cards.keys():
		var card: Control = _product_cards[product_id]
		if card.has_method("set_card_state"):
			card.set_card_state(state)


func _on_buy_live_product(product_id: String) -> void:
	if _purchase_busy:
		return
	if _is_voucher_mode():
		_on_buy_with_vouchers(product_id)
		return
	if not Commerce.is_live_store_google_product(product_id):
		_set_status("That product is not in the live store.")
		return
	if not _can_start_real_money_purchase():
		_show_protect_account_modal()
		return
	if OS.get_name() == "Android" and not Commerce.is_android_product_ready(product_id):
		_store_query_pending = true
		_set_status(STATUS_LOADING)
		_query_live_products()
		return
	_last_purchase_path = "billing"
	_purchase_busy = true
	_set_hud_blocking(true)
	_set_buy_enabled(false)
	_set_card_state_for(product_id, ProductCardScript.STATE_PURCHASING)
	_set_status("Starting Google Play purchase…")
	var result: Dictionary = Commerce.purchase_android_product(product_id)
	_apply_launch_result(result)


func _set_card_state_for(product_id: String, state: String) -> void:
	if not _product_cards.has(product_id):
		return
	var card: Control = _product_cards[product_id]
	if card.has_method("set_card_state"):
		card.set_card_state(state)


func _apply_launch_result(result: Dictionary) -> void:
	var st: String = str(result.get("status", ""))
	if st == "BILLING_FLOW_LAUNCHED":
		_set_status("Complete the purchase in Google Play…")
		return
	if st == Commerce.STATUS_CANCELED:
		_finish_busy("Purchase canceled.", ProductCardScript.STATE_READY)
		return
	if st == Commerce.STATUS_PENDING:
		_finish_busy("Purchase pending. Diamonds are granted after Google completes payment.", ProductCardScript.STATE_PENDING)
		return
	if st == Commerce.STATUS_UNAUTHENTICATED:
		_finish_busy("Sign in to buy Diamonds.", ProductCardScript.STATE_UNAVAILABLE)
		return
	if st == Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED:
		_finish_busy(tr("ACCOUNT_PROTECT_PURCHASE_TITLE"), ProductCardScript.STATE_READY)
		_show_protect_account_modal()
		return
	if st == Commerce.STATUS_BILLING_UNAVAILABLE:
		_finish_busy("Google Play Billing is available on Android devices.", ProductCardScript.STATE_UNAVAILABLE)
		return
	if st == Commerce.STATUS_INVALID_PRODUCT:
		_finish_busy("This product cannot be purchased.", ProductCardScript.STATE_UNAVAILABLE)
		return
	if st == "ALREADY_OWNED_QUERYING":
		_set_status("Checking existing Google Play purchases…")
		return
	_finish_busy("Could not start purchase (%s)." % st, ProductCardScript.STATE_FAILED)


func _on_billing_status(status: String, detail: Dictionary) -> void:
	if status == "PRODUCT_DETAILS" or status == "CONNECTED":
		var rows: Variant = detail.get("product_details", [])
		if typeof(rows) != TYPE_ARRAY:
			rows = detail.get("productDetails", [])
		if typeof(rows) == TYPE_ARRAY:
			_ingest_product_detail_rows(rows)
		_refresh_product_presentation()
		if status == "CONNECTED" and not _any_formatted_price_ready() and not _is_voucher_mode():
			_store_query_pending = true
			_set_status(STATUS_LOADING)
		return
	if status == Commerce.STATUS_PENDING:
		_finish_busy("Purchase pending. Diamonds are granted after Google completes payment.", ProductCardScript.STATE_PENDING)
		return
	if status == Commerce.STATUS_CANCELED:
		_finish_busy("Purchase canceled.", ProductCardScript.STATE_READY)
		return
	if status == Commerce.STATUS_DELIVERED:
		_finish_busy("Purchase complete. Diamonds updated from the server.", ProductCardScript.STATE_SUCCESS)
		return
	if status == Commerce.STATUS_ALREADY_DELIVERED:
		_finish_busy("This purchase was already delivered.", ProductCardScript.STATE_SUCCESS)
		return
	if status == Commerce.STATUS_SERVER_REJECTED:
		_finish_busy("Google purchase could not be validated. It will retry if still unfinished.", ProductCardScript.STATE_FAILED)
		return
	if status == Commerce.STATUS_VALIDATION_PENDING:
		_set_status("Validating purchase with the server…")
		return
	if status == Commerce.STATUS_FAILED:
		_finish_busy("Purchase failed.", ProductCardScript.STATE_FAILED)
		return


func _finish_busy(message: String, card_state: String = ProductCardScript.STATE_READY) -> void:
	_purchase_busy = false
	_set_hud_blocking(false)
	_set_buy_enabled(true)
	_set_card_states(card_state)
	_set_status(message)
	if card_state == ProductCardScript.STATE_READY:
		_refresh_product_presentation()


func _set_buy_enabled(enabled: bool) -> void:
	for product_id: Variant in _buy_buttons.keys():
		var btn: Button = _buy_buttons[product_id]
		btn.disabled = not enabled
	for product_id: Variant in _product_cards.keys():
		var card: Control = _product_cards[product_id]
		if card.has_method("set_buy_enabled"):
			card.set_buy_enabled(enabled)
	_refresh_pay_mode_buttons()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _on_iap_query() -> void:
	var result: Dictionary = Commerce.query_android_products()
	_set_status("IAP TEST query: %s (granted=false)" % str(result.get("status", "")))


func _on_iap_buy_builder() -> void:
	var result: Dictionary = Commerce.purchase_android_product(Commerce.GOOGLE_PRIMARY_TEST_PRODUCT)
	_set_status(
		"IAP TEST buy: %s granted=%s delivered=%s"
		% [str(result.get("status", "")), str(result.get("granted", false)), str(result.get("delivered", false))]
	)


func _on_iap_restore() -> void:
	var result: Dictionary = Commerce.restore_android_purchases()
	_set_status("IAP TEST restore: %s (granted=false)" % str(result.get("status", "")))


func _close() -> void:
	if _purchase_busy:
		if _is_voucher_mode():
			_set_status("Please wait until this voucher purchase finishes.")
		else:
			_set_status("Please wait until Google Play finishes this purchase.")
		return
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _can_start_real_money_purchase() -> bool:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null or not identity.has_method("can_start_real_money_purchase"):
		return false
	return bool(identity.call("can_start_real_money_purchase"))


func _show_protect_account_modal() -> void:
	if _protect_overlay != null and is_instance_valid(_protect_overlay):
		_protect_overlay.visible = true
		_protect_overlay.move_to_front()
		return
	_protect_overlay = Control.new()
	_protect_overlay.name = "ProtectAccountModal"
	_protect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_protect_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_protect_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 280)
	card.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 14, 2))
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	card.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	var title := Label.new()
	title.name = "ProtectAccountTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = tr("ACCOUNT_PROTECT_PURCHASE_TITLE")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	var body := Label.new()
	body.name = "ProtectAccountBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = tr("ACCOUNT_PROTECT_PURCHASE_BODY")
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", COL_INK)
	col.add_child(body)

	var secure_btn := Button.new()
	secure_btn.name = "ProtectAccountSecureButton"
	secure_btn.text = tr("ACCOUNT_PURCHASE_SECURE_MCS")
	secure_btn.custom_minimum_size = Vector2(0, 48)
	secure_btn.pressed.connect(_on_protect_secure_pressed)
	col.add_child(secure_btn)

	var cancel_btn := Button.new()
	cancel_btn.name = "ProtectAccountCancelButton"
	cancel_btn.text = tr("UI_CANCEL")
	cancel_btn.custom_minimum_size = Vector2(0, 48)
	cancel_btn.pressed.connect(_hide_protect_account_modal)
	col.add_child(cancel_btn)

	_set_status(tr("ACCOUNT_PROTECT_PURCHASE_TITLE"))


func _on_protect_secure_pressed() -> void:
	var panel_script: GDScript = load("res://Scripts/UI/AccountSettingsPanel.gd") as GDScript
	if panel_script == null:
		return
	_hide_protect_account_modal()
	_protect_overlay = Control.new()
	_protect_overlay.name = "ProtectAccountModal"
	_protect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_protect_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.add_child(scroll)
	var panel: Control = panel_script.new() as Control
	panel.name = "ProtectAccountSettingsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	if panel.has_method("show_secure_view"):
		panel.call("show_secure_view")


func _hide_protect_account_modal() -> void:
	if _protect_overlay != null and is_instance_valid(_protect_overlay):
		_protect_overlay.queue_free()
	_protect_overlay = null


func _style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(int(border_w))
	s.border_color = border
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
