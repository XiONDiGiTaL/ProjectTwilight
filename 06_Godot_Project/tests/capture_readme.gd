extends SceneTree
## Stages the gameplay screenshots used in README.md and saves them as JPEG to
## user://captures/readme_*.jpg. Rendered from the player's own client; copy
## the ones you want into docs/screenshots/.
##   godot --path 06_Godot_Project -s res://tests/capture_readme.gd [scene ...]
## Scenes: priest, combat, sonic, magic, town (default: all).

const FIELD := "res://scenes/game/field.tscn"

var scene: Node3D
var sim: FieldSimulation
var player: SimUnit


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/readme_%s.jpg" % name
	root.get_texture().get_image().save_jpg(out, 0.9)
	print("saved ", ProjectSettings.globalize_path(out))


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
		if cond.call():
			return true
	return false


## Starts the field scene with a throwaway character described by `spec`.
func _start(map_name: String, cell: Vector2i, spec: Dictionary) -> bool:
	if scene != null:
		scene.queue_free()
		await _wait(0.3)
	var ch := CharacterRules.new_character(String(spec.get("name", "Hero")), bool(spec.get("male", true)),
		int(spec.get("hair", 2)), int(spec.get("hair_color", 0)), CharacterRules.stats_from_pairs(5, 5, 5))
	ch.job = String(spec.get("job", "novice"))
	ch.level = int(spec.get("level", 60))
	ch.job_level = int(spec.get("job_level", 40))
	ch.stats = spec.get("stats", {"str": 60, "agi": 50, "vit": 40, "int": 20, "dex": 45, "luk": 20})
	ch.status_points = 0
	ch.skills = spec.get("skills", {"NV_BASIC": 9})
	ch.skill_points = 0
	ch.equipment = {"weapon": int(spec.get("weapon", 1201)), "body": 2301}
	ch.cloth_color = int(spec.get("cloth", 0))
	ch.aura = String(spec.get("aura", "class"))
	ch.zeny = 125000
	ch.map = map_name
	ch.cell = [cell.x, cell.y]
	ch.script_vars = {"TW_TRAIN_ASKED": {"0": 1}}
	var hk := []
	for code in spec.get("hotkeys", []):
		hk.append({"type": "skill", "id": code})
	ch.hotkeys = hk
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	root.get_node("GameSession").slot = "slot1"
	scene = load(FIELD).instantiate()
	scene.bots_enabled = false
	root.add_child(scene)
	await _wait(0.5)
	if scene.get("player") == null or scene.player == null:
		print("field failed on ", map_name)
		return false
	sim = scene.sim
	player = scene.player
	player.hp = player.max_hp
	player.sp = player.max_sp
	scene.camera.distance = float(spec.get("camera", 150.0))
	await _wait(5.0)      # let the map banner fade before anything is staged
	# Clear the stage: wild monsters near the player would walk into the shot.
	for u in sim.units.values():
		if not u.is_player() and Vector2(u.walker.cell).distance_to(Vector2(player.walker.cell)) < 26.0:
			u.walker = GridWalker.new(sim.pathfinder.nearest_walkable(u.walker.cell + Vector2i(60, 60), 40))
	return true


## A monster placed next to the player; `hp` > 0 makes it a durable target.
func _monster(mob: String, offset: Vector2i, hp := 0, passive := false) -> SimUnit:
	var m := sim.add_monster(mob, sim.pathfinder.nearest_walkable(player.walker.cell + offset, 4))
	if hp > 0:
		m.max_hp = hp
		m.hp = hp
	if passive:
		m.walker.walk_speed = 100000.0
	return m


## A scripted bystander: any class, look and posture.
func _extra(name: String, job: String, male: bool, offset: Vector2i, hair: int, hair_color: int, cloth: int,
		weapon := 0, sitting := false, aura := "none") -> SimUnit:
	var u := sim.add_player(name, sim.pathfinder.nearest_walkable(player.walker.cell + offset, 3),
		{"str": 30, "agi": 30, "vit": 30, "int": 30, "dex": 30, "luk": 10})
	u.job = job
	u.sprite = String(sim.job_db.get(job, {}).get("sprite", "초보자"))
	u.male = male
	u.hair_style = hair
	u.hair_color = hair_color
	u.cloth_color = cloth
	u.aura = aura
	u.level = 50
	u.job_level = 30
	u.skills["NV_BASIC"] = 9
	if weapon != 0:
		u.equipment["weapon"] = weapon
	sim._recalc_player(u)
	u.hp = u.max_hp
	u.sp = u.max_sp
	u.sitting = sitting
	return u


# --- Scenes ---------------------------------------------------------------------

