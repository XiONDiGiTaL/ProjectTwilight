class_name RemoteSimulation
extends FieldSimulation
## A co-op client's replica of the host's simulation of one map.
##
## It is a FieldSimulation so the field scene, HUD, minimap and windows work
## unchanged, but it never decides anything: units, ground items and events
## come from the host (NetCodec), every command_* is forwarded to the host,
## and tick() only moves walkers and timers between host updates.

## Object with send_command(name: String, args: Array) (NetSession).
var net: Object
var local_unit_id := 0


func _init(p_gat: GatFile, p_net: Object) -> void:
	super._init(p_gat, 1)
	net = p_net
	guilds = GuildStore.new("", item_db)   # read-only replica; never touches the player's guild file


## Installs the host's snapshot of the map. Emits spawn events so the scene
## builds its views exactly as it does offline.
func apply_snapshot(snap: Dictionary) -> void:
	map_name = String(snap.get("map", ""))
	map_info = map_db.get(map_name, {})
	units.clear()
	npcs.clear()
	ground_items.clear()
	warps.clear()
	events.clear()
	for w in snap.get("warps", []):
		warps.append((w as Dictionary).duplicate())
	var raw_npcs: Dictionary = snap.get("npcs", {})
	for nid in raw_npcs:
		npcs[int(nid)] = (raw_npcs[nid] as Dictionary).duplicate()
		events.append({"type": "npc_spawn", "npc": int(nid)})
	for d in snap.get("units", []):
		NetCodec.apply_unit(self, d)
		events.append({"type": "spawn", "id": int(d.id)})
	_set_ground(snap.get("ground", {}))
	for gid in ground_items:
		events.append({"type": "drop", "ground": gid})


## One host update: changed units, removed unit ids, ground items (or null
## when unchanged) and the host's events in order.
func apply_frame(changed: Array, ground: Variant, host_events: Array) -> void:
	for d in changed:
		var known := units.has(int(d.id))
		if NetCodec.apply_unit(self, d) and known:
			events.append({"type": "appearance", "id": int(d.id)})
	if ground is Dictionary:
		_set_ground(ground)
	for e in host_events:
		if String(e.get("type", "")) == "despawn":
			events.append(e)          # the scene frees the view first ...
			continue
		events.append(e)


## Called by the scene after it handled a despawn event.
func forget_unit(unit_id: int) -> void:
	units.erase(unit_id)


func apply_self(c: Dictionary) -> void:
	var u: SimUnit = units.get(local_unit_id)
	if u == null:
		return
	NetCodec.apply_self(self, u, c)
	# Derived numbers the HUD reads (ATK, weight bonus, masteries); HP / SP come from the unit state.
	var hp := u.hp
	var sp := u.sp
	var mhp := u.max_hp
	var msp := u.max_sp
	_recalc_player(u)
	u.max_hp = mhp
	u.max_sp = msp
	u.hp = hp
	u.sp = sp
	events.append({"type": "stats", "id": u.id})
	events.append({"type": "inventory", "id": u.id})


func _set_ground(g: Dictionary) -> void:
	var fresh := {}
	for gid in g:
		fresh[int(gid)] = (g[gid] as Dictionary).duplicate()
	ground_items = fresh


## Interpolation only: walkers and visible timers advance; nothing is decided.
func tick(ms: float) -> void:
	for id in units:
		var u: SimUnit = units[id]
		u.walker.advance(ms)
		if u.cast_skill != "":
			u.cast_left = maxf(0.0, u.cast_left - ms)
		u.skill_delay = maxf(0.0, u.skill_delay - ms)
	for gid in ground_items:
		ground_items[gid].age = float(ground_items[gid].get("age", 0.0)) + ms


func _send(name: String, args: Array) -> bool:
	if net != null:
		net.send_command(name, args)
	return true


# --- Every command is a request to the host --------------------------------------

func command_move(_u: int, cell: Vector2i) -> bool: return _send("command_move", [cell])
func command_attack(_u: int, target_id: int) -> bool: return _send("command_attack", [target_id])
func command_pickup(_u: int, ground_id: int) -> bool: return _send("command_pickup", [ground_id])
func command_use_item(_u: int, index: int) -> bool: return _send("command_use_item", [index])
func command_equip(_u: int, index: int) -> bool: return _send("command_equip", [index])
func command_unequip(_u: int, slot: String) -> bool: return _send("command_unequip", [slot])
func command_talk(_u: int, npc_id: int) -> bool: return _send("command_talk", [npc_id])
func command_buy(_u: int, item_id: int, amount: int) -> bool: return _send("command_buy", [item_id, amount])
func command_sell(_u: int, index: int, amount: int) -> bool: return _send("command_sell", [index, amount])
func command_open_storage(_u: int, npc_id: int, _fee := true) -> bool: return _send("command_open_storage", [npc_id])
func command_storage_deposit(_u: int, index: int, amount: int) -> bool: return _send("command_storage_deposit", [index, amount])
func command_storage_withdraw(_u: int, index: int, amount: int) -> bool: return _send("command_storage_withdraw", [index, amount])
func command_create_guild(_u: int, guild_name: String) -> bool: return _send("command_create_guild", [guild_name])
func command_guild_invite(_u: int, target_name: String) -> bool: return _send("command_guild_invite", [target_name])
func command_guild_accept(_u: int, gid: String) -> bool: return _send("command_guild_accept", [gid])
func command_guild_decline(_u: int, gid: String) -> bool: return _send("command_guild_decline", [gid])
func command_guild_kick(_u: int, target_name: String) -> bool: return _send("command_guild_kick", [target_name])
func command_guild_promote(_u: int, target_name: String) -> bool: return _send("command_guild_promote", [target_name])
func command_guild_demote(_u: int, target_name: String) -> bool: return _send("command_guild_demote", [target_name])
func command_guild_transfer(_u: int, target_name: String) -> bool: return _send("command_guild_transfer", [target_name])
func command_guild_disband(_u: int) -> bool: return _send("command_guild_disband", [])
func command_leave_guild(_u: int) -> bool: return _send("command_leave_guild", [])
func command_open_guild_storage(_u: int, npc_id: int) -> bool: return _send("command_open_guild_storage", [npc_id])
func command_guild_deposit(_u: int, index: int, amount: int) -> bool: return _send("command_guild_deposit", [index, amount])
func command_guild_withdraw(_u: int, index: int, amount: int) -> bool: return _send("command_guild_withdraw", [index, amount])
func command_learn_skill(_u: int, code: String) -> bool: return _send("command_learn_skill", [code])
func command_job_change(_u: int, job: String) -> bool: return _send("command_job_change", [job])
func command_use_skill(_u: int, code: String, target_id: int = 0) -> bool: return _send("command_use_skill", [code, target_id])
func command_sit(_u: int) -> bool: return _send("command_sit", [])
func command_raise_stat(_u: int, stat: String) -> bool: return _send("command_raise_stat", [stat])


func close_shop(_u: int) -> void:
	_send("close_shop", [])


func close_storage(_u: int) -> void:
	_send("close_storage", [])


func close_guild_storage(_u: int) -> void:
	_send("close_guild_storage", [])
