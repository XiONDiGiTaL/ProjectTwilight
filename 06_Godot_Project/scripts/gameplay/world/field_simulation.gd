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
##   {type: "drop", ground}  {type: "ground_gone", ground}
##   {type: "pickup", id, ground, item, amount}  {type: "pickup_fail", id, reason}
##   {type: "heal", id, amount}  {type: "inventory", id}  {type: "stats", id}
##   {type: "equipment", id}  {type: "npc_spawn", npc}  {type: "npc_open", id, npc}
##   {type: "trade", id, ok, text}

const MONSTER_DB := "res://data/prerenewal/monsters.json"
const EXP_DB := "res://data/prerenewal/exp_tables.json"
const ITEM_DB := "res://data/prerenewal/items.json"
const OWNER_PRIORITY_MS := 3000.0   # killer's exclusive pickup window (Medium confidence)
const GROUND_ITEM_LIFETIME_MS := 60000.0
const STAT_NAMES := ["str", "agi", "vit", "int", "dex", "luk"]
const SHOP_DB := "res://data/prerenewal/shops.json"
const EQUIP_SLOTS := ["head_top", "head_mid", "head_low", "weapon", "shield", "body", "garment", "shoes", "acc1", "acc2"]
## Novice base weapon delay (BTBA, seconds) per weapon type. Medium confidence.
const NOVICE_BTBA := {"fist": 0.5, "dagger": 0.65}
const NPC_TALK_RANGE := 2
const NPC_TRADE_RANGE := 6
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
var item_db: Dictionary = {}
## ground id -> {id, item, amount, cell: Vector2i, offset: Vector2, owner, age}
var ground_items: Dictionary = {}
var _next_ground := 1
var shop_db: Dictionary = {}
## npc id -> {id, name, sprite, cell: Vector2i, direction, shop, greeting}
var npcs: Dictionary = {}
var _next_npc := 1

var _next_id := 1


func _init(p_gat: GatFile, seed_value: int = 1) -> void:
	gat = p_gat
	pathfinder = GridPathfinder.new(gat)
	rng.seed = seed_value
	monster_db = _load_json(MONSTER_DB)
	exp_tables = _load_json(EXP_DB)
	item_db = _load_json(ITEM_DB)
	item_db.erase("_provenance")
	shop_db = _load_json(SHOP_DB)
	shop_db.erase("_doc")
	for sid in shop_db:  # JSON numbers are floats; catalogues use int item ids
		var ids: Array[int] = []
		for v in shop_db[sid].get("items", []):
			ids.append(int(v))
		shop_db[sid].items = ids


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


## Spawns the shop NPCs defined for `map_name` in shops.json.
func spawn_npcs(map_name: String) -> void:
	for shop_id in shop_db:
		var s: Dictionary = shop_db[shop_id]
		if String(s.get("map", "")) != map_name:
			continue
		var nid := _next_npc
		_next_npc += 1
		npcs[nid] = {"id": nid, "name": s.npc_name, "sprite": s.sprite,
			"cell": Vector2i(int(s.cell[0]), int(s.cell[1])), "direction": int(s.get("direction", 0)),
			"shop": shop_id, "greeting": String(s.get("greeting", ""))}
		events.append({"type": "npc_spawn", "npc": nid})


## Restores a player from a validated SaveGame character dictionary.
func add_player_from_save(c: Dictionary) -> SimUnit:
	var u := add_player(String(c.name), c.cell, c.stats)
	u.job = String(c.job)
	u.male = bool(c.get("male", true))
	u.hair_style = int(c.get("hair_style", 2))
	u.hair_color = int(c.get("hair_color", 0))
	u.level = int(c.level)
	u.job_level = int(c.job_level)
	u.base_exp = int(c.base_exp)
	u.job_exp = int(c.job_exp)
	u.status_points = int(c.status_points)
	u.zeny = int(c.zeny)
	u.inventory = Inventory.from_array(c.inventory, item_db)
	var eq: Dictionary = c.get("equipment", {})
	for slot in eq:
		var def: Dictionary = item_db.get(str(eq[slot]), {})
		if EQUIP_SLOTS.has(slot) and _slot_fits(def, String(slot)):
			u.equipment[slot] = int(eq[slot])
	_recalc_player(u)
	u.hp = u.max_hp if int(c.hp) <= 0 else clampi(int(c.hp), 1, u.max_hp)
	u.sp = u.max_sp if int(c.hp) <= 0 else clampi(int(c.sp), 0, u.max_sp)
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
	u.size = String(m.get("size", "medium"))
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
	u.pickup_target = 0
	u.talk_target = 0
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
	u.pickup_target = 0
	return true


