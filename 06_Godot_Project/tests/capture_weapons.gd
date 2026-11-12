extends SceneTree
## Visual check: every player job in the running field scene, grouped by tier,
## with its class weapon; then an Archer firing a visible arrow volley.
##   godot --path 06_Godot_Project -s res://tests/capture_weapons.gd   (not headless)
## Saves user://captures/bow_weapons_*.png and bow_projectile.png.

const FIELD := "res://scenes/game/field.tscn"
const CAPTURE_DIR := "user://captures"
const FIRST_WEAPON := {
	"swordman": 1116, "mage": 1601, "archer": 1701,
	"acolyte": 1501, "merchant": 1301, "thief": 1207,
}
const GROUP_ORDER := ["first", "second", "transcendent", "third"]

var scene: Node3D
var sim: FieldSimulation
var res: Node
var center_cell: Vector2i
var center_world: Vector3


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [CAPTURE_DIR, name]
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	root.size = Vector2i(1600, 900)
	scene = load(FIELD).instantiate()
	scene.save_slot = ""
	scene.bots_enabled = false
	scene.map_name = "prontera"
	scene.start_cell = Vector2i(156, 180)
	root.add_child(scene)
	await process_frame
	await _frames(8)
	sim = scene.sim
	res = scene._res
	center_cell = scene.player.walker.cell
	center_world = scene.map.cell_pos_to_world(center_cell)
	scene.hud.visible = false
	scene.camera.follow = null
	scene.camera.focus = center_world
	scene.camera.distance = 230.0
	# The local player and wandering monsters are not part of the lineup.
	var local_view: UnitView = scene.views.get(scene.player.id)
	if local_view:
		local_view.visible = false
	for u in sim.units.values():
		if not u.is_player():
			u.walker.walk_speed = 1e9
			var mv: UnitView = scene.views.get(u.id)
			if mv:
				mv.visible = false
	for nv in scene.npc_views.values():
		nv.visible = false

	var groups := {}
	for id in sim.job_db:
		if String(id).begins_with("_"):
			continue
		var j: Dictionary = sim.job_db[id]
		var tier := int(j.get("tier", 0))
		var key := "first" if tier <= 1 else ("second" if tier == 2 else ("transcendent" if tier == 3 else "third"))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(String(id))
	for key in GROUP_ORDER:
		if groups.has(key):
			await _capture_group(key, groups[key])
	await _capture_projectile()
	quit(0)


func _male_for(job: String, j: Dictionary) -> bool:
	var forced := String(j.get("sex", ""))
	if forced == "female":
		return false
	if forced == "male" or j.has("pack_sprite"):
		return true
	var sprite := String(j.get("sprite", ""))
	var male_base := "%s남/%s_남" % [PlayerSprites.BODY_DIR, sprite]
	if res.exists(male_base + ".spr") and res.exists(male_base + ".act"):
		return true
	var female_base := "%s여/%s_여" % [PlayerSprites.BODY_DIR, sprite]
	return not (res.exists(female_base + ".spr") and res.exists(female_base + ".act"))


func _weapon_for(job: String) -> int:
	if job == "novice":
		return 1201
	if job in ["bard", "clown", "minstrel"]:
		return 1901
	if job in ["dancer", "gypsy", "wanderer"]:
		return 1951
	var id := job
	while id != "":
		if FIRST_WEAPON.has(id):
			return int(FIRST_WEAPON[id])
		id = String(sim.job_db.get(id, {}).get("parent", ""))
	return 1201


