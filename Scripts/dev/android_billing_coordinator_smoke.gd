extends SceneTree

## Isolated Batch 4C Android billing coordinator smoke. No live Play purchase. No live user://.
##   Godot --headless --path <project> -s res://Scripts/dev/android_billing_coordinator_smoke.gd

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const CoordinatorScript := preload("res://Scripts/AndroidPlayBillingCoordinator.gd")
const BillingClientScript := preload("res://addons/GodotGooglePlayBilling/BillingClient.gd")

var _fail: Array[String] = []
var _rpc_calls: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _purchase(token: String, state: int, product_id: String = "com.crownspire.builder_queue_perm") -> Dictionary:
	return {
		"order_id": "GPA.SMOKE-%s" % token,
		"purchase_token": token,
		"package_name": "com.mythiccrownstudios.crownspire",
		"purchase_state": state,
		"purchase_time": 1,
		"original_json": JSON.stringify({
			"orderId": "GPA.SMOKE-%s" % token,
			"packageName": "com.mythiccrownstudios.crownspire",
			"productId": product_id,
			"purchaseTime": 1,
			"purchaseState": 0,
			"purchaseToken": token,
		}),
		"is_acknowledged": false,
		"quantity": 1,
		"product_ids": PackedStringArray([product_id]),
	}


func _reject_server(_platform: String, _receipt: String) -> Dictionary:
	_rpc_calls += 1
	return {"ok": false, "error": "validation_failed", "delivered": false, "granted": false}


func _deliver_server(_platform: String, _receipt: String) -> Dictionary:
	_rpc_calls += 1
	return {
		"ok": true,
		"purchases": [{
			"delivery_status": "DELIVERED",
			"seen_before": _rpc_calls > 1,
			"entitlement_id": Commerce.ENT_BUILDER_PERM,
		}],
		"wallet": {
			"diamonds": 0,
			"entitlements": [{
				"entitlement_id": Commerce.ENT_BUILDER_PERM,
				"status": "active",
				"starts_at": 1,
				"expires_at": 0,
			}],
		},
	}


func _deliver_diamonds_server(_platform: String, _receipt: String) -> Dictionary:
	_rpc_calls += 1
	return {
		"ok": true,
		"purchases": [{
			"delivery_status": "DELIVERED",
			"seen_before": _rpc_calls > 1,
			"product_id": "com.crownspire.diamonds_500",
		}],
		"wallet": {
			"diamonds": 500,
			"entitlements": [],
		},
	}


