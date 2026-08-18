extends Node

## Android Google Play Billing transport for Crownspire.
## NOT purchase authority. Billing callbacks never grant Diamonds, queues, VIP, or Bag items.
## Server ledger via CommerceAuthority.process_platform_purchase is the only delivery path.
##
## Plugin: GodotGooglePlayBilling 3.2.0 (Godot 4.2+, Play Billing Library 8.3.0).
## Class-based BillingClient API — not the obsolete 1.x singleton examples.
## Desktop/headless: no-op unless the Android singleton exists.
##
## One-time products with a Play purchase option must launch as:
##   _billing.call("purchase", product_id, purchase_option_id)
## Diamonds pack: com.crownspire.diamonds_500 / buy-500-diamonds.
## Do not pass an offer token; plugin 3.2.0 resolves it from purchase_option_id.

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const BillingClientScript := preload("res://addons/GodotGooglePlayBilling/BillingClient.gd")

const PLUGIN_SINGLETON := "GodotGooglePlayBilling"
const PLUGIN_VERSION := "3.2.0"
const LOG_PREFIX := "[CrownspireBilling]"

signal billing_status(status: String, detail: Dictionary)

var _billing: Node = null
var _connected: bool = false
var _product_details: Array = []
var _product_details_query_completed: bool = false
var _last_status: String = ""


func _ready() -> void:
	if not _android_billing_available():
		_last_status = Commerce.STATUS_BILLING_UNAVAILABLE
		return
	_billing = BillingClientScript.new()
	add_child(_billing)
	_billing.connected.connect(_on_connected)
	_billing.disconnected.connect(_on_disconnected)
	_billing.connect_error.connect(_on_connect_error)
	_billing.query_product_details_response.connect(_on_query_product_details)
	_billing.query_purchases_response.connect(_on_query_purchases)
	_billing.on_purchase_updated.connect(_on_purchase_updated)
	_billing.acknowledge_purchase_response.connect(_on_acknowledge_response)
	_billing.consume_purchase_response.connect(_on_consume_response)
	if Commerce.is_nakama_authenticated():
		start_billing()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN and what != NOTIFICATION_APPLICATION_RESUMED:
		return
	if _billing == null or not _connected:
		return
	if not Commerce.is_nakama_authenticated():
		return
	restore_purchases()


func _android_billing_available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton(PLUGIN_SINGLETON)


func start_billing() -> Dictionary:
	if _billing == null:
		return {"ok": false, "status": Commerce.STATUS_BILLING_UNAVAILABLE, "granted": false}
	if not Commerce.is_nakama_authenticated():
		return {"ok": false, "status": Commerce.STATUS_UNAUTHENTICATED, "granted": false}
	var uid: String = _session_user_id()
	if not uid.is_empty() and _billing.has_method("set_obfuscated_account_id"):
		_billing.call("set_obfuscated_account_id", uid.sha256_text())
	_billing.call("start_connection")
	return {"ok": true, "status": "CONNECTING", "granted": false}


func on_session_ready() -> void:
	if _billing == null:
		return
	start_billing()


func query_configured_products() -> Dictionary:
	if _billing == null or not _connected:
		return {"ok": false, "status": Commerce.STATUS_BILLING_UNAVAILABLE, "granted": false}
	var ids: PackedStringArray = Commerce.get_google_query_product_ids()
	_product_details_query_completed = false
	_billing_log("product_query_start", {
		"connected": _connected,
		"product_id": ",".join(ids),
		"product_type": "inapp",
		"details_count": ids.size(),
	})
	_billing.call("query_product_details", ids, 0) ## BillingClient.ProductType.INAPP
	return {"ok": true, "status": "QUERYING", "product_ids": ids, "granted": false}


func is_billing_connected() -> bool:
	return _connected


func has_completed_product_details_query() -> bool:
	return _product_details_query_completed


func is_product_ready(product_id: String) -> bool:
	if not is_billing_connected():
		return false
	if not _product_details_query_completed:
		return false
	var pid: String = product_id.strip_edges()
	if get_product_detail_row(pid).is_empty():
		return false
	return not resolve_purchase_option_id(pid).is_empty()


