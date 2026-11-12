class_name NetCodec
extends RefCounted
## Plain-data forms of simulation state for the co-op wire (Godot Variant
## encoding over ENet; no objects are ever sent or decoded).
##
##   unit_state(u)        public state of any unit (what other players see)
##   self_state(sim, u)   the owner's private state: inventory, skills, stats,
##                        storage, open windows, guild record
## The host is authoritative: clients only ever *apply* these.

## Commands a client may ask the host to run on its own unit. Everything else
## is refused. The host always supplies the unit id itself.
const CLIENT_COMMANDS := [
	"command_move", "command_attack", "command_pickup", "command_use_item", "command_equip", "command_unequip",
	"command_talk", "command_buy", "command_sell", "close_shop", "command_open_storage", "close_storage",
	"command_storage_deposit", "command_storage_withdraw", "command_create_guild", "command_guild_invite",
	"command_guild_accept", "command_guild_decline", "command_guild_kick", "command_guild_promote",
	"command_guild_demote", "command_guild_transfer", "command_guild_disband", "command_leave_guild",
	"command_open_guild_storage", "close_guild_storage", "command_guild_deposit", "command_guild_withdraw",
	"command_learn_skill", "command_job_change", "command_use_skill", "command_sit", "command_raise_stat",
]
## Argument types per command (after the unit id), checked before calling.
const COMMAND_ARGS := {
	"command_move": [TYPE_VECTOR2I], "command_attack": [TYPE_INT], "command_pickup": [TYPE_INT],
	"command_use_item": [TYPE_INT], "command_equip": [TYPE_INT], "command_unequip": [TYPE_STRING],
	"command_talk": [TYPE_INT], "command_buy": [TYPE_INT, TYPE_INT], "command_sell": [TYPE_INT, TYPE_INT],
	"close_shop": [], "command_open_storage": [TYPE_INT], "close_storage": [],
	"command_storage_deposit": [TYPE_INT, TYPE_INT], "command_storage_withdraw": [TYPE_INT, TYPE_INT],
	"command_create_guild": [TYPE_STRING], "command_guild_invite": [TYPE_STRING], "command_guild_accept": [TYPE_STRING],
	"command_guild_decline": [TYPE_STRING], "command_guild_kick": [TYPE_STRING], "command_guild_promote": [TYPE_STRING],
	"command_guild_demote": [TYPE_STRING], "command_guild_transfer": [TYPE_STRING], "command_guild_disband": [],
	"command_leave_guild": [], "command_open_guild_storage": [TYPE_INT], "close_guild_storage": [],
	"command_guild_deposit": [TYPE_INT, TYPE_INT], "command_guild_withdraw": [TYPE_INT, TYPE_INT],
	"command_learn_skill": [TYPE_STRING], "command_job_change": [TYPE_STRING], "command_use_skill": [TYPE_STRING, TYPE_INT],
	"command_sit": [], "command_raise_stat": [TYPE_STRING],
}


## True when `args` is a well-formed argument list for a client command.
static func valid_command(name: String, args: Array) -> bool:
	if not CLIENT_COMMANDS.has(name):
		return false
	var want: Array = COMMAND_ARGS[name]
	if args.size() != want.size():
		return false
	for i in want.size():
		if typeof(args[i]) != int(want[i]):
			return false
		if args[i] is String and String(args[i]).length() > 64:
			return false
	return true


static func unit_state(u: SimUnit) -> Dictionary:
	var w := u.walker
	return {
		"id": u.id, "k": int(u.kind), "n": u.name, "mob": u.mob_id, "spr": u.sprite, "job": u.job,
		"male": u.male, "hs": u.hair_style, "hc": u.hair_color, "cc": u.cloth_color, "aura": u.aura,
		"lv": u.level, "jlv": u.job_level, "hp": u.hp, "mhp": u.max_hp, "sp": u.sp, "msp": u.max_sp,
		"cell": w.cell, "dir": w.direction, "path": w.path.duplicate(), "prog": w._progress, "spd": w.walk_speed,
		"dead": u.dead, "sit": u.sitting, "td": u.trickdead, "tgt": u.target_id,
		"aint": u.attack_interval, "amot": u.attack_motion, "wt": u.weapon_type, "size": u.size,
		"el": u.element, "ellv": u.element_level, "st": u.statuses.duplicate(true),
		"cs": u.cast_skill, "cl": u.cast_left, "ct": u.cast_total, "ctg": u.cast_target, "clv": u.cast_level,
		"bot": u.is_bot, "role": u.bot_role, "gid": u.guild_id, "gn": u.guild_name,
	}


