extends Node

## Android Google Play Billing transport for Crownspire.
## NOT purchase authority. Billing callbacks never grant Diamonds, queues, VIP, or Bag items.
## Server ledger via CommerceAuthority.process_platform_purchase is the only delivery path.
##
## Plugin: GodotGooglePlayBilling 3.2.0 (Godot 4.2+, Play Billing Library 8.3.0).
## Class-based BillingClient API — not the obsolete 1.x singleton examples.
## Desktop/headless: no-op unless the Android singleton exists.

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const BillingClientScript := preload("res://addons/GodotGooglePlayBilling/BillingClient.gd")

const PLUGIN_SINGLETON := "GodotGooglePlayBilling"
const PLUGIN_VERSION := "3.2.0"

signal billing_status(status: String, detail: Dictionary)

var _billing: Node = null
var _connected: bool = false
var _product_details: Array = []
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
	_billing.call("query_product_details", ids, 0) ## BillingClient.ProductType.INAPP
	return {"ok": true, "status": "QUERYING", "product_ids": ids, "granted": false}


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
	if not Commerce.is_allowed_google_product(product_id):
		return {"ok": false, "status": Commerce.STATUS_INVALID_PRODUCT, "granted": false, "delivered": false}
	if _billing == null or not _connected:
		return {"ok": false, "status": Commerce.STATUS_BILLING_UNAVAILABLE, "granted": false, "delivered": false}
	var result: Dictionary = _billing.call("purchase", product_id)
	var code: int = int(result.get("response_code", -999))
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
			"debug_message": str(result.get("debug_message", "")),
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


func get_last_status() -> String:
	return _last_status


func _on_connected() -> void:
	_connected = true
	_last_status = "CONNECTED"
	query_configured_products()
	restore_purchases()
	_emit_status("CONNECTED", {})


func _on_disconnected() -> void:
	_connected = false
	_last_status = "DISCONNECTED"
	_emit_status("DISCONNECTED", {})


func _on_connect_error(response_code: int, debug_message: String) -> void:
	_connected = false
	_last_status = Commerce.STATUS_FAILED
	_emit_status(Commerce.STATUS_FAILED, {"billing_code": response_code, "debug_message": debug_message, "granted": false})


func _on_query_product_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) == Commerce.BILLING_CODE_OK:
		var details: Variant = response.get("product_details", [])
		if typeof(details) == TYPE_ARRAY:
			_product_details = details
	_emit_status("PRODUCT_DETAILS", response)


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