func get_product_detail_row(product_id: String) -> Dictionary:
	var pid: String = product_id.strip_edges()
	if pid.is_empty():
		return {}
	for item: Variant in _product_details:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var row_id: String = str(row.get("product_id", row.get("id", ""))).strip_edges()
		if row_id.is_empty():
			row_id = str(row.get("productId", "")).strip_edges()
		if row_id == pid:
			return row
	return {}


func get_one_time_offer_rows(row: Dictionary) -> Array:
	var list: Variant = row.get("one_time_purchase_offer_details_list", [])
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		list = row.get("oneTimePurchaseOfferDetailsList", [])
	if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty():
		return list
	var singular: Variant = row.get("one_time_purchase_offer_details", {})
	if typeof(singular) != TYPE_DICTIONARY or (singular as Dictionary).is_empty():
		singular = row.get("oneTimePurchaseOfferDetails", {})
	if typeof(singular) == TYPE_DICTIONARY and not (singular as Dictionary).is_empty():
		return [singular]
	return []


func resolve_purchase_option_id(product_id: String) -> String:
	var row: Dictionary = get_product_detail_row(product_id)
	if row.is_empty():
		return ""
	var preferred: String = Commerce.get_preferred_google_purchase_option(product_id)
	var fallback: String = ""
	for item: Variant in get_one_time_offer_rows(row):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = item
		if not _is_base_one_time_offer(offer):
			continue
		var option_id: String = str(offer.get("purchase_option_id", offer.get("purchaseOptionId", ""))).strip_edges()
		if option_id.is_empty():
			continue
		if not preferred.is_empty() and option_id == preferred:
			return option_id
		if fallback.is_empty():
			fallback = option_id
	if not preferred.is_empty():
		return ""
	return fallback


func resolve_purchase_launch(product_id: String) -> Dictionary:
	var pid: String = product_id.strip_edges()
	var base := {
		"ok": false,
		"granted": false,
		"delivered": false,
		"rpc_sent": false,
		"product_id": pid,
		"purchase_option_id": "",
	}
	if not Commerce.is_allowed_google_product(pid):
		base["status"] = Commerce.STATUS_INVALID_PRODUCT
		return base
	if not _connected:
		base["status"] = Commerce.STATUS_BILLING_NOT_READY
		return base
	if not is_product_ready(pid):
		base["status"] = Commerce.STATUS_PRODUCT_DETAILS_NOT_READY
		return base
	var option_id: String = resolve_purchase_option_id(pid)
	if option_id.is_empty():
		base["status"] = Commerce.STATUS_PRODUCT_DETAILS_NOT_READY
		return base
	base["ok"] = true
	base["status"] = "READY"
	base["purchase_option_id"] = option_id
	return base


func purchase_product(product_id: String) -> Dictionary:
	if not Commerce.is_nakama_authenticated():
		return {"ok": false, "status": Commerce.STATUS_UNAUTHENTICATED, "granted": false, "delivered": false}
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null or not identity.has_method("has_recoverable_identity") or not bool(identity.call("has_recoverable_identity")):
		return {
			"ok": false,
			"status": Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"billing_launched": false,
		}
	var launch: Dictionary = resolve_purchase_launch(product_id)
	if not bool(launch.get("ok", false)):
		_billing_log("purchase_blocked", {
			"connected": _connected,
			"product_id": product_id,
			"product_found": not get_product_detail_row(product_id).is_empty(),
			"purchase_option_id": str(launch.get("purchase_option_id", "")),
			"status": str(launch.get("status", "")),
			"details_count": _product_details.size(),
			"query_completed": _product_details_query_completed,
		})
		return launch
	if _billing == null:
		return {
			"ok": false,
			"status": Commerce.STATUS_BILLING_UNAVAILABLE,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
		}
	var option_id: String = str(launch.get("purchase_option_id", ""))
	_billing_log("purchase_launch", {
		"connected": _connected,
		"product_id": product_id,
		"product_type": "inapp",
		"product_found": true,
		"purchase_option_id": option_id,
		"details_count": _product_details.size(),
		"status": "LAUNCHING",
	})
	var result: Dictionary = _billing.call("purchase", product_id, option_id)
	var code: int = int(result.get("response_code", -999))
	var debug_message: String = str(result.get("debug_message", ""))
	_billing_log("purchase_launch_result", {
		"connected": _connected,
		"product_id": product_id,
		"purchase_option_id": option_id,
		"response_code": code,
		"debug_message": debug_message,
		"status": "BILLING_FLOW_LAUNCHED" if code == Commerce.BILLING_CODE_OK else Commerce.STATUS_FAILED,
	})
	if result.is_empty() or code != Commerce.BILLING_CODE_OK:
		if code == Commerce.BILLING_CODE_USER_CANCELED:
			return {"ok": false, "status": Commerce.STATUS_CANCELED, "granted": false, "delivered": false, "rpc_sent": false}
		if code == Commerce.BILLING_CODE_ITEM_ALREADY_OWNED:
			restore_purchases()
			return {"ok": true, "status": "ALREADY_OWNED_QUERYING", "granted": false, "delivered": false, "rpc_sent": false}
		return {
			"ok": false,
			"status": Commerce.STATUS_FAILED,
			"granted": false,
			"delivered": false,
			"rpc_sent": false,
			"billing_code": code,
			"debug_message": debug_message,
		}
	return {"ok": true, "status": "BILLING_FLOW_LAUNCHED", "granted": false, "delivered": false}


