extends Node3D
## Offline field: one map, the player, monsters, loot and combat.
## The FieldSimulation is authoritative; this scene only presents it and
## turns input into simulation commands. Progress is saved locally.
##
## Controls: left-click monster = attack, item = pick up, ground = walk.
## I / Alt+E = inventory, Alt+A / S = status, Q / Alt+Q = equipment, K / Alt+S = skills,
## F1-F9 = hotkey bar, Insert = sit / stand, U = cycle aura, M = minimap,
## Enter = chat / @commands, F12 = save now.

@export var map_name := "prt_fild08"
@export var start_cell := Vector2i(170, 200)
@export var sim_seed := 1
## Save slot; "" disables loading and saving (tests, tools).
@export var save_slot := "slot1"
## CPU adventurers that populate the map (off for tools and capture scenes).
@export var bots_enabled := true

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
var _casts: Dictionary = {}        # unit id -> CastingCircle


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

	# The save decides which map we are on; read it before loading the map.
	var saved: Dictionary = {}
	var loaded_msg := ""
	if save_slot != "" and SaveGame.exists(save_slot):
		var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
		item_db.erase("_provenance")
		var r := SaveGame.read(save_slot, item_db, ClassInsignia.classes())
		if r.ok:
			saved = r.character
			if String(saved.map) != "":
				map_name = String(saved.map)
		else:
			loaded_msg = "Save could not be loaded: %s" % r.error

	map = RoMap.new()
	add_child(map)
	if not map.load_map(map_name):
		push_error("Could not load map %s" % map_name)
		return
	sim = FieldSimulation.new(map.gat, sim_seed)
	if not saved.is_empty():
		player = sim.add_player_from_save(saved)
	if player == null:
		player = sim.add_player("Adventurer", start_cell, {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
		player.inventory.add(501, 3, sim.item_db, player.max_weight())  # starter Red Potions
	# Arrivals from scripts / unknown maps may land on a blocked cell.
	if not sim.pathfinder.is_walkable(player.walker.cell):
		var c := player.walker.cell
		if c.x <= 0 or c.y <= 0 or c.x >= map.gat.width or c.y >= map.gat.height:
			c = Vector2i(map.gat.width / 2, map.gat.height / 2)
		player.walker = GridWalker.new(sim.pathfinder.nearest_walkable(c, 60))
	sim.setup_map(map_name, ensure_npc_world(_res).warps_on(map_name), ensure_npc_world(_res).monsters_on(map_name))
	_spawn_script_npcs()
	if bots_enabled:
		BotBrain.populate(sim, sim.rng.randi_range(2, 4), BotBrain.map_level(sim), player.walker.cell)
	_maybe_offer_training.call_deferred()
	for w in sim.warps:
		var wv := WarpPortalView.new()
		add_child(wv)
		wv.setup(w, map)

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
	hud.skill_window.available = sim.available_skills
	hud.skill_window.requirements = sim.skill_requirements_unmet
	hud.skill_window.bind_unit(player, sim.skill_db)
	hud.dialog.chosen.connect(_on_dialog_choice)
	hud.skill_window.learn_requested.connect(func(c): sim.command_learn_skill(player.id, c))
	hud.skill_window.use_requested.connect(func(c): sim.command_use_skill(player.id, c))
	hud.hotkeys.bind_unit(player, sim.item_db, sim.skill_db)
	hud.hotkeys.activate_requested.connect(use_hotkey)
	hud.chat.submitted.connect(_on_chat_submit)
	_build_marker()
	_consume_events()  # creates views for the initial spawns
	camera.follow = views[player.id]
	(views[player.id] as UnitView).update_weapon(_res)
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player), true)
	if loaded_msg != "":
		hud.notify(loaded_msg, UiTheme.HP_MID)
	hud.map_banner(String(sim.map_info.get("name", map_name)), String(sim.map_info.get("subtitle", "")))
	hud.bind_minimap(map.gat, sim, player.id, String(sim.map_info.get("name", map_name)))


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

