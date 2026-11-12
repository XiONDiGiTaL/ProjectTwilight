extends SceneTree
## Co-op transport test, client side (start coop_host.gd first).
##   godot --headless --path 06_Godot_Project -s res://tests/net/coop_client.gd
## Joins with the code in user://coop_test_code.txt and checks: handshake,
## snapshot, private state, movement, combat, chat, an @command, a map
## transfer and a remote NPC dialog. Prints "CLIENT RESULT: n passed, m failed".

const CODE_FILE := "user://coop_test_code.txt"

var ns: Node
var sim: RemoteSimulation
var res: Node
var passed := 0
var failed := 0
var entered_maps: Array = []
var notices: Array = []
var chats: Array = []
var dialogs: Array = []
var seen_events := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("CLIENT PASS: ", name)
	else:
		failed += 1
		print("CLIENT FAIL: ", name, "  ", detail)


## Pumps frames (ticking the replica) until `cond` is true or `ms` passed.
func _wait(cond: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var last := t0
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		var now := Time.get_ticks_msec()
		if sim != null:
			sim.tick(float(now - last))
			for e in sim.drain_events():
				seen_events[String(e.type)] = int(seen_events.get(String(e.type), 0)) + 1
				if String(e.type) == "damage" and sim.units.has(int(e.src)) and int(e.src) == ns.local_unit_id:
					seen_events["my_damage"] = int(seen_events.get("my_damage", 0)) + 1
				if String(e.type) == "despawn":
					sim.forget_unit(int(e.id))
		last = now
		if cond.call():
			return true
	return false


func _attach() -> void:
	sim = RemoteSimulation.new(WorldBuilder.load_gat(res, ns.local_map), ns)
	ns.attach_remote(sim)


func _me() -> SimUnit:
	return sim.units.get(ns.local_unit_id) if sim != null else null


func _run() -> void:
	res = root.get_node("RoResources")
	if not res.is_mounted:
		res.mount()
	ns = root.get_node_or_null("NetSession")
	if ns == null:
		ns = (load("res://scripts/networking/net_session.gd") as GDScript).new()
		ns.name = "NetSession"
		root.add_child(ns)
	ns.map_entered.connect(func(m): entered_maps.append(m))
	ns.notice_received.connect(func(t, _ok): notices.append(t))
	ns.chat_received.connect(func(from, t): chats.append("%s: %s" % [from, t]))
	ns.dialog_received.connect(func(kind, payload): dialogs.append([kind, payload]))
	ns.session_failed.connect(func(m): print("CLIENT: session failed: ", m))
	var code := FileAccess.get_file_as_string(CODE_FILE).strip_edges()
	# A wrong code must be refused before any connection is attempted.
	_check("bad code rejected locally", not ns.join("AAAA-BBBB-CCCC-DDDD-EEEE-FFFF", {}))
	var ch := CharacterRules.new_character("ClientHero", false, 3, 1, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [172, 370]
	ch.map = "prt_fild08"
	var save := {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "character": ch}
	_check("join starts", ns.join(code, save), ns.last_error)
	_check("entered the host's map", await _wait(func(): return not entered_maps.is_empty(), 20000), ns.last_error)
	if entered_maps.is_empty():
		_finish()
		return
	_attach()
	var me := _me()
	_check("snapshot has my unit", me != null and me.name == "ClientHero")
	var host_seen := false
	var monsters := 0
	for id in sim.units:
		var u: SimUnit = sim.units[id]
		host_seen = host_seen or u.name == "HostHero"
		if not u.is_player():
			monsters += 1
	_check("sees the host player and monsters", host_seen and monsters > 0, "host=%s monsters=%d" % [host_seen, monsters])
	_check("private state: starter potions and gear", me.inventory.count(501) == 3 and int(me.equipment.get("weapon", 0)) == 1201,
		"potions=%d eq=%s" % [me.inventory.count(501), me.equipment])
	_check("host greeting arrives as chat", await _wait(func(): return not chats.is_empty(), 5000), str(chats))
	_check("host bow projectile event reaches the client", int(seen_events.get("projectile", 0)) > 0, str(seen_events))

	# Movement is decided by the host and comes back as unit state.
	var start := me.walker.cell
	sim.command_move(me.id, start + Vector2i(4, 0))
	_check("movement replicated", await _wait(func(): return _me().walker.cell.distance_to(start) >= 3, 6000), str(_me().walker.cell))
	# A command with bad argument types is ignored by the host.
	ns.send_command("command_move", ["not a cell"])
	ns.send_command("_kill", [1, 1])

	# Combat: attack the nearest monster until the host reports our damage.
	var target := 0
	var best := 9999.0
	for id in sim.units:
		var u2: SimUnit = sim.units[id]
		if not u2.is_player() and not u2.dead:
			var d := Vector2(u2.walker.cell).distance_to(Vector2(_me().walker.cell))
			if d < best:
				best = d
				target = int(id)
	sim.command_attack(me.id, target)
	_check("combat: my damage events arrive", await _wait(func(): return int(seen_events.get("my_damage", 0)) > 0, 40000),
		"target %d dist %.0f events %s" % [target, best, seen_events])

	# @command runs on the host and answers privately.
	ns.say("@where")
	_check("@command answered by the host", await _wait(func(): return notices.any(func(n): return String(n).contains("Prontera Field")), 5000), str(notices))
	ns.say("hello from the client")
	_check("own chat echoed to the map", await _wait(func(): return chats.any(func(c): return String(c).begins_with("ClientHero:")), 5000), str(chats))

	# Map transfer: the host moves us and sends the new map.
	ns.say("@warp prontera 150 185")
	_check("transferred to prontera", await _wait(func(): return entered_maps.size() >= 2 and String(entered_maps[-1]) == "prontera", 30000), str(entered_maps))
	if entered_maps.size() >= 2:
		_attach()
		_check("new map snapshot has me and script NPCs", _me() != null and sim.npcs.values().any(func(n): return String(n.get("kind", "")) == "script"),
			"npcs=%d" % sim.npcs.size())
		# Remote NPC dialog: talk to a Stylist, pick an option, then cancel.
		var stylist := 0
		for nid in sim.npcs:
			if String(sim.npcs[nid].get("name", "")).begins_with("Stylist"):
				stylist = int(nid)
		var cell: Vector2i = sim.npcs[stylist].cell if stylist != 0 else Vector2i.ZERO
		ns.say("@warp prontera %d %d" % [cell.x, cell.y - 1])
		await _wait(func(): return _me() != null and Vector2(_me().walker.cell).distance_to(Vector2(cell)) <= 3, 5000)
		sim.command_talk(_me().id, stylist)
		_check("NPC dialog shown remotely", await _wait(func(): return not dialogs.is_empty(), 8000), "stylist=%d cell=%s" % [stylist, cell])
		if not dialogs.is_empty():
			var first: Array = dialogs[0]
			_check("dialog is a menu with options", String(first[0]) == "select" or String(first[0]) == "page", str(first))
			var before := dialogs.size()
			ns.answer_dialog(0)
			await _wait(func(): return dialogs.size() > before, 5000)
			ns.answer_dialog(-1)      # cancel whatever came next
			_check("dialog round trip continued", dialogs.size() > before, str(dialogs.size()))
	_finish()


func _finish() -> void:
	print("CLIENT RESULT: %d passed, %d failed" % [passed, failed])
	ns.leave()
	await create_timer(0.5).timeout
	quit(0 if failed == 0 else 1)
