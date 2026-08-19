extends VBoxContainer

## Account secure / login panel for Profile → Settings and login gate.
## Mythic Crown Studios Account = Nakama email/password linked to the SAME user.
## Never displays stored passwords. Never logs password contents.

signal request_close_forms
signal conflict_resolved(result: Dictionary)
signal gate_cancel_requested

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")

const COL_INK := Color(0.95, 0.92, 0.86, 1.0)
const COL_MUTED := Color(0.72, 0.68, 0.62, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.36, 1.0)
const COL_PANEL := Color(0.10, 0.12, 0.22, 0.96)
const COL_BORDER := Color(0.72, 0.58, 0.28, 0.95)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_ERR := Color(0.92, 0.42, 0.38, 1.0)
const TOUCH_H := 48
const FONT_SECTION := 18
const FONT_BODY := 15
const FONT_BUTTON := 16

enum View { SUMMARY, SECURE, LOGIN, CONFLICT }

var _view: int = View.SUMMARY
var _status: Label = null
var _busy: bool = false
## When true: forced secured-account reauth — no Secure Account CTA, Cancel returns to login.
var _login_gate_mode: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild()
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("account_state_changed"):
		if not identity.account_state_changed.is_connected(_on_account_changed):
			identity.account_state_changed.connect(_on_account_changed)
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_signal("cloud_conflict"):
		if not cloud.cloud_conflict.is_connected(_on_cloud_conflict):
			cloud.cloud_conflict.connect(_on_cloud_conflict)


func configure_for_login_gate() -> void:
	_login_gate_mode = true
	_view = View.LOGIN
	rebuild()


func show_login_view() -> void:
	_view = View.LOGIN
	rebuild()


func show_secure_view() -> void:
	_show_secure()


func show_conflict_view() -> void:
	_view = View.CONFLICT
	rebuild()


func _on_account_changed() -> void:
	if _view == View.SUMMARY or _view == View.CONFLICT:
		rebuild()


func _on_cloud_conflict(_code: String, _detail: Dictionary) -> void:
	if _login_gate_mode or _view == View.LOGIN or _view == View.SUMMARY:
		_view = View.CONFLICT
		rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_status = null
	# Authoritative conflict takes UI priority once present.
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		if _view != View.CONFLICT and (_login_gate_mode or _view == View.SUMMARY or _view == View.LOGIN):
			_view = View.CONFLICT
	match _view:
		View.SECURE:
			_build_secure_form()
		View.LOGIN:
			_build_login_form()
		View.CONFLICT:
			_build_conflict_form()
		_:
			_build_summary()


func _build_summary() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	var secured: bool = _is_secured_account(identity)
	var title := Label.new()
	title.name = "AccountStatusTitle"
	title.text = tr("ACCOUNT_SECURED_TITLE") if secured else tr("ACCOUNT_GUEST_TITLE")
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)
	_add_support_identity_rows(identity)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if secured:
		body.text = tr("ACCOUNT_PROGRESS_PROTECTED")
		var masked: String = str(identity.call("get_masked_email")) if identity != null else ""
		if masked != "":
			body.text += "\n%s: %s" % [tr("ACCOUNT_EMAIL"), masked]
		var methods: PackedStringArray = PackedStringArray()
		if identity != null and identity.has_method("get_linked_method_labels"):
			var raw: Variant = identity.call("get_linked_method_labels")
			if raw is PackedStringArray:
				methods = raw
			elif typeof(raw) == TYPE_ARRAY:
				for item: Variant in raw:
					methods.append(str(item))
		if methods.size() > 0:
			body.text += "\n%s: %s" % [tr("ACCOUNT_LINKED"), ", ".join(methods)]
	else:
		body.text = tr("ACCOUNT_SECURE_PROGRESS")
	_style_label(body, FONT_BODY, COL_MUTED)
	add_child(body)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	if not secured and not _login_gate_mode:
		var mcs := Label.new()
		mcs.text = tr("ACCOUNT_MCS")
		_style_label(mcs, FONT_BODY, COL_INK)
		add_child(mcs)
		var secure_btn := Button.new()
		secure_btn.name = "SecureAccountButton"
		secure_btn.text = tr("ACCOUNT_SECURE")
		secure_btn.custom_minimum_size = Vector2(0, TOUCH_H)
		_style_button(secure_btn)
		secure_btn.pressed.connect(_show_secure)
		add_child(secure_btn)

	if identity != null:
		_add_google_identity_actions(identity, false)
		_add_provider_availability_note(identity)

	var login_btn := Button.new()
	login_btn.name = "LogInButton"
	login_btn.text = tr("ACCOUNT_LOG_IN")
	login_btn.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(login_btn)
	login_btn.pressed.connect(_show_login)
	add_child(login_btn)


