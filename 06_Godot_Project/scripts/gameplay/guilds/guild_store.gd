class_name GuildStore
extends RefCounted
## Shared guild registry and guild storage, persisted to user://guilds.json.
##
## Offline mode owns this table; a co-op host or dedicated server would keep
## the same records server-side. Storage is one 300-slot bag per guild, shared
## by every member and saved independently of character saves.
##
## Ranks: every member has one of "leader" / "officer" / "member" in the
## record's `ranks` map (name -> rank). `leader` stays the canonical leader
## name and always agrees with the single "leader" entry. Files written
## before ranks existed load with the recorded leader as leader and everyone
## else as member. This class only stores; FieldSimulation checks who may do
## what (see can()).

const PATH := "user://guilds.json"
const SLOTS := 300
const RANK_LEADER := "leader"
const RANK_OFFICER := "officer"
const RANK_MEMBER := "member"
const RANKS := [RANK_LEADER, RANK_OFFICER, RANK_MEMBER]
const MOTD_MAX := 200

var path := PATH
var guilds: Dictionary = {}   # gid -> {id, name, leader, members: Array, ranks: Dictionary, invites: Array, storage: Inventory}
var _item_db: Dictionary = {}


func _init(p_path := PATH, item_db: Dictionary = {}) -> void:
	path = p_path
	_item_db = item_db
	load_from_disk()


## Stable id derived from the guild name, so the same name is the same guild.
static func id_for(name: String) -> String:
	return "g_" + name.strip_edges().to_lower().md5_text().substr(0, 10)


func get_guild(gid: String) -> Dictionary:
	return guilds.get(gid, {})


func find_by_name(name: String) -> Dictionary:
	var clean := name.strip_edges().to_lower()
	for gid in guilds:
		if String(guilds[gid].name).to_lower() == clean:
			return guilds[gid]
	return {}


## Creates the guild when needed, adds `member`, returns its record ({} on a
## name that cannot be used).
func join(name: String, member: String) -> Dictionary:
	var clean := name.strip_edges().left(24)
	if clean.length() < 2 or member == "":
		return {}
	var g: Dictionary = find_by_name(clean)
	if g.is_empty():
		var inv := Inventory.new()
		inv.max_entries = SLOTS
		g = {"id": id_for(clean), "name": clean, "leader": member, "members": [], "ranks": {}, "motd": "", "invites": [], "storage": inv}
		guilds[String(g.id)] = g
	_add_member(g, member)
	(g.invites as Array).erase(member)
	save()
	return g


## Adds a member with the right rank: leader if the guild has none, else member.
func _add_member(g: Dictionary, member: String) -> void:
	if not (g.members as Array).has(member):
		g.members.append(member)
	if String(g.get("leader", "")) == "":
		g.leader = member
	var ranks: Dictionary = g.ranks
	if String(g.leader) == member:
		ranks[member] = RANK_LEADER
	elif not ranks.has(member):
		ranks[member] = RANK_MEMBER


## "leader" / "officer" / "member", or "" for non-members.
func rank_of(gid: String, member: String) -> String:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or not (g.members as Array).has(member):
		return ""
	if String(g.get("leader", "")) == member:
		return RANK_LEADER
	var r := String((g.ranks as Dictionary).get(member, RANK_MEMBER))
	return r if r == RANK_OFFICER else RANK_MEMBER


## The permission matrix. action: invite | kick | promote | demote |
## transfer | disband | storage. `target_rank` matters for kick only.
static func can(actor_rank: String, action: String, target_rank := RANK_MEMBER) -> bool:
	match action:
		"storage":
			return actor_rank != ""
		"invite":
			return actor_rank == RANK_LEADER or actor_rank == RANK_OFFICER
		"kick":
			if actor_rank == RANK_LEADER:
				return target_rank != RANK_LEADER
			return actor_rank == RANK_OFFICER and target_rank == RANK_MEMBER
		"promote", "demote", "transfer", "disband":
			return actor_rank == RANK_LEADER
		"motd":
			return actor_rank == RANK_LEADER or actor_rank == RANK_OFFICER
		"chat":
			return actor_rank != ""
	return false


