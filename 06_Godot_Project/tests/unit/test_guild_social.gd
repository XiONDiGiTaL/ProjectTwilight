extends RefCounted
## Guild social features: the message of the day, its permissions and
## persistence, and guild chat delivered only to online guild members.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const TEST_PATH := "user://test_guild_social.json"


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
	var sim := FieldSimulation.new(_gat(), 73, RuleConfig.new(), TEST_PATH)
	sim.map_name = "prontera"
	sim.map_info = sim.map_db.get("prontera", {})
	return sim


## Leader, Officer, Member and Outsider online; only the first three are guilded.
func _guild(sim: FieldSimulation) -> Dictionary:
	var out := {}
	var names := ["Leader", "Officer", "Member", "Outsider"]
	for i in names.size():
		out[names[i]] = sim.add_player(names[i], Vector2i(40 + i, 40), FLAT)
	var leader: SimUnit = out.Leader
	sim.command_create_guild(leader.id, "Social Guard")
	for n in ["Officer", "Member"]:
		sim.command_guild_invite(leader.id, n)
		sim.command_guild_accept((out[n] as SimUnit).id, leader.guild_id)
	sim.command_guild_promote(leader.id, "Officer")
	out.gid = leader.guild_id
	sim.drain_events()
	return out


func test_motd_persists_and_cleans(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	if sim.guilds.motd_of(g.gid) != "":
		return "a new guild should have no MOTD"
	if not sim.command_guild_set_motd(leader.id, "  Raid at 20:00\nBring potions  "):
		return "the leader could not set the MOTD"
	var expected := "Raid at 20:00 Bring potions"
	if sim.guilds.motd_of(g.gid) != expected:
		return "MOTD was not cleaned: %s" % sim.guilds.motd_of(g.gid)
	var reloaded := GuildStore.new(TEST_PATH, sim.item_db)
	if reloaded.motd_of(g.gid) != expected:
		return "MOTD did not survive a reload"
	if not sim.command_guild_set_motd(leader.id, ""):
		return "the leader could not clear the MOTD"
	return true if sim.guilds.motd_of(g.gid) == "" else "the MOTD was not cleared"


func test_motd_permissions(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var officer: SimUnit = g.Officer
	var member: SimUnit = g.Member
	var outsider: SimUnit = g.Outsider
	if not sim.command_guild_set_motd(officer.id, "Officers can edit"):
		return "an officer could not set the MOTD"
	if sim.command_guild_set_motd(member.id, "Members cannot"):
		return "a member changed the MOTD"
	if sim.guilds.motd_of(g.gid) != "Officers can edit":
		return "a rejected member changed the stored MOTD"
	if sim.command_guild_set_motd(outsider.id, "Not a member"):
		return "a guildless player changed the MOTD"
	if GuildStore.can("member", "motd") or not GuildStore.can("officer", "motd"):
		return "MOTD permission matrix is wrong"
	if not GuildStore.can("member", "chat") or GuildStore.can("", "chat"):
		return "chat permission matrix is wrong"
	return true


func test_motd_shown_when_joining(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	var outsider: SimUnit = g.Outsider
	sim.command_guild_set_motd(leader.id, "Welcome aboard.")
	sim.command_guild_invite(leader.id, "Outsider")
	if not sim.command_guild_accept(outsider.id, g.gid):
		return "the invitation was not accepted"
	var notices: Array = sim.drain_events().filter(func(e):
		return e.type == "guild" and e.id == outsider.id and String(e.get("text", "")).contains("Welcome aboard."))
	return true if not notices.is_empty() else "the MOTD was not shown on join"


func test_guild_chat_members_only(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	var outsider: SimUnit = g.Outsider
	if not sim.command_guild_chat(leader.id, "  Hello  guild  "):
		return "the leader could not send guild chat"
	var chat: Array = sim.drain_events().filter(func(e): return e.type == "chat")
	if chat.size() != 3:
		return "expected three guild recipients, got %d" % chat.size()
	var got := {}
	for e in chat:
		if String(e.channel) != "guild" or String(e.from) != "Leader" or String(e.text) != "Hello  guild" or String(e.guild_id) != g.gid:
			return "chat event fields are wrong: %s" % [e]
		got[e.id] = true
	for n in ["Leader", "Officer", "Member"]:
		if not got.has((g[n] as SimUnit).id):
			return "%s did not receive guild chat" % n
	if got.has(outsider.id):
		return "a non-member received guild chat"
	if sim.command_guild_chat(outsider.id, "I am not in the guild"):
		return "a non-member sent guild chat"
	return true if sim.drain_events().filter(func(e): return e.type == "chat").is_empty() else "a rejected message still reached members"


func test_guild_chat_command(_t) -> Variant:
	_clean()
	var sim := _field()
	var g := _guild(sim)
	var leader: SimUnit = g.Leader
	var result := ChatCommands.execute(sim, leader, "/g Hello from the command line")
	if not result.ok or String(result.text) != "":
		return "the /g command should be silent and delegate to the simulation: %s" % [result]
	var chat: Array = sim.drain_events().filter(func(e): return e.type == "chat")
	if chat.size() != 3:
		return "the /g command did not reach all members"
	if ChatCommands.execute(sim, leader, "/g").ok:
		return "an empty /g should show usage"
	var plain := ChatCommands.execute(sim, leader, "hello there")
	if not plain.ok or not String(plain.text).contains("hello there"):
		return "plain speech should still echo"
	var help := ChatCommands.execute(sim, leader, "@help")
	if not String(help.text).contains("/g"):
		return "@help should mention /g"
	var outsider: SimUnit = g.Outsider
	ChatCommands.execute(sim, outsider, "/g not allowed")
	return true if sim.drain_events().filter(func(e): return e.type == "chat").is_empty() else "a guildless /g reached members"