func _add_support_identity_rows(identity: Node) -> void:
	if identity != null and identity.has_method("get_chief_display_name"):
		var chief: String = str(identity.call("get_chief_display_name")).strip_edges()
		if chief != "":
			var chief_lbl := Label.new()
			chief_lbl.name = "ChiefNameLabel"
			chief_lbl.text = "%s: %s" % [tr("CHIEF_NAME"), chief]
			_style_label(chief_lbl, FONT_BODY, COL_INK)
			add_child(chief_lbl)
	var full_id: String = ""
	var short_id: String = ""
	if identity != null:
		if identity.has_method("get_current_player_id"):
			full_id = str(identity.call("get_current_player_id")).strip_edges()
		if identity.has_method("get_current_player_id_short"):
			short_id = str(identity.call("get_current_player_id_short")).strip_edges()
	var row := HBoxContainer.new()
	row.name = "PlayerIdRow"
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var id_lbl := Label.new()
	id_lbl.name = "PlayerIdLabel"
	id_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if short_id == "":
		id_lbl.text = "%s: —" % tr("PLAYER_ID")
	else:
		id_lbl.text = "%s: %s" % [tr("PLAYER_ID"), short_id]
	_style_label(id_lbl, FONT_BODY, COL_MUTED)
	row.add_child(id_lbl)
	var copy_btn := Button.new()
	copy_btn.name = "PlayerIdCopyButton"
	copy_btn.text = tr("COPY")
	copy_btn.custom_minimum_size = Vector2(96, TOUCH_H)
	copy_btn.disabled = full_id.is_empty()
	_style_button(copy_btn)
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	copy_btn.pressed.connect(_on_copy_player_id_pressed)
	row.add_child(copy_btn)
	var copied := Label.new()
	copied.name = "PlayerIdCopiedLabel"
	copied.visible = false
	copied.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(copied, FONT_BODY, COL_OK)
	add_child(copied)


func _on_copy_player_id_pressed() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	var copied_ok: bool = false
	if identity != null and identity.has_method("copy_current_player_id_to_clipboard"):
		var result: Dictionary = identity.call("copy_current_player_id_to_clipboard")
		copied_ok = bool(result.get("copied", false))
	var copied_lbl: Label = find_child("PlayerIdCopiedLabel", true, false)
	if copied_lbl == null:
		return
	if copied_ok:
		copied_lbl.text = tr("PLAYER_ID_COPIED")
		copied_lbl.visible = true
	else:
		copied_lbl.visible = false


func _add_provider_availability_note(identity: Node) -> void:
	var google_ok: bool = identity.has_method("is_google_sign_in_available") and bool(identity.call("is_google_sign_in_available"))
	var apple_ok: bool = identity.has_method("is_apple_sign_in_available") and bool(identity.call("is_apple_sign_in_available"))
	if google_ok and apple_ok:
		return
	if google_ok and not apple_ok:
		var apple_note := Label.new()
		apple_note.name = "AppleUnavailableNote"
		apple_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		apple_note.text = tr("ACCOUNT_APPLE_UNAVAILABLE")
		_style_label(apple_note, FONT_BODY, COL_MUTED)
		add_child(apple_note)
		return
	var note := Label.new()
	note.name = "ProviderUnavailableNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = tr("ACCOUNT_PROVIDER_COMING")
	_style_label(note, FONT_BODY, COL_MUTED)
	add_child(note)
	if not google_ok:
		var diag := Label.new()
		diag.name = "GoogleDiagnosticNote"
		diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var player_code: String = "G1"
		if identity.has_method("get_google_sign_in_status"):
			var st: Dictionary = identity.call("get_google_sign_in_status")
			player_code = str(st.get("player_diagnostic", "G1"))
			if player_code == "":
				player_code = "G1"
		diag.text = tr("ACCOUNT_GOOGLE_UNAVAILABLE_G2") if player_code == "G2" else tr("ACCOUNT_GOOGLE_UNAVAILABLE_G1")
		_style_label(diag, FONT_BODY, COL_MUTED)
		add_child(diag)
		var google: Node = get_node_or_null("/root/GoogleIdentityClient")
		if google != null and google.has_method("log_availability_once"):
			google.call("log_availability_once")


