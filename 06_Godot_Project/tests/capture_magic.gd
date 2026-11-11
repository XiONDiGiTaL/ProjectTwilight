extends SceneTree
## Visual check: Mage casting (circle, cast bar, aura), bolt release, and a
## line-up of every element's casting circle plus the aura styles.
##   godot --path 06_Godot_Project -s res://tests/capture_magic.gd   (not headless)


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
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	var sim: FieldSimulation = scene.sim
	var p: SimUnit = scene.player
	p.stats.int = 40
	p.stats.dex = 20
	p.job_level = 10
	p.skills.NV_BASIC = 9
	sim.command_job_change(p.id, "mage")
	for code in ["MG_FIREBOLT", "MG_COLDBOLT", "MG_LIGHTNINGBOLT", "MG_SOULSTRIKE", "MG_NAPALMBEAT"]:
		p.skills[code] = 10
	p.max_sp = 999
	p.sp = 999
	scene.camera.distance = 170.0
	# Clear wandering monsters near us and place a still target.
	for id in sim.units.keys():
		var u: SimUnit = sim.units[id]
		if not u.is_player():
			u.walker.walk_speed = 1e9
	var target := sim.add_monster("1002", p.walker.cell + Vector2i(5, -3))
	target.walker.walk_speed = 1e9
	target.max_hp = 99999
	target.hp = 99999
	await _frames(30)

	sim.command_use_skill(p.id, "MG_FIREBOLT", target.id)
	await _frames(70)
	await _shot("magic_cast_fire")

	# Let it go off and catch the bolts mid-fall.
	while p.is_casting():
		await process_frame
	await _frames(6)
	await _shot("magic_release_fire")

	p.skill_delay = 0.0
	sim.command_use_skill(p.id, "MG_LIGHTNINGBOLT", target.id)
	await _frames(80)
	await _shot("magic_cast_wind")

	# Element line-up: one circle per element around the player.
	p.walker.stop()
	sim._cancel_cast(p)
	await _frames(20)
	var origin: Vector3 = scene.views[p.id].global_position
	var els := ElementPalette.ELEMENTS.keys()
	for i in els.size():
		var c := CastingCircle.make(els[i], 10, 60.0)
		scene.add_child(c)
		var col := i % 5
		var row := i / 5
		c.global_position = origin + Vector3((col - 2) * 26.0, 0, (row - 0.5) * 30.0 - 30.0)
		c.elapsed = 30.0
	scene.camera.distance = 260.0
	await _frames(40)
	await _shot("magic_elements")
	for n in scene.get_children():
		if n is CastingCircle:
			n.queue_free()

	# Aura styles.
	scene.camera.distance = 120.0
	for style in ["class", "ember", "radiant", "void"]:
		p.aura = style
		await _frames(50)
		await _shot("aura_%s" % style)
	quit(0)
