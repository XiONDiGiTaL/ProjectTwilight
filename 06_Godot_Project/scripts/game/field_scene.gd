extends Node3D
## Offline field: one map, the player, monsters, loot and combat.
## The FieldSimulation is authoritative; this scene only presents it and
## turns input into simulation commands. Progress is saved locally.
##
## Controls: left-click monster = attack, item = pick up, ground = walk.
## I / Alt+E = inventory, Alt+A / S = status, Q / Alt+Q = equipment, K / Alt+S = skills,
## F1-F9 = hotkey bar, Insert = sit / stand, F12 = save now.

@export var map_name := "prt_fild08"
@export var start_cell := Vector2i(170, 200)
@export var spawns := {"1002": 25, "1063": 12, "1007": 12}  # Poring, Lunatic, Fabre
@export var sim_seed := 1
## Save slot; "" disables loading and saving (tests, tools).
@export var save_slot := "slot1"

const PICK_RADIUS_PX := 34.0
const ITEM_PICK_RADIUS_PX := 22.0
const AUTOSAVE_SEC := 30.0

var map: RoMap
var sim: FieldSimulation
var player: SimUnit
var views: Dictionary = {}         # unit id -> UnitView
var item_views: Dictionary = {}    # ground id -> GroundItemView
var npc_views: Dictionary = {}     # npc id -> NpcView
var camera: RoCamera
var hud: CombatHud
var walker: GridWalker:            # kept for tools/tests that inspect the player walker
	get:
		return player.walker if player else null
var _target_marker: MeshInstance3D
var _res: Node
var _autosave_in := AUTOSAVE_SEC


func _ready() -> void:
	_res = get_node("/root/RoResources")
	if not _res.is_mounted:
		_res.mount()
	var session := get_node_or_null("/root/GameSession")
	if session and session.slot != "" and save_slot != "":
		save_slot = session.slot
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	add_child(env)

	map = RoMap.new()
	add_child(map)
	if not map.load_map(map_name):
		push_error("Could not load map %s" % map_name)
		return
	sim = FieldSimulation.new(map.gat, sim_seed)
	var loaded_msg := ""
	if save_slot != "" and SaveGame.exists(save_slot):
		var r := SaveGame.read(save_slot, sim.item_db, ClassInsignia.classes())
		if r.ok and (r.character.map == map_name or r.character.map == ""):
			player = sim.add_player_from_save(r.character)
			loaded_msg = "Welcome back, %s." % player.name
		elif not r.ok:
			loaded_msg = "Save could not be loaded: %s" % r.error
	if player == null:
		player = sim.add_player("Adventurer", start_cell, {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
		player.inventory.add(501, 3, sim.item_db, player.max_weight())  # starter Red Potions
	for mob in spawns:
		sim.spawn_random(mob, int(spawns[mob]))
	sim.spawn_npcs(map_name)

	camera = RoCamera.new()
	camera.distance = 240.0
	add_child(camera)
	hud = CombatHud.new()
	add_child(hud)
	hud.camera = camera
	hud.numbers.camera = camera
	hud.inventory.bind_unit(player, sim.item_db)
	hud.inventory.use_requested.connect(func(i): sim.command_use_item(player.id, i))
	hud.status_window.bind_unit(player)
	hud.status_window.raise_requested.connect(func(s): sim.command_raise_stat(player.id, s))
	hud.inventory.equip_requested.connect(func(i): sim.command_equip(player.id, i))
	hud.equipment_window.bind_unit(player, sim.item_db)
	hud.equipment_window.unequip_requested.connect(func(s): sim.command_unequip(player.id, s))
	hud.shop.buy_requested.connect(func(item, n): sim.command_buy(player.id, item, n))
	hud.shop.sell_requested.connect(func(i, n): sim.command_sell(player.id, i, n))
	hud.shop.shop_closed.connect(func(): sim.close_shop(player.id))
	hud.skill_window.bind_unit(player, sim.skill_db)
	hud.skill_window.learn_requested.connect(func(c): sim.command_learn_skill(player.id, c))
	hud.skill_window.use_requested.connect(func(c): sim.command_use_skill(player.id, c))
	hud.hotkeys.bind_unit(player, sim.item_db, sim.skill_db)
	hud.hotkeys.activate_requested.connect(use_hotkey)
	_build_marker()
	_consume_events()  # creates views for the initial spawns
	camera.follow = views[player.id]
	(views[player.id] as UnitView).update_weapon(_res)
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player), true)
	if loaded_msg != "":
		hud.notify(loaded_msg, UiTheme.ACCENT)


