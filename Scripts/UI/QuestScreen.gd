extends Control

const MobileScrollUtil = preload("res://Scripts/UI/MobileScroll.gd")
const TABS: Array[String] = ["Main", "Daily", "Achievement"]

var current_tab: String = "Main"
var tab_buttons: Dictionary = {}
var list_box: VBoxContainer
var reward_popup: PanelContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

	if has_node("/root/QuestState"):
		if not QuestState.quest_updated.is_connected(_refresh):
			QuestState.quest_updated.connect(_refresh)


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if has_node("/root/QuestState"):
		QuestState.on_quest_screen_opened()
		# QuestState.refresh_auto_progress()

	_refresh()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var dim: ColorRect = ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_bottom = -190.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window: PanelContainer = PanelContainer.new()
	window.name = "QuestWindow"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.custom_minimum_size = Vector2(640, 900)
	window.offset_left = -320
	window.offset_top = -450
	window.offset_right = 320
	window.offset_bottom = 450
	add_child(window)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 12)
	window.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	root.add_child(header)

	var title_label: Label = Label.new()
	title_label.text = "QUESTS"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(64, 48)
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)

	for tab: String in TABS:
		var button: Button = Button.new()
		button.text = tab
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_set_tab.bind(tab))
		tabs.add_child(button)
		tab_buttons[tab] = button

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "QuestScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	MobileScrollUtil.ensure(self, scroll, "MobileScrollQuest")

	list_box = VBoxContainer.new()
	list_box.name = "QuestList"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)

	reward_popup = PanelContainer.new()
	reward_popup.name = "RewardPopup"
	reward_popup.visible = false
	reward_popup.set_anchors_preset(Control.PRESET_CENTER)
	reward_popup.custom_minimum_size = Vector2(440, 240)
	reward_popup.offset_left = -220
	reward_popup.offset_top = -120
	reward_popup.offset_right = 220
	reward_popup.offset_bottom = 120
	add_child(reward_popup)

	_set_tab(current_tab)


func _set_tab(tab_name: String) -> void:
	current_tab = tab_name

	for tab: String in TABS:
		var button: Button = tab_buttons[tab]
		button.set_pressed_no_signal(tab == current_tab)
		
	_refresh()


func _refresh() -> void:
	if list_box == null:
		return

	for child: Node in list_box.get_children():
		child.queue_free()

	if not has_node("/root/QuestState"):
		var missing: Label = Label.new()
		missing.text = "QuestState autoload is missing."
		list_box.add_child(missing)
		return

	var quests: Array = QuestState.get_quests_for_tab(current_tab)

	for quest: Dictionary in quests:
		list_box.add_child(_make_quest_card(quest))

	if quests.is_empty():
		var empty: Label = Label.new()
		empty.text = "No quests yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_box.add_child(empty)


func _make_quest_card(quest: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.name = str(quest.get("id", "QuestCard"))
	card.custom_minimum_size = Vector2(0, 150)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var title: Label = Label.new()
	title.text = str(quest.get("title", "Quest"))
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var desc: Label = Label.new()
	desc.text = str(quest.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	var progress: int = int(QuestState.get_progress(quest))
	var target: int = QuestState.get_target(quest)

	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(target, 1)
	bar.value = clamp(progress, 0, target)
	bar.custom_minimum_size = Vector2(0, 28)
	box.add_child(bar)

	var bottom: HBoxContainer = HBoxContainer.new()
	box.add_child(bottom)

	var reward_label: Label = Label.new()
	reward_label.text = "Rewards: " + _format_rewards(quest.get("rewards", []))
	reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(reward_label)

	var progress_label: Label = Label.new()
	progress_label.text = "%d/%d" % [min(progress, target), target]
	progress_label.custom_minimum_size = Vector2(90, 36)
	bottom.add_child(progress_label)

	var claim_button: Button = Button.new()
	claim_button.custom_minimum_size = Vector2(110, 44)

	if QuestState.is_claimed(quest):
		claim_button.text = "CLAIMED"
		claim_button.disabled = true

	elif QuestState.can_claim(quest):
		claim_button.text = "CLAIM"
		claim_button.disabled = false

		var quest_id: String = str(quest.get("id", ""))
		var reward_list: Array = quest.get("rewards", [])

		claim_button.pressed.connect(_claim.bind(quest_id, reward_list))

	else:
		claim_button.text = "GO TO"
		claim_button.disabled = false

		var progress_key: String = str(quest.get("progress_key", ""))
		claim_button.pressed.connect(_go_to_quest.bind(progress_key))

	bottom.add_child(claim_button)
	return card


func _claim(quest_id: String, rewards: Array) -> void:
	if QuestState.claim_quest(quest_id):
		_show_rewards(rewards)

	_refresh()


func _go_to_quest(progress_key: String) -> void:
	print("Quest target coming soon: ", progress_key)


func _format_rewards(rewards: Array) -> String:
	var parts: Array[String] = []

	for reward: Dictionary in rewards:
		var emoji: String = str(reward.get("emoji", ""))
		var reward_name: String = str(reward.get("name", reward.get("id", ""))).capitalize()
		var amount: int = int(reward.get("amount", 0))
		parts.append("%s %s x%d" % [emoji, reward_name, amount])

	return ", ".join(parts)


func _show_rewards(rewards: Array) -> void:
	for child: Node in reward_popup.get_children():
		child.queue_free()

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	reward_popup.add_child(box)

	var title: Label = Label.new()
	title.text = "Rewards Claimed!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var reward_text: Label = Label.new()
	reward_text.text = _format_rewards(rewards)
	reward_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reward_text)

	var ok_button: Button = Button.new()
	ok_button.text = "OK"
	ok_button.custom_minimum_size = Vector2(160, 48)
	ok_button.pressed.connect(_hide_reward_popup)
	box.add_child(ok_button)

	reward_popup.visible = true


func _hide_reward_popup() -> void:
	reward_popup.visible = false


func _close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")

	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		visible = false
		