## Walk to a ground item and pick it up.
func command_pickup(unit_id: int, ground_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or not ground_items.has(ground_id):
		return false
	u.target_id = 0
	u.pickup_target = ground_id
	return true


## Uses the inventory entry at `index` (usable items only).
func command_use_item(unit_id: int, index: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or index < 0 or index >= u.inventory.entries.size():
		return false
	var item_id := int(u.inventory.entries[index].id)
	var def: Dictionary = item_db.get(str(item_id), {})
	if def.get("type", "") != "usable":
		return false
	var heal_range: Array = def.get("heal_hp", [0, 0])
	u.inventory.remove_at(index, 1)
	var amount := rng.randi_range(int(heal_range[0]), int(heal_range[1]))
	var before := u.hp
	u.hp = mini(u.max_hp, u.hp + amount)
	events.append({"type": "heal", "id": u.id, "amount": u.hp - before})
	events.append({"type": "inventory", "id": u.id})
	return true


## Equips the inventory entry at `index`; a previously equipped item returns to the inventory.
func command_equip(unit_id: int, index: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or not u.is_player() or index < 0 or index >= u.inventory.entries.size():
		return false
	var item_id := int(u.inventory.entries[index].id)
	var def: Dictionary = item_db.get(str(item_id), {})
	var slot := String(def.get("equip", ""))
	if slot == "" or u.level < int(def.get("equip_level", 1)):
		return false
	u.inventory.remove_at(index, 1)
	if u.equipment.has(slot):
		u.inventory.entries.append({"id": int(u.equipment[slot]), "amount": 1})
	u.equipment[slot] = item_id
	_recalc_player(u)
	events.append({"type": "equipment", "id": u.id})
	events.append({"type": "inventory", "id": u.id})
	return true


func command_unequip(unit_id: int, slot: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or not u.equipment.has(slot):
		return false
	if u.inventory.entries.size() >= Inventory.MAX_ENTRIES:
		return false
	u.inventory.entries.append({"id": int(u.equipment[slot]), "amount": 1})
	u.equipment.erase(slot)
	_recalc_player(u)
	events.append({"type": "equipment", "id": u.id})
	events.append({"type": "inventory", "id": u.id})
	return true


## Walk to an NPC and open its shop.
func command_talk(unit_id: int, npc_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or not npcs.has(npc_id):
		return false
	u.target_id = 0
	u.pickup_target = 0
	u.talk_target = npc_id
	return true


## Buys from the open shop. Validated here, never by the client.
func command_buy(unit_id: int, item_id: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	var shop := _open_shop_of(u)
	if shop.is_empty() or amount <= 0 or not (shop.items as Array).has(item_id):
		return _trade(u, false, "That item is not sold here.")
	var def: Dictionary = item_db.get(str(item_id), {})
	var cost := int(def.get("price", 0)) * amount
	if cost > u.zeny:
		return _trade(u, false, "Not enough Zeny.")
	if not u.inventory.add(item_id, amount, item_db, u.max_weight() - u.equipment_weight(item_db)):
		return _trade(u, false, "You cannot carry that much.")
	u.zeny -= cost
	events.append({"type": "inventory", "id": u.id})
	return _trade(u, true, "Bought  %s  ×%d   −%d z" % [def.name, amount, cost])


## Sells inventory entry `index` to the open shop at half the item price.
func command_sell(unit_id: int, index: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if _open_shop_of(u).is_empty() or index < 0 or index >= u.inventory.entries.size() or amount <= 0:
		return _trade(u, false, "Nothing to sell.")
	var item_id := int(u.inventory.entries[index].id)
	var def: Dictionary = item_db.get(str(item_id), {})
	if u.inventory.remove_at(index, amount) < 0:
		return _trade(u, false, "You do not have that many.")
	var gain := int(def.get("price", 0)) / 2 * amount
	u.zeny += gain
	events.append({"type": "inventory", "id": u.id})
	return _trade(u, true, "Sold  %s  ×%d   +%d z" % [def.name, amount, gain])


func close_shop(unit_id: int) -> void:
	var u: SimUnit = units.get(unit_id)
	if u:
		u.open_shop = 0


func _open_shop_of(u: SimUnit) -> Dictionary:
	if u == null or u.dead or u.open_shop == 0 or not npcs.has(u.open_shop):
		return {}
	var npc: Dictionary = npcs[u.open_shop]
	if _chebyshev(u.walker.cell, npc.cell) > NPC_TRADE_RANGE:
		return {}
	return shop_db.get(npc.shop, {})


func _trade(u: SimUnit, ok: bool, text: String) -> bool:
	if u:
		events.append({"type": "trade", "id": u.id, "ok": ok, "text": text})
	return ok


static func _slot_fits(def: Dictionary, slot: String) -> bool:
	var s := String(def.get("equip", ""))
	return s == slot or (s == "acc" and slot.begins_with("acc"))


## Spends status points to raise a stat by one. Returns false if not allowed.
func command_raise_stat(unit_id: int, stat: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or not u.is_player() or not STAT_NAMES.has(stat):
		return false
	var cost := StatRulesPreRenewal.raise_cost(int(u.stats[stat]))
	if cost < 0 or cost > u.status_points:
		return false
	u.status_points -= cost
	u.stats[stat] = int(u.stats[stat]) + 1
	var hp_frac := float(u.hp) / maxi(u.max_hp, 1)
	_recalc_player(u)
	u.hp = clampi(roundi(u.max_hp * hp_frac), 1, u.max_hp)
	events.append({"type": "stats", "id": u.id})
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
		if u.talk_target != 0:
			_pursue_talk(u)
		elif u.pickup_target != 0:
			_pursue_pickup(u)
		elif u.target_id != 0:
			_pursue(u)
		elif not u.is_player():
			_wander(u, ms)
		u.walker.advance(ms)
	for gid in ground_items.keys():
		var g: Dictionary = ground_items[gid]
		g.age += ms
		if g.age >= GROUND_ITEM_LIFETIME_MS:
			ground_items.erase(gid)
			events.append({"type": "ground_gone", "ground": gid})


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


func _pursue_talk(u: SimUnit) -> void:
	var npc: Dictionary = npcs.get(u.talk_target, {})
	if npc.is_empty():
		u.talk_target = 0
		return
	if _chebyshev(u.walker.cell, npc.cell) <= NPC_TALK_RANGE and not u.walker.is_moving():
		u.open_shop = u.talk_target
		u.talk_target = 0
		u.walker.direction = GridWalker.direction_to(u.walker.cell, npc.cell)
		events.append({"type": "npc_open", "id": u.id, "npc": npc.id})
		return
	if not u.walker.is_moving():
		var goal := pathfinder.nearest_walkable(npc.cell + Vector2i(0, -1), 3)
		var path := pathfinder.find_path(u.walker.planning_origin(), goal)
		if path.is_empty():
			u.talk_target = 0
		else:
			u.walker.walk(path)


func _pursue_pickup(u: SimUnit) -> void:
	var g: Dictionary = ground_items.get(u.pickup_target, {})
	if g.is_empty():
		u.pickup_target = 0
		return
	var dist := _chebyshev(u.walker.cell, g.cell)
	if dist <= 1 and not u.walker.is_moving():
		var gid := u.pickup_target
		u.pickup_target = 0
		if g.owner != 0 and g.owner != u.id and g.age < OWNER_PRIORITY_MS:
			events.append({"type": "pickup_fail", "id": u.id, "reason": "You cannot pick up this item yet."})
			return
		if not u.inventory.add(int(g.item), int(g.amount), item_db, u.max_weight() - u.equipment_weight(item_db)):
			events.append({"type": "pickup_fail", "id": u.id, "reason": "You are carrying too much weight."})
			return
		ground_items.erase(gid)
		events.append({"type": "pickup", "id": u.id, "ground": gid, "item": g.item, "amount": g.amount})
		events.append({"type": "inventory", "id": u.id})
		return
	if not u.walker.is_moving():
		var path := pathfinder.find_path(u.walker.planning_origin(), g.cell)
		if path.is_empty():
			u.pickup_target = 0
		else:
			u.walker.walk(path)


const DROP_OFFSETS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]


func _drop_loot(t: SimUnit, owner_id: int) -> void:
	var drops: Array = t.data.get("drops", [])
	var placed := 0
	for d in drops:
		if rng.randi_range(0, 9999) >= int(d[1]):
			continue
		if not item_db.has(str(int(d[0]))):
			continue
		# Spread drops over the death cell and its neighbours, like the client.
		var c: Vector2i = t.walker.cell + DROP_OFFSETS[placed % DROP_OFFSETS.size()]
		if not pathfinder.is_walkable(c):
			c = t.walker.cell
		var gid := _next_ground
		_next_ground += 1
		ground_items[gid] = {"id": gid, "item": int(d[0]), "amount": 1, "cell": c,
			"offset": Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)), "owner": owner_id, "age": 0.0}
		events.append({"type": "drop", "ground": gid})
		placed += 1


## Places an item on the ground (debug, quests, player drops).
func spawn_ground_item(item_id: int, amount: int, cell: Vector2i) -> int:
	var gid := _next_ground
	_next_ground += 1
	ground_items[gid] = {"id": gid, "item": item_id, "amount": amount, "cell": cell,
		"offset": Vector2(0.5, 0.5), "owner": 0, "age": 0.0}
	events.append({"type": "drop", "ground": gid})
	return gid


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
		var top := 0
		var top_dmg := -1
		for pid in t.damaged_by:
			if int(t.damaged_by[pid]) > top_dmg:
				top_dmg = int(t.damaged_by[pid])
				top = int(pid)
		_drop_loot(t, top)
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
	u.batk = StatRulesPreRenewal.status_atk(int(s.str), int(s.dex), int(s.luk))
	var weapon: Dictionary = item_db.get(str(u.equipment.get("weapon", 0)), {})
	u.weapon_type = String(weapon.get("weapon_type", "fist"))
	var wr := CombatRulesPreRenewal.weapon_atk_range(int(weapon.get("atk", 0)), int(weapon.get("weapon_level", 1)), int(s.dex))
	u.watk_min = wr.x
	u.watk_max = wr.y
	u.atk_min = u.batk + wr.x
	u.atk_max = u.batk + wr.y
	var def_total := 0
	for slot in u.equipment:
		def_total += int(item_db.get(str(u.equipment[slot]), {}).get("def", 0))
	u.hard_def = def_total
	var btba: float = NOVICE_BTBA.get(u.weapon_type, 0.6)
	var a := CombatRulesPreRenewal.aspd(btba, int(s.agi), int(s.dex))
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
