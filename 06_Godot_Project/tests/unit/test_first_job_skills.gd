extends RefCounted
## Archer, Acolyte, Merchant and Thief have dedicated first-job trees.

const JOBS := ["archer", "acolyte", "merchant", "thief"]


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _dummy(sim: FieldSimulation, cell: Vector2i, hp := 100000) -> SimUnit:
	var m := sim.add_monster("1002", cell)
	m.walker.walk_speed = 1e9
	m.max_hp = hp
	m.hp = hp
	m.stats.vit = 0
	m.stats.int = 0
	m.stats.agi = 0
	return m


static func _cast_to_end(sim: FieldSimulation, p: SimUnit) -> void:
	for i in 200:
		if not p.is_casting():
			return
		sim.tick(50.0)


static func _player(sim: FieldSimulation, job: String, cell: Vector2i, int_: int = 20) -> SimUnit:
	var p := sim.add_player("Tester", cell, {"str": 20, "agi": 10, "vit": 20, "int": int_, "dex": 20, "luk": 10})
	p.job = job
	p.level = 40
	p.max_sp = 2000
	p.sp = 2000
	return p


static func _give_weapon(sim: FieldSimulation, p: SimUnit, item_id: int) -> void:
	p.inventory.add(item_id, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)


func test_first_job_skill_data(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 71)
	for id in JOBS:
		var job: Dictionary = sim.job_db.get(id, {})
		var codes: Array = job.get("skills", [])
		if codes.size() < 3:
			return "%s has only %d first-job skills" % [id, codes.size()]
		var p := _player(sim, id, Vector2i(10, 10))
		p.skill_points = 20
		var available := sim.available_skills(p)
		for code in codes:
			var s: Dictionary = sim.skill_db.get(code, {})
			if s.is_empty():
				return "%s lists missing skill %s" % [id, code]
			if String(s.get("job", "")) != id:
				return "%s skill %s belongs to %s" % [id, code, s.get("job")]
			if String(s.get("desc", "")).strip_edges() == "":
				return "%s skill %s has no description" % [id, code]
			if not available.has(code):
				return "%s does not expose %s" % [id, code]
			if not sim.command_learn_skill(p.id, code):
				return "%s cannot learn %s: %s" % [id, code, sim.skill_requirements_unmet(p, code)]
			if String(s.get("type", "")) == "active":
				if int(s.get("max_level", 0)) < 1 or (s.get("sp_cost", []) as Array).size() < int(s.max_level):
					return "%s skill %s has incomplete level data" % [id, code]
				if not (String(s.get("target", "")) in ["enemy", "ally", "self", "self_area", "dead_ally"]):
					return "%s skill %s has no supported target" % [id, code]
				if not s.has("effect") and not (bool(s.get("physical", false)) or bool(s.get("magic", false))):
					return "%s skill %s has no effect" % [id, code]
			elif String(s.get("type", "")) == "passive":
				if int(s.get("mastery_atk", 0)) <= 0:
					return "%s passive %s has no mastery effect" % [id, code]
			else:
				return "%s skill %s has an unsupported type" % [id, code]
	return true


func test_first_job_skills_execute(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 72)
	var archer := _player(sim, "archer", Vector2i(10, 10))
	_give_weapon(sim, archer, 1701)
	archer.inventory.add(1750, 2, sim.item_db, 99999)
	archer.skills["AC_DOUBLESTRAFE"] = 10
	var target := _dummy(sim, Vector2i(15, 10))
	var hp := target.hp
	if not sim.command_use_skill(archer.id, "AC_DOUBLESTRAFE", target.id):
		return "double strafe was rejected"
	sim._attack(archer, target)
	if target.hp >= hp:
		return "double strafe dealt no damage"

	var acolyte := _player(sim, "acolyte", Vector2i(10, 20), 60)
	acolyte.skills["AL_HEAL"] = 10
	var ally := sim.add_player("Ally", Vector2i(10, 22), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	ally.hp = 1
	if not sim.command_use_skill(acolyte.id, "AL_HEAL", ally.id):
		return "heal was rejected"
	_cast_to_end(sim, acolyte)
	if ally.hp <= 1:
		return "heal restored no HP"

	var merchant := _player(sim, "merchant", Vector2i(10, 30))
	merchant.skills["MC_MAMMONITE"] = 10
	var mtarget := _dummy(sim, Vector2i(11, 30))
	var mhp := mtarget.hp
	sim.command_use_skill(merchant.id, "MC_MAMMONITE", mtarget.id)
	sim._attack(merchant, mtarget)
	if mtarget.hp >= mhp:
		return "mammonite dealt no damage"
	merchant.inventory.add(1301, 1, sim.item_db, 99999)
	sim.command_equip(merchant.id, merchant.inventory.entries.size() - 1)
	merchant.skills["MC_AXEMASTERY"] = 5
	sim._recalc_player(merchant)
	if merchant.mastery_atk != 15:
		return "axe mastery should give +15 with an axe, got %d" % merchant.mastery_atk

	var thief := _player(sim, "thief", Vector2i(10, 40))
	thief.skills["TF_ENVENOM"] = 10
	var ttarget := _dummy(sim, Vector2i(11, 40))
	var thp := ttarget.hp
	sim.command_use_skill(thief.id, "TF_ENVENOM", ttarget.id)
	sim._attack(thief, ttarget)
	if ttarget.hp >= thp:
		return "envenom dealt no damage"
	return true
