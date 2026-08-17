extends Control

## Release Shop: live_store catalog SKUs only (currently diamonds_500).
## Buy uses AndroidPlayBillingCoordinator / CommerceAuthority. Never grants locally.
## DEBUG IAP TEST harness remains debug-only and must not be the release store.

const Commerce := preload("res://Scripts/CommerceAuthority.gd")

const PRICE_UNAVAILABLE := "Price shown at Google Play checkout"
const STATUS_IDLE := "Ready to buy."

var _status: Label = null
var _buy_buttons: Dictionary = {} ## product_id -> Button
var _price_labels: Dictionary = {} ## product_id -> Label
var _purchase_busy: bool = false
var _billing_bound: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bind_billing_signals()
	_refresh_live_prices()
	_query_live_products()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_release_product_ids() -> PackedStringArray:
	return Commerce.get_live_store_google_product_ids()


func _node_suffix(product_id: String) -> String:
	return product_id.replace(".", "_")


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	_buy_buttons.clear()
	_price_labels.clear()

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
	var debug_iap: bool = OS.is_debug_build()
	window.custom_minimum_size = Vector2(560, 640 if debug_iap else 480)
	window.offset_left = -280
	window.offset_top = -320 if debug_iap else -240
	window.offset_right = 280
	window.offset_bottom = 320 if debug_iap else 240
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

	_build_live_store_rows(root)

	_status = Label.new()
	_status.name = "ShopStatus"
	_status.text = STATUS_IDLE
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	root.add_child(_status)

	if debug_iap:
		_build_iap_test_harness(root)

	var close_main: Button = Button.new()
	close_main.text = "Close"
	close_main.custom_minimum_size = Vector2(0, 56)
	close_main.pressed.connect(_close)
	root.add_child(close_main)


func _build_live_store_rows(root: VBoxContainer) -> void:
	var rows: Array = Commerce.get_live_store_catalog_rows()
	if rows.is_empty():
		var empty: Label = Label.new()
		empty.name = "ShopEmpty"
		empty.text = "No live store products are available."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 20)
		root.add_child(empty)
		return

	for item: Variant in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var product_id: String = str(row.get("iap_product_id", "")).strip_edges()
		if product_id.is_empty():
			product_id = str(row.get("product_id", "")).strip_edges()
		if product_id.is_empty():
			continue
		if not Commerce.is_live_store_google_product(product_id):
			continue

		var suffix: String = _node_suffix(product_id)
		var card: VBoxContainer = VBoxContainer.new()
		card.name = "ReleaseProduct_%s" % suffix
		card.add_theme_constant_override("separation", 8)
		root.add_child(card)

		var name_label: Label = Label.new()
		name_label.name = "ProductName_%s" % suffix
		name_label.text = _live_product_title(row)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 24)
		card.add_child(name_label)

		var price_label: Label = Label.new()
		price_label.name = "PriceLabel_%s" % suffix
		price_label.text = PRICE_UNAVAILABLE
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_font_size_override("font_size", 18)
		card.add_child(price_label)
		_price_labels[product_id] = price_label

		var buy: Button = Button.new()
		buy.name = "BuyButton_%s" % suffix
		buy.text = "Buy"
		buy.custom_minimum_size = Vector2(0, 56)
		buy.pressed.connect(_on_buy_live_product.bind(product_id))
		card.add_child(buy)
		_buy_buttons[product_id] = buy


func _live_product_title(row: Dictionary) -> String:
	var named: String = str(row.get("name", "")).strip_edges()
	if not named.is_empty():
		return named
	var amount: int = int(row.get("diamond_amount", 0))
	if amount > 0:
		return "%s Diamonds" % str(amount)
	return str(row.get("iap_product_id", "Store product"))


func _build_iap_test_harness(root: VBoxContainer) -> void:
	var banner: Label = Label.new()
	banner.text = "IAP TEST — DEBUG ONLY. Queue SKUs are not in the release store."
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 14)
	root.add_child(banner)

	var query_btn: Button = Button.new()
	query_btn.name = "DebugQueryButton"
	query_btn.text = "IAP TEST: Query products"
	query_btn.pressed.connect(_on_iap_query)
	root.add_child(query_btn)

	var buy_btn: Button = Button.new()
	buy_btn.name = "DebugBuilderBuyButton"
	buy_btn.text = "IAP TEST: Buy Permanent Builder Queue"
	buy_btn.pressed.connect(_on_iap_buy_builder)
	root.add_child(buy_btn)

	var restore_btn: Button = Button.new()
	restore_btn.name = "DebugRestoreButton"
	restore_btn.text = "IAP TEST: Restore purchases"
	restore_btn.pressed.connect(_on_iap_restore)
	root.add_child(restore_btn)


