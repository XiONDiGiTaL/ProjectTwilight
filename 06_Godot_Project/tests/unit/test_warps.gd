extends RefCounted
## Map setup from maps.json, warp detection and respawn points.


static func _open_gat(w := 400, h := 400) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func test_setup_map_populates(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 4)
	sim.setup_map("prt_fild08")
	var monsters := 0
	for u in sim.units.values():
		if not u.is_player():
			monsters += 1
	if monsters != 57:
		return "expected 57 field monsters, got %d" % monsters
	if sim.warps.size() != 1 or sim.warps[0].to_map != "prontera":
		return "warps wrong: %s" % str(sim.warps)
	if sim.npcs.size() != 1 or sim.respawn_cell != Vector2i(170, 200):
		return "npcs/respawn wrong"
	var town := FieldSimulation.new(_open_gat(312, 392), 4)
	town.setup_map("prontera")
	return true if town.units.is_empty() and town.warps[0].to_map == "prt_fild08" else "town should have no monsters"


func test_walking_onto_warp(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 5)
	sim.setup_map("prt_fild08")
	var p := sim.add_player("Traveler", Vector2i(170, 368), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	sim.drain_events()
	sim.command_move(p.id, Vector2i(170, 376))
	var warps := 0
	var dest: Dictionary = {}
	for i in 200:
		sim.tick(50.0)
		for ev in sim.drain_events():
			if ev.type == "warp":
				warps += 1
				dest = ev
	if warps != 1:
		return "expected exactly one warp event, got %d" % warps
	return true if dest.to_map == "prontera" and dest.to_cell == Vector2i(156, 40) else "destination wrong: %s" % dest


## Fallen players return to their save point: Prontera (the hub) by default,
## which from a field means a revive event that moves them to Prontera; on
## the save map itself they stand up at the saved cell.
func test_respawn_at_save_point(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 6)
	sim.setup_map("prt_fild08")
	var p := sim.add_player("Unlucky", Vector2i(300, 300), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	var m := sim.add_monster("1063", Vector2i(301, 300), 0)
	sim._kill(p, m)
	sim.drain_events()
	sim.tick(FieldSimulation.PLAYER_REVIVE_MS + 50.0)
	var ev: Array = sim.drain_events().filter(func(e): return e.type == "revive" and e.id == p.id)
	if ev.is_empty() or String(ev[0].get("to_map", "")) != "prontera" or ev[0].to_cell != Vector2i(156, 191):
		return "should return to the Prontera save point: %s" % [ev]
	if p.dead or p.hp != p.max_hp:
		return "not revived"
	var town := FieldSimulation.new(_open_gat(400, 400), 7)
	town.setup_map("prontera")
	var q := town.add_player("Local", Vector2i(100, 100), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	town._kill(q, q)
	town.tick(FieldSimulation.PLAYER_REVIVE_MS + 50.0)
	return true if q.walker.cell == Vector2i(156, 191) else "town revive at %s" % q.walker.cell


func test_warp_span_area(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 8)
	sim.setup_map("prt_fild08", [{"cell": Vector2i(50, 50), "span": Vector2i(2, 1), "to_map": "prontera", "to_cell": Vector2i(1, 1), "name": "w"}])
	if sim.warp_at(Vector2i(52, 51)).is_empty():
		return "edge of the span area should trigger"
	if not sim.warp_at(Vector2i(53, 50)).is_empty() or not sim.warp_at(Vector2i(50, 52)).is_empty():
		return "outside the span should not trigger"
	return true if sim.warps.size() == 1 else "rAthena warps should replace maps.json warps"


func test_training_map_alias(_t) -> Variant:
	if MapAliases._alias("new_1-1") != "new_zone01" or MapAliases._alias("new_5-4") != "new_zone04":
		return "alias pattern wrong"
	return true if MapAliases._alias("prontera") == "" and CharacterRules.START_MAP == "new_1-1" else "start map / alias wrong"
