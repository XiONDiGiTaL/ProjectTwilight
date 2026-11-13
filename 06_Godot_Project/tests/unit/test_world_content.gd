extends RefCounted
## rAthena-referenced Prontera-field content: monster rows, spawn tables and
## the immovable / non-attacker mode used by Pupa.


static func _gat(w := 400, h := 400) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func test_new_monster_rows(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(20, 20), 1)
	var expected := {
		"1004": ["Hornet", 8, 169, "wind", "insect", "small"],
		"1008": ["Pupa", 2, 427, "earth", "insect", "small"],
		"1018": ["Creamy", 16, 595, "wind", "insect", "small"],
		"1031": ["Poporing", 14, 344, "poison", "plant", "medium"],
		"1051": ["Thief Bug", 6, 126, "neutral", "insect", "small"],
		"1052": ["Rocker", 9, 198, "earth", "insect", "medium"],
		"1113": ["Drops", 3, 55, "fire", "plant", "medium"],
	}
	for id in expected:
		var row: Dictionary = sim.monster_db.get(id, {})
		var want: Array = expected[id]
		if row.is_empty():
			return "missing monster %s" % id
		if String(row.name) != want[0] or int(row.level) != want[1] or int(row.hp) != want[2]:
			return "%s stats wrong: %s" % [id, row]
		if String(row.element) != want[3] or String(row.race) != want[4] or String(row.size) != want[5]:
			return "%s element/race/size wrong" % id
		if int(row.atk[0]) <= 0 or int(row.atk[1]) < int(row.atk[0]):
			return "%s attack range wrong" % id
		if String(row.sprite) == "":
			return "%s has no sprite" % id
	return true


func test_new_field_spawn_tables(_t) -> Variant:
	var maps := ["prt_fild00", "prt_fild04", "prt_fild05"]
	for map_name in maps:
		var info: Dictionary = FieldSimulation._load_json(FieldSimulation.MAP_DB).get(map_name, {})
		if info.is_empty() or String(info.get("name", "")) == "":
			return "missing map %s" % map_name
		if not info.has("spawns") or (info.spawns as Dictionary).is_empty():
			return "map %s has no spawn table" % map_name
		var sim := FieldSimulation.new(_gat(), 7)
		sim.setup_map(map_name)
		var expected := 0
		for mob in info.spawns:
			expected += int(info.spawns[mob])
		var actual := 0
		for id in sim.units:
			if not (sim.units[id] as SimUnit).is_player():
				actual += 1
		if actual != expected:
			return "%s spawned %d monsters, expected %d" % [map_name, actual, expected]
		if sim.respawn_cell == Vector2i(-1, -1):
			return "%s has no respawn cell" % map_name
	return true


func test_pupa_is_immovable_and_harmless(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(40, 40), 3)
	var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	var pupa := sim.add_monster("1008", Vector2i(11, 10))
	if pupa == null or not pupa.immovable or not pupa.non_attacker:
		return "Pupa flags missing"
	var cell := pupa.cell()
	for i in 100:
		sim.tick(50.0)
	if pupa.cell() != cell:
		return "Pupa wandered from %s to %s" % [cell, pupa.cell()]
	sim.drain_events()
	if not sim.command_attack(p.id, pupa.id):
		return "could not attack Pupa"
	for i in 200:
		sim.tick(50.0)
		for ev in sim.drain_events():
			if String(ev.get("type", "")) == "attack" and int(ev.get("id", 0)) == pupa.id:
				return "Pupa attacked back"
	return true if pupa.target_id == 0 else "Pupa acquired a target"
