class_name FieldSimulation
extends RefCounted
## Authoritative simulation of one map: units, monster AI, combat, EXP, respawns.
##
## Deterministic for a given seed and sequence of commands and time steps, so
## the same code can run offline, on a co-op host, or on a server. It never
## touches rendering; the presentation layer reads units and consumes events:
##   {type: "spawn", id}            {type: "attack", id, target}
##   {type: "damage", src, dst, amount, crit, miss}
##   {type: "death", id, killer}    {type: "exp", id, base, job}
##   {type: "levelup", id, level, kind: "base"|"job"}  {type: "revive", id}

const MONSTER_DB := "res://data/prerenewal/monsters.json"
const EXP_DB := "res://data/prerenewal/exp_tables.json"
const NOVICE_FIST_BTBA := 0.5     # seconds; Medium confidence
const MONSTER_RESPAWN_MS := 5000.0
const PLAYER_REVIVE_MS := 3000.0
const WANDER_MIN_MS := 3000.0
const WANDER_MAX_MS := 8000.0
const CHASE_GIVE_UP_CELLS := 14

var gat: GatFile
var pathfinder: GridPathfinder
var rng := RandomNumberGenerator.new()
var units: Dictionary = {}  # id -> SimUnit
var events: Array = []
var monster_db: Dictionary = {}
var exp_tables: Dictionary = {}

var _next_id := 1


func _init(p_gat: GatFile, seed_value: int = 1) -> void:
	gat = p_gat
	pathfinder = GridPathfinder.new(gat)
	rng.seed = seed_value
	monster_db = _load_json(MONSTER_DB)
	exp_tables = _load_json(EXP_DB)


static func _load_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


# --- Spawning ---------------------------------------------------------------

func add_player(name: String, cell: Vector2i, stats: Dictionary) -> SimUnit:
	var u := SimUnit.new()
	u.kind = SimUnit.Kind.PLAYER
	u.name = name
	u.sprite = "초보자"
	u.stats = stats.duplicate()
	u.walker = GridWalker.new(pathfinder.nearest_walkable(cell, 20))
	u.spawn_cell = u.walker.cell
	u.status_points = StatRulesPreRenewal.NOVICE_START_POINTS - _stat_cost(stats)
	_recalc_player(u)
	u.hp = u.max_hp
	u.sp = u.max_sp
	_register(u)
	return u


func add_monster(mob_id: String, cell: Vector2i, spawn_radius: int = 0) -> SimUnit:
	var m: Dictionary = monster_db.get(mob_id, {})
	if m.is_empty():
		push_warning("Unknown monster %s" % mob_id)
		return null
	var u := SimUnit.new()
	u.kind = SimUnit.Kind.MONSTER
	u.mob_id = mob_id
	u.data = m
	u.name = m.name
	u.sprite = m.sprite
	u.level = int(m.level)
	for k in ["str", "agi", "vit", "int", "dex", "luk"]:
		u.stats[k] = int(m[k])
	u.max_hp = int(m.hp)
	u.hp = u.max_hp
	u.atk_min = int(m.atk[0])
	u.atk_max = int(m.atk[1])
	u.hard_def = int(m.def)
	u.attack_range = int(m.range)
	u.attack_interval = float(m.attack_delay)
	u.attack_motion = float(m.attack_motion)
	u.spawn_cell = cell
	u.spawn_radius = spawn_radius
	u.walker = GridWalker.new(_random_cell_near(cell, spawn_radius))
	u.walker.walk_speed = float(m.walk_speed)
	u.idle_timer = rng.randf_range(0.0, WANDER_MAX_MS)
	_register(u)
	return u


## Places `count` monsters at random walkable cells anywhere on the map.
func spawn_random(mob_id: String, count: int) -> void:
	for i in count:
		var c := _random_cell_near(Vector2i(gat.width / 2, gat.height / 2), maxi(gat.width, gat.height))
		add_monster(mob_id, c, 0)


func _register(u: SimUnit) -> void:
	u.id = _next_id
	_next_id += 1
	units[u.id] = u
	events.append({"type": "spawn", "id": u.id})


# --- Commands (from the local player or network clients) --------------------

