extends RefCounted
## Inventory rules, loot, item use, stat raising and save files.


static func _open_gat(w: int, h: int) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _sim() -> FieldSimulation:
	return FieldSimulation.new(_open_gat(40, 40), 11)


static func _player(sim: FieldSimulation) -> SimUnit:
	return sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})


func test_inventory_stacking_and_weight(_t) -> Variant:
	var sim := _sim()
	var inv := Inventory.new()
	if not inv.add(909, 5, sim.item_db, 100) or not inv.add(909, 3, sim.item_db, 100):
		return "jellopy should stack"
	if inv.entries.size() != 1 or inv.count(909) != 8:
		return "stack wrong: %s" % str(inv.entries)
	if inv.add(1201, 3, sim.item_db, 100):
		return "3 knives (120 weight) must exceed limit 100"
	if not inv.add(1201, 2, sim.item_db, 100) or inv.entries.size() != 3:
		return "equipment should not stack"
	if inv.remove_at(0, 8) != 909 or inv.count(909) != 0:
		return "remove failed"
	return true if inv.weight(sim.item_db) == 80 else "weight wrong: %d" % inv.weight(sim.item_db)


func test_max_weight_formula(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	return true if p.max_weight() == 2150 else "expected 2000 + 5*30"


func test_kill_drops_and_pickup(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	var got_drop := false
	for attempt in 8:
		var m := sim.add_monster("1002", Vector2i(12, 10), 0)
		m.hp = 1
		sim.command_attack(p.id, m.id)
		for i in 100:
			sim.tick(50.0)
			if m.dead:
				break
		if not sim.ground_items.is_empty():
			got_drop = true
			break
	if not got_drop:
		return "8 Poring kills dropped nothing (Jellopy is 70%)"
	var gid: int = sim.ground_items.keys()[0]
	var item: int = sim.ground_items[gid].item
	var before := p.inventory.count(item)
	sim.drain_events()
	sim.command_pickup(p.id, gid)
	for i in 100:
		sim.tick(50.0)
	if sim.ground_items.has(gid) or p.inventory.count(item) != before + 1:
		return "pickup failed"
	var saw_pickup := false
	for ev in sim.drain_events():
		saw_pickup = saw_pickup or ev.type == "pickup"
	return true if saw_pickup else "no pickup event"


func test_owner_priority(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	var gid := sim.spawn_ground_item(909, 1, Vector2i(11, 10))
	sim.ground_items[gid].owner = 9999  # someone else's loot
	sim.command_pickup(p.id, gid)
	for i in 10:
		sim.tick(50.0)
	if not sim.ground_items.has(gid):
		return "picked up another player's loot during priority"
	sim.ground_items[gid].age = FieldSimulation.OWNER_PRIORITY_MS + 1.0
	sim.command_pickup(p.id, gid)
	for i in 10:
		sim.tick(50.0)
	return true if not sim.ground_items.has(gid) else "could not pick up after priority expired"


func test_use_potion(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	p.inventory.add(501, 2, sim.item_db, p.max_weight())
	p.inventory.add(909, 1, sim.item_db, p.max_weight())
	p.hp = 1
	if sim.command_use_item(p.id, 1):
		return "jellopy must not be usable"
	if not sim.command_use_item(p.id, 0):
		return "potion use failed"
	if p.hp < 1 + 1 or p.inventory.count(501) != 1:
		return "potion did not heal or was not consumed"
	return true


func test_raise_stat(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	var points := p.status_points
	var old_atk := p.atk_max
	if not sim.command_raise_stat(p.id, "str"):
		return "raise failed"
	if p.stats.str != 6 or p.status_points != points - 2 or p.atk_max <= old_atk:
		return "raise effects wrong"
	p.status_points = 0
	return true if not sim.command_raise_stat(p.id, "str") else "raised without points"


func test_save_roundtrip(_t) -> Variant:
	var sim := _sim()
	var p := _player(sim)
	p.level = 7
	p.base_exp = 33
	p.zeny = 1234
	p.inventory.add(909, 4, sim.item_db, p.max_weight())
	p.inventory.add(1201, 1, sim.item_db, p.max_weight())
	var data := SaveGame.capture(p, "prt_fild08")
	var round: Variant = JSON.parse_string(JSON.stringify(data))
	var r := SaveGame.validate(round, sim.item_db, ClassInsignia.classes())
	if not r.ok:
		return "validate failed: %s" % r.error
	var sim2 := _sim()
	var q := sim2.add_player_from_save(r.character)
	if q.level != 7 or q.base_exp != 33 or q.zeny != 1234 or q.inventory.count(909) != 4 or q.inventory.count(1201) != 1:
		return "roundtrip lost data"
	return true if q.walker.cell == p.walker.cell else "position lost"


func test_save_rejects_and_clamps(_t) -> Variant:
	var classes := ClassInsignia.classes()
	var db := _sim().item_db
	if SaveGame.validate("garbage", db, classes).ok:
		return "accepted garbage"
	if SaveGame.validate({"format": "project-twilight-save", "version": 99, "character": {}}, db, classes).ok:
		return "accepted future version"
	var r := SaveGame.validate({"format": "project-twilight-save", "version": 1, "character": {
		"name": "", "job": "dragon_god", "level": 500, "stats": {"str": 400, "agi": -3},
		"inventory": [{"id": 909, "amount": 2}, {"id": 99999, "amount": 1}, {"id": 501, "amount": -4}]}}, db, classes)
	if not r.ok:
		return "should clamp, not reject: %s" % r.error
	var c: Dictionary = r.character
	if c.job != "novice" or c.level != 99 or c.stats.str != 99 or c.stats.agi != 1 or c.name != "Adventurer":
		return "clamping wrong: %s" % c
	return true if c.inventory.size() == 1 else "invalid items kept: %s" % str(c.inventory)
