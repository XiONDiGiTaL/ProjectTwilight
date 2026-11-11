extends RefCounted
## Character creation rules, slots and save v3 appearance.

const TEST_DIR := "user://test_saves/"


static func _db() -> Dictionary:
	var db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	db.erase("_provenance")
	return db


static func _open_gat() -> GatFile:
	var g := GatFile.new()
	g.width = 300
	g.height = 300
	g.heights.resize(300 * 300 * 4)
	g.types.resize(300 * 300)
	return g


func test_hexagon_spends_all_48_points(_t) -> Variant:
	for s in [[1, 1, 1], [5, 5, 5], [9, 1, 9], [9, 9, 9], [3, 7, 2]]:
		var st := CharacterRules.stats_from_pairs(s[0], s[1], s[2])
		if not CharacterRules.valid_hexagon(st):
			return "hexagon %s invalid" % str(s)
		if CharacterRules.remaining_points(st) != 0:
			return "build %s leaves %d points" % [str(s), CharacterRules.remaining_points(st)]
	if CharacterRules.valid_hexagon({"str": 9, "int": 9, "agi": 5, "luk": 5, "vit": 5, "dex": 5}):
		return "pair summing to 18 accepted"
	return true


func test_hexagon_widget_keeps_pairs(_t) -> Variant:
	var h := StatHexagon.new()
	for i in 6:
		h.raise("str")
	if h.stats.str != 9 or h.stats.int != 1:
		return "STR should cap at 9 with INT 1: %s" % h.stats
	h.raise("int")
	h.free()
	return true


func test_name_rules(_t) -> Variant:
	var R := CharacterRules
	var cases := {
		"Bob": false, "Adventurer": true, "Twilight Hero": true, " Lead": false, "Trail ": false,
		"Two  Spaces": false, "Bad!Name": false, "ThisNameIsWayTooLongToBeUsed": false, "라그나로크": true,
	}
	for n in cases:
		var ok: bool = R.validate_name(n, []) == ""
		if ok != cases[n]:
			return "name '%s' expected %s" % [n, cases[n]]
	if R.validate_name("adventurer", ["Adventurer"]) == "":
		return "duplicate (case-insensitive) accepted"
	return true


func test_slots_create_list_delete(_t) -> Variant:
	var old_dir := SaveGame.save_dir
	SaveGame.save_dir = TEST_DIR
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR + f)
	var db := _db()
	var ch := CharacterRules.new_character("Slot Tester", false, 5, 3, CharacterRules.stats_from_pairs(7, 3, 5))
	ch.cell = [ch.cell.x, ch.cell.y]
	var err := SaveGame.write("slot2", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var listing := SaveGame.list_slots(CharacterRules.MAX_SLOTS, db, ClassInsignia.classes())
	var result: Variant = true
	if err != OK or listing.size() != 6:
		result = "write/list failed"
	elif listing[0].ok or not listing[1].ok or listing[1].character.name != "Slot Tester":
		result = "slot contents wrong"
	elif listing[1].character.male != false or listing[1].character.hair_style != 5 or listing[1].character.hair_color != 3:
		result = "appearance not saved"
	elif SaveGame.delete("slot2") != OK or SaveGame.exists("slot2"):
		result = "delete failed"
	SaveGame.save_dir = old_dir
	return result


func test_new_character_spawns_full_with_gear(_t) -> Variant:
	var ch := CharacterRules.new_character("Fresh Novice", true, 2, 0, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [ch.cell.x, ch.cell.y]
	var data: Variant = JSON.parse_string(JSON.stringify({"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "character": ch}))
	var sim := FieldSimulation.new(_open_gat(), 1)
	var r := SaveGame.validate(data, sim.item_db, ClassInsignia.classes())
	if not r.ok:
		return r.error
	var p := sim.add_player_from_save(r.character)
	if p.hp != p.max_hp or p.sp != p.max_sp:
		return "new character should start at full HP/SP (%d/%d)" % [p.hp, p.max_hp]
	if p.equipment.get("weapon", 0) != 1201 or p.equipment.get("body", 0) != 2301:
		return "starting gear not equipped: %s" % p.equipment
	return true if p.status_points == 0 and p.inventory.count(501) == 3 else "points/potions wrong"


func test_v2_save_gets_default_look(_t) -> Variant:
	var r := SaveGame.validate({"format": SaveGame.FORMAT, "version": 2, "character": {"name": "Oldtimer", "job": "novice"}},
		_db(), ClassInsignia.classes())
	if not r.ok:
		return r.error
	var c: Dictionary = r.character
	return true if c.male == true and c.hair_style == 2 and c.hair_color == 0 else "defaults wrong: %s" % c
