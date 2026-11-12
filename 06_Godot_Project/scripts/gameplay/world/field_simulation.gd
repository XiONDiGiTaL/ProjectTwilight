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
##   {type: "skill", id, skill, text}  {type: "skill_fail", id, text}  {type: "skills", id}
##   {type: "posture", id}   (sitting / play dead changed)  {type: "regen", id}
##   {type: "warp", id, to_map, to_cell: Vector2i}
##   {type: "job_change", id, job}  {type: "skill_hit", id, skill, cell}
##   {type: "cast_start", id, skill, element, level, target, duration}
##   {type: "cast_end", id, skill, ok: bool}   (ok = false: interrupted)
##   {type: "magic", id, skill, element, target, hits, cell, splash, fx}   (spell released)
##   {type: "skill_fx", id, skill, fx, element, cell, from_cell, area, hits}  (physical skill visual)
##   {type: "projectile", id, target, element, hits}  (visible arrow volley)
##   {type: "status", id, status, on: bool}   {type: "counter", id, target}
##   {type: "sp_heal", id, amount}   {type: "resurrect", id, by}
##   {type: "despawn", id}   (a unit left this map)
##   {type: "chat", channel: "guild", id, guild_id, guild_name, from, text}

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
## Level-1 class weapons handed out by the guild on a first job change. These
## are separate items from the level-gated shop weapons so every kit can be
## equipped by a freshly changed level-1 character.
const FIRST_JOB_WEAPON := {
	"swordman": 9001,   # Starter Katana
	"mage": 9002,       # Starter Rod
	"archer": 9003,     # Starter Short Bow
	"acolyte": 9004,    # Starter Club
	"merchant": 9005,   # Starter Axe
	"thief": 9006,      # Starter Main Gauche
}
const SKILL_DB := "res://data/prerenewal/skills.json"
const MAP_DB := "res://data/prerenewal/maps.json"
const JOB_DB := "res://data/prerenewal/jobs.json"
const JOB_CHANGE_JOB_LEVEL := 10
const JOB_CHANGE_BASIC_SKILL := 9
const WARP_RADIUS := 1
const NPC_TALK_RANGE := 2
const NPC_TRADE_RANGE := 6
## Kafra storage has no weight limit: items are counted in slots only.
const STORAGE_MAX_WEIGHT := 1 << 30
const GUILD_CHAT_MAX := 160
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
## Shared guilds and their storage (persisted outside character saves).
var guilds: GuildStore
var skill_db: Dictionary = {}
var map_db: Dictionary = {}
var job_db: Dictionary = {}
## Server rules: EXP / drop rates, autoloot and the level cap (RuleConfig).
var rules: RuleConfig
var map_name := ""
var map_info: Dictionary = {}
## Warp portals on this map: {cell: Vector2i, to_map, to_cell: Vector2i, label}
var warps: Array = []
var respawn_cell := Vector2i(-1, -1)
## npc id -> {id, name, sprite, cell: Vector2i, direction, shop, greeting}
var npcs: Dictionary = {}
var _next_npc := 1

var _next_id := 1


func _init(p_gat: GatFile, seed_value: int = 1, p_rules: RuleConfig = null, guild_path := "") -> void:
	gat = p_gat
	pathfinder = GridPathfinder.new(gat)
	rng.seed = seed_value
	rules = p_rules if p_rules != null else RuleConfig.load_config()
	monster_db = _load_json(MONSTER_DB)
	monster_db.erase("_doc")
	monster_db.erase("_provenance")
	exp_tables = _load_json(EXP_DB)
	exp_tables.erase("_doc")
	item_db = _load_json(ITEM_DB)
	item_db.erase("_provenance")
	job_db = _load_json(JOB_DB)
	job_db.erase("_provenance")
	map_db = _load_json(MAP_DB)
	map_db.erase("_doc")
	skill_db = _load_json(SKILL_DB)
	skill_db.erase("_provenance")
	shop_db = _load_json(SHOP_DB)
	shop_db.erase("_doc")
	for sid in shop_db:  # JSON numbers are floats; catalogues use int item ids
		var ids: Array[int] = []
		for v in shop_db[sid].get("items", []):
			ids.append(int(v))
		shop_db[sid].items = ids
	guilds = GuildStore.new(guild_path if guild_path != "" else GuildStore.PATH, item_db)


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
	_grant_default_skills(u)
	_recalc_player(u)
	u.hp = u.max_hp
	u.sp = u.max_sp
	_register(u)
	return u


## Populates the world for a map from maps.json: monsters, NPCs, warps, respawn point.
## `extra_warps`: rAthena warp portals for this map ({cell, span, to_map,
## to_cell, name}); when given they replace the maps.json warps.
func setup_map(name: String, extra_warps: Array = [], extra_spawns: Array = []) -> void:
	map_name = name
	map_info = map_db.get(name, {})
	var rp: Array = map_info.get("respawn", [])
	if rp.size() == 2:
		respawn_cell = pathfinder.nearest_walkable(Vector2i(int(rp[0]), int(rp[1])), 20)
	warps.clear()
	if not extra_warps.is_empty():
		for w in extra_warps:
			var to_map := String(w.to_map)
			warps.append({"cell": w.cell, "span": w.get("span", Vector2i.ONE), "to_map": to_map, "to_cell": w.to_cell,
				"label": String(map_db.get(to_map, {}).get("name", to_map))})
	else:
		for w in map_info.get("warps", []):
			warps.append({"cell": Vector2i(int(w.cell[0]), int(w.cell[1])), "to_map": String(w.to_map),
				"to_cell": Vector2i(int(w.to_cell[0]), int(w.to_cell[1])), "label": String(w.get("label", "")),
				"span": Vector2i(WARP_RADIUS, WARP_RADIUS)})
	var spawns: Dictionary = map_info.get("spawns", {})
	for mob in spawns:
		spawn_random(String(mob), int(spawns[mob]))
	# rAthena spawn lines, for maps maps.json does not populate. Only monsters
	# in monsters.json can appear; others are skipped until their data exists.
	if spawns.is_empty():
		for sp in extra_spawns:
			var id := str(int(sp.mob_id))
			if not monster_db.has(id):
				continue
			for i in mini(int(sp.amount), 60):
				var a: Vector2i = sp.area
				if Vector2i(sp.cell) == Vector2i.ZERO:
					spawn_random(id, 1)
				else:
					add_monster(id, sp.cell, maxi(a.x, a.y))
	spawn_npcs(name)


## Warp whose touch area contains `cell` (rAthena span: x +/- sx, y +/- sy), or {}.
func warp_at(cell: Vector2i) -> Dictionary:
	for w in warps:
		var sp: Vector2i = w.get("span", Vector2i(WARP_RADIUS, WARP_RADIUS))
		var c: Vector2i = w.cell
		if absi(cell.x - c.x) <= maxi(sp.x, 0) and absi(cell.y - c.y) <= maxi(sp.y, 0):
			return w
	return {}


## Spawns the shop NPCs defined for `map_name` in shops.json.
func spawn_npcs(map_name: String) -> void:
	for shop_id in shop_db:
		var s: Dictionary = shop_db[shop_id]
		if String(s.get("map", "")) != map_name:
			continue
		var nid := _next_npc
		_next_npc += 1
		npcs[nid] = {"id": nid, "name": s.npc_name, "sprite": s.sprite, "kind": "shop",
			"cell": Vector2i(int(s.cell[0]), int(s.cell[1])), "direction": int(s.get("direction", 0)),
			"shop": shop_id, "greeting": String(s.get("greeting", ""))}
		events.append({"type": "npc_spawn", "npc": nid})
	for n in map_db.get(map_name, {}).get("npcs", []):
		var nid := _next_npc
		_next_npc += 1
		npcs[nid] = {"id": nid, "name": String(n.name), "sprite": String(n.sprite), "kind": String(n.get("kind", "talk")),
			"cell": Vector2i(int(n.cell[0]), int(n.cell[1])), "direction": int(n.get("direction", 0)),
			"shop": "", "greeting": String(n.get("greeting", ""))}
		events.append({"type": "npc_spawn", "npc": nid})


## Restores a player from a validated SaveGame character dictionary.
func add_player_from_save(c: Dictionary) -> SimUnit:
	var u := add_player(String(c.name), c.cell, c.stats)
	u.job = String(c.job) if job_db.has(String(c.job)) else "novice"
	u.sprite = String(job_db.get(u.job, {}).get("sprite", "초보자"))
	u.male = bool(c.get("male", true))
	u.hair_style = int(c.get("hair_style", 2))
	u.hair_color = int(c.get("hair_color", 0))
	u.aura = String(c.get("aura", "class"))
	u.cloth_color = int(c.get("cloth_color", 0))
	u.script_vars = c.get("script_vars", {})
	u.save_map = String(c.get("save_map", SimUnit.HUB_MAP))
	u.save_cell = Vector2i(int(c.get("save_cell", [SimUnit.HUB_CELL.x, SimUnit.HUB_CELL.y])[0]), int(c.get("save_cell", [SimUnit.HUB_CELL.x, SimUnit.HUB_CELL.y])[1]))
	u.options = c.get("options", {})
	u.guild_id = String(c.get("guild_id", ""))
	u.guild_name = String(c.get("guild_name", ""))
	if u.guild_id != "" and u.guild_name != "":
		var g: Dictionary = guilds.join(u.guild_name, u.name)
		u.guild_id = String(g.get("id", u.guild_id))
		_guild_motd_notice(u, g)
	u.level = int(c.level)
	u.job_level = int(c.job_level)
	u.base_exp = int(c.base_exp)
	u.job_exp = int(c.job_exp)
	u.status_points = int(c.status_points)
	u.zeny = int(c.zeny)
	u.inventory = Inventory.from_array(c.inventory, item_db)
	u.storage = Inventory.from_array(c.get("storage", []), item_db)
	u.storage.max_entries = SimUnit.STORAGE_SLOTS
	var saved_skills: Dictionary = c.get("skills", {})
	if not saved_skills.is_empty():
		u.skills = {}
		for code in saved_skills:
			if skill_db.has(code):
				u.skills[code] = clampi(int(saved_skills[code]), 0, int(skill_db[code].max_level))
		_grant_default_skills(u, false)
	if c.has("skill_points") and c.has("skills"):
		u.skill_points = int(c.skill_points)
	else:
		u.skill_points = maxi(0, u.job_level - 1 - _spent_skill_points(u))
	var hk: Variant = c.get("hotkeys", [])
	if hk is Array:
		for i in mini(hk.size(), u.hotkeys.size()):
			u.hotkeys[i] = hk[i]
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
	u.element = String(m.get("element", "neutral"))
	u.element_level = int(m.get("element_level", 1))
	u.mdef = int(m.get("mdef", 0))
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
	if u.trickdead:
		return _skill_fail(u, "You cannot move while playing dead.")
	if u.is_incapacitated():
		return _skill_fail(u, "You cannot move right now.")
	if u.has_status("confusion"):
		# Confused: the walk goes somewhere random nearby instead.
		cell = u.walker.cell + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
	u.sitting = false
	u.target_id = 0
	u.queued_skill = ""
	u.pickup_target = 0
	u.talk_target = 0
	_cancel_cast(u)
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
	if u.trickdead:
		return _skill_fail(u, "You cannot attack while playing dead.")
	if u.is_incapacitated():
		return _skill_fail(u, "You cannot attack right now.")
	u.sitting = false
	u.target_id = target_id
	u.pickup_target = 0
	return true


