class_name BotBrain
extends RefCounted
## CPU adventurers: player units driven by a small AI so maps feel populated.
## They are ordinary players to the simulation (same stats, combat, EXP, loot
## rules and death), and they act only through the same commands a human
## client sends (command_move / attack / use_skill / pickup / sit), so the
## rules core stays authoritative.
##
## Roles:
##   melee    Swordman / Dark Knight / Merchant / Thief / Novice: hunt, loot
##   caster   Mage: picks the bolt element that hurts the target most
##   support  Shaman: heals and buffs nearby players (humans included),
##            revives fallen allies with Spiritual Prayer, fights with Summon
## Dead bots wait to be revived (any player's Spiritual Prayer works); after
## BOT_REVIVE_MS they "return to their save point" and re-enter the map.

const THINK_MS := 450.0
const BOT_REVIVE_MS := 40000.0
const HUNT_RADIUS := 14
const SUPPORT_RANGE := 9
const MAX_BOTS := 4

const NAMES := ["Aeris", "Brannoc", "Celwyn", "Dario", "Elyra", "Fenrik", "Gwyndel", "Haldor", "Isolde", "Joren",
	"Kaelis", "Lysandra", "Marek", "Nerys", "Orrin", "Perrin", "Quilla", "Roderic", "Sable", "Talwyn", "Ulric",
	"Vespera", "Wrenna", "Xander", "Yselle", "Zarek", "Mirelle", "Tobias", "Corvin", "Aurelle", "Kestrel", "Liora",
	"Dain", "Seraphine", "Bastian", "Nyla", "Rowan", "Astrid", "Cassius", "Ember"]

## role, job, weapon item, skills {code: level-scale}, female only
const ARCHETYPES := [
	{"role": "melee", "job": "swordman", "weapon": 1116, "skills": {"SM_SWORD": 1.0, "SM_TWOHAND": 1.0, "SM_BASH": 1.0}},
	{"role": "melee", "job": "dark_knight", "weapon": 1116, "skills": {"SM_TWOHAND": 1.0, "DK_BLOODYCRASH": 1.0, "DK_CRITUP": 0.6}},
	{"role": "melee", "job": "merchant", "weapon": 1301, "skills": {}},
	{"role": "melee", "job": "thief", "weapon": 1207, "skills": {}},
	{"role": "melee", "job": "novice", "weapon": 1201, "skills": {"NV_BASIC": 1.0}},
	{"role": "caster", "job": "mage", "weapon": 1601, "skills": {"MG_FIREBOLT": 0.5, "MG_COLDBOLT": 0.5, "MG_LIGHTNINGBOLT": 0.5, "MG_SRECOVERY": 0.6}},
	{"role": "support", "job": "shaman", "weapon": 1601, "female": true,
		"skills": {"SH_COMFORT": 1.0, "SH_PROTECTION": 0.8, "SH_WRATH": 0.6, "SH_PRAYER": 0.5, "SH_SUMMON": 0.7, "SH_AUTOHEAL": 0.8}},
]

## Display colour per role, used by name tags and minimap blips.
const ROLE_COLORS := {
	"melee": Color(1.0, 0.62, 0.4),
	"caster": Color(0.72, 0.56, 1.0),
	"support": Color(0.45, 1.0, 0.66),
}


## Places `count` CPU adventurers at random walkable parts of the map, keeping
## `away_from` (usually the player) at a little distance so they do not crowd.
static func populate(sim: FieldSimulation, count: int, level: int, away_from := Vector2i(-1, -1)) -> Array:
	var out: Array = []
	var want := clampi(count, 1, MAX_BOTS)
	for i in want:
		var cell := Vector2i(-1, -1)
		for attempt in 60:
			var p := Vector2i(sim.rng.randi_range(2, maxi(3, sim.gat.width - 3)),
				sim.rng.randi_range(2, maxi(3, sim.gat.height - 3)))
			if away_from.x >= 0 and FieldSimulation._chebyshev(p, away_from) < 14:
				continue
			cell = sim.pathfinder.nearest_walkable(p, 30)
			if cell != Vector2i(-1, -1):
				break
		if cell == Vector2i(-1, -1):
			continue
		out.append(spawn(sim, cell, level))
	return out


## Level the CPU adventurers of this map should be: slightly above the local
## monsters, so they hold their own without outclassing the player's field.
static func map_level(sim: FieldSimulation) -> int:
	var total := 0
	var n := 0
	for id in sim.units:
		var u: SimUnit = sim.units[id]
		if not u.is_player() and int(u.level) > 0:
			total += int(u.level)
			n += 1
	if n == 0:
		return 30
	return clampi(roundi(float(total) / n * 1.1), 3, 90)


