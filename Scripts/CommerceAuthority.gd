extends RefCounted

## CLIENT COORDINATOR / MIRROR. NOT PURCHASE AUTHORITY.
## Production paid flow: Platform Store → receipt → Nakama RPC validation
## → server ledger → idempotent delivery → this snapshot → UI mirrors.
##
## A platform purchase callback MUST NOT grant Diamonds or paid entitlements.
## Do not treat GameState.diamonds, resources.cfg, or queue cfg files as authority.
##
## Not an autoload. Preload / class_name. Do not add to project.godot.

const CATALOG_PATH := "res://data/commerce_products.json"
const ENT_BUILDER_30D := "entitlement_builder_queue_30d"
const ENT_BUILDER_PERM := "entitlement_builder_queue_perm"
const ENT_RESEARCH_PERM := "entitlement_research_queue_perm"
const ENT_MARCH_PERM := "entitlement_march_queue_perm"

static var _smoke: bool = false
static var _has_snapshot: bool = false
static var _wallet_balance: int = 0
static var _beta_vouchers: int = 0
static var _beta_voucher_available: bool = false
static var _beta_voucher_offers: Array = []
static var _beta_topup: Dictionary = {}
static var _voucher_inflight_keys: Dictionary = {}
static var _last_voucher_idempotency_key: String = ""
static var _entitlements: Dictionary = {}
static var _vip_verified: bool = false
static var _vip_level_server: int = 0
static var _authority_sync_token: int = 0
static var _session_restore_count: int = 0
static var _session_refresh_count: int = 0
static var _has_test_session_payloads: bool = false
static var _test_session_restore_wallet: Dictionary = {}
static var _test_session_refresh_wallet: Dictionary = {}
static var _wallet_owner_user_id: String = ""
static var _signal_bus: Object = null

signal wallet_snapshot_changed


static func get_signal_bus() -> Object:
	if _signal_bus == null:
		_signal_bus = new()
	return _signal_bus


static func _emit_wallet_snapshot_changed() -> void:
	var bus: Object = get_signal_bus()
	if bus.has_signal("wallet_snapshot_changed"):
		bus.emit_signal("wallet_snapshot_changed")


static func begin_smoke_isolation() -> void:
	_smoke = true
	_test_process_purchase = Callable()
	_has_test_session_payloads = false
	_test_session_restore_wallet = {}
	_test_session_refresh_wallet = {}
	_authority_sync_token = 0
	_session_restore_count = 0
	_session_refresh_count = 0
	_wallet_owner_user_id = ""
	_voucher_inflight_keys.clear()
	_last_voucher_idempotency_key = ""
	clear_snapshot()


static func end_smoke_isolation() -> void:
	_test_process_purchase = Callable()
	_has_test_session_payloads = false
	_test_session_restore_wallet = {}
	_test_session_refresh_wallet = {}
	clear_snapshot()
	_smoke = false


static func is_smoke_isolation() -> bool:
	return _smoke


static func clear_snapshot() -> void:
	_has_snapshot = false
	_wallet_balance = 0
	_beta_vouchers = 0
	_beta_voucher_available = false
	_beta_voucher_offers.clear()
	_beta_topup.clear()
	_entitlements.clear()
	_vip_verified = false
	_vip_level_server = 0
	_wallet_owner_user_id = ""
	_voucher_inflight_keys.clear()
	_last_voucher_idempotency_key = ""


static func has_server_snapshot() -> bool:
	return _has_snapshot


static func apply_wallet_snapshot(balance: int) -> void:
	_has_snapshot = true
	_wallet_balance = maxi(0, int(balance))
	_sync_diamond_mirror()


static func apply_entitlement_snapshot(rows: Array) -> void:
	_has_snapshot = true
	_entitlements.clear()
	for item: Variant in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = item
		var eid: String = str(rec.get("entitlement_id", "")).strip_edges()
		if eid.is_empty():
			continue
		_entitlements[eid] = {
			"entitlement_id": eid,
			"status": str(rec.get("status", "")),
			"starts_at": int(rec.get("starts_at", 0)),
			"expires_at": int(rec.get("expires_at", 0)),
		}


static func apply_commerce_wallet_payload(wallet: Dictionary) -> bool:
	var expected: String = _current_auth_user_id()
	var payload_uid: String = str(wallet.get("user_id", "")).strip_edges()
	if payload_uid != "" and expected != "" and payload_uid != expected:
		return false
	apply_wallet_snapshot(int(wallet.get("diamonds", 0)))
	if wallet.has("vouchers"):
		_beta_vouchers = maxi(0, int(wallet.get("vouchers", 0)))
	else:
		_beta_vouchers = maxi(0, int(wallet.get("beta_vouchers", 0)))
	_beta_voucher_available = bool(wallet.get("beta_voucher_available", false))
	var offers: Variant = wallet.get("voucher_offers", null)
	if typeof(offers) != TYPE_ARRAY:
		offers = wallet.get("beta_voucher_offers", [])
	_beta_voucher_offers = offers if typeof(offers) == TYPE_ARRAY else []
	var topup: Variant = wallet.get("beta_topup", {})
	_beta_topup = topup if typeof(topup) == TYPE_DICTIONARY else {}
	var ents: Variant = wallet.get("entitlements", [])
	if typeof(ents) == TYPE_ARRAY:
		apply_entitlement_snapshot(ents)
	_wallet_owner_user_id = expected
	_emit_wallet_snapshot_changed()
	return true


