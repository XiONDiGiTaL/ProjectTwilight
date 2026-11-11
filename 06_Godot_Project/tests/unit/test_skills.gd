extends RefCounted
## Novice skills, posture, natural regeneration and save v4.


static func _open_gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _setup() -> Array:
	var sim := FieldSimulation.new(_open_gat(), 31)
	var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	return [sim, p]


func test_defaults_and_learning(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	if p.skills.get("NV_FIRSTAID", 0) != 1 or p.skills.get("NV_TRICKDEAD", 0) != 1 or p.skills.get("NV_BASIC", -1) != 0:
		return "default skills wrong: %s" % p.skills
	if p.skill_points != 0 or sim.command_learn_skill(p.id, "NV_BASIC"):
		return "learned without points"
	sim._gain_exp(p, 0, 10)  # job level 1 -> 2 grants a point
	if p.job_level != 2 or p.skill_points != 1:
		return "job level up should grant a skill point (jl %d sp %d)" % [p.job_level, p.skill_points]
	if not sim.command_learn_skill(p.id, "NV_BASIC") or p.skills.NV_BASIC != 1 or p.skill_points != 0:
		return "learning failed"
	return true if not sim.command_learn_skill(p.id, "NV_FIRSTAID") else "quest skill learned with points"


func test_first_aid(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	p.hp = 10
	p.sp = 5
	if not sim.command_use_skill(p.id, "NV_FIRSTAID") or p.hp != 15 or p.sp != 2:
		return "first aid wrong: hp %d sp %d" % [p.hp, p.sp]
	if sim.command_use_skill(p.id, "NV_FIRSTAID"):
		return "used during after-cast delay / without SP"
	sim.tick(1100.0)
	return true if not sim.command_use_skill(p.id, "NV_FIRSTAID") else "used with 2 SP (needs 3)"


func test_play_dead(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	var m := sim.add_monster("1063", Vector2i(11, 10), 0)
	m.target_id = p.id
	p.sp = 10
	if not sim.command_use_skill(p.id, "NV_TRICKDEAD") or not p.trickdead or p.sp != 5:
		return "play dead did not activate"
	if m.target_id != 0:
		return "monster kept its target"
	if sim.command_move(p.id, Vector2i(15, 10)) or sim.command_attack(p.id, m.id):
		return "moved or attacked while playing dead"
	sim._provoke(m, p)
	if m.target_id != 0:
		return "monster re-targeted a feigning player"
	if not sim.command_use_skill(p.id, "NV_TRICKDEAD") or p.trickdead or p.sp != 5:
		return "getting up should be free and end the state"
	return true


func test_sitting_requires_basic_3(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	if sim.command_sit(p.id):
		return "sat without Basic Skill 3"
	p.skills.NV_BASIC = 3
	if not sim.command_sit(p.id) or not p.sitting:
		return "could not sit"
	sim.command_move(p.id, Vector2i(14, 10))
	return true if not p.sitting else "moving should stand up"


func test_regen(_t) -> Variant:
	if RegenRulesPreRenewal.hp_amount(400, 20) != 6 or RegenRulesPreRenewal.hp_amount(50, 1) != 1:
		return "hp regen formula wrong"
	if RegenRulesPreRenewal.sp_amount(150, 12) != 4:
		return "sp regen formula wrong"
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	p.hp = 1
	sim.tick(5900.0)
	if p.hp != 1:
		return "regenerated before 6 s"
	sim.tick(200.0)
	if p.hp <= 1:
		return "no regen after 6 s standing"
	p.skills.NV_BASIC = 3
	sim.command_sit(p.id)
	var hp := p.hp
	sim.tick(3050.0)
	if p.hp <= hp:
		return "sitting should regenerate every 3 s"
	# Overweight (>= 50%) blocks regeneration.
	p.inventory.add(1201, 30, sim.item_db, 100000)
	hp = p.hp
	p.hp = 1
	sim.tick(7000.0)
	return true if p.hp == 1 else "regenerated while overweight"


func test_save_v4_skills_hotkeys(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	p.skills.NV_BASIC = 4
	p.skill_points = 2
	p.hotkeys[0] = {"type": "skill", "id": "NV_FIRSTAID"}
	p.hotkeys[3] = {"type": "item", "id": 501}
	var data: Variant = JSON.parse_string(JSON.stringify(SaveGame.capture(p, "prt_fild08")))
	var r := SaveGame.validate(data, sim.item_db, ClassInsignia.classes())
	var q := FieldSimulation.new(_open_gat(), 2).add_player_from_save(r.character)
	if q.skills.get("NV_BASIC", 0) != 4 or q.skill_points != 2:
		return "skills not restored: %s / %d" % [q.skills, q.skill_points]
	if q.hotkeys[0] == null or q.hotkeys[0].id != "NV_FIRSTAID" or q.hotkeys[3] == null or int(q.hotkeys[3].id) != 501:
		return "hotkeys not restored: %s" % str(q.hotkeys)
	# Older saves: skill points derived from job level.
	var old := SaveGame.validate({"format": SaveGame.FORMAT, "version": 3, "character": {"name": "Veteran", "job_level": 6}},
		sim.item_db, ClassInsignia.classes())
	var o := FieldSimulation.new(_open_gat(), 3).add_player_from_save(old.character)
	return true if o.skill_points == 5 and o.skills.get("NV_FIRSTAID", 0) == 1 else "v3 migration wrong: %d" % o.skill_points
