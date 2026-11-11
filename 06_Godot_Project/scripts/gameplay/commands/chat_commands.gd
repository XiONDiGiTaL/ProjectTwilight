class_name ChatCommands
extends RefCounted
## Private-server style at-commands (@go, @heal, @save, @mobinfo ...).
##
## Rules level only: every command runs through FieldSimulation state and
## commands, so a co-op host or a dedicated server can validate them the same
## way offline play does. Map travel is returned as an action and the caller
## checks that the destination exists in the player's data.

const HELP_LINES := [
	"@go <map>          travel to a map (Prontera is the hub)",
	"@warp <map> [x y]  travel to a map or a map cell",
	"@heal              restore HP and SP",
	"@save              set your save point here",
	"@revive            stand up where you fell",
	"@die               fall in battle (for testing)",
	"@rates             current EXP / drop rates",
	"@autoloot [on|off] take drops straight into your bag",
	"@mobinfo <name>    monster level, HP, EXP",
	"@who               players on this map",
	"@guild             your guild and guild storage",
	"@guild create <name>  found or join a guild",
	"@guild leave       leave your guild",
	"@exp               your EXP progress",
	"@job               your class and job level",
	"@where             current map and cell",
	"@time              local time",
]

## Towns with a known arrival cell. Other maps arrive at their centre.
const HUB_TOWNS := {"prontera": Vector2i(156, 191)}


## Runs one line. Returns {ok: bool, text: String, action?: {kind, map, x, y}}.
static func execute(sim: FieldSimulation, u: SimUnit, line: String) -> Dictionary:
	var text := line.strip_edges()
	if text == "" or sim == null or u == null:
		return _ok("")
	if not text.begins_with("@"):
		return _ok("You say: %s" % text)
	var parts := text.substr(1).split(" ", false)
	if parts.is_empty():
		return _err("Type @help for the command list.")
	var cmd := String(parts[0]).to_lower()
	var args := parts.slice(1)
	match cmd:
		"help", "commands", "?":
			return _ok("\n".join(HELP_LINES))
		"go":
			if args.is_empty():
				return _err("Usage: @go <map>   (e.g. @go prontera)")
			var m := String(args[0]).to_lower()
			var cell: Vector2i = HUB_TOWNS.get(m, Vector2i.ZERO)
			return _travel(m, cell)
		"warp":
			if args.is_empty():
				return _err("Usage: @warp <map> [x y]")
			var m := String(args[0]).to_lower()
			var cell := Vector2i.ZERO
			if args.size() >= 3 and String(args[1]).is_valid_int() and String(args[2]).is_valid_int():
				cell = Vector2i(int(args[1]), int(args[2]))
			return _travel(m, cell)
		"heal":
			if u.dead:
				return _err("You are dead. Try @revive.")
			sim.script_heal(u, u.max_hp, u.max_sp)
			return _ok("Fully healed.")
		"save":
			u.save_map = sim.map_name
			u.save_cell = u.walker.cell
			return _ok("Save point set to %s (%d, %d)." % [sim.map_name, u.save_cell.x, u.save_cell.y])
		"die":
			if u.dead:
				return _err("You are already down.")
			sim._kill(u, u)
			return _ok("You fall in battle.")
		"revive":
			if not sim.command_revive(u.id):
				return _err("You are not dead.")
			return _ok("You stand up again.")
		"rates":
			return _ok(sim.rules.describe())
		"autoloot":
			if args.is_empty():
				sim.rules.autoloot = not sim.rules.autoloot
			else:
				sim.rules.autoloot = String(args[0]).to_lower() in ["on", "1", "true", "yes"]
			return _ok("Autoloot %s." % ("ON" if sim.rules.autoloot else "OFF"))
		"mobinfo":
			if args.is_empty():
				return _err("Usage: @mobinfo <name>")
			return _mobinfo(sim, " ".join(args))
		"who":
			return _ok(_who(sim))
		"guild":
			if u.guild_id == "" and args.is_empty():
				return _ok("You are not in a guild. Use @guild create <name>.")
			if args.is_empty():
				var g: Dictionary = sim.guilds.get_guild(u.guild_id)
				var members := 0
				var stored := 0
				if not g.is_empty():
					members = (g.members as Array).size()
					stored = (g.get("storage") as Inventory).entries.size()
				return _ok("Guild: %s   Members: %d   Storage: %d / %d" % [u.guild_name, members, stored, SimUnit.STORAGE_SLOTS])
			var sub := String(args[0]).to_lower()
			if sub == "create":
				if args.size() < 2:
					return _err("Usage: @guild create <name>")
				if not sim.command_create_guild(u.id, " ".join(args.slice(1))):
					return _err("You are already in a guild, or that name is too short.")
				return _ok("Guild %s founded. Its storage opens at a guild Kafra." % u.guild_name)
			if sub == "leave":
				if not sim.command_leave_guild(u.id):
					return _err("You are not in a guild.")
				return _ok("You left your guild.")
			return _err("Usage: @guild [create <name>|leave]")
		"exp":
			return _ok("%d / %d base   %d / %d job" % [u.base_exp, sim.next_base_exp(u), u.job_exp, sim.next_job_exp(u)])
		"job":
			var jn := String(sim.job_db.get(u.job, {}).get("name", u.job))
			return _ok("%s   Base Lv %d   Job Lv %d" % [jn, u.level, u.job_level])
		"where":
			return _ok("%s   (%d, %d)" % [String(sim.map_info.get("name", sim.map_name)), u.walker.cell.x, u.walker.cell.y])
		"time":
			return _ok(Time.get_time_string_from_system())
	return _err("Unknown command @%s. Type @help." % cmd)


static func _travel(map_name: String, cell: Vector2i) -> Dictionary:
	return {"ok": true, "text": "Traveling to %s." % map_name,
		"action": {"kind": "warp", "map": map_name, "x": cell.x, "y": cell.y}}


static func _mobinfo(sim: FieldSimulation, query: String) -> Dictionary:
	var q := query.to_lower()
	var found: Dictionary = {}
	var id := ""
	if sim.monster_db.has(q):
		id = q
		found = sim.monster_db[q]
	else:
		for k in sim.monster_db:
			var entry: Variant = sim.monster_db[k]
			if not (entry is Dictionary):
				continue
			if String(entry.get("name", "")).to_lower().contains(q):
				id = String(k)
				found = entry
				break
	if found.is_empty():
		return _err("No monster named %s." % query)
	var drops: Array = found.get("drops", [])
	var names: Array = []
	for d in drops.slice(0, 4):
		var def: Dictionary = sim.item_db.get(str(int(d[0])), {})
		names.append(String(def.get("name", str(d[0]))))
	var drop_text := ", ".join(names) if not names.is_empty() else "none known"
	return _ok("%s  (id %s)   Lv %d   HP %d   Base EXP %d   Job EXP %d\nDrops: %s" % [
		String(found.get("name", "?")), id, int(found.get("level", 0)), int(found.get("hp", 0)),
		int(found.get("base_exp", 0)), int(found.get("job_exp", 0)), drop_text])


static func _who(sim: FieldSimulation) -> String:
	var lines: Array = []
	for id in sim.units:
		var p: SimUnit = sim.units[id]
		if not p.is_player() or p.dead:
			continue
		var jn := String(sim.job_db.get(p.job, {}).get("name", p.job))
		lines.append("%s   Lv %d %s" % [p.name, p.level, jn])
	if lines.is_empty():
		return "Nobody else is here."
	return "\n".join(lines)


static func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text}


static func _err(text: String) -> Dictionary:
	return {"ok": false, "text": text}
