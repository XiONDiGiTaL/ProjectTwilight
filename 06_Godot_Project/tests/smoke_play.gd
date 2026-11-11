extends SceneTree
## End-to-end smoke test of the real game flow, as a player runs it:
## main menu -> character select -> create a character -> play -> field,
## walk, fight and talk for a few seconds. Uses a throwaway save folder so
## the player's own saves are never touched.
##   godot --path 06_Godot_Project -s res://tests/smoke_play.gd   (not headless)

var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _f in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://captures/%s.png" % name))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var tmp := "user://smoke_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(30)
	await _shot("smoke_1_menu")
	change_scene_to_file("res://scenes/ui/character_select.tscn")
	await _frames(30)
	var ch := CharacterRules.new_character("Smoketest", true, 2, 0, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [ch.cell.x, ch.cell.y]
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var session := root.get_node("GameSession")
	session.slot = "slot1"
	change_scene_to_file("res://scenes/game/field.tscn")
	await _frames(60)
	var field: Node = current_scene
	if field == null or field.get("player") == null:
		push_error("SMOKE: field did not start")
		quit(1)
		return
	var p: SimUnit = field.player
	print("SMOKE: in field ", field.map_name, " at ", p.walker.cell, " job ", p.job)
	field.sim.command_move(p.id, p.walker.cell + Vector2i(3, 2))
	await _frames(90)
	for id in field.sim.units:
		var u: SimUnit = field.sim.units[id]
		if not u.is_player():
			field.sim.command_attack(p.id, u.id)
			break
	await _frames(240)
	await _shot("smoke_2_field")
	print("SMOKE: hp ", p.hp, "/", p.max_hp, " exp ", p.base_exp, " cell ", p.walker.cell)
	field.save_now()
	print("SMOKE: saved ok=", SaveGame.exists("slot1"))
	# Fast travel through the script warp path to a town without maps.json data.
	field.script_warp("geffen", 119, 59)
	await _frames(120)
	var g: Node = current_scene
	print("SMOKE: after warp map=", g.get("map_name"), " cell=", (g.player as SimUnit).walker.cell if g and g.get("player") else "?")
	await _shot("smoke_3_geffen")
	SaveGame.save_dir = "user://saves/"
	quit(0)
