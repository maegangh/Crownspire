extends VBoxContainer

## Phase 4 — Account secure / login panel for Profile → Settings.
## Code-built; Crownspire dark/gold styling. Never displays stored passwords.

signal request_close_forms

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

enum View { SUMMARY, SECURE, LOGIN }

var _view: int = View.SUMMARY
var _status: Label = null
var _busy: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild()
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("account_state_changed"):
		if not identity.account_state_changed.is_connected(_on_account_changed):
			identity.account_state_changed.connect(_on_account_changed)


func _on_account_changed() -> void:
	if _view == View.SUMMARY:
		rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_status = null
	match _view:
		View.SECURE:
			_build_secure_form()
		View.LOGIN:
			_build_login_form()
		_:
			_build_summary()


func _build_summary() -> void:
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	var secured: bool = identity != null and bool(identity.call("is_secured"))
	var title := Label.new()
	title.text = "Account Secured" if secured else "Guest Account"
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if secured:
		var masked: String = str(identity.call("get_masked_email")) if identity != null else ""
		body.text = "Your Crownspire progress is protected."
		if masked != "":
			body.text += "\nEmail: %s" % masked
	else:
		body.text = "Secure your account to protect your Crownspire progress."
	_style_label(body, FONT_BODY, COL_MUTED)
	add_child(body)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	if not secured:
		var secure_btn := Button.new()
		secure_btn.text = "SECURE ACCOUNT"
		secure_btn.custom_minimum_size = Vector2(0, TOUCH_H)
		_style_button(secure_btn)
		secure_btn.pressed.connect(_show_secure)
		add_child(secure_btn)

	var login_btn := Button.new()
	login_btn.text = "LOG IN"
	login_btn.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(login_btn)
	login_btn.pressed.connect(_show_login)
	add_child(login_btn)


func _build_secure_form() -> void:
	var title := Label.new()
	title.text = "Secure Account"
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var email := _make_line("Email", false)
	var password := _make_line("Password", true)
	var confirm := _make_line("Confirm Password", true)
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
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(cancel)
	cancel.pressed.connect(_show_summary)
	row.add_child(cancel)
	var go := Button.new()
	go.text = "Secure Account"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(go)
	go.pressed.connect(_on_secure_pressed.bind(email["edit"], password["edit"], confirm["edit"]))
	row.add_child(go)


func _build_login_form() -> void:
	var title := Label.new()
	title.text = "Log In"
	_style_label(title, FONT_SECTION, COL_GOLD)
	add_child(title)

	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null:
		var warn: Dictionary = identity.call("warn_before_login_switch")
		if bool(warn.get("warn", false)):
			var w := Label.new()
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			w.text = str(warn.get("message", ""))
			_style_label(w, FONT_BODY, COL_ERR)
			add_child(w)

	var email := _make_line("Email", false)
	var password := _make_line("Password", true)
	add_child(email["wrap"])
	add_child(password["wrap"])

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status, FONT_BODY, COL_MUTED)
	add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(cancel)
	cancel.pressed.connect(_show_summary)
	row.add_child(cancel)
	var go := Button.new()
	go.text = "Log In"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, TOUCH_H)
	_style_button(go)
	go.pressed.connect(_on_login_pressed.bind(email["edit"], password["edit"]))
	row.add_child(go)


func _on_secure_pressed(email_edit: LineEdit, pass_edit: LineEdit, confirm_edit: LineEdit) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Securing account…", false)
	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity == null:
		_set_status("Account system unavailable.", true)
		_busy = false
		return
	var email: String = email_edit.text
	var password: String = pass_edit.text
	var confirm: String = confirm_edit.text
	var res: Dictionary = await identity.call("secure_guest_with_email", email, password, confirm)
	# Clear fields immediately — never leave password text lingering longer than needed.
	pass_edit.text = ""
	confirm_edit.text = ""
	password = ""
	confirm = ""
	_busy = false
	if bool(res.get("ok", false)):
		_set_status("Account secured. Your progress stays on this account.", false)
		_view = View.SUMMARY
		rebuild()
	else:
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)


func _on_login_pressed(email_edit: LineEdit, pass_edit: LineEdit) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Logging in…", false)
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
	if bool(res.get("ok", false)):
		_set_status("Logged in. Progress loaded for this account.", false)
		_view = View.SUMMARY
		rebuild()
	else:
		_set_status(str(res.get("message", AccountEmailAuthScript.user_message_for_code(str(res.get("error", ""))))), true)


func _show_secure() -> void:
	_view = View.SECURE
	rebuild()


func _show_login() -> void:
	_view = View.LOGIN
	rebuild()


func _show_summary() -> void:
	_view = View.SUMMARY
	rebuild()


func show_login_view() -> void:
	_show_login()


func _set_status(text: String, is_error: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", COL_ERR if is_error else COL_OK)


func _make_line(label_text: String, secret: bool) -> Dictionary:
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
	wrap.add_child(edit)
	return {"wrap": wrap, "edit": edit}


func _style_label(lbl: Label, font_size: int, color: Color) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _style_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", FONT_BUTTON)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", COL_GOLD)
