extends Node
## Private co-op session (autoload "NetSession"). Host-authoritative over ENet.
##
## Host: keeps one FieldSimulation per map that has players in it (built by
## WorldBuilder), ticks them, runs every client command through the same
## command_* validation as offline play, and sends each client the changed
## units, ground items and events of its map plus its own private state.
## Client: joins with an invitation code, proves knowledge of the code's
## secret with an HMAC challenge (the secret never travels), and mirrors its
## map in a RemoteSimulation.
##
## Offline play never touches this node (mode == OFFLINE).

signal session_failed(message: String)
signal session_ended(message: String)
signal map_entered(map_name: String)          # client: load / reload the field scene
signal dialog_received(kind: String, payload: Dictionary)   # client: NPC dialog from the host
signal notice_received(text: String, ok: bool)
signal chat_received(from: String, text: String)
signal peers_changed

enum Mode { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 7350
const MAX_PLAYERS := 8
const FRAME_MS := 100.0        # unit state broadcast interval
const SELF_MS := 250.0         # private state check interval
const AUTH_TIMEOUT_MS := 8000.0
const PROTOCOL := 1

var mode := Mode.OFFLINE
var port := DEFAULT_PORT
var invitation_code := ""
var last_error := ""
var code_announced := false     # the host's field scene shows the code once

# --- Host state -----------------------------------------------------------------
var _secret := PackedByteArray()
## map name -> {sim: FieldSimulation, sent: {unit id: hash}, ground_hash: int, acc: float}
var _maps: Dictionary = {}
## peer id -> {authed, nonce, map, unit_id, name, link: PeerLink, self_hash, self_acc, joined_at}
var _peers: Dictionary = {}
var _guilds: GuildStore
var _local_events: Array = []       # events of the host player's map, for the host's own scene
var _seed := 1

# --- Client state ---------------------------------------------------------------
var remote: RemoteSimulation        # attached by the field scene once its map is loaded
var _pending_snapshot: Dictionary = {}
var _pending_frames: Array = []
var _pending_self: Dictionary = {}
var _character: Dictionary = {}     # what we send on entering
var local_unit_id := 0
var local_map := ""


## Waits for one dialog answer from a remote player (host side).
class PeerLink extends RefCounted:
	signal answered(value: Variant)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _end("The host closed the session."))


func is_active() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


# =============================================================================
# Host
# =============================================================================

## Starts hosting. Returns the invitation code ("" on failure; see last_error).
func host(p_port := DEFAULT_PORT, advertised_ip := "") -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS)
	if err != OK:
		last_error = "Could not open port %d (%s)." % [p_port, error_string(err)]
		return ""
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = p_port
	_secret = InvitationCode.new_secret()
	_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF) | 1
	var ip := advertised_ip if advertised_ip != "" else local_ip()
	invitation_code = InvitationCode.encode(ip, p_port, _secret)
	_peers[1] = {"authed": true, "map": "", "unit_id": 0, "name": "", "link": PeerLink.new(), "self_hash": 0, "self_acc": 0.0}
	return invitation_code


## Best LAN address to put in the code (the host can override it for WAN play).
static func local_ip() -> String:
	var best := "127.0.0.1"
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		if s.begins_with("192.168.") or s.begins_with("10."):
			return s
		best = s
	return best


## Host player enters (or re-enters after travel) a map. Returns
## {sim, unit} or {} when the map cannot be built.
func host_enter(character: Dictionary, map_name: String, res: Node) -> Dictionary:
	var u := _place(1, character, map_name, res)
	if u == null:
		return {}
	return {"sim": _maps[map_name].sim, "unit": u}


## The host player's simulation for its current map (after host_enter).
func host_sim() -> FieldSimulation:
	var p: Dictionary = _peers.get(1, {})
	return _maps[p.map].sim if not p.is_empty() and _maps.has(p.get("map", "")) else null


## Moves the host player to another map. The scene reloads afterwards and
## calls host_enter_existing().
func host_travel(to_map: String, to_cell: Vector2i, res: Node) -> bool:
	return _transfer(1, to_map, to_cell, res)


