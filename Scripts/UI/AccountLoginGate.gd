extends CanvasLayer

## Phase 4 login gate overlay — shown when a known secured account cannot restore session.
## Does not create a new guest. Never stores passwords.

const AccountSettingsPanelScript = preload("res://Scripts/UI/AccountSettingsPanel.gd")

const COL_DIM := Color(0.02, 0.03, 0.06, 0.82)
const COL_INK := Color(0.95, 0.92, 0.86, 1.0)
const COL_GOLD := Color(0.90, 0.74, 0.36, 1.0)
const COL_PANEL := Color(0.08, 0.10, 0.18, 0.98)
const COL_BORDER := Color(0.72, 0.58, 0.28, 0.95)

var _panel: VBoxContainer = null
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
	card.custom_minimum_size = Vector2(520, 420)
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

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "Your secured Crownspire account session could not be restored. Log in with email to continue. A new guest account will not be created."
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", COL_INK)
	_panel.add_child(body)

	_account_panel = AccountSettingsPanelScript.new()
	_panel.add_child(_account_panel)
	if _account_panel.has_method("show_login_view"):
		_account_panel.call("show_login_view")

	var identity: Node = get_node_or_null("/root/AccountIdentityState")
	if identity != null and identity.has_signal("email_auth_completed"):
		identity.email_auth_completed.connect(_on_email_auth_completed)


func _on_email_auth_completed(result: Dictionary) -> void:
	if bool(result.get("ok", false)) and bool(result.get("logged_in", false)):
		queue_free()


static func ensure_on_tree(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	if tree.root.get_node_or_null("AccountLoginGate") != null:
		return
	var gate := load("res://Scripts/UI/AccountLoginGate.gd")
	if gate == null:
		return
	var node: CanvasLayer = gate.new()
	node.name = "AccountLoginGate"
	tree.root.add_child(node)
