extends RefCounted
## Server rules: defaults, user/server overrides and their effect on the world.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}


static func _gat(w := 120, h := 120) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


## A deterministic monster: fixed EXP and one guaranteed, known drop.
## The player is credited as the damage dealer so EXP and drop ownership apply.
static func _loot_dummy(sim: FieldSimulation, victim: SimUnit) -> SimUnit:
	sim.monster_db["9001"] = {
		"name": "Test Blob", "sprite": "poring", "level": 1, "hp": 10, "base_exp": 10, "job_exp": 5,
		"str": 1, "agi": 1, "vit": 1, "int": 1, "dex": 1, "luk": 1,
		"atk": [1, 2], "def": 0, "mdef": 0, "size": "medium", "element": "neutral", "element_level": 1,
		"range": 1, "attack_delay": 1000, "attack_motion": 500, "walk_speed": 1.0,
		"drops": [[501, 10000]],
	}
	var mob := sim.add_monster("9001", Vector2i(51, 50), 0)
	mob.damaged_by[victim.id] = 10
	return mob


func _field(rules: RuleConfig) -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), 13, rules)
	sim.map_name = "rules_test"
	sim.respawn_cell = Vector2i(60, 60)
	return sim


static func _write(path: String, text := "") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func test_shipped_defaults(_t) -> Variant:
	var r := RuleConfig.new()
	r._read_json(RuleConfig.DEFAULTS_PATH)
	if not FileAccess.file_exists(RuleConfig.DEFAULTS_PATH):
		return "data/config.json is missing"
	if r.exp_rate != 5000 or r.job_exp_rate != 5000 or r.drop_rate != 5000:
		return "shipped rates should be 5000 (50x): %s" % r.describe()
	if r.max_level != 99 or r.autoloot:
		return "shipped caps wrong: %s" % r.describe()
	return true if r.describe().contains("EXP x50") else "describe() should show effective multipliers"


func test_effective_rate_labels(_t) -> Variant:
	var r := RuleConfig.new()
	r.exp_rate = 150
	r.job_exp_rate = 125
	r.drop_rate = 5000
	var text := r.describe()
	if not text.contains("EXP x1.5"):
		return "150%% should render as x1.5: %s" % text
	if not text.contains("JOB x1.25"):
		return "125%% should render as x1.25: %s" % text
	if not text.contains("DROP x50"):
		return "5000%% should render as x50: %s" % text
	if r.rate_summary() != "EXP x1.5   JOB x1.25   DROP x50":
		return "rate_summary() should show effective multipliers only: %s" % r.rate_summary()
	return true


func test_rate_multiplier_updates_all_three_rates(_t) -> Variant:
	var r := RuleConfig.new()
	r.apply_rate_multiplier(25)
	if r.exp_rate != 2500 or r.job_exp_rate != 2500 or r.drop_rate != 2500:
		return "25x should set all three rates to 2500%%: %s" % r.describe()
	r.apply_rate_multiplier(0)
	return true if r.exp_rate == 2500 else "an invalid preset should not clear the rates"


func test_kv_overrides_and_clamps(_t) -> Variant:
	var r := RuleConfig.new()
	r._read_kv("// header comment\nbase_exp_rate: 300\njob_exp_rate = 150\nitem_rate_common: 250\nmax_level: 120\nautoloot: 1\nunknown_key: 5\n", "test.cfg")
	if r.exp_rate != 300 or r.job_exp_rate != 150 or r.drop_rate != 250:
		return "overrides not applied: %s" % r.describe()
	if r.max_level != 120 or not r.autoloot:
		return "cap/autoloot not applied: %s" % r.describe()
	var c := RuleConfig.new()
	c._read_kv("exp_rate: 999999\nmax_level: 0\n", "clamp.cfg")
	return true if c.exp_rate == 10000 and c.max_level == 1 else "values not clamped: %s" % c.describe()


func test_rathena_server_conf_folder(_t) -> Variant:
	var root := ProjectSettings.globalize_path("user://rule_test_server")
	DirAccess.make_dir_recursive_absolute(root.path_join("conf/battle"))
	_write(root.path_join("conf/battle/exp.conf"), "// rAthena\nbase_exp_rate: 500\nmax_level: 175\n")
	_write(root.path_join("conf/battle/drops.conf"), "item_rate_common: 200\n")
	var r := RuleConfig.load_config(root)
	if r.exp_rate != 500 or r.drop_rate != 200 or r.max_level != 175:
		return "server conf not read: %s" % r.describe()
	return true if r.sources.size() > 0 else "sources should record the conf files"


func test_exp_rate_scales_kills(_t) -> Variant:
	var rules := RuleConfig.new()
	rules.exp_rate = 200
	rules.job_exp_rate = 200
	var sim := _field(rules)
	var p := sim.add_player("Hero", Vector2i(50, 50), FLAT)
	var mob := _loot_dummy(sim, p)
	sim.drain_events()
	sim._kill(mob, p)
	var got := -1
	for ev in sim.drain_events():
		if ev.type == "exp" and ev.id == p.id:
			got = int(ev.base)
	var want := 20
	return true if got == want else "expected %d EXP at x2, got %d" % [want, got]


func test_level_cap_stops_level_ups(_t) -> Variant:
	var rules := RuleConfig.new()
	rules.max_level = 1
	rules.exp_rate = 10000
	var sim := _field(rules)
	var p := sim.add_player("Capped", Vector2i(50, 50), FLAT)
	var mob := _loot_dummy(sim, p)
	sim.drain_events()
	sim._kill(mob, p)
	for ev in sim.drain_events():
		if ev.type == "levelup" and ev.id == p.id:
			return "level cap 1 should block level ups"
	return true if p.level == 1 else "level moved past the cap"


func test_drop_rate_and_autoloot(_t) -> Variant:
	var rules := RuleConfig.new()
	rules.drop_rate = 10000   # every listed drop
	rules.autoloot = true
	var sim := _field(rules)
	var p := sim.add_player("Looter", Vector2i(50, 50), FLAT)
	var mob := _loot_dummy(sim, p)
	sim.drain_events()
	sim._kill(mob, p)
	var looted := 0
	for ev in sim.drain_events():
		if ev.type == "autoloot" and ev.id == p.id:
			looted += 1
	if looted == 0:
		return "autoloot produced no drops"
	if not sim.ground_items.is_empty():
		return "autoloot should not leave items on the ground"
	return true if p.inventory.entries.size() > 0 else "loot never reached the inventory"


func test_zero_drop_rate(_t) -> Variant:
	var rules := RuleConfig.new()
	rules.drop_rate = 0
	var sim := _field(rules)
	var p := sim.add_player("Unlucky", Vector2i(50, 50), FLAT)
	var mob := _loot_dummy(sim, p)
	sim.drain_events()
	sim._kill(mob, p)
	for ev in sim.drain_events():
		if ev.type == "drop":
			return "drop rate 0 should drop nothing"
	return true if sim.ground_items.is_empty() else "ground items appeared at rate 0"
