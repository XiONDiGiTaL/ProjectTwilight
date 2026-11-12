extends RefCounted
## Guild ranks (leader / officer / member): migration of rank-less guild
## files, the permission matrix enforced by FieldSimulation, persistence,
## leadership transfer, disband and succession.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const TEST_PATH := "user://test_guild_ranks.json"


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
	var sim := FieldSimulation.new(_gat(), 71, RuleConfig.new(), TEST_PATH)
	sim.map_name = "prontera"
	sim.map_info = sim.map_db.get("prontera", {})
	return sim


## A guild with Leader, Officer (promoted), Member and Second (members), all online.
func _guild(sim: FieldSimulation) -> Dictionary:
	var out := {}
	var names := ["Leader", "Officer", "Member", "Second"]
	for i in names.size():
		out[names[i]] = sim.add_player(names[i], Vector2i(50 + i, 50), FLAT)
	var leader: SimUnit = out.Leader
	sim.command_create_guild(leader.id, "Twilight Guard")
	for n in ["Officer", "Member", "Second"]:
		sim.command_guild_invite(leader.id, n)
		sim.command_guild_accept((out[n] as SimUnit).id, leader.guild_id)
	sim.command_guild_promote(leader.id, "Officer")
	out.gid = leader.guild_id
	sim.drain_events()
	return out


static func _snapshot(sim: FieldSimulation) -> String:
	return FileAccess.get_file_as_string(TEST_PATH) if FileAccess.file_exists(TEST_PATH) else ""


func test_legacy_file_migrates(_t) -> Variant:
	_clean()
	var legacy := {"g_legacy": {"name": "Old Guard", "leader": "Elder", "members": ["Elder", "Squire", "Page"],
		"invites": ["Hopeful"], "storage": []}}
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy))
	f.close()
	var sim := _field()
	var store := sim.guilds
	if store.rank_of("g_legacy", "Elder") != "leader" or store.rank_of("g_legacy", "Squire") != "member" or store.rank_of("g_legacy", "Page") != "member":
		return "legacy ranks wrong: %s" % [store.get_guild("g_legacy").get("ranks")]
	if store.rank_of("g_legacy", "Hopeful") != "" or store.invites_for("Hopeful").size() != 1:
		return "invitations should survive and carry no rank"
	# Usable immediately: the legacy leader can promote, and it persists in the new shape.
	var elder := sim.add_player("Elder", Vector2i(50, 50), FLAT)
	elder.guild_id = "g_legacy"
	elder.guild_name = "Old Guard"
	if not sim.command_guild_promote(elder.id, "Squire"):
		return "legacy leader could not promote"
	var reloaded := GuildStore.new(TEST_PATH, sim.item_db)
	if reloaded.rank_of("g_legacy", "Squire") != "officer" or reloaded.rank_of("g_legacy", "Elder") != "leader":
		return "migrated record did not save ranks"
	# Unknown rank values fall back to member; a leader missing from `ranks` is still the leader.
	var odd := {"g_odd": {"name": "Odd", "leader": "Boss", "members": ["Boss", "Imp"], "ranks": {"Imp": "emperor"}, "invites": [], "storage": []}}
	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(odd))
	f.close()
	var s2 := GuildStore.new(TEST_PATH, sim.item_db)
	return true if s2.rank_of("g_odd", "Imp") == "member" and s2.rank_of("g_odd", "Boss") == "leader" else "unknown rank not normalised"


