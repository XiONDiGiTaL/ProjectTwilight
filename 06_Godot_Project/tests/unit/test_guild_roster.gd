extends RefCounted
## Guild roster rules: leader-only invitations, accepting / declining,
## kicking and leadership succession when the leader leaves.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const TEST_PATH := "user://test_guild_roster.json"


static func _gat(w := 400, h := 400) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _field() -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), 51, RuleConfig.new(), TEST_PATH)
	sim.map_name = "prontera"
	sim.map_info = sim.map_db.get("prontera", {})
	return sim


func test_invite_accept_and_persist(_t) -> Variant:
	_clean()
	var sim := _field()
	var leader := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(leader.id, "Twilight Guard")
	var gid := leader.guild_id
	if not sim.command_guild_invite(leader.id, "Member"):
		return "leader could not invite"
	var reloaded := GuildStore.new(TEST_PATH, sim.item_db)
	if reloaded.invites_for("Member").is_empty():
		return "the invitation did not persist"
	var member := sim.add_player("Member", Vector2i(51, 50), FLAT)
	if sim.command_guild_accept(member.id, gid) == false:
		return "member could not accept the invitation"
	if member.guild_id != gid:
		return "accepted member is not in the guild"
	var g := sim.guilds.get_guild(gid)
	if (g.members as Array).size() != 2 or String(g.leader) != "Leader":
		return "roster or leader wrong after accepting"
	if reloaded.invites_for("Member").size() != 1:
		return "acceptance was not saved"
	return true


func test_permissions(_t) -> Variant:
	_clean()
	var sim := _field()
	var leader := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	var member := sim.add_player("Member", Vector2i(51, 50), FLAT)
	sim.command_create_guild(leader.id, "Twilight Guard")
	var gid := leader.guild_id
	sim.command_guild_invite(leader.id, "Member")
	sim.command_guild_accept(member.id, gid)
	if sim.command_guild_invite(member.id, "Third"):
		return "a member must not be able to invite"
	if sim.command_guild_kick(member.id, "Leader"):
		return "a member must not be able to kick"
	if not sim.command_guild_kick(leader.id, "Member"):
		return "the leader could not kick a member"
	if member.guild_id != "":
		return "the kicked online member kept the guild"
	var g := sim.guilds.get_guild(gid)
	return true if (g.members as Array).size() == 1 else "roster not updated after kick"


func test_decline(_t) -> Variant:
	_clean()
	var sim := _field()
	var leader := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(leader.id, "Twilight Guard")
	sim.command_guild_invite(leader.id, "Member")
	var member := sim.add_player("Member", Vector2i(51, 50), FLAT)
	if not sim.command_guild_decline(member.id, leader.guild_id):
		return "declining failed"
	if not sim.guilds.invites_for("Member").is_empty():
		return "the invitation survived a decline"
	return true if member.guild_id == "" else "a decliner joined the guild"


func test_leader_leaving_promotes_next(_t) -> Variant:
	_clean()
	var sim := _field()
	var leader := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	var member := sim.add_player("Member", Vector2i(51, 50), FLAT)
	sim.command_create_guild(leader.id, "Twilight Guard")
	var gid := leader.guild_id
	sim.command_guild_invite(leader.id, "Member")
	sim.command_guild_accept(member.id, gid)
	if not sim.command_leave_guild(leader.id):
		return "leader could not leave"
	var g := sim.guilds.get_guild(gid)
	if String(g.leader) != "Member":
		return "leadership was not promoted: %s" % [g.leader]
	if not sim.command_leave_guild(member.id):
		return "last member could not leave"
	g = sim.guilds.get_guild(gid)
	if not (g.members as Array).is_empty() or String(g.leader) != "":
		return "an empty guild should have no leader"
	if not sim.command_create_guild(member.id, "Twilight Guard"):
		return "the former member could not return"
	g = sim.guilds.get_guild(gid)
	return true if String(g.leader) == "Member" else "returning member did not become leader"


func test_accept_requires_invitation(_t) -> Variant:
	_clean()
	var sim := _field()
	var leader := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(leader.id, "Twilight Guard")
	var outsider := sim.add_player("Outsider", Vector2i(51, 50), FLAT)
	return true if not sim.command_guild_accept(outsider.id, leader.guild_id) else "accepted without an invitation"
