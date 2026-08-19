extends SceneTree

## Public Player ID display / copy / account-switch smokes. No live login or purchase.
##   Godot --headless --path <project> -s res://Scripts/dev/player_identity_display_smoke.gd

const FULL_A := "4cbd705c-42a3-41ad-a312-7181f995765f"
const FULL_B := "b91e33aa-1111-2222-3333-444444444444"
const SHORT_A := "4cbd705c"
const SHORT_B := "b91e33aa"
const PUBLIC_A := "A2B3-C4D5"
const PUBLIC_B := "H7JK-MNPQ"
const SMOKE_PASSWORD := "P4SmokePass_NeverPersist_9x!"
const SMOKE_EMAIL := "player.id.display@crownspire.smoke.test"

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _label_has_secret(root: Node) -> bool:
	for n: Node in root.find_children("*", "", true, false):
		if n is Label:
			var t: String = str((n as Label).text)
			if t.find("auth_token") >= 0 or t.find("refresh_token") >= 0:
				return true
			if t.find("eyJ") >= 0 or t.find("password=") >= 0:
				return true
		if n is LineEdit:
			var nm: String = str(n.name).to_lower()
			if nm.find("token") >= 0:
				return true
	return false


func _run() -> void:
	await process_frame
	await process_frame

	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	if nc == null or identity == null or asp == null or cloud == null:
		push_error("[PLAYER IDENTITY] ABORT — required autoloads missing")
		quit(2)
		return

	identity.call("begin_smoke_isolation")
	asp.call("begin_smoke_isolation")
	asp.call("enable_smoke_bootstrap_hold", true)
	cloud.call("begin_smoke_isolation")
	nc.call("begin_email_auth_smoke_isolation")
	nc.call("begin_session_store_smoke_isolation")

	print("[PLAYER IDENTITY] L loading never shows UUID prefix")
	identity.call("claim_local_saves_for_user", FULL_A)
	asp.call("open_save_context", FULL_A, {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	nc.call("smoke_set_session_user", FULL_A)
	identity.call("on_authenticated", FULL_A, "device")
	_assert(str(identity.call("get_current_player_id")) == FULL_A, "L: internal user_id remains UUID")
	_assert(str(identity.call("get_public_player_id")) == "", "L: public ID empty while loading")
	_assert(str(identity.call("get_public_player_id_status")) == "LOADING", "L: status LOADING")
	_assert(str(identity.call("get_player_id_copy_payload")) == "", "L: copy empty while loading")
	var ProfileScript: GDScript = load("res://Scripts/UI/PlayerProfileScreen.gd") as GDScript
	var PanelScript: GDScript = load("res://Scripts/UI/AccountSettingsPanel.gd") as GDScript
	_assert(ProfileScript != null and PanelScript != null, "L: profile/account scripts failed to load")
	if ProfileScript == null or PanelScript == null:
		push_error("[PLAYER IDENTITY] ABORT — UI scripts failed to load")
		quit(2)
		return
	var profile: Control = ProfileScript.new()
	profile.name = "PlayerIdentityProfileSmoke"
	root.add_child(profile)
	profile.call("apply_self_profile_for_display", {
		"user_id": "stale-should-not-win",
		"display_name": "Commander",
		"alliance_tag": "",
		"power": 12,
		"vip_level": 0,
	})
	await process_frame
	await process_frame
	var loading_lbl: Label = profile.find_child("PlayerIdLabel", true, false)
	_assert(loading_lbl != null, "L: PlayerIdLabel missing")
	_assert(loading_lbl != null and str(loading_lbl.text).find("Loading") >= 0, "L: loading text missing")
	_assert(loading_lbl == null or str(loading_lbl.text).find(SHORT_A) < 0, "L: UUID prefix shown as fallback")
	_assert(loading_lbl == null or str(loading_lbl.text).find(FULL_A) < 0, "L: full UUID visible while loading")
	var loading_copy: Button = profile.find_child("PlayerIdCopyButton", true, false)
	_assert(loading_copy != null and loading_copy.disabled, "L: copy enabled before public ID ready")

	print("[PLAYER IDENTITY] A profile Chief Name + public Player ID")
	identity.call("smoke_set_public_player_id_for_user", FULL_A, PUBLIC_A)
	identity.call("retry_public_player_id")
	await process_frame
	await process_frame
	_assert(str(identity.call("get_public_player_id")) == PUBLIC_A, "A: public ID ready")
	_assert(str(identity.call("get_player_id_copy_payload")) == PUBLIC_A, "A: copy payload is public ID")
	_assert(str(identity.call("get_player_id_copy_payload")) != FULL_A, "A: copy payload must not be UUID")
	_assert(str(identity.call("get_player_id_copy_payload")) != SHORT_A, "A: copy payload must not be UUID prefix")
	var chief: Label = profile.find_child("ChiefNameLabel", true, false)
	_assert(chief != null, "A: ChiefNameLabel missing")
	_assert(chief != null and str(chief.text).strip_edges() != "", "A: Chief Name missing")
	_assert(chief == null or str(chief.text).find("@") < 0, "A: Chief Name must not be email")
	var id_lbl: Label = profile.find_child("PlayerIdLabel", true, false)
	_assert(id_lbl != null, "A: PlayerIdLabel missing")
	_assert(id_lbl != null and str(id_lbl.text).find(PUBLIC_A) >= 0, "A: public Player ID missing")
	_assert(id_lbl == null or str(id_lbl.text).find(SHORT_A) < 0, "A: UUID prefix visible on profile")
	_assert(id_lbl == null or str(id_lbl.text).find(FULL_A) < 0, "A: full user_id visible on profile")
	_assert(id_lbl == null or str(id_lbl.text).to_lower().find("nakama") < 0, "A: technical Nakama wording")
	_assert(id_lbl == null or str(id_lbl.text).to_lower().find("uuid") < 0, "A: technical UUID wording")

	print("[PLAYER IDENTITY] B copy uses public Player ID")
	var copy_btn: Button = profile.find_child("PlayerIdCopyButton", true, false)
	_assert(copy_btn != null, "B: Copy button missing")
	_assert(copy_btn == null or not copy_btn.disabled, "B: Copy disabled after public ID ready")
	if copy_btn != null:
		copy_btn.emit_signal("pressed")
	await process_frame
	var copied: Label = profile.find_child("PlayerIdCopiedLabel", true, false)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_assert(copied != null and copied.visible, "B: copy confirmation hidden")
		_assert(copied != null and str(copied.text).find("Player ID copied") >= 0, "B: confirmation text")
		_assert(str(DisplayServer.clipboard_get()) == PUBLIC_A, "B: clipboard was not the public Player ID")
		_assert(str(DisplayServer.clipboard_get()) != FULL_A, "B: clipboard used Nakama UUID")
		_assert(str(DisplayServer.clipboard_get()) != SHORT_A, "B: clipboard used UUID prefix")
	else:
		_assert(copied == null or not copied.visible or str(copied.text).find(FULL_A) < 0, "B: UUID shown when clipboard unavailable")

	print("[PLAYER IDENTITY] C guest Player ID visible in Account Settings")
	_assert(str(identity.call("get_account_kind")) == "GUEST", "C: expected guest")
	var panel: Control = PanelScript.new()
	panel.name = "PlayerIdentityAccountSmoke"
	root.add_child(panel)
	await process_frame
	await process_frame
	var guest_id: Label = panel.find_child("PlayerIdLabel", true, false)
	_assert(guest_id != null and str(guest_id.text).find(PUBLIC_A) >= 0, "C: guest public Player ID missing")
	_assert(guest_id == null or str(guest_id.text).find(SHORT_A) < 0, "C: guest UUID prefix visible")
	_assert(panel.find_child("PlayerIdCopyButton", true, false) != null, "C: guest Copy missing")
	_assert(not _label_has_secret(panel), "C: secrets in guest account UI")
	_assert(not _label_has_secret(profile), "C: secrets in profile UI")

	print("[PLAYER IDENTITY] D Secure Account preserves public Player ID")
	var before_secure: String = str(identity.call("get_public_player_id"))
	var secure: Dictionary = await identity.call("secure_guest_with_email", SMOKE_EMAIL, SMOKE_PASSWORD, SMOKE_PASSWORD)
	_assert(bool(secure.get("ok", false)), "D: secure failed: %s" % str(secure.get("error", "")))
	_assert(str(identity.call("get_current_player_id")) == FULL_A, "D: internal user_id changed on secure")
	_assert(str(identity.call("get_public_player_id")) == before_secure, "D: public Player ID changed on secure")
	await process_frame
	await process_frame
	var secured_id: Label = panel.find_child("PlayerIdLabel", true, false)
	_assert(secured_id != null and str(secured_id.text).find(PUBLIC_A) >= 0, "D: settings public ID after secure")

	print("[PLAYER IDENTITY] M/E account switch clears stale public ID")
	identity.call("smoke_set_public_player_id_for_user", FULL_B, PUBLIC_B)
	nc.call("smoke_set_session_user", FULL_B)
	identity.call("on_authenticated", FULL_B, "email")
	await process_frame
	await process_frame
	_assert(str(identity.call("get_current_player_id")) == FULL_B, "E: live internal id after switch")
	_assert(str(identity.call("get_public_player_id")) == PUBLIC_B, "E: public ID after switch")
	_assert(str(identity.call("get_player_id_copy_payload")) == PUBLIC_B, "E: copy payload after switch")
	var switched_profile: Label = profile.find_child("PlayerIdLabel", true, false)
	_assert(switched_profile != null and str(switched_profile.text).find(PUBLIC_B) >= 0, "E: profile still shows previous public ID")
	_assert(switched_profile == null or str(switched_profile.text).find(PUBLIC_A) < 0, "E: stale public ID still visible on profile")
	_assert(switched_profile == null or str(switched_profile.text).find(SHORT_A) < 0, "E: UUID prefix visible after switch")
	_assert(switched_profile == null or str(switched_profile.text).find(SHORT_B) < 0, "E: new UUID prefix used as Player ID")
	var switched_settings: Label = panel.find_child("PlayerIdLabel", true, false)
	_assert(switched_settings != null and str(switched_settings.text).find(PUBLIC_B) >= 0, "E: settings still shows previous Player ID")

	print("[PLAYER IDENTITY] N/F Google same-user link preserves public Player ID")
	var google_same: Dictionary = identity.call("smoke_link_provider_same_user", "GOOGLE", FULL_B, FULL_B)
	_assert(bool(google_same.get("ok", false)), "F: same-user Google smoke failed")
	_assert(str(identity.call("get_current_player_id")) == FULL_B, "F: internal user_id changed on Google link")
	_assert(str(identity.call("get_public_player_id")) == PUBLIC_B, "F: public Player ID changed on Google link")

	print("[PLAYER IDENTITY] G copy payload is public ID after switch")
	_assert(str(identity.call("get_player_id_copy_payload")) == PUBLIC_B, "G: copy payload stale")
	_assert(str(identity.call("get_player_id_copy_payload")) != FULL_B, "G: copy payload leaked UUID")
	_assert(switched_profile == null or str(switched_profile.text).find(FULL_B) < 0, "G: full id leaked after switch")

	print("[PLAYER IDENTITY] unavailable state")
	identity.call("smoke_mark_public_player_id_unavailable", true)
	identity.call("retry_public_player_id")
	await process_frame
	await process_frame
	var unavailable_lbl: Label = profile.find_child("PlayerIdLabel", true, false)
	_assert(str(identity.call("get_public_player_id_status")) == "UNAVAILABLE", "unavailable: status")
	_assert(unavailable_lbl != null and str(unavailable_lbl.text).to_lower().find("unavailable") >= 0, "unavailable: label")
	_assert(unavailable_lbl == null or str(unavailable_lbl.text).find(SHORT_B) < 0, "unavailable: UUID prefix fallback")
	identity.call("smoke_mark_public_player_id_unavailable", false)
	identity.call("retry_public_player_id")
	await process_frame
	await process_frame

	print("[PLAYER IDENTITY] H security")
	_assert(not _label_has_secret(profile), "H: profile leaked tokens")
	_assert(not _label_has_secret(panel), "H: settings leaked tokens")
	_assert(str(identity.call("get_player_id_copy_payload")).find("eyJ") < 0, "H: copy payload looks like a JWT")
	_assert(str(identity.call("format_public_player_id", "a2b3 c4d5")) == PUBLIC_A, "H: client normalize/format")
	_assert(str(identity.call("normalize_public_player_id", "A2B3-C4D0")) == "", "H: reject 0")

	cloud.call("end_smoke_isolation")
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")
	nc.call("end_email_auth_smoke_isolation")
	nc.call("end_session_store_smoke_isolation")
	profile.queue_free()
	panel.queue_free()

	if _fail.is_empty():
		print("[PLAYER IDENTITY] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[PLAYER IDENTITY] FAIL: %s" % f)
		quit(1)