## A CPU Priest heals and blesses the player in the middle of a fight.
func _scene_priest() -> void:
	if not await _start("prt_fild08", Vector2i(166, 358), {"name": "Aldric", "job": "swordman", "level": 38, "job_level": 30,
			"weapon": 1116, "hair": 5, "hair_color": 2, "skills": {"NV_BASIC": 9, "SM_SWORD": 10, "SM_TWOHAND": 5, "SM_BASH": 10},
			"hotkeys": ["SM_BASH", "SM_MAGNUM"], "camera": 115.0}):
		return
	var foe := _monster("1063", Vector2i(2, 0), 4000)
	_monster("1002", Vector2i(-3, 2), 2500)
	var priest := BotBrain.spawn(sim, player.walker.cell + Vector2i(-4, 1), 45, BotBrain.ARCHETYPES.size() - 1)
	priest.name = "Seraphine"
	priest.hair_style = 9
	priest.hair_color = 4
	priest.sp = priest.max_sp
	await _wait(0.4)
	scene.attack(foe.id)
	await _wait(1.6)
	player.hp = int(player.max_hp * 0.28)
	scene.hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))
	if await _until(func(): return priest.is_casting(), 6.0):
		await _wait(0.45)
		await _shot("priest_casting_heal")
	var before := player.hp
	if await _until(func(): return player.hp > before + 20, 6.0):
		await _wait(0.12)
		await _shot("priest_heals_player")
	if await _until(func(): return player.has_status("angelus"), 8.0):
		await _wait(0.15)
		await _shot("priest_buffs_player")
	else:
		print("priest: no Angelus within 8 s (sp %d/%d)" % [priest.sp, priest.max_sp])


## Melee: a Knight's Bowling Bash into a pack, with damage numbers and HP bars.
func _scene_combat() -> void:
	if not await _start("prt_fild08", Vector2i(168, 360), {"name": "Brannoc", "job": "knight", "level": 70, "job_level": 40,
			"weapon": 1163, "hair": 3, "hair_color": 6, "aura": "ember",
			"skills": {"NV_BASIC": 9, "SM_SWORD": 10, "SM_TWOHAND": 10, "SM_BASH": 10, "KN_BOWLINGBASH": 10, "KN_SPEARSTAB": 5},
			"hotkeys": ["SM_BASH", "KN_BOWLINGBASH", "SM_MAGNUM"], "camera": 115.0}):
		return
	var a := _monster("1063", Vector2i(2, 0), 9000)
	_monster("1002", Vector2i(3, 1), 9000)
	_monster("1007", Vector2i(2, -1), 9000)
	_monster("1002", Vector2i(3, -1), 9000)
	await _wait(0.5)
	scene.attack(a.id)
	await _until(func(): return a.hp < a.max_hp, 6.0)
	await _wait(0.9)
	await _shot("combat_melee")
	sim.command_use_skill(player.id, "KN_BOWLINGBASH", a.id)
	var hp := a.hp
	await _until(func(): return a.hp < hp - 200, 4.0)
	await _wait(0.22)
	await _shot("combat_bowling_bash")


## An Assassin's Sonic Blow: the built-up combo number over a durable target.
func _scene_sonic() -> void:
	if not await _start("prt_fild08", Vector2i(167, 359), {"name": "Nyla", "job": "assassin", "male": false, "level": 75,
			"job_level": 45, "weapon": 1207, "hair": 12, "hair_color": 5, "cloth": 1, "aura": "none",
			"stats": {"str": 85, "agi": 80, "vit": 20, "int": 10, "dex": 50, "luk": 30},
			"skills": {"NV_BASIC": 9, "AS_SONICBLOW": 10, "AS_GRIMTOOTH": 5, "TF_ENVENOM": 10, "TF_DAGGERMASTERY": 10},
			"hotkeys": ["AS_SONICBLOW", "AS_GRIMTOOTH", "TF_ENVENOM"], "camera": 100.0}):
		return
	var foe := _monster("1063", Vector2i(1, 0), 60000, true)
	_monster("1002", Vector2i(4, 2), 3000, true)
	await _wait(0.6)
	scene.attack(foe.id)
	await _until(func(): return foe.hp < foe.max_hp, 6.0)
	await _wait(0.4)
	for attempt in 3:
		player.skill_delay = 0.0
		player.sp = player.max_sp
		var hp := foe.hp
		if not sim.command_use_skill(player.id, "AS_SONICBLOW", foe.id):
			await _wait(0.4)
			continue
		if await _until(func(): return foe.hp < hp - 300, 3.0):
			await _wait(0.16 + 0.1 * attempt)
			await _shot("sonic_blow_%d" % (attempt + 1))
		await _wait(1.3)