func _add_google_identity_actions(identity: Node, login_form: bool, switch_blocked: bool = false) -> void:
	var google_ok: bool = identity.has_method("is_google_sign_in_available") and bool(identity.call("is_google_sign_in_available"))
	if not google_ok:
		return
	var linked: bool = false
	if identity.has_method("get_linked_providers"):
		var providers: Variant = identity.call("get_linked_providers")
		if providers is Dictionary:
			linked = bool((providers as Dictionary).get("GOOGLE", false))
	if linked:
		var linked_lbl := Label.new()
		linked_lbl.name = "GoogleLinkedLabel"
		linked_lbl.text = "%s: Google" % tr("ACCOUNT_LINKED")
		_style_label(linked_lbl, FONT_BODY, COL_OK)
		add_child(linked_lbl)
		return
	if login_form:
		var cont := Button.new()
		cont.name = "ContinueGoogleButton"
		cont.text = tr("ACCOUNT_CONTINUE_GOOGLE")
		cont.custom_minimum_size = Vector2(0, TOUCH_H)
		cont.disabled = switch_blocked
		_style_button(cont)
		cont.pressed.connect(_on_google_login_pressed)
		add_child(cont)
		return
	var secured: bool = identity.has_method("is_secured") and bool(identity.call("is_secured"))
	if secured:
		var link_btn := Button.new()
		link_btn.name = "LinkGoogleButton"
		link_btn.text = tr("ACCOUNT_LINK_GOOGLE")
		link_btn.custom_minimum_size = Vector2(0, TOUCH_H)
		_style_button(link_btn)
		link_btn.pressed.connect(_on_google_link_pressed)
		add_child(link_btn)
		return
	var sign_in := Button.new()
	sign_in.name = "SignInGoogleButton"
	sign_in.text = tr("ACCOUNT_SECURE_GOOGLE")
	sign_in.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(sign_in)
	sign_in.pressed.connect(_on_google_link_pressed)
	add_child(sign_in)


