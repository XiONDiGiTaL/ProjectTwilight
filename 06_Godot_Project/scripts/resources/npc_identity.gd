class_name NpcIdentity
extends RefCounted
## NPC sprite lookup from the player's client: npcidentity.lub gives
## jobtbl.JT_<NAME> = id, jobname.lub maps ids to sprite names. rAthena
## scripts refer to sprites by id (909) or by constant name (4_F_KAFRA1);
## both resolve to data/sprite/npc/<name>.spr. Read-only, built once.

const DIR := "data/luafiles514/lua files/datainfo/"

static var _by_id: Dictionary = {}     # int -> sprite name
static var _by_const: Dictionary = {}  # "4_F_KAFRA1" -> id
static var _loaded := false


static func ensure(res: Node) -> void:
	if _loaded or res == null:
		return
	_loaded = true
	var idc := Lua51Chunk.decode(res.read(DIR + "npcidentity.lub"))
	var env := idc.run_tables()
	var jobtbl: Dictionary = env.get("jobtbl", {}) if env.get("jobtbl") is Dictionary else {}
	for k in jobtbl:
		var name := String(k)
		if name.begins_with("JT_"):
			_by_const[name.substr(3)] = int(jobtbl[k])
	var jn := Lua51Chunk.decode(res.read(DIR + "jobname.lub"))
	var env2 := jn.run_tables(env)
	for g in env2:
		var t: Variant = env2[g]
		if t is Dictionary and g != "jobtbl":
			for id in t:
				if (id is int) and t[id] is String:
					_by_id[int(id)] = String(t[id]).to_lower()


## Sprite file stem for an rAthena sprite token ("909", "4_F_KAFRA1", "-1").
static func sprite_for(res: Node, token: String) -> String:
	ensure(res)
	token = token.strip_edges()
	if token == "" or token == "-1" or token == "111" or token == "139":
		return ""   # hidden / invisible NPCs
	var id := int(token) if token.is_valid_int() else int(_by_const.get(token.to_upper(), -1))
	if id >= 0 and _by_id.has(id):
		return String(_by_id[id])
	return token.to_lower() if not token.is_valid_int() else ""


static func count() -> int:
	return _by_id.size()