func host_unit() -> SimUnit:
	var p: Dictionary = _peers.get(1, {})
	var sim := host_sim()
	return sim.units.get(int(p.get("unit_id", 0))) if sim != null else null


func host_map() -> String:
	return String(_peers.get(1, {}).get("map", ""))


## Events of the host player's map since the last call (host scene only).
func take_local_events() -> Array:
	var out := _local_events
	_local_events = []
	return out


func player_names() -> Array:
	var out: Array = []
	for pid in _peers:
		if String(_peers[pid].get("name", "")) != "":
			out.append(String(_peers[pid].name))
	return out


func _map_entry(map_name: String, res: Node) -> Dictionary:
	if _maps.has(map_name):
		return _maps[map_name]
	var sim := WorldBuilder.build(res, map_name, _seed + _maps.size() * 7919, null, true, _guilds)
	if sim == null:
		return {}
	if _guilds == null:
		_guilds = sim.guilds          # the first map's store is shared by every later map
	var e := {"sim": sim, "sent": {}, "ground_hash": 0, "acc": 0.0}
	_maps[map_name] = e
	return e


## Adds a peer's character to a map's simulation. Returns the unit or null.
func _place(peer_id: int, character: Dictionary, map_name: String, res: Node) -> SimUnit:
	var e := _map_entry(map_name, res)
	if e.is_empty():
		return null
	var sim: FieldSimulation = e.sim
	var u := sim.add_player_from_save(character)
	if not sim.pathfinder.is_walkable(u.walker.cell):
		var c := u.walker.cell
		if c.x <= 0 or c.y <= 0 or c.x >= sim.gat.width or c.y >= sim.gat.height:
			c = Vector2i(sim.gat.width / 2, sim.gat.height / 2)
		u.walker = GridWalker.new(sim.pathfinder.nearest_walkable(c, 60))
	var p: Dictionary = _peers[peer_id]
	p.map = map_name
	p.unit_id = u.id
	p.name = u.name
	p.self_hash = 0
	peers_changed.emit()
	return u


## Moves a peer's player to another map (portal, script warp, save point).
func _transfer(peer_id: int, to_map: String, to_cell: Vector2i, res: Node) -> bool:
	var p: Dictionary = _peers.get(peer_id, {})
	if p.is_empty() or not MapAliases.exists(res, to_map):
		return false
	var old: Dictionary = _maps.get(String(p.map), {})
	if old.is_empty():
		return false
	var sim: FieldSimulation = old.sim
	var u: SimUnit = sim.units.get(int(p.unit_id))
	if u == null:
		return false
	u.warping = false
	if to_map == String(p.map):
		# Same map: a teleport, not a transfer (the unit keeps its id).
		var c := to_cell
		if c.x <= 0 or c.y <= 0:
			c = Vector2i(sim.gat.width / 2, sim.gat.height / 2)
		u.walker = GridWalker.new(sim.pathfinder.nearest_walkable(c, 60))
		u.target_id = 0
		return true
	var character := _validated(SaveGame.capture(u, to_map), sim)
	character.cell = to_cell
	character.map = to_map
	if u.dead:
		character.hp = 0     # arrive standing, at full health (returned to a save point)
	sim.remove_unit(u.id)
	var nu := _place(peer_id, character, to_map, res)
	if nu == null:
		return false
	if peer_id != 1:
		_send_enter(peer_id)
	return true


## warp "<map>",x,y from an NPC script run for a remote player.
func script_warp_for(peer_id: int, to_map: String, x: int, y: int) -> void:
	var p: Dictionary = _peers.get(peer_id, {})
	if p.is_empty() or not _maps.has(p.get("map", "")):
		return
	var sim: FieldSimulation = _maps[p.map].sim
	var u: SimUnit = sim.units.get(int(p.unit_id))
	if u == null:
		return
	var m := to_map
	var c := Vector2i(x, y)
	if m == "SavePoint" or m == "Save":
		m = u.save_map
		c = u.save_cell
	if m == "Random":
		m = String(p.map)
		c = Vector2i.ZERO
	if m == String(p.map):
		if c.x <= 0 or c.y <= 0:
			c = Vector2i(sim.gat.width / 2, sim.gat.height / 2)
		u.walker = GridWalker.new(sim.pathfinder.nearest_walkable(c, 60))
		return
	if not _transfer(peer_id, m, c, get_node("/root/RoResources")):
		_s_notice.rpc_id(peer_id, "%s is not available on the host." % m, false)


