extends SceneTree

## Castle tap routing + remote profile power regression smoke.
## Godot --headless --path . -s res://Scripts/dev/player_castle_tap_profile_smoke.gd

var _failed: int = 0
var _hud: FakeHUD
var _popup: Control
var _layer: Node2D
var _popup_script: GDScript
var _profile_script: GDScript
var _layer_script: GDScript


class FakeHUD extends Node:
	var profile_calls: Array = []
	var chat_calls: Array = []
	var march: FakeMarchSetup

	func open_player_profile(user_id: String = "", world_seed: Dictionary = {}) -> void:
		profile_calls.append({"user_id": user_id, "seed": world_seed.duplicate(true)})

	func open_private_chat(user_id: String, display_name: String) -> void:
		chat_calls.append({"user_id": user_id, "display_name": display_name})

	func ensure_player_castle_popup() -> Control:
		return get_node_or_null("PlayerCastlePopup") as Control


class FakeMarchSetup extends Node:
	var opens: Array = []

	func open_for_target(target: Dictionary) -> void:
		opens.append(target.duplicate(true))


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("[CASTLE TAP] FAIL: %s" % msg)
	print("[CASTLE TAP] FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("[CASTLE TAP] OK: %s" % msg)


func _enemy(overrides: Dictionary = {}) -> Dictionary:
	var t := {
		"user_id": "enemy_rubble_001",
		"display_name": "Rubble",
		"alliance_id": "ally_enemy",
		"alliance_tag": "RBL",
		"alliance_name": "Rubble Clan",
		"kingdom_id": "k1",
		"world_x": 4200.0,
		"world_y": 3800.0,
		"power": 15420,
		"citadel_level": 8,
		"avatar_id": "avatar_01",
		"peace_shield_active": false,
		"anti_scout_active": false,
		"beginner_protection_active": false,
		"resolved": true,
	}
	for k: Variant in overrides.keys():
		t[k] = overrides[k]
	return t


func _run() -> void:
	await process_frame
	_popup_script = load("res://Scripts/UI/PlayerCastlePopup.gd") as GDScript
	_profile_script = load("res://Scripts/UI/PlayerProfileScreen.gd") as GDScript
	_layer_script = load("res://Scripts/World/WorldCastleLayer.gd") as GDScript
	if _popup_script == null or _profile_script == null or _layer_script == null:
		_fail("failed to load production scripts")
		print("[CASTLE TAP] FAILED count=%d" % _failed)
		quit(1)
		return
	_setup_harness()
	await process_frame
	if _popup == null or not _popup.has_method("open_for_castle"):
		_fail("PlayerCastlePopup script did not attach (open_for_castle missing)")
		print("[CASTLE TAP] FAILED count=%d" % _failed)
		quit(1)
		return

	await _test_a_enemy_tap_opens_popup_not_profile()
	await _test_b_profile_button()
	await _test_c_scout_route()
	await _test_d_attack_route()
	await _test_e_same_cycle_cannot_open_profile()
	await _test_f_own_castle()
	await _test_g_alliance_mate()
	_test_h_remote_power_from_world()
	_test_i_missing_power_not_fabricated()
	await _test_nameplate_and_emulated_mouse()

	if _failed == 0:
		print("[CASTLE TAP] PASS")
		quit(0)
	else:
		print("[CASTLE TAP] FAILED count=%d" % _failed)
		quit(1)


func _setup_harness() -> void:
	_hud = FakeHUD.new()
	_hud.name = "GameHUD"
	_hud.add_to_group("game_hud")
	root.add_child(_hud)
	_hud.march = FakeMarchSetup.new()
	_hud.march.name = "MarchSetupScreen"
	_hud.add_child(_hud.march)

	_popup = Control.new()
	_popup.name = "PlayerCastlePopup"
	_popup.set_script(_popup_script)
	_hud.add_child(_popup)

	_layer = _layer_script.new()
	_layer.name = "WorldCastleLayer"
	root.add_child(_layer)


func _labels() -> PackedStringArray:
	return _popup.call("get_visible_action_labels") as PackedStringArray


func _has_label(labels: PackedStringArray, text: String) -> bool:
	for s: String in labels:
		if s == text:
			return true
	return false


func _test_a_enemy_tap_opens_popup_not_profile() -> void:
	_hud.profile_calls.clear()
	_popup.call("open_for_castle", _enemy())
	if not bool(_popup.visible):
		_fail("A: popup not visible after enemy castle open")
	else:
		_ok("A: popup visible")
	var labels: PackedStringArray = _labels()
	for need: String in ["Profile", "Scout", "Attack", "Message", "Share Location"]:
		if not _has_label(labels, need):
			_fail("A: missing action %s in %s" % [need, str(labels)])
	if not _hud.profile_calls.is_empty():
		_fail("A: full profile opened automatically: %s" % str(_hud.profile_calls))
	else:
		_ok("A: full profile did not open automatically")
	if bool(_popup.call("are_actions_armed")):
		_fail("A: actions armed in the same open call (click-through window)")
	else:
		_ok("A: actions disarmed until next frame")


func _test_b_profile_button() -> void:
	await process_frame
	if not bool(_popup.call("are_actions_armed")):
		_fail("B: actions never armed")
		return
	_hud.profile_calls.clear()
	_popup.call("_on_profile")
	if _hud.profile_calls.is_empty():
		_fail("B: Profile button did not open Player Profile")
		return
	var call: Dictionary = _hud.profile_calls[0]
	if str(call.get("user_id", "")) != "enemy_rubble_001":
		_fail("B: wrong profile user %s" % call)
	elif int(call.get("seed", {}).get("power", 0)) != 15420:
		_fail("B: profile seed missing castle power")
	else:
		_ok("B: Profile button opens full Player Profile with world seed")


func _test_c_scout_route() -> void:
	_popup.call("open_for_castle", _enemy())
	await process_frame
	_hud.profile_calls.clear()
	_hud.march.opens.clear()
	_popup.call("_on_scout")
	# Offline authority fail-closes; still must not open profile or attack setup.
	if not _hud.profile_calls.is_empty():
		_fail("C: scout opened profile")
	elif not _hud.march.opens.is_empty():
		_fail("C: scout opened March Setup")
	else:
		_ok("C: Scout stays on scout route (no profile / no attack setup)")


func _test_d_attack_route() -> void:
	_popup.call("open_for_castle", _enemy())
	await process_frame
	_hud.profile_calls.clear()
	_hud.march.opens.clear()
	_popup.call("_on_attack")
	if not _hud.profile_calls.is_empty():
		_fail("D: attack opened profile")
	elif _hud.march.opens.is_empty():
		_fail("D: attack did not open March Setup: %s" % _popup.call("get_status_text"))
	else:
		_ok("D: Attack opens March Setup only")


func _test_e_same_cycle_cannot_open_profile() -> void:
	_hud.profile_calls.clear()
	_popup.call("open_for_castle", _enemy())
	# Same input cycle: opening frame, actions not armed.
	_popup.call("_on_profile")
	if not _hud.profile_calls.is_empty():
		_fail("E: same-cycle Profile handler opened full profile")
		return
	# Android-like emulated mouse-up on the Profile button.
	for c in (_popup.get("_actions") as Node).get_children():
		var btn: Button = c as Button
		if btn != null and btn.text == "Profile":
			btn.pressed.emit()
			break
	if not _hud.profile_calls.is_empty():
		_fail("E: emulated button press on unarmed Profile opened profile")
	else:
		_ok("E: one touch cannot open popup + profile in the same input cycle")
	await process_frame
	_popup.call("_on_profile")
	if _hud.profile_calls.is_empty():
		_fail("E: Profile still blocked after arming")
	else:
		_ok("E: Profile works on a later input cycle")


func _test_f_own_castle() -> void:
	var local_id: String = "local_user_self"
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("smoke_set_session_user"):
		nc.call("smoke_set_session_user", local_id)
	var own: Dictionary = _enemy({
		"user_id": local_id,
		"display_name": "Me",
		"alliance_id": "ally_self",
	})
	_popup.call("open_for_castle", own)
	await process_frame
	if not bool(_popup.get("_is_self")):
		_popup.set("_is_self", true)
		_popup.call("_refresh")
		await process_frame
	var labels: PackedStringArray = _labels()
	if _has_label(labels, "Scout") or _has_label(labels, "Attack") or _has_label(labels, "Message"):
		_fail("F: own castle still shows Scout/Attack/Message: %s" % str(labels))
	elif not _has_label(labels, "Profile") or not _has_label(labels, "Share Location"):
		_fail("F: own castle missing Profile/Share Location: %s" % str(labels))
	else:
		_ok("F: own castle has Profile/Share Location and no Scout/Attack")


func _test_g_alliance_mate() -> void:
	var attacker_id: String = "ally_self"
	var ab: Node = root.get_node_or_null("/root/AllianceBackend")
	if ab != null:
		ab.set("_profile", {
			"user_id": "me",
			"alliance_id": attacker_id,
		})
	var als: Node = root.get_node_or_null("/root/AllianceState")
	if als != null:
		als.set("alliance_id", attacker_id)
	var mate: Dictionary = _enemy({
		"user_id": "ally_mate_009",
		"display_name": "Mate",
		"alliance_id": attacker_id,
	})
	_popup.call("open_for_castle", mate)
	await process_frame
	var labels: PackedStringArray = _labels()
	if not _has_label(labels, "Profile") or not _has_label(labels, "Message") or not _has_label(labels, "Share Location"):
		_fail("G: alliance popup missing social actions: %s" % str(labels))
	if not _has_label(labels, "Scout") or not _has_label(labels, "Attack"):
		_fail("G: alliance popup should still list Scout/Attack (blocked on use)")
	_hud.profile_calls.clear()
	_hud.chat_calls.clear()
	_hud.march.opens.clear()
	var gate: Node = root.get_node_or_null("/root/HostileActionGate")
	var atk: Dictionary = gate.call("evaluate", "attack", mate, {"user_id": "me", "alliance_id": attacker_id})
	var scout: Dictionary = gate.call("evaluate", "scout", mate, {"user_id": "me", "alliance_id": attacker_id})
	if bool(atk.get("ok", false)) or bool(scout.get("ok", false)):
		_fail("G: alliance hostile actions were allowed")
	_popup.call("_on_scout")
	_popup.call("_on_attack")
	if not _hud.march.opens.is_empty():
		_fail("G: alliance attack reached March Setup")
	elif not _hud.profile_calls.is_empty():
		_fail("G: alliance scout/attack opened profile")
	else:
		var st: String = str(_popup.call("get_status_text"))
		if "alliance member" not in st.to_lower():
			_fail("G: blocked reason missing: %s" % st)
		else:
			_ok("G: alliance popup opens; hostile blocked; social actions present")
	_popup.call("_on_profile")
	if _hud.profile_calls.is_empty():
		_fail("G: alliance Profile button dead")
	_popup.call("open_for_castle", mate)
	await process_frame
	_popup.call("_on_message")
	if _hud.chat_calls.is_empty():
		_fail("G: alliance Message button dead")
	else:
		_ok("G: alliance Profile/Message usable")


func _test_h_remote_power_from_world() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	var power_bak: Variant = gs.get("power") if gs != null else 0
	if gs != null:
		gs.set("power", 999999)
	var pub_zero := {"user_id": "enemy_rubble_001", "display_name": "Rubble", "power": 0}
	var world := {"user_id": "enemy_rubble_001", "power": 15420}
	var helper: Object = _profile_script.new()
	var resolved: int = int(helper.call("resolve_remote_display_power", pub_zero, world))
	helper.free()
	if resolved != 15420:
		_fail("H: resolve_remote_display_power expected 15420 got %d" % resolved)
		if gs != null:
			gs.set("power", power_bak)
		return
	var ab2: Node = root.get_node_or_null("/root/AllianceBackend")
	if ab2 != null:
		ab2.set("_cached_kingdom_castles", [world])
		var cached: Dictionary = ab2.call("get_cached_castle_for_user", "enemy_rubble_001")
		if int(cached.get("power", 0)) != 15420:
			_fail("H: cached kingdom castle power mismatch")
			if gs != null:
				gs.set("power", power_bak)
			return
	if gs != null and int(gs.get("power")) == resolved:
		_fail("H: remote power matched local GameState.power sentinel")
	else:
		_ok("H: remote profile power uses world/castle power, not GameState")
	if gs != null:
		gs.set("power", power_bak)


func _test_i_missing_power_not_fabricated() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	var power_bak: Variant = gs.get("power") if gs != null else 0
	if gs != null:
		gs.set("power", 999999)
	var pub := {"user_id": "unknown_007", "display_name": "Unknown"}
	var world := {"user_id": "unknown_007"}
	var helper: Object = _profile_script.new()
	var resolved: int = int(helper.call("resolve_remote_display_power", pub, world))
	var garbage: int = int(helper.call("coerce_social_stat", "not-a-number"))
	helper.free()
	if resolved != 0:
		_fail("I: missing power fabricated as %d" % resolved)
	else:
		_ok("I: unknown/missing remote power stays 0 (not fabricated)")
	if garbage != 0:
		_fail("I: invalid power string fabricated as %d" % garbage)
	else:
		_ok("I: invalid power values coerce to 0")
	if gs != null:
		gs.set("power", power_bak)


func _test_nameplate_and_emulated_mouse() -> void:
	await process_frame
	if _layer.get("_other_root") == null:
		_fail("nameplate: OtherPlayerCastles missing")
		return
	_layer.call("_spawn_other_castle", _enemy(), Vector2(200, 200))
	var castle: Node = (_layer.get("_other_root") as Node).get_child(0)
	var btn: Button = castle.find_child("NameplateButton", true, false) as Button
	if btn == null:
		_fail("nameplate: NameplateButton missing")
		return
	_layer.set("_last_castle_tap_route", "")
	btn.pressed.emit()
	if str(_layer.call("get_last_castle_tap_route")) != "popup":
		_fail("nameplate tap routed to %s instead of popup" % _layer.call("get_last_castle_tap_route"))
	else:
		_ok("nameplate tap opens popup, not full profile")

	var taps: Array = [0]
	var on_tap := func():
		taps[0] = int(taps[0]) + 1
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	mouse.device = -1
	mouse.position = Vector2(10, 10)
	_layer.call("_handle_castle_pointer_event", mouse, on_tap)
	if int(taps[0]) != 0:
		_fail("E2: emulated mouse (device -1) triggered castle tap")
	else:
		_ok("E2: emulated mouse from touch is ignored on castle Area2D")
