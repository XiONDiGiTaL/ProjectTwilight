extends SceneTree
## Co-op with the real field scene, client side (start coop_scene_host.gd first).
##   godot --path 06_Godot_Project -s res://tests/net/coop_scene_client.gd   (not headless)
## Joins from the character select screen's own code path, plays the field
## scene on a replica, fights, chats, changes map and talks to a script NPC.
## Screenshots: user://captures/coop_client_*.png.

const CODE_FILE := "user://coop_scene_code.txt"

var failed := 0
var notices: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		failed += 1
	print("CLIENT %s: %s  %s" % ["PASS" if ok else "FAIL", name, "" if ok else detail])


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
	var tmp := "user://coop_client_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	var ch := CharacterRules.new_character("ClientHero", false, 3, 1, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [173, 370]
	ch.map = "prt_fild08"
	ch.script_vars = {"TW_TRAIN_ASKED": {"0": 1}}
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var ns: Node = root.get_node("NetSession")
	ns.notice_received.connect(func(t, _ok): notices.append(t))
	await _wait(func(): return FileAccess.file_exists(CODE_FILE), 60000)
	var code := FileAccess.get_file_as_string(CODE_FILE).strip_edges()
	change_scene_to_file("res://scenes/ui/character_select.tscn")
	await _wait(func(): return current_scene != null and current_scene.has_method("_join"), 10000)
	await _wait(func(): return false, 500)
	await _shot("coop_client_0_select")
	current_scene._join("slot1", code)
	_check("joined through the character select", await _wait(func(): return _field() != null, 30000), ns.last_error)
	if _field() == null:
		quit(1)
		return
	var field := _field()
	_check("field runs on a replica", field.sim is RemoteSimulation and field.player.name == "ClientHero")
	var host_seen := false
	for v in field.views.values():
		host_seen = host_seen or (v.unit != null and v.unit.name == "HostHero")
	_check("client sees the host's character", host_seen, "views=%d" % field.views.size())
	_check("inventory replicated to the windows", field.player.inventory.count(501) == 3)
	var start: Vector2i = field.player.walker.cell
	field.walk_to(start + Vector2i(0, -4))
	_check("client walks (decided by the host)", await _wait(func(): return _field().player.walker.cell.distance_to(start) >= 3, 6000))
	# Fight the nearest monster until one dies or 25 s pass.
	var target := 0
	var best := 9999.0
	for id in field.sim.units:
		var u: SimUnit = field.sim.units[id]
		if not u.is_player() and not u.dead:
			var d := Vector2(u.walker.cell).distance_to(Vector2(field.player.walker.cell))
			if d < best:
				best = d
				target = int(id)
	field.attack(target)
	var hit := await _wait(func():
		var t: SimUnit = _field().sim.units.get(target)
		return t == null or t.hp < t.max_hp or t.dead, 30000)
	_check("client damages a monster", hit, "target %d dist %.0f" % [target, best])
	await _shot("coop_client_1_combat")
	field._on_chat_submit("hello from the client")
	await _wait(func(): return false, 1500)
	await _shot("coop_client_2_chat")
	# Map change ordered by the host: the scene reloads on the new map.
	field._on_chat_submit("@warp prontera 150 185")
	_check("client follows the host's transfer to prontera",
		await _wait(func(): return _field() != null and _field().map_name == "prontera" and _field() != field, 30000))
	field = _field()
	if field != null and field.map_name == "prontera":
		_check("script NPCs are visible", field.npc_views.size() > 0, str(field.npc_views.size()))
		var stylist := 0
		for nid in field.sim.npcs:
			if String(field.sim.npcs[nid].get("name", "")).begins_with("Stylist"):
				stylist = int(nid)
		if stylist != 0:
			var cell: Vector2i = field.sim.npcs[stylist].cell
			field._on_chat_submit("@warp prontera %d %d" % [cell.x, cell.y - 1])
			await _wait(func(): return Vector2(_field().player.walker.cell).distance_to(Vector2(cell)) <= 3, 5000)
			field.sim.command_talk(field.player.id, stylist)
			_check("remote NPC dialog opens in the glass dialog", await _wait(func(): return _field().hud.dialog.visible, 8000))
			await _wait(func(): return false, 400)
			await _shot("coop_client_3_dialog")
			field.hud.dialog.chosen.emit(-1)
			await _wait(func(): return false, 500)
		# Wait for the host player to arrive, then take the group shot.
		await _wait(func():
			for v in _field().views.values():
				if v.unit != null and v.unit.name == "HostHero":
					return true
			return false, 30000)
		await _wait(func(): return false, 2500)
		await _shot("coop_client_4_prontera")
	var saved := SaveGame.read("slot1", FieldSimulation._load_json(FieldSimulation.ITEM_DB), ClassInsignia.classes())
	_check("client keeps its own save", bool(saved.ok) and String(saved.character.name) == "ClientHero")
	print("CLIENT RESULT: %d failed" % failed)
	ns.leave()
	await _wait(func(): return false, 500)
	quit(0 if failed == 0 else 1)