static func _validated(save: Dictionary, sim: FieldSimulation) -> Dictionary:
	var r := SaveGame.validate(JSON.parse_string(JSON.stringify(save)), sim.item_db, ClassInsignia.classes())
	return r.character if r.ok else {}


func _snapshot(map_name: String) -> Dictionary:
	var sim: FieldSimulation = _maps[map_name].sim
	var units: Array = []
	for id in sim.units:
		units.append(NetCodec.unit_state(sim.units[id]))
	var npcs := {}
	for nid in sim.npcs:
		npcs[nid] = (sim.npcs[nid] as Dictionary).duplicate()
	var warps: Array = []
	for w in sim.warps:
		warps.append((w as Dictionary).duplicate())
	return {"map": map_name, "units": units, "npcs": npcs, "warps": warps, "ground": sim.ground_items.duplicate(true)}


func _send_enter(peer_id: int) -> void:
	var p: Dictionary = _peers[peer_id]
	var sim: FieldSimulation = _maps[p.map].sim
	_s_enter.rpc_id(peer_id, String(p.map), int(p.unit_id), _snapshot(String(p.map)),
		NetCodec.self_state(sim, sim.units[int(p.unit_id)]))


func _process(delta: float) -> void:
	if mode != Mode.HOST:
		return
	var ms := delta * 1000.0
	var res := get_node_or_null("/root/RoResources")
	var occupied := {}
	for pid in _peers:
		var m := String(_peers[pid].get("map", ""))
		if m != "":
			occupied[m] = true
	for map_name in occupied:
		var e: Dictionary = _maps[map_name]
		var sim: FieldSimulation = e.sim
		sim.tick(ms)
		var evs := sim.drain_events()
		_host_react(map_name, evs, res)
		e.acc = float(e.acc) + ms
		var due := float(e.acc) >= FRAME_MS
		if due:
			e.acc = 0.0
		if due or not evs.is_empty():
			_broadcast(map_name, evs)
		if String(_peers[1].get("map", "")) == map_name:
			_local_events.append_array(evs)
	# Private state, when it changed.
	for pid in _peers:
		if pid == 1:
			continue
		var p: Dictionary = _peers[pid]
		if String(p.get("map", "")) == "" or not _maps.has(p.map):
			if not bool(p.authed) and Time.get_ticks_msec() - float(p.get("joined_at", 0.0)) > AUTH_TIMEOUT_MS:
				_kick(pid, "Authentication timed out.")
			continue
		p.self_acc = float(p.self_acc) + ms
		if float(p.self_acc) < SELF_MS:
			continue
		p.self_acc = 0.0
		var sim2: FieldSimulation = _maps[p.map].sim
		var u: SimUnit = sim2.units.get(int(p.unit_id))
		if u == null:
			continue
		var st := NetCodec.self_state(sim2, u)
		var h := st.hash()
		if h != int(p.self_hash):
			p.self_hash = h
			_s_self.rpc_id(pid, st)


## Host-side consequences of events that concern remote players.
func _host_react(map_name: String, evs: Array, res: Node) -> void:
	for ev in evs:
		var t := String(ev.get("type", ""))
		if t != "warp" and t != "npc_open" and t != "revive":
			continue
		var pid := _peer_of(map_name, int(ev.get("id", 0)))
		if pid <= 1:
			continue     # the host's own scene handles the host player
		match t:
			"warp":
				if not _transfer(pid, String(ev.to_map), ev.to_cell, res):
					var sim: FieldSimulation = _maps[map_name].sim
					var u: SimUnit = sim.units.get(int(ev.id))
					if u:
						u.warping = false
					_s_notice.rpc_id(pid, "%s is not available on the host." % String(ev.to_map), false)
			"revive":
				if ev.has("to_map"):
					_transfer(pid, String(ev.to_map), ev.to_cell, res)
			"npc_open":
				var sim2: FieldSimulation = _maps[map_name].sim
				var npc: Dictionary = sim2.npcs.get(int(ev.npc), {})
				if String(npc.get("kind", "")) == "script":
					_run_script_for(pid, map_name, npc, res)


