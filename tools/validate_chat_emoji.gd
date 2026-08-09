extends SceneTree

## Explicit load/instantiate of ChatScreen + ChatEmojiCatalog (not a short editor scan).

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var ok := true

	print("[validate] load ChatEmojiCatalog")
	var cat_scr: Script = load("res://Scripts/UI/ChatEmojiCatalog.gd") as Script
	if cat_scr == null:
		push_error("[validate] ChatEmojiCatalog failed to load")
		ok = false
	else:
		var assets: Dictionary = ChatEmojiCatalog.verify_all_assets()
		print("[validate] assets loaded=", assets.get("loaded"), "/", assets.get("total"), " ok=", assets.get("ok"))
		if not bool(assets.get("ok", false)):
			push_error("[validate] missing assets: " + str(assets.get("missing", [])))
			ok = false
		var norm: String = ChatEmojiCatalog.normalize_outbound("hi 😀 :fire: [b]no[/b]")
		print("[validate] normalize=", norm)
		if norm.find(":grinning:") < 0 or norm.find(":fire:") < 0:
			push_error("[validate] normalize failed")
			ok = false
		if norm.find("[b]") < 0:
			push_error("[validate] BBCode text was corrupted")
			ok = false
		var segs: Array = ChatEmojiCatalog.parse_segments("A :grinning: B :not_real: C")
		var kinds := []
		for s in segs:
			kinds.append("%s:%s" % [s.get("kind"), s.get("text", s.get("token", ""))])
		print("[validate] segments=", kinds)
		## Unknown token must remain as text.
		var unknown_ok := false
		for s in segs:
			if str(s.get("kind")) == "text" and str(s.get("text")).find(":not_real:") >= 0:
				unknown_ok = true
		if not unknown_ok:
			push_error("[validate] unknown token was dropped")
			ok = false

	print("[validate] load ChatScreen.gd")
	var scr: Script = load("res://Scripts/UI/ChatScreen.gd") as Script
	if scr == null:
		push_error("[validate] ChatScreen failed to load")
		ok = false
	else:
		var node := Control.new()
		node.set_script(scr)
		if node.get_script() != scr:
			push_error("[validate] set_script failed")
			ok = false
		else:
			root.add_child(node)
			## Simulate phone portrait.
			node.size = Vector2(720, 1280)
			node.call("on_open")
			print("[validate] labels=",
				str(node.get("_tool_emoji_btn").text), "/",
				str(node.get("_tool_location_btn").text), "/",
				str(node.get("_tool_rally_btn").text), "/",
				str(node.get("_tool_more_btn").text))
			## Insert token via picker path.
			node.call("_insert_emoji_token", "grinning")
			var input: LineEdit = node.get("_input") as LineEdit
			print("[validate] draft=", input.text if input else "null")
			if input == null or input.text.find(":grinning:") < 0:
				push_error("[validate] token not inserted")
				ok = false
			## Message row component: emoji text block.
			var block: Control = node.call("_build_emoji_text_block", "Hello :fire: world :unknown_tok:", 16, Color.WHITE)
			root.add_child(block)
			print("[validate] message-row children=", block.get_child_count())
			if block.get_child_count() < 2:
				push_error("[validate] emoji text block too empty")
				ok = false
			## Picker fit inside 720x1280.
			node.call("_open_emoji_picker")
			node.call("_fit_emoji_panel")
			var panel: PanelContainer = node.get("_emoji_panel") as PanelContainer
			if panel != null:
				await process_frame
				node.call("_fit_emoji_panel")
				await process_frame
				var r := Rect2(panel.position, panel.size)
				print("[validate] emoji panel rect=", r)
				if r.size.x > 380.0 or r.size.y > 440.0:
					push_error("[validate] emoji panel larger than intended cap")
					ok = false
				if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > 720.5 or r.end.y > 1280.5:
					push_error("[validate] emoji panel outside 720x1280")
					ok = false
				print("[validate] panel fits viewport=", r.end.x <= 720.5 and r.end.y <= 1280.5)
			## Direct tab hides Rally.
			node.call("_set_tab", "private")
			var rally: Button = node.get("_tool_rally_btn") as Button
			print("[validate] rally visible on DM=", rally.visible if rally else "null")
			if rally != null and rally.visible:
				push_error("[validate] Rally still visible in Direct")
				ok = false
			block.queue_free()
			node.queue_free()

	## Export inclusion: Android preset uses all_resources; PNGs under res://assets are included.
	var export_cfg := ConfigFile.new()
	if export_cfg.load("res://export_presets.cfg") == OK:
		var filt: String = str(export_cfg.get_value("preset.0", "export_filter", ""))
		print("[validate] android export_filter=", filt)
		if filt != "all_resources":
			push_warning("[validate] unexpected export_filter — confirm assets pack manually")
	else:
		push_warning("[validate] export_presets.cfg missing")

	## Confirm ResourceLoader can see PNGs (import or raw).
	var sample := "res://assets/UI/chat_emoji/1f600.png"
	print("[validate] ResourceLoader.exists 1f600=", ResourceLoader.exists(sample), " FileAccess=", FileAccess.file_exists(sample))

	if ok:
		print("[validate] PASS")
		quit(0)
	else:
		print("[validate] FAIL")
		quit(1)