## Enter opens the command line before the GUI consumes it, so the same key
## that submits a command cannot immediately reopen the console.
func _input(e: InputEvent) -> void:
	if hud == null or player == null:
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode != KEY_ENTER and e.keycode != KEY_KP_ENTER:
		return
	if hud.chat.is_open():
		return
	hud.chat.open()
	get_viewport().set_input_as_handled()


## Chat line: @commands run through the simulation, plain text is local speech.
func _on_chat_submit(text: String) -> void:
	var r := ChatCommands.execute(sim, player, text)
	if r.has("action"):
		var a: Dictionary = r.action
		if String(a.get("kind", "")) == "warp":
			script_warp(String(a.map), int(a.x), int(a.y))
	var msg := String(r.get("text", ""))
	if msg != "":
		hud.notify(msg, UiTheme.ACCENT if bool(r.get("ok", true)) else UiTheme.HP_MID)


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
			KEY_U:
				cycle_aura()
			KEY_M:
				hud.toggle_minimap()
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


## Skill / spell visuals by the skill's "fx" key (skills.json).
func _play_fx(fx: String, from: Vector3, to: Vector3, element: String, hits: int, area: int) -> void:
	match fx:
		"orbs":
			SpellFx.orbs(self, from, to, element, hits)
		"burst", "spikes":
			SpellFx.burst(self, to, element, area)
		"impact":
			SpellFx.burst(self, to, element, area)
			SpellFx.burst(self, to, element, area + 1)
			SpellFx.bolts(self, to, element, 1)
		"wave":
			SpellFx.orbs(self, from, to, element, 3)
		"judgment":
			for i in hits:
				SpellFx.bolts(self, to + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)), element, 1)
			SpellFx.burst(self, to, element, area)
		"support", "aura":
			SpellFx.burst(self, to, element, 0)
		"slash":
			SpellFx.burst(self, to, element, 0)
		_:
			SpellFx.bolts(self, to, element, hits)


## Cycles the player's cosmetic aura (saved with the character).
func cycle_aura() -> void:
	player.aura = PlayerAura.next_style(player.aura)
	hud.notify("Aura:  %s" % PlayerAura.STYLES[player.aura].name, UiTheme.ACCENT)
	save_now()


## Uses hotkey slot `i`: a skill or a usable item from the inventory.
func use_hotkey(i: int) -> void:
	var e: Variant = hud.hotkeys.entry(i)
	if e == null:
		return
	if e.type == "skill":
		# Targeted skills aim at the monster under the cursor, else the current target.
		var hovered := monster_at_screen(get_viewport().get_mouse_position())
		sim.command_use_skill(player.id, String(e.id), hovered)
		if hovered != 0:
			var t: SimUnit = sim.units[hovered]
			hud.set_target(t.id, t.name, t.level, t.hp, t.max_hp)
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
		if sim != null and player != null and is_inside_tree() and not _skip_exit_save:
			save_now()


func _exit_tree() -> void:
	RoMap.clear_occlusion()
	if not _skip_exit_save:
		save_now()


