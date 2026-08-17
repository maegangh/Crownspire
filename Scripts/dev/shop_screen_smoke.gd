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

	print("[SHOP] release UI exposes diamonds_500 only")
	var shop: Control = ShopScript.new()
	shop.name = "ShopScreenSmoke"
	root.add_child(shop)
	await process_frame
	shop.call("on_open")
	await process_frame

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
	_assert(joined.find("Price shown at Google Play checkout") >= 0, "fallback price copy missing")
	_assert(shop.find_child("BuyButton_com_crownspire_builder_queue_perm", true, false) == null, "release must not show builder buy")
	_assert(shop.find_child("ReleaseProduct_com_crownspire_test_diamonds_internal_do_not_ship", true, false) == null, "TEST SKU row must not exist")

	print("[SHOP] buy uses existing coordinator path")
	var buy: Button = shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false)
	_assert(buy != null, "buy button lookup")
	if buy != null:
		buy.emit_signal("pressed")
		await process_frame
	var status: Label = shop.find_child("ShopStatus", true, false)
	var status_text: String = str(status.text) if status != null else ""
	_assert(
		status_text.find("Sign in") >= 0 or status_text.find("Google Play Billing") >= 0 or status_text.find("purchase") >= 0,
		"buy status unexpected: %s" % status_text
	)
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "buy launch must not grant locally")
	_assert(not bool(Commerce.notify_platform_purchase_success({"ok": true}).get("granted", true)), "client callback still not authority")

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
