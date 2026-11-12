extends RefCounted
## Pre-Renewal combat rules and the field simulation on a synthetic open map.




static func _open_gat(w: int, h: int) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)  # all zero = walkable
	return g


func test_hit_rate_clamps(_t) -> Variant:
	if CombatRulesPreRenewal.hit_rate(10, 200) != 5 or CombatRulesPreRenewal.hit_rate(200, 1) != 95 or CombatRulesPreRenewal.hit_rate(20, 30) != 70:
		return "hit rate wrong"
	return true


func test_defense_minimum_one(_t) -> Variant:
	if CombatRulesPreRenewal.apply_defense(5, 0, 50) != 1:
		return "damage below 1"
	return true if CombatRulesPreRenewal.apply_defense(100, 50, 10) == 40 else "hard/soft DEF order wrong: %d" % CombatRulesPreRenewal.apply_defense(100, 50, 10)


func test_novice_aspd(_t) -> Variant:
	# WD = 25; ASPD = 200 - (25 - (5 + 1) / 10) = 175.6 -> 488 ms between attacks
	var a := CombatRulesPreRenewal.aspd(0.5, 5, 5)
	if not is_equal_approx(a, 175.6):
		return "aspd %f" % a
	return true if is_equal_approx(CombatRulesPreRenewal.attack_interval_ms(a), 488.0) else "interval wrong"


func test_crit_ignores_defense(_t) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attacker := {"hit": 1, "flee": 1, "luk": 400, "vit": 1, "atk_min": 10, "atk_max": 20, "def": 0, "is_player": true, "can_crit": true}
	var target := {"hit": 1, "flee": 999, "luk": 0, "vit": 99, "atk_min": 1, "atk_max": 1, "def": 90, "is_player": false, "can_crit": false}
	var r := CombatRulesPreRenewal.resolve_attack(attacker, target, rng)
	return true if r.crit and r.damage == 20 else "expected crit for max ATK, got %s" % r


func test_monsters_never_crit(_t) -> Variant:
	var rng := RandomNumberGenerator.new()
	var m := {"hit": 999, "flee": 1, "luk": 999, "vit": 1, "atk_min": 5, "atk_max": 5, "def": 0, "is_player": false, "can_crit": false}
	var p := {"hit": 1, "flee": 1, "luk": 0, "vit": 1, "atk_min": 1, "atk_max": 1, "def": 0, "is_player": true, "can_crit": true}
	for i in 50:
		if CombatRulesPreRenewal.resolve_attack(m, p, rng).crit:
			return "monster critted"
	return true


func test_sim_kill_exp_levelup_respawn(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(40, 40), 3, RuleConfig.new())
	var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
	var m := sim.add_monster("1002", Vector2i(14, 10), 0)
	if p == null or m == null or m.max_hp != 50:
		return "setup failed"
	p.base_exp = 8
	sim.drain_events()
	sim.command_attack(p.id, m.id)
	var saw := {}
	var t := 0.0
	while t < 60000.0 and not m.dead:
		sim.tick(50.0)
		t += 50.0
		for ev in sim.drain_events():
			saw[ev.type] = saw.get(ev.type, 0) + 1
	if not m.dead:
		return "poring not killed in 60 s (hp %d)" % m.hp
	if p.level != 2 or p.base_exp != 1 or p.job_exp != 1:
		return "exp/level wrong: lv %d base %d job %d" % [p.level, p.base_exp, p.job_exp]
	for k in ["attack", "damage", "death", "exp", "levelup"]:
		if not saw.has(k):
			return "missing event %s (%s)" % [k, saw]
	if p.target_id != 0:
		return "player still targets a dead monster"
	for i in 110:
		sim.tick(50.0)
	return true if not m.dead and m.hp == m.max_hp else "monster did not respawn"


func test_sim_monster_retaliates(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(40, 40), 5)
	var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 1, "agi": 1, "vit": 1, "int": 1, "dex": 1, "luk": 1})
	var m := sim.add_monster("1063", Vector2i(11, 10), 0)  # Lunatic (passive)
	if m.target_id != 0:
		return "passive monster should not start with a target"
	sim.command_attack(p.id, m.id)
	var hit_back := false
	for i in 200:
		sim.tick(50.0)
		for ev in sim.drain_events():
			if ev.type == "attack" and ev.id == m.id and ev.target == p.id:
				hit_back = true
	return true if hit_back else "monster never attacked its attacker"


func test_sim_deterministic(_t) -> Variant:
	var results := []
	for run in 2:
		var sim := FieldSimulation.new(_open_gat(30, 30), 99)
		var p := sim.add_player("A", Vector2i(5, 5), {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
		var m := sim.add_monster("1007", Vector2i(8, 5), 0)
		sim.command_attack(p.id, m.id)
		var log := []
		for i in 300:
			sim.tick(33.0)
			for ev in sim.drain_events():
				if ev.type == "damage":
					log.append([ev.src, ev.dst, ev.amount, ev.miss, ev.crit])
		results.append(log)
	return true if results[0] == results[1] and not results[0].is_empty() else "simulation not deterministic"
