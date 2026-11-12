extends SceneTree
## Co-op with the real field scene, host side (pair with coop_scene_client.gd).
##   godot --path 06_Godot_Project -s res://tests/net/coop_scene_host.gd   (not headless)
## Hosts on 127.0.0.1:7392 with a throwaway character, plays the field scene
## as the host, waits for the client, follows it to Prontera through a real
## map travel and saves screenshots to user://captures/coop_host_*.png.

const PORT := 7392
const CODE_FILE := "user://coop_scene_code.txt"

var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		failed += 1
	print("HOST %s: %s  %s" % ["PASS" if ok else "FAIL", name, "" if ok else detail])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/%s.png" % name)


func _wait(cond: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		if cond.call():
			return true
	return false


func _field() -> Node:
	var f := current_scene
	return f if f != null and f.get("player") != null and f.get("hud") != null else null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var tmp := "user://coop_host_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	var ch := CharacterRules.new_character("HostHero", true, 2, 0, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [170, 370]
	ch.map = "prt_fild08"
	ch.script_vars = {"TW_TRAIN_ASKED": {"0": 1}}
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var ns: Node = root.get_node("NetSession")
	var code: String = ns.host(PORT, "127.0.0.1")
	_check("host opens the port", code != "", ns.last_error)
	root.get_node("GameSession").slot = "slot1"
	change_scene_to_file("res://scenes/game/field.tscn")
	_check("field scene runs as host", await _wait(func(): return _field() != null, 20000))
	if _field() == null:
		quit(1)
		return
	var field := _field()
	_check("host scene presents the map", field.views.size() > 3 and field.views.has(field.player.id), "views=%d" % field.views.size())
	var start: Vector2i = field.player.walker.cell
	field.walk_to(start + Vector2i(3, 0))
	_check("host walks (ticked by NetSession)", await _wait(func(): return _field().player.walker.cell != start, 5000))
	var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("HOST: waiting for the client, code ", code)
	_check("client joins", await _wait(func(): return ns.player_names().size() > 1, 60000))
	var seen := await _wait(func():
		for v in _field().views.values():
			if v.unit != null and v.unit.name == "ClientHero":
				return true
		return false, 8000)
	_check("host sees the client's character", seen)
	ns.say("welcome to the session")
	await _wait(func(): return false, 2500)
	await _shot("coop_host_1_field")
	# Follow the client to Prontera when it leaves the map (a real host travel).
	var left := await _wait(func():
		for v in _field().views.values():
			if v.unit != null and v.unit.name == "ClientHero":
				return false
		return true, 60000)
	_check("client's view is removed when it changes map", left)
	_field()._on_chat_submit("@warp prontera 156 187")
	_check("host travels to prontera", await _wait(func(): return _field() != null and _field().map_name == "prontera", 30000))
	if _field() != null:
		var together := await _wait(func():
			for v in _field().views.values():
				if v.unit != null and v.unit.name == "ClientHero":
					return true
			return false, 10000)
		_check("host and client meet in prontera", together)
		await _wait(func(): return false, 2000)
		await _shot("coop_host_2_prontera")
	await _wait(func(): return ns.player_names().size() <= 1, 60000)
	print("HOST RESULT: %d failed" % failed)
	ns.leave()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
	quit(0 if failed == 0 else 1)