# --- Frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	sim.tick(delta * 1000.0)
	_consume_events()
	if views.has(player.id):
		map.update_occlusion(camera, (views[player.id] as Node3D).global_position)
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
	if hud.dialog.visible and player.walker.is_moving():
		hud.dialog.close()
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
				var spawned: SimUnit = sim.units[ev.id]
				_create_view(spawned)
				if spawned.is_bot:
					var tag_color: Color = BotBrain.ROLE_COLORS.get(spawned.bot_role, Color(0.72, 0.9, 1.0))
					(views[spawned.id] as UnitView).set_name_tag(spawned.name, tag_color)
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
				# CPU adventurers earn EXP by the same rules but stay quiet.
				if ev.id == player.id:
					var pv: UnitView = views[ev.id]
					if ev.base > 0:
						hud.numbers.spawn_offset(pv.global_position, Vector2(110, -40), "+%d BASE EXP" % ev.base, DamageNumbers.Kind.EXP_BASE)
					if ev.job > 0:
						hud.numbers.spawn_offset(pv.global_position, Vector2(110, -18), "+%d JOB EXP" % ev.job, DamageNumbers.Kind.EXP_JOB)
					player_changed = true
			"levelup":
				if ev.id == player.id:
					var lv: UnitView = views[ev.id]
					var lu: SimUnit = sim.units[ev.id]
					if ev.kind == "base":
						hud.level_up(lv.global_position, "Level Up", "Lv %d  ·  +%d pts" % [ev.level, lu.status_points])
					else:
						hud.level_up(lv.global_position, "Job Level Up", "Job Lv %d" % ev.level)
					player_changed = true
					save_now()
			"revive":
				if ev.id == player.id and ev.has("to_map"):
					player.dead = false
					hud.notify("You return to your save point.", UiTheme.TEXT)
					_take_warp(String(ev.to_map), ev.to_cell)
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
			"autoloot":
				if ev.id == player.id:
					var adef: Dictionary = sim.item_db.get(str(ev.item), {})
					hud.notify("Obtained  %s  ×%d" % [adef.get("name", "item"), ev.amount], UiTheme.TEXT)
					inventory_changed = true
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
			"warp":
				if ev.id == player.id:
					_take_warp(String(ev.to_map), ev.to_cell)
			"npc_spawn":
				_create_npc_view(ev.npc)
			"npc_open":
				if ev.id == player.id:
					var npc: Dictionary = sim.npcs[ev.npc]
					if String(npc.get("kind", "shop")) == "script":
						_run_npc_script(npc)
					elif String(npc.get("kind", "shop")) == "job_guide":
						_job_dialog_start(npc)
					else:
						var shop_def: Dictionary = sim.shop_db.get(npc.shop, {})
						hud.shop.open(npc.name, npc.greeting, shop_def.get("items", []), player, sim.item_db)
			"job_change":
				var jv: UnitView = views.get(ev.id)
				if jv:
					jv.rebuild_player(_res)
				if ev.id == player.id:
					var jname := String(sim.job_db.get(ev.job, {}).get("name", ev.job))
					hud.level_up(jv.global_position if jv else Vector3.ZERO, "Job Change", jname)
					save_now()
				player_changed = true
			"cast_start":
				var cv: UnitView = views.get(ev.id)
				if cv:
					var circle := CastingCircle.make(String(ev.element), int(ev.level), float(ev.duration) / 1000.0)
					add_child(circle)
					circle.global_position = cv.global_position
					if _casts.has(ev.id) and is_instance_valid(_casts[ev.id]):
						(_casts[ev.id] as CastingCircle).interrupt()
					_casts[ev.id] = circle
					if ev.id == player.id:
						var sname := String(sim.skill_db.get(ev.skill, {}).get("name", ev.skill))
						hud.cast_begin(cv.head_position, float(ev.duration), "%s  Lv %d" % [sname, ev.level], ElementPalette.glow(String(ev.element)))
			"cast_end":
				var circle_v: CastingCircle = _casts.get(ev.id)
				if circle_v and is_instance_valid(circle_v):
					if ev.ok:
						circle_v.release()
					else:
						circle_v.interrupt()
				_casts.erase(ev.id)
				if ev.id == player.id:
					hud.cast_end(bool(ev.ok))
					if not ev.ok:
						hud.notify("Casting interrupted.", UiTheme.HP_MID)
				player_changed = player_changed or ev.id == player.id
			"magic":
				var tv: UnitView = views.get(ev.target)
				var caster: UnitView = views.get(ev.id)
				if tv:
					_play_fx(String(ev.get("fx", "bolts")), caster.global_position if caster else tv.global_position,
						tv.global_position, String(ev.element), int(ev.hits), int(ev.splash))
			"skill_fx":
				var from_v: UnitView = views.get(ev.id)
				var to_pos := map.cell_to_world(ev.cell.x, ev.cell.y)
				var tid := int(ev.get("target", 0))
				if tid != 0 and views.has(tid):
					to_pos = (views[tid] as UnitView).global_position
				_play_fx(String(ev.fx), from_v.global_position if from_v else to_pos, to_pos, String(ev.element), int(ev.hits), int(ev.area))
				if from_v and from_v.sprite and String(ev.fx) != "support" and String(ev.fx) != "aura":
					from_v.sprite.play_once("attack", 450.0)
			"status":
				var stv: UnitView = views.get(ev.id)
				if stv:
					var stname := StatusRules.display_name(String(ev.status))
					if ev.on:
						var deb := StatusRules.is_debuff(String(ev.status))
						hud.numbers.spawn(stv.head_position(), stname.to_upper(), DamageNumbers.Kind.MISS)
						if ev.id == player.id:
							hud.notify(("%s!" if deb else "%s") % stname, UiTheme.HP_MID if deb else UiTheme.ACCENT)
					elif ev.id == player.id:
						hud.notify("%s wore off." % stname, UiTheme.TEXT_DIM)
					stv.set_status_tint(sim.units[ev.id])
				player_changed = player_changed or ev.id == player.id
			"counter":
				var ctv: UnitView = views.get(ev.id)
				if ctv:
					hud.numbers.spawn(ctv.head_position(), "COUNTER", DamageNumbers.Kind.MISS)
			"sp_heal":
				var spv: UnitView = views.get(ev.id)
				if spv:
					hud.numbers.spawn(spv.head_position(), "+%d SP" % ev.amount, DamageNumbers.Kind.NORMAL)
				player_changed = player_changed or ev.id == player.id
			"resurrect":
				if ev.id == player.id:
					hud.notify("You have been revived.", UiTheme.HP_HIGH)
				player_changed = player_changed or ev.id == player.id
			"skill_hit":
				var sv: UnitView = views.get(ev.id)
				if sv:
					hud.skill_flash(map.cell_to_world(ev.cell.x, ev.cell.y), String(ev.skill))
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
	else:
		hud.numbers.spawn_combo(at, int(ev.amount), int(ev.get("hits", 1)), bool(ev.crit))
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