func _build_marker() -> void:
	_target_marker = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.5, 4.5)
	quad.orientation = PlaneMesh.FACE_Y
	_target_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.42, 0.86, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_marker.material_override = mat
	_target_marker.visible = false
	add_child(_target_marker)


# --- Input -------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_I:
				hud.inventory.toggle()
			KEY_E:
				if e.alt_pressed:
					hud.inventory.toggle()
			KEY_A:
				if e.alt_pressed:
					hud.status_window.toggle()
			KEY_S:
				if e.alt_pressed:
					hud.skill_window.toggle()
				else:
					hud.status_window.toggle()
			KEY_K:
				hud.skill_window.toggle()
			KEY_INSERT:
				sim.command_sit(player.id)
			KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9:
				use_hotkey(e.keycode - KEY_F1)
			KEY_F12:
				save_now(true)
			KEY_Q:
				hud.equipment_window.toggle()
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var npc := npc_at_screen(e.position)
	if npc != 0:
		sim.command_talk(player.id, npc)
		return
	var target := monster_at_screen(e.position)
	if target != 0:
		attack(target)
		return
	var gid := item_at_screen(e.position)
	if gid != 0:
		sim.command_pickup(player.id, gid)
		return
	var cell := map.pick_cell(camera.project_ray_origin(e.position), camera.project_ray_normal(e.position))
	if cell.x >= 0:
		walk_to(cell)


## Monster id whose sprite is under the screen point, or 0.
func monster_at_screen(p: Vector2) -> int:
	var best := 0
	var best_d := PICK_RADIUS_PX
	for id in views:
		var u: SimUnit = sim.units[id]
		if u.is_player() or u.dead:
			continue
		var v: UnitView = views[id]
		var feet := camera.unproject_position(v.global_position)
		var head := camera.unproject_position(v.head_position())
		var d := Geometry2D.get_closest_point_to_segment(p, feet, head).distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


## Uses hotkey slot `i`: a skill or a usable item from the inventory.
func use_hotkey(i: int) -> void:
	var e: Variant = hud.hotkeys.entry(i)
	if e == null:
		return
	if e.type == "skill":
		sim.command_use_skill(player.id, String(e.id))
		return
	for k in player.inventory.entries.size():
		if int(player.inventory.entries[k].id) == int(e.id):
			sim.command_use_item(player.id, k)
			return
	hud.notify("You have no %s left." % sim.item_db.get(str(int(e.id)), {}).get("name", "items"), UiTheme.HP_MID)


## NPC id whose sprite is under the screen point, or 0.
func npc_at_screen(p: Vector2) -> int:
	for nid in npc_views:
		var v: NpcView = npc_views[nid]
		var feet := camera.unproject_position(v.global_position)
		var head := camera.unproject_position(v.head_position())
		if Geometry2D.get_closest_point_to_segment(p, feet, head).distance_to(p) < PICK_RADIUS_PX:
			return nid
	return 0


## Ground item id under the screen point, or 0.
func item_at_screen(p: Vector2) -> int:
	var best := 0
	var best_d := ITEM_PICK_RADIUS_PX
	for gid in item_views:
		var v: GroundItemView = item_views[gid]
		var d := camera.unproject_position(v.global_position + Vector3(0, 1.5, 0)).distance_to(p)
		if d < best_d:
			best_d = d
			best = gid
	return best


func walk_to(cell: Vector2i) -> bool:
	if not sim.command_move(player.id, cell):
		return false
	_target_marker.position = map.cell_to_world(cell.x, cell.y) + Vector3(0, 0.3, 0)
	_target_marker.visible = true
	return true