## Creates one bot of a random archetype near `cell`. Returns the unit.
static func spawn(sim: FieldSimulation, cell: Vector2i, level: int, archetype := -1) -> SimUnit:
	var rng := sim.rng
	var a: Dictionary = ARCHETYPES[archetype if archetype >= 0 else rng.randi_range(0, ARCHETYPES.size() - 1)]
	var lv := clampi(level, 1, 99)
	var stats := _stats_for(String(a.role), lv)
	var u := sim.add_player(_unique_name(sim), sim.pathfinder.nearest_walkable(cell, 30), stats)
	u.is_bot = true
	u.bot_role = String(a.role)
	u.male = not bool(a.get("female", false)) and rng.randf() < 0.55
	u.hair_style = rng.randi_range(1, 19)
	u.hair_color = rng.randi_range(0, 8)
	u.aura = PlayerAura.ORDER[rng.randi_range(0, PlayerAura.ORDER.size() - 2)]
	u.level = lv
	u.job_level = clampi(lv / 2 + 1, 1, 50)
	u.job = String(a.job)
	u.sprite = String(sim.job_db.get(u.job, {}).get("sprite", "초보자"))
	u.save_map = ""   # bots re-enter the current map
	u.skills = {}
	sim._grant_default_skills(u)
	u.skills["NV_BASIC"] = 9
	for code in a.skills:
		if sim.skill_db.has(code):
			var mx := int(sim.skill_db[code].max_level)
			u.skills[code] = clampi(int(ceil(mx * float(a.skills[code]) * minf(1.0, lv / 30.0))), 1, mx)
	var w := int(a.weapon)
	if sim.item_db.has(str(w)) and lv >= int(sim.item_db[str(w)].get("equip_level", 1)):
		u.equipment["weapon"] = w
	elif sim.item_db.has("1201"):
		u.equipment["weapon"] = 1201
	u.equipment["body"] = 2301
	sim._recalc_player(u)
	u.hp = u.max_hp
	u.sp = u.max_sp
	u.bot_think = rng.randf_range(0.0, THINK_MS)
	sim.events.append({"type": "bot_spawn", "id": u.id})
	return u


## Bots share the map with the player, so their names must not collide.
static func _unique_name(sim: FieldSimulation) -> String:
	var taken := {}
	for id in sim.units:
		taken[String(sim.units[id].name)] = true
	for attempt in 32:
		var candidate := String(NAMES[sim.rng.randi_range(0, NAMES.size() - 1)])
		if not taken.has(candidate):
			return candidate
	return "Adventurer %d" % (sim.units.size() + 1)


static func _stats_for(role: String, lv: int) -> Dictionary:
	var f := lv / 99.0
	match role:
		"caster":
			return {"str": 1, "agi": 5 + int(20 * f), "vit": 8 + int(30 * f), "int": 12 + int(80 * f), "dex": 12 + int(60 * f), "luk": 5}
		"support":
			return {"str": 5, "agi": 5 + int(15 * f), "vit": 12 + int(45 * f), "int": 12 + int(75 * f), "dex": 8 + int(40 * f), "luk": 5}
	return {"str": 12 + int(75 * f), "agi": 8 + int(60 * f), "vit": 10 + int(45 * f), "int": 1, "dex": 8 + int(35 * f), "luk": 5 + int(20 * f)}


## Called by FieldSimulation.tick for every bot.
static func think(sim: FieldSimulation, u: SimUnit, ms: float) -> void:
	u.bot_think -= ms
	if u.bot_think > 0.0:
		return
	u.bot_think = THINK_MS + sim.rng.randf_range(-80.0, 80.0)
	if u.dead or u.is_incapacitated() or u.is_casting():
		return
	if u.bot_role == "support" and _support(sim, u):
		return
	# Rest when hurt or out of SP and nothing is chasing us.
	var threatened := _threatened(sim, u)
	if not threatened and (u.hp < u.max_hp * 0.35 or (u.bot_role != "melee" and u.sp < u.max_sp * 0.2)):
		if not u.sitting:
			u.target_id = 0
			u.walker.stop()
			sim.command_sit(u.id)
		return
	if u.sitting:
		if (u.hp >= u.max_hp * 0.9 and (u.bot_role == "melee" or u.sp >= u.max_sp * 0.8)) or threatened:
			sim.command_sit(u.id)   # stand up
		else:
			return
	if u.pickup_target != 0 or u.talk_target != 0:
		return
	# Loot first (only what we may take: our own drops or free-for-all).
	var loot := _nearest_loot(sim, u)
	if loot != 0 and u.target_id == 0:
		sim.command_pickup(u.id, loot)
		return
	if u.inventory.weight(sim.item_db) + u.equipment_weight(sim.item_db) > u.max_weight() * 0.6:
		_sell_junk(sim, u)
	# Keep fighting the current target; otherwise pick one.
	var t: SimUnit = sim.units.get(u.target_id)
	if t == null or t.dead:
		t = _pick_target(sim, u)
		if t == null:
			_wander(sim, u)
			return
		sim.command_attack(u.id, t.id)
	_combat_skill(sim, u, t)


## Empties the loot bag the way a merchant would: everything but potions
## becomes Zeny at the usual half price.
static func _sell_junk(sim: FieldSimulation, u: SimUnit) -> void:
	var sold := 0
	for i in range(u.inventory.entries.size() - 1, -1, -1):
		var e: Dictionary = u.inventory.entries[i]
		if int(e.id) == 501:
			continue
		var amount := int(e.amount)
		u.zeny += int(sim.item_db.get(str(int(e.id)), {}).get("price", 0)) / 2 * amount
		sold += amount
		u.inventory.remove_at(i, amount)
	if sold > 0:
		sim.events.append({"type": "inventory", "id": u.id})


