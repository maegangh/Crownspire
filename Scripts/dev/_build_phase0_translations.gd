extends SceneTree

## One-shot: build Translation resources from locales/crownspire_ui.csv
## Godot --headless --path . -s res://Scripts/dev/_build_phase0_translations.gd

const CSV_PATH := "res://locales/crownspire_ui.csv"
const OUT_EN_TRES := "res://locales/crownspire_ui.en.tres"
const OUT_TR_TRES := "res://locales/crownspire_ui.tr.tres"
const OUT_EN_BIN := "res://locales/crownspire_ui.en.translation"
const OUT_TR_BIN := "res://locales/crownspire_ui.tr.translation"


func _init() -> void:
	var err: int = _build()
	quit(err)


func _build() -> int:
	if not FileAccess.file_exists(CSV_PATH):
		push_error("Missing CSV: %s" % CSV_PATH)
		return 1
	var f: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("Cannot open CSV")
		return 1
	var header_line: String = f.get_line().strip_edges()
	if header_line.is_empty():
		push_error("Empty CSV header")
		return 1
	var headers: PackedStringArray = header_line.split(",")
	if headers.size() < 3:
		push_error("CSV needs keys,en,tr columns")
		return 1
	var en_i: int = -1
	var tr_i: int = -1
	for i in range(headers.size()):
		var h: String = headers[i].strip_edges().to_lower()
		if h == "en":
			en_i = i
		elif h == "tr":
			tr_i = i
	if en_i < 0 or tr_i < 0:
		push_error("CSV missing en/tr columns")
		return 1

	var t_en := Translation.new()
	t_en.locale = "en"
	var t_tr := Translation.new()
	t_tr.locale = "tr"
	var count: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges().is_empty():
			continue
		var cols: PackedStringArray = _parse_csv_line(line)
		if cols.is_empty():
			continue
		var key: String = cols[0].strip_edges()
		if key.is_empty() or key.to_lower() == "keys":
			continue
		var en_v: String = cols[en_i] if cols.size() > en_i else ""
		var tr_v: String = cols[tr_i] if cols.size() > tr_i else ""
		t_en.add_message(StringName(key), en_v)
		t_tr.add_message(StringName(key), tr_v)
		count += 1
	f.close()

	var e1: Error = ResourceSaver.save(t_en, OUT_EN_TRES)
	var e2: Error = ResourceSaver.save(t_tr, OUT_TR_TRES)
	t_en.locale = "en"
	t_tr.locale = "tr"
	var e3: Error = ResourceSaver.save(t_en, OUT_EN_BIN)
	var e4: Error = ResourceSaver.save(t_tr, OUT_TR_BIN)
	if e1 != OK or e2 != OK or e3 != OK or e4 != OK:
		push_error("ResourceSaver failed tres_en=%d tres_tr=%d bin_en=%d bin_tr=%d" % [e1, e2, e3, e4])
		return 1
	print("[LOCALE BUILD] wrote %d keys -> tres+translation (%s / %s)" % [count, OUT_EN_BIN, OUT_TR_BIN])
	return 0


func _parse_csv_line(line: String) -> PackedStringArray:
	# Minimal RFC4180-ish split: supports "quoted, commas".
	var out: PackedStringArray = PackedStringArray()
	var cur: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					cur += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			cur += ch
			i += 1
			continue
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	out.append(cur)
	return out
