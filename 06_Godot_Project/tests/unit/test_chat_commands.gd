extends RefCounted
## At-commands (@go, @heal, @save, @mobinfo ...). They must run through the
## simulation, so a host or server can validate them the same way.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}


static func _gat(w := 120, h := 120) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func _field() -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), 17, RuleConfig.new())
	sim.map_name = "prt_fild08"
	sim.map_info = sim.map_db.get("prt_fild08", {})
	sim.respawn_cell = Vector2i(60, 60)
	return sim


func test_help_and_unknown(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Tester", Vector2i(50, 50), FLAT)
	var help := ChatCommands.execute(sim, p, "@help")
	if not help.ok or not String(help.text).contains("@go"):
		return "@help should list the commands: %s" % help.text
	var bad := ChatCommands.execute(sim, p, "@nope")
	if bad.ok or not String(bad.text).contains("@help"):
		return "unknown commands should fail with a hint"
	var say := ChatCommands.execute(sim, p, "hello world")
	return true if say.ok and String(say.text).contains("hello world") else "plain text should echo"


func test_heal_save_and_where(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Tester", Vector2i(50, 50), FLAT)
	p.hp = 1
	p.sp = 0
	ChatCommands.execute(sim, p, "@heal")
	if p.hp != p.max_hp or p.sp != p.max_sp:
		return "@heal should fully restore HP and SP"
	p.walker = GridWalker.new(Vector2i(70, 72))
	ChatCommands.execute(sim, p, "@save")
	if p.save_map != "prt_fild08" or p.save_cell != Vector2i(70, 72):
		return "@save should store the current map and cell"
	var where := ChatCommands.execute(sim, p, "@where")
	return true if String(where.text).contains("72") else "@where should show the cell"


func test_go_and_warp_actions(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Traveler", Vector2i(50, 50), FLAT)
	var go := ChatCommands.execute(sim, p, "@go prontera")
	if not go.has("action") or String(go.action.map) != "prontera":
		return "@go should return a warp action"
	if int(go.action.x) != 156 or int(go.action.y) != 191:
		return "@go prontera should use the hub cell"
	var warp := ChatCommands.execute(sim, p, "@warp geffen 120 60")
	if not warp.has("action") or int(warp.action.x) != 120 or int(warp.action.y) != 60:
		return "@warp should carry the requested cell"
	return true if String(warp.action.map) == "geffen" else "@warp map wrong"


func test_die_and_revive(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Unlucky", Vector2i(50, 50), FLAT)
	var die := ChatCommands.execute(sim, p, "@die")
	if not die.ok or not p.dead:
		return "@die should fell the player"
	var rev := ChatCommands.execute(sim, p, "@revive")
	if not rev.ok or p.dead or p.hp <= 0:
		return "@revive should stand the player up at half HP"
	var again := ChatCommands.execute(sim, p, "@revive")
	return true if not again.ok else "@revive should refuse a living player"


func test_mobinfo_who_rates_and_job(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Tester", Vector2i(50, 50), FLAT)
	sim.add_player("Friend", Vector2i(52, 50), FLAT)
	var info := ChatCommands.execute(sim, p, "@mobinfo poring")
	if not info.ok or not String(info.text).contains("HP 50"):
		return "@mobinfo should find Poring and its HP: %s" % info.text
	var who := ChatCommands.execute(sim, p, "@who")
	if not String(who.text).contains("Friend"):
		return "@who should list players on the map"
	var rates := ChatCommands.execute(sim, p, "@rates")
	if not String(rates.text).contains("EXP x"):
		return "@rates should describe the rule set"
	var job := ChatCommands.execute(sim, p, "@job")
	return true if String(job.text).contains("Novice") else "@job should name the class"


func test_rates_preset_action(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Rates", Vector2i(50, 50), FLAT)
	for spec in [["1", 1], ["25", 25], ["50", 50], ["default", 0]]:
		var r := ChatCommands.execute(sim, p, "@rates %s" % spec[0])
		if not r.ok or not r.has("action"):
			return "@rates %s should return a preset action" % spec[0]
		if String(r.action.kind) != "rate_preset" or int(r.action.multiplier) != int(spec[1]):
			return "@rates %s carried the wrong action: %s" % [spec[0], r.action]
		if String(r.text) != "":
			return "@rates %s should leave feedback to the field" % spec[0]
	var bad := ChatCommands.execute(sim, p, "@rates 2")
	if bad.ok or not String(bad.text).contains("Usage"):
		return "@rates should reject unknown presets"
	var extra := ChatCommands.execute(sim, p, "@rates 25 50")
	if extra.ok or not String(extra.text).contains("Usage"):
		return "@rates should reject extra arguments"
	var current := ChatCommands.execute(sim, p, "@rates")
	return true if current.ok and String(current.text).contains("EXP x") \
		else "@rates without an argument should still describe the rules"


func test_autoloot_toggle(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Looter", Vector2i(50, 50), FLAT)
	ChatCommands.execute(sim, p, "@autoloot")
	if not sim.rules.autoloot:
		return "@autoloot should toggle on"
	ChatCommands.execute(sim, p, "@autoloot off")
	return true if not sim.rules.autoloot else "@autoloot off should toggle off"