func _build_secure_form() -> void:
	var title := Label.new()
	title.text = tr("ACCOUNT_SECURE")
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var subtitle := Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = tr("ACCOUNT_MCS")
	_style_label(subtitle, FONT_BODY, COL_INK)
	add_child(subtitle)

	var email := _make_line(tr("ACCOUNT_EMAIL"), false, "Email")
	var password := _make_line(tr("ACCOUNT_PASSWORD"), true, "Password")
	var confirm := _make_line(tr("ACCOUNT_CONFIRM_PASSWORD"), true, "ConfirmPassword")
	add_child(email["wrap"])
	add_child(password["wrap"])
	add_child(confirm["wrap"])

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var cancel := Button.new()
	cancel.text = tr("UI_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(cancel)
	cancel.pressed.connect(_show_summary)
	row.add_child(cancel)
	var go := Button.new()
	go.name = "CreateAccountButton"
	go.text = tr("ACCOUNT_CREATE")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(go)
	go.pressed.connect(_on_secure_pressed.bind(email["edit"], password["edit"], confirm["edit"]))
	row.add_child(go)


func _build_login_form() -> void:
	var title := Label.new()
	title.text = tr("ACCOUNT_LOG_IN")
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var subtitle := Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = tr("ACCOUNT_MCS")
	_style_label(subtitle, FONT_BODY, COL_INK)
	add_child(subtitle)

	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	var safety: Dictionary = {}
	if identity != null and not _login_gate_mode:
		safety = identity.call("warn_before_login_switch")
		if bool(safety.get("warn", false)) or bool(safety.get("block", false)):
			var w := Label.new()
			w.name = "AccountSwitchWarning"
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			w.text = str(safety.get("message", tr("ACCOUNT_SWITCH_WARNING")))
			_style_label(w, FONT_BODY, COL_ERR)
			add_child(w)
	elif _login_gate_mode:
		var secured_note := Label.new()
		secured_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		secured_note.text = "Enter the email and password for your Mythic Crown Studios Account."
		_style_label(secured_note, FONT_BODY, COL_MUTED)
		add_child(secured_note)

	var email := _make_line(tr("ACCOUNT_EMAIL"), false, "LoginEmail")
	var password := _make_line(tr("ACCOUNT_PASSWORD"), true, "LoginPassword")
	add_child(email["wrap"])
	add_child(password["wrap"])

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	var blocked: bool = bool(safety.get("block", false))
	if blocked and not _login_gate_mode:
		var secure_first := Button.new()
		secure_first.name = "SecureBeforeLoginButton"
		secure_first.text = tr("ACCOUNT_SECURE")
		secure_first.custom_minimum_size = Vector2(0, TOUCH_H)
		_style_button(secure_first)
		secure_first.pressed.connect(_show_secure)
		add_child(secure_first)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var cancel := Button.new()
	cancel.text = tr("UI_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(cancel)
	cancel.pressed.connect(_on_login_cancel)
	row.add_child(cancel)
	var go := Button.new()
	go.name = "SubmitLogInButton"
	go.text = tr("ACCOUNT_LOG_IN")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, TOUCH_H)
	go.disabled = blocked
	_style_button(go)
	go.pressed.connect(_on_login_pressed.bind(email["edit"], password["edit"]))
	row.add_child(go)

	if identity != null:
		_add_google_identity_actions(identity, true, blocked)


func _build_conflict_form() -> void:
	var title := Label.new()
	title.text = "Resolve Cloud Save Conflict"
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"This device and your cloud save both have progress that cannot be merged automatically. "
		+ "Choose which save to keep. The other remains on disk/cloud until you choose."
	)
	_style_label(body, FONT_BODY, COL_MUTED)
	add_child(body)

	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("get_blocked_conflict"):
		var detail: Dictionary = cloud.call("get_blocked_conflict")
		var reason: String = str(detail.get("reason", detail.get("code", ""))).strip_edges()
		if reason != "":
			var meta := Label.new()
			meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			meta.text = "Conflict: %s" % reason
			_style_label(meta, FONT_BODY, COL_MUTED)
			add_child(meta)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	var cloud_btn := Button.new()
	cloud_btn.text = "USE CLOUD SAVE"
	cloud_btn.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(cloud_btn)
	cloud_btn.pressed.connect(_on_conflict_choice.bind("use_cloud"))
	add_child(cloud_btn)

	var local_btn := Button.new()
	local_btn.text = "KEEP DEVICE SAVE"
	local_btn.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(local_btn)
	local_btn.pressed.connect(_on_conflict_choice.bind("use_local"))
	add_child(local_btn)

	var back := Button.new()
	back.text = "Back to Log In"
	back.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(back)
	back.pressed.connect(_show_login)
	add_child(back)


func _on_secure_pressed(email_edit: LineEdit, pass_edit: LineEdit, confirm_edit: LineEdit) -> void:
	if _busy:
		return
	_busy = true
	_set_status(tr("ACCOUNT_SECURING"), false)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		_set_status("Account system unavailable.", true)
		_busy = false
		return
	var email: String = email_edit.text
	var password: String = pass_edit.text
	var confirm: String = confirm_edit.text
	var res: Dictionary = await identity.call("secure_guest_with_email", email, password, confirm)
	pass_edit.text = ""
	confirm_edit.text = ""
	password = ""
	confirm = ""
	_busy = false
	if bool(res.get("ok", false)):
		_set_status(tr("ACCOUNT_SECURED_SUCCESS"), false)
		_view = View.SUMMARY
		rebuild()
	else:
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)


func _on_login_pressed(email_edit: LineEdit, pass_edit: LineEdit) -> void:
	if _busy:
		return
	_busy = true
	_set_status(tr("ACCOUNT_LOGGING_IN"), false)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		_set_status("Account system unavailable.", true)
		_busy = false
		return
	var email: String = email_edit.text
	var password: String = pass_edit.text
	var res: Dictionary = await identity.call("login_with_email", email, password)
	pass_edit.text = ""
	password = ""
	_busy = false
	if not bool(res.get("logged_in", false)) and not bool(res.get("ok", false)):
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)
		return
	# Auth succeeded — conflict is a separate resolution step (does not block reauth).
	if bool(res.get("conflict", false)) or _has_blocked_conflict():
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_CLOUD_CONFLICT))), true)
		_view = View.CONFLICT
		rebuild()
		return
	_set_status("Logged in. Progress loaded for this account.", false)
	_view = View.SUMMARY
	rebuild()


func _on_google_link_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_status(tr("ACCOUNT_LINKING_GOOGLE"), false)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		_set_status("Account system unavailable.", true)
		_busy = false
		return
	var res: Dictionary = await identity.call("link_google_identity")
	_busy = false
	if bool(res.get("ok", false)):
		_set_status(tr("ACCOUNT_SECURED_SUCCESS"), false)
		_view = View.SUMMARY
		rebuild()
		return
	_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)