func command_move(unit_id: int, cell: Vector2i) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead:
		return false
	u.target_id = 0
	var path := pathfinder.find_path(u.walker.planning_origin(), cell)
	if path.is_empty():
		return false
	u.walker.walk(path)
	return true


func command_attack(unit_id: int, target_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	var t: SimUnit = units.get(target_id)
	if u == null or t == null or u.dead or t.dead or u == t:
		return false
	u.target_id = target_id
	return true


# --- Simulation ---------------------------------------------------------------

## Advances the world by `ms` milliseconds. Events accumulate in `events`.
func tick(ms: float) -> void:
	for id in units.keys():
		var u: SimUnit = units[id]
		if u.dead:
			u.respawn_in -= ms
			if u.respawn_in <= 0.0:
				_revive(u)
			continue
		u.attack_cooldown = maxf(0.0, u.attack_cooldown - ms)
		if u.target_id != 0:
			_pursue(u)
		elif not u.is_player():
			_wander(u, ms)
		u.walker.advance(ms)


## Returns and clears pending events.
func drain_events() -> Array:
	var out := events
	events = []
	return out


func _pursue(u: SimUnit) -> void:
	var t: SimUnit = units.get(u.target_id)
	if t == null or t.dead:
		u.target_id = 0
		return
	var dist := _chebyshev(u.walker.cell, t.walker.cell)
	if not u.is_player() and dist > CHASE_GIVE_UP_CELLS:
		u.target_id = 0
		return
	if dist <= u.attack_range and not u.walker.is_moving():
		u.walker.direction = GridWalker.direction_to(u.walker.cell, t.walker.cell)
		if u.attack_cooldown <= 0.0:
			_attack(u, t)
		return
	if dist <= u.attack_range and u.walker.is_moving():
		# Stop at the next cell boundary, then attack.
		var keep: Array[Vector2i] = [u.walker.path[0]]
		u.walker.path = keep
		return
	# Re-path toward the target when idle or when it has moved away from our goal.
	var goal: Vector2i = u.walker.path[-1] if u.walker.is_moving() else u.walker.cell
	if not u.walker.is_moving() or _chebyshev(goal, t.walker.cell) > u.attack_range:
		var path := pathfinder.find_path(u.walker.planning_origin(), t.walker.cell)
		if path.size() > 1:
			path.remove_at(path.size() - 1)  # stand next to the target, not on it
			u.walker.walk(path)
		elif path.size() == 1 and _chebyshev(u.walker.planning_origin(), t.walker.cell) > u.attack_range:
			u.walker.walk(path)


func _attack(u: SimUnit, t: SimUnit) -> void:
	u.attack_cooldown = u.attack_interval
	events.append({"type": "attack", "id": u.id, "target": t.id})
	var r := CombatRulesPreRenewal.resolve_attack(u.combat_profile(), t.combat_profile(), rng)
	events.append({"type": "damage", "src": u.id, "dst": t.id, "amount": r.damage, "crit": r.crit, "miss": r.miss})
	if r.miss:
		_provoke(t, u)
		return
	t.hp = maxi(0, t.hp - r.damage)
	t.damaged_by[u.id] = int(t.damaged_by.get(u.id, 0)) + r.damage
	if t.hp <= 0:
		_kill(t, u)
	else:
		_provoke(t, u)


## Passive monsters fight back when attacked.
func _provoke(victim: SimUnit, attacker: SimUnit) -> void:
	if not victim.is_player() and victim.target_id == 0:
		victim.target_id = attacker.id


func _kill(t: SimUnit, killer: SimUnit) -> void:
	t.dead = true
	t.target_id = 0
	t.walker.stop()
	t.respawn_in = PLAYER_REVIVE_MS if t.is_player() else MONSTER_RESPAWN_MS
	events.append({"type": "death", "id": t.id, "killer": killer.id})
	for id in units:
		var other: SimUnit = units[id]
		if other.target_id == t.id:
			other.target_id = 0
	if not t.is_player():
		# Pre-Renewal: EXP split by damage share among damage dealers (Medium confidence).
		var total := 0
		for v in t.damaged_by.values():
			total += int(v)
		for pid in t.damaged_by:
			var p: SimUnit = units.get(pid)
			if p == null or not p.is_player() or total == 0:
				continue
			var share := float(t.damaged_by[pid]) / total
			_gain_exp(p, maxi(1, roundi(int(t.data.base_exp) * share)), maxi(1, roundi(int(t.data.job_exp) * share)))
	t.damaged_by.clear()


func _revive(u: SimUnit) -> void:
	u.dead = false
	u.hp = u.max_hp
	if u.is_player():
		u.walker = GridWalker.new(u.spawn_cell)
	else:
		var c := _random_cell_near(Vector2i(gat.width / 2, gat.height / 2), maxi(gat.width, gat.height)) \
			if u.spawn_radius == 0 else _random_cell_near(u.spawn_cell, u.spawn_radius)
		var speed := u.walker.walk_speed
		u.walker = GridWalker.new(c)
		u.walker.walk_speed = speed
	events.append({"type": "revive", "id": u.id})


func _wander(u: SimUnit, ms: float) -> void:
	if u.walker.is_moving():
		return
	u.idle_timer -= ms
	if u.idle_timer > 0.0:
		return
	u.idle_timer = rng.randf_range(WANDER_MIN_MS, WANDER_MAX_MS)
	var dest := u.walker.cell + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-5, 5))
	var path := pathfinder.find_path(u.walker.cell, dest, 12)
	if not path.is_empty():
		u.walker.walk(path)


