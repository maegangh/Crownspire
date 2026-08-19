extends SceneTree

## Isolated Batch 4B commerce-authority client smoke. Does not touch live user://.
##   Godot --headless --path <project> -s res://Scripts/dev/commerce_authority_smoke.gd

const Commerce := preload("res://Scripts/CommerceAuthority.gd")

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
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	var rs: Node = root.get_node_or_null("/root/ResearchState")
	var ms: Node = root.get_node_or_null("/root/MarchState")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	var al: Node = root.get_node_or_null("/root/AllianceState")
	if gs == null or cs == null or cloud == null or asp == null or identity == null:
		push_error("[COMMERCE 4B] ABORT — required autoloads missing")
		quit(2)
		return

	print("[COMMERCE 4B] isolate account partition")
	asp.call("begin_smoke_isolation")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "commerce_4b")
	asp.call("open_save_context", "commerce_4b", {
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
	_assert(gs_path.contains("saves_smoke_test") or gs_path.contains("commerce_4b"), "resources path not isolated: %s" % gs_path)
	if not (gs_path.contains("saves_smoke_test") or gs_path.contains("commerce_4b")):
		push_error("[COMMERCE 4B] ABORT — GameState path not isolated")
		quit(2)
		return

	# D. client-only fake purchase success → zero delivery
	print("[COMMERCE 4B] D client callback is not authority")
	var fake: Dictionary = Commerce.notify_platform_purchase_success({"ok": true, "product_id": "com.crownspire.builder_queue_perm"})
	_assert(not bool(fake.get("delivered", true)), "D: client callback must not deliver")
	_assert(not bool(fake.get("granted", true)), "D: client callback must not grant")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "D: wallet stays 0")
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "D: no paid construction from callback")

	# G. local Diamond edit cannot alter authoritative wallet
	print("[COMMERCE 4B] G local diamond edit")
	gs.set("diamonds", 999999)
	gs.call("save_resources")
	_assert(int(gs.get("diamonds")) == 999999, "G: mirror accepted local edit")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "G: server wallet unchanged by local edit")

	# Cloud sync cannot raise authoritative Diamonds; Food remains.
	print("[COMMERCE 4B] G cloud cannot raise server diamonds")
	var res_path: String = str(asp.call("partition_path", "resources.cfg", "commerce_4b"))
	var seed_r := ConfigFile.new()
	seed_r.set_value("resources", "food", 7777)
	seed_r.set_value("resources", "wood", 1000)
	seed_r.set_value("resources", "stone", 1000)
	seed_r.set_value("resources", "iron", 1000)
	seed_r.set_value("resources", "diamonds", 999999)
	seed_r.save(res_path)
	var built: Dictionary = cloud.call("build_payload_for_user", "commerce_4b")
	_assert(bool(built.get("ok", false)), "G: payload build failed")
	var payload: Dictionary = built.get("payload", {})
	var files: Dictionary = payload.get("files", {})
	_assert(files.has("resources.cfg"), "G: resources.cfg missing from payload")
	var decoded: PackedByteArray = Marshalls.base64_to_raw(str(files["resources.cfg"]))
	var packed := ConfigFile.new()
	_assert(packed.parse(decoded.get_string_from_utf8()) == OK, "G: packed resources parse failed")
	_assert(int(packed.get_value("resources", "diamonds", -1)) == 0, "G: uploaded diamonds must be sanitized to 0")
	_assert(int(packed.get_value("resources", "food", 0)) == 7777, "G: food must survive cloud sanitize")

	var up: Dictionary = await cloud.call("upload_current_partition")
	_assert(bool(up.get("ok", false)), "G: upload failed: %s" % str(up))
	gs.set("diamonds", 1)
	gs.set("food", 1)
	gs.call("save_resources")
	var restored: Dictionary = cloud.call("restore_payload_to_partition", payload, "commerce_4b")
	_assert(bool(restored.get("ok", false)), "G: restore failed: %s" % str(restored))
	var after := ConfigFile.new()
	_assert(after.load(res_path) == OK, "G: restored resources missing")
	_assert(int(after.get_value("resources", "diamonds", -1)) == 0, "G: restored diamonds must be 0")
	_assert(int(after.get_value("resources", "food", 0)) == 7777, "G: restored food must remain 7777")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "G: authoritative wallet still 0 after cloud")

	# F. local queue cfg true + server false → no paid queue
	print("[COMMERCE 4B] F local queue cfg cannot create paid ownership")
	var q_path: String = str(cs.call("get_queue_path"))
	_assert(str(q_path).contains("saves_smoke_test") or str(q_path).contains("commerce_4b"), "F: construction path not isolated: %s" % q_path)
	if str(q_path).contains("saves_smoke_test") or str(q_path).contains("commerce_4b"):
		var qcfg := ConfigFile.new()
		qcfg.set_value("meta", "permanent_secondary_construction_queue", true)
		qcfg.set_value("meta", "secondary_construction_queue_owned", true)
		qcfg.set_value("jobs", "json", "[]")
		qcfg.save(q_path)
		cs.call("load_construction_state")
		_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "F: local permanent flag must not grant paid construction")
		_assert(int(cs.call("get_construction_queue_limit")) == 1, "F: construction cap stays 1")
	if rs != null:
		var r_path: String = str(rs.call("get_save_path"))
		_assert(str(r_path).contains("saves_smoke_test") or str(r_path).contains("commerce_4b"), "F: research path not isolated: %s" % r_path)
		if str(r_path).contains("saves_smoke_test") or str(r_path).contains("commerce_4b"):
			var rcfg := ConfigFile.new()
			rcfg.set_value("meta", "permanent_secondary_research_queue", true)
			rcfg.set_value("meta", "secondary_research_queue_owned", true)
			rcfg.save(r_path)
			rs.call("load_research_state")
			_assert(not bool(rs.call("has_permanent_secondary_research_queue")), "F: local research flag must not grant paid research")
	if ms != null:
		ms.set("permanent_march_queue_entitlement", true)
		_assert(int(ms.call("get_march_queue_paid_bonus")) == 0, "F: local march flag must not grant paid march")

	# E. server snapshot grants paid queue through reconcile
	print("[COMMERCE 4B] E server entitlement snapshot")
	Commerce.apply_entitlement_snapshot([{
		"entitlement_id": Commerce.ENT_BUILDER_PERM,
		"status": "active",
		"starts_at": 1,
		"expires_at": 0,
	}])
	_assert(bool(cs.call("has_permanent_secondary_construction_queue")), "E: server snapshot must grant paid construction")
	_assert(int(cs.call("get_construction_queue_limit")) == 2, "E: construction cap 2 after server grant")
	Commerce.clear_snapshot()
	_assert(not bool(cs.call("has_permanent_secondary_construction_queue")), "E: clearing snapshot removes paid construction")

	# M. VIP10 local edit cannot create paid-sensitive march capacity
	print("[COMMERCE 4B] M VIP10 fail-closed")
	if ms != null:
		ms.call("begin_smoke_isolation")
		gs.set("vip_level", 10)
		_assert(int(ms.call("get_march_queue_vip_bonus")) == 0, "M: local VIP 10 must not grant march bonus")
		_assert(int(ms.call("get_march_queue_limit")) == 2, "M: march cap stays 2")
		Commerce.apply_server_vip_for_queues(true, 10)
		_assert(int(ms.call("get_march_queue_vip_bonus")) == 1, "M: verified VIP may grant +1")
		Commerce.apply_server_vip_for_queues(false, 10)
		_assert(int(ms.call("get_march_queue_vip_bonus")) == 0, "M: unverified VIP remains fail-closed")
		# Leave MarchState smoke isolation on until process exit so load_marches cannot rewrite live marches.cfg.

	# First small consumable Diamond pack catalog contract
	print("[COMMERCE 4B] diamonds_500 catalog")
	var cat: Dictionary = Commerce.load_commerce_catalog()
	var found_pack := false
	var products: Variant = cat.get("products", [])
	if typeof(products) == TYPE_ARRAY:
		for item: Variant in products:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = item
			if str(row.get("product_id", "")) != "com.crownspire.diamonds_500":
				continue
			found_pack = true
			_assert(str(row.get("iap_product_id", "")) == "com.crownspire.diamonds_500", "catalog iap id")
			_assert(int(row.get("diamond_amount", 0)) == 500, "catalog 500 diamonds")
			_assert(int(row.get("usd_cents", 0)) == 499, "catalog 499 cents")
			_assert(str(row.get("delivery_type", "")) == "DIAMONDS", "catalog DIAMONDS")
			_assert(str(row.get("repeatability", "")) == "consumable", "catalog consumable")
			_assert(bool(row.get("live_store", false)), "catalog live_store")
			_assert(bool(row.get("production_deliverable", false)), "catalog production_deliverable")
	_assert(found_pack, "catalog missing com.crownspire.diamonds_500")
	_assert(Commerce.is_allowed_google_product("com.crownspire.diamonds_500"), "client allows diamonds_500")
	_assert(not Commerce.is_allowed_google_product("com.crownspire.test.diamonds_internal_do_not_ship"), "client blocks TEST SKU")
	_assert(Commerce.get_preferred_google_purchase_option("com.crownspire.diamonds_500") == "buy-500-diamonds", "preferred purchase option")
	_assert(Commerce.GOOGLE_DIAMOND_PACK_500_PURCHASE_OPTION == "buy-500-diamonds", "option constant")
	var list_price: String = Commerce.formatted_price_from_google_details({
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
	_assert(list_price == "US$4.99", "localized price from matching buy-500-diamonds row")
	_assert(Commerce.is_live_store_google_product("com.crownspire.diamonds_500"), "diamonds_500 live_store")
	_assert(not Commerce.is_live_store_google_product("com.crownspire.builder_queue_perm"), "builder perm not live_store")
	_assert(not Commerce.is_live_store_google_product("com.crownspire.test.diamonds_internal_do_not_ship"), "TEST SKU not live_store")

	print("[COMMERCE 4B] session wallet restore/refresh")
	gs.set("diamonds", 500)
	gs.call("save_resources")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": []},
		{"diamonds": 0, "entitlements": []}
	)
	await Commerce.on_session_authenticated()
	var sync_counts: Dictionary = Commerce.get_session_authority_sync_counts()
	_assert(int(sync_counts.get("restore", 0)) >= 1, "session restore invoked")
	_assert(int(sync_counts.get("refresh", 0)) >= 1, "session refresh invoked")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "session refresh server wallet 0")
	_assert(int(gs.get("diamonds")) == 0, "session refresh HUD 0")

	print("[COMMERCE 4B] client cannot mutate beta vouchers")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"beta_vouchers": 5,
		"beta_voucher_available": true,
		"entitlements": [],
	})
	_assert(int(Commerce.get_beta_voucher_balance()) == 5, "server snapshot voucher balance 5")
	_assert(int(Commerce.get_voucher_balance()) == 5, "voucher alias reads the same snapshot")
	var mutate: Dictionary = Commerce.try_set_beta_voucher_balance(999)
	_assert(not bool(mutate.get("ok", true)), "V: client cannot set voucher balance")
	_assert(int(Commerce.get_beta_voucher_balance()) == 5, "V: voucher balance unchanged after client write attempt")
	var self_grant: Dictionary = Commerce.try_grant_beta_voucher_testing()
	_assert(not bool(self_grant.get("ok", true)), "H: client cannot self-grant voucher entitlement")
	_assert(str(self_grant.get("error", "")) == "client_cannot_grant_entitlement", "H: self-grant error")
	_assert(int(Commerce.get_server_voucher_cost("com.crownspire.diamonds_500")) == 499, "catalog peg is 499 without wallet offers")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"vouchers": 5,
		"beta_voucher_available": false,
		"voucher_offers": [{
			"product_id": "com.crownspire.diamonds_500",
			"voucher_cost": 499,
			"voucher_purchasable": true,
		}],
		"entitlements": [],
	})
	_assert(int(Commerce.get_voucher_balance()) == 5, "canonical vouchers field is accepted")
	_assert(int(Commerce.get_server_voucher_cost("com.crownspire.diamonds_500")) == 499, "server voucher cost from offers")
	_assert(Commerce.is_product_voucher_purchasable("com.crownspire.diamonds_500"), "diamonds_500 is voucher-purchasable from snapshot")
	_assert(not Commerce.is_product_voucher_purchasable("entitlement_builder_queue_perm"), "E: non-voucher product is not purchasable")
	_assert(not Commerce.is_beta_voucher_available(), "entitlement remains false")
	Commerce.set_test_process_purchase_override(_voucher_spend_stub)
	var spent: Dictionary = await Commerce.purchase_with_vouchers("com.crownspire.diamonds_500")
	_assert(bool(spent.get("ok", false)), "spend RPC allowed without tester entitlement")
	_assert(str(spent.get("purchase_source", "")) == "BETA_VOUCHER", "spend source remains BETA_VOUCHER")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "J: diamonds from server wallet")
	_assert(int(Commerce.get_voucher_balance()) == 0, "J: vouchers from server wallet")
	_assert(not bool(Commerce.notify_platform_purchase_success({"ok": true}).get("granted", true)), "N: no local grant")
	var nonce1: String = Commerce.generate_opaque_idempotency_key()
	var nonce2: String = Commerce.generate_opaque_idempotency_key()
	_assert(nonce1 != nonce2 and nonce1.length() >= 32 and nonce1.find("-") >= 0, "I: generated nonce is opaque UUID")
	Commerce.clear_voucher_purchase_key("com.crownspire.diamonds_500")
	var held: String = Commerce.peek_or_create_voucher_purchase_key("com.crownspire.diamonds_500")
	_assert(held == Commerce.peek_or_create_voucher_purchase_key("com.crownspire.diamonds_500"), "I: in-flight retry reuses nonce")
	Commerce.clear_voucher_purchase_key("com.crownspire.diamonds_500")
	_assert(Commerce.peek_or_create_voucher_purchase_key("com.crownspire.diamonds_500") != held, "I: later purchase gets a new nonce")
	Commerce.clear_voucher_purchase_key("com.crownspire.diamonds_500")
	Commerce.set_test_process_purchase_override(Callable())
	Commerce.apply_commerce_wallet_payload({"diamonds": 0, "beta_voucher_available": false, "entitlements": []})

	# Bag diamond pack fail-closed
	print("[COMMERCE 4B] bag diamond pack")
	gs.set("diamonds", 50)
	var pack: Dictionary = Commerce.try_convert_bag_diamond_pack()
	_assert(not bool(pack.get("ok", true)), "bag: diamond pack conversion must fail closed")
	_assert(not bool(pack.get("granted", true)), "bag: must not grant")
	_assert(int(gs.get("diamonds")) == 50, "bag: must not mint local diamonds")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "bag: must not mint server diamonds")

	# Alliance Research diamond bypass production gate
	print("[COMMERCE 4B] alliance diamond bypass fail-closed")
	if al != null:
		_assert(str(al.get("_save_path_override")) == "", "alliance: commerce smoke must not enable alliance smoke isolation")
		var bypass: Dictionary = al.call("contribute_to_research", "missing", true)
		_assert(not bool(bypass.get("ok", true)), "alliance: bypass must not succeed")
		var err: String = str(bypass.get("error", ""))
		_assert(
			err.find("server Diamond") >= 0 or err.find("Not in an alliance") >= 0 or err.find("No active") >= 0,
			"alliance: unexpected bypass error: %s" % err
		)

	Commerce.end_smoke_isolation()
	cloud.call("end_smoke_isolation")

	if _fail.is_empty():
		print("[COMMERCE 4B] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[COMMERCE 4B] FAIL: %s" % f)
		quit(1)


func _voucher_spend_stub(kind: String, payload: String) -> Dictionary:
	if kind != "BETA_VOUCHER_BUY":
		return {"ok": false, "error": "unexpected %s %s" % [kind, payload], "granted": false}
	return {
		"ok": true,
		"purchase_source": "BETA_VOUCHER",
		"wallet": {
			"diamonds": 500,
			"vouchers": 0,
			"beta_voucher_available": false,
			"voucher_offers": [{
				"product_id": "com.crownspire.diamonds_500",
				"voucher_cost": 499,
			}],
			"entitlements": [],
		},
	}