# --- Job guide dialogue ------------------------------------------------------------

const FIRST_JOBS := ["swordman", "mage", "archer", "acolyte", "merchant", "thief"]
var _dialog_npc: Dictionary = {}
var _dialog_state := ""
var _dialog_job := ""


## Classic second jobs per first job; only those in jobs.json are playable yet.
const SECOND_JOBS := {
	"swordman": ["knight", "crusader", "dark_knight"], "acolyte": ["priest", "monk", "shaman"],
	"mage": ["wizard", "sage"], "archer": ["hunter", "bard", "dancer"],
	"merchant": ["blacksmith", "alchemist"], "thief": ["assassin", "rogue"],
}
var _dialog_choices: Array = []


func _second_job_dialog(npc: Dictionary) -> void:
	var options: Array = SECOND_JOBS.get(player.job, [])
	var ready: Array = []
	var later: Array = []
	for j in options:
		if sim.job_db.has(j):
			ready.append(j)
		else:
			later.append(String(ClassInsignia.classes().get(j, {}).get("name", j.capitalize())))
	var need := 40
	if not ready.is_empty():
		need = int(sim.job_db[ready[0]].get("min_parent_job_level", 40))
	var jn := String(sim.job_db.get(player.job, {}).get("name", player.job))
	var text := "A %s seeking a greater path. At Job Level %d you may advance (you are Job Level %d)." % [jn, need, player.job_level]
	if not later.is_empty():
		text += "\n\nNot yet open in this build: %s." % ", ".join(later)
	if ready.is_empty():
		_dialog_state = "done"
		hud.dialog.show_page(npc.name, text, ["Close"])
		return
	_dialog_state = "choose2"
	_dialog_choices = ready
	var labels: Array = []
	for j in ready:
		var reason := sim.job_change_unmet(player, j)
		labels.append(String(sim.job_db[j].name) + ("" if reason == "" else "  (locked)"))
	labels.append("Not yet")
	hud.dialog.show_page(npc.name, text, labels)