## Sets a member's rank to officer or member (never the leader's). The caller
## checks permissions. False when nothing would change.
func set_rank(gid: String, member: String, rank: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or not (g.members as Array).has(member) or String(g.leader) == member:
		return false
	if rank != RANK_OFFICER and rank != RANK_MEMBER:
		return false
	if rank_of(gid, member) == rank:
		return false
	g.ranks[member] = rank
	save()
	return true


## Hands leadership to another member. The old leader becomes an officer.
func transfer(gid: String, new_leader: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or not (g.members as Array).has(new_leader) or String(g.leader) == new_leader:
		return false
	var old := String(g.leader)
	g.leader = new_leader
	g.ranks[new_leader] = RANK_LEADER
	if (g.members as Array).has(old):
		g.ranks[old] = RANK_OFFICER
	save()
	return true


## Removes the guild and its storage for good.
func disband(gid: String) -> bool:
	if not guilds.has(gid):
		return false
	guilds.erase(gid)
	save()
	return true


func leave(gid: String, member: String) -> void:
	var g: Dictionary = get_guild(gid)
	if g.is_empty():
		return
	var was_leader := String(g.get("leader", "")) == member
	(g.members as Array).erase(member)
	(g.invites as Array).erase(member)
	(g.ranks as Dictionary).erase(member)
	if (g.members as Array).is_empty():
		g.leader = ""
		guilds.erase(gid)   # nobody left: the guild is gone
	elif was_leader:
		# Succession: the first officer, otherwise the first member.
		var heir := String((g.members as Array)[0])
		for m in g.members:
			if String((g.ranks as Dictionary).get(m, RANK_MEMBER)) == RANK_OFFICER:
				heir = String(m)
				break
		g.leader = heir
		g.ranks[heir] = RANK_LEADER
	save()


## Adds a pending invitation (idempotent); false for members / bad names.
func invite(gid: String, member: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or member == "" or (g.members as Array).has(member):
		return false
	if (g.invites as Array).has(member):
		return true
	g.invites.append(member)
	save()
	return true


## Accepts an invitation and returns the guild ({} if there is none).
func accept(gid: String, member: String) -> Dictionary:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or not (g.invites as Array).has(member):
		return {}
	(g.invites as Array).erase(member)
	_add_member(g, member)
	save()
	return g


func decline(gid: String, member: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty():
		return false
	var had := (g.invites as Array).has(member)
	(g.invites as Array).erase(member)
	if had:
		save()
	return had


## Removes a member (never the leader). The caller checks permissions.
func kick(gid: String, member: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty() or not (g.members as Array).has(member) or String(g.get("leader", "")) == member:
		return false
	(g.members as Array).erase(member)
	(g.invites as Array).erase(member)
	(g.ranks as Dictionary).erase(member)
	save()
	return true


## Guilds that have a pending invitation for `member`.
func invites_for(member: String) -> Array:
	var out: Array = []
	for gid in guilds:
		var g: Dictionary = guilds[gid]
		if (g.invites as Array).has(member):
			out.append(g)
	return out


func storage_of(gid: String) -> Inventory:
	var g: Dictionary = get_guild(gid)
	return g.get("storage") if not g.is_empty() else null


## The guild's message of the day ("" when none is set).
func motd_of(gid: String) -> String:
	var g: Dictionary = get_guild(gid)
	return String(g.get("motd", "")) if not g.is_empty() else ""


## A one-line MOTD, capped at MOTD_MAX characters.
static func clean_motd(text: String) -> String:
	return text.replace("\r", " ").replace("\n", " ").strip_edges().left(MOTD_MAX)


## Sets or clears the MOTD. The caller checks permission.
func set_motd(gid: String, text: String) -> bool:
	var g: Dictionary = get_guild(gid)
	if g.is_empty():
		return false
	g.motd = clean_motd(text)
	save()
	return true


func save() -> void:
	var out := {}
	for gid in guilds:
		var g: Dictionary = guilds[gid]
		var inv: Inventory = g.get("storage")
		out[gid] = {"name": g.name, "leader": String(g.get("leader", "")),
			"members": (g.members as Array).duplicate(), "ranks": (g.get("ranks", {}) as Dictionary).duplicate(),
			"motd": String(g.get("motd", "")), "invites": (g.get("invites", []) as Array).duplicate(),
			"storage": inv.to_array()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()


func load_from_disk() -> void:
	guilds.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	for gid in parsed:
		var e: Variant = parsed[gid]
		if not (e is Dictionary):
			continue
		var raw: Variant = e.get("storage", [])
		var inv := Inventory.from_array(raw if raw is Array else [], _item_db)
		inv.max_entries = SLOTS
		var members: Array = []
		var raw_members: Variant = e.get("members", [])
		if raw_members is Array:
			for m in raw_members:
				members.append(String(m).left(23))
		var invites: Array = []
		var raw_invites: Variant = e.get("invites", [])
		if raw_invites is Array:
			for m in raw_invites:
				invites.append(String(m).left(23))
		var motd := clean_motd(String(e.get("motd", "")))
		var leader := String(e.get("leader", ""))
		if leader == "" and not members.is_empty():
			leader = String(members[0])
		if leader != "" and not members.has(leader):
			leader = String(members[0]) if not members.is_empty() else ""
		# Ranks: files from before ranks have none (leader + members); unknown
		# values fall back to member; exactly one leader, matching `leader`.
		var ranks := {}
		var raw_ranks: Variant = e.get("ranks", {})
		for m in members:
			var r := String(raw_ranks.get(m, RANK_MEMBER)) if raw_ranks is Dictionary else RANK_MEMBER
			ranks[m] = RANK_OFFICER if r == RANK_OFFICER else RANK_MEMBER
		if leader != "":
			ranks[leader] = RANK_LEADER
		guilds[String(gid)] = {"id": String(gid), "name": String(e.get("name", "Guild")).left(24),
			"leader": leader, "members": members, "ranks": ranks, "motd": motd,
			"invites": invites, "storage": inv}