func _run() -> void:
	await process_frame
	await process_frame

	var gs: Node = root.get_node_or_null("/root/GameState")
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if gs == null or cs == null or cloud == null or asp == null or identity == null:
		push_error("[BILLING 4C] ABORT — required autoloads missing")
		quit(2)
		return

	print("[BILLING 4C] isolate account partition")
	asp.call("begin_smoke_isolation")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "billing_4c")
	asp.call("open_save_context", "billing_4c", {
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
	cs.call("refresh_account_save_paths")
	gs.call("load_resources")
	var gs_path: String = str(gs.call("get_resources_path"))
	_assert(gs_path.contains("saves_smoke_test") or gs_path.contains("billing_4c"), "resources path not isolated: %s" % gs_path)
	if not (gs_path.contains("saves_smoke_test") or gs_path.contains("billing_4c")):
		push_error("[BILLING 4C] ABORT — GameState path not isolated")
		quit(2)
		return

	var ids: PackedStringArray = Commerce.get_google_query_product_ids()
	_assert(ids.has("com.crownspire.builder_queue_perm"), "catalog missing builder perm Google ID")
	_assert(ids.has("com.crownspire.diamonds_500"), "catalog missing diamonds_500 Google ID")
	_assert(not ids.has("com.crownspire.test.diamonds_internal_do_not_ship"), "TEST SKU must not be queried")
	_assert(Commerce.is_allowed_google_product("com.crownspire.diamonds_500"), "diamonds_500 must be buyable")
	_assert(Commerce.is_consumable_google_product("com.crownspire.diamonds_500"), "diamonds_500 must be consumable")
	_assert(not Commerce.is_consumable_google_product("com.crownspire.builder_queue_perm"), "builder perm must not be consumable")
	_assert(not Commerce.is_allowed_google_product("com.crownspire.test.diamonds_internal_do_not_ship"), "TEST SKU must not be buyable")
	_assert(Commerce.is_live_store_google_product("com.crownspire.diamonds_500"), "diamonds_500 is live_store")
	_assert(not Commerce.is_live_store_google_product("com.crownspire.builder_queue_perm"), "builder perm is not live_store")
	_assert(not Commerce.get_live_store_google_product_ids().has("com.crownspire.test.diamonds_internal_do_not_ship"), "TEST SKU not in live store ids")
	_assert(Commerce.get_preferred_google_purchase_option(Commerce.GOOGLE_DIAMOND_PACK_500) == "buy-500-diamonds", "preferred option")
	_assert(Commerce.GOOGLE_DIAMOND_PACK_500_PURCHASE_OPTION == "buy-500-diamonds", "purchase option constant")
	_assert(not Engine.has_singleton("GodotGooglePlayBilling"), "desktop must not expose Play Billing singleton")

	var coord: Node = CoordinatorScript.new()
	root.add_child(coord)
	await process_frame
	_assert(str(coord.call("get_last_status")) == Commerce.STATUS_BILLING_UNAVAILABLE, "desktop coordinator must stay unavailable")
	_assert(not bool(coord.call("is_product_ready", Commerce.GOOGLE_DIAMOND_PACK_500)), "desktop product must not be ready")

	print("[BILLING 4C] product details readiness + purchase option")
	var diamonds_details := [{
		"product_id": "com.crownspire.diamonds_500",
		"product_type": "inapp",
		"one_time_purchase_offer_details_list": [{
			"purchase_option_id": "buy-500-diamonds",
			"offer_id": null,
			"formatted_price": "US$4.99",
		}],
	}]
	coord.call("apply_smoke_billing_state", [], false, false, null)
	_assert(not bool(coord.call("is_product_ready", Commerce.GOOGLE_DIAMOND_PACK_500)), "disconnected details must not be ready")
	var blocked_disc: Dictionary = coord.call("resolve_purchase_launch", Commerce.GOOGLE_DIAMOND_PACK_500)
	_assert(str(blocked_disc.get("status", "")) == Commerce.STATUS_BILLING_NOT_READY, "disconnected launch blocked")
	_assert(not bool(blocked_disc.get("granted", true)), "disconnected must not grant")

	coord.call("apply_smoke_billing_state", [], true, true, null)
	_assert(not bool(coord.call("is_product_ready", Commerce.GOOGLE_DIAMOND_PACK_500)), "empty details must not be ready")
	var blocked_empty: Dictionary = coord.call("resolve_purchase_launch", Commerce.GOOGLE_DIAMOND_PACK_500)
	_assert(str(blocked_empty.get("status", "")) == Commerce.STATUS_PRODUCT_DETAILS_NOT_READY, "absent details launch blocked")
	_assert(not bool(blocked_empty.get("granted", true)), "absent details must not grant")
	_assert(str(coord.call("get_formatted_price_for_product", Commerce.GOOGLE_DIAMOND_PACK_500)) == "", "no Google price before details")

	var stub: Node = load("res://Scripts/dev/billing_purchase_stub.gd").new()
	coord.call("apply_smoke_billing_state", diamonds_details, true, true, stub)
	_assert(bool(coord.call("is_product_ready", Commerce.GOOGLE_DIAMOND_PACK_500)), "details + option must be ready")
	_assert(str(coord.call("resolve_purchase_option_id", Commerce.GOOGLE_DIAMOND_PACK_500)) == "buy-500-diamonds", "option from details list")
	_assert(str(coord.call("get_formatted_price_for_product", Commerce.GOOGLE_DIAMOND_PACK_500)) == "US$4.99", "price from one_time_purchase_offer_details_list")
	var ready_launch: Dictionary = coord.call("resolve_purchase_launch", Commerce.GOOGLE_DIAMOND_PACK_500)
	_assert(bool(ready_launch.get("ok", false)), "ready launch eligible")
	_assert(str(ready_launch.get("purchase_option_id", "")) == "buy-500-diamonds", "launch option buy-500-diamonds")
	_assert(not bool(ready_launch.get("granted", true)), "eligible launch must not grant")

	if identity != null and identity.has_method("smoke_mark_secured_email"):
		identity.call("smoke_mark_secured_email")
	var launched: Dictionary = coord.call("purchase_product", Commerce.GOOGLE_DIAMOND_PACK_500)
	var launch_status: String = str(launched.get("status", ""))
	if launch_status != Commerce.STATUS_UNAUTHENTICATED:
		_assert(launch_status == "BILLING_FLOW_LAUNCHED", "secured launch status got %s" % launch_status)
		_assert(str(stub.get("last_product_id")) == "com.crownspire.diamonds_500", "purchase product id")
		_assert(str(stub.get("last_purchase_option_id")) == "buy-500-diamonds", "purchase option id")
		_assert(str(stub.get("last_offer_id")) == "", "must not pass offer token")
	_assert(not bool(launched.get("granted", true)), "launch must not grant")

	var wrong_option := [{
		"product_id": "com.crownspire.diamonds_500",
		"one_time_purchase_offer_details_list": [{
			"purchase_option_id": "other-option",
			"offer_id": null,
			"formatted_price": "US$9.99",
		}],
	}]
	coord.call("apply_smoke_billing_state", wrong_option, true, true, stub)
	_assert(not bool(coord.call("is_product_ready", Commerce.GOOGLE_DIAMOND_PACK_500)), "wrong option must not be ready")
	_assert(str(coord.call("resolve_purchase_option_id", Commerce.GOOGLE_DIAMOND_PACK_500)) == "", "wrong option must not be selected")
	coord.queue_free()
	stub.queue_free()

	# A. Billing callback alone → zero entitlement
	print("[BILLING 4C] A callback alone")
	var fake: Dictionary = Commerce.notify_platform_purchase_success({
		"ok": true,
		"product_id": "com.crownspire.builder_queue_perm",
	})
	_assert(not bool(fake.get("delivered", true)), "A: notify must not deliver")
	_assert(not bool(fake.get("granted", true)), "A: notify must not grant")
	var a_in: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_OK,
		"purchases": [_purchase("tok-a", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED)],
	})
	_assert(not bool(a_in.get("granted", true)), "A: ingest without server success must not grant")
	_assert(not bool(a_in.get("delivered", true)), "A: ingest without server success must not deliver")
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "A: no paid construction from callback")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "A: wallet stays 0")

	# B. purchase callback + server rejection → zero entitlement
	print("[BILLING 4C] B server rejection")
	_rpc_calls = 0
	Commerce.set_test_process_purchase_override(_reject_server)
	var b_in: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_OK,
		"purchases": [_purchase("tok-b", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED)],
	})
	_assert(str(b_in.get("status", "")) == Commerce.STATUS_SERVER_REJECTED, "B: status SERVER_REJECTED")
	_assert(bool(b_in.get("rpc_sent", false)), "B: server was contacted")
	_assert(not bool(b_in.get("acknowledge", true)), "B: must not ack rejected purchase")
	_assert(not bool(b_in.get("consume", true)), "B: must not consume rejected purchase")
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "B: rejection must not grant")
	Commerce.set_test_process_purchase_override(Callable())

	# F. canceled → no RPC delivery/grant
	print("[BILLING 4C] F canceled")
	_rpc_calls = 0
	Commerce.set_test_process_purchase_override(_deliver_server)
	var f_in: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_USER_CANCELED,
		"purchases": [_purchase("tok-f", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED)],
	})
	_assert(str(f_in.get("status", "")) == Commerce.STATUS_CANCELED, "F: status CANCELED")
	_assert(not bool(f_in.get("rpc_sent", true)), "F: cancel must not RPC")
	_assert(_rpc_calls == 0, "F: override must not run")
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "F: cancel must not grant")

	# G. pending → no grant
	print("[BILLING 4C] G pending")
	var g_in: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-g", Commerce.GOOGLE_PURCHASE_STATE_PENDING)
	)
	_assert(str(g_in.get("status", "")) == Commerce.STATUS_PENDING, "G: status PENDING")
	_assert(not bool(g_in.get("rpc_sent", true)), "G: pending must not RPC")
	_assert(not bool(g_in.get("consume", true)), "G: pending must not consume")
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "G: pending must not grant")
	Commerce.set_test_process_purchase_override(Callable())

	# H. unauthenticated / guest protection / desktop billing unavailable
	print("[BILLING 4C] H unauthenticated")
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var authed: bool = nc != null and bool(nc.call("is_authenticated"))
	var h: Dictionary = Commerce.purchase_android_product("com.crownspire.builder_queue_perm")
	_assert(not bool(h.get("granted", true)), "H: must not grant")
	_assert(not bool(h.get("delivered", true)), "H: must not deliver")
	if not authed:
		_assert(str(h.get("status", "")) == Commerce.STATUS_UNAUTHENTICATED, "H: status UNAUTHENTICATED")
	elif identity != null and identity.has_method("has_recoverable_identity") and not bool(identity.call("has_recoverable_identity")):
		_assert(str(h.get("status", "")) == Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED, "H: guest must require account protection")
	else:
		_assert(str(h.get("status", "")) == Commerce.STATUS_BILLING_UNAVAILABLE, "H: desktop authed → billing unavailable")

	# I. invalid product ID → blocked
	print("[BILLING 4C] I invalid product")
	var i_buy: Dictionary = Commerce.purchase_android_product("com.not.a.real.sku")
	_assert(str(i_buy.get("status", "")) == Commerce.STATUS_INVALID_PRODUCT, "I: launch blocked")
	var i_in: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-i", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED, "com.not.a.real.sku")
	)
	_assert(str(i_in.get("status", "")) == Commerce.STATUS_INVALID_PRODUCT, "I: ingest blocked")
	_assert(not bool(i_in.get("rpc_sent", true)), "I: invalid must not RPC")
	var i_test: Dictionary = Commerce.purchase_android_product("com.crownspire.test.diamonds_internal_do_not_ship")
	_assert(str(i_test.get("status", "")) == Commerce.STATUS_INVALID_PRODUCT, "I: TEST SKU blocked")

	# J. local queue cfg remains unable to create ownership
	print("[BILLING 4C] J local queue cfg")
	var q_path: String = str(cs.call("get_queue_path"))
	_assert(str(q_path).contains("saves_smoke_test") or str(q_path).contains("billing_4c"), "J: construction path not isolated")
	if str(q_path).contains("saves_smoke_test") or str(q_path).contains("billing_4c"):
		var qcfg := ConfigFile.new()
		qcfg.set_value("meta", "permanent_secondary_construction_queue", true)
		qcfg.set_value("meta", "secondary_construction_queue_owned", true)
		qcfg.set_value("jobs", "json", "[]")
		qcfg.save(q_path)
		cs.call("load_construction_state")
		_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "J: local flag must not grant")
		_assert(int(cs.call("get_construction_queue_limit")) == 1, "J: construction cap stays 1")

	# C. purchase callback + server delivered → mirror updated
	print("[BILLING 4C] C server delivered")
	_rpc_calls = 0
	Commerce.set_test_process_purchase_override(_deliver_server)
	var c_in: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_OK,
		"purchases": [_purchase("tok-c", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED)],
	})
	_assert(str(c_in.get("status", "")) == Commerce.STATUS_DELIVERED, "C: status DELIVERED got %s" % str(c_in.get("status", "")))
	_assert(bool(c_in.get("delivered", false)), "C: delivered true")
	_assert(not bool(c_in.get("granted", true)), "C: billing path must not set granted=true locally")
	_assert(bool(c_in.get("acknowledge", false)), "C: ack after server accept")
	_assert(not bool(c_in.get("consume", true)), "C: durable queue must never consume")
	_assert(bool(cs.call("has_permanent_secondary_construction_queue")), "C: server snapshot must mirror paid construction")
	_assert(int(cs.call("get_construction_queue_limit")) == 2, "C: construction cap 2 after server grant")

	# D. duplicate callback → no duplicate
	print("[BILLING 4C] D duplicate")
	var d_in: Dictionary = await Commerce.ingest_google_purchase_updated({
		"response_code": Commerce.BILLING_CODE_OK,
		"purchases": [_purchase("tok-c", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED)],
	})
	_assert(str(d_in.get("status", "")) == Commerce.STATUS_ALREADY_DELIVERED, "D: already delivered")
	_assert(bool(cs.call("has_permanent_secondary_construction_queue")), "D: entitlement remains")
	_assert(int(cs.call("get_construction_queue_limit")) == 2, "D: cap stays 2")
	_assert(not bool(d_in.get("consume", true)), "D: duplicate durable must not consume")

	# E. reconnect/query purchases → submit again safely
	print("[BILLING 4C] E reconnect/query")
	Commerce.remember_pending_google_purchase(_purchase("tok-e", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED))
	var retries: Array = await Commerce.retry_pending_google_purchases()
	_assert(retries.size() >= 1, "E: pending retry ran")
	_assert(bool(cs.call("has_permanent_secondary_construction_queue")), "E: restore still one entitlement")
	_assert(int(cs.call("get_construction_queue_limit")) == 2, "E: no duplicate queue")
	_assert(not bool((retries[0] as Dictionary).get("consume", true)), "E: durable retry must not consume")

	# Diamond pack: consume only after server DELIVERED; never local grant
	print("[BILLING 4C] diamonds_500 consume-after-delivery")
	var diamonds_before: int = int(gs.get("diamonds"))
	_rpc_calls = 0
	Commerce.set_test_process_purchase_override(_reject_server)
	var d_rej: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-d500-rej", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED, "com.crownspire.diamonds_500")
	)
	_assert(str(d_rej.get("status", "")) == Commerce.STATUS_SERVER_REJECTED, "diamonds: rejected stays rejected")
	_assert(not bool(d_rej.get("consume", true)), "diamonds: must not consume rejected purchase")
	_assert(not bool(d_rej.get("acknowledge", true)), "diamonds: must not ack rejected purchase")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "diamonds: reject must not mint wallet")
	_assert(int(gs.get("diamonds")) == diamonds_before, "diamonds: reject must not mint GameState")

	_rpc_calls = 0
	Commerce.set_test_process_purchase_override(_deliver_diamonds_server)
	var d_ok: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-d500", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED, "com.crownspire.diamonds_500")
	)
	_assert(str(d_ok.get("status", "")) == Commerce.STATUS_DELIVERED, "diamonds: DELIVERED got %s" % str(d_ok.get("status", "")))
	_assert(bool(d_ok.get("delivered", false)), "diamonds: delivered true")
	_assert(not bool(d_ok.get("granted", true)), "diamonds: billing path must not set granted=true locally")
	_assert(bool(d_ok.get("consume", false)), "diamonds: consume only after server DELIVERED")
	_assert(not bool(d_ok.get("acknowledge", true)), "diamonds: consumable must not acknowledge")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "diamonds: server wallet mirror is 500")

	var d_dup: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-d500", Commerce.GOOGLE_PURCHASE_STATE_PURCHASED, "com.crownspire.diamonds_500")
	)
	_assert(str(d_dup.get("status", "")) == Commerce.STATUS_ALREADY_DELIVERED, "diamonds: duplicate already delivered")
	_assert(bool(d_dup.get("consume", false)), "diamonds: duplicate still consumes Google row")
	_assert(not bool(d_dup.get("acknowledge", true)), "diamonds: duplicate must not acknowledge")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "diamonds: duplicate does not add a second 500")

	var d_pending: Dictionary = await Commerce.ingest_google_billing_purchase(
		_purchase("tok-d500-p", Commerce.GOOGLE_PURCHASE_STATE_PENDING, "com.crownspire.diamonds_500")
	)
	_assert(str(d_pending.get("status", "")) == Commerce.STATUS_PENDING, "diamonds: pending stays pending")
	_assert(not bool(d_pending.get("consume", true)), "diamonds: pending must not consume")
	Commerce.set_test_process_purchase_override(Callable())

	# Production coordinator must never accept test mocks as authority.
	print("[BILLING 4C] production mocks are not authority")
	Commerce.end_smoke_isolation()
	Commerce.set_test_process_purchase_override(_deliver_server)
	var prod: Dictionary = await Commerce.process_platform_purchase("GOOGLE", "fake-receipt")
	_assert(not bool(prod.get("ok", true)), "prod: override ignored outside smoke")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "prod: mock cannot mint wallet")
	Commerce.begin_smoke_isolation()

	var src := FileAccess.open("res://Scripts/AndroidPlayBillingCoordinator.gd", FileAccess.READ)
	var body: String = src.get_as_text() if src != null else ""
	_assert(body.find("grant_permanent_secondary_construction_queue") < 0, "coordinator must not call local grant")
	_assert(body.find("add_diamonds") < 0, "coordinator must not add diamonds")
	_assert(body.find("consume_purchase") >= 0, "coordinator must be able to consume after delivery")
	_assert(body.find("_maybe_finish_google_purchase") >= 0, "coordinator finishes Google only after ingest flags")
	_assert(body.find("consume_purchase_response ignored") < 0, "consumable consume path must be live")
	_assert(body.find("call(\"purchase\", product_id, option_id)") >= 0, "purchase must pass purchase_option_id")
	_assert(body.find("one_time_purchase_offer_details_list") >= 0, "must read Billing 8 offer list")
	_assert(body.find("buy-500-diamonds") >= 0 or body.find("GOOGLE_DIAMOND_PACK_500_PURCHASE_OPTION") >= 0, "buy-500-diamonds path present")
	_assert(body.find("[CrownspireBilling]") >= 0, "safe billing diagnostics missing")
	_assert(body.find("call(\"purchase\", product_id)") < 0 or body.find("call(\"purchase\", product_id, option_id)") >= 0, "must not revert to product-id-only purchase")
	_assert(BillingClientScript != null, "BillingClient.gd must parse")

	cloud.call("end_smoke_isolation")
	Commerce.end_smoke_isolation()

	if _fail.is_empty():
		print("[BILLING 4C] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[BILLING 4C] FAIL: %s" % f)
		quit(1)