func _job_dialog_start(npc: Dictionary) -> void:
	_dialog_npc = npc
	if int(sim.job_db.get(player.job, {}).get("tier", 0)) == 1:
		_second_job_dialog(npc)
		return
	if player.job != "novice":
		var jn := String(sim.job_db.get(player.job, {}).get("name", player.job))
		_dialog_state = "done"
		hud.dialog.show_page(npc.name, "You have already chosen your path, %s. Train hard and come back stronger!" % jn, ["Close"])
		return
	var basic := int(player.skills.get("NV_BASIC", 0))
	if player.job_level < FieldSimulation.JOB_CHANGE_JOB_LEVEL or basic < FieldSimulation.JOB_CHANGE_BASIC_SKILL:
		_dialog_state = "done"
		hud.dialog.show_page(npc.name, "%s\n\nTo choose a guild you need Job Level %d (you have %d) and Basic Skill level %d (you have %d). Hunt Porings in the field to the south and spend your skill points in the skill window (K)." % [
			npc.greeting, FieldSimulation.JOB_CHANGE_JOB_LEVEL, player.job_level, FieldSimulation.JOB_CHANGE_BASIC_SKILL, basic], ["Close"])
		return
	_dialog_state = "choose"
	var labels: Array = []
	for j in FIRST_JOBS:
		labels.append(String(sim.job_db.get(j, {}).get("name", j)))
	labels.append("Not yet")
	hud.dialog.show_page(npc.name, "Your basic training is complete. Which path will you walk?", labels)


func _on_dialog_choice(i: int) -> void:
	match _dialog_state:
		"choose":
			if i >= FIRST_JOBS.size():
				hud.dialog.close()
				return
			_dialog_job = FIRST_JOBS[i]
			_dialog_state = "confirm"
			var jn := String(sim.job_db.get(_dialog_job, {}).get("name", _dialog_job))
			var note := "" if not (sim.job_db.get(_dialog_job, {}).get("skills", []) as Array).is_empty() else "\n\n(Its guild skills are still being prepared in this build.)"
			hud.dialog.show_page(_dialog_npc.name, "Become a %s? This choice is permanent.%s" % [jn, note], ["Become a %s" % jn, "Go back"])
		"choose2":
			if i >= _dialog_choices.size():
				hud.dialog.close()
				return
			_dialog_job = _dialog_choices[i]
			var reason := sim.job_change_unmet(player, _dialog_job)
			var jdef: Dictionary = sim.job_db[_dialog_job]
			if reason != "":
				_dialog_state = "back"
				hud.dialog.show_page(_dialog_npc.name, "%s\n\n%s" % [String(jdef.name), reason], ["Go back"])
				return
			_dialog_state = "confirm"
			hud.dialog.show_page(_dialog_npc.name, "Become a %s? Your %s skills stay with you and unspent skill points carry over. This choice is permanent." % [String(jdef.name), String(sim.job_db.get(player.job, {}).get("name", ""))],
				["Become a %s" % String(jdef.name), "Go back"])
		"back":
			_job_dialog_start(_dialog_npc)
		"confirm":
			if i == 0:
				sim.command_job_change(player.id, _dialog_job)
				hud.dialog.close()
			else:
				_job_dialog_start(_dialog_npc)
		_:
			hud.dialog.close()


## Moves the player to another map: save at the destination, then reload.
func _travel(to_map: String, to_cell: Vector2i) -> void:
	if save_slot == "":
		hud.notify("Map travel needs a character save slot.", UiTheme.HP_MID)
		return
	player.walker = GridWalker.new(to_cell)
	player.target_id = 0
	SaveGame.write(save_slot, SaveGame.capture(player, to_map))
	var dest := String(sim.map_db.get(to_map, {}).get("name", to_map))
	hud.transition("Traveling to %s" % dest)
	set_process(false)
	await get_tree().create_timer(0.45).timeout
	_skip_exit_save = true
	get_tree().change_scene_to_file("res://scenes/game/field.tscn")


var _skip_exit_save := false


# --- NPC scripts (rAthena format, scripts/npc/) ------------------------------------

## Parsed once per game session and kept across map changes.
static var npc_world: RaWorld
var _npc_running := false


