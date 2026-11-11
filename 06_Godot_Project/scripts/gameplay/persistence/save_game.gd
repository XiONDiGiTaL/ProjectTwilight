class_name SaveGame
extends RefCounted
## Versioned local character saves (offline mode).
##
## Format (JSON, user://saves/<slot>.json):
##   {"format": "project-twilight-save", "version": 1, "saved_at": unix,
##    "character": {name, job, level, job_level, base_exp, job_exp, stats{},
##                  status_points, hp, sp, zeny, inventory[{id, amount}],
##                  map, cell: [x, y]}}
## Loading validates every field and clamps it to legal ranges, so a damaged
## or hand-edited file cannot produce an invalid character. Writes go to a
## temporary file first and are then renamed, so a crash never leaves a
## half-written save.

const FORMAT := "project-twilight-save"
const VERSION := 7  # v2 equipment, v3 appearance, v4 skills + hotkeys, v5 aura + cloth dye + second jobs, v6 Kafra storage, v7 guild membership; older files still load
## Save folder; tests point this at a temporary folder.
static var save_dir := "user://saves/"
const STAT_NAMES := ["str", "agi", "vit", "int", "dex", "luk"]


## Lists saved characters: [{slot, ok, error, character}] for slot1..slotN in order.
static func list_slots(max_slots: int, item_db: Dictionary, classes: Dictionary) -> Array:
	var out := []
	for i in max_slots:
		var slot := "slot%d" % (i + 1)
		if exists(slot):
			var r := read(slot, item_db, classes)
			out.append({"slot": slot, "ok": r.ok, "error": r.error, "character": r.character})
		else:
			out.append({"slot": slot, "ok": false, "error": "", "character": {}})
	return out


## Permanently deletes a slot's save file. Returns OK or an error.
static func delete(slot: String) -> Error:
	if not exists(slot):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path_for(slot))


static func path_for(slot: String) -> String:
	return save_dir + slot + ".json"


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_for(slot))


## Serialises a player SimUnit plus its location.
static func capture(u: SimUnit, map_name: String) -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"character": {
			"name": u.name, "job": u.job,
			"level": u.level, "job_level": u.job_level,
			"base_exp": u.base_exp, "job_exp": u.job_exp,
			"stats": u.stats.duplicate(), "status_points": u.status_points,
			"hp": u.hp, "sp": u.sp, "zeny": u.zeny,
			"inventory": u.inventory.to_array(),
			"storage": u.storage.to_array(),
			"equipment": u.equipment.duplicate(),
			"male": u.male, "hair_style": u.hair_style, "hair_color": u.hair_color, "aura": u.aura, "cloth_color": u.cloth_color, "script_vars": _vars_out(u.script_vars), "options": u.options.duplicate(), "save_map": u.save_map, "save_cell": [u.save_cell.x, u.save_cell.y],
			"skills": u.skills.duplicate(), "skill_points": u.skill_points, "hotkeys": u.hotkeys.duplicate(true),
			"guild_id": u.guild_id, "guild_name": u.guild_name,
			"map": map_name, "cell": [u.walker.cell.x, u.walker.cell.y],
		},
	}


## Script variable arrays have int indexes; JSON needs string keys.
static func _vars_out(v: Dictionary) -> Dictionary:
	var out := {}
	for k in v:
		var arr := {}
		for i in v[k]:
			arr[str(i)] = v[k][i]
		out[String(k)] = arr
	return out