func _bind_billing_signals() -> void:
	if _billing_bound:
		return
	var node: Node = Commerce.ensure_android_billing_node()
	if node == null or not node.has_signal("billing_status"):
		return
	if not node.billing_status.is_connected(_on_billing_status):
		node.billing_status.connect(_on_billing_status)
	_billing_bound = true


func _query_live_products() -> void:
	if not Commerce.is_nakama_authenticated():
		_set_status("Sign in to buy Diamonds.")
		return
	var result: Dictionary = Commerce.query_android_products()
	var st: String = str(result.get("status", ""))
	if st == Commerce.STATUS_BILLING_UNAVAILABLE:
		_set_status("Google Play Billing is available on Android devices.")
		return
	if st == Commerce.STATUS_UNAUTHENTICATED:
		_set_status("Sign in to buy Diamonds.")
		return
	if bool(result.get("ok", false)):
		_set_status("Loading store…")


func _refresh_live_prices() -> void:
	for product_id: Variant in _price_labels.keys():
		var pid: String = str(product_id)
		var details: Dictionary = Commerce.get_google_product_details(pid)
		var formatted: String = Commerce.formatted_price_from_google_details(details)
		var price_label: Label = _price_labels[pid]
		if formatted.is_empty():
			price_label.text = PRICE_UNAVAILABLE
		else:
			price_label.text = formatted


func _on_buy_live_product(product_id: String) -> void:
	if _purchase_busy:
		return
	if not Commerce.is_live_store_google_product(product_id):
		_set_status("That product is not in the live store.")
		return
	_purchase_busy = true
	if has_node("/root/UiLayerStack"):
		UiLayerStack.set_layer_blocking("hud_screen", true)
	_set_buy_enabled(false)
	_set_status("Starting Google Play purchase…")
	var result: Dictionary = Commerce.purchase_android_product(product_id)
	_apply_launch_result(result)


func _apply_launch_result(result: Dictionary) -> void:
	var st: String = str(result.get("status", ""))
	if st == "BILLING_FLOW_LAUNCHED":
		_set_status("Complete the purchase in Google Play…")
		return
	if st == Commerce.STATUS_CANCELED:
		_finish_busy("Purchase canceled.")
		return
	if st == Commerce.STATUS_PENDING:
		_finish_busy("Purchase pending. Diamonds are granted after Google completes payment.")
		return
	if st == Commerce.STATUS_UNAUTHENTICATED:
		_finish_busy("Sign in to buy Diamonds.")
		return
	if st == Commerce.STATUS_BILLING_UNAVAILABLE:
		_finish_busy("Google Play Billing is available on Android devices.")
		return
	if st == Commerce.STATUS_INVALID_PRODUCT:
		_finish_busy("This product cannot be purchased.")
		return
	if st == "ALREADY_OWNED_QUERYING":
		_set_status("Checking existing Google Play purchases…")
		return
	_finish_busy("Could not start purchase (%s)." % st)


func _on_billing_status(status: String, _detail: Dictionary) -> void:
	if status == "PRODUCT_DETAILS" or status == "CONNECTED":
		_refresh_live_prices()
		if status == "CONNECTED":
			_set_status(STATUS_IDLE)
		return
	if status == Commerce.STATUS_PENDING:
		_finish_busy("Purchase pending. Diamonds are granted after Google completes payment.")
		return
	if status == Commerce.STATUS_CANCELED:
		_finish_busy("Purchase canceled.")
		return
	if status == Commerce.STATUS_DELIVERED:
		_finish_busy("Purchase complete. Diamonds updated from the server.")
		return
	if status == Commerce.STATUS_ALREADY_DELIVERED:
		_finish_busy("This purchase was already delivered.")
		return
	if status == Commerce.STATUS_SERVER_REJECTED:
		_finish_busy("Google purchase could not be validated. It will retry if still unfinished.")
		return
	if status == Commerce.STATUS_VALIDATION_PENDING:
		_set_status("Validating purchase with the server…")
		return
	if status == Commerce.STATUS_FAILED:
		_finish_busy("Purchase failed.")
		return


func _finish_busy(message: String) -> void:
	_purchase_busy = false
	if has_node("/root/UiLayerStack"):
		UiLayerStack.set_layer_blocking("hud_screen", false)
	_set_buy_enabled(true)
	_set_status(message)


func _set_buy_enabled(enabled: bool) -> void:
	for product_id: Variant in _buy_buttons.keys():
		var btn: Button = _buy_buttons[product_id]
		btn.disabled = not enabled


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
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()