func _on_google_login_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_status(tr("ACCOUNT_LOGGING_IN"), false)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		_set_status("Account system unavailable.", true)
		_busy = false
		return
	var res: Dictionary = await identity.call("login_with_google")
	_busy = false
	if not bool(res.get("logged_in", false)) and not bool(res.get("ok", false)):
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)
		return
	if bool(res.get("conflict", false)) or _has_blocked_conflict():
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_CLOUD_CONFLICT))), true)
		_view = View.CONFLICT
		rebuild()
		return
	_set_status("Logged in. Progress loaded for this account.", false)
	_view = View.SUMMARY
	rebuild()


func _on_conflict_choice(choice: String) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Resolving conflict…", false)
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud == null or not cloud.has_method("apply_conflict_choice"):
		_set_status("Conflict resolution unavailable.", true)
		_busy = false
		return
	var res: Dictionary = await cloud.call("apply_conflict_choice", choice)
	_busy = false
	if bool(res.get("ok", false)):
		_set_status("Conflict resolved.", false)
		var identity: Node = get_node_or_null("/root/AccountIdentityState")
		if identity != null and identity.has_method("set_boot_gate_mode_for_future"):
			identity.call("set_boot_gate_mode_for_future", "AUTO_CONTINUE")
		conflict_resolved.emit(res)
		_view = View.SUMMARY
		rebuild()
	else:
		_set_status(str(res.get("message", res.get("error", "Could not resolve conflict."))), true)
		if _has_blocked_conflict():
			_view = View.CONFLICT
			rebuild()


func _on_login_cancel() -> void:
	if _login_gate_mode:
		# Stay on login form — do not present Guest Account summary under a secured gate.
		_view = View.LOGIN
		rebuild()
		gate_cancel_requested.emit()
		return
	_show_summary()


func _show_secure() -> void:
	_view = View.SECURE
	rebuild()


func _show_login() -> void:
	_view = View.LOGIN
	rebuild()


func _show_summary() -> void:
	_view = View.SUMMARY
	rebuild()


func _is_secured_account(identity: Node) -> bool:
	if identity == null:
		return false
	if bool(identity.call("is_secured")):
		return true
	if identity.has_method("is_known_secured") and bool(identity.call("is_known_secured")):
		return true
	if identity.has_method("should_block_guest_device_fallback") and bool(identity.call("should_block_guest_device_fallback")):
		return true
	return false


func _has_blocked_conflict() -> bool:
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	return cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict"))


func _set_status(text: String, is_error: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", COL_ERR if is_error else COL_OK)


func _make_line(label_text: String, secret: bool, field_id: String = "") -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	_style_label(lbl, FONT_BODY, COL_INK)
	wrap.add_child(lbl)
	var edit := LineEdit.new()
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, TOUCH_H)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if field_id != "":
		edit.name = "%sEdit" % field_id
	if secret:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(edit)
		var toggle := Button.new()
		toggle.name = "%sVisibilityToggle" % (field_id if field_id != "" else "Password")
		toggle.custom_minimum_size = Vector2(88, TOUCH_H)
		toggle.focus_mode = Control.FOCUS_ALL
		_style_button(toggle)
		_refresh_password_toggle(edit, toggle)
		toggle.pressed.connect(_on_password_visibility_pressed.bind(edit, toggle))
		row.add_child(toggle)
		wrap.add_child(row)
	else:
		wrap.add_child(edit)
	return {"wrap": wrap, "edit": edit}


func _on_password_visibility_pressed(edit: LineEdit, toggle: Button) -> void:
	edit.secret = not edit.secret
	_refresh_password_toggle(edit, toggle)


func _refresh_password_toggle(edit: LineEdit, toggle: Button) -> void:
	if edit.secret:
		toggle.text = tr("ACCOUNT_SHOW_PASSWORD")
		toggle.tooltip_text = tr("ACCOUNT_SHOW_PASSWORD")
	else:
		toggle.text = tr("ACCOUNT_HIDE_PASSWORD")
		toggle.tooltip_text = tr("ACCOUNT_HIDE_PASSWORD")


func _style_label(lbl: Label, font_size: int, color: Color) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _style_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", FONT_BUTTON)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", COL_GOLD)