static func ensure_npc_world(res: Node) -> RaWorld:
	if npc_world == null:
		npc_world = RaWorld.new()
		npc_world.load_all(res)
		for e in npc_world.errors:
			push_warning("NPC script: " + String(e))
		print("NPC scripts: %d files, %d NPCs, %d functions, %d errors" % [npc_world.loaded_files.size(),
			npc_world.npcs.size(), npc_world.functions.size(), npc_world.errors.size()])
	return npc_world


## First arrival in the Training Grounds: ask whether to train or skip to Prontera.
func _maybe_offer_training() -> void:
	if not map_name.begins_with("new_") or int(player.script_vars.get("TW_TRAIN_ASKED", {}).get(0, 0)) != 0:
		return
	await get_tree().create_timer(0.8).timeout
	var def := ensure_npc_world(_res).find_npc("Training Choice#tw")
	if not def.is_empty() and not _npc_running:
		_run_npc_script({"script": "Training Choice#tw"})


func _spawn_script_npcs() -> void:
	var world := ensure_npc_world(_res)
	for def in world.npcs_on(map_name):
		var sprite := NpcIdentity.sprite_for(_res, String(def.sprite))
		if sprite == "":
			continue   # invisible NPCs (-1, 111, 139) are event / touch scripts
		var nid := sim.add_script_npc(def, sprite)
		if not bool(def.get("_inited", false)):
			def._inited = true
			var init := RaInterpreter.new(world, RaHost.new(), sim, player, def)
			init.run("OnInit")
	# Floating NPCs (e.g. the shared Healer body) run OnInit once too.
	for name in world.npcs:
		var d: Dictionary = world.npcs[name]
		if String(d.map) == "" and d.body != null and not bool(d.get("_inited", false)):
			d._inited = true
			RaInterpreter.new(world, RaHost.new(), sim, player, d).run("OnInit")


func _run_npc_script(npc: Dictionary) -> void:
	if _npc_running:
		return
	var world := ensure_npc_world(_res)
	var def := world.find_npc(String(npc.script))
	if def.is_empty():
		return
	_npc_running = true
	var host := FieldNpcHost.new(self)
	var vm := RaInterpreter.new(world, host, sim, player, def)
	await vm.run()
	if not vm.unsupported.is_empty():
		print("NPC %s used unsupported commands: %s" % [def.name, vm.unsupported])
	if vm.error != "":
		hud.notify("Script error: " + vm.error, UiTheme.HP_MID)
	_npc_running = false
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))
	hud.inventory.refresh()
	hud.skill_window.refresh()
	hud.status_window.refresh()


## warp "<map>",x,y from a script. Validates the map against the client.
func script_warp(to_map: String, x: int, y: int) -> void:
	var m := to_map
	if m == "SavePoint" or m == "Save":
		m = player.save_map
		x = player.save_cell.x
		y = player.save_cell.y
	if m == "Random":
		m = map_name
		x = 0
		y = 0
	if not MapAliases.exists(_res, m):
		hud.notify("%s is not in your client's data." % m, UiTheme.HP_MID)
		return
	if m == map_name:
		var c := Vector2i(x, y)
		if x <= 0 or y <= 0:
			c = sim.pathfinder.nearest_walkable(Vector2i(map.gat.width / 2, map.gat.height / 2), 60)
		player.walker = GridWalker.new(sim.pathfinder.nearest_walkable(c, 20))
		return
	_travel(m, Vector2i(x, y))


## A warp portal was stepped on: same-map portals teleport, others load the
## destination map (only if the client has it).
func _take_warp(to_map: String, to_cell: Vector2i) -> void:
	if to_map == map_name:
		player.walker = GridWalker.new(sim.pathfinder.nearest_walkable(to_cell, 10))
		player.warping = false
		return
	if not MapAliases.exists(_res, to_map):
		hud.notify("%s is not in your client's data." % to_map, UiTheme.HP_MID)
		player.warping = false
		return
	_travel(to_map, to_cell)


func script_effect(kind: String) -> void:
	var v: UnitView = views.get(player.id)
	if v:
		SpellFx.burst(self, v.global_position, "holy" if kind == "heal" else "neutral", 0)


func script_appearance_changed() -> void:
	var v: UnitView = views.get(player.id)
	if v:
		v.rebuild_player(_res)
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))


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
