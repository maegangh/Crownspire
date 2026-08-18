extends SceneTree

## Phase 1 Beta Voucher client smoke. No live Play purchase. No live user://.
##   Godot --headless --path <project> -s res://Scripts/dev/beta_voucher_smoke.gd

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
	if gs == null or asp == null or identity == null:
		push_error("[BETA VOUCHER] ABORT — required autoloads missing")
		quit(2)
		return

	asp.call("begin_smoke_isolation")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "beta_voucher")
	asp.call("open_save_context", "beta_voucher", {
		"legacy_owner": "other",
		"legacy_mismatch": true,
		"reload": false,
	})
	Commerce.begin_smoke_isolation()
	gs.call("load_resources")

	print("[BETA VOUCHER] hidden until server approval")
	_assert(not Commerce.is_beta_voucher_available(), "default snapshot is not beta mode")
	_assert(int(Commerce.get_beta_voucher_balance()) == 0, "default voucher balance 0")
	_assert(not bool(Commerce.try_set_beta_voucher_balance(50).get("ok", true)), "no local voucher write")
	_assert(not bool(Commerce.try_grant_beta_voucher_testing().get("ok", true)), "H: client cannot self-grant tester entitlement")

	print("[BETA VOUCHER] redeem + purchase stubs refresh from server payload")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"beta_vouchers": 0,
		"beta_voucher_available": true,
		"beta_voucher_offers": [{
			"product_id": "com.crownspire.diamonds_500",
			"voucher_cost": 5,
		}],
		"entitlements": [],
	})
	_assert(Commerce.is_beta_voucher_available(), "server entitlement enables beta mode")
	_assert(int(Commerce.get_server_voucher_cost("com.crownspire.diamonds_500")) == 5, "client displays server cost")
	Commerce.set_test_process_purchase_override(_voucher_stub)
	var redeemed: Dictionary = await Commerce.redeem_voucher_code("CROWNSPIRE-TEST-VOUCHER-5")
	_assert(bool(redeemed.get("ok", false)), "redeem stub ok")
	_assert(int(Commerce.get_beta_voucher_balance()) == 5, "redeem updates voucher snapshot")
	var bought: Dictionary = await Commerce.purchase_with_vouchers("com.crownspire.diamonds_500", "smoke-1")
	_assert(bool(bought.get("ok", false)), "voucher buy stub ok")
	_assert(str(bought.get("purchase_source", "")) == "BETA_VOUCHER", "buy source BETA_VOUCHER")
	_assert(int(Commerce.get_beta_voucher_balance()) == 0, "buy spends server vouchers")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "buy grants server diamonds")
	_assert(int(gs.get("diamonds")) == 500, "HUD mirror updates from server wallet")

	print("[BETA VOUCHER] shop surfaces redeem UI only in approved mode")
	var shop: Control = ShopScript.new()
	shop.name = "BetaVoucherShopSmoke"
	root.add_child(shop)
	await process_frame
	shop.call("on_open")
	await process_frame
	var panel: Control = shop.find_child("BetaVoucherPanel", true, false)
	_assert(panel != null and panel.visible, "approved mode shows redeem panel")
	_assert(shop.find_child("BetaVoucherRedeemInput", true, false) != null, "redeem input")
	_assert(shop.find_child("VoucherBuyButton_com_crownspire_diamonds_500", true, false) != null, "distinct voucher buy")
	_assert(shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false) != null, "Google Buy remains distinct")
	shop.queue_free()

	Commerce.end_smoke_isolation()
	if _fail.is_empty():
		print("[BETA VOUCHER] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[BETA VOUCHER] FAIL: %s" % f)
		quit(1)


func _voucher_stub(kind: String, payload: String) -> Dictionary:
	if kind == "BETA_VOUCHER_REDEEM":
		return {
			"ok": true,
			"granted_vouchers": 5,
			"wallet": {
				"diamonds": 0,
				"beta_vouchers": 5,
				"beta_voucher_available": true,
				"beta_voucher_offers": [{
					"product_id": "com.crownspire.diamonds_500",
					"voucher_cost": 5,
				}],
				"entitlements": [],
			},
		}
	if kind == "BETA_VOUCHER_BUY":
		return {
			"ok": true,
			"purchase_source": "BETA_VOUCHER",
			"wallet": {
				"diamonds": 500,
				"beta_vouchers": 0,
				"beta_voucher_available": true,
				"beta_voucher_offers": [{
					"product_id": "com.crownspire.diamonds_500",
					"voucher_cost": 5,
				}],
				"entitlements": [],
			},
		}
	return {"ok": false, "error": "unexpected %s %s" % [kind, payload]}
