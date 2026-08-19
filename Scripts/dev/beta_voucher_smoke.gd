extends SceneTree

## Phase 1 Beta Voucher client smoke. No live Play purchase. No live user://.
##   Godot --headless --path <project> -s res://Scripts/dev/beta_voucher_smoke.gd

const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const ShopScript := preload("res://Scripts/UI/ShopScreen.gd")

var _fail: Array[String] = []
var _redeem_calls: int = 0
var _buy_calls: int = 0


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
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	if gs == null or asp == null or identity == null or nc == null:
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
	nc.call("begin_email_auth_smoke_isolation")
	nc.call("begin_session_store_smoke_isolation")
	Commerce.begin_smoke_isolation()
	gs.call("load_resources")

	print("[BETA VOUCHER] hidden until server approval")
	_assert(not Commerce.is_beta_voucher_available(), "default snapshot is not beta mode")
	_assert(int(Commerce.get_beta_voucher_balance()) == 0, "default voucher balance 0")
	_assert(not bool(Commerce.try_set_beta_voucher_balance(50).get("ok", true)), "no local voucher write")
	_assert(not bool(Commerce.try_grant_beta_voucher_testing().get("ok", true)), "H: client cannot self-grant tester entitlement")

	print("[BETA VOUCHER] A shop open with no snapshot is fail-closed")
	var diamonds_before_open: int = int(Commerce.get_authoritative_diamonds())
	var vouchers_before_open: int = int(Commerce.get_beta_voucher_balance())
	var shop: Control = ShopScript.new()
	shop.name = "BetaVoucherShopSmoke"
	root.add_child(shop)
	await process_frame
	shop.call("on_open")
	await process_frame
	await process_frame
	var panel: Control = shop.find_child("BetaVoucherPanel", true, false)
	_assert(panel != null and not panel.visible, "A: no snapshot keeps panel hidden")
	_assert(shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false) != null, "E: Diamond Buy remains")
	var redeem_in: LineEdit = shop.find_child("BetaVoucherRedeemInput", true, false)
	_assert(redeem_in != null and str(redeem_in.text).strip_edges() == "", "I: redeem field not prefilled")
	_assert(_redeem_calls == 0, "I: opening Shop must not redeem")
	_assert(int(Commerce.get_authoritative_diamonds()) == diamonds_before_open, "H: open must not grant Diamonds")
	_assert(int(Commerce.get_beta_voucher_balance()) == vouchers_before_open, "G: open must not mint vouchers")

	print("[BETA VOUCHER] B/D late wallet snapshot shows panel without reopen")
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
	await process_frame
	_assert(panel != null and panel.visible, "B/D: entitled snapshot shows panel while Shop is open")
	_assert(int(Commerce.get_server_voucher_cost("com.crownspire.diamonds_500")) == 5, "client displays server cost")
	var bal: Label = shop.find_child("BetaVoucherBalance", true, false)
	_assert(bal != null and str(bal.text).find("0") >= 0, "B: balance 0 from server")
	_assert(shop.find_child("VoucherBuyButton_com_crownspire_diamonds_500", true, false) != null, "distinct voucher buy")
	_assert(_redeem_calls == 0, "I: snapshot apply does not redeem")

	print("[BETA VOUCHER] C unavailable snapshot hides panel")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"beta_vouchers": 0,
		"beta_voucher_available": false,
		"entitlements": [],
	})
	await process_frame
	_assert(panel != null and not panel.visible, "C: unavailable keeps panel hidden")

	print("[BETA VOUCHER] E wallet refresh failure stays fail-closed")
	Commerce.clear_snapshot()
	shop.call("on_open")
	await process_frame
	await process_frame
	_assert(not Commerce.is_nakama_authenticated(), "E: unauthenticated refresh path")
	_assert(panel != null and not panel.visible, "E: failed refresh does not fabricate voucher UI")
	_assert(shop.find_child("BuyButton_com_crownspire_diamonds_500", true, false) != null, "E: Shop remains usable")
	_assert(shop.visible, "E: Shop still open")

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
	Commerce.set_test_process_purchase_override(_voucher_stub)
	var redeemed: Dictionary = await Commerce.redeem_voucher_code("SMOKE-LOCAL-STUB")
	_assert(bool(redeemed.get("ok", false)), "redeem stub ok")
	_assert(int(Commerce.get_beta_voucher_balance()) == 5, "redeem updates voucher snapshot")
	_assert(_redeem_calls == 1, "redeem stub called once")
	var bought: Dictionary = await Commerce.purchase_with_vouchers("com.crownspire.diamonds_500", "smoke-1")
	_assert(bool(bought.get("ok", false)), "voucher buy stub ok")
	_assert(str(bought.get("purchase_source", "")) == "BETA_VOUCHER", "buy source BETA_VOUCHER")
	_assert(int(Commerce.get_beta_voucher_balance()) == 0, "buy spends server vouchers")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "buy grants server diamonds")
	_assert(int(gs.get("diamonds")) == 500, "HUD mirror updates from server wallet")
	_assert(_buy_calls == 1, "buy stub called once")

	print("[BETA VOUCHER] F account switch drops previous voucher availability")
	nc.call("smoke_set_session_user", "user_a")
	identity.call("on_authenticated", "user_a", "device")
	Commerce.apply_commerce_wallet_payload({
		"diamonds": 0,
		"user_id": "user_a",
		"beta_vouchers": 0,
		"beta_voucher_available": true,
		"beta_voucher_offers": [{
			"product_id": "com.crownspire.diamonds_500",
			"voucher_cost": 5,
		}],
		"entitlements": [],
	})
	await process_frame
	_assert(Commerce.is_beta_voucher_available(), "F: user_a entitled")
	_assert(panel != null and panel.visible, "F: user_a panel visible")
	nc.call("smoke_set_session_user", "user_b")
	identity.call("on_authenticated", "user_b", "email")
	await process_frame
	await process_frame
	_assert(not Commerce.is_beta_voucher_available(), "F: stale user_a voucher must not remain")
	_assert(panel != null and not panel.visible, "F: Shop hid previous user's voucher panel")
	_assert(not bool(Commerce.apply_commerce_wallet_payload({
		"diamonds": 99,
		"user_id": "user_a",
		"beta_voucher_available": true,
		"beta_vouchers": 7,
		"entitlements": [],
	})), "F: stale wallet rejected")
	_assert(not Commerce.is_beta_voucher_available(), "F: rejected stale payload stays hidden")

	print("[BETA VOUCHER] authenticated Shop open refreshes authoritative wallet")
	Commerce.clear_snapshot()
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "user_id": "user_b", "beta_voucher_available": false, "entitlements": []},
		{
			"diamonds": 0,
			"user_id": "user_b",
			"beta_vouchers": 0,
			"beta_voucher_available": true,
			"beta_voucher_offers": [{
				"product_id": "com.crownspire.diamonds_500",
				"voucher_cost": 5,
			}],
			"entitlements": [],
		}
	)
	var refresh_before: int = int(Commerce.get_session_authority_sync_counts().get("refresh", 0))
	shop.call("on_open")
	await process_frame
	await process_frame
	await process_frame
	_assert(int(Commerce.get_session_authority_sync_counts().get("refresh", 0)) > refresh_before, "Shop open refreshes server wallet")
	_assert(Commerce.is_beta_voucher_available(), "open refresh applied entitled snapshot")
	_assert(panel != null and panel.visible, "K: entitled snapshot visible while Shop is open")
	_assert(_redeem_calls == 1, "I: wallet refresh must not redeem")

	shop.queue_free()
	nc.call("end_email_auth_smoke_isolation")
	nc.call("end_session_store_smoke_isolation")
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
		_redeem_calls += 1
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
		_buy_calls += 1
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