func restore_purchases() -> Dictionary:
	if not Commerce.is_nakama_authenticated():
		return {"ok": false, "status": Commerce.STATUS_UNAUTHENTICATED, "granted": false}
	if _billing == null or not _connected:
		return {"ok": false, "status": Commerce.STATUS_BILLING_UNAVAILABLE, "granted": false}
	_billing.call("query_purchases", 0) ## INAPP
	return {"ok": true, "status": "QUERYING_PURCHASES", "granted": false}


func get_product_details() -> Array:
	return _product_details.duplicate(true)


func get_formatted_price_for_product(product_id: String) -> String:
	var row: Dictionary = get_product_detail_row(product_id)
	if row.is_empty():
		return ""
	return Commerce.formatted_price_from_google_details(row)


func get_last_status() -> String:
	return _last_status


func _on_connected() -> void:
	_connected = true
	_last_status = "CONNECTED"
	_billing_log("connected", {"connected": true, "status": "CONNECTED"})
	query_configured_products()
	restore_purchases()
	_emit_status("CONNECTED", {})


func _on_disconnected() -> void:
	_connected = false
	_product_details_query_completed = false
	_last_status = "DISCONNECTED"
	_billing_log("disconnected", {"connected": false, "status": "DISCONNECTED"})
	_emit_status("DISCONNECTED", {})


func _on_connect_error(response_code: int, debug_message: String) -> void:
	_connected = false
	_product_details_query_completed = false
	_last_status = Commerce.STATUS_FAILED
	_billing_log("connect_error", {
		"connected": false,
		"response_code": response_code,
		"debug_message": debug_message,
		"status": Commerce.STATUS_FAILED,
	})
	_emit_status(Commerce.STATUS_FAILED, {"billing_code": response_code, "debug_message": debug_message, "granted": false})


func _on_query_product_details(response: Dictionary) -> void:
	_product_details_query_completed = true
	var code: int = int(response.get("response_code", -1))
	if code == Commerce.BILLING_CODE_OK:
		var details: Variant = response.get("product_details", [])
		if typeof(details) == TYPE_ARRAY:
			_product_details = details
	var target: String = Commerce.GOOGLE_DIAMOND_PACK_500
	var found: bool = not get_product_detail_row(target).is_empty()
	_billing_log("product_query_result", {
		"connected": _connected,
		"product_id": target,
		"product_type": "inapp",
		"details_count": _product_details.size(),
		"product_found": found,
		"purchase_option_id": resolve_purchase_option_id(target),
		"response_code": code,
		"debug_message": str(response.get("debug_message", "")),
		"unfetched_ids": _unfetched_product_ids(response),
		"query_completed": true,
		"status": "PRODUCT_DETAILS",
	})
	_emit_status("PRODUCT_DETAILS", {
		"response_code": code,
		"debug_message": str(response.get("debug_message", "")),
		"details_count": _product_details.size(),
		"product_found": found,
		"product_details": _product_details.duplicate(true),
	})