func _peer_of(map_name: String, unit_id: int) -> int:
	for pid in _peers:
		var p: Dictionary = _peers[pid]
		if String(p.get("map", "")) == map_name and int(p.get("unit_id", 0)) == unit_id:
			return int(pid)
	return 0


func _broadcast(map_name: String, evs: Array) -> void:
	var e: Dictionary = _maps[map_name]
	var sim: FieldSimulation = e.sim
	var targets: Array = []
	for pid in _peers:
		if pid != 1 and String(_peers[pid].get("map", "")) == map_name:
			targets.append(pid)
	var sent: Dictionary = e.sent
	var changed: Array = []
	for id in sim.units:
		var st := NetCodec.unit_state(sim.units[id])
		var h := st.hash()
		if int(sent.get(id, 0)) != h:
			sent[id] = h
			changed.append(st)
	for id in sent.keys():
		if not sim.units.has(id):
			sent.erase(id)
	var ground: Variant = null
	var gh := sim.ground_items.hash()
	if gh != int(e.ground_hash):
		e.ground_hash = gh
		ground = sim.ground_items.duplicate(true)
	if targets.is_empty() or (changed.is_empty() and ground == null and evs.is_empty()):
		return
	for pid in targets:
		_s_frame.rpc_id(pid, changed, ground, evs)


func _run_script_for(peer_id: int, map_name: String, npc: Dictionary, res: Node) -> void:
	var p: Dictionary = _peers.get(peer_id, {})
	if p.is_empty() or bool(p.get("script_running", false)):
		return
	var world := WorldBuilder.world(res)
	var def := world.find_npc(String(npc.get("script", "")))
	var sim: FieldSimulation = _maps[map_name].sim
	var u: SimUnit = sim.units.get(int(p.unit_id))
	if def.is_empty() or u == null:
		return
	p.script_running = true
	var host_ui := NetNpcHost.new(self, peer_id, p.link)
	var vm := RaInterpreter.new(world, host_ui, sim, u, def)
	await vm.run()
	if _peers.has(peer_id):
		_peers[peer_id].script_running = false