static func _threatened(sim: FieldSimulation, u: SimUnit) -> bool:
	for id in sim.units:
		var m: SimUnit = sim.units[id]
		if not m.is_player() and not m.dead and m.target_id == u.id:
			return true
	return false


static func _nearest_loot(sim: FieldSimulation, u: SimUnit) -> int:
	var best := 0
	var best_d := 7
	for gid in sim.ground_items:
		var g: Dictionary = sim.ground_items[gid]
		var free: bool = int(g.owner) == 0 or int(g.owner) == u.id or float(g.age) >= FieldSimulation.OWNER_PRIORITY_MS
		var d := FieldSimulation._chebyshev(u.walker.cell, g.cell)
		if free and d < best_d:
			best_d = d
			best = int(gid)
	return best


## Nearest live monster nobody human is fighting (no kill stealing).
static func _pick_target(sim: FieldSimulation, u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var best_d := HUNT_RADIUS + 1
	for id in sim.units:
		var m: SimUnit = sim.units[id]
		if m.is_player() or m.dead:
			continue
		var stolen := false
		for pid in m.damaged_by:
			var other: SimUnit = sim.units.get(int(pid))
			if other and other.is_player() and not other.is_bot:
				stolen = true
		if stolen and m.target_id != u.id:
			continue
		var d := FieldSimulation._chebyshev(u.walker.cell, m.walker.cell)
		if d < best_d:
			best_d = d
			best = m
	return best


## Uses an attack skill when it makes sense (SP to spare, not on delay).
static func _combat_skill(sim: FieldSimulation, u: SimUnit, t: SimUnit) -> void:
	if u.skill_delay > 0.0 or u.queued_skill != "" or u.sp < u.max_sp * 0.25:
		return
	match u.bot_role:
		"caster":
			var best := ""
			var best_mod := -1
			for code in ["MG_FIREBOLT", "MG_COLDBOLT", "MG_LIGHTNINGBOLT"]:
				if int(u.skills.get(code, 0)) <= 0:
					continue
				var el := String(sim.skill_db[code].element)
				var mod := ElementRulesPreRenewal.modifier(el, t.element, t.element_level)
				if mod > best_mod:
					best_mod = mod
					best = code
			if best != "":
				sim.command_use_skill(u.id, best, t.id)
		"support":
			if int(u.skills.get("SH_SUMMON", 0)) > 0:
				sim.command_use_skill(u.id, "SH_SUMMON", t.id)
		_:
			for code in ["DK_BLOODYCRASH", "SM_BASH"]:
				if int(u.skills.get(code, 0)) > 0 and sim.rng.randf() < 0.35:
					sim.command_use_skill(u.id, code, t.id)
					return


## Healer duties. Returns true if it acted.
static func _support(sim: FieldSimulation, u: SimUnit) -> bool:
	if u.skill_delay > 0.0:
		return false
	var hurt: SimUnit = null
	var hurt_frac := 0.65
	var fallen: SimUnit = null
	var unbuffed: SimUnit = null
	for id in sim.units:
		var p: SimUnit = sim.units[id]
		if not p.is_player() or FieldSimulation._chebyshev(u.walker.cell, p.walker.cell) > SUPPORT_RANGE:
			continue
		if p.dead:
			if fallen == null or not p.is_bot:   # humans first
				fallen = p
			continue
		var frac := float(p.hp) / maxi(1, p.max_hp)
		if frac < hurt_frac or (frac < 0.9 and not p.is_bot and frac < hurt_frac + 0.2):
			hurt_frac = frac
			hurt = p
		if not p.has_status("protection") and (unbuffed == null or not p.is_bot):
			unbuffed = p
	if fallen and int(u.skills.get("SH_PRAYER", 0)) > 0 and u.sp >= 60:
		return sim.command_use_skill(u.id, "SH_PRAYER", fallen.id)
	if hurt and int(u.skills.get("SH_COMFORT", 0)) > 0:
		return sim.command_use_skill(u.id, "SH_COMFORT", hurt.id)
	if unbuffed and int(u.skills.get("SH_PROTECTION", 0)) > 0 and u.sp > u.max_sp * 0.4:
		return sim.command_use_skill(u.id, "SH_PROTECTION", unbuffed.id)
	if not u.has_status("wrath") and int(u.skills.get("SH_WRATH", 0)) > 0 and u.sp > u.max_sp * 0.6:
		return sim.command_use_skill(u.id, "SH_WRATH", u.id)
	return false


static func _wander(sim: FieldSimulation, u: SimUnit) -> void:
	if u.walker.is_moving() or sim.rng.randf() > 0.25:
		return
	var dest := u.walker.cell + Vector2i(sim.rng.randi_range(-10, 10), sim.rng.randi_range(-10, 10))
	sim.command_move(u.id, sim.pathfinder.nearest_walkable(dest, 6))