## Applies a unit state onto a replica unit (created when missing). Returns
## true when the unit's look changed (the view must be rebuilt).
static func apply_unit(sim: FieldSimulation, d: Dictionary) -> bool:
	var id := int(d.id)
	var u: SimUnit = sim.units.get(id)
	var fresh := u == null
	if fresh:
		u = SimUnit.new()
		u.id = id
		u.walker = GridWalker.new(d.cell)
		sim.units[id] = u
	var look_before := "%s|%s|%d|%d|%d|%s" % [u.job, u.male, u.hair_style, u.hair_color, u.cloth_color, u.weapon_type]
	u.kind = int(d.k) as SimUnit.Kind
	u.name = String(d.n)
	u.mob_id = String(d.mob)
	u.sprite = String(d.spr)
	u.job = String(d.job)
	u.male = bool(d.male)
	u.hair_style = int(d.hs)
	u.hair_color = int(d.hc)
	u.cloth_color = int(d.cc)
	u.aura = String(d.aura)
	u.level = int(d.lv)
	u.job_level = int(d.jlv)
	u.max_hp = int(d.mhp)
	u.hp = int(d.hp)
	u.max_sp = int(d.msp)
	u.sp = int(d.sp)
	u.dead = bool(d.dead)
	u.sitting = bool(d.sit)
	u.trickdead = bool(d.td)
	u.target_id = int(d.tgt)
	u.attack_interval = float(d.aint)
	u.attack_motion = float(d.amot)
	u.weapon_type = String(d.wt)
	u.size = String(d.size)
	u.element = String(d.el)
	u.element_level = int(d.ellv)
	u.statuses = (d.st as Dictionary).duplicate(true)
	u.cast_skill = String(d.cs)
	u.cast_left = float(d.cl)
	u.cast_total = float(d.ct)
	u.cast_target = int(d.ctg)
	u.cast_level = int(d.clv)
	u.is_bot = bool(d.bot)
	u.bot_role = String(d.role)
	u.guild_id = String(d.gid)
	u.guild_name = String(d.gn)
	if u.mob_id != "" and u.data.is_empty():
		u.data = sim.monster_db.get(u.mob_id, {})
	# The host's walker is the truth; the replica only interpolates between updates.
	var w := u.walker
	w.walk_speed = float(d.spd)
	w.cell = d.cell
	w.direction = int(d.dir)
	var path: Array[Vector2i] = []
	for c in d.path:
		path.append(c)
	w.path = path
	w._progress = float(d.prog)
	var look_after := "%s|%s|%d|%d|%d|%s" % [u.job, u.male, u.hair_style, u.hair_color, u.cloth_color, u.weapon_type]
	return not fresh and look_before != look_after


## The owner's private state (a save-shaped character plus session fields).
static func self_state(sim: FieldSimulation, u: SimUnit) -> Dictionary:
	var c: Dictionary = SaveGame.capture(u, sim.map_name).character
	c.erase("hotkeys")   # hotkeys are the client's own UI
	c["open_shop"] = u.open_shop
	c["open_storage"] = u.open_storage
	c["open_guild_storage"] = u.open_guild_storage
	c["open_guild_npc"] = u.open_guild_npc
	c["guild_record"] = sim.guilds.record_data(u.guild_id)
	var invites: Array = []
	for g in sim.guilds.invites_for(u.name):
		invites.append(sim.guilds.record_data(String(g.id)))
	c["guild_invites"] = invites
	return c


## Applies the owner's private state onto the replica player.
static func apply_self(sim: FieldSimulation, u: SimUnit, c: Dictionary) -> void:
	u.base_exp = int(c.get("base_exp", 0))
	u.job_exp = int(c.get("job_exp", 0))
	var st: Dictionary = c.get("stats", {})
	for k in FieldSimulation.STAT_NAMES:
		u.stats[k] = int(st.get(k, 1))
	u.status_points = int(c.get("status_points", 0))
	u.skill_points = int(c.get("skill_points", 0))
	u.zeny = int(c.get("zeny", 0))
	u.inventory = Inventory.from_array(c.get("inventory", []), sim.item_db)
	var storage := Inventory.from_array(c.get("storage", []), sim.item_db)
	storage.max_entries = SimUnit.STORAGE_SLOTS
	u.storage = storage
	var eq := {}
	var raw_eq: Dictionary = c.get("equipment", {})
	for slot in raw_eq:
		eq[String(slot)] = int(raw_eq[slot])
	u.equipment = eq
	var sk := {}
	var raw_sk: Dictionary = c.get("skills", {})
	for code in raw_sk:
		sk[String(code)] = int(raw_sk[code])
	u.skills = sk
	u.script_vars = SaveGame._vars_in(c.get("script_vars", {}))
	u.options = (c.get("options", {}) as Dictionary).duplicate()
	u.save_map = String(c.get("save_map", SimUnit.HUB_MAP))
	var sc: Array = c.get("save_cell", [SimUnit.HUB_CELL.x, SimUnit.HUB_CELL.y])
	u.save_cell = Vector2i(int(sc[0]), int(sc[1]))
	u.guild_id = String(c.get("guild_id", ""))
	u.guild_name = String(c.get("guild_name", ""))
	u.open_shop = int(c.get("open_shop", 0))
	u.open_storage = int(c.get("open_storage", 0))
	u.open_guild_storage = String(c.get("open_guild_storage", ""))
	u.open_guild_npc = int(c.get("open_guild_npc", 0))
	# Guild records the player can see: their own guild and pending invitations.
	sim.guilds.guilds.clear()
	sim.guilds.install_record(c.get("guild_record", {}))
	for g in c.get("guild_invites", []):
		sim.guilds.install_record(g)
