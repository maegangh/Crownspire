extends SceneTree

## Release Shop + login wallet-sync smoke. No live Play purchase. No live user://.
##   Godot --headless --path <project> -s res://Scripts/dev/shop_screen_smoke.gd

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const ShopScript := preload("res://Scripts/UI/ShopScreen.gd")

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame

	var gs: Node = root.get_node_or_null("/root/GameState")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	if gs == null or asp == null or identity == null or cloud == null:
		push_error("[SHOP] ABORT — required autoloads missing")
		quit(2)
		return

	print("[SHOP] isolate account partition")
	asp.call("begin_smoke_isolation")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "shop_release")
	asp.call("open_save_context", "shop_release", {
		"legacy_owner": "other",
		"legacy_mismatch": true,
		"reload": false,
	})
	if asp.has_method("enable_smoke_bootstrap_hold"):
		asp.call("enable_smoke_bootstrap_hold", false)
	if asp.has_method("set_cloud_bootstrap_hold"):
		asp.call("set_cloud_bootstrap_hold", false)
	cloud.call("begin_smoke_isolation")
	Commerce.begin_smoke_isolation()
	gs.call("load_resources")

	print("[SHOP] live_store catalog")
	var live_ids: PackedStringArray = Commerce.get_live_store_google_product_ids()
	_assert(live_ids.has("com.crownspire.diamonds_500"), "live store missing diamonds_500")
	_assert(not live_ids.has("com.crownspire.builder_queue_perm"), "builder perm must stay hidden")
	_assert(not live_ids.has("com.crownspire.builder_queue_30d"), "builder 30d must stay hidden")
	_assert(not live_ids.has("com.crownspire.research_queue_perm"), "research perm must stay hidden")
	_assert(not live_ids.has("com.crownspire.march_queue_perm"), "march perm must stay hidden")
	_assert(not live_ids.has("com.crownspire.test.diamonds_internal_do_not_ship"), "TEST SKU must stay hidden")
	_assert(Commerce.is_live_store_google_product("com.crownspire.diamonds_500"), "diamonds_500 is live_store")
	_assert(not Commerce.is_live_store_google_product("com.crownspire.builder_queue_perm"), "queue SKU is not live_store")
	var priced: String = Commerce.formatted_price_from_google_details({
		"product_id": "com.crownspire.diamonds_500",
		"one_time_purchase_offer_details": {"formatted_price": "CA$6.99"},
	})
	_assert(priced == "CA$6.99", "localized Google price is used when present")
	_assert(Commerce.formatted_price_from_google_details({}) == "", "missing price must stay empty")
	var option_priced: String = Commerce.formatted_price_from_google_details({
		"product_id": "com.crownspire.diamonds_500",
		"one_time_purchase_offer_details_list": [{
			"purchase_option_id": "other-option",
			"formatted_price": "US$9.99",
		}, {
			"purchase_option_id": "buy-500-diamonds",
			"offer_id": null,
			"formatted_price": "US$4.99",
		}],
	})
	_assert(option_priced == "US$4.99", "shop price prefers buy-500-diamonds list row")
	_assert(Commerce.get_preferred_google_purchase_option("com.crownspire.diamonds_500") == "buy-500-diamonds", "shop preferred option")

	print("[SHOP] release UI exposes diamonds_500 only")
	var shop: Control = ShopScript.new()
	shop.name = "ShopScreenSmoke"
	root.add_child(shop)
	await process_frame
	shop.call("on_open")
	await process_frame

	_assert(shop.visible, "shop opens in release storefront")
	_assert(str(shop.call("get_active_tab")) == "diamonds", "Diamonds tab must be active on open")
	_assert(shop.find_child("ShopTab_diamonds", true, false) != null, "Diamonds tab missing")
	_assert(shop.find_child("ShopTab_deals", true, false) != null, "Deals tab missing")
	_assert(shop.find_child("ShopTab_growth", true, false) != null, "Growth tab missing")
	_assert(shop.find_child("ShopTab_passes", true, false) != null, "Passes tab missing")
	_assert(shop.find_child("ShopTab_offers", true, false) != null, "Special Offers tab missing")
	_assert(shop.find_child("DiamondGrid", true, false) != null, "future Diamond grid missing")
	_assert(shop.find_child("ShopBackButton", true, false) != null, "visible Back missing")
	_assert(shop.find_child("ShopCloseButton", true, false) != null, "visible Close missing")

	var ids: PackedStringArray = shop.call("get_release_product_ids")
	_assert(ids.has("com.crownspire.diamonds_500"), "shop release ids include diamonds_500")
	_assert(ids.size() == 1, "shop release ids must be diamonds_500 only, got %s" % str(ids.size()))
	_assert(shop.find_child("ReleaseProduct_com_crownspire_diamonds_500", true, false) != null, "release product row missing")
	_assert(shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false) != null, "release buy button missing")
	_assert(shop.find_child("Shop coming soon", true, false) == null, "placeholder must be gone")
	var body_labels: Array = []
	_collect_label_text(shop, body_labels)
	var joined: String = " | ".join(body_labels)
	_assert(joined.find("Shop coming soon") < 0, "release shop still says coming soon")
	_assert(joined.find("500 Diamonds") >= 0, "release shop must show 500 Diamonds")
	_assert(joined.find("$4.99") < 0, "must not hardcode $4.99")
	_assert(joined.find("Price shown at Google Play checkout") < 0, "old checkout fallback must not remain")
	var price_label: Label = shop.find_child("PriceLabel_com_crownspire_diamonds_500", true, false)
	_assert(price_label != null, "price label missing")
	var pre_price: String = str(price_label.text) if price_label != null else ""
	_assert(
		pre_price.find("Loading price") >= 0 or pre_price.find("Price unavailable") >= 0 or pre_price.find("Loading store") >= 0,
		"pre-details price should be loading/unavailable, got: %s" % pre_price
	)
	_assert(shop.find_child("BuyButton_com_crownspire_builder_queue_perm", true, false) == null, "release must not show builder buy")
	_assert(shop.find_child("ReleaseProduct_com_crownspire_test_diamonds_internal_do_not_ship", true, false) == null, "TEST SKU row must not exist")
	_assert(int(shop.call("count_live_buy_buttons_in_active_page")) == 1, "Diamonds tab should have one live Buy")
	var beta_panel: Control = shop.find_child("BetaVoucherPanel", true, false)
	_assert(beta_panel != null, "beta voucher panel node exists")
	_assert(beta_panel != null and not beta_panel.visible, "beta voucher panel hidden for production users")
	_assert(shop.find_child("VoucherBuyButton_com_crownspire_diamonds_500", true, false) != null, "voucher buy control exists")

	print("[SHOP] beta voucher panel appears only when server enables it")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"beta_vouchers": 5,
		"beta_voucher_available": true,
		"beta_voucher_offers": [{
			"product_id": "com.crownspire.diamonds_500",
			"iap_product_id": "com.crownspire.diamonds_500",
			"voucher_cost": 5,
		}],
		"entitlements": [],
	})
	shop.call("on_open")
	await process_frame
	var beta_shown: Control = shop.find_child("BetaVoucherPanel", true, false)
	_assert(beta_shown != null and beta_shown.visible, "server-approved beta mode shows voucher panel")
	var bal: Label = shop.find_child("BetaVoucherBalance", true, false)
	_assert(bal != null and str(bal.text).find("5") >= 0, "voucher balance displayed from server")
	_assert(shop.find_child("BetaVoucherRedeemInput", true, false) != null, "redeem field present")
	_assert(shop.find_child("BetaVoucherRedeemButton", true, false) != null, "redeem button present")
	Commerce.apply_commerce_wallet_payload({"diamonds": 0, "beta_voucher_available": false, "beta_vouchers": 0, "entitlements": []})
	shop.call("on_open")
	await process_frame
	var beta_hidden: Control = shop.find_child("BetaVoucherPanel", true, false)
	_assert(beta_hidden != null and not beta_hidden.visible, "L: authoritative unavailable hides voucher panel")
	_assert(not Commerce.is_beta_voucher_available(), "L: client snapshot stays unauthorized")
	_assert(not bool(Commerce.try_grant_beta_voucher_testing().get("ok", true)), "L: UI/client cannot self-enable")

	print("[SHOP] tabs switch; coming-soon pages have no live Buy")
	var coming_tabs: PackedStringArray = PackedStringArray(["deals", "growth", "passes", "offers"])
	for tab_id in coming_tabs:
		shop.call("select_tab", tab_id)
		await process_frame
		_assert(str(shop.call("get_active_tab")) == tab_id, "tab did not switch to %s" % tab_id)
		_assert(int(shop.call("count_live_buy_buttons_in_active_page")) == 0, "%s tab must not expose live Buy" % tab_id)
		_assert(shop.find_child("ComingSoonLabel_%s" % tab_id, true, false) != null, "%s coming soon copy missing" % tab_id)
	shop.call("select_tab", "diamonds")
	await process_frame
	_assert(str(shop.call("get_active_tab")) == "diamonds", "return to Diamonds failed")
	_assert(int(shop.call("count_live_buy_buttons_in_active_page")) == 1, "Diamonds Buy missing after tab return")

	print("[SHOP] Google formatted price replaces loading/fallback")
	shop.call("_on_billing_status", "PRODUCT_DETAILS", {
		"response_code": 0,
		"product_details": [{
			"product_id": "com.crownspire.diamonds_500",
			"title": "500 Diamonds",
			"one_time_purchase_offer_details_list": [{
				"purchase_option_id": "buy-500-diamonds",
				"offer_id": null,
				"formatted_price": "CA$6.99",
			}],
			"one_time_purchase_offer_details": {"formatted_price": "CA$6.99"},
		}],
	})
	await process_frame
	var priced_label: Label = shop.find_child("PriceLabel_com_crownspire_diamonds_500", true, false)
	_assert(priced_label != null and str(priced_label.text) == "CA$6.99", "formatted Google price not shown, got %s" % str(priced_label.text if priced_label != null else ""))
	var after_labels: Array = []
	_collect_label_text(shop, after_labels)
	var after_joined: String = " | ".join(after_labels)
	_assert(after_joined.find("Loading store") < 0, "Loading store remained after product details")
	_assert(after_joined.find("Loading price") < 0, "Loading price remained after product details")
	_assert(after_joined.find("Price shown at Google Play checkout") < 0, "checkout fallback remained after product details")
	_assert(after_joined.find("$4.99") < 0, "must not display hardcoded USD after details")

	print("[SHOP] buy uses existing coordinator path")
	var buy: Button = shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false)
	_assert(buy != null, "buy button lookup")
	if buy != null:
		buy.emit_signal("pressed")
		await process_frame
		await process_frame
	var protect: Node = shop.find_child("ProtectAccountModal", true, false)
	_assert(protect != null, "guest buy must show protect-account modal")
	_assert(shop.find_child("ProtectAccountTitle", true, false) != null, "protect title missing")
	_assert(shop.find_child("ProtectAccountSecureButton", true, false) != null, "protect Secure button missing")
	_assert(shop.find_child("ProtectAccountCancelButton", true, false) != null, "protect Cancel missing")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "guest protect gate must not grant locally")
	var guest_launch: Dictionary = Commerce.purchase_android_product("com.crownspire.diamonds_500")
	_assert(str(guest_launch.get("status", "")) != "BILLING_FLOW_LAUNCHED", "guest must not launch Google Billing")
	_assert(not bool(guest_launch.get("granted", true)), "guest launch must not grant")
	if shop.has_method("_hide_protect_account_modal"):
		shop.call("_hide_protect_account_modal")

	print("[SHOP] secured account still has purchase path")
	identity.call("smoke_mark_secured_email")
	_assert(bool(identity.call("can_start_real_money_purchase")), "secured account can purchase")
	var secured_launch: Dictionary = Commerce.purchase_android_product("com.crownspire.diamonds_500")
	_assert(str(secured_launch.get("status", "")) != Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED, "secured must not hard-gate")
	_assert(
		str(secured_launch.get("status", "")) == Commerce.STATUS_BILLING_UNAVAILABLE
		or str(secured_launch.get("status", "")) == Commerce.STATUS_UNAUTHENTICATED
		or str(secured_launch.get("status", "")) == "BILLING_FLOW_LAUNCHED",
		"secured purchase path unexpected: %s" % str(secured_launch.get("status", ""))
	)
	if buy != null:
		buy.emit_signal("pressed")
		await process_frame
	var status: Label = shop.find_child("ShopStatus", true, false)
	var status_text: String = str(status.text) if status != null else ""
	_assert(
		status_text.find("Sign in") >= 0 or status_text.find("Google Play Billing") >= 0 or status_text.find("purchase") >= 0 or status_text.find("Protect") >= 0,
		"buy status unexpected: %s" % status_text
	)
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "buy launch must not grant locally")
	_assert(not bool(Commerce.notify_platform_purchase_success({"ok": true}).get("granted", true)), "client callback still not authority")

	print("[SHOP] Close / Back / purchase-busy")
	var stack: Node = root.get_node_or_null("/root/UiLayerStack")
	_assert(stack != null, "UiLayerStack missing")
	if stack != null:
		stack.call("reset_for_tests")
		stack.call("push_layer", "hud_screen", Callable(shop, "request_back"), "screen", false)
	_assert(bool(shop.call("request_back")) == false, "idle Back should pop the shop layer")
	shop.call("set_purchase_in_flight_for_test", true)
	_assert(bool(shop.call("is_purchase_busy")), "purchase busy flag")
	_assert(bool(shop.call("request_back")) == true, "busy Back must keep shop")
	if stack != null:
		_assert(bool(stack.call("is_layer_blocking", "hud_screen")), "busy must block hud_screen")
		stack.call("handle_back")
		_assert(shop.visible, "busy Android Back must not close shop")
		_assert(str(stack.call("top_id")) == "hud_screen", "busy Back must keep hud_screen")
	var close_btn: Button = shop.find_child("ShopCloseButton", true, false)
	_assert(close_btn != null, "Close button lookup")
	if close_btn != null:
		close_btn.emit_signal("pressed")
		await process_frame
	_assert(shop.visible, "visible Close must not dismiss during purchase")
	shop.call("set_purchase_in_flight_for_test", false)
	if stack != null:
		stack.call("set_layer_blocking", "hud_screen", false)
	var back_btn: Button = shop.find_child("ShopBackButton", true, false)
	_assert(back_btn != null, "Back button lookup")
	if back_btn != null:
		back_btn.emit_signal("pressed")
		await process_frame
	_assert(not shop.visible, "visible Back should close shop when idle")
	shop.call("on_open")
	await process_frame
	_assert(shop.visible, "shop can reopen after Close/Back")

	print("[SHOP] login wallet refresh + entitlement restore")
	gs.set("diamonds", 500)
	gs.call("save_resources")
	_assert(int(gs.get("diamonds")) == 500, "stale local mirror 500")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": []},
		{"diamonds": 0, "entitlements": []}
	)
	await Commerce.on_session_authenticated()
	var counts: Dictionary = Commerce.get_session_authority_sync_counts()
	_assert(int(counts.get("restore", 0)) >= 1, "login must call restore_server_entitlements")
	_assert(int(counts.get("refresh", 0)) >= 1, "login must call refresh_server_wallet")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "server wallet 0 after refresh")
	_assert(int(gs.get("diamonds")) == 0, "HUD/local mirror becomes 0 after refund/relogin")

	print("[SHOP] pending/cancel still do not grant")
	var pending: Dictionary = await Commerce.ingest_google_billing_purchase({
		"order_id": "GPA.SHOP-P",
		"purchase_token": "tok-shop-p",
		"package_name": "com.mythiccrownstudios.crownspire",
		"purchase_state": Commerce.GOOGLE_PURCHASE_STATE_PENDING,
		"purchase_time": 1,
		"original_json": "{\"productId\":\"com.crownspire.diamonds_500\"}",
		"product_ids": PackedStringArray(["com.crownspire.diamonds_500"]),
	})
	_assert(str(pending.get("status", "")) == Commerce.STATUS_PENDING, "pending status")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "pending must not grant")
	var canceled: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_USER_CANCELED,
		"purchases": [],
	})
	_assert(str(canceled.get("status", "")) == Commerce.STATUS_CANCELED, "canceled status")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "cancel must not grant")

	print("[SHOP] delivered then duplicate")
	Commerce.set_test_process_purchase_override(_deliver_once)
	var delivered: Dictionary = await Commerce.ingest_google_billing_purchase({
		"order_id": "GPA.SHOP-D",
		"purchase_token": "tok-shop-d",
		"package_name": "com.mythiccrownstudios.crownspire",
		"purchase_state": Commerce.GOOGLE_PURCHASE_STATE_PURCHASED,
		"purchase_time": 1,
		"original_json": "{\"productId\":\"com.crownspire.diamonds_500\",\"purchaseToken\":\"tok-shop-d\"}",
		"is_acknowledged": false,
		"product_ids": PackedStringArray(["com.crownspire.diamonds_500"]),
	})
	_assert(str(delivered.get("status", "")) == Commerce.STATUS_DELIVERED, "delivered status got %s" % str(delivered.get("status", "")))
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "server delivery updates wallet")
	_assert(int(gs.get("diamonds")) == 500, "HUD updates after server DELIVERED")
	var dup: Dictionary = await Commerce.ingest_google_billing_purchase({
		"order_id": "GPA.SHOP-D",
		"purchase_token": "tok-shop-d",
		"package_name": "com.mythiccrownstudios.crownspire",
		"purchase_state": Commerce.GOOGLE_PURCHASE_STATE_PURCHASED,
		"purchase_time": 1,
		"original_json": "{\"productId\":\"com.crownspire.diamonds_500\",\"purchaseToken\":\"tok-shop-d\"}",
		"is_acknowledged": false,
		"product_ids": PackedStringArray(["com.crownspire.diamonds_500"]),
	})
	_assert(str(dup.get("status", "")) == Commerce.STATUS_ALREADY_DELIVERED, "duplicate already delivered")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "duplicate must not double grant")

	print("[SHOP] purchase-option source contract")
	var coord_src := FileAccess.open("res://Scripts/AndroidPlayBillingCoordinator.gd", FileAccess.READ)
	var coord_body: String = coord_src.get_as_text() if coord_src != null else ""
	_assert(coord_body.find("call(\"purchase\", product_id, option_id)") >= 0, "shop path must pass purchase_option_id")
	_assert(coord_body.find("one_time_purchase_offer_details_list") >= 0, "shop path must read offer list")
	_assert(coord_body.find("buy-500-diamonds") >= 0, "buy-500-diamonds must exist in live purchase path")

	shop.queue_free()
	Commerce.end_smoke_isolation()
	cloud.call("end_smoke_isolation")

	if _fail.is_empty():
		print("[SHOP] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[SHOP] FAIL: %s" % f)
		quit(1)


func _deliver_once(_platform: String, _receipt: String) -> Dictionary:
	var already: bool = int(Commerce.get_authoritative_diamonds()) >= 500
	return {
		"ok": true,
		"purchases": [{
			"delivery_status": "DELIVERED",
			"seen_before": already,
			"product_id": "com.crownspire.diamonds_500",
		}],
		"wallet": {
			"diamonds": 500,
			"entitlements": [],
		},
	}


func _collect_label_text(n: Node, out: Array) -> void:
	if n is Label:
		out.append(str((n as Label).text))
	for child: Node in n.get_children():
		_collect_label_text(child, out)
