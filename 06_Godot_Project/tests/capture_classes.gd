extends SceneTree
## Visual check: Dark Knight and Shaman sprites, their skill trees, skill
## effects and the new damage numbers.
##   godot --path 06_Godot_Project -s res://tests/capture_classes.gd   (not headless)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _f in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://captures/%s.png" % name))


func _make(scene: Node3D, job: String, male: bool) -> SimUnit:
	var sim: FieldSimulation = scene.sim
	var p: SimUnit = scene.player
	p.male = male
	p.level = 70
	p.job_level = 10
	p.skills.NV_BASIC = 9
	p.job = "novice"
	sim.command_job_change(p.id, "swordman" if job == "dark_knight" else "acolyte")
	p.job_level = 40
	sim.command_job_change(p.id, job)
	p.skill_points = 30
	p.max_sp = 3000
	p.sp = 3000
	await _frames(10)
	(scene.views[p.id] as UnitView).rebuild_player(scene._res)
	return p


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	var sim: FieldSimulation = scene.sim
	for id in sim.units.keys():
		var u: SimUnit = sim.units[id]
		if not u.is_player():
			u.walker.walk_speed = 1e9
	scene.camera.distance = 110.0

	# Dark Knight: sprite + skill window + Hell Impact.
	var p: SimUnit = await _make(scene, "dark_knight", true)
	for code in ["SM_SWORD", "SM_TWOHAND", "DK_AXEMASTERY", "DK_BLOODYCRASH", "DK_GUILLOTINE", "DK_DARKWEAPON", "DK_HELLIMPACT", "DK_GENOCIDE", "DK_DEATHBLADE"]:
		p.skills[code] = 10
	p.inventory.add(1351, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)
	var dummy := sim.add_monster("1002", p.walker.cell + Vector2i(2, -1))
	dummy.walker.walk_speed = 1e9
	dummy.max_hp = 999999
	dummy.hp = 999999
	scene.hud.skill_window.toggle(true)
	scene.hud.skill_window.position = Vector2(760, 90)
	scene.hud.skill_window.refresh()
	await _frames(40)
	await _shot("class_dk_tree")
	scene.hud.skill_window.toggle(false)
	sim.command_use_skill(p.id, "DK_DARKWEAPON")
	await _frames(20)
	sim.command_use_skill(p.id, "DK_GENOCIDE")
	await _frames(12)
	await _shot("class_dk_genocide")
	p.skill_delay = 0
	sim.command_use_skill(p.id, "DK_HELLIMPACT", dummy.id)
	await _frames(90)
	await _shot("class_dk_hellimpact")
	# Death Blade with a sword: multi-hit numbers building up to the total.
	p.inventory.add(1116, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)
	p.skill_delay = 0
	sim.command_use_skill(p.id, "DK_DEATHBLADE", dummy.id)
	await _frames(28)
	await _shot("class_dk_deathblade_numbers")

	# Shaman: sprite sheet body, tree, spirits.
	p = await _make(scene, "shaman", false)
	for code in ["SH_COMFORT", "SH_SUMMON", "SH_SPIRITFIRE", "SH_SPIRITWIND", "SH_DIVINE", "SH_PROTECTION", "SH_RAINDANCE"]:
		p.skills[code] = 10
	p.stats.int = 80
	scene.camera.distance = 90.0
	await _frames(30)
	await _shot("class_shaman_idle")
	scene.hud.skill_window.toggle(true)
	scene.hud.skill_window.refresh()
	await _frames(30)
	await _shot("class_shaman_tree")
	scene.hud.skill_window.toggle(false)
	scene.camera.distance = 140.0
	sim.command_use_skill(p.id, "SH_DIVINE", dummy.id)
	await _frames(100)
	await _shot("class_shaman_divine_cast")
	while p.is_casting():
		await process_frame
	await _frames(14)
	await _shot("class_shaman_divine_release")
	quit(0)
