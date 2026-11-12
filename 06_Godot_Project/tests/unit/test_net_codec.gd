extends RefCounted
## Co-op wire forms: command whitelist, unit state and private state round trips.


static func _open_gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func test_command_whitelist(_t) -> Variant:
	if not NetCodec.valid_command("command_move", [Vector2i(3, 4)]):
		return "a well-formed move was refused"
	if NetCodec.valid_command("command_move", ["3,4"]) or NetCodec.valid_command("command_move", []):
		return "bad argument types or counts must be refused"
	for name in ["_kill", "add_player", "script_get_item", "remove_unit", "tick", "command_nope"]:
		if NetCodec.valid_command(name, []) or NetCodec.valid_command(name, [1]):
			return "%s must not be callable by a client" % name
	if NetCodec.valid_command("command_create_guild", ["x".repeat(65)]):
		return "over-long strings must be refused"
	for name in NetCodec.CLIENT_COMMANDS:
		if not NetCodec.COMMAND_ARGS.has(name):
			return "%s has no argument types" % name
		if not FieldSimulation.new(_open_gat(), 1).has_method(name):
			return "%s is not a simulation method" % name
	return true


func test_unit_state_round_trip(_t) -> Variant:
	var host := FieldSimulation.new(_open_gat(), 3)
	var p := host.add_player("Wire", Vector2i(10, 10), {"str": 9, "agi": 8, "vit": 7, "int": 6, "dex": 5, "luk": 4})
	p.hair_style = 7
	p.hair_color = 3
	p.cloth_color = 2
	var m := host.add_monster("1002", Vector2i(14, 12))
	host.command_move(p.id, Vector2i(16, 10))
	host.tick(120.0)
	var replica := RemoteSimulation.new(_open_gat(), null)
	if NetCodec.apply_unit(replica, NetCodec.unit_state(p)):
		return "a new unit is not an appearance change"
	NetCodec.apply_unit(replica, NetCodec.unit_state(m))
	var rp: SimUnit = replica.units.get(p.id)
	var rm: SimUnit = replica.units.get(m.id)
	if rp == null or rm == null:
		return "units missing on the replica"
	if rp.name != "Wire" or not rp.is_player() or rp.hair_style != 7 or rp.cloth_color != 2:
		return "player look lost"
	if rm.is_player() or rm.name != m.name or rm.max_hp != m.max_hp or rm.data.is_empty():
		return "monster state lost"
	if rp.walker.cell != p.walker.cell or rp.walker.path.size() != p.walker.path.size():
		return "walker not mirrored: %s vs %s" % [rp.walker.cell, p.walker.cell]
	# The replica keeps walking between host updates.
	var before := rp.walker.position()
	replica.tick(300.0)
	if rp.walker.position() == before:
		return "the replica should interpolate movement"
	p.hair_color = 5
	return true if NetCodec.apply_unit(replica, NetCodec.unit_state(p)) else "a changed look must be reported"


func test_private_state_round_trip(_t) -> Variant:
	var host := FieldSimulation.new(_open_gat(), 4)
	var p := host.add_player("Owner", Vector2i(10, 10), {"str": 9, "agi": 8, "vit": 7, "int": 6, "dex": 5, "luk": 4})
	p.inventory.add(501, 7, host.item_db, p.max_weight())
	p.zeny = 4321
	p.skills.NV_BASIC = 6
	p.status_points = 12
	var replica := RemoteSimulation.new(_open_gat(), null)
	replica.local_unit_id = p.id
	NetCodec.apply_unit(replica, NetCodec.unit_state(p))
	# The state crosses the wire as plain data.
	var wire: Variant = bytes_to_var(var_to_bytes(NetCodec.self_state(host, p)))
	replica.apply_self(wire)
	var rp: SimUnit = replica.units[p.id]
	if rp.inventory.count(501) != 7 or rp.zeny != 4321:
		return "inventory or zeny lost: %d potions, %d z" % [rp.inventory.count(501), rp.zeny]
	if int(rp.skills.get("NV_BASIC", 0)) != 6 or rp.status_points != 12 or int(rp.stats.str) != 9:
		return "skills or stats lost"
	return true if not replica.guilds.persistent else "a replica guild store must never write to disk"


func test_replica_forwards_commands(_t) -> Variant:
	var sent: Array = []
	var net := _FakeNet.new(sent)
	var replica := RemoteSimulation.new(_open_gat(), net)
	replica.command_move(1, Vector2i(5, 6))
	replica.command_use_skill(1, "SM_BASH", 9)
	replica.close_shop(1)
	if sent.size() != 3:
		return "expected 3 forwarded commands, got %d" % sent.size()
	for s in sent:
		if not NetCodec.valid_command(String(s[0]), s[1]):
			return "%s is forwarded in a form the host would refuse" % String(s[0])
	return true if replica.units.is_empty() else "a replica must not act on its own"


class _FakeNet extends RefCounted:
	var log: Array

	func _init(p_log: Array) -> void:
		log = p_log

	func send_command(name: String, args: Array) -> void:
		log.append([name, args])