func _capture_group(key: String, ids: Array) -> void:
	var cols := 4
	var rows := int(ceil(float(ids.size()) / cols))
	var units: Array = []
	for i in ids.size():
		var job := String(ids[i])
		var j: Dictionary = sim.job_db[job]
		var p := sim.add_player(String(j.get("name", job)), center_cell,
			{"str": 30, "agi": 30, "vit": 30, "int": 30, "dex": 30, "luk": 10})
		p.job = job
		p.sprite = String(j.get("sprite", "초보자"))
		p.male = _male_for(job, j)
		p.level = 70
		p.job_level = 40
		p.hair_style = 2
		p.hair_color = 0
		p.cloth_color = 0
		p.aura = "none"
		p.equipment["weapon"] = _weapon_for(job)
		sim._recalc_player(p)
		p.hp = p.max_hp
		p.sp = p.max_sp
		scene._create_view(p)
		var v: UnitView = scene.views.get(p.id)
		if v == null or v.sprite == null:
			print("weapon capture: no body for ", job)
			scene.remove_view(p.id)
			sim.units.erase(p.id)
			continue
		v.set_process(false)
		var col := i % cols
		var row := i / cols
		v.global_position = center_world + Vector3(
			(col - (cols - 1) / 2.0) * 32.0, 0,
			(row - (rows - 1) / 2.0) * 26.0)
		v.sprite.play_once("attack", 80.0, true)
		v.set_name_tag(String(j.get("name", job)))
		v.name_tag.font_size = 28
		v.name_tag.outline_size = 8
		v.name_tag.position = Vector3(0, v.sprite.top_height() + 7.0, 0)
		units.append(p)
	scene.camera.focus = center_world
	scene.camera.distance = 135.0 + rows * 10.0
	await _frames(10)
	await _shot("bow_weapons_%s" % key)
	for p in units:
		scene.remove_view(p.id)
		sim.units.erase(p.id)
	await _frames(2)


func _capture_projectile() -> void:
	var archer := sim.add_player("Archer", center_cell,
		{"str": 30, "agi": 30, "vit": 30, "int": 10, "dex": 50, "luk": 20})
	archer.job = "archer"
	archer.sprite = "궁수"
	archer.male = true
	archer.level = 50
	archer.job_level = 40
	archer.hair_style = 2
	archer.hair_color = 0
	archer.cloth_color = 0
	archer.aura = "none"
	archer.equipment["weapon"] = 1701
	sim._recalc_player(archer)
	archer.hp = archer.max_hp
	archer.sp = 500
	archer.max_sp = 500
	archer.inventory.add(1750, 2, sim.item_db, 99999)
	archer.skills["AC_DOUBLESTRAFE"] = 10
	scene._create_view(archer)

	var target := sim.add_monster("1002", center_cell)
	target.max_hp = 999999
	target.hp = 999999
	target.walker.walk_speed = 1e9
	scene._create_view(target)

	var av: UnitView = scene.views.get(archer.id)
	var tv: UnitView = scene.views.get(target.id)
	if av == null or av.sprite == null or tv == null or tv.sprite == null:
		print("projectile capture: missing Archer or target sprite")
		return
	av.set_process(false)
	tv.set_process(false)
	# Keep the arena off the plaza's ambient light so both arrows read clearly.
	var stage_world := center_world + Vector3(0, 0, -45)
	av.global_position = stage_world + Vector3(-20, 0, 0)
	tv.global_position = stage_world + Vector3(20, 0, 0)
	av.sprite.set_action("idle", 0)
	av.set_name_tag("Archer")
	av.name_tag.font_size = 28
	av.name_tag.outline_size = 8
	av.name_tag.position = Vector3(0, av.sprite.top_height() + 7.0, 0)
	scene.camera.focus = stage_world
	scene.camera.distance = 82.0
	await _frames(4)

	if not sim.command_use_skill(archer.id, "AC_DOUBLESTRAFE", target.id):
		print("projectile capture: skill could not be queued")
		return
	sim._attack(archer, target)
	scene._consume_events()
	# Leave enough flight time for both Double Strafe arrows to be well apart;
	# the second arrow deliberately trails the first by ArrowProjectile.HIT_STAGGER.
	await create_timer(0.32).timeout
	await _shot("bow_projectile")