func attack(target_id: int) -> bool:
	if not sim.command_attack(player.id, target_id):
		return false
	_target_marker.visible = false
	var t: SimUnit = sim.units[target_id]
	hud.set_target(t.id, t.name, t.level, t.hp, t.max_hp)
	return true


# --- Saving --------------------------------------------------------------------

func save_now(announce := false) -> void:
	if save_slot == "" or player == null:
		return
	var err := SaveGame.write(save_slot, SaveGame.capture(player, map_name))
	if announce:
		hud.notify("Game saved." if err == OK else "Save failed (%s)." % error_string(err),
			UiTheme.ACCENT if err == OK else UiTheme.HP_LOW)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if sim != null and player != null and is_inside_tree():
			save_now()


func _exit_tree() -> void:
	save_now()


# --- Frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	sim.tick(delta * 1000.0)
	_consume_events()
	for v in views.values():
		(v as UnitView).camera_yaw = camera.yaw_deg
	if not player.walker.is_moving():
		_target_marker.visible = false
	var mouse := get_viewport().get_mouse_position()
	var hover := item_at_screen(mouse)
	if hover != 0:
		var iv: GroundItemView = item_views[hover]
		hud.hover_tag(iv.item_name, camera.unproject_position(iv.head_position()))
	else:
		hud.hover_tag("", Vector2.ZERO)
	# Walking away from the merchant closes the shop (the simulation also enforces range).
	if hud.shop.visible and sim._open_shop_of(player).is_empty():
		hud.shop.toggle(false)
		hud.notify("You walked away from the shop.", UiTheme.TEXT_DIM)
	_autosave_in -= delta
	if _autosave_in <= 0.0:
		_autosave_in = AUTOSAVE_SEC
		save_now()


func _consume_events() -> void:
	var player_changed := false
	var inventory_changed := false
	for ev in sim.drain_events():
		match ev.type:
			"spawn":
				_create_view(sim.units[ev.id])
			"attack":
				var a: SimUnit = sim.units[ev.id]
				var av: UnitView = views.get(ev.id)
				if av and av.sprite:
					av.sprite.play_once("attack", minf(a.attack_motion, a.attack_interval))
			"damage":
				_on_damage(ev)
				player_changed = player_changed or ev.dst == player.id
			"death":
				hud.unit_died(ev.id)
				player_changed = player_changed or ev.id == player.id
			"exp":
				var pv: UnitView = views[ev.id]
				if ev.base > 0:
					hud.numbers.spawn_offset(pv.global_position, Vector2(110, -40), "+%d BASE EXP" % ev.base, DamageNumbers.Kind.EXP_BASE)
				if ev.job > 0:
					hud.numbers.spawn_offset(pv.global_position, Vector2(110, -18), "+%d JOB EXP" % ev.job, DamageNumbers.Kind.EXP_JOB)
				player_changed = true
			"levelup":
				var lv: UnitView = views[ev.id]
				var lu: SimUnit = sim.units[ev.id]
				if ev.kind == "base":
					hud.level_up(lv.global_position, "LEVEL UP", "Base Level %d reached  ·  %d status points available" % [ev.level, lu.status_points])
				else:
					hud.level_up(lv.global_position, "JOB LEVEL UP", "Job Level %d reached" % ev.level)
				player_changed = true
				save_now()
			"revive":
				player_changed = player_changed or ev.id == player.id
			"drop":
				_create_item_view(ev.ground)
			"ground_gone":
				_remove_item_view(ev.ground)
			"pickup":
				_remove_item_view(ev.ground)
				if ev.id == player.id:
					var def: Dictionary = sim.item_db.get(str(ev.item), {})
					hud.notify("Obtained  %s  ×%d" % [def.get("name", "item"), ev.amount], UiTheme.TEXT)
			"pickup_fail":
				if ev.id == player.id:
					hud.notify(ev.reason, UiTheme.HP_MID)
			"heal":
				var hv: UnitView = views.get(ev.id)
				if hv:
					hud.numbers.spawn(hv.head_position(), "+%d" % ev.amount, DamageNumbers.Kind.HEAL)
				player_changed = player_changed or ev.id == player.id
			"inventory":
				inventory_changed = inventory_changed or ev.id == player.id
			"stats":
				player_changed = player_changed or ev.id == player.id
			"skills":
				player_changed = player_changed or ev.id == player.id
			"skill":
				if ev.id == player.id:
					hud.notify(ev.text, UiTheme.ACCENT)
				player_changed = player_changed or ev.id == player.id
			"skill_fail":
				if ev.id == player.id:
					hud.notify(ev.text, UiTheme.HP_MID)
			"posture", "regen":
				player_changed = player_changed or ev.id == player.id
			"equipment":
				var ev_view: UnitView = views.get(ev.id)
				if ev_view:
					ev_view.update_weapon(_res)
				player_changed = player_changed or ev.id == player.id
			"npc_spawn":
				_create_npc_view(ev.npc)
			"npc_open":
				if ev.id == player.id:
					var npc: Dictionary = sim.npcs[ev.npc]
					var shop_def: Dictionary = sim.shop_db.get(npc.shop, {})
					hud.shop.open(npc.name, npc.greeting, shop_def.get("items", []), player, sim.item_db)
			"trade":
				if ev.id == player.id:
					hud.notify(ev.text, UiTheme.TEXT if ev.ok else UiTheme.HP_MID)
					hud.shop.refresh()
					player_changed = true
	if inventory_changed:
		hud.inventory.refresh()
		hud.hotkeys.refresh()
	if player_changed:
		hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))
		hud.status_window.refresh()
		hud.inventory.refresh()
		hud.equipment_window.refresh()
		hud.skill_window.refresh()
		hud.hotkeys.refresh()