static func get_wallet_owner_user_id() -> String:
	return _wallet_owner_user_id


static func get_authoritative_diamonds() -> int:
	if not _has_snapshot:
		return 0
	return _wallet_balance


static func is_beta_voucher_available() -> bool:
	if not _has_snapshot or not _beta_voucher_available:
		return false
	return _wallet_belongs_to_current_user()


static func _wallet_belongs_to_current_user() -> bool:
	var owner: String = _wallet_owner_user_id.strip_edges()
	var current: String = _current_auth_user_id()
	if owner == "" and current == "":
		return true
	if owner == "" or current == "":
		return false
	return owner == current


static func get_beta_voucher_balance() -> int:
	if not _has_snapshot:
		return 0
	return _beta_vouchers


static func get_voucher_balance() -> int:
	return get_beta_voucher_balance()


static func get_beta_topup_snapshot() -> Dictionary:
	return _beta_topup.duplicate(true)


static func get_server_voucher_cost(product_id: String) -> int:
	var pid: String = product_id.strip_edges()
	for item: Variant in _beta_voucher_offers:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if str(row.get("product_id", "")).strip_edges() == pid or str(row.get("iap_product_id", "")).strip_edges() == pid:
			if row.has("voucher_purchasable") and not bool(row.get("voucher_purchasable", true)):
				return 0
			if row.has("beta_voucher_purchasable") and not bool(row.get("beta_voucher_purchasable", true)):
				return 0
			return maxi(0, int(row.get("voucher_cost", 0)))
	return 0


static func is_product_voucher_purchasable(product_id: String) -> bool:
	return get_server_voucher_cost(product_id) > 0


static func generate_opaque_idempotency_key() -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(16)
	if bytes.size() < 16:
		bytes.resize(16)
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80
	var hex := ""
	for i in range(16):
		hex += "%02x" % (int(bytes[i]) & 0xff)
		if i == 3 or i == 5 or i == 7 or i == 9:
			hex += "-"
	return hex


static func peek_or_create_voucher_purchase_key(product_id: String, explicit_key: String = "") -> String:
	var pid: String = product_id.strip_edges()
	var explicit: String = explicit_key.strip_edges()
	if not explicit.is_empty():
		_voucher_inflight_keys[pid] = explicit
		_last_voucher_idempotency_key = explicit
		return explicit
	if pid.is_empty():
		return ""
	if _voucher_inflight_keys.has(pid):
		var existing: String = str(_voucher_inflight_keys[pid]).strip_edges()
		if not existing.is_empty():
			_last_voucher_idempotency_key = existing
			return existing
	var created: String = generate_opaque_idempotency_key()
	_voucher_inflight_keys[pid] = created
	_last_voucher_idempotency_key = created
	return created


static func get_inflight_voucher_purchase_key(product_id: String) -> String:
	var pid: String = product_id.strip_edges()
	if not _voucher_inflight_keys.has(pid):
		return ""
	return str(_voucher_inflight_keys[pid]).strip_edges()


static func get_last_voucher_idempotency_key() -> String:
	return _last_voucher_idempotency_key


static func clear_voucher_purchase_key(product_id: String) -> void:
	var pid: String = product_id.strip_edges()
	if _voucher_inflight_keys.has(pid):
		_voucher_inflight_keys.erase(pid)


## Client cannot mint, spend, or correct Beta Vouchers locally.
static func try_set_beta_voucher_balance(_amount: int) -> Dictionary:
	return {
		"ok": false,
		"error": "client_cannot_mutate_voucher_balance",
		"beta_vouchers": get_beta_voucher_balance(),
	}


## Client cannot self-assign tester authorization.
static func try_grant_beta_voucher_testing() -> Dictionary:
	return {
		"ok": false,
		"error": "client_cannot_grant_entitlement",
		"beta_voucher_available": is_beta_voucher_available(),
	}


static func has_paid_entitlement(entitlement_id: String) -> bool:
	if not _has_snapshot:
		return false
	if not _entitlements.has(entitlement_id):
		return false
	var rec: Dictionary = _entitlements[entitlement_id]
	if str(rec.get("status", "")) != "active":
		return false
	var exp: int = int(rec.get("expires_at", 0))
	if exp > 0 and exp <= int(Time.get_unix_time_from_system()):
		return false
	return true


static func has_any_active_entitlement() -> bool:
	if not _has_snapshot:
		return false
	for eid: Variant in _entitlements.keys():
		if has_paid_entitlement(str(eid)):
			return true
	return false


static func has_pending_purchase_ledger() -> bool:
	if _smoke:
		return false
	return not list_pending_google_receipts().is_empty()


static func get_timed_entitlement_expires(entitlement_id: String) -> int:
	if not has_paid_entitlement(entitlement_id):
		return 0
	return int((_entitlements[entitlement_id] as Dictionary).get("expires_at", 0))


## Batch 4B: no server VIP pipeline. Paid-sensitive VIP10 march bonus stays fail-closed.
static func is_vip_verified_for_queues() -> bool:
	return _vip_verified and _vip_level_server >= 10


static func apply_server_vip_for_queues(verified: bool, level: int) -> void:
	_has_snapshot = true
	_vip_verified = verified
	_vip_level_server = level


