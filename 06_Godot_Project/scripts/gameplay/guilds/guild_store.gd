class_name GuildStore
extends RefCounted
## Shared guild registry and guild storage, persisted to user://guilds.json.
##
## Offline mode owns this table; a co-op host or dedicated server would keep
## the same records server-side. Storage is one 300-slot bag per guild, shared
## by every member and saved independently of character saves.

const PATH := "user://guilds.json"
const SLOTS := 300

var path := PATH
var guilds: Dictionary = {}   # gid -> {id, name, leader, members: Array, invites: Array, storage: Inventory}
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
		g = {"id": id_for(clean), "name": clean, "leader": member, "members": [], "invites": [], "storage": inv}
		guilds[String(g.id)] = g
	if not (g.members as Array).has(member):
		g.members.append(member)
	if String(g.get("leader", "")) == "":
		g.leader = member
	(g.invites as Array).erase(member)
	save()
	return g


func leave(gid: String, member: String) -> void:
	var g: Dictionary = get_guild(gid)
	if g.is_empty():
		return
	(g.members as Array).erase(member)
	(g.invites as Array).erase(member)
	if String(g.get("leader", "")) == member:
		g.leader = String((g.members as Array)[0]) if not (g.members as Array).is_empty() else ""
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
	if not (g.members as Array).has(member):
		g.members.append(member)
	if String(g.get("leader", "")) == "":
		g.leader = member
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


func save() -> void:
	var out := {}
	for gid in guilds:
		var g: Dictionary = guilds[gid]
		var inv: Inventory = g.get("storage")
		out[gid] = {"name": g.name, "leader": String(g.get("leader", "")),
			"members": (g.members as Array).duplicate(), "invites": (g.get("invites", []) as Array).duplicate(),
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
		var leader := String(e.get("leader", ""))
		if leader == "" and not members.is_empty():
			leader = String(members[0])
		guilds[String(gid)] = {"id": String(gid), "name": String(e.get("name", "Guild")).left(24),
			"leader": leader, "members": members, "invites": invites, "storage": inv}
