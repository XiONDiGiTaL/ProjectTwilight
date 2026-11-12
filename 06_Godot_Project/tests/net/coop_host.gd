extends SceneTree
## Co-op transport test, host side (pair with coop_client.gd).
##   godot --headless --path 06_Godot_Project -s res://tests/net/coop_host.gd
## Hosts on 127.0.0.1:7391, enters prt_fild08 with a fresh character, writes
## the invitation code to user://coop_test_code.txt and runs until the client
## has come and gone (or 70 s).

const PORT := 7391
const CODE_FILE := "user://coop_test_code.txt"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var res := root.get_node("RoResources")
	if not res.is_mounted:
		res.mount()
	var ns: Node = root.get_node_or_null("NetSession")
	if ns == null:
		ns = (load("res://scripts/networking/net_session.gd") as GDScript).new()
		ns.name = "NetSession"
		root.add_child(ns)
	var code: String = ns.host(PORT, "127.0.0.1")
	if code == "":
		print("HOST FAIL: ", ns.last_error)
		quit(1)
		return
	var ch := CharacterRules.new_character("HostHero", true, 2, 0, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [170, 370]
	ch.map = "prt_fild08"
	var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	var r := SaveGame.validate({"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "character": ch}, item_db, ClassInsignia.classes())
	var entered: Dictionary = ns.host_enter(r.character, "prt_fild08", res)
	if entered.is_empty():
		print("HOST FAIL: could not build prt_fild08")
		quit(1)
		return
	var sim: FieldSimulation = entered.sim
	var me: SimUnit = entered.unit
	print("HOST: up, code ", code, " units ", sim.units.size(), " me ", me.id)
	ns.chat_received.connect(func(from, text): print("HOST: chat <", from, "> ", text))
	ns.notice_received.connect(func(text, _ok): print("HOST: notice ", text))
	var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	var seen_client := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 70000:
		await process_frame
		ns.take_local_events()
		var names: Array = ns.player_names()
		if names.size() > 1 and not seen_client:
			seen_client = true
			print("HOST: players ", names)
			# Let the guest finish attaching its replica before the one-shot event.
			await create_timer(1.0).timeout
			# Regression: the client must receive the host's projectile event, not
			# just the resulting damage. Turn the host into an Archer and fire once.
			me.job_level = 10
			me.skills["NV_BASIC"] = 9
			var archer_ok: bool = sim.command_job_change(me.id, "archer")
			print("HOST: projectile regression archer=", archer_ok)
			if archer_ok:
				var dummy := sim.add_monster("1002", sim.pathfinder.nearest_walkable(me.walker.cell + Vector2i(5, 0), 4))
				dummy.max_hp = 999999
				dummy.hp = 999999
				dummy.walker.walk_speed = 1e9
				sim._attack(me, dummy)
			ns.say("welcome to the session")
		if seen_client and names.size() == 1:
			print("HOST: client left; maps ", ns._maps.keys())
			break
	print("HOST: done seen_client=", seen_client)
	ns.leave()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
	quit(0 if seen_client else 1)
