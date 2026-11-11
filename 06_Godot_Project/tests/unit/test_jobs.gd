extends RefCounted
## Job change, class formulas and Swordman skills.


static func _open_gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _ready_novice(sim: FieldSimulation) -> SimUnit:
	var p := sim.add_player("Hopeful", Vector2i(10, 10), {"str": 9, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
	p.job_level = 10
	p.skills.NV_BASIC = 9
	return p


func test_hp_sp_formulas(_t) -> Variant:
	# Novice keeps (35 + 5*lv) * (1 + VIT/100).
	if CombatRulesPreRenewal.job_max_hp(10, 0, 0.0, 5) != 85:
		return "novice hp formula changed"
	# Swordman lv 10, VIT 0: 35 + 50 + sum_{i=2..10} round(0.7 i) = 85 + 38 = 123
	var hp := CombatRulesPreRenewal.job_max_hp(10, 0, 0.7, 5)
	if hp != 123:
		return "swordman hp expected 123, got %d" % hp
	return true if CombatRulesPreRenewal.job_max_sp(10, 0, 6) == 70 else "mage sp wrong"


func test_job_change_requirements(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 8)
	var p := sim.add_player("Early", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	if sim.command_job_change(p.id, "swordman"):
		return "job change without requirements"
	var q := _ready_novice(sim)
	if sim.command_job_change(q.id, "lord_knight") or sim.command_job_change(q.id, "novice"):
		return "invalid target job accepted"
	var before_weight := q.max_weight()
	if not sim.command_job_change(q.id, "swordman"):
		return "eligible job change failed"
	if q.job != "swordman" or q.job_level != 1 or q.sprite != "검사" or q.max_weight() != before_weight + 800:
		return "job change effects wrong: %s %d %s %d" % [q.job, q.job_level, q.sprite, q.max_weight()]
	if not q.skills.has("SM_BASH") or q.skills.get("NV_FIRSTAID", 0) != 1:
		return "skill list wrong after job change"
	return true if not sim.command_job_change(q.id, "mage") else "second job change allowed"


func test_sword_mastery_and_weapon_rules(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 9)
	var p := _ready_novice(sim)
	sim.command_job_change(p.id, "swordman")
	p.skill_points = 10
	var base_atk := p.atk_max
	for i in 3:
		sim.command_learn_skill(p.id, "SM_SWORD")
	if p.atk_max != base_atk:
		return "mastery applied bare-handed"
	p.inventory.add(1201, 1, sim.item_db, p.max_weight())
	sim.command_equip(p.id, p.inventory.entries.size() - 1)
	if p.mastery_atk != 12 or p.atk_min != p.batk + p.watk_min + 12:
		return "sword mastery not applied with a dagger: %d" % p.mastery_atk
	var m := FieldSimulation.new(_open_gat(), 1)
	var mage := _ready_novice(m)
	m.command_job_change(mage.id, "mage")
	mage.inventory.add(1201, 1, m.item_db, mage.max_weight())
	return true if m.command_equip(mage.id, mage.inventory.entries.size() - 1) else "mage should be able to use a dagger"


func test_bash_and_magnum_break(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 12)
	var p := _ready_novice(sim)
	sim.command_job_change(p.id, "swordman")
	p.skill_points = 10
	if sim.command_learn_skill(p.id, "SM_MAGNUM"):
		return "Magnum Break learned without Bash 5"
	for i in 5:
		sim.command_learn_skill(p.id, "SM_BASH")
	if not sim.command_learn_skill(p.id, "SM_MAGNUM"):
		return "Magnum Break should unlock at Bash 5"
	p.sp = 100
	var m := sim.add_monster("1002", Vector2i(11, 10), 0)
	m.hp = 5000
	m.max_hp = 5000
	sim.drain_events()
	if not sim.command_use_skill(p.id, "SM_BASH", m.id):
		return "bash refused"
	var bashed := false
	for i in 40:
		sim.tick(50.0)
		for ev in sim.drain_events():
			bashed = bashed or (ev.type == "skill_hit" and ev.skill == "SM_BASH")
		if bashed:
			break
	if not bashed or p.sp != 92:
		return "bash did not land or SP wrong (%d)" % p.sp
	# Magnum Break hits everything within 2 cells, nothing beyond.
	var near := sim.add_monster("1002", Vector2i(12, 12), 0)
	var far := sim.add_monster("1002", Vector2i(16, 10), 0)
	near.hp = 5000
	far.hp = 5000
	sim.tick(2100.0)
	sim.drain_events()
	var near_hp := near.hp
	if not sim.command_use_skill(p.id, "SM_MAGNUM"):
		return "magnum break refused"
	var hit_ids := {}
	for ev in sim.drain_events():
		if ev.type == "damage":
			hit_ids[ev.dst] = true
	if not hit_ids.has(near.id) or hit_ids.has(far.id):
		return "magnum break area wrong: %s" % str(hit_ids.keys())
	return true


func test_first_job_exp_and_points(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 13)
	var p := _ready_novice(sim)
	sim.command_job_change(p.id, "swordman")
	if sim.next_job_exp(p) != 30:
		return "first job table not used: %d" % sim.next_job_exp(p)
	sim._gain_exp(p, 0, 30)
	return true if p.job_level == 2 and p.skill_points == 1 else "first-job level up wrong"