func _on_damage(ev: Dictionary) -> void:
	var dst: SimUnit = sim.units[ev.dst]
	var src: SimUnit = sim.units[ev.src]
	var dv: UnitView = views.get(ev.dst)
	if dv == null:
		return
	var at := dv.head_position()
	if ev.miss:
		hud.numbers.spawn(at, "MISS", DamageNumbers.Kind.MISS)
	elif dst.is_player():
		hud.numbers.spawn(at, str(ev.amount), DamageNumbers.Kind.TAKEN)
	elif ev.crit:
		hud.numbers.spawn(at, str(ev.amount), DamageNumbers.Kind.CRIT)
	else:
		hud.numbers.spawn(at, str(ev.amount), DamageNumbers.Kind.NORMAL)
	if not ev.miss and not dst.dead and dv.sprite:
		dv.sprite.play_once("hurt", 280.0)
	# Monster HP bars appear once a player attacks them and stay until death.
	if not dst.is_player() and src.is_player():
		hud.engage(dst.id, dst.hp + (ev.amount if not ev.miss else 0), dst.max_hp, dv.head_position, dst.name)
		if ev.src == player.id and hud.target_id() != dst.id:
			hud.set_target(dst.id, dst.name, dst.level, dst.hp + (ev.amount if not ev.miss else 0), dst.max_hp)
	hud.update_hp(dst.id, dst.hp, dst.max_hp)


func _create_view(u: SimUnit) -> void:
	var v := UnitView.new()
	v.unit = u
	v.map = map
	add_child(v)
	var ok := v.build_player(_res, u.male, u.hair_style, u.hair_color) if u.is_player() else v.build_monster(_res)
	if not ok:
		push_warning("No sprite for %s (%s)" % [u.name, u.sprite])
	v.position = map.cell_pos_to_world(u.walker.position())
	views[u.id] = v


func _create_npc_view(nid: int) -> void:
	var v := NpcView.new()
	add_child(v)
	v.setup(sim.npcs[nid], _res, map)
	npc_views[nid] = v


func _create_item_view(gid: int) -> void:
	var g: Dictionary = sim.ground_items.get(gid, {})
	if g.is_empty():
		return
	var v := GroundItemView.new()
	add_child(v)
	v.setup(g, sim.item_db.get(str(g.item), {}), map)
	item_views[gid] = v


func _remove_item_view(gid: int) -> void:
	if item_views.has(gid):
		(item_views[gid] as Node).queue_free()
		item_views.erase(gid)
