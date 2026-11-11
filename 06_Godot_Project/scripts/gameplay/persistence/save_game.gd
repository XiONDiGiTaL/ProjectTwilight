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
const VERSION := 2  # v2 adds "equipment"; v1 files still load
const SAVE_DIR := "user://saves/"
const STAT_NAMES := ["str", "agi", "vit", "int", "dex", "luk"]


static func path_for(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


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
			"equipment": u.equipment.duplicate(),
			"map": map_name, "cell": [u.walker.cell.x, u.walker.cell.y],
		},
	}


static func write(slot: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var final_path := path_for(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var dir := DirAccess.open(SAVE_DIR)
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
	out.hp = maxi(1, int(c.get("hp", 1)))
	out.sp = maxi(0, int(c.get("sp", 0)))
	out.zeny = clampi(int(c.get("zeny", 0)), 0, 1000000000)
	var inv: Variant = c.get("inventory", [])
	out.inventory = Inventory.from_array(inv if inv is Array else [], item_db).to_array()
	var eq := {}
	var raw_eq: Variant = c.get("equipment", {})
	if raw_eq is Dictionary:
		for slot in raw_eq:
			var id := int(raw_eq[slot])
			if item_db.has(str(id)) and String(item_db[str(id)].get("equip", "")) != "":
				eq[String(slot)] = id
	out.equipment = eq
	out.map = String(c.get("map", ""))
	var cell: Variant = c.get("cell", [0, 0])
	out.cell = Vector2i(int(cell[0]), int(cell[1])) if cell is Array and cell.size() == 2 else Vector2i.ZERO
	return {"ok": true, "error": "", "character": out}
