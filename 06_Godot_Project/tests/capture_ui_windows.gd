extends SceneTree
## Visual verification of every gameplay window at 1280×720 and 1920×1080.
##   godot --path 06_Godot_Project -s res://tests/capture_ui_windows.gd
## Opens each window against populated Prontera data, saves a screenshot, and
## fails if a window is empty or leaves the viewport. Images go to
## user://captures/ui_verify and are never committed.

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const OUT_DIR := "user://captures/ui_verify"
const GUILDS_PATH := "user://captures/ui_verify_guilds.json"
const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}

var _scene: Node3D
var _hud: CombatHud
var _label := ""
var _errors: Array[String] = []
var _report: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for size in SIZES:
		root.size = size
		for _f in 3:
			await process_frame
		_label = "%dx%d" % [size.x, size.y]
		_report.append("== %s ==" % _label)
		_scene = load("res://scenes/game/field.tscn").instantiate()
		_scene.save_slot = ""
		_scene.map_name = "prontera"
		_scene.start_cell = Vector2i(152, 191)
		root.add_child(_scene)
		await process_frame
		if _scene.player == null:
			_errors.append("%s: field failed to load" % _label)
			_scene.queue_free()
			continue
		_hud = _scene.hud
		_setup()
		# The live field closes shop/storage when the simulation says the player
		# walked away; this harness opens them directly for a stable screenshot.
		_scene.set_process(false)
		await create_timer(0.35).timeout
		await _capture_window("inventory", _hud.inventory)
		await _capture_window("status", _hud.status_window)
		await _capture_window("equipment", _hud.equipment_window)
		await _capture_window("skills", _hud.skill_window)
		await _capture_window("shop", _hud.shop, _open_shop)
		await _capture_window("storage", _hud.storage, _open_storage)
		await _capture_window("guild_storage", _hud.storage, _open_guild_storage)
		await _capture_window("guild", _hud.guild_window)
		await _capture_dialog()
		_scene.queue_free()
		await process_frame
		await process_frame

	if _errors.is_empty():
		print("\nUI capture verification passed for every window at both resolutions.")
	else:
		for e in _errors:
			print("UI CAPTURE ERROR: ", e)
	_report.append("\nRESULT: %s" % ("PASS" if _errors.is_empty() else "FAIL"))
	for e in _errors:
		_report.append("ERROR: " + e)
	var report := FileAccess.open(OUT_DIR + "/report.txt", FileAccess.WRITE)
	if report:
		report.store_string("\n".join(_report))
	print("Images: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0 if _errors.is_empty() else 1)


func _setup() -> void:
	var sim: FieldSimulation = _scene.sim
	var p: SimUnit = _scene.player
	p.zeny = 5000
	# A little of everything so every row has real content.
	for entry in [[501, 12], [502, 5], [909, 7], [1201, 1], [2301, 1], [2401, 1]]:
		p.inventory.add(int(entry[0]), int(entry[1]), sim.item_db, p.max_weight())
	for item in [1201, 2301]:
		for i in p.inventory.entries.size():
			if int(p.inventory.entries[i].id) == item:
				sim.command_equip(p.id, i)
				break
	sim._gain_exp(p, 0, 160)
	for i in 3:
		sim.command_learn_skill(p.id, "NV_BASIC")
	sim.command_learn_skill(p.id, "NV_FIRSTAID")
	_hud.hotkeys.set_entry(0, {"type": "skill", "id": "NV_FIRSTAID"})
	_hud.hotkeys.set_entry(1, {"type": "item", "id": 501})

	# Guild view: leader plus two officers and one member, a MOTD and shared bag.
	if FileAccess.file_exists(GUILDS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GUILDS_PATH))
	sim.guilds = GuildStore.new(GUILDS_PATH, sim.item_db)
	p.guild_id = ""
	p.guild_name = ""
	if not sim.command_create_guild(p.id, "Twilight Guard"):
		_errors.append("%s: could not found the capture guild" % _label)
		return
	var gid := p.guild_id
	var names := ["Aria", "Brannoc", "Celwyn"]
	for i in names.size():
		var n: String = names[i]
		sim.command_guild_invite(p.id, n)
		var other := sim.add_player(n, Vector2i(154 + i, 191), FLAT)
		sim.command_guild_accept(other.id, gid)
	sim.command_guild_promote(p.id, "Aria")
	sim.command_guild_promote(p.id, "Brannoc")
	sim.command_guild_set_motd(p.id, "Guild meeting at 20:00 - bring potions and a warp scroll.")
	var bag: Inventory = sim.guilds.storage_of(gid)
	bag.add(909, 7, sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	bag.add(2301, 1, sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	p.storage.add(501, 20, sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	p.storage.add(1201, 1, sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	_hud.inventory.refresh()
	_hud.status_window.refresh()
	_hud.equipment_window.refresh()
	_hud.skill_window.refresh()
	_hud.guild_window.bind(sim.guilds, p)


func _hide_all() -> void:
	for w: GlassWindow in [_hud.inventory, _hud.status_window, _hud.equipment_window,
			_hud.skill_window, _hud.shop, _hud.storage, _hud.guild_window]:
		if w.visible:
			w.toggle(false)
	_hud.dialog.close()


func _open_shop() -> void:
	var sim: FieldSimulation = _scene.sim
	var p: SimUnit = _scene.player
	var found := {}
	for n in sim.npcs.values():
		if String(n.get("kind", "shop")) != "shop":
			continue
		var sd: Dictionary = sim.shop_db.get(String(n.get("shop", "")), {})
		if not (sd.get("items", []) as Array).is_empty():
			found = n
			break
	if found.is_empty():
		_errors.append("%s: no populated shop NPC found" % _label)
		return
	var shop_def: Dictionary = sim.shop_db.get(String(found.get("shop", "")), {})
	_hud.shop.open(String(found.name), String(found.get("greeting", "")),
		shop_def.get("items", []), p, sim.item_db)
	_hud.shop._selected = 0
	_hud.shop.refresh()


func _open_storage() -> void:
	var p: SimUnit = _scene.player
	_hud.storage.open("Kafra", p, _scene.sim.item_db)
	_hud.storage._set_mode(true)
	_hud.storage.refresh()


func _open_guild_storage() -> void:
	var sim: FieldSimulation = _scene.sim
	var p: SimUnit = _scene.player
	var g: Dictionary = sim.guilds.get_guild(p.guild_id)
	if g.is_empty():
		_errors.append("%s: guild storage has no guild" % _label)
		return
	_hud.storage.open_guild(String(g.name), p, sim.guilds.storage_of(p.guild_id), sim.item_db)


func _capture_window(name: String, w: GlassWindow, prepare: Callable = Callable()) -> void:
	_hide_all()
	if prepare.is_valid():
		prepare.call()
	w.position = w._default_position
	w.toggle(true)
	for _f in 4:
		await process_frame
	if not w.visible:
		_errors.append("%s %s: window is not visible" % [_label, name])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "%s/%s_%s.png" % [OUT_DIR, _label, name]
	img.save_png(out)
	var rect := Rect2(w.global_position, w.size)
	_check_rect(name, rect, img)
	print("CAPTURE  %s  %-14s  pos=%s  size=%s" % [_label, name, w.global_position, w.size])


func _capture_dialog() -> void:
	_hide_all()
	_hud.dialog.show_page("Kafra", "Welcome to the Kafra service. What can I do for you today?",
		["Open storage", "Save point"], true)
	for _f in 4:
		await process_frame
	if not _hud.dialog.visible:
		_errors.append("%s dialog: dialogue is not visible" % _label)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "%s/%s_dialog.png" % [OUT_DIR, _label]
	img.save_png(out)
	_hud.dialog.close()
	var rect := Rect2(_hud.dialog.global_position, _hud.dialog.size)
	_check_rect("dialog", rect, img)
	print("CAPTURE  %s  %-14s  pos=%s  size=%s" % [_label, "dialog", rect.position, rect.size])


func _check_rect(name: String, rect: Rect2, img: Image) -> void:
	var before := _errors.size()
	if img.get_width() != root.size.x or img.get_height() != root.size.y:
		_errors.append("%s %s: image is %dx%d" % [_label, name, img.get_width(), img.get_height()])
	if rect.size.x <= 0 or rect.size.y <= 0:
		_errors.append("%s %s: empty window rect" % [_label, name])
	# The project uses canvas-items stretch, so Controls are logical pixels while
	# the captured texture is at the requested window resolution.
	var logical := root.get_visible_rect().size
	var scale := Vector2(img.get_width(), img.get_height()) / logical
	var physical := Rect2(rect.position * scale, rect.size * scale)
	var image_rect := Rect2(Vector2.ZERO, Vector2(img.get_width(), img.get_height()))
	if not image_rect.grow(2.0).encloses(physical):
		_errors.append("%s %s: outside viewport: %s" % [_label, name, physical])
	_report.append("%s  %-14s  logical=%s  physical=%s" % [
		"PASS" if _errors.size() == before else "FAIL", name, rect, physical])