## A Mage's bolt: element-coloured casting circle, cast bar, then the strike.
func _scene_magic() -> void:
	if not await _start("prt_fild08", Vector2i(168, 362), {"name": "Elyra", "job": "mage", "male": false, "level": 55,
			"job_level": 40, "weapon": 1601, "hair": 7, "hair_color": 3, "aura": "none",
			"stats": {"str": 5, "agi": 20, "vit": 30, "int": 90, "dex": 40, "luk": 10},
			"skills": {"NV_BASIC": 9, "MG_FIREBOLT": 10, "MG_COLDBOLT": 10, "MG_LIGHTNINGBOLT": 10, "MG_SOULSTRIKE": 5},
			"hotkeys": ["MG_FIREBOLT", "MG_COLDBOLT", "MG_LIGHTNINGBOLT", "MG_SOULSTRIKE"], "camera": 115.0}):
		return
	var foe := _monster("1007", Vector2i(5, 1), 30000, true)
	await _wait(0.6)
	sim.command_use_skill(player.id, "MG_FIREBOLT", foe.id)
	if await _until(func(): return player.is_casting(), 3.0):
		await _wait(1.6)
		await _shot("magic_casting_fire")
	var hp := foe.hp
	if await _until(func(): return foe.hp < hp, 8.0):
		await _wait(0.2)
		await _shot("magic_fire_bolt")
	await _wait(2.6)
	player.skill_delay = 0.0
	sim.command_use_skill(player.id, "MG_LIGHTNINGBOLT", foe.id)
	if await _until(func(): return player.is_casting(), 3.0):
		await _wait(1.4)
		await _shot("magic_casting_wind")


## Prontera, the hub: many classes and palettes sitting, walking and casting.
func _scene_town() -> void:
	if not await _start("prontera", Vector2i(156, 180), {"name": "Rowan", "job": "crusader", "level": 80, "job_level": 45,
			"weapon": 1163, "hair": 4, "hair_color": 1, "cloth": 2, "aura": "none", "camera": 140.0}):
		return
	var cast := [
		# name, job, male, offset, hair, hair colour, cloth dye, weapon, sitting
		["Isolde", "priest", false, Vector2i(-3, 1), 9, 4, 0, 1501, false],
		["Kaelis", "wizard", true, Vector2i(-5, -1), 6, 7, 1, 1601, true],
		["Wrenna", "hunter", false, Vector2i(-6, -2), 11, 2, 3, 1702, true],
		["Dario", "blacksmith", true, Vector2i(4, -2), 8, 5, 0, 1301, false],
		["Liora", "dancer", false, Vector2i(5, 1), 14, 6, 2, 1951, false],
		["Corvin", "assassin", true, Vector2i(2, -4), 10, 0, 1, 1207, true],
		["Aurelle", "sage", false, Vector2i(-2, -4), 3, 3, 4, 1550, true],
		["Haldor", "monk", true, Vector2i(-1, 4), 5, 8, 0, 0, false],
		["Tobias", "bard", true, Vector2i(3, 3), 12, 2, 3, 1901, true],
		["Mirelle", "alchemist", false, Vector2i(7, -1), 2, 1, 1, 1301, false],
		["Zarek", "rogue", true, Vector2i(-7, 2), 15, 4, 2, 1207, false],
		["Astrid", "knight", false, Vector2i(1, 5), 7, 5, 4, 1116, false],
	]
	var units := {}
	for c in cast:
		units[c[0]] = _extra(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
	await _wait(1.2)
	# A few of them are busy: walking past, and a Priest blessing a friend.
	sim.command_move(units["Dario"].id, units["Dario"].walker.cell + Vector2i(-6, 1))
	sim.command_move(units["Zarek"].id, units["Zarek"].walker.cell + Vector2i(5, -2))
	sim.command_move(units["Astrid"].id, units["Astrid"].walker.cell + Vector2i(4, 2))
	var priest: SimUnit = units["Isolde"]
	priest.skills["AL_ANGELUS"] = 10
	priest.skills["AL_HEAL"] = 10
	sim.command_use_skill(priest.id, "AL_ANGELUS", player.id)
	await _wait(0.5)
	await _shot("prontera_hub")
	await _wait(0.6)
	units["Haldor"].hp = int(units["Haldor"].max_hp * 0.4)
	priest.skill_delay = 0.0
	sim.command_use_skill(priest.id, "AL_HEAL", units["Haldor"].id)
	await _until(func(): return priest.is_casting(), 2.0)
	await _wait(0.5)
	scene.camera.distance = 120.0
	await _wait(0.2)
	await _shot("prontera_hub_close")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var tmp := "user://readme_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	var audio := root.get_node_or_null("GameAudio")
	if audio:
		audio.enabled = false
	var want := OS.get_cmdline_user_args()
	var scenes := {"priest": _scene_priest, "combat": _scene_combat, "sonic": _scene_sonic, "magic": _scene_magic, "town": _scene_town}
	for key in scenes:
		if want.is_empty() or want.has(key):
			print("--- ", key)
			await scenes[key].call()
	quit(0)