# --- Progression ----------------------------------------------------------------

func _gain_exp(p: SimUnit, base: int, job: int) -> void:
	events.append({"type": "exp", "id": p.id, "base": base, "job": job})
	p.base_exp += base
	p.job_exp += job
	var base_table: Array = exp_tables.get("base_normal", [])
	while p.level - 1 < base_table.size() and p.base_exp >= int(base_table[p.level - 1]):
		p.base_exp -= int(base_table[p.level - 1])
		p.status_points += StatRulesPreRenewal.status_points_gained(p.level)
		p.level += 1
		_recalc_player(p)
		p.hp = p.max_hp
		p.sp = p.max_sp
		events.append({"type": "levelup", "id": p.id, "level": p.level, "kind": "base"})
	var job_table: Array = exp_tables.get("job_novice", [])
	while p.job_level - 1 < job_table.size() and p.job_exp >= int(job_table[p.job_level - 1]):
		p.job_exp -= int(job_table[p.job_level - 1])
		p.job_level += 1
		events.append({"type": "levelup", "id": p.id, "level": p.job_level, "kind": "job"})


## EXP needed for the next base / job level, or 0 when the table ends.
func next_base_exp(p: SimUnit) -> int:
	var t: Array = exp_tables.get("base_normal", [])
	return int(t[p.level - 1]) if p.level - 1 < t.size() else 0


func next_job_exp(p: SimUnit) -> int:
	var t: Array = exp_tables.get("job_novice", [])
	return int(t[p.job_level - 1]) if p.job_level - 1 < t.size() else 0


func _recalc_player(u: SimUnit) -> void:
	var s := u.stats
	u.max_hp = CombatRulesPreRenewal.novice_max_hp(u.level, int(s.vit))
	u.max_sp = CombatRulesPreRenewal.novice_max_sp(u.level, int(s.int))
	var batk := StatRulesPreRenewal.status_atk(int(s.str), int(s.dex), int(s.luk))
	u.atk_min = batk  # bare-handed: no weapon ATK variance
	u.atk_max = batk
	var a := CombatRulesPreRenewal.aspd(NOVICE_FIST_BTBA, int(s.agi), int(s.dex))
	u.attack_interval = CombatRulesPreRenewal.attack_interval_ms(a)
	u.attack_motion = minf(u.attack_interval, 500.0)


static func _stat_cost(stats: Dictionary) -> int:
	var total := 0
	for k in stats:
		total += StatRulesPreRenewal.total_raise_cost(1, int(stats[k]))
	return total


# --- Helpers ------------------------------------------------------------------

func _random_cell_near(c: Vector2i, radius: int) -> Vector2i:
	for attempt in 40:
		var p := c + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if pathfinder.is_walkable(p):
			return p
	return pathfinder.nearest_walkable(c, 30)


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