func test_promote_persists(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	if sim.guilds.rank_of(g.gid, "Officer") != "officer" or sim.guild_rank(g.Officer) != "officer":
		return "promotion did not apply"
	if GuildStore.new(TEST_PATH, sim.item_db).rank_of(g.gid, "Officer") != "officer":
		return "promotion did not survive a reload"
	if sim.command_guild_promote(leader.id, "Officer"):
		return "promoting an officer again should be rejected"
	if sim.command_guild_promote(leader.id, "Nobody") or sim.command_guild_promote(leader.id, "Leader"):
		return "promoted a non-member or the leader"
	if not sim.command_guild_demote(leader.id, "Officer") or sim.guilds.rank_of(g.gid, "Officer") != "member":
		return "demotion failed"
	return true if GuildStore.new(TEST_PATH, sim.item_db).rank_of(g.gid, "Officer") == "member" else "demotion did not persist"


func test_officer_can_invite_and_kick_members(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var officer: SimUnit = g.Officer
	if not sim.command_guild_invite(officer.id, "Recruit"):
		return "officer could not invite"
	if sim.guilds.invites_for("Recruit").is_empty():
		return "officer invitation not stored"
	if not sim.command_guild_kick(officer.id, "Member"):
		return "officer could not kick an ordinary member"
	var member: SimUnit = g.Member
	if member.guild_id != "" or sim.guilds.rank_of(g.gid, "Member") != "":
		return "kicked member still has a guild or rank"
	return true if not (sim.guilds.get_guild(g.gid).ranks as Dictionary).has("Member") else "rank entry survived the kick"


func test_member_has_no_management_rights(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var member: SimUnit = g.Member
	var before := _snapshot(sim)
	if sim.command_guild_invite(member.id, "Recruit"):
		return "member invited"
	if sim.command_guild_kick(member.id, "Second"):
		return "member kicked"
	if sim.command_guild_promote(member.id, "Second") or sim.command_guild_demote(member.id, "Officer"):
		return "member changed a rank"
	if sim.command_guild_transfer(member.id, "Second") or sim.command_guild_disband(member.id):
		return "member transferred or disbanded"
	var fails: Array = sim.drain_events().filter(func(e): return e.type == "guild" and e.id == member.id and not e.ok)
	if fails.size() != 6:
		return "each rejection should explain itself with a guild event (got %d)" % fails.size()
	# Rejected actions change nothing in memory or on disk.
	return true if _snapshot(sim) == before and sim.guilds.rank_of(g.gid, "Second") == "member" else "a rejected action mutated the guild"


func test_officer_limits(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	var officer: SimUnit = g.Officer
	sim.command_guild_promote(leader.id, "Second")
	var before := _snapshot(sim)
	if sim.command_guild_kick(officer.id, "Second"):
		return "officer kicked another officer"
	if sim.command_guild_kick(officer.id, "Leader"):
		return "officer kicked the leader"
	if sim.command_guild_promote(officer.id, "Member") or sim.command_guild_demote(officer.id, "Second"):
		return "officer changed a rank"
	if sim.command_guild_transfer(officer.id, "Member") or sim.command_guild_disband(officer.id):
		return "officer transferred or disbanded"
	if sim.command_guild_kick(leader.id, "Leader"):
		return "leader kicked themselves"
	return true if _snapshot(sim) == before else "rejected officer actions were saved"


func test_leader_kicks_officer(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	if not sim.command_guild_kick(leader.id, "Officer"):
		return "leader could not kick an officer"
	var rec := sim.guilds.get_guild(g.gid)
	if (rec.members as Array).has("Officer") or (rec.ranks as Dictionary).has("Officer"):
		return "officer membership or rank entry remained"
	var reloaded := GuildStore.new(TEST_PATH, sim.item_db)
	return true if reloaded.rank_of(g.gid, "Officer") == "" and (g.Officer as SimUnit).guild_id == "" else "kick not persisted / online state not cleared"


func test_transfer_leadership(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	if sim.command_guild_transfer(leader.id, "Stranger") or sim.command_guild_transfer(leader.id, "Leader"):
		return "transferred to a non-member or to self"
	if not sim.command_guild_transfer(leader.id, "Member"):
		return "transfer failed"
	var rec := sim.guilds.get_guild(g.gid)
	if String(rec.leader) != "Member" or sim.guilds.rank_of(g.gid, "Member") != "leader" or sim.guilds.rank_of(g.gid, "Leader") != "officer":
		return "transfer left leader=%s ranks=%s" % [rec.leader, rec.ranks]
	var leaders := 0
	for m in rec.ranks:
		if String(rec.ranks[m]) == "leader":
			leaders += 1
	if leaders != 1:
		return "exactly one leader entry expected, found %d" % leaders
	var reloaded := GuildStore.new(TEST_PATH, sim.item_db)
	if String(reloaded.get_guild(g.gid).leader) != "Member" or reloaded.rank_of(g.gid, "Leader") != "officer":
		return "transfer did not persist"
	# The old leader lost leader rights; the new leader has them.
	if sim.command_guild_promote(leader.id, "Second"):
		return "the old leader kept leader rights"
	return true if sim.command_guild_promote((g.Member as SimUnit).id, "Second") else "the new leader cannot promote"


func test_disband_clears_everyone(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	var member: SimUnit = g.Member
	member.open_guild_storage = String(g.gid)
	member.open_guild_npc = 7
	if not sim.command_guild_disband(leader.id):
		return "leader could not disband"
	if not sim.guilds.get_guild(g.gid).is_empty() or not GuildStore.new(TEST_PATH, sim.item_db).get_guild(g.gid).is_empty():
		return "guild record survived the disband"
	for n in ["Leader", "Officer", "Member", "Second"]:
		var u: SimUnit = g[n]
		if u.guild_id != "" or u.guild_name != "" or u.open_guild_storage != "" or u.open_guild_npc != 0:
			return "%s kept guild state after the disband" % n
	var told: Array = sim.drain_events().filter(func(e): return e.type == "guild" and e.id == member.id)
	return true if not told.is_empty() else "members were not told about the disband"


func test_succession_prefers_officers(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	# Roster order is Leader, Officer, Member, Second; make the LAST one the only officer.
	var leader: SimUnit = g.Leader
	sim.command_guild_demote(leader.id, "Officer")
	sim.command_guild_promote(leader.id, "Second")
	sim.command_leave_guild(leader.id)
	var rec := sim.guilds.get_guild(g.gid)
	if String(rec.leader) != "Second" or sim.guilds.rank_of(g.gid, "Second") != "leader":
		return "an officer should succeed first, got %s" % rec.leader
	# No officers left: the first member succeeds.
	sim.command_leave_guild((g.Second as SimUnit).id)
	rec = sim.guilds.get_guild(g.gid)
	if String(rec.leader) != "Officer":
		return "the first member should succeed, got %s" % rec.leader
	sim.command_leave_guild((g.Officer as SimUnit).id)
	sim.command_leave_guild((g.Member as SimUnit).id)
	return true if sim.guilds.get_guild(g.gid).is_empty() else "an empty guild should be removed"


func test_window_offers_only_permitted_controls(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var w := GuildWindow.new()
	w.bind(sim.guilds, g.Leader)
	if w.actions_for("Member") != ["PROMOTE", "TRANSFER", "KICK"] or w.actions_for("Officer") != ["DEMOTE", "TRANSFER", "KICK"]:
		return "leader controls wrong: %s / %s" % [w.actions_for("Member"), w.actions_for("Officer")]
	if not w.actions_for("Leader").is_empty():
		return "no controls on your own row"
	w.bind(sim.guilds, g.Officer)
	if w.actions_for("Member") != ["KICK"] or not w.actions_for("Leader").is_empty():
		return "officer controls wrong: %s / %s" % [w.actions_for("Member"), w.actions_for("Leader")]
	sim.command_guild_promote((g.Leader as SimUnit).id, "Second")
	if not w.actions_for("Second").is_empty():
		return "an officer must not see controls for another officer"
	w.bind(sim.guilds, g.Member)
	var none := w.actions_for("Second").is_empty() and w.actions_for("Officer").is_empty() and w.actions_for("Leader").is_empty()
	w.free()
	return true if none else "members must see no management controls"
