extends SceneTree
## Records the launcher's background loop: Prontera's plaza with a crowd of
## classes, HUD hidden, camera swaying slowly. Writes numbered JPEG frames to
## user://captures/launcher_bg/ (960x540, 24 fps, 16 s, seamless camera loop).
## tools/launcher/make_background.py blurs, darkens and encodes them.
##   godot --path 06_Godot_Project -s res://tests/capture_launcher_bg.gd

const FPS := 24
const SECONDS := 16.0
const OUT := "user://captures/launcher_bg/"


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for f in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT + f)
	root.size = Vector2i(1280, 720)
	var tmp := "user://launcher_bg_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	var audio := root.get_node_or_null("GameAudio")
	if audio:
		audio.enabled = false
	var ch := CharacterRules.new_character("Rowan", true, 4, 1, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.job = "crusader"
	ch.level = 80
	ch.job_level = 45
	ch.skills = {"NV_BASIC": 9}
	ch.equipment = {"weapon": 1163, "body": 2301}
	ch.map = "prontera"
	ch.cell = [156, 180]
	ch.script_vars = {"TW_TRAIN_ASKED": {"0": 1}}
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	root.get_node("GameSession").slot = "slot1"
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.bots_enabled = false
	root.add_child(scene)
	await _wait(0.5)
	if scene.get("player") == null or scene.player == null:
		print("field failed")
		quit(1)
		return
	var sim: FieldSimulation = scene.sim
	var here: Vector2i = scene.player.walker.cell
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var jobs := ["priest", "wizard", "hunter", "blacksmith", "dancer", "assassin", "sage", "monk", "bard", "alchemist",
		"rogue", "knight", "swordman", "mage", "acolyte", "thief", "archer", "merchant", "lord_knight", "high_wizard"]
	var walkers: Array = []
	for i in jobs.size():
		var job: String = jobs[i]
		var off := Vector2i(rng.randi_range(-11, 11), rng.randi_range(-9, 9))
		var u := sim.add_player("B%d" % i, sim.pathfinder.nearest_walkable(here + off, 4),
			{"str": 30, "agi": 30, "vit": 30, "int": 30, "dex": 30, "luk": 10})
		u.job = job
		u.sprite = String(sim.job_db.get(job, {}).get("sprite", "초보자"))
		u.male = job != "dancer" and (job == "bard" or rng.randf() < 0.5)
		u.hair_style = rng.randi_range(1, 19)
		u.hair_color = rng.randi_range(0, 8)
		u.cloth_color = rng.randi_range(0, 4)
		u.aura = "none"
		u.skills["NV_BASIC"] = 9
		sim._recalc_player(u)
		u.hp = u.max_hp
		if i % 3 == 0:
			u.sitting = true
		else:
			walkers.append(u)
	await _wait(5.5)     # map banner fades
	scene.hud.visible = false
	for v in scene.views.values():
		if v.has_method("set_name_tag"):
			v.set_name_tag("")
	for v in scene.npc_views.values():
		for c in v.get_children():
			if c is Label3D:
				c.visible = false
	scene.camera.distance = 170.0
	var total := int(FPS * SECONDS)
	var step_ms := 1000.0 / FPS
	var next_walk := 0
	for f in total:
		var t := float(f) / total
		scene.camera.yaw_deg = 16.0 * sin(TAU * t)
		scene.camera.distance = 170.0 + 18.0 * cos(TAU * t)
		if f == next_walk and not walkers.is_empty():
			next_walk += 9
			var w: SimUnit = walkers[rng.randi_range(0, walkers.size() - 1)]
			sim.command_move(w.id, sim.pathfinder.nearest_walkable(here + Vector2i(rng.randi_range(-11, 11), rng.randi_range(-9, 9)), 4))
		var t0 := Time.get_ticks_msec()
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_jpg("%sf_%04d.jpg" % [OUT, f], 0.92)
		# Keep simulated time close to video time so walking speed looks natural.
		while Time.get_ticks_msec() - t0 < int(step_ms):
			await process_frame
	print("frames ", total, " -> ", ProjectSettings.globalize_path(OUT))
	quit(0)