## CLIENT CALLBACK IS NEVER AUTHORITY. Zero delivery.
static func notify_platform_purchase_success(_payload: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": "client_callback_not_authority",
		"delivered": false,
		"granted": false,
	}


## Fail-closed Bag conversion. A client-invented stack must not mint Diamonds.
static func try_convert_bag_diamond_pack() -> Dictionary:
	return {
		"ok": false,
		"error": "bag_possession_authority_required",
		"granted": false,
	}


static func _sync_diamond_mirror() -> void:
	if not _has_snapshot:
		return
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return
	var gs: Node = (tree as SceneTree).root.get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.set("diamonds", _wallet_balance)
	if gs.has_method("save_resources"):
		gs.call("save_resources")
	if gs.has_signal("resources_changed"):
		gs.emit_signal("resources_changed")


## ---------------------------------------------------------------------------
## Batch 4C — Android Google Play receipt handoff (no local paid grants)
## ---------------------------------------------------------------------------

const PLATFORM_GOOGLE := "GOOGLE"
const PLATFORM_APPLE := "APPLE"
const RPC_PROCESS_PURCHASE := "crownspire_commerce_process_purchase"
const RPC_RESTORE := "crownspire_commerce_restore"
const RPC_GET_WALLET := "crownspire_commerce_get_wallet"
const RPC_REDEEM_VOUCHER := "crownspire_commerce_redeem_voucher_code"
const RPC_PURCHASE_WITH_VOUCHERS := "crownspire_commerce_purchase_with_vouchers"
const RPC_GET_BETA_TOPUP := "crownspire_commerce_get_beta_topup"
const RPC_CLAIM_BETA_TOPUP := "crownspire_commerce_claim_beta_topup_milestone"
const PENDING_FILE := "iap_pending.cfg"
const GOOGLE_PRIMARY_TEST_PRODUCT := "com.crownspire.builder_queue_perm"
const GOOGLE_DIAMOND_PACK_500 := "com.crownspire.diamonds_500"
const GOOGLE_DIAMOND_PACK_500_PURCHASE_OPTION := "buy-500-diamonds"
const GOOGLE_PURCHASE_STATE_PURCHASED := 1
const GOOGLE_PURCHASE_STATE_PENDING := 2
const BILLING_CODE_OK := 0
const BILLING_CODE_USER_CANCELED := 1
const BILLING_CODE_ITEM_ALREADY_OWNED := 7

const STATUS_CANCELED := "CANCELED"
const STATUS_PENDING := "PENDING"
const STATUS_FAILED := "FAILED"
const STATUS_UNAUTHENTICATED := "UNAUTHENTICATED"
const STATUS_INVALID_PRODUCT := "INVALID_PRODUCT"
const STATUS_VALIDATION_PENDING := "PURCHASED_SERVER_VALIDATION_PENDING"
const STATUS_SERVER_REJECTED := "SERVER_REJECTED"
const STATUS_DELIVERED := "DELIVERED"
const STATUS_ALREADY_DELIVERED := "ALREADY_DELIVERED"
const STATUS_BILLING_UNAVAILABLE := "BILLING_UNAVAILABLE"
const STATUS_BILLING_NOT_READY := "BILLING_NOT_READY"
const STATUS_PRODUCT_DETAILS_NOT_READY := "PRODUCT_DETAILS_NOT_READY"
const STATUS_ACCOUNT_PROTECTION_REQUIRED := "ACCOUNT_PROTECTION_REQUIRED"

## Smoke-only RPC stub. Production never sets this except begin_smoke_isolation callers.
static var _test_process_purchase: Callable = Callable()
static var _billing_node: Node = null


static func set_test_process_purchase_override(cb: Callable) -> void:
	if not _smoke:
		return
	_test_process_purchase = cb


static func is_nakama_authenticated() -> bool:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return false
	var nc: Node = (tree as SceneTree).root.get_node_or_null("/root/NakamaConnection")
	return nc != null and bool(nc.call("is_authenticated"))


static func _current_auth_user_id() -> String:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return ""
	var root: Node = (tree as SceneTree).root
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("get_user_id"):
		var uid: String = str(nc.call("get_user_id")).strip_edges()
		if uid != "":
			return uid
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_method("get_auth_user_id"):
		return str(identity.call("get_auth_user_id")).strip_edges()
	return ""


static func _account_has_recoverable_identity() -> bool:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return false
	var identity: Node = (tree as SceneTree).root.get_node_or_null("/root/AccountIdentityState")
	if identity == null or not identity.has_method("has_recoverable_identity"):
		return false
	return bool(identity.call("has_recoverable_identity"))


static func _apply_wallet_for_expected_user(wallet: Dictionary, expected_user_id: String) -> bool:
	var current: String = _current_auth_user_id()
	if expected_user_id != "" and current != "" and expected_user_id != current:
		return false
	var stamped: Dictionary = wallet.duplicate(true)
	if expected_user_id != "" and str(stamped.get("user_id", "")).strip_edges() == "":
		stamped["user_id"] = expected_user_id
	return apply_commerce_wallet_payload(stamped)


