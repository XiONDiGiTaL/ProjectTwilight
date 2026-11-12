extends RefCounted
## Element table, MATK, cast times and the Mage bolts.


static func _open_gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _mage(sim: FieldSimulation, dex := 30) -> SimUnit:
	var p := sim.add_player("Caster", Vector2i(10, 10), {"str": 1, "agi": 1, "vit": 5, "int": 40, "dex": dex, "luk": 1})
	p.job_level = 10
	p.skills.NV_BASIC = 9
	sim.command_job_change(p.id, "mage")
	p.max_sp = 500
	p.sp = 500
	return p


static func _types(events: Array) -> Array:
	var out := []
	for e in events:
		out.append(e.type)
	return out


func test_element_table(_t) -> Variant:
	var checks := [["fire", "earth", 1, 150], ["water", "fire", 1, 150], ["wind", "water", 1, 175],
		["neutral", "ghost", 1, 25], ["ghost", "neutral", 1, 25], ["fire", "undead", 1, 125],
		["holy", "shadow", 4, 200], ["neutral", "ghost", 3, 0], ["water", "water", 1, 25]]
	for c in checks:
		var m := ElementRulesPreRenewal.modifier(c[0], c[1], c[2])
		if m != c[3]:
			return "%s vs %s %d: expected %d, got %d" % [c[0], c[1], c[2], c[3], m]
	if ElementRulesPreRenewal.apply(100, "holy", "holy", 2) != 0:
		return "negative modifier should clamp to 0"
	return true if ElementRulesPreRenewal.apply(100, "fire", "earth", 1) == 150 else "apply wrong"


func test_matk_and_cast_time(_t) -> Variant:
	if ElementRulesPreRenewal.matk_range(10) != Vector2i(11, 14):
		return "matk(10) wrong: %s" % ElementRulesPreRenewal.matk_range(10)
	if ElementRulesPreRenewal.matk_range(99) != Vector2i(99 + 196, 99 + 361):
		return "matk(99) wrong"
	if not is_equal_approx(ElementRulesPreRenewal.cast_time_ms(1000.0, 75), 500.0):
		return "dex 75 should halve cast time"
	return true if ElementRulesPreRenewal.cast_time_ms(2100.0, 150) == 0.0 else "150 dex should be instant"


func test_bolt_cast_flow(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 21, RuleConfig.new())
	var p := _mage(sim, 30)
	p.skills.MG_FIREBOLT = 3
	var m := sim.add_monster("1002", Vector2i(14, 10))
	sim.drain_events()
	if not sim.command_use_skill(p.id, "MG_FIREBOLT", m.id):
		return "fire bolt refused"
	var ev := sim.drain_events()
	if not _types(ev).has("cast_start") or not p.is_casting():
		return "cast did not start in range: %s" % [_types(ev)]
	var expected := 2100.0 * (1.0 - 30.0 / 150.0)
	if not is_equal_approx(p.cast_total, expected):
		return "cast time %f, expected %f" % [p.cast_total, expected]
	var sp_before := p.sp
	sim.tick(expected - 50.0)
	if p.sp != sp_before or not p.is_casting():
		return "SP spent or cast ended early"
	var hp_before := m.hp
	sim.tick(100.0)
	ev = sim.drain_events()
	var t := _types(ev)
	if not (t.has("cast_end") and t.has("magic") and t.has("damage")):
		return "release events missing: %s" % [t]
	for e in ev:
		if e.type == "magic" and (e.hits != 3 or e.element != "fire"):
			return "magic event wrong: %s" % e
	if p.sp != sp_before - 18:
		return "fire bolt lv3 should cost 18 SP, spent %d" % (sp_before - p.sp)
	if m.hp >= hp_before and not m.dead:
		return "no damage dealt"
	return true if p.skill_delay > 0.0 else "after-cast delay not set"


func test_cast_interrupts(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 22)
	var p := _mage(sim)
	p.skills.MG_COLDBOLT = 5
	var m := sim.add_monster("1002", Vector2i(13, 10))
	sim.command_use_skill(p.id, "MG_COLDBOLT", m.id)
	sim.drain_events()
	sim.command_move(p.id, Vector2i(5, 5))
	var ev := sim.drain_events()
	var interrupted := false
	for e in ev:
		if e.type == "cast_end" and not e.ok:
			interrupted = true
	if not interrupted or p.is_casting() or p.sp != 500:
		return "moving should interrupt the cast without spending SP"
	sim.command_move(p.id, p.walker.cell)
	p.walker.stop()
	sim.command_use_skill(p.id, "MG_COLDBOLT", m.id)
	if not p.is_casting():
		return "second cast did not start"
	sim._apply_hit(m, p, {"damage": 3, "crit": false, "miss": false})
	return true if not p.is_casting() and p.sp == 500 else "damage should interrupt the cast"


func test_elements_change_damage(_t) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var poring := {"mdef": 5, "int": 0, "vit": 1, "element": "water", "element_level": 1}
	var cold := 0
	var lightning := 0
	for i in 30:
		cold += ElementRulesPreRenewal.magic_hit(Vector2i(60, 80), 100, poring, "water", rng)
		lightning += ElementRulesPreRenewal.magic_hit(Vector2i(60, 80), 100, poring, "wind", rng)
	if lightning < cold * 5:
		return "lightning (175%%) vs cold (25%%) on water: %d vs %d" % [lightning, cold]
	return true


func test_walks_into_spell_range(_t) -> Variant:
	var sim := FieldSimulation.new(_open_gat(), 23)
	var p := _mage(sim)
	p.skills.MG_SOULSTRIKE = 1
	p.skills.MG_NAPALMBEAT = 4
	var m := sim.add_monster("1002", Vector2i(30, 10))
	m.data = m.data.duplicate()
	m.walker.walk_speed = 100000.0  # effectively still
	sim.command_use_skill(p.id, "MG_SOULSTRIKE", m.id)
	if p.is_casting():
		return "cast started out of range"
	for i in 200:
		sim.tick(50.0)
		if p.is_casting():
			break
	if not p.is_casting():
		return "never reached range to cast"
	return true if FieldSimulation._chebyshev(p.walker.cell, m.walker.cell) <= 9 else "cast from too far"


func test_aura_saved(_t) -> Variant:
	var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	var classes := ClassInsignia.classes()
	var base := {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "character": {"name": "Aurora", "aura": "ember"}}
	var r := SaveGame.validate(base, item_db, classes)
	if not r.ok or r.character.aura != "ember":
		return "aura not kept: %s" % r
	base.character.aura = "rainbow-unicorn"
	r = SaveGame.validate(base, item_db, classes)
	if r.character.aura != "class":
		return "invalid aura not reset"
	return true if PlayerAura.next_style("none") == "class" else "aura cycle should wrap"
