extends CanvasLayer

## Phase 4 login gate overlay — shown when a known secured account cannot restore session.
## Does not create a new guest. Never stores passwords.
## After successful email auth, dismisses — or shows conflict resolution if cloud conflict is blocked.

const AccountSettingsPanelScript = preload("res://Scripts/UI/AccountSettingsPanel.gd")

const COL_DIM := Color(0.02, 0.03, 0.06, 0.82)
const COL_INK := Color(0.95, 0.92, 0.86, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.36, 1.0)
const COL_PANEL := Color(0.08, 0.10, 0.18, 0.98)
const COL_BORDER := Color(0.72, 0.58, 0.28, 0.95)

var _panel: VBoxContainer = null
var _body: Label = null
var _account_panel: Node = null


func _ready() -> void:
	layer = 100
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 12)
	card.add_child(_panel)

	var title := Label.new()
	title.text = "Account Login Required"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	_panel.add_child(title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", COL_INK)
	_panel.add_child(_body)
	_refresh_body_copy()

	_account_panel = AccountSettingsPanelScript.new()
	_panel.add_child(_account_panel)
	if _account_panel.has_method("configure_for_login_gate"):
		_account_panel.call("configure_for_login_gate")
	elif _account_panel.has_method("show_login_view"):
		_account_panel.call("show_login_view")
	if _account_panel.has_signal("conflict_resolved"):
		_account_panel.conflict_resolved.connect(_on_conflict_resolved)

	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("email_auth_completed"):
		identity.email_auth_completed.connect(_on_email_auth_completed)
	if identity != null and identity.has_signal("account_state_changed"):
		identity.account_state_changed.connect(_on_account_changed)
	var stack: Node = get_node_or_null("/root/UiLayerStack")
	if stack != null:
		stack.call("push_layer", "blocking:AccountLoginGate", func() -> bool: return true, "modal", true)

	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		if _account_panel.has_method("show_conflict_view"):
			_account_panel.call("show_conflict_view")
		_refresh_body_copy()


func _on_account_changed() -> void:
	_refresh_body_copy()


func _refresh_body_copy() -> void:
	if _body == null:
		return
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		_body.text = (
			"You are signed in, but a cloud save conflict needs attention before continuing. "
			+ "Choose which save to keep. A new guest account will not be created."
		)
		return
	_body.text = (
		"Your secured Crownspire account session could not be restored. "
		+ "Log in with email to continue. A new guest account will not be created."
	)


func _on_email_auth_completed(result: Dictionary) -> void:
	# Auth failure: stay open so the player can retry.
	if not bool(result.get("logged_in", false)):
		_refresh_body_copy()
		return
	# Auth success with conflict: keep gate open on conflict UI (do not soft-lock as login failure).
	if bool(result.get("conflict", false)):
		_refresh_body_copy()
		if _account_panel != null and _account_panel.has_method("show_conflict_view"):
			_account_panel.call("show_conflict_view")
		return
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		_refresh_body_copy()
		if _account_panel != null and _account_panel.has_method("show_conflict_view"):
			_account_panel.call("show_conflict_view")
		return
	queue_free()


func _on_conflict_resolved(_result: Dictionary) -> void:
	queue_free()


func _exit_tree() -> void:
	var stack: Node = get_node_or_null("/root/UiLayerStack")
	if stack != null:
		stack.call("remove_layer", "blocking:AccountLoginGate")


## HUD/tests: present overlay only for terminal restore failure without a live session.
static func should_present_overlay(identity: Node) -> bool:
	if identity == null:
		return false
	if identity.has_method("should_force_login_gate"):
		return bool(identity.call("should_force_login_gate"))
	return false


static func ensure_on_tree(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	if tree.root.get_node_or_null("AccountLoginGate") != null:
		return
	var identity: Node = tree.root.get_node_or_null("/root/AccountIdentityState")
	if not should_present_overlay(identity):
		print("[CrownspireSession] gate_suppressed_live_session")
		return
	var gate := load("res://Scripts/UI/AccountLoginGate.gd")
	if gate == null:
		return
	print("[CrownspireSession] gate_shown reason=ensure_on_tree")
	var node: CanvasLayer = gate.new()
	node.name = "AccountLoginGate"
	tree.root.add_child(node)