## Walk to a ground item and pick it up.
func command_pickup(unit_id: int, ground_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or u.trickdead or not ground_items.has(ground_id):
		return false
	u.sitting = false
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
	# Quivers unpack into arrows; the quiver is removed only after the arrows fit.
	if String(def.get("use_effect", "")) == "ammo":
		var ammo_id := int(def.get("ammo_item", 0))
		var ammo_amount := int(def.get("ammo_amount", 0))
		if ammo_id <= 0 or ammo_amount <= 0 or not item_db.has(str(ammo_id)):
			return false
		u.inventory.remove_at(index, 1)
		if not u.inventory.add(ammo_id, ammo_amount, item_db, u.max_weight() - u.equipment_weight(item_db)):
			u.inventory.entries.insert(mini(index, u.inventory.entries.size()), {"id": item_id, "amount": 1})
			return false
		events.append({"type": "inventory", "id": u.id})
		return true
	var heal_range: Array = def.get("heal_hp", [0, 0])
	u.inventory.remove_at(index, 1)
	var amount := rng.randi_range(int(heal_range[0]), int(heal_range[1]))
	amount = amount * (100 + 10 * int(u.skills.get("SM_RECOVERY", 0))) / 100
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
	if slot == "weapon" and not (job_db.get(u.job, {}).get("btba", {}) as Dictionary).has(String(def.get("weapon_type", ""))):
		return _skill_fail(u, "Your class cannot use this weapon.")
	if slot == "shield" and bool(item_db.get(str(u.equipment.get("weapon", 0)), {}).get("two_handed", false)):
		return _skill_fail(u, "You cannot use a shield with a two-handed weapon.")
	u.inventory.remove_at(index, 1)
	if slot == "weapon":
		_clear_weapon_buffs(u)
		if bool(def.get("two_handed", false)) and u.equipment.has("shield"):
			u.inventory.entries.append({"id": int(u.equipment.shield), "amount": 1})
			u.equipment.erase("shield")
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


# --- Kafra storage -----------------------------------------------------------

## Marks a Kafra's storage as open for a player. Range-checked.
## `charge_fee` applies rules.kafra_fee; rAthena Kafra scripts pass false
## because they already charge the fee written in their own script.
func command_open_storage(unit_id: int, npc_id: int, charge_fee := true) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or not npcs.has(npc_id):
		return false
	var npc: Dictionary = npcs[npc_id]
	var kind := String(npc.get("kind", ""))
	# A script NPC may open storage when its own script runs openstorage.
	if kind != "kafra" and kind != "script":
		return false
	if _chebyshev(u.walker.cell, npc.cell) > NPC_TRADE_RANGE:
		return _storage(u, false, "You are too far from the Kafra.")
	var fee := maxi(0, rules.kafra_fee) if charge_fee else 0
	if fee > 0:
		if u.zeny < fee:
			return _storage(u, false, "You need %d zeny to use storage." % fee)
		u.zeny -= fee
		events.append({"type": "inventory", "id": u.id})
	u.open_storage = npc_id
	u.open_shop = 0
	return _storage(u, true, "Storage opened" + ("  -%d z" % fee if fee > 0 else ""))


func close_storage(unit_id: int) -> void:
	var u: SimUnit = units.get(unit_id)
	if u:
		u.open_storage = 0


func _open_storage_of(u: SimUnit) -> Dictionary:
	if u == null or u.dead or u.open_storage == 0 or not npcs.has(u.open_storage):
		return {}
	var npc: Dictionary = npcs[u.open_storage]
	if _chebyshev(u.walker.cell, npc.cell) > NPC_TRADE_RANGE:
		return {}
	return npc


## Simulation NPC placed for an rAthena script (nearest copy near the player).
func script_npc_id(script_name: String, near: Vector2i) -> int:
	var best := 0
	var best_d := 1 << 30
	for nid in npcs:
		var n: Dictionary = npcs[nid]
		if String(n.get("script", "")) != script_name:
			continue
		var d := _chebyshev(near, n.cell)
		if d < best_d:
			best_d = d
			best = nid
	return best


## Moves inventory entry `index` into the open Kafra storage.
func command_storage_deposit(unit_id: int, index: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if _open_storage_of(u).is_empty() or index < 0 or index >= u.inventory.entries.size() or amount <= 0:
		return false
	var e: Dictionary = u.inventory.entries[index]
	if int(e.amount) < amount:
		return _storage(u, false, "You do not have that many.")
	if not u.storage.add(int(e.id), amount, item_db, STORAGE_MAX_WEIGHT):
		return _storage(u, false, "Kafra storage is full.")
	u.inventory.remove_at(index, amount)
	events.append({"type": "inventory", "id": u.id})
	return _storage(u, true, "Stored  %s  ×%d" % [String(item_db.get(str(int(e.id)), {}).get("name", "item")), amount])


## Moves stored entry `index` back into the inventory (weight and slots apply).
func command_storage_withdraw(unit_id: int, index: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if _open_storage_of(u).is_empty() or index < 0 or index >= u.storage.entries.size() or amount <= 0:
		return false
	var e: Dictionary = u.storage.entries[index]
	if int(e.amount) < amount:
		return _storage(u, false, "There are not that many in storage.")
	if not u.inventory.add(int(e.id), amount, item_db, u.max_weight() - u.equipment_weight(item_db)):
		return _storage(u, false, "You cannot carry that much.")
	u.storage.remove_at(index, amount)
	events.append({"type": "inventory", "id": u.id})
	return _storage(u, true, "Withdrew  %s  ×%d" % [String(item_db.get(str(int(e.id)), {}).get("name", "item")), amount])


func _storage(u: SimUnit, ok: bool, text: String) -> bool:
	if u:
		events.append({"type": "storage", "id": u.id, "ok": ok, "text": text})
	return ok


# --- Guilds and guild storage ------------------------------------------------

## Founds a guild, or joins the existing guild with that name.
func command_create_guild(unit_id: int, guild_name: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var clean := guild_name.strip_edges().left(24)
	if u == null or not u.is_player() or u.guild_id != "" or clean.length() < 2:
		return false
	var g: Dictionary = guilds.join(clean, u.name)
	if g.is_empty():
		return false
	u.guild_id = String(g.id)
	u.guild_name = String(g.name)
	events.append({"type": "guild", "id": u.id, "ok": true, "text": "Guild  %s" % u.guild_name})
	_guild_motd_notice(u, g)
	return true


## The acting unit's rank in its own guild, read from the guild record (never
## from the client): "leader" / "officer" / "member", or "" when guildless.
func guild_rank(u: SimUnit) -> String:
	return guilds.rank_of(u.guild_id, u.name) if u != null and u.guild_id != "" else ""


## Leader / officer invitation; persists for characters who are offline.
func command_guild_invite(unit_id: int, target_name: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null or g.is_empty():
		return false
	if not GuildStore.can(guild_rank(u), "invite"):
		return _guild(u, false, "Only the leader and officers can invite.")
	var target := target_name.strip_edges().left(23)
	if target.length() < 2 or target == u.name:
		return _guild(u, false, "That name cannot be invited.")
	if (g.members as Array).has(target):
		return _guild(u, false, "%s is already a member." % target)
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.is_player() and other.name == target and other.guild_id != "":
			return _guild(u, false, "%s is already in a guild." % target)
	if not guilds.invite(u.guild_id, target):
		return _guild(u, false, "Could not invite %s." % target)
	return _guild(u, true, "Invited %s to %s." % [target, String(g.name)])


func command_guild_accept(unit_id: int, gid: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.guild_id != "":
		return false
	var g: Dictionary = guilds.accept(gid, u.name)
	if g.is_empty():
		return _guild(u, false, "That invitation is no longer valid.")
	u.guild_id = String(g.id)
	u.guild_name = String(g.name)
	_guild_motd_notice(u, g)
	return _guild(u, true, "Joined guild %s." % u.guild_name)


func command_guild_decline(unit_id: int, gid: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or not guilds.decline(gid, u.name):
		return false
	return _guild(u, true, "Invitation declined.")


## Removal by rank: the leader may remove officers and members, officers only
## ordinary members. An online member loses the guild immediately.
func command_guild_kick(unit_id: int, target_name: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null or g.is_empty():
		return false
	var rank := guild_rank(u)
	if not GuildStore.can(rank, "invite"):   # members have no removal rights at all
		return _guild(u, false, "Only the leader and officers can remove members.")
	var target := target_name.strip_edges().left(23)
	if target == u.name or not (g.members as Array).has(target):
		return _guild(u, false, "That member is not in the guild.")
	if not GuildStore.can(rank, "kick", guilds.rank_of(u.guild_id, target)):
		return _guild(u, false, "Officers can only remove ordinary members.")
	if not guilds.kick(u.guild_id, target):
		return _guild(u, false, "Could not remove %s." % target)
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.is_player() and other.name == target and other.guild_id == u.guild_id:
			other.guild_id = ""
			other.guild_name = ""
			other.open_guild_storage = ""
			other.open_guild_npc = 0
			events.append({"type": "guild", "id": other.id, "ok": false, "text": "You were removed from %s." % String(g.name)})
	return _guild(u, true, "Removed %s from the guild." % target)


## Leader-only: makes a member an officer.
func command_guild_promote(unit_id: int, target_name: String) -> bool:
	return _guild_set_rank(unit_id, target_name, "promote", GuildStore.RANK_OFFICER)


## Leader-only: makes an officer an ordinary member again.
func command_guild_demote(unit_id: int, target_name: String) -> bool:
	return _guild_set_rank(unit_id, target_name, "demote", GuildStore.RANK_MEMBER)


## Leader / officer only: set or clear the guild message of the day.
func command_guild_set_motd(unit_id: int, text: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null:
		return false
	if g.is_empty():
		return _guild(u, false, "You are not in a guild.")
	if not GuildStore.can(guild_rank(u), "motd"):
		return _guild(u, false, "Only the leader and officers can edit the guild message.")
	var clean := GuildStore.clean_motd(text)
	guilds.set_motd(u.guild_id, clean)
	return _guild(u, true, "Guild message cleared." if clean == "" else "Guild message updated.")


## Guild chat: one event per online member, so only members receive it.
func command_guild_chat(unit_id: int, text: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null:
		return false
	if g.is_empty():
		return _guild(u, false, "You are not in a guild.")
	if not GuildStore.can(guild_rank(u), "chat"):
		return _guild(u, false, "Only guild members can use guild chat.")
	var clean := text.replace("\r", " ").replace("\n", " ").strip_edges().left(GUILD_CHAT_MAX)
	if clean == "":
		return _guild(u, false, "Type a message.")
	var delivered := false
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.is_player() and other.guild_id == u.guild_id:
			events.append({"type": "chat", "channel": "guild", "id": other.id,
				"guild_id": u.guild_id, "guild_name": String(g.name), "from": u.name, "text": clean})
			delivered = true
	return delivered


func _guild_motd_notice(u: SimUnit, g: Dictionary) -> void:
	var motd := String(g.get("motd", ""))
	if u != null and motd != "":
		events.append({"type": "guild", "id": u.id, "ok": true, "text": "Guild message: %s" % motd})


func _guild_set_rank(unit_id: int, target_name: String, action: String, rank: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null or g.is_empty():
		return false
	if not GuildStore.can(guild_rank(u), action):
		return _guild(u, false, "Only the guild leader can %s members." % action)
	var target := target_name.strip_edges().left(23)
	if target == u.name or not (g.members as Array).has(target):
		return _guild(u, false, "%s is not a member of the guild." % (target if target != "" else "That name"))
	if not guilds.set_rank(u.guild_id, target, rank):
		return _guild(u, false, "%s is already %s." % [target, "an officer" if rank == GuildStore.RANK_OFFICER else "an ordinary member"])
	var text := "%s is now %s of %s." % [target, "an officer" if rank == GuildStore.RANK_OFFICER else "a member", String(g.name)]
	_guild_tell(u.guild_id, target, true, "You are now %s of %s." % ["an officer" if rank == GuildStore.RANK_OFFICER else "a member", String(g.name)])
	return _guild(u, true, text)


## Leader-only: hands the guild to another member; the old leader becomes an officer.
func command_guild_transfer(unit_id: int, target_name: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null or g.is_empty():
		return false
	if not GuildStore.can(guild_rank(u), "transfer"):
		return _guild(u, false, "Only the guild leader can transfer leadership.")
	var target := target_name.strip_edges().left(23)
	if target == u.name or not (g.members as Array).has(target):
		return _guild(u, false, "%s is not a member of the guild." % (target if target != "" else "That name"))
	if not guilds.transfer(u.guild_id, target):
		return _guild(u, false, "Could not transfer leadership to %s." % target)
	_guild_tell(u.guild_id, target, true, "You are now the leader of %s." % String(g.name))
	return _guild(u, true, "%s now leads %s. You are an officer." % [target, String(g.name)])


## Leader-only and irreversible: removes the guild, its storage and every
## online member's guild state.
func command_guild_disband(unit_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g: Dictionary = guilds.get_guild(u.guild_id) if u != null else {}
	if u == null or g.is_empty():
		return false
	if not GuildStore.can(guild_rank(u), "disband"):
		return _guild(u, false, "Only the guild leader can disband the guild.")
	var gid := u.guild_id
	var gname := String(g.name)
	if not guilds.disband(gid):
		return _guild(u, false, "Could not disband the guild.")
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.is_player() and other.guild_id == gid:
			other.guild_id = ""
			other.guild_name = ""
			other.open_guild_storage = ""
			other.open_guild_npc = 0
			if other.id != u.id:
				events.append({"type": "guild", "id": other.id, "ok": false, "text": "%s was disbanded." % gname})
	return _guild(u, true, "You disbanded %s." % gname)


## Guild notice to one online member by name (no-op when they are offline).
func _guild_tell(gid: String, member: String, ok: bool, text: String) -> void:
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.is_player() and other.name == member and other.guild_id == gid:
			events.append({"type": "guild", "id": other.id, "ok": ok, "text": text})


func command_leave_guild(unit_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.guild_id == "":
		return false
	var was_leader := guild_rank(u) == GuildStore.RANK_LEADER
	var left_gid := u.guild_id
	guilds.leave(u.guild_id, u.name)
	if was_leader:
		var after: Dictionary = guilds.get_guild(left_gid)
		if not after.is_empty():
			_guild_tell(left_gid, String(after.leader), true, "You are now the leader of %s." % String(after.name))
	u.open_guild_storage = ""
	u.open_guild_npc = 0
	u.guild_id = ""
	u.guild_name = ""
	events.append({"type": "guild", "id": u.id, "ok": true, "text": "You left your guild."})
	return true


## Opens the shared guild storage. Only one member may use it at a time.
func command_open_guild_storage(unit_id: int, npc_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or not npcs.has(npc_id):
		return false
	var npc: Dictionary = npcs[npc_id]
	var kind := String(npc.get("kind", ""))
	if kind != "kafra" and kind != "script":
		return false
	if u.guild_id == "" or guilds.get_guild(u.guild_id).is_empty():
		return _guild_storage(u, false, "You are not in a guild.")
	if _chebyshev(u.walker.cell, npc.cell) > NPC_TRADE_RANGE:
		return _guild_storage(u, false, "You are too far from the guild storage.")
	for other_id in units:
		var other: SimUnit = units[other_id]
		if other.id != u.id and not other.dead and other.open_guild_storage == u.guild_id:
			return _guild_storage(u, false, "Another guild member is using the guild storage.")
	u.open_guild_storage = u.guild_id
	u.open_guild_npc = npc_id
	u.open_storage = 0
	u.open_shop = 0
	return _guild_storage(u, true, "Guild storage opened")


func close_guild_storage(unit_id: int) -> void:
	var u: SimUnit = units.get(unit_id)
	if u:
		u.open_guild_storage = ""
		u.open_guild_npc = 0


func _open_guild_storage_of(u: SimUnit) -> Dictionary:
	if u == null or u.dead or u.guild_id == "" or u.open_guild_storage != u.guild_id:
		return {}
	if not npcs.has(u.open_guild_npc):
		return {}
	var npc: Dictionary = npcs[u.open_guild_npc]
	if _chebyshev(u.walker.cell, npc.cell) > NPC_TRADE_RANGE:
		return {}
	return guilds.get_guild(u.guild_id)


func command_guild_deposit(unit_id: int, index: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g := _open_guild_storage_of(u)
	if g.is_empty() or index < 0 or index >= u.inventory.entries.size() or amount <= 0:
		return false
	var bag: Inventory = g.get("storage")
	var e: Dictionary = u.inventory.entries[index]
	if int(e.amount) < amount:
		return _guild_storage(u, false, "You do not have that many.")
	if not bag.add(int(e.id), amount, item_db, STORAGE_MAX_WEIGHT):
		return _guild_storage(u, false, "Guild storage is full.")
	u.inventory.remove_at(index, amount)
	guilds.save()
	events.append({"type": "inventory", "id": u.id})
	return _guild_storage(u, true, "Stored  %s  ×%d  in the guild storage" % [String(item_db.get(str(int(e.id)), {}).get("name", "item")), amount])


func command_guild_withdraw(unit_id: int, index: int, amount: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	var g := _open_guild_storage_of(u)
	if g.is_empty() or amount <= 0:
		return false
	var bag: Inventory = g.get("storage")
	if index < 0 or index >= bag.entries.size():
		return false
	var e: Dictionary = bag.entries[index]
	if int(e.amount) < amount:
		return _guild_storage(u, false, "There are not that many in the guild storage.")
	if not u.inventory.add(int(e.id), amount, item_db, u.max_weight() - u.equipment_weight(item_db)):
		return _guild_storage(u, false, "You cannot carry that much.")
	bag.remove_at(index, amount)
	guilds.save()
	events.append({"type": "inventory", "id": u.id})
	return _guild_storage(u, true, "Withdrew  %s  ×%d  from the guild storage" % [String(item_db.get(str(int(e.id)), {}).get("name", "item")), amount])


func _guild_storage(u: SimUnit, ok: bool, text: String) -> bool:
	if u:
		events.append({"type": "guild_storage", "id": u.id, "ok": ok, "text": text})
	return ok


func _guild(u: SimUnit, ok: bool, text: String) -> bool:
	if u:
		events.append({"type": "guild", "id": u.id, "ok": ok, "text": text})
	return ok


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


## Learns one level of a skill with a skill point.
func command_learn_skill(unit_id: int, code: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var s: Dictionary = skill_db.get(code, {})
	if u == null or s.is_empty() or s.get("quest", false) or u.skill_points <= 0:
		return false
	if not available_skills(u).has(code) or skill_requirements_unmet(u, code) != "":
		return false
	var lv := int(u.skills.get(code, 0))
	if lv >= int(s.max_level):
		return false
	u.skills[code] = lv + 1
	u.skill_points -= 1
	_recalc_player(u)
	events.append({"type": "skills", "id": u.id})
	return true


## Changes a Novice into a first job (Novice job level 10 and Basic Skill 9).
func command_job_change(unit_id: int, job: String) -> bool:
	var u: SimUnit = units.get(unit_id)
	var j: Dictionary = job_db.get(job, {})
	if u == null or u.dead or j.is_empty() or not (int(j.get("tier", 0)) in [1, 2, 3, 4] or _forcing_job):
		return false
	var reason := "" if _forcing_job else job_change_unmet(u, job)
	if reason != "":
		return _skill_fail(u, reason)
	# Pre-Renewal: unspent points carry over from second job onward. This also
	# covers transcendence and third jobs, so no points are lost on promotion.
	var keep_points := u.skill_points if int(j.tier) >= 2 else 0
	var hp_frac := float(u.hp) / maxi(u.max_hp, 1)
	u.job = job
	u.sprite = String(j.sprite)
	u.job_level = 1
	u.job_exp = 0
	u.skill_points = keep_points
	u.statuses.clear()
	_grant_default_skills(u, false)
	# A weapon the new class cannot use goes back to the inventory.
	if u.equipment.has("weapon") and not (j.btba as Dictionary).has(String(item_db.get(str(u.equipment.weapon), {}).get("weapon_type", ""))):
		command_unequip(u.id, "weapon")
	_recalc_player(u)
	_grant_first_job_kit(u, job)
	u.hp = clampi(roundi(u.max_hp * hp_frac), 1, u.max_hp)
	events.append({"type": "job_change", "id": u.id, "job": job})
	events.append({"type": "skills", "id": u.id})
	return true


## Display name of the guild-issued first-job weapon, or "" for other jobs.
func first_job_weapon_name(job: String) -> String:
	var weapon_id := int(FIRST_JOB_WEAPON.get(job, 0))
	return String(item_db.get(str(weapon_id), {}).get("name", "")) if weapon_id != 0 else ""


## First-job equipment supplied by the guild so the new class can fight at once.
func _grant_first_job_kit(u: SimUnit, job: String) -> void:
	var weapon_id := int(FIRST_JOB_WEAPON.get(job, 0))
	if weapon_id == 0:
		return
	var max_w := u.max_weight() - u.equipment_weight(item_db)
	u.inventory.add(weapon_id, 1, item_db, max_w)
	if job == "archer":
		u.inventory.add(1750, 100, item_db, max_w)   # Arrows
		u.inventory.add(1751, 1, item_db, max_w)     # Quiver
	for i in range(u.inventory.entries.size()):
		if int(u.inventory.entries[i].id) == weapon_id:
			command_equip(u.id, i)
			return


## "" if `u` may change to `job` now, else the reason.
func job_change_unmet(u: SimUnit, job: String) -> String:
	var j: Dictionary = job_db.get(job, {})
	if j.is_empty():
		return "Unknown job."
	if int(j.get("tier", 0)) == 1:
		if u.job != "novice":
			return "Only Novices can take a first job."
		if u.job_level < JOB_CHANGE_JOB_LEVEL or int(u.skills.get("NV_BASIC", 0)) < JOB_CHANGE_BASIC_SKILL:
			return "You need Job Level %d and Basic Skill level %d." % [JOB_CHANGE_JOB_LEVEL, JOB_CHANGE_BASIC_SKILL]
		return ""
	if u.job != String(j.get("parent", "")):
		return "Only a %s can become a %s." % [String(job_db.get(String(j.get("parent", "")), {}).get("name", "?")), String(j.name)]
	var need_base := int(j.get("min_parent_base_level", 0))
	if u.level < need_base:
		return "You need Base Level %d as a %s (you have %d)." % [need_base, String(job_db.get(u.job, {}).get("name", u.job)), u.level]
	var need := int(j.get("min_parent_job_level", 40))
	if u.job_level < need:
		return "You need Job Level %d as a %s (you have %d)." % [need, String(job_db.get(u.job, {}).get("name", u.job)), u.job_level]
	if String(j.get("sex", "")) == "female" and u.male:
		return "The %s path is open to women only." % String(j.name)
	if String(j.get("sex", "")) == "male" and not u.male:
		return "The %s path is open to men only." % String(j.name)
	return ""


## Uses a skill. Validated here: learned, SP, delay, posture.
func command_use_skill(unit_id: int, code: String, target_id: int = 0) -> bool:
	var u: SimUnit = units.get(unit_id)
	var s: Dictionary = skill_db.get(code, {})
	if u == null or u.dead or s.is_empty():
		return false
	if int(u.skills.get(code, 0)) <= 0:
		return _skill_fail(u, "You have not learned %s." % s.name)
	if s.type == "passive":
		return _skill_fail(u, "%s is a passive skill." % s.name)
	if code == "NV_TRICKDEAD" and u.trickdead:
		u.trickdead = false
		events.append({"type": "posture", "id": u.id})
		events.append({"type": "skill", "id": u.id, "skill": code, "text": "You get back up."})
		return true
	if u.trickdead:
		return _skill_fail(u, "You cannot do that while playing dead.")
	if u.is_incapacitated():
		return _skill_fail(u, "You cannot act right now.")
	if u.has_status("silence"):
		return _skill_fail(u, "You are silenced.")
	if u.is_casting():
		return _skill_fail(u, "You are already casting.")
	var weapon_err := _weapon_unmet(u, s)
	if weapon_err != "":
		return _skill_fail(u, weapon_err)
	if _needs_ammo(u, s) and not _has_ammo(u):
		return _skill_fail(u, "You have no arrows.")
	if u.skill_delay > 0.0:
		return _skill_fail(u, "Skill is not ready yet.")
	var level := int(u.skills.get(code, 0))
	var costs: Array = s.get("sp_cost", [0])
	var cost := int(costs[clampi(level - 1, 0, costs.size() - 1)])
	if u.sp < cost:
		return _skill_fail(u, "Not enough SP.")
	if String(s.get("target", "")) == "enemy":
		# Queue it: the unit walks into range and the skill replaces its next attack.
		var t: SimUnit = units.get(target_id if target_id != 0 else u.target_id)
		if t == null or t.dead or t.is_player():
			return _skill_fail(u, "Select a target first.")
		u.target_id = t.id
		u.queued_skill = code
		u.sitting = false
		if _uses_cast(s) and _chebyshev(u.walker.cell, t.walker.cell) <= int(s.get("range", 9 if s.has("magic") else u.attack_range)) and not u.walker.is_moving():
			_begin_cast(u, t)
		return true
	var tgt_kind := String(s.get("target", ""))
	if tgt_kind == "ally" or tgt_kind == "dead_ally":
		return _use_support(u, code, s, level, target_id)
	if tgt_kind == "self":
		if not _pay(u, s, level):
			return false
		_self_skill(u, code, s, level)
		return true
	if tgt_kind == "self_area" and code != "SM_MAGNUM":
		if not _pay(u, s, level):
			return false
		_area_skill(u, code, s, level)
		return true
	u.sp -= cost
	u.skill_delay = float(s.get("after_cast_delay", 0))
	match code:
		"NV_FIRSTAID":
			var before := u.hp
			u.hp = mini(u.max_hp, u.hp + int(s.heal_hp))
			events.append({"type": "heal", "id": u.id, "amount": u.hp - before})
			events.append({"type": "skill", "id": u.id, "skill": code, "text": "First Aid"})
		"NV_TRICKDEAD":
			u.trickdead = true
			u.sitting = false
			u.target_id = 0
			u.walker.stop()
			for id in units:
				var m: SimUnit = units[id]
				if m.target_id == u.id:
					m.target_id = 0
			events.append({"type": "posture", "id": u.id})
			events.append({"type": "skill", "id": u.id, "skill": code, "text": "Play Dead"})
		"SM_MAGNUM":
			_magnum_break(u, s, level)
	return true


func _skill_profile(u: SimUnit, s: Dictionary, level: int) -> Dictionary:
	var prof := u.combat_profile()
	prof.skill_pct = int(s.get("damage_pct_base", 100)) + int(s.get("damage_pct_per_level", 0)) * level
	prof.hit_mult_pct = 100 + int(s.get("hit_pct_per_level", 0)) * level
	prof.can_crit = false
	return prof


func _magnum_break(u: SimUnit, s: Dictionary, level: int) -> void:
	var prof := _skill_profile(u, s, level)
	var area := int(s.get("area", 2))
	events.append({"type": "skill", "id": u.id, "skill": "SM_MAGNUM", "text": "Magnum Break"})
	events.append({"type": "skill_hit", "id": u.id, "skill": "SM_MAGNUM", "cell": u.walker.cell})
	for id in units.keys():
		var t: SimUnit = units[id]
		if t.is_player() or t.dead or _chebyshev(u.walker.cell, t.walker.cell) > area:
			continue
		_apply_hit(u, t, CombatRulesPreRenewal.resolve_attack(prof, t.combat_profile(), rng), String(s.get("element", "neutral")))


# --- Magic (Pre-Renewal cast time, MATK, elements) ---------------------------

func _skill_cost(s: Dictionary, level: int) -> int:
	var costs: Array = s.get("sp_cost", [0])
	return int(costs[clampi(level - 1, 0, costs.size() - 1)])


## A per-level skill value: a number, or an array indexed by level.
static func per_level(s: Dictionary, key: String, level: int, fallback: float = 0.0) -> float:
	var v: Variant = s.get(key, fallback)
	if v is Array:
		var a: Array = v
		return float(a[clampi(level - 1, 0, a.size() - 1)]) if not a.is_empty() else fallback
	return float(v)


func _begin_cast(u: SimUnit, t: SimUnit) -> void:
	var code := u.queued_skill
	u.queued_skill = ""
	var s: Dictionary = skill_db.get(code, {})
	var level := int(u.skills.get(code, 0))
	if level <= 0 or u.sp < _skill_cost(s, level):
		_skill_fail(u, "Not enough SP.")
		return
	u.walker.stop()
	u.walker.direction = GridWalker.direction_to(u.walker.cell, t.walker.cell)
	u.cast_skill = code
	u.cast_level = level
	u.cast_target = t.id
	u.cast_total = ElementRulesPreRenewal.cast_time_ms(per_level(s, "cast_time", level), int(u.stats.dex))
	u.cast_left = u.cast_total
	events.append({"type": "cast_start", "id": u.id, "skill": code, "element": String(s.get("element", "neutral")),
		"level": level, "target": t.id, "duration": u.cast_total})
	if u.cast_total <= 0.0:
		_advance_cast(u, 0.0)


func _cancel_cast(u: SimUnit) -> void:
	if not u.is_casting():
		return
	events.append({"type": "cast_end", "id": u.id, "skill": u.cast_skill, "ok": false})
	u.cast_skill = ""
	u.cast_target = 0


func _advance_cast(u: SimUnit, ms: float) -> void:
	var t: SimUnit = units.get(u.cast_target)
	var wants_dead := String(skill_db.get(u.cast_skill, {}).get("target", "")) == "dead_ally"
	if t == null or t.dead != wants_dead or t.trickdead:
		_cancel_cast(u)
		u.target_id = 0
		return
	u.cast_left -= ms
	if u.cast_left > 0.0:
		return
	var code := u.cast_skill
	var level := u.cast_level
	var s: Dictionary = skill_db.get(code, {})
	u.cast_skill = ""
	u.cast_target = 0
	var cost := _skill_cost(s, level)
	if _weapon_unmet(u, s) != "":
		events.append({"type": "cast_end", "id": u.id, "skill": code, "ok": false})
		_skill_fail(u, _weapon_unmet(u, s))
		return
	if u.sp < cost:   # SP is spent when the spell is released
		events.append({"type": "cast_end", "id": u.id, "skill": code, "ok": false})
		_skill_fail(u, "Not enough SP.")
		return
	u.sp -= cost
	u.skill_delay = per_level(s, "after_cast_delay", level)
	u.attack_cooldown = maxf(u.attack_cooldown, u.skill_delay)
	events.append({"type": "cast_end", "id": u.id, "skill": code, "ok": true})
	events.append({"type": "skill", "id": u.id, "skill": code, "text": String(s.name)})
	_release_spell(u, t, s, code, level)


## Releases a finished spell: `hits` bolts on the target (and its splash area).
func _release_spell(u: SimUnit, t: SimUnit, s: Dictionary, code: String, level: int) -> void:
	if bool(s.get("physical", false)):
		_physical_strike(u, t, s, code, level)
		return
	if s.has("effect"):
		_support_effect(u, t, s, code, level)
		return
	var element := String(s.get("element", "neutral"))
	var hits := int(per_level(s, "hits", level, 1.0))
	var pct := int(per_level(s, "damage_pct", level, 100.0))
	var area := int(s.get("splash", 0))
	events.append({"type": "magic", "id": u.id, "skill": code, "element": element, "target": t.id,
		"hits": hits, "cell": t.walker.cell, "splash": area, "fx": String(s.get("fx", "bolts"))})
	pct = pct * (100 + _element_bonus(u, element)) / 100
	var victims: Array[SimUnit] = [t]
	if area > 0:
		for id in units:
			var o: SimUnit = units[id]
			if o != t and not o.is_player() and not o.dead and _chebyshev(o.walker.cell, t.walker.cell) <= area:
				victims.append(o)
	for v in victims:
		var bonus := 100
		if String(v.data.get("race", "")) == "undead" or v.element == "undead":
			bonus += int(s.get("undead_bonus_per_level", 0)) * level
		var total := 0
		for h in hits:
			total += ElementRulesPreRenewal.magic_hit(u.matk(), pct * bonus / 100, v.combat_profile(), element, rng)
		if victims.size() > 1 and bool(s.get("split_damage", false)):
			total = maxi(1, total / victims.size())
		# Element already applied per hit (pass "" so it is not applied twice).
		_apply_hit(u, v, {"damage": total, "crit": false, "miss": false, "hits": hits, "element": element}, "")
		if total > 0:
			_inflict(u, v, s, level)


# --- Class skills (data-driven from skills.json) --------------------------------

## Skills that go through the cast bar (spells, wind-ups like Hell Impact).
static func _uses_cast(s: Dictionary) -> bool:
	return s.has("magic") or s.has("cast_time")


## "" when the equipped weapon satisfies the skill, else the reason.
func _weapon_unmet(u: SimUnit, s: Dictionary) -> String:
	var need: Array = s.get("weapon", [])
	if not need.is_empty() and not need.has(u.weapon_type):
		var kinds := "an axe" if need.has("axe") else ("a sword" if need.has("sword") else "a " + String(need[0]))
		return "%s needs %s." % [String(s.get("name", "This skill")), kinds]
	if bool(s.get("needs_weapon", false)) and u.weapon_type == "fist" and String(s.get("target", "")) == "self":
		return "%s needs a weapon." % String(s.get("name", "This skill"))
	return ""


## Spends the SP and starts the after-cast delay. False (with a message) if short of SP.
func _pay(u: SimUnit, s: Dictionary, level: int) -> bool:
	var cost := _skill_cost(s, level)
	if u.sp < cost:
		return _skill_fail(u, "Not enough SP.")
	u.sp -= cost
	u.skill_delay = per_level(s, "after_cast_delay", level)
	return true


## Physical skill on `t`: hits rolled one by one, optional splash / pierce,
## element override, life steal and status chance.
func _physical_strike(u: SimUnit, t: SimUnit, s: Dictionary, code: String, level: int, element_override := "") -> void:
	var prof := _skill_profile(u, s, level)
	var element := String(s.get("element", ""))
	if element == "":
		element = element_override if element_override != "" else u.weapon_element()
	var victims: Array[SimUnit] = [t]
	var splash := int(per_level(s, "splash", level, 0.0))
	if splash > 0:
		victims = _monsters_near(t.walker.cell, splash)
	elif bool(s.get("pierce", false)):
		victims = _monsters_on_line(u.walker.cell, t.walker.cell, int(s.get("range", 7)))
		if not victims.has(t):
			victims.push_front(t)
	events.append({"type": "skill_fx", "id": u.id, "skill": code, "fx": String(s.get("fx", "slash")), "element": element,
		"cell": t.walker.cell, "from_cell": u.walker.cell, "area": splash, "hits": int(per_level(s, "hits", level, 1.0))})
	_strike_all(u, victims, prof, s, level, element)


## Self-centred area skills (Magnum Break style, Genocide, Chaos).
func _area_skill(u: SimUnit, code: String, s: Dictionary, level: int) -> void:
	var area := int(per_level(s, "area", level, 2.0))
	var element := String(s.get("element", u.weapon_element()))
	events.append({"type": "skill", "id": u.id, "skill": code, "text": String(s.name)})
	events.append({"type": "skill_hit", "id": u.id, "skill": code, "cell": u.walker.cell})
	events.append({"type": "skill_fx", "id": u.id, "skill": code, "fx": String(s.get("fx", "burst")), "element": element,
		"cell": u.walker.cell, "from_cell": u.walker.cell, "area": area, "hits": 1})
	_strike_all(u, _monsters_near(u.walker.cell, area), _skill_profile(u, s, level), s, level, element)


func _strike_all(u: SimUnit, victims: Array[SimUnit], prof: Dictionary, s: Dictionary, level: int, element: String) -> void:
	var hits := int(per_level(s, "hits", level, 1.0))
	var dealt := 0
	for v in victims:
		if v.dead:
			continue
		var total := 0
		var landed := 0
		var any_crit := false
		for h in hits:
			var r := CombatRulesPreRenewal.resolve_attack(prof, v.combat_profile(), rng)
			if not r.miss:
				landed += 1
				total += ElementRulesPreRenewal.apply(r.damage, element, v.defence_element()[0], v.defence_element()[1])
				any_crit = any_crit or r.crit
		var before := v.hp
		_apply_hit(u, v, {"damage": total, "crit": any_crit, "miss": landed == 0, "hits": hits, "element": element}, "")
		var applied := before - v.hp
		dealt += maxi(0, applied)
		if applied > 0:
			_inflict(u, v, s, level)
	var steal := int(per_level(s, "lifesteal_pct", level, 0.0))
	if steal > 0 and dealt > 0 and not u.dead:
		var heal := mini(u.max_hp - u.hp, maxi(1, dealt * steal / 100))
		if heal > 0:
			u.hp += heal
			events.append({"type": "heal", "id": u.id, "amount": heal})


func _monsters_near(c: Vector2i, radius: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for id in units:
		var m: SimUnit = units[id]
		if not m.is_player() and not m.dead and _chebyshev(c, m.walker.cell) <= radius:
			out.append(m)
	return out


## Monsters on the cells of a straight line from `a` toward `b`, up to `length` cells.
func _monsters_on_line(a: Vector2i, b: Vector2i, length: int) -> Array[SimUnit]:
	var cells := {}
	var d := Vector2(b - a)
	var n := maxi(1, maxi(absi(b.x - a.x), absi(b.y - a.y)))
	var step := d / n
	for i in range(1, length + 1):
		cells[Vector2i((Vector2(a) + step * i).round())] = true
	var out: Array[SimUnit] = []
	for id in units:
		var m: SimUnit = units[id]
		if not m.is_player() and not m.dead and cells.has(m.walker.cell):
			out.append(m)
	return out


## Rolls a skill's status effect on a victim (after resistance).
func _inflict(u: SimUnit, v: SimUnit, s: Dictionary, level: int) -> void:
	var inf: Dictionary = s.get("inflict", {})
	if inf.is_empty() or v.dead:
		return
	var st := String(inf.status)
	var base := int(per_level(inf, "chance", level, 0.0))
	var prof := v.combat_profile()
	if rng.randi_range(0, 99) < StatusRules.effective_chance(st, base, prof):
		apply_status(v, st, StatusRules.effective_duration(st, prof), {"by": u.id})


## Adds or refreshes a status. Incapacitating ones stop walking and casting.
func apply_status(t: SimUnit, st: String, duration_ms: float, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry.left = duration_ms
	var fresh := not t.statuses.has(st)
	t.statuses[st] = entry
	if bool(StatusRules.DEFS.get(st, {}).get("blocks_action", false)):
		t.walker.stop()
		_cancel_cast(t)
		if not t.is_player():
			t.attack_cooldown = maxf(t.attack_cooldown, 200.0)
	if t.is_player():
		_recalc_player(t)
	if fresh:
		events.append({"type": "status", "id": t.id, "status": st, "on": true})


func _clear_status(t: SimUnit, st: String) -> void:
	if not t.statuses.has(st):
		return
	t.statuses.erase(st)
	if t.is_player():
		_recalc_player(t)
	events.append({"type": "status", "id": t.id, "status": st, "on": false})


func _clear_weapon_buffs(u: SimUnit) -> void:
	for st in ["dark_weapon", "mistletoe"]:
		_clear_status(u, st)


## Status timers and the HP drains of Dark Breath / Shadow Quicken.
func _tick_statuses(u: SimUnit, ms: float) -> void:
	if u.statuses.is_empty():
		return
	for st in u.statuses.keys():
		var e: Dictionary = u.statuses[st]
		e.left = float(e.left) - ms
		if int(e.get("drain_permille", 0)) > 0:
			e.drain_t = float(e.get("drain_t", 0.0)) + ms
			while float(e.drain_t) >= StatusRules.DRAIN_INTERVAL_MS and u.statuses.has(st):
				e.drain_t = float(e.drain_t) - StatusRules.DRAIN_INTERVAL_MS
				var amount := StatusRules.drain_amount(u.max_hp, int(e.drain_permille))
				if u.hp - amount <= u.max_hp * StatusRules.DRAIN_FLOOR_PCT / 100:
					_clear_status(u, st)   # critically low: the buff ends instead of draining further
					_skill_fail(u, "%s fades: your HP is too low." % StatusRules.display_name(st))
				else:
					u.hp -= amount
					events.append({"type": "regen", "id": u.id})
		if u.statuses.has(st) and float(e.left) <= 0.0:
			_clear_status(u, st)


## Self buffs (Dark Breath, Shadow Quicken, Dark Weapon, Auto Counter, Rain Dance...).
func _self_skill(u: SimUnit, code: String, s: Dictionary, level: int) -> void:
	var st := String(s.get("status", ""))
	if st == "":
		return
	apply_status(u, st, per_level(s, "duration", level, 60000.0), _status_data(s, level))
	if st == "auto_counter":
		u.target_id = 0
		u.walker.stop()
	events.append({"type": "skill", "id": u.id, "skill": code, "text": String(s.name)})
	events.append({"type": "skill_fx", "id": u.id, "skill": code, "fx": String(s.get("fx", "aura")),
		"element": String(s.get("weapon_element", s.get("element", "shadow" if code.begins_with("DK_") else "holy"))),
		"cell": u.walker.cell, "from_cell": u.walker.cell, "area": 0, "hits": 1})


## Per-level numbers a status needs, copied from the skill at cast time.
func _status_data(s: Dictionary, level: int) -> Dictionary:
	var d := {"level": level, "skill": String(s.get("name", ""))}
	for k in ["atk_pct", "aspd_pct", "matk_pct", "def_bonus"]:
		if s.has(k):
			d[k] = int(per_level(s, k, level, 0.0))
	if s.has("drain_permille"):
		d.drain_permille = int(s.drain_permille)
	if s.has("element_bonus"):
		var eb := {}
		for el in s.element_bonus:
			eb[el] = int(per_level(s.element_bonus, el, level, 0.0))
		d.element_bonus = eb
	return d


## Extra % for the caster's own magic of `element` (Rain Dance, Southeast Wind).
func _element_bonus(u: SimUnit, element: String) -> int:
	var b := 0
	for st in u.statuses:
		b += int((u.statuses[st].get("element_bonus", {}) as Dictionary).get(element, 0))
	return b


## Ally-targeted skills: heal, SP, buffs, resurrection. Validates the target.
func _use_support(u: SimUnit, code: String, s: Dictionary, level: int, target_id: int) -> bool:
	var t: SimUnit = units.get(target_id) if target_id != 0 else u
	if t == null or not t.is_player():
		t = u
	var wants_dead := String(s.target) == "dead_ally"
	if wants_dead and not t.dead:
		return _skill_fail(u, "%s needs a fallen player as its target." % String(s.name))
	if not wants_dead and t.dead:
		return _skill_fail(u, "That player has fallen.")
	if bool(s.get("no_self", false)) and t == u:
		return _skill_fail(u, "%s cannot target yourself." % String(s.name))
	if _chebyshev(u.walker.cell, t.walker.cell) > int(s.get("range", 9)):
		return _skill_fail(u, "Out of range.")
	if bool(s.get("needs_weapon", false)) and t.weapon_type == "fist":
		return _skill_fail(u, "The target has no weapon to enchant.")
	if s.has("cast_time"):
		u.queued_skill = code
		_begin_cast(u, t)
		return true
	if not _pay(u, s, level):
		return false
	events.append({"type": "skill", "id": u.id, "skill": code, "text": String(s.name)})
	_support_effect(u, t, s, code, level)
	return true


func _support_effect(u: SimUnit, t: SimUnit, s: Dictionary, code: String, level: int) -> void:
	events.append({"type": "skill_fx", "id": u.id, "skill": code, "fx": "support", "element": "holy",
		"cell": t.walker.cell, "from_cell": u.walker.cell, "area": 0, "hits": 1, "target": t.id})
	match String(s.effect):
		"heal":
			var amount := heal_amount(u, level)
			var before := t.hp
			t.hp = mini(t.max_hp, t.hp + amount)
			events.append({"type": "heal", "id": t.id, "amount": t.hp - before})
		"sp":
			var amount := 8 * level + int(u.stats.int) / 2
			var before := t.sp
			t.sp = mini(t.max_sp, t.sp + amount)
			events.append({"type": "sp_heal", "id": t.id, "amount": t.sp - before})
		"buff":
			apply_status(t, String(s.status), per_level(s, "duration", level, 60000.0), _status_data(s, level))
		"resurrect":
			if t.dead:
				t.dead = false
				t.sitting = false
				t.trickdead = false
				t.respawn_in = 0.0
				t.hp = maxi(1, t.max_hp * int(per_level(s, "revive_pct", level, 10.0)) / 100)
				events.append({"type": "resurrect", "id": t.id, "by": u.id})
				events.append({"type": "revive", "id": t.id})


## Classic Heal formula: floor((BaseLv + INT) / 8) * (4 + 8 * SkillLv). High confidence.
static func heal_amount_for(base_level: int, int_: int, level: int) -> int:
	return (base_level + int_) / 8 * (4 + 8 * level)


func heal_amount(u: SimUnit, level: int) -> int:
	return heal_amount_for(u.level, int(u.stats.int), level)


# --- NPC script hooks (rAthena-format scripts, see scripts/npc/) ----------------
# Scripts decide eligibility themselves; these apply the result with the
# simulation's own rules and events, so a host / server stays authoritative.

var _forcing_job := false


func script_heal(u: SimUnit, hp: int, sp: int) -> void:
	if u.dead:
		return
	var h := mini(u.max_hp - u.hp, maxi(0, hp))
	var p := mini(u.max_sp - u.sp, maxi(0, sp))
	u.hp += h
	u.sp += p
	if h > 0:
		events.append({"type": "heal", "id": u.id, "amount": h})
	if p > 0:
		events.append({"type": "sp_heal", "id": u.id, "amount": p})
	events.append({"type": "regen", "id": u.id})


## jobchange from a script (requirements already checked by the script).
func script_job_change(u: SimUnit, job: String) -> bool:
	_forcing_job = true
	var ok := command_job_change(u.id, job)
	_forcing_job = false
	return ok


## skill "CODE", level: grants (or raises) a skill without spending points.
func script_grant_skill(u: SimUnit, code: String, level: int) -> bool:
	if not skill_db.has(code):
		return false
	u.skills[code] = maxi(int(u.skills.get(code, 0)), clampi(level, 1, int(skill_db[code].max_level)))
	_recalc_player(u)
	events.append({"type": "skills", "id": u.id})
	return true


## resetskill: refunds every non-quest skill level as skill points.
func script_reset_skills(u: SimUnit) -> void:
	var refund := 0
	for code in u.skills:
		if not skill_db.get(code, {}).get("quest", false):
			refund += int(u.skills[code])
			u.skills[code] = 0
	u.skill_points += refund
	u.statuses.clear()
	_recalc_player(u)
	events.append({"type": "skills", "id": u.id})


## resetstatus: every stat back to 1, raise costs refunded as status points.
func script_reset_stats(u: SimUnit) -> void:
	u.status_points += _stat_cost(u.stats)
	for k in STAT_NAMES:
		u.stats[k] = 1
	_recalc_player(u)
	u.hp = mini(u.hp, u.max_hp)
	u.sp = mini(u.sp, u.max_sp)
	events.append({"type": "stats", "id": u.id})


func script_get_item(u: SimUnit, item_id: int, amount: int) -> bool:
	if not item_db.has(str(item_id)) or amount <= 0:
		return false
	var ok := u.inventory.add(item_id, amount, item_db, u.max_weight() - u.equipment_weight(item_db))
	events.append({"type": "inventory", "id": u.id})
	return ok


func script_del_item(u: SimUnit, item_id: int, amount: int) -> bool:
	if u.inventory.count(item_id) < amount:
		return false
	var left := amount
	for i in range(u.inventory.entries.size() - 1, -1, -1):
		if left <= 0:
			break
		if int(u.inventory.entries[i].id) == item_id:
			left -= u.inventory.remove_at(i, left)
	events.append({"type": "inventory", "id": u.id})
	return true


## Adds a Kafra storage NPC to this map (maps.json "kafra" entries and tests).
func add_kafra_npc(cell: Vector2i, display := "Kafra") -> int:
	var nid := _next_npc
	_next_npc += 1
	npcs[nid] = {"id": nid, "name": display, "sprite": "4_f_kafra1", "kind": "kafra",
		"cell": cell, "direction": 0, "shop": "", "greeting": "Welcome to the Kafra Corporation!"}
	events.append({"type": "npc_spawn", "npc": nid})
	return nid


## Removes a unit from this map (a player left, or moved to another map on
## a co-op host). Emits {type: "despawn", id}.
func remove_unit(unit_id: int) -> void:
	var u: SimUnit = units.get(unit_id)
	if u == null:
		return
	_cancel_cast(u)
	units.erase(unit_id)
	for id in units:
		var other: SimUnit = units[id]
		if other.target_id == unit_id:
			other.target_id = 0
		if other.cast_target == unit_id:
			_cancel_cast(other)
	events.append({"type": "despawn", "id": unit_id})


## Adds a script NPC to this map (spawned by the field from RaWorld).
func add_script_npc(def: Dictionary, sprite: String) -> int:
	var nid := _next_npc
	_next_npc += 1
	npcs[nid] = {"id": nid, "name": String(def.display), "sprite": sprite, "kind": "script",
		"cell": Vector2i(int(def.x), int(def.y)), "direction": int(def.dir), "shop": "", "greeting": "",
		"script": String(def.name)}
	events.append({"type": "npc_spawn", "npc": nid})
	return nid


## Stands a fallen player up where they lie (@revive). Used by QoL commands.
func command_revive(unit_id: int, pct := 50) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or not u.dead or not u.is_player():
		return false
	u.dead = false
	u.sitting = false
	u.trickdead = false
	u.respawn_in = 0.0
	u.hp = clampi(u.max_hp * pct / 100, 1, u.max_hp)
	events.append({"type": "revive", "id": u.id})
	return true


## Sit or stand (Insert). Needs Basic Skill level 3.
func command_sit(unit_id: int) -> bool:
	var u: SimUnit = units.get(unit_id)
	if u == null or u.dead or u.trickdead:
		return false
	if int(u.skills.get("NV_BASIC", 0)) < 3:
		return _skill_fail(u, "Sitting requires Basic Skill level 3.")
	u.sitting = not u.sitting
	if u.sitting:
		u.walker.stop()
		u.target_id = 0
	events.append({"type": "posture", "id": u.id})
	return true


func _skill_fail(u: SimUnit, text: String) -> bool:
	events.append({"type": "skill_fail", "id": u.id, "text": text})
	return false


func _grant_default_skills(u: SimUnit, reset := true) -> void:
	if reset:
		u.skills = {}
	for code in available_skills(u):
		var s: Dictionary = skill_db[code]
		if s.get("quest", false) and int(u.skills.get(code, 0)) == 0:
			u.skills[code] = 1   # quest skills granted until their quests exist
		elif not u.skills.has(code):
			u.skills[code] = 0


## Skill codes a unit can have: Novice skills plus every job in its ancestry.
## The chain is built from the current class upward, so transcendent and third
## jobs keep the first- and second-job trees that led to them.
func available_skills(u: SimUnit) -> Array:
	var out: Array = []
	var chain: Array = []
	var job := u.job
	var guard := 0
	while job != "" and not chain.has(job) and guard < 8:
		chain.push_front(job)
		job = String(job_db.get(job, {}).get("parent", ""))
		guard += 1
	if not chain.has("novice"):
		chain.push_front("novice")
	for jid in chain:
		for code in job_db.get(jid, {}).get("skills", []):
			if skill_db.has(code) and not out.has(code):
				out.append(code)
	return out


## Returns "" if the skill's prerequisites are met, else a reason.
func skill_requirements_unmet(u: SimUnit, code: String) -> String:
	var req: Dictionary = skill_db.get(code, {}).get("requires", {})
	for r in req:
		if int(u.skills.get(r, 0)) < int(req[r]):
			return "Requires %s level %d." % [skill_db.get(r, {}).get("name", r), int(req[r])]
	return ""


func _spent_skill_points(u: SimUnit) -> int:
	var n := 0
	for code in u.skills:
		if not skill_db.get(code, {}).get("quest", false):
			n += int(u.skills[code])
	return n


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
		u.skill_delay = maxf(0.0, u.skill_delay - ms)
		_tick_statuses(u, ms)
		if u.dead:
			continue
		if u.is_player():
			_regen(u, ms)
		if u.is_bot:
			BotBrain.think(self, u, ms)
		if u.is_incapacitated():
			u.walker.advance(ms)
			continue
		if u.is_casting():
			_advance_cast(u, ms)
		elif u.talk_target != 0:
			_pursue_talk(u)
		elif u.pickup_target != 0:
			_pursue_pickup(u)
		elif u.target_id != 0:
			_pursue(u)
		elif not u.is_player():
			_wander(u, ms)
		u.walker.advance(ms)
		# Portals move the local player; CPU adventurers stay on their map.
		if u.is_player() and not u.is_bot and not u.walker.is_moving() and not u.warping:
			var w := warp_at(u.walker.cell)
			if not w.is_empty():
				u.warping = true
				events.append({"type": "warp", "id": u.id, "to_map": w.to_map, "to_cell": w.to_cell})
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
	if t == null or t.dead or t.trickdead:
		u.target_id = 0
		return
	var dist := _chebyshev(u.walker.cell, t.walker.cell)
	if not u.is_player() and dist > CHASE_GIVE_UP_CELLS:
		u.target_id = 0
		return
	var reach := u.attack_range
	var spell: Dictionary = skill_db.get(u.queued_skill, {}) if u.queued_skill != "" else {}
	if spell.has("range"):
		reach = int(spell.range)
	elif spell.has("magic"):
		reach = 9
	if not u.is_player() and u.has_status("confusion"):
		u.idle_timer = 0.0
		_wander(u, 0.0)   # confused monsters stagger about instead of chasing
		return
	if dist <= reach and not u.walker.is_moving():
		u.walker.direction = GridWalker.direction_to(u.walker.cell, t.walker.cell)
		if _uses_cast(spell):
			_begin_cast(u, t)
		elif u.attack_cooldown <= 0.0:
			_attack(u, t)
		return
	if dist <= reach and u.walker.is_moving():
		# Stop at the next cell boundary, then attack.
		var keep: Array[Vector2i] = [u.walker.path[0]]
		u.walker.path = keep
		return
	# Re-path toward the target when idle or when it has moved away from our goal.
	var goal: Vector2i = u.walker.path[-1] if u.walker.is_moving() else u.walker.cell
	if not u.walker.is_moving() or _chebyshev(goal, t.walker.cell) > reach:
		var path := pathfinder.find_path(u.walker.planning_origin(), t.walker.cell)
		if path.size() > 1:
			path.remove_at(path.size() - 1)  # stand next to the target, not on it
			u.walker.walk(path)
		elif path.size() == 1 and _chebyshev(u.walker.planning_origin(), t.walker.cell) > reach:
			u.walker.walk(path)


func _regen(u: SimUnit, ms: float) -> void:
	if u.trickdead or RegenRulesPreRenewal.blocked_by_weight(u.inventory.weight(item_db) + u.equipment_weight(item_db), u.max_weight()):
		u.hp_regen_t = 0.0
		u.sp_regen_t = 0.0
		return
	var changed := false
	u.hp_regen_t += ms
	if u.hp_regen_t >= RegenRulesPreRenewal.interval(RegenRulesPreRenewal.HP_INTERVAL_MS, u.sitting):
		u.hp_regen_t = 0.0
		if u.hp < u.max_hp:
			u.hp = mini(u.max_hp, u.hp + RegenRulesPreRenewal.hp_amount(u.max_hp, int(u.stats.vit)))
			changed = true
	u.sp_regen_t += ms
	if u.sp_regen_t >= RegenRulesPreRenewal.interval(RegenRulesPreRenewal.SP_INTERVAL_MS, u.sitting):
		u.sp_regen_t = 0.0
		if u.sp < u.max_sp:
			var ah := int(u.skills.get("SH_AUTOHEAL", 0))
			var sp_gain := RegenRulesPreRenewal.sp_amount(u.max_sp, int(u.stats.int)) * (100 + 10 * ah) / 100 + ah
			u.sp = mini(u.max_sp, u.sp + sp_gain)
			changed = true
	var rec := int(u.skills.get("SM_RECOVERY", 0))
	var srec := int(u.skills.get("MG_SRECOVERY", 0))
	if srec > 0 and rec == 0:
		if u.walker.is_moving():
			u.recovery_t = 0.0
		else:
			u.recovery_t += ms
			if u.recovery_t >= 10000.0:
				u.recovery_t = 0.0
				if u.sp < u.max_sp:
					u.sp = mini(u.max_sp, u.sp + 3 * srec + int(u.max_sp * 0.002 * srec))
					changed = true
	if rec > 0:
		if u.walker.is_moving():
			u.recovery_t = 0.0
		else:
			u.recovery_t += ms
			if u.recovery_t >= 10000.0:
				u.recovery_t = 0.0
				if u.hp < u.max_hp:
					u.hp = mini(u.max_hp, u.hp + 5 * rec + int(u.max_hp * 0.002 * rec))
					changed = true
	if changed:
		events.append({"type": "regen", "id": u.id})


func _pursue_talk(u: SimUnit) -> void:
	var npc: Dictionary = npcs.get(u.talk_target, {})
	if npc.is_empty():
		u.talk_target = 0
		return
	if _chebyshev(u.walker.cell, npc.cell) <= NPC_TALK_RANGE and not u.walker.is_moving():
		u.open_shop = u.talk_target if String(npc.get("kind", "shop")) == "shop" else 0
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
	var owner: SimUnit = units.get(owner_id)
	var drops: Array = t.data.get("drops", [])
	var placed := 0
	for d in drops:
		# d[1] is a chance in 10000; drop_rate is a percentage of it.
		var chance := mini(10000, int(round(float(d[1]) * rules.drop_rate / 100.0)))
		if chance <= 0 or rng.randi_range(0, 9999) >= chance:
			continue
		if not item_db.has(str(int(d[0]))):
			continue
		if rules.autoloot and owner != null and owner.is_player():
			if owner.inventory.add(int(d[0]), 1, item_db, owner.max_weight() - owner.equipment_weight(item_db)):
				events.append({"type": "autoloot", "id": owner.id, "item": int(d[0]), "amount": 1})
				events.append({"type": "inventory", "id": owner.id})
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


## Bow attacks consume the first ammo stack in the inventory. Enchantments keep
## priority; otherwise the consumed arrow supplies the attack element.
func _needs_ammo(u: SimUnit, sk: Dictionary = {}) -> bool:
	if not u.is_player() or u.weapon_type != "bow":
		return false
	return sk.is_empty() or (sk.get("weapon", []) as Array).has("bow")


func _is_ammo(item_id: int) -> bool:
	return String(item_db.get(str(item_id), {}).get("type", "")) == "ammo"


func _has_ammo(u: SimUnit) -> bool:
	for e in u.inventory.entries:
		if _is_ammo(int(e.id)):
			return true
	return false


func _consume_ammo(u: SimUnit) -> Dictionary:
	for i in range(u.inventory.entries.size()):
		var item_id := int(u.inventory.entries[i].id)
		if _is_ammo(item_id):
			u.inventory.remove_at(i, 1)
			return item_db.get(str(item_id), {})
	return {}


func _attack_element(u: SimUnit, ammo: Dictionary) -> String:
	var enchanted := u.weapon_element()
	if enchanted != "neutral":
		return enchanted
	return String(ammo.get("element", "neutral"))


func _attack(u: SimUnit, t: SimUnit) -> void:
	u.attack_cooldown = u.attack_interval
	var prof := u.combat_profile()
	if u.queued_skill != "":
		var code := u.queued_skill
		u.queued_skill = ""
		var sk: Dictionary = skill_db.get(code, {})
		var level := int(u.skills.get(code, 0))
		if level > 0 and _weapon_unmet(u, sk) == "":
			if _needs_ammo(u, sk) and not _has_ammo(u):
				_skill_fail(u, "You have no arrows.")
				return
			if _pay(u, sk, level):
				var shot_ammo: Dictionary = {}
				if _needs_ammo(u, sk):
					shot_ammo = _consume_ammo(u)
				var shot_element := _attack_element(u, shot_ammo) if not shot_ammo.is_empty() else ""
				if not shot_ammo.is_empty():
					events.append({"type": "projectile", "id": u.id, "target": t.id, "element": shot_element,
						"hits": maxi(1, int(per_level(sk, "hits", level, 1.0)))})
				events.append({"type": "skill", "id": u.id, "skill": code, "text": String(sk.name)})
				events.append({"type": "skill_hit", "id": u.id, "skill": code, "cell": t.walker.cell})
				events.append({"type": "attack", "id": u.id, "target": t.id})
				_physical_strike(u, t, sk, code, level, shot_element)
				return
		elif level > 0 and _weapon_unmet(u, sk) != "":
			_skill_fail(u, _weapon_unmet(u, sk))
	# Auto Counter: a braced player blocks a monster's melee swing and counters.
	if not u.is_player() and t.is_player() and t.has_status("auto_counter") and u.attack_range <= 2:
		_clear_status(t, "auto_counter")
		events.append({"type": "counter", "id": t.id, "target": u.id})
		events.append({"type": "attack", "id": t.id, "target": u.id})
		var cp := t.combat_profile()
		cp.force_crit = true
		_apply_hit(t, u, CombatRulesPreRenewal.resolve_attack(cp, u.combat_profile(), rng), t.weapon_element())
		return
	var ammo: Dictionary = {}
	if _needs_ammo(u):
		ammo = _consume_ammo(u)
		if ammo.is_empty():
			_skill_fail(u, "You have no arrows.")
			return
	var element := _attack_element(u, ammo) if u.is_player() else "neutral"
	if not ammo.is_empty():
		events.append({"type": "projectile", "id": u.id, "target": t.id, "element": element, "hits": 1})
	events.append({"type": "attack", "id": u.id, "target": t.id})
	_apply_hit(u, t, CombatRulesPreRenewal.resolve_attack(prof, t.combat_profile(), rng), element)


func _apply_hit(u: SimUnit, t: SimUnit, r: Dictionary, element := "neutral") -> void:
	if not r.miss and element != "":
		r.damage = ElementRulesPreRenewal.apply(r.damage, element, t.element, t.element_level)
	events.append({"type": "damage", "src": u.id, "dst": t.id, "amount": r.damage, "crit": r.crit, "miss": r.miss,
		"hits": int(r.get("hits", 1)), "element": String(r.get("element", element))})
	if r.miss:
		_provoke(t, u)
		return
	t.hp = maxi(0, t.hp - r.damage)
	if r.damage > 0 and t.has_status("sleep"):
		_clear_status(t, "sleep")
	if r.damage > 0 and t.is_casting() and not bool(skill_db.get(t.cast_skill, {}).get("uninterruptible", false)):
		_cancel_cast(t)
	t.damaged_by[u.id] = int(t.damaged_by.get(u.id, 0)) + r.damage
	if t.hp <= 0:
		_kill(t, u)
	else:
		_provoke(t, u)


## Passive monsters fight back when attacked.
func _provoke(victim: SimUnit, attacker: SimUnit) -> void:
	if not victim.is_player() and victim.target_id == 0 and not attacker.trickdead:
		victim.target_id = attacker.id


func _kill(t: SimUnit, killer: SimUnit) -> void:
	for st in t.statuses.keys():
		_clear_status(t, st)
	_cancel_cast(t)
	t.dead = true
	t.target_id = 0
	t.walker.stop()
	# CPU adventurers lie where they fell until a player revives them, then
	# return to their save point on their own after a while.
	if t.is_bot:
		t.respawn_in = BotBrain.BOT_REVIVE_MS
	else:
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
	u.sitting = false
	u.trickdead = false
	u.hp = u.max_hp
	if u.is_player() and u.save_map != "" and u.save_map != map_name:
		# Fallen players return to their save point (Prontera, the hub, by default).
		events.append({"type": "revive", "id": u.id, "to_map": u.save_map, "to_cell": u.save_cell})
		return
	if u.is_player():
		var home := u.save_cell if u.save_map == map_name else (respawn_cell if respawn_cell.x >= 0 else u.spawn_cell)
		u.walker = GridWalker.new(pathfinder.nearest_walkable(home, 20))
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

## Base-level cap for this character's class. Third jobs reach 150; every
## earlier class (Novice through transcendent) stops at 99. The server rule
## can lower the cap, but never raise it past the class limit.
func base_level_cap(u: SimUnit) -> int:
	var class_cap := int(job_db.get(u.job, {}).get("max_base_level", 99))
	return clampi(mini(rules.max_level, class_cap), 1, 999)


func _gain_exp(p: SimUnit, base: int, job: int) -> void:
	base = roundi(base * rules.exp_rate / 100.0)
	job = roundi(job * rules.job_exp_rate / 100.0)
	events.append({"type": "exp", "id": p.id, "base": base, "job": job})
	p.base_exp += base
	p.job_exp += job
	var base_table: Array = exp_tables.get("base_normal", [])
	var cap := base_level_cap(p)
	while p.level < cap and p.level - 1 < base_table.size() and p.base_exp >= int(base_table[p.level - 1]):
		p.base_exp -= int(base_table[p.level - 1])
		p.status_points += StatRulesPreRenewal.status_points_gained(p.level)
		p.level += 1
		_recalc_player(p)
		p.hp = p.max_hp
		p.sp = p.max_sp
		events.append({"type": "levelup", "id": p.id, "level": p.level, "kind": "base"})
	var job_table: Array = exp_tables.get(String(job_db.get(p.job, {}).get("job_table", "job_novice")), [])
	while p.job_level - 1 < job_table.size() and p.job_exp >= int(job_table[p.job_level - 1]):
		p.job_exp -= int(job_table[p.job_level - 1])
		p.job_level += 1
		p.skill_points += 1
		events.append({"type": "levelup", "id": p.id, "level": p.job_level, "kind": "job"})


## EXP needed for the next base / job level, or 0 when the table ends.
func next_base_exp(p: SimUnit) -> int:
	var t: Array = exp_tables.get("base_normal", [])
	return int(t[p.level - 1]) if p.level < base_level_cap(p) and p.level - 1 < t.size() else 0


func next_job_exp(p: SimUnit) -> int:
	var t: Array = exp_tables.get(String(job_db.get(p.job, {}).get("job_table", "job_novice")), [])
	return int(t[p.job_level - 1]) if p.job_level - 1 < t.size() else 0


func _recalc_player(u: SimUnit) -> void:
	var s := u.stats
	var j: Dictionary = job_db.get(u.job, job_db.get("novice", {}))
	u.max_hp = CombatRulesPreRenewal.job_max_hp(u.level, int(s.vit), float(j.get("hp_a", 0.0)), int(j.get("hp_b", 5)))
	u.max_sp = CombatRulesPreRenewal.job_max_sp(u.level, int(s.int), int(j.get("sp_factor", 1)))
	u.weight_bonus = int(j.get("weight_bonus", 0))
	u.batk = StatRulesPreRenewal.status_atk(int(s.str), int(s.dex), int(s.luk))
	var weapon: Dictionary = item_db.get(str(u.equipment.get("weapon", 0)), {})
	u.weapon_type = String(weapon.get("weapon_type", "fist"))
	# Bows attack from range; instruments and whips have a short reach.
	u.attack_range = int(weapon.get("range", 1))
	var wr := CombatRulesPreRenewal.weapon_atk_range(int(weapon.get("atk", 0)), int(weapon.get("weapon_level", 1)), int(s.dex))
	u.watk_min = wr.x
	u.watk_max = wr.y
	# Weapon masteries (e.g. Sword Mastery) add flat ATK after DEF.
	u.mastery_atk = 0
	for code in u.skills:
		var sk: Dictionary = skill_db.get(code, {})
		if sk.has("mastery_atk") and (sk.get("mastery_weapons", []) as Array).has(u.weapon_type):
			u.mastery_atk += int(sk.mastery_atk) * int(u.skills[code])
	u.atk_min = u.batk + wr.x + u.mastery_atk
	u.atk_max = u.batk + wr.y + u.mastery_atk
	var def_total := 0
	for slot in u.equipment:
		def_total += int(item_db.get(str(u.equipment[slot]), {}).get("def", 0))
	# Every active buff that carries a DEF bonus contributes (Spiritual
	# Protection, Rune Shield, Assumptio, ...).
	u.def_bonus = 0
	for st in u.statuses:
		u.def_bonus += int(u.statuses[st].get("def_bonus", 0))
	u.hard_def = def_total + u.def_bonus
	u.mdef = u.def_bonus
	u.crit_bonus = int(u.skills.get("DK_CRITUP", 0)) * int(skill_db.get("DK_CRITUP", {}).get("crit_permille_per_level", 10))
	u.matk_item_pct = int(weapon.get("matk_pct", 0))
	var btba_table: Dictionary = j.get("btba", NOVICE_BTBA)
	var btba: float = float(btba_table.get(u.weapon_type, 0.6))
	var a := CombatRulesPreRenewal.aspd(btba, int(s.agi), int(s.dex))
	u.attack_interval = CombatRulesPreRenewal.attack_interval_ms(a)
	var quicken := int(u.status_value("shadow_quicken", "aspd_pct", 0))
	if quicken > 0:
		u.attack_interval = maxf(StatusRules.ASPD_CAP_INTERVAL_MS, u.attack_interval * (100 - quicken) / 100.0)
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