func _on_query_purchases(response: Dictionary) -> void:
	var ingested: Dictionary = await Commerce.ingest_google_purchase_updated(response)
	_maybe_finish_google_purchase(ingested)
	var retries: Array = await Commerce.retry_pending_google_purchases()
	for row: Variant in retries:
		if typeof(row) == TYPE_DICTIONARY:
			_maybe_finish_google_purchase(row)
	_emit_status(str(ingested.get("status", "QUERY_PURCHASES")), ingested)


func _on_purchase_updated(response: Dictionary) -> void:
	## Google callback is NEVER authority. CommerceAuthority will not grant locally.
	_billing_log("purchase_updated", {
		"connected": _connected,
		"response_code": int(response.get("response_code", -1)),
		"debug_message": str(response.get("debug_message", "")),
		"status": "PURCHASE_UPDATED",
	})
	var ingested: Dictionary = await Commerce.ingest_google_purchase_updated(response)
	_maybe_finish_google_purchase(ingested)
	_last_status = str(ingested.get("status", ""))
	_emit_status(_last_status, ingested)


func _maybe_finish_google_purchase(ingested: Dictionary) -> void:
	if _billing == null:
		return
	var token: String = str(ingested.get("purchase_token", "")).strip_edges()
	if token.is_empty():
		return
	## Consumable Diamond packs: consume only after server DELIVERED.
	## Durable queue SKUs: acknowledge after server DELIVERED. Never consume them.
	## Failed/pending/unverified purchases must not be finished here.
	if bool(ingested.get("consume", false)):
		_billing.call("consume_purchase", token)
		return
	if not bool(ingested.get("acknowledge", false)):
		return
	_billing.call("acknowledge_purchase", token)


func _on_acknowledge_response(response: Dictionary) -> void:
	_emit_status("ACKNOWLEDGED", response)


func _on_consume_response(response: Dictionary) -> void:
	## Consume confirms Google can sell the consumable again. It is not a Diamond grant.
	_emit_status("CONSUMED", response)


func _session_user_id() -> String:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		return ""
	return str(nc.call("get_user_id")).strip_edges()


func _emit_status(status: String, detail: Dictionary) -> void:
	var payload: Dictionary = detail.duplicate(true)
	payload["granted"] = false
	if not payload.has("delivered"):
		payload["delivered"] = status == Commerce.STATUS_DELIVERED or status == Commerce.STATUS_ALREADY_DELIVERED
	billing_status.emit(status, payload)


func _is_base_one_time_offer(offer: Dictionary) -> bool:
	## Plugin 3.2.0: base one-time row has a null/empty offer_id. Discounted offers have an offer_id.
	var offer_id: Variant = offer.get("offer_id", offer.get("offerId", null))
	if offer_id == null:
		return true
	return str(offer_id).strip_edges().is_empty()


func _unfetched_product_ids(response: Dictionary) -> String:
	var raw: Variant = response.get("unfetched_products", [])
	if typeof(raw) != TYPE_ARRAY:
		return ""
	var ids: PackedStringArray = PackedStringArray()
	for item: Variant in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var pid: String = str((item as Dictionary).get("product_id", "")).strip_edges()
		if pid.is_empty():
			pid = str((item as Dictionary).get("productId", "")).strip_edges()
		if not pid.is_empty() and not ids.has(pid):
			ids.append(pid)
	return ",".join(ids)


func apply_smoke_billing_state(
	details: Array,
	connected: bool,
	query_completed: bool = true,
	billing_stub: Node = null
) -> void:
	if not Commerce.is_smoke_isolation():
		return
	_connected = connected
	_product_details = details
	_product_details_query_completed = query_completed
	if billing_stub != null:
		_billing = billing_stub


func _billing_log(stage: String, fields: Dictionary = {}) -> void:
	var allow := [
		"connected",
		"product_id",
		"product_type",
		"details_count",
		"product_found",
		"purchase_option_id",
		"response_code",
		"debug_message",
		"status",
		"query_completed",
		"unfetched_ids",
	]
	var parts: PackedStringArray = PackedStringArray()
	parts.append(LOG_PREFIX)
	parts.append(stage)
	for key: String in allow:
		if fields.has(key):
			parts.append("%s=%s" % [key, str(fields[key])])
	print(" ".join(parts))