static func load_commerce_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func get_google_query_product_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var cat: Dictionary = load_commerce_catalog()
	var products: Variant = cat.get("products", [])
	if typeof(products) != TYPE_ARRAY:
		return out
	for item: Variant in products:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if str(row.get("product_type", "")) == "TEST_ONLY":
			continue
		if bool(row.get("production_deliverable", true)) == false:
			continue
		var ids: Variant = row.get("platform_product_ids", {})
		var gid: String = ""
		if typeof(ids) == TYPE_DICTIONARY:
			gid = str((ids as Dictionary).get("GOOGLE", "")).strip_edges()
		if gid.is_empty():
			gid = str(row.get("iap_product_id", "")).strip_edges()
		if gid.is_empty():
			continue
		if not out.has(gid):
			out.append(gid)
	return out


static func is_allowed_google_product(product_id: String) -> bool:
	var pid: String = product_id.strip_edges()
	if pid.is_empty():
		return false
	if pid.find("test.diamonds_internal_do_not_ship") >= 0:
		return false
	return get_google_query_product_ids().has(pid)


static func get_live_store_catalog_rows() -> Array:
	var out: Array = []
	var cat: Dictionary = load_commerce_catalog()
	var products: Variant = cat.get("products", [])
	if typeof(products) != TYPE_ARRAY:
		return out
	for item: Variant in products:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if str(row.get("product_type", "")) == "TEST_ONLY":
			continue
		if bool(row.get("production_deliverable", true)) == false:
			continue
		if not bool(row.get("live_store", false)):
			continue
		out.append(row)
	return out


static func get_live_store_google_product_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item: Variant in get_live_store_catalog_rows():
		var row: Dictionary = item
		var ids: Variant = row.get("platform_product_ids", {})
		var gid: String = ""
		if typeof(ids) == TYPE_DICTIONARY:
			gid = str((ids as Dictionary).get("GOOGLE", "")).strip_edges()
		if gid.is_empty():
			gid = str(row.get("iap_product_id", "")).strip_edges()
		if gid.is_empty():
			continue
		if not out.has(gid):
			out.append(gid)
	return out


static func is_live_store_google_product(product_id: String) -> bool:
	return get_live_store_google_product_ids().has(product_id.strip_edges())


static func get_preferred_google_purchase_option(product_id: String) -> String:
	if product_id.strip_edges() == GOOGLE_DIAMOND_PACK_500:
		return GOOGLE_DIAMOND_PACK_500_PURCHASE_OPTION
	return ""


static func get_one_time_offer_rows(details: Dictionary) -> Array:
	var list: Variant = details.get("one_time_purchase_offer_details_list", [])
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		list = details.get("oneTimePurchaseOfferDetailsList", [])
	if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty():
		return list
	var singular: Variant = details.get("one_time_purchase_offer_details", {})
	if typeof(singular) != TYPE_DICTIONARY or (singular as Dictionary).is_empty():
		singular = details.get("oneTimePurchaseOfferDetails", {})
	if typeof(singular) == TYPE_DICTIONARY and not (singular as Dictionary).is_empty():
		return [singular]
	return []


static func formatted_price_from_google_details(details: Dictionary) -> String:
	var pid: String = str(details.get("product_id", details.get("productId", ""))).strip_edges()
	var preferred: String = get_preferred_google_purchase_option(pid)
	var fallback: String = ""
	for item: Variant in get_one_time_offer_rows(details):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = item
		var nested: String = str(offer.get("formatted_price", "")).strip_edges()
		if nested.is_empty():
			nested = str(offer.get("formattedPrice", "")).strip_edges()
		if nested.is_empty():
			continue
		var option_id: String = str(offer.get("purchase_option_id", offer.get("purchaseOptionId", ""))).strip_edges()
		if not preferred.is_empty() and option_id == preferred:
			return nested
		if fallback.is_empty():
			fallback = nested
	if not fallback.is_empty():
		return fallback
	var flat: String = str(details.get("formatted_price", "")).strip_edges()
	if flat.is_empty():
		flat = str(details.get("formattedPrice", "")).strip_edges()
	return flat


static func get_android_billing_node() -> Node:
	return ensure_android_billing_node()


static func is_android_billing_connected() -> bool:
	var node: Node = get_android_billing_node()
	if node == null or not node.has_method("is_billing_connected"):
		return false
	return bool(node.call("is_billing_connected"))


static func has_android_product_details_query_completed() -> bool:
	var node: Node = get_android_billing_node()
	if node == null or not node.has_method("has_completed_product_details_query"):
		return false
	return bool(node.call("has_completed_product_details_query"))


static func is_android_product_ready(product_id: String) -> bool:
	var node: Node = get_android_billing_node()
	if node == null or not node.has_method("is_product_ready"):
		return false
	return bool(node.call("is_product_ready", product_id))


static func is_consumable_google_product(product_id: String) -> bool:
	var pid: String = product_id.strip_edges()
	if pid.is_empty():
		return false
	var cat: Dictionary = load_commerce_catalog()
	var products: Variant = cat.get("products", [])
	if typeof(products) != TYPE_ARRAY:
		return false
	for item: Variant in products:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var ids: Variant = row.get("platform_product_ids", {})
		var gid: String = ""
		if typeof(ids) == TYPE_DICTIONARY:
			gid = str((ids as Dictionary).get("GOOGLE", "")).strip_edges()
		if gid.is_empty():
			gid = str(row.get("iap_product_id", "")).strip_edges()
		if gid == pid or str(row.get("product_id", "")).strip_edges() == pid:
			return str(row.get("repeatability", "")) == "consumable"
	return false


