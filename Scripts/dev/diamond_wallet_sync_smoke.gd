extends SceneTree

## Wallet authority + stale-user apply smoke. No live purchase. No production grant.
##   Godot --headless --path <project> -s res://Scripts/dev/diamond_wallet_sync_smoke.gd

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
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	if gs == null or identity == null or asp == null:
		push_error("[WALLET SYNC] ABORT — required autoloads missing")
		quit(2)
		return

	identity.call("begin_smoke_isolation")
	asp.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "wallet_a")
	asp.call("open_save_context", "wallet_a", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	if nc != null and nc.has_method("begin_email_auth_smoke_isolation"):
		nc.call("begin_email_auth_smoke_isolation")
		nc.call("smoke_set_session_user", "wallet_a")
	identity.call("on_authenticated", "wallet_a", "device")
	Commerce.begin_smoke_isolation()

	print("[WALLET SYNC] A session refresh is Diamond authority")
	gs.set("diamonds", 500)
	if gs.has_method("save_resources"):
		gs.call("save_resources")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 40, "entitlements": [], "user_id": "wallet_a"},
		{"diamonds": 40, "entitlements": [], "user_id": "wallet_a"}
	)
	await Commerce.on_session_authenticated()
	var counts: Dictionary = Commerce.get_session_authority_sync_counts()
	_assert(int(counts.get("restore", 0)) >= 1, "A: restore_server_entitlements missing")
	_assert(int(counts.get("refresh", 0)) >= 1, "A: refresh_server_wallet missing")
	_assert(int(Commerce.get_authoritative_diamonds()) == 40, "A: server wallet not applied")
	_assert(int(gs.get("diamonds")) == 40, "A: local mirror not updated from server")

	print("[WALLET SYNC] B stale previous-user wallet cannot apply")
	if nc != null:
		nc.call("smoke_set_session_user", "wallet_b")
	identity.call("on_authenticated", "wallet_b", "device")
	var stale: bool = Commerce.apply_commerce_wallet_payload({
		"diamonds": 999,
		"user_id": "wallet_a",
		"entitlements": [],
	})
	_assert(not stale, "B: stale A payload applied to B")
	_assert(int(Commerce.get_authoritative_diamonds()) != 999, "B: wallets merged")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 777, "entitlements": [], "user_id": "wallet_a"},
		{"diamonds": 777, "entitlements": [], "user_id": "wallet_a"}
	)
	var refresh: Dictionary = await Commerce.refresh_server_wallet()
	_assert(str(refresh.get("error", "")) == "stale_wallet_user" or not bool(refresh.get("ok", true)), "B: stale refresh applied")
	_assert(int(Commerce.get_authoritative_diamonds()) != 777, "B: refresh merged A into B")

	print("[WALLET SYNC] C current user wallet still applies")
	_assert(bool(Commerce.apply_commerce_wallet_payload({"diamonds": 12, "user_id": "wallet_b"})), "C: current wallet rejected")
	_assert(int(Commerce.get_authoritative_diamonds()) == 12, "C: current wallet not 12")
	_assert(Commerce.get_wallet_owner_user_id() == "wallet_b" or Commerce.get_wallet_owner_user_id() == "", "C: owner %s" % Commerce.get_wallet_owner_user_id())

	print("[WALLET SYNC] D client cannot mint Diamonds during account ops")
	_assert(not bool(Commerce.notify_platform_purchase_success({"ok": true}).get("granted", true)), "D: client callback granted")
	if gs.has_method("add_diamonds"):
		gs.call("add_diamonds", 50)
		_assert(int(Commerce.get_authoritative_diamonds()) == 12, "D: add_diamonds changed authority")

	Commerce.end_smoke_isolation()
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")
	if nc != null and nc.has_method("end_email_auth_smoke_isolation"):
		nc.call("end_email_auth_smoke_isolation")

	if _fail.is_empty():
		print("[WALLET SYNC] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[WALLET SYNC] FAIL: %s" % f)
		quit(1)
