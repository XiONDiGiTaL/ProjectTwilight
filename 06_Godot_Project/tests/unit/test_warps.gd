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
	if monsters != 49:
		return "expected 49 field monsters, got %d" % monsters
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


func test_respawn_at_map_point(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 6)
	sim.setup_map("prt_fild08")
	var p := sim.add_player("Unlucky", Vector2i(300, 300), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	var m := sim.add_monster("1063", Vector2i(301, 300), 0)
	p.hp = 1
	sim._kill(p, m)
	sim.tick(FieldSimulation.PLAYER_REVIVE_MS + 50.0)
	return true if not p.dead and p.walker.cell == sim.respawn_cell and p.hp == p.max_hp else "respawn wrong: %s" % p.walker.cell