func _kick(peer_id: int, reason: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_s_kick.rpc_id(peer_id, reason)
	await get_tree().create_timer(0.3).timeout
	if multiplayer.multiplayer_peer != null and _peers.has(peer_id):
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if mode != Mode.HOST:
		return
	var nonce := Crypto.new().generate_random_bytes(16)
	_peers[peer_id] = {"authed": false, "nonce": nonce, "map": "", "unit_id": 0, "name": "", "link": PeerLink.new(),
		"self_hash": 0, "self_acc": 0.0, "joined_at": float(Time.get_ticks_msec())}
	_s_challenge.rpc_id(peer_id, PROTOCOL, nonce)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.HOST or not _peers.has(peer_id):
		return
	var p: Dictionary = _peers[peer_id]
	_peers.erase(peer_id)      # first: the departed peer can no longer be reached
	(p.link as PeerLink).answered.emit(255)     # unblock a waiting NPC script
	if String(p.get("map", "")) != "" and _maps.has(p.map):
		var sim: FieldSimulation = _maps[p.map].sim
		sim.close_shop(int(p.unit_id))
		sim.close_storage(int(p.unit_id))
		sim.close_guild_storage(int(p.unit_id))
		sim.remove_unit(int(p.unit_id))
	if String(p.get("name", "")) != "":
		_announce(String(p.get("map", "")), "%s left the session." % String(p.name))
	peers_changed.emit()


func _announce(map_name: String, text: String) -> void:
	for pid in _peers:
		if pid == 1:
			notice_received.emit(text, true)
		elif String(_peers[pid].get("map", "")) != "":
			_s_notice.rpc_id(pid, text, true)


static func proof(secret: PackedByteArray, nonce: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret, nonce)


# --- Host: messages from clients --------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _c_auth(digest: PackedByteArray) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var p: Dictionary = _peers.get(pid, {})
	if mode != Mode.HOST or p.is_empty() or bool(p.authed):
		return
	if digest != proof(_secret, p.nonce):
		_kick(pid, "The invitation code is not valid for this session.")
		return
	p.authed = true
	_s_auth_ok.rpc_id(pid)


@rpc("any_peer", "call_remote", "reliable")
func _c_enter(save: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var p: Dictionary = _peers.get(pid, {})
	if mode != Mode.HOST or p.is_empty() or not bool(p.authed) or String(p.map) != "":
		return
	var res := get_node("/root/RoResources")
	var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	item_db.erase("_provenance")
	var r := SaveGame.validate(save, item_db, ClassInsignia.classes())
	if not r.ok:
		_kick(pid, "The host could not read that character: %s" % String(r.error))
		return
	var character: Dictionary = r.character
	for other in _peers:
		if other != pid and String(_peers[other].get("name", "")) == String(character.name):
			_kick(pid, "A character named %s is already in the session." % String(character.name))
			return
	var map_name := String(character.get("map", ""))
	if map_name == "" or not MapAliases.exists(res, map_name):
		map_name = SimUnit.HUB_MAP
		character.cell = SimUnit.HUB_CELL
	if _place(pid, character, map_name, res) == null:
		_kick(pid, "The host could not load %s." % map_name)
		return
	_send_enter(pid)
	_announce(map_name, "%s joined the session." % String(character.name))


@rpc("any_peer", "call_remote", "reliable")
func _c_command(name: String, args: Array) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var p: Dictionary = _peers.get(pid, {})
	if mode != Mode.HOST or p.is_empty() or String(p.get("map", "")) == "" or not NetCodec.valid_command(name, args):
		return
	var sim: FieldSimulation = _maps[p.map].sim
	if not sim.units.has(int(p.unit_id)):
		return
	var full: Array = [int(p.unit_id)]
	full.append_array(args)
	sim.callv(name, full)


@rpc("any_peer", "call_remote", "reliable")
func _c_dialog(value: Variant) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var p: Dictionary = _peers.get(pid, {})
	if mode != Mode.HOST or p.is_empty() or not (value is int or value is String):
		return
	(p.link as PeerLink).answered.emit(value)


@rpc("any_peer", "call_remote", "reliable")
func _c_chat(text: String) -> void:
	var pid := multiplayer.get_remote_sender_id()
	_host_chat(pid, text)


## Chat and @commands on the host (also used for the host player's own line).
func _host_chat(pid: int, text: String) -> void:
	var p: Dictionary = _peers.get(pid, {})
	var line := text.strip_edges().left(200)
	if mode != Mode.HOST or p.is_empty() or line == "" or String(p.get("map", "")) == "":
		return
	var sim: FieldSimulation = _maps[p.map].sim
	var u: SimUnit = sim.units.get(int(p.unit_id))
	if u == null:
		return
	if line.begins_with("@"):
		var r := ChatCommands.execute(sim, u, line)
		if r.has("action"):
			var a: Dictionary = r.action
			if pid == 1:
				host_action.emit(a)      # the host's own scene performs it
			elif String(a.get("kind", "")) == "warp":
				_transfer(pid, String(a.map), Vector2i(int(a.x), int(a.y)), get_node("/root/RoResources"))
		var msg := String(r.get("text", ""))
		if msg != "":
			if pid == 1:
				notice_received.emit(msg, bool(r.get("ok", true)))
			else:
				_s_notice.rpc_id(pid, msg, bool(r.get("ok", true)))
		return
	for other in _peers:
		if String(_peers[other].get("map", "")) == "":
			continue
		if other == 1:
			chat_received.emit(u.name, line)
		else:
			_s_chat.rpc_id(other, u.name, line)


signal host_action(action: Dictionary)   # host player's @warp etc. (the scene performs it)


# =============================================================================
# Client
# =============================================================================

## Joins the session described by `code` with a save-shaped character.
func join(code: String, character_save: Dictionary) -> bool:
	leave()
	var d := InvitationCode.decode(code)
	if not bool(d.ok):
		last_error = String(d.error)
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(String(d.ip), int(d.port))
	if err != OK:
		last_error = "Could not start the connection (%s)." % error_string(err)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_secret = d.secret
	_character = character_save
	return true


## The field scene attaches its replica once the map is loaded; buffered
## host data is applied in order.
func attach_remote(sim: RemoteSimulation) -> void:
	remote = sim
	sim.local_unit_id = local_unit_id
	sim.apply_snapshot(_pending_snapshot)
	if not _pending_self.is_empty():
		sim.apply_self(_pending_self)
	for f in _pending_frames:
		sim.apply_frame(f[0], f[1], f[2])
	_pending_frames.clear()


func send_command(name: String, args: Array) -> void:
	if mode == Mode.CLIENT:
		_c_command.rpc_id(1, name, args)


func answer_dialog(value: Variant) -> void:
	if mode == Mode.CLIENT:
		_c_dialog.rpc_id(1, value)


## Chat line or @command from the local player.
func say(text: String) -> void:
	if mode == Mode.CLIENT:
		_c_chat.rpc_id(1, text)
	elif mode == Mode.HOST:
		_host_chat(1, text)


func _on_connected() -> void:
	pass   # the host speaks first (_s_challenge)


@rpc("authority", "call_remote", "reliable")
func _s_challenge(protocol: int, nonce: PackedByteArray) -> void:
	if protocol != PROTOCOL:
		_fail("The host runs a different version of Project Twilight.")
		return
	_c_auth.rpc_id(1, proof(_secret, nonce))


@rpc("authority", "call_remote", "reliable")
func _s_auth_ok() -> void:
	_c_enter.rpc_id(1, _character)


@rpc("authority", "call_remote", "reliable")
func _s_enter(map_name: String, unit_id: int, snapshot: Dictionary, self_state: Dictionary) -> void:
	remote = null
	local_map = map_name
	local_unit_id = unit_id
	_pending_snapshot = snapshot
	_pending_self = self_state
	_pending_frames.clear()
	map_entered.emit(map_name)


@rpc("authority", "call_remote", "reliable")
func _s_frame(changed: Array, ground: Variant, evs: Array) -> void:
	if remote != null:
		remote.apply_frame(changed, ground, evs)
	else:
		_pending_frames.append([changed, ground, evs])


@rpc("authority", "call_remote", "reliable")
func _s_self(state: Dictionary) -> void:
	_pending_self = state
	if remote != null:
		remote.apply_self(state)


@rpc("authority", "call_remote", "reliable")
func _s_dialog(kind: String, payload: Dictionary) -> void:
	dialog_received.emit(kind, payload)


@rpc("authority", "call_remote", "reliable")
func _s_notice(text: String, ok: bool) -> void:
	notice_received.emit(text, ok)


@rpc("authority", "call_remote", "reliable")
func _s_chat(from: String, text: String) -> void:
	chat_received.emit(from, text)


@rpc("authority", "call_remote", "reliable")
func _s_kick(reason: String) -> void:
	_fail(reason)


# =============================================================================
# Shared
# =============================================================================

## Leaves or closes the session and returns to offline mode.
func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	invitation_code = ""
	code_announced = false
	_maps.clear()
	_peers.clear()
	_guilds = null
	_local_events.clear()
	remote = null
	_pending_snapshot = {}
	_pending_frames.clear()
	_pending_self = {}
	local_unit_id = 0
	local_map = ""


func _fail(message: String) -> void:
	last_error = message
	var was_active := mode != Mode.OFFLINE
	leave()
	if was_active:
		session_failed.emit(message)


func _end(message: String) -> void:
	last_error = message
	leave()
	session_ended.emit(message)