static func _vars_in(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		if not (v[k] is Dictionary) or String(k).length() > 32:
			continue
		var arr := {}
		for i in v[k]:
			var val: Variant = v[k][i]
			if val is float:
				val = int(val)
			if (val is int or val is String) and String(i).is_valid_int() and arr.size() < 128:
				arr[int(i)] = val if not (val is String) else String(val).left(255)
		out[String(k)] = arr
		if out.size() >= 512:
			break
	return out


static func write(slot: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var final_path := path_for(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var dir := DirAccess.open(save_dir)
	if dir.file_exists(final_path.get_file()):
		dir.remove(final_path.get_file())
	return dir.rename(tmp_path.get_file(), final_path.get_file())


## Returns {"ok": bool, "error": String, "character": Dictionary (validated)}.
static func read(slot: String, item_db: Dictionary, classes: Dictionary) -> Dictionary:
	if not exists(slot):
		return {"ok": false, "error": "No save in slot %s." % slot, "character": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(slot)))
	return validate(parsed, item_db, classes)


static func validate(parsed: Variant, item_db: Dictionary, classes: Dictionary) -> Dictionary:
	if not (parsed is Dictionary) or parsed.get("format", "") != FORMAT:
		return {"ok": false, "error": "Not a Project Twilight save file.", "character": {}}
	var version := int(parsed.get("version", 0))
	if version < 1 or version > VERSION:
		return {"ok": false, "error": "Save version %d is not supported by this build." % version, "character": {}}
	var c: Variant = parsed.get("character", {})
	if not (c is Dictionary):
		return {"ok": false, "error": "Save has no character.", "character": {}}
	var out := {}
	var name := String(c.get("name", "Adventurer")).strip_edges().left(23)
	out.name = name if name != "" else "Adventurer"
	var job := String(c.get("job", "novice"))
	out.job = job if classes.has(job) else "novice"
	out.level = clampi(int(c.get("level", 1)), 1, 99)
	out.job_level = clampi(int(c.get("job_level", 1)), 1, 70)
	out.base_exp = maxi(0, int(c.get("base_exp", 0)))
	out.job_exp = maxi(0, int(c.get("job_exp", 0)))
	var stats := {}
	var raw_stats: Variant = c.get("stats", {})
	for k in STAT_NAMES:
		stats[k] = clampi(int(raw_stats.get(k, 1)) if raw_stats is Dictionary else 1, 1, 99)
	out.stats = stats
	out.status_points = clampi(int(c.get("status_points", 0)), 0, 9999)
	out.hp = maxi(0, int(c.get("hp", 0)))   # 0 = full on load
	out.sp = maxi(0, int(c.get("sp", 0)))
	out.male = bool(c.get("male", true))
	out.hair_style = clampi(int(c.get("hair_style", 2)), 1, 99)
	out.hair_color = clampi(int(c.get("hair_color", 0)), 0, 131)
	out.cloth_color = clampi(int(c.get("cloth_color", 0)), 0, 699)
	out.script_vars = _vars_in(c.get("script_vars", {}))
	var opts := {}
	var raw_opts: Variant = c.get("options", {})
	if raw_opts is Dictionary:
		for k in ["falcon", "cart", "peco"]:
			if raw_opts.has(k):
				opts[k] = bool(raw_opts[k])
	out.options = opts
	out.guild_id = String(c.get("guild_id", "")).left(24)
	out.guild_name = String(c.get("guild_name", "")).left(24)
	if out.guild_id == "":
		out.guild_name = ""
	var sm := String(c.get("save_map", SimUnit.HUB_MAP))
	out.save_map = sm if sm.is_valid_filename() and sm.length() <= 32 and sm != "" else SimUnit.HUB_MAP
	var sc: Variant = c.get("save_cell", [SimUnit.HUB_CELL.x, SimUnit.HUB_CELL.y])
	out.save_cell = [clampi(int(sc[0]), 0, 1024), clampi(int(sc[1]), 0, 1024)] if sc is Array and sc.size() == 2 else [SimUnit.HUB_CELL.x, SimUnit.HUB_CELL.y]
	var aura := String(c.get("aura", "class"))
	out.aura = aura if PlayerAura.is_valid(aura) else "class"
	out.zeny = clampi(int(c.get("zeny", 0)), 0, 1000000000)
	var inv: Variant = c.get("inventory", [])
	out.inventory = Inventory.from_array(inv if inv is Array else [], item_db).to_array()
	var stored: Variant = c.get("storage", [])
	var stored_inv := Inventory.from_array(stored if stored is Array else [], item_db)
	while stored_inv.entries.size() > SimUnit.STORAGE_SLOTS:
		stored_inv.entries.remove_at(stored_inv.entries.size() - 1)
	out.storage = stored_inv.to_array()
	var eq := {}
	var raw_eq: Variant = c.get("equipment", {})
	if raw_eq is Dictionary:
		for slot in raw_eq:
			var id := int(raw_eq[slot])
			if item_db.has(str(id)) and String(item_db[str(id)].get("equip", "")) != "":
				eq[String(slot)] = id
	out.equipment = eq
	var sk := {}
	var raw_sk: Variant = c.get("skills", {})
	if raw_sk is Dictionary:
		for code in raw_sk:
			sk[String(code)] = clampi(int(raw_sk[code]), 0, 10)
	if not sk.is_empty():
		out.skills = sk
		out.skill_points = clampi(int(c.get("skill_points", 0)), 0, 300)
	var hk := []
	var raw_hk: Variant = c.get("hotkeys", [])
	if raw_hk is Array:
		for e in raw_hk.slice(0, 9):
			if e is Dictionary and String(e.get("type", "")) in ["item", "skill"]:
				hk.append({"type": String(e.type), "id": e.get("id")})
			else:
				hk.append(null)
	out.hotkeys = hk
	out.map = String(c.get("map", ""))
	var cell: Variant = c.get("cell", [0, 0])
	out.cell = Vector2i(int(cell[0]), int(cell[1])) if cell is Array and cell.size() == 2 else Vector2i.ZERO
	return {"ok": true, "error": "", "character": out}
