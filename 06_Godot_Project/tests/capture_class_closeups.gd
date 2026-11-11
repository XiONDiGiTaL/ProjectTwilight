extends SceneTree
## Close-ups: Dark Knight (male / female), Shaman, and the damage-number styles.
##   godot --path 06_Godot_Project -s res://tests/capture_class_closeups.gd   (not headless)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _f in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://captures/%s.png" % name))


func _look(scene: Node3D, job: String, male: bool, action := "idle") -> void:
	var p: SimUnit = scene.player
	p.male = male
	p.job = job
	p.sprite = String(scene.sim.job_db[job].sprite)
	var v: UnitView = scene.views[p.id]
	v.rebuild_player(scene._res)
	await _frames(4)
	if action == "cast":
		p.cast_skill = "SH_SUMMON"
	else:
		p.cast_skill = ""
	await _frames(20)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await _frames(30)
	scene.hud.visible = false
	scene.camera.distance = 42.0
	await _look(scene, "dark_knight", true)
	await _shot("closeup_dk_male")
	await _look(scene, "dark_knight", false)
	await _shot("closeup_dk_female")
	await _look(scene, "shaman", false)
	await _shot("closeup_shaman")
	await _look(scene, "shaman", false, "cast")
	await _shot("closeup_shaman_cast")
	# Damage-number styles around the player.
	scene.hud.visible = true
	scene.camera.distance = 120.0
	var at: Vector3 = (scene.views[scene.player.id] as UnitView).head_position()
	var nums: DamageNumbers = scene.hud.numbers
	nums.spawn_offset(at, Vector2(-260, 0), "87", DamageNumbers.Kind.NORMAL)
	nums.spawn_offset(at, Vector2(-150, 30), "MISS", DamageNumbers.Kind.MISS)
	nums.spawn_offset(at, Vector2(220, 10), "1204", DamageNumbers.Kind.CRIT)
	nums.spawn_offset(at, Vector2(-120, -80), "34", DamageNumbers.Kind.TAKEN)
	nums.spawn_offset(at, Vector2(250, -90), "+412", DamageNumbers.Kind.HEAL)
	nums.spawn_combo(at, 5321, 5)
	await _frames(40)
	await _shot("closeup_damage_numbers")
	quit(0)