static func google_receipt_from_purchase(purchase: Dictionary) -> String:
	var original: String = str(purchase.get("original_json", "")).strip_edges()
	if not original.is_empty():
		return original
	var product_ids: PackedStringArray = PackedStringArray()
	var raw_ids: Variant = purchase.get("product_ids", [])
	if typeof(raw_ids) == TYPE_PACKED_STRING_ARRAY:
		product_ids = raw_ids
	elif typeof(raw_ids) == TYPE_ARRAY:
		for v: Variant in raw_ids:
			product_ids.append(str(v))
	var product_id: String = product_ids[0] if product_ids.size() > 0 else ""
	var rebuilt := {
		"orderId": str(purchase.get("order_id", "")),
		"packageName": str(purchase.get("package_name", "")),
		"productId": product_id,
		"purchaseTime": int(purchase.get("purchase_time", 0)),
		"purchaseState": 0,
		"purchaseToken": str(purchase.get("purchase_token", "")),
		"quantity": int(purchase.get("quantity", 1)),
		"acknowledged": bool(purchase.get("is_acknowledged", false)),
	}
	return JSON.stringify(rebuilt)


## Billing callback / query result ingestion. NEVER grants locally.
static func ingest_google_purchase_updated(response: Dictionary) -> Dictionary:
	var code: int = int(response.get("response_code", -999))
	if code == BILLING_CODE_USER_CANCELED:
		return {
			"ok": false,
			"status": STATUS_CANCELED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"acknowledge": false,
			"consume": false,
		}
	if code != BILLING_CODE_OK:
		return {
			"ok": false,
			"status": STATUS_FAILED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"acknowledge": false,
			"consume": false,
			"billing_code": code,
			"debug_message": str(response.get("debug_message", "")),
		}
	var purchases: Array = []
	var raw: Variant = response.get("purchases", [])
	if typeof(raw) == TYPE_ARRAY:
		purchases = raw
	if purchases.is_empty():
		return {
			"ok": false,
			"status": STATUS_FAILED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"acknowledge": false,
			"consume": false,
		}
	var last: Dictionary = {}
	for item: Variant in purchases:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		last = await ingest_google_billing_purchase(item)
	return last


static func ingest_google_billing_purchase(purchase: Dictionary) -> Dictionary:
	var base := {
		"granted": false,
		"delivered": false,
		"rpc_sent": false,
		"acknowledge": false,
		"consume": false,
		"purchase_token": str(purchase.get("purchase_token", "")),
	}
	var pstate: int = int(purchase.get("purchase_state", 0))
	if pstate == GOOGLE_PURCHASE_STATE_PENDING:
		base["ok"] = false
		base["status"] = STATUS_PENDING
		return base
	if pstate != GOOGLE_PURCHASE_STATE_PURCHASED:
		base["ok"] = false
		base["status"] = STATUS_FAILED
		return base
	if not _purchase_has_allowed_google_product(purchase):
		base["ok"] = false
		base["status"] = STATUS_INVALID_PRODUCT
		return base
	if not is_nakama_authenticated() and not _smoke:
		remember_pending_google_purchase(purchase)
		base["ok"] = false
		base["status"] = STATUS_UNAUTHENTICATED
		return base
	var receipt: String = google_receipt_from_purchase(purchase)
	if receipt.strip_edges().is_empty() or str(purchase.get("purchase_token", "")).strip_edges().is_empty():
		base["ok"] = false
		base["status"] = STATUS_FAILED
		base["error"] = "missing_receipt"
		return base
	remember_pending_google_purchase(purchase)
	base["status"] = STATUS_VALIDATION_PENDING
	var server: Dictionary = await process_platform_purchase(PLATFORM_GOOGLE, receipt)
	base["rpc_sent"] = true
	base["server"] = server
	if _server_process_delivered(server):
		_apply_server_process_result(server)
		var already: bool = _server_already_delivered(server)
		base["ok"] = true
		base["delivered"] = true
		base["status"] = STATUS_ALREADY_DELIVERED if already else STATUS_DELIVERED
		## Finish Google only after the server ledger accepted the transaction.
		## Consumable Diamond packs: consume so the player can buy again.
		## Durable queue SKUs: acknowledge and never consume.
		## Consumption is not a grant and must not run on failed/pending/unverified rows.
		var finish: Dictionary = _google_finish_flags(purchase, false)
		base["consume"] = bool(finish.get("consume", false))
		base["acknowledge"] = bool(finish.get("acknowledge", false))
		clear_pending_google_purchase(str(purchase.get("purchase_token", "")))
		return base
	base["ok"] = false
	base["status"] = STATUS_SERVER_REJECTED
	base["error"] = str(server.get("error", "validation_failed"))
	return base


static func process_platform_purchase(platform: String, receipt: String) -> Dictionary:
	if _smoke and _test_process_purchase.is_valid():
		var stub: Variant = _test_process_purchase.call(platform, receipt)
		if typeof(stub) == TYPE_DICTIONARY:
			return stub
	if not is_nakama_authenticated():
		return {
			"ok": false,
			"error": "not_authenticated",
			"status": STATUS_UNAUTHENTICATED,
			"delivered": false,
			"granted": false,
		}
	return await _rpc_commerce(RPC_PROCESS_PURCHASE, {
		"platform": platform,
		"receipt": receipt,
	})


static func restore_server_entitlements() -> Dictionary:
	_session_restore_count += 1
	var expected: String = _current_auth_user_id()
	if _smoke and _has_test_session_payloads:
		if not _apply_wallet_for_expected_user(_test_session_restore_wallet, expected):
			return {"ok": false, "error": "stale_wallet_user", "applied": false, "status": "SMOKE"}
		return {"ok": true, "status": "SMOKE", "wallet": _test_session_restore_wallet}
	if not is_nakama_authenticated() and not _smoke:
		return {"ok": false, "error": "not_authenticated", "status": STATUS_UNAUTHENTICATED}
	if _smoke and _test_process_purchase.is_valid():
		return {"ok": true, "status": "SMOKE"}
	var restored: Dictionary = await _rpc_commerce(RPC_RESTORE, {})
	if expected != _current_auth_user_id():
		return {"ok": false, "error": "stale_wallet_user", "applied": false}
	if bool(restored.get("ok", false)):
		var wallet: Variant = restored.get("wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			_apply_wallet_for_expected_user(wallet, expected)
	return restored


static func refresh_server_wallet() -> Dictionary:
	_session_refresh_count += 1
	var expected: String = _current_auth_user_id()
	if _smoke and _has_test_session_payloads:
		if not _apply_wallet_for_expected_user(_test_session_refresh_wallet, expected):
			return {"ok": false, "error": "stale_wallet_user", "applied": false}
		return {"ok": true, "wallet": _test_session_refresh_wallet}
	if not is_nakama_authenticated():
		return {"ok": false, "error": "not_authenticated"}
	var res: Dictionary = await _rpc_commerce(RPC_GET_WALLET, {})
	if expected != _current_auth_user_id():
		return {"ok": false, "error": "stale_wallet_user", "applied": false}
	if bool(res.get("ok", false)):
		var wallet: Variant = res.get("wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			_apply_wallet_for_expected_user(wallet, expected)
	return res


static func redeem_voucher_code(code: String) -> Dictionary:
	var trimmed: String = code.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "error": "empty_code"}
	if _smoke and _test_process_purchase.is_valid():
		var stub: Variant = _test_process_purchase.call("BETA_VOUCHER_REDEEM", trimmed)
		if typeof(stub) == TYPE_DICTIONARY:
			var row: Dictionary = stub
			if bool(row.get("ok", false)):
				var wallet: Variant = row.get("wallet", {})
				if typeof(wallet) == TYPE_DICTIONARY:
					apply_commerce_wallet_payload(wallet)
			return row
	if not is_nakama_authenticated():
		return {"ok": false, "error": "not_authenticated"}
	var res: Dictionary = await _rpc_commerce(RPC_REDEEM_VOUCHER, {"code": trimmed})
	if bool(res.get("ok", false)):
		var wallet: Variant = res.get("wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			apply_commerce_wallet_payload(wallet)
	return res


static func purchase_with_vouchers(product_id: String, idempotency_key: String = "") -> Dictionary:
	var pid: String = product_id.strip_edges()
	if pid.is_empty():
		return {"ok": false, "error": "product_required", "granted": false}
	var key: String = peek_or_create_voucher_purchase_key(pid, idempotency_key)
	if key.is_empty():
		return {"ok": false, "error": "idempotency_key_required", "granted": false}
	if _smoke and _test_process_purchase.is_valid():
		var stub: Variant = _test_process_purchase.call("BETA_VOUCHER_BUY", pid)
		if typeof(stub) == TYPE_DICTIONARY:
			var row: Dictionary = stub
			if bool(row.get("ok", false)):
				var wallet: Variant = row.get("wallet", {})
				if typeof(wallet) == TYPE_DICTIONARY:
					apply_commerce_wallet_payload(wallet)
			return row
	if not is_nakama_authenticated():
		return {"ok": false, "error": "not_authenticated", "granted": false}
	var res: Dictionary = await _rpc_commerce(RPC_PURCHASE_WITH_VOUCHERS, {
		"product_id": pid,
		"idempotency_key": key,
	})
	if bool(res.get("ok", false)):
		var delivered_wallet: Variant = res.get("wallet", {})
		if typeof(delivered_wallet) == TYPE_DICTIONARY:
			apply_commerce_wallet_payload(delivered_wallet)
	return res


static func refresh_beta_topup() -> Dictionary:
	if _smoke and _has_test_session_payloads:
		return {"ok": true, "beta_topup": _beta_topup}
	if not is_nakama_authenticated():
		return {"ok": false, "error": "not_authenticated"}
	var res: Dictionary = await _rpc_commerce(RPC_GET_BETA_TOPUP, {})
	if bool(res.get("ok", false)):
		var wallet: Variant = res.get("wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			apply_commerce_wallet_payload(wallet)
		var topup: Variant = res.get("beta_topup", {})
		if typeof(topup) == TYPE_DICTIONARY:
			_beta_topup = topup
	return res


static func claim_beta_topup_milestone(milestone_id: String) -> Dictionary:
	var mid: String = milestone_id.strip_edges()
	if mid.is_empty():
		return {"ok": false, "error": "milestone_required"}
	if not is_nakama_authenticated() and not _smoke:
		return {"ok": false, "error": "not_authenticated"}
	if _smoke and _test_process_purchase.is_valid():
		var stub: Variant = _test_process_purchase.call("BETA_TOPUP_CLAIM", mid)
		if typeof(stub) == TYPE_DICTIONARY:
			var row: Dictionary = stub
			if bool(row.get("ok", false)):
				var wallet: Variant = row.get("wallet", {})
				if typeof(wallet) == TYPE_DICTIONARY:
					apply_commerce_wallet_payload(wallet)
			return row
	var res: Dictionary = await _rpc_commerce(RPC_CLAIM_BETA_TOPUP, {"milestone_id": mid})
	if bool(res.get("ok", false)):
		var wallet: Variant = res.get("wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			apply_commerce_wallet_payload(wallet)
	return res


static func set_test_session_authority_payloads(restore_wallet: Dictionary, refresh_wallet: Dictionary) -> void:
	if not _smoke:
		return
	_has_test_session_payloads = true
	_test_session_restore_wallet = restore_wallet.duplicate(true)
	_test_session_refresh_wallet = refresh_wallet.duplicate(true)


static func get_session_authority_sync_counts() -> Dictionary:
	return {
		"restore": _session_restore_count,
		"refresh": _session_refresh_count,
	}


static func on_session_authenticated() -> void:
	_authority_sync_token += 1
	var token: int = _authority_sync_token
	if OS.get_name() == "Android":
		var node: Node = ensure_android_billing_node()
		if node != null and node.has_method("on_session_ready"):
			node.call("on_session_ready")
	await _run_session_authority_sync(token)


static func _run_session_authority_sync(token: int) -> void:
	await restore_server_entitlements()
	if token != _authority_sync_token:
		return
	await refresh_server_wallet()


static func purchase_android_product(product_id: String) -> Dictionary:
	if not is_allowed_google_product(product_id):
		return {
			"ok": false,
			"status": STATUS_INVALID_PRODUCT,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
		}
	if not is_nakama_authenticated():
		return {
			"ok": false,
			"status": STATUS_UNAUTHENTICATED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
		}
	if not _account_has_recoverable_identity():
		return {
			"ok": false,
			"status": STATUS_ACCOUNT_PROTECTION_REQUIRED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"billing_launched": false,
		}
	var node: Node = ensure_android_billing_node()
	if node == null:
		return {
			"ok": false,
			"status": STATUS_BILLING_UNAVAILABLE,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
		}
	return node.call("purchase_product", product_id)


static func query_android_products() -> Dictionary:
	if not is_nakama_authenticated():
		return {"ok": false, "status": STATUS_UNAUTHENTICATED, "granted": false}
	var node: Node = ensure_android_billing_node()
	if node == null:
		return {"ok": false, "status": STATUS_BILLING_UNAVAILABLE, "granted": false}
	return node.call("query_configured_products")


static func restore_android_purchases() -> Dictionary:
	if not is_nakama_authenticated():
		return {"ok": false, "status": STATUS_UNAUTHENTICATED, "granted": false}
	var node: Node = ensure_android_billing_node()
	if node == null:
		return {"ok": false, "status": STATUS_BILLING_UNAVAILABLE, "granted": false}
	return node.call("restore_purchases")


static func ensure_android_billing_node() -> Node:
	if OS.get_name() != "Android":
		return null
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	if _billing_node != null and is_instance_valid(_billing_node):
		return _billing_node
	var script: Resource = load("res://Scripts/AndroidPlayBillingCoordinator.gd")
	if script == null:
		return null
	_billing_node = (script as GDScript).new()
	_billing_node.name = "AndroidPlayBillingCoordinator"
	(tree as SceneTree).root.add_child(_billing_node)
	return _billing_node


static func get_google_product_details(product_id: String) -> Dictionary:
	var pid: String = product_id.strip_edges()
	if pid.is_empty():
		return {}
	var node: Node = ensure_android_billing_node()
	if node == null or not node.has_method("get_product_details"):
		return {}
	var rows: Variant = node.call("get_product_details")
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for item: Variant in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var rid: String = str(row.get("product_id", "")).strip_edges()
		if rid.is_empty():
			rid = str(row.get("productId", "")).strip_edges()
		if rid == pid:
			return row
	return {}


static func remember_pending_google_purchase(purchase: Dictionary) -> void:
	var token: String = str(purchase.get("purchase_token", "")).strip_edges()
	if token.is_empty():
		return
	var cfg := ConfigFile.new()
	var path: String = _pending_path()
	cfg.load(path)
	cfg.set_value(token, "platform", PLATFORM_GOOGLE)
	cfg.set_value(token, "receipt", google_receipt_from_purchase(purchase))
	cfg.set_value(token, "product_ids", JSON.stringify(purchase.get("product_ids", [])))
	cfg.set_value(token, "is_acknowledged", bool(purchase.get("is_acknowledged", false)))
	cfg.set_value(token, "updated_unix", int(Time.get_unix_time_from_system()))
	cfg.save(path)


static func clear_pending_google_purchase(purchase_token: String) -> void:
	var token: String = purchase_token.strip_edges()
	if token.is_empty():
		return
	var path: String = _pending_path()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if cfg.has_section(token):
		cfg.erase_section(token)
		cfg.save(path)


static func list_pending_google_receipts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg := ConfigFile.new()
	if cfg.load(_pending_path()) != OK:
		return out
	for section: String in cfg.get_sections():
		out.append({
			"purchase_token": section,
			"platform": str(cfg.get_value(section, "platform", PLATFORM_GOOGLE)),
			"receipt": str(cfg.get_value(section, "receipt", "")),
			"is_acknowledged": bool(cfg.get_value(section, "is_acknowledged", false)),
		})
	return out


static func retry_pending_google_purchases() -> Array:
	var results: Array = []
	for row: Dictionary in list_pending_google_receipts():
		var receipt: String = str(row.get("receipt", ""))
		if receipt.is_empty():
			continue
		var server: Dictionary = await process_platform_purchase(PLATFORM_GOOGLE, receipt)
		var wrap := {
			"purchase_token": str(row.get("purchase_token", "")),
			"server": server,
			"granted": false,
			"acknowledge": false,
			"consume": false,
		}
		if _server_process_delivered(server):
			_apply_server_process_result(server)
			var finish: Dictionary = _google_finish_flags({
				"product_ids": PackedStringArray(),
				"original_json": receipt,
				"is_acknowledged": bool(row.get("is_acknowledged", false)),
			}, bool(row.get("is_acknowledged", false)))
			wrap["consume"] = bool(finish.get("consume", false))
			wrap["acknowledge"] = bool(finish.get("acknowledge", false))
			wrap["delivered"] = true
			clear_pending_google_purchase(str(row.get("purchase_token", "")))
		results.append(wrap)
	return results


static func _pending_path() -> String:
	var tree := Engine.get_main_loop()
	if tree != null and tree is SceneTree:
		var asp: Node = (tree as SceneTree).root.get_node_or_null("/root/AccountSavePaths")
		if asp != null:
			return str(asp.call("path_for", PENDING_FILE))
	return "user://iap_pending.cfg"


static func _apply_server_process_result(server: Dictionary) -> void:
	var wallet: Variant = server.get("wallet", {})
	if typeof(wallet) == TYPE_DICTIONARY:
		apply_commerce_wallet_payload(wallet)


static func _server_process_delivered(server: Dictionary) -> bool:
	if not bool(server.get("ok", false)):
		return false
	var purchases: Variant = server.get("purchases", [])
	if typeof(purchases) != TYPE_ARRAY or (purchases as Array).is_empty():
		return typeof(server.get("wallet", null)) == TYPE_DICTIONARY
	for item: Variant in purchases:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var status: String = str((item as Dictionary).get("delivery_status", ""))
		if status == "DELIVERED":
			return true
	return false


static func _google_finish_flags(purchase: Dictionary, already_acknowledged: bool) -> Dictionary:
	var consumable := false
	for pid: String in _purchase_google_product_ids(purchase):
		if is_consumable_google_product(pid):
			consumable = true
			break
	if not consumable:
		var receipt: String = str(purchase.get("original_json", "")).strip_edges()
		if receipt.is_empty():
			receipt = str(purchase.get("receipt", "")).strip_edges()
		if not receipt.is_empty():
			var parsed: Variant = JSON.parse_string(receipt)
			if typeof(parsed) == TYPE_DICTIONARY:
				consumable = is_consumable_google_product(str((parsed as Dictionary).get("productId", "")))
	if consumable:
		return {"consume": true, "acknowledge": false}
	var acked: bool = already_acknowledged or bool(purchase.get("is_acknowledged", false))
	return {"consume": false, "acknowledge": not acked}


static func _server_already_delivered(server: Dictionary) -> bool:
	var purchases: Variant = server.get("purchases", [])
	if typeof(purchases) != TYPE_ARRAY:
		return false
	for item: Variant in purchases:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = item
		if bool(rec.get("seen_before", false)):
			return true
	return false


static func _purchase_has_allowed_google_product(purchase: Dictionary) -> bool:
	for pid: String in _purchase_google_product_ids(purchase):
		if is_allowed_google_product(pid):
			return true
	return false


static func _purchase_google_product_ids(purchase: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var raw_ids: Variant = purchase.get("product_ids", [])
	if typeof(raw_ids) == TYPE_PACKED_STRING_ARRAY:
		out = raw_ids
	elif typeof(raw_ids) == TYPE_ARRAY:
		for v: Variant in raw_ids:
			out.append(str(v))
	if out.is_empty():
		var original: String = str(purchase.get("original_json", "")).strip_edges()
		if not original.is_empty():
			var parsed: Variant = JSON.parse_string(original)
			if typeof(parsed) == TYPE_DICTIONARY:
				var pid: String = str((parsed as Dictionary).get("productId", "")).strip_edges()
				if not pid.is_empty():
					out.append(pid)
	return out


static func _rpc_commerce(rpc_id: String, payload: Dictionary) -> Dictionary:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return {"ok": false, "error": "no_tree", "delivered": false, "granted": false}
	var nc: Node = (tree as SceneTree).root.get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return {"ok": false, "error": "not_authenticated", "status": STATUS_UNAUTHENTICATED, "delivered": false, "granted": false}
	var client: Variant = nc.call("get_client")
	var session: Variant = nc.call("get_session")
	if client == null or session == null:
		return {"ok": false, "error": "missing_session", "delivered": false, "granted": false}
	var raw: Variant = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if raw == null or raw.is_exception():
		var reason: String = "RPC failed"
		if raw != null and raw.get_exception() != null:
			reason = str(raw.get_exception().message)
		return {"ok": false, "error": reason, "delivered": false, "granted": false}
	var payload_str: String = str(raw.payload) if ("payload" in raw) else ""
	if payload_str.strip_edges() == "":
		return {"ok": true}
	var parsed: Variant = JSON.parse_string(payload_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid RPC response", "delivered": false, "granted": false}
	return parsed
