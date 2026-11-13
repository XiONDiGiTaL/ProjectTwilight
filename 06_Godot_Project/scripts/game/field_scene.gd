extends Node3D
## Offline field: one map, the player, monsters, loot and combat.
## The FieldSimulation is authoritative; this scene only presents it and
## turns input into simulation commands. Progress is saved locally.
##
## Controls: left-click monster = attack, item = pick up, ground = walk.
## I / Alt+E = inventory, Alt+A / S = status, Q / Alt+Q = equipment, K / Alt+S = skills,
## F1-F9 = hotkey bar, Insert = sit / stand, U = cycle aura, M = minimap,
## Enter = chat / @commands / whispers, Esc = Settings, F12 = save now.

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
const ARROW_PROJECTILE := preload("res://scripts/rendering/fx/arrow_projectile.gd")

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
var _config_exp_rate := 100
var _config_job_exp_rate := 100
var _config_drop_rate := 100
## Co-op: the NetSession autoload while a session is active, else null.
## Host: NetSession owns and ticks the simulation; this scene only presents it.
## Client: `sim` is a RemoteSimulation that mirrors the host's map.
var _net: Node
var _net_host := false
var _net_client := false
var _hud_refresh_in := 0.0
var _audio: Node                  # GameAudio autoload (null in bare tool scenes)
var _leaving := false


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
	var ns := get_node_or_null("/root/NetSession")
	if ns != null and ns.is_active() and save_slot != "":
		_net = ns
		_net_host = ns.is_host()
		_net_client = ns.is_client()

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
	# In a session the host decides where everyone is.
	if _net_client:
		map_name = String(_net.local_map)
	elif _net_host and _net.host_map() != "":
		map_name = _net.host_map()

	map = RoMap.new()
	add_child(map)
	if not map.load_map(map_name):
		push_error("Could not load map %s" % map_name)
		return
	if _net != null:
		if not _enter_session(saved):
			return
	else:
		_build_offline_world(saved)
	_config_exp_rate = sim.rules.exp_rate
	_config_job_exp_rate = sim.rules.job_exp_rate
	_config_drop_rate = sim.rules.drop_rate
	var settings := _settings_autoload()
	if settings and not _net_client:
		settings.rate_preset_changed.connect(_apply_rate_preset)
		_apply_rate_preset(settings.rate_preset())
	_maybe_offer_training.call_deferred()
	for w in sim.warps:
		var wv := WarpPortalView.new()
		add_child(wv)
		wv.setup(w, map)

	camera = RoCamera.new()
	camera.distance = 240.0
	add_child(camera)
	if settings:
		var view: Vector3 = settings.camera_view()
		camera.distance = view.x
		camera.pitch_deg = view.y
		camera.yaw_deg = view.z
		if not settings.camera_view_changed.is_connected(_apply_camera_view):
			settings.camera_view_changed.connect(_apply_camera_view)
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
	hud.storage.deposit_requested.connect(func(i, n): sim.command_storage_deposit(player.id, i, n))
	hud.storage.withdraw_requested.connect(func(i, n): sim.command_storage_withdraw(player.id, i, n))
	hud.guild_window.bind(sim.guilds, player)
	hud.guild_window.invite_requested.connect(func(n): sim.command_guild_invite(player.id, n))
	hud.guild_window.kick_requested.connect(func(n): sim.command_guild_kick(player.id, n))
	hud.guild_window.leave_requested.connect(func(): sim.command_leave_guild(player.id))
	hud.guild_window.promote_requested.connect(func(n): sim.command_guild_promote(player.id, n))
	hud.guild_window.demote_requested.connect(func(n): sim.command_guild_demote(player.id, n))
	hud.guild_window.transfer_requested.connect(func(n): sim.command_guild_transfer(player.id, n))
	hud.guild_window.disband_requested.connect(func(): sim.command_guild_disband(player.id))
	hud.guild_window.motd_requested.connect(func(t): sim.command_guild_set_motd(player.id, t))
	hud.guild_window.accept_requested.connect(func(gid): sim.command_guild_accept(player.id, gid))
	hud.guild_window.decline_requested.connect(func(gid): sim.command_guild_decline(player.id, gid))
	hud.storage.guild_deposit_requested.connect(func(i, n): sim.command_guild_deposit(player.id, i, n))
	hud.storage.guild_withdraw_requested.connect(func(i, n): sim.command_guild_withdraw(player.id, i, n))
	hud.storage.storage_closed.connect(func():
		sim.close_storage(player.id)
		sim.close_guild_storage(player.id))
	hud.skill_window.available = sim.available_skills
	hud.skill_window.requirements = sim.skill_requirements_unmet
	hud.skill_window.bind_unit(player, sim.skill_db)
	hud.dialog.chosen.connect(_on_dialog_choice)
	hud.skill_window.learn_requested.connect(func(c): sim.command_learn_skill(player.id, c))
	hud.skill_window.use_requested.connect(func(c): sim.command_use_skill(player.id, c))
	hud.hotkeys.bind_unit(player, sim.item_db, sim.skill_db)
	hud.hotkeys.activate_requested.connect(use_hotkey)
	hud.chat.submitted.connect(_on_chat_submit)
	hud.chat.dm_reply_requested.connect(_on_chat_dm_reply)
	hud.chat.portrait_capture_requested.connect(_capture_portrait)
	_build_marker()
	if _net_host:
		# The simulation was already running (or NetSession will drain its
		# setup events), so present what exists; the handlers skip duplicates.
		for id in sim.units:
			_create_view(sim.units[id])
		for nid in sim.npcs:
			_create_npc_view(nid)
		for gid in sim.ground_items:
			_create_item_view(gid)
	_consume_events()  # creates views for the initial spawns
	camera.follow = views[player.id]
	(views[player.id] as UnitView).update_weapon(_res)
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player), true)
	if loaded_msg != "":
		hud.notify(loaded_msg, UiTheme.HP_MID)
	hud.map_banner(String(sim.map_info.get("name", map_name)), String(sim.map_info.get("subtitle", "")))
	hud.bind_minimap(map.gat, sim, player.id, String(sim.map_info.get("name", map_name)))
	_refresh_social()
	_audio = get_node_or_null("/root/GameAudio")
	if _audio:
		_audio.play_map_music(map_name)
	if _net != null:
		_net.notice_received.connect(_on_net_notice)
		_net.chat_received.connect(_on_net_chat)
		_net.direct_message_received.connect(_on_net_dm)
		_net.roster_changed.connect(_on_roster_changed)
		_net.session_ended.connect(_leave_to_menu)
		_net.session_failed.connect(_leave_to_menu)
		if _net_host:
			_net.host_action.connect(_on_chat_action)
			if not _net.code_announced:
				_net.code_announced = true
				DisplayServer.clipboard_set(String(_net.invitation_code))
				hud.notify("Hosting co-op. Invitation code copied:  %s   (@code shows it again)" % String(_net.invitation_code), UiTheme.ACCENT)
		else:
			_net.map_entered.connect(_on_net_map_entered)
			_net.dialog_received.connect(_on_net_dialog)
			hud.dialog.number_entered.connect(func(v):
				if _net_dialog_open:
					_net_dialog_open = false
					_net.answer_dialog(int(v)))


## Offline world: this scene owns and ticks the simulation.
func _build_offline_world(saved: Dictionary) -> void:
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


## Co-op world. Host: the character enters (or is already in) one of
## NetSession's map simulations. Client: a replica fed by the host.
func _enter_session(saved: Dictionary) -> bool:
	if _net_client:
		var replica := RemoteSimulation.new(map.gat, _net)
		_net.attach_remote(replica)
		sim = replica
		player = sim.units.get(int(_net.local_unit_id))
		if player == null:
			_leave_to_menu("The host did not send your character.")
			return false
		if not saved.is_empty():
			player.hotkeys = (saved.get("hotkeys", player.hotkeys) as Array).duplicate(true)
		return true
	if _net.host_map() == "":
		if saved.is_empty():
			_leave_to_menu("Hosting needs a saved character.")
			return false
		var entered: Dictionary = _net.host_enter(saved, map_name, _res)
		if entered.is_empty():
			_leave_to_menu("Could not load %s." % map_name)
			return false
	sim = _net.host_sim()
	player = _net.host_unit()
	if sim == null or player == null:
		_leave_to_menu("The session lost your character.")
		return false
	return true


func _on_net_notice(text: String, ok: bool) -> void:
	hud.notify(text, UiTheme.ACCENT if ok else UiTheme.HP_MID)


func _on_net_chat(from: String, text: String) -> void:
	hud.chat.add_say(from, text)
	for v in views.values():
		var uv := v as UnitView
		if uv.unit != null and uv.unit.is_player() and uv.unit.name == from:
			hud.numbers.spawn(uv.head_position(), text.left(40), DamageNumbers.Kind.MISS)


## Client: the host moved us to another map (portal, warp, save point).
func _on_net_map_entered(_map: String) -> void:
	if _leaving:
		return
	_leaving = true
	player.walker = GridWalker.new(player.walker.cell)
	save_now()
	hud.transition("Traveling to %s" % String(sim.map_db.get(String(_net.local_map), {}).get("name", _net.local_map)))
	set_process(false)
	await get_tree().create_timer(0.3).timeout
	_skip_exit_save = true
	get_tree().change_scene_to_file("res://scenes/game/field.tscn")


## Client: an NPC script running on the host shows its dialog here.
func _on_net_dialog(kind: String, payload: Dictionary) -> void:
	match kind:
		"page":
			_net_dialog_open = true
			hud.dialog.show_page(String(payload.get("speaker", "")), String(payload.get("text", "")), payload.get("options", ["Next"]))
		"select":
			_net_dialog_open = true
			hud.dialog.show_page(String(payload.get("speaker", "")), String(payload.get("text", "")), payload.get("options", []), true)
		"number":
			_net_dialog_open = true
			hud.dialog.ask_number(String(payload.get("speaker", "")), String(payload.get("text", "")), int(payload.get("lo", 0)), int(payload.get("hi", 0)))
		"close":
			_net_dialog_open = false
			hud.dialog.close()
		"effect":
			var n := String(payload.get("name", ""))
			script_effect("heal" if n.contains("HEAL") or n == "312" or n == "313" else "sparkle")
		"storage":
			_net_dialog_open = false
			hud.dialog.close()
			hud.storage.open("Kafra", player, sim.item_db)
		"guild_storage":
			_net_dialog_open = false
			hud.dialog.close()
			var g: Dictionary = sim.guilds.guilds.get(player.guild_id, {})
			if not g.is_empty():
				hud.storage.open_guild(String(g.get("name", "Guild")), player, g.get("storage"), sim.item_db)


var _net_dialog_open := false


## Saves, closes any session and returns to the title screen.
func _leave_to_menu(message := "") -> void:
	if _leaving and message == "":
		return
	_leaving = true
	if player != null and not _skip_exit_save:
		save_now()
	_skip_exit_save = true
	var session := get_node_or_null("/root/GameSession")
	if session:
		session.notice = message
	var ns := get_node_or_null("/root/NetSession")
	if ns:
		ns.leave()
	set_process(false)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")


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
	var line := text.strip_edges()
	if line == "@leave" or line == "@quit":
		_leave_to_menu("")
		return
	if line.begins_with("/w ") or line.begins_with("/dm ") or line.begins_with("/tell "):
		var rest := line.substr(line.find(" ") + 1).strip_edges()
		var pair := rest.split(" ", false, 1)
		if pair.size() < 2:
			hud.chat.add_system("Usage: /w <name> <message>")
			return
		var target := String(pair[0]).strip_edges()
		var message := String(pair[1]).strip_edges()
		if target == "" or message == "":
			hud.chat.add_system("Usage: /w <name> <message>")
			return
		if _net == null:
			hud.chat.add_system("Whispers need a co-op session.")
			return
		hud.chat.record_outgoing_dm(target, message)
		_net.whisper(target, message)
		return
	if _net != null:
		if line == "@code":
			if _net_host:
				DisplayServer.clipboard_set(String(_net.invitation_code))
				hud.notify("Invitation code copied:  %s" % String(_net.invitation_code), UiTheme.ACCENT)
			else:
				hud.notify("Only the host has the invitation code.", UiTheme.TEXT_DIM)
			return
		if line == "@who":
			hud.notify("In this session:  %s" % ", ".join(PackedStringArray(_net.player_names())) if _net_host else "Ask the host: only the host lists players.", UiTheme.ACCENT)
			return
		_net.say(line)      # the host runs @commands and relays speech
		return
	var r := ChatCommands.execute(sim, player, text)
	if r.has("action"):
		_on_chat_action(r.action)
	var msg := String(r.get("text", ""))
	if msg != "":
		if line.begins_with("@"):
			hud.notify(msg, UiTheme.ACCENT if bool(r.get("ok", true)) else UiTheme.HP_MID)
		else:
			hud.chat.add_say(player.name, msg.trim_prefix("You say: "), true)


func _on_chat_dm_reply(to: String, text: String) -> void:
	if _net == null:
		hud.chat.add_system("Whispers need a co-op session.")
		return
	_net.whisper(to, text)


func _on_net_dm(from: String, text: String) -> void:
	hud.chat.receive_dm(from, text)


func _on_roster_changed(roster: Array) -> void:
	_set_contacts(roster)


## Keeps the community tab current with the live session roster. The local
## player is always present, even outside co-op, so the portrait and current
## map have a home in the community view.
func _refresh_social() -> void:
	if hud == null or hud.chat == null or player == null:
		return
	var roster: Array = _net.directory() if _net != null else []
	_set_contacts(roster)


func _set_contacts(roster: Array) -> void:
	if hud == null or hud.chat == null or player == null:
		return
	var merged: Dictionary = {}
	for entry in roster:
		if entry is Dictionary and String(entry.get("name", "")) != "":
			merged[String(entry.get("name", ""))] = entry
	var mine := _contact_for(player)
	mine["self"] = true
	mine["portrait_path"] = hud.chat.my_portrait()
	merged[String(mine.get("name", ""))] = mine
	hud.chat.set_contacts(merged.values())


func _contact_for(u: SimUnit) -> Dictionary:
	var map_label := String(sim.map_info.get("name", map_name))
	return {
		"name": u.name,
		"job": u.job,
		"level": u.level,
		"job_level": u.job_level,
		"map": map_label,
		"online": true,
		"male": u.male,
		"hair_style": u.hair_style,
		"hair_color": u.hair_color,
		"cloth_color": u.cloth_color,
		"sprite": u.sprite,
	}


## Saves a close-up around the player's head as the community avatar. The
## caller gets the image after the current draw; no game asset is written to
## the repository, only the player's user:// folder.
func _capture_portrait() -> void:
	if player == null or camera == null or not views.has(player.id):
		return
	await RenderingServer.frame_post_draw
	var v: UnitView = views.get(player.id)
	if v == null:
		return
	var at := camera.unproject_position(v.head_position())
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	var rect := Rect2i(roundi(at.x) - 72, roundi(at.y) - 92, 144, 144).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		hud.chat.add_system("The portrait frame fell outside the view.")
		return
	var crop := image.get_region(rect)
	crop.resize(96, 96, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute("user://avatars")
	var safe := player.name.to_lower().replace(" ", "_").replace("/", "_")
	var path := "user://avatars/%s.png" % safe
	var err := crop.save_png(path)
	if err != OK:
		hud.chat.add_system("The portrait could not be saved.")
		return
	hud.chat.set_my_portrait(path)
	_refresh_social()
	hud.notify("Portrait captured for %s." % player.name, UiTheme.ACCENT)


func _on_chat_action(a: Dictionary) -> void:
	match String(a.get("kind", "")):
		"warp":
			script_warp(String(a.map), int(a.x), int(a.y))
		"rate_preset":
			_apply_rate_preset_action(int(a.get("multiplier", 0)))


## @rates presets go through Settings, so the command and the window share the
## same stored choice. An unchanged choice still reapplies and announces itself.
func _apply_rate_preset_action(multiplier: int) -> void:
	var settings := _settings_autoload()
	if settings == null:
		_apply_rate_preset(multiplier)
		return
	var before: int = settings.rate_preset()
	settings.set_rate_preset(multiplier)
	if before == multiplier or not settings.rate_preset_changed.is_connected(_apply_rate_preset):
		_apply_rate_preset(multiplier)


func _settings_autoload() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree else null


func _apply_camera_view(distance: float, pitch: float, yaw: float) -> void:
	if camera == null:
		return
	camera.distance = distance
	camera.pitch_deg = pitch
	camera.yaw_deg = yaw


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				if not hud.chat.is_open():
					hud.toggle_settings()
					get_viewport().set_input_as_handled()
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
			KEY_G:
				if hud.guild_window.visible:
					hud.guild_window.toggle(false)
				else:
					hud.guild_window.open(sim.guilds, player)
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
		var u: SimUnit = sim.units.get(id)
		if u == null or u.is_player() or u.dead:
			continue
		var v: UnitView = views[id]
		var feet := camera.unproject_position(v.global_position)
		var head := camera.unproject_position(v.head_position())
		var d := Geometry2D.get_closest_point_to_segment(p, feet, head).distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


## Player id whose sprite is under the screen point, or 0.
func player_at_screen(p: Vector2) -> int:
	var best := 0
	var best_d := PICK_RADIUS_PX
	for id in views:
		var u: SimUnit = sim.units.get(id)
		if u == null or not u.is_player() or u.dead:
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
	var t: SimUnit = sim.units.get(target_id)
	if t == null:
		return false
	hud.set_target(t.id, t.name, t.level, t.hp, t.max_hp)
	return true


# --- Saving --------------------------------------------------------------------

## Settings presets override server config rates for this field, live while the
## window is open. RATE_PRESET_NONE restores the rates loaded at field start.
func _apply_rate_preset(multiplier: int) -> void:
	if sim == null or _net_client:
		return
	if multiplier <= 0:
		sim.rules.exp_rate = _config_exp_rate
		sim.rules.job_exp_rate = _config_job_exp_rate
		sim.rules.drop_rate = _config_drop_rate
		_notify_rate_change("Rates restored")
		return
	sim.rules.apply_rate_multiplier(multiplier)
	_notify_rate_change("Rates set")


## The field ready path applies the stored preset before the HUD exists; only
## later live changes announce themselves.
func _notify_rate_change(prefix: String) -> void:
	if hud == null:
		return
	hud.notify("%s:  %s" % [prefix, sim.rules.rate_summary()], UiTheme.ACCENT)


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
	if sim == null or player == null:
		return
	if not _net_host:
		sim.tick(delta * 1000.0)    # the host's simulations are ticked by NetSession
	_consume_events()
	if _net_client:
		# Replicated HP / SP / EXP arrive as state, not always as events.
		_hud_refresh_in -= delta
		if _hud_refresh_in <= 0.0:
			_hud_refresh_in = 0.25
			hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))
	if views.has(player.id):
		map.update_occlusion(camera, (views[player.id] as Node3D).global_position)
	for v in views.values():
		(v as UnitView).camera_yaw = camera.yaw_deg
	for id in sim.units:
		var pu: SimUnit = sim.units[id]
		if pu != null and pu.is_player():
			hud.update_player_plate(pu.id, pu.hp, pu.max_hp)
	if not player.walker.is_moving():
		_target_marker.visible = false
	var mouse := get_viewport().get_mouse_position()
	var hovered_player := player_at_screen(mouse)
	hud.set_hovered_player(hovered_player)
	if hovered_player != 0:
		hud.hover_tag("", Vector2.ZERO)
	else:
		var monster := monster_at_screen(mouse)
		if monster != 0:
			var mv: UnitView = views[monster]
			hud.hover_tag(mv.unit.name, camera.unproject_position(mv.head_position()), true)
		else:
			var hover := item_at_screen(mouse)
			if hover != 0:
				var iv: GroundItemView = item_views[hover]
				hud.hover_tag(iv.item_name, camera.unproject_position(iv.head_position()))
			else:
				hud.hover_tag("", Vector2.ZERO)
	if hud.dialog.visible and player.walker.is_moving():
		hud.dialog.close()
		if _net_dialog_open:
			_net_dialog_open = false
			_net.answer_dialog(255)    # walking away cancels the whole script
	# Walking away from the merchant closes the shop (the simulation also enforces range).
	if hud.shop.visible and sim._open_shop_of(player).is_empty():
		hud.shop.toggle(false)
		hud.notify("You walked away from the shop.", UiTheme.TEXT_DIM)
	if hud.storage.visible:
		if hud.storage.guild_mode:
			if sim._open_guild_storage_of(player).is_empty():
				hud.storage.toggle(false)
				hud.notify("You walked away from the guild storage.", UiTheme.TEXT_DIM)
		elif sim._open_storage_of(player).is_empty():
			hud.storage.toggle(false)
			hud.notify("You walked away from the Kafra.", UiTheme.TEXT_DIM)
	_autosave_in -= delta
	if _autosave_in <= 0.0:
		_autosave_in = AUTOSAVE_SEC
		save_now()


func _consume_events() -> void:
	var player_changed := false
	var inventory_changed := false
	var batch: Array = _net.take_local_events() if _net_host else sim.drain_events()
	for ev in batch:
		match ev.type:
			"spawn":
				var spawned: SimUnit = sim.units.get(ev.id)
				if spawned != null:
					_create_view(spawned)
			"despawn":
				remove_view(ev.id, true)
			"appearance":
				var look: UnitView = views.get(ev.id)
				if look:
					look.rebuild_player(_res)
					look.update_weapon(_res)
			"attack":
				var a: SimUnit = sim.units.get(ev.id)
				var av: UnitView = views.get(ev.id)
				if a and av and av.sprite:
					av.sprite.play_once("attack", minf(a.attack_motion, a.attack_interval))
				if a and _audio:
					if a.is_player():
						_audio.swing(a.weapon_type, _vol(a))
					else:
						_audio.monster(a.sprite, "attack", _vol(a))
			"projectile":
				var pv: UnitView = views.get(ev.id)
				var tv: UnitView = views.get(ev.target)
				if pv and tv:
					ARROW_PROJECTILE.volley(self, pv.projectile_origin(), tv.projectile_origin(), String(ev.element), int(ev.get("hits", 1)))
			"damage":
				_on_damage(ev)
				player_changed = player_changed or ev.dst == player.id
			"death":
				hud.unit_died(ev.id)
				var dead_u: SimUnit = sim.units.get(ev.id)
				if dead_u and _audio:
					if dead_u.is_player():
						_audio.play("die_male.wav", _vol(dead_u))
					elif not _audio.monster(dead_u.sprite, "die", _vol(dead_u)):
						_audio.play("20th_monster_die.wav", _vol(dead_u) * 0.6)
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
					if _audio:
						_audio.play("levelup.wav" if ev.kind == "base" else "effect/st_job_level_up.wav")
					player_changed = true
					save_now()
			"revive":
				if ev.id == player.id and ev.has("to_map"):
					hud.notify("You return to your save point.", UiTheme.TEXT)
					if not _net_client:      # a client is moved by the host
						player.dead = false
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
					if _audio and int(ev.amount) > 0:
						_audio.play("_heal_effect.wav", _vol(hv.unit) * 0.9, 250)
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
				if ev.id == player.id and _audio:
					_audio.play("effect/ef_portal.wav")
				if ev.id == player.id and not _net_client:
					_take_warp(String(ev.to_map), ev.to_cell)
			"npc_spawn":
				_create_npc_view(ev.npc)
			"npc_open":
				if ev.id == player.id and sim.npcs.has(ev.npc):
					var npc: Dictionary = sim.npcs[ev.npc]
					if String(npc.get("kind", "shop")) == "script":
						if not _net_client:      # the host runs scripts for its clients
							_run_npc_script(npc)
					elif String(npc.get("kind", "shop")) == "job_guide":
						_job_dialog_start(npc)
					elif String(npc.get("kind", "shop")) == "kafra":
						if sim.command_open_storage(player.id, npc.id):
							hud.storage.open(npc.name, player, sim.item_db)
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
					if _audio:
						_audio.play("effect/ef_beginspell.wav", _vol(cv.unit))
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
					if _audio:
						_audio.skill(String(ev.get("skill", "")), String(ev.element), _vol(tv.unit))
			"skill_fx":
				var from_v: UnitView = views.get(ev.id)
				var to_pos := map.cell_to_world(ev.cell.x, ev.cell.y)
				var tid := int(ev.get("target", 0))
				if tid != 0 and views.has(tid):
					to_pos = (views[tid] as UnitView).global_position
				_play_fx(String(ev.fx), from_v.global_position if from_v else to_pos, to_pos, String(ev.element), int(ev.hits), int(ev.area))
				if _audio and from_v:
					_audio.skill(String(ev.get("skill", "")), String(ev.element), _vol(from_v.unit))
				if from_v and from_v.sprite and String(ev.fx) != "support" and String(ev.fx) != "aura":
					from_v.sprite.play_once("attack", 450.0)
			"status":
				var stv: UnitView = views.get(ev.id)
				if stv:
					var stname := StatusRules.display_name(String(ev.status))
					if ev.on:
						var deb := StatusRules.is_debuff(String(ev.status))
						if _audio:
							_audio.status(String(ev.status), _vol(stv.unit))
						hud.numbers.spawn(stv.head_position(), stname.to_upper(), DamageNumbers.Kind.MISS)
						if ev.id == player.id:
							hud.notify(("%s!" if deb else "%s") % stname, UiTheme.HP_MID if deb else UiTheme.ACCENT)
					elif ev.id == player.id:
						hud.notify("%s wore off." % stname, UiTheme.TEXT_DIM)
					if sim.units.has(ev.id):
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
			"storage":
				if ev.id == player.id:
					hud.notify(ev.text, UiTheme.TEXT if ev.ok else UiTheme.HP_MID)
					hud.storage.refresh()
					inventory_changed = true
			"chat":
				if String(ev.get("channel", "")) == "guild":
					hud.chat.add_guild(String(ev.get("from", "?")), String(ev.get("text", "")))
			"guild", "guild_storage":
				if ev.id == player.id:
					hud.notify(ev.text, UiTheme.TEXT if ev.ok else UiTheme.HP_MID)
					if ev.type == "guild_storage":
						hud.storage.refresh()
					else:
						hud.guild_window.refresh()
					inventory_changed = true
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
		_refresh_social()
		hud.status_window.refresh()
		hud.inventory.refresh()
		hud.equipment_window.refresh()
		hud.skill_window.refresh()
		hud.hotkeys.refresh()


func _on_damage(ev: Dictionary) -> void:
	var dst: SimUnit = sim.units.get(ev.dst)
	var src: SimUnit = sim.units.get(ev.src)
	var dv: UnitView = views.get(ev.dst)
	if dv == null or dst == null or src == null:
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
	if _audio and not ev.miss:
		if src.is_player():
			_audio.hit(src.weapon_type, _vol(dst))
			if not dst.is_player() and not dst.dead:
				_audio.monster(dst.sprite, "damage", _vol(dst) * 0.8)
		elif dst.is_player():
			_audio.taken(_vol(dst))
	# Monster HP bars appear once a player attacks them and stay until death.
	if not dst.is_player() and src.is_player():
		hud.engage(dst.id, dst.hp + (ev.amount if not ev.miss else 0), dst.max_hp, dv.head_position, dst.name)
		if ev.src == player.id and hud.target_id() != dst.id:
			hud.set_target(dst.id, dst.name, dst.level, dst.hp + (ev.amount if not ev.miss else 0), dst.max_hp)
	hud.update_hp(dst.id, dst.hp, dst.max_hp)


## Loudness of something happening at a unit, by its distance from the player.
func _vol(u: SimUnit) -> float:
	if u == null or player == null:
		return 1.0
	return GameAudioFalloff.at(Vector2(u.walker.cell).distance_to(Vector2(player.walker.cell)))


## Removes a unit's visual and every HUD element tied to it. Despawn events and
## capture tools use this one path so a freed view cannot leave a plate anchor.
func remove_view(unit_id: int, died := false) -> void:
	var v: UnitView = views.get(unit_id)
	if hud != null:
		if died:
			hud.unit_died(unit_id)
		hud.remove_player_plate(unit_id)
	if v != null:
		v.queue_free()
	views.erase(unit_id)
	_casts.erase(unit_id)
	if sim is RemoteSimulation:
		(sim as RemoteSimulation).forget_unit(unit_id)


func _create_view(u: SimUnit) -> void:
	if views.has(u.id):
		return
	var v := UnitView.new()
	v.unit = u
	v.map = map
	add_child(v)
	var ok := v.build_player(_res, u.male, u.hair_style, u.hair_color) if u.is_player() else v.build_monster(_res)
	if not ok:
		push_warning("No sprite for %s (%s)" % [u.name, u.sprite])
	v.position = map.cell_pos_to_world(u.walker.position())
	views[u.id] = v
	if u.is_player() and hud != null:
		var tag_color: Color = BotBrain.ROLE_COLORS.get(u.bot_role, Color(1.0, 0.93, 0.7)) if u.is_bot else Color(1.0, 0.93, 0.7)
		hud.add_player_plate(u.id, u.name, u.hp, u.max_hp, v.head_position, tag_color)
	if u.is_player():
		v.update_weapon(_res)


# --- Job guide dialogue ------------------------------------------------------------

const FIRST_JOBS := ["swordman", "mage", "archer", "acolyte", "merchant", "thief"]
var _dialog_npc: Dictionary = {}
var _dialog_state := ""
var _dialog_job := ""


## Classic second jobs per first job; jobs.json decides which are playable.
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


## Every job whose `parent` is this class (and is a higher tier). Used for the
## second -> transcendent and transcendent -> third-job steps.
func _advanced_jobs(job: String, tier: int) -> Array:
	var out: Array = []
	for id in sim.job_db:
		var j: Dictionary = sim.job_db[id]
		if String(j.get("parent", "")) == job and int(j.get("tier", 0)) > tier:
			out.append(String(id))
	return out


## Offers the next step of an already-chosen line: transcendence, then the
## third job. Requirements live in jobs.json (Base Level and Job Level).
func _advanced_job_dialog(npc: Dictionary, jobs: Array, tier: int) -> void:
	var first: Dictionary = sim.job_db[jobs[0]]
	var need_base := int(first.get("min_parent_base_level", 99))
	var need_job := int(first.get("min_parent_job_level", 70))
	var jn := String(sim.job_db.get(player.job, {}).get("name", player.job))
	var text := ""
	if tier == 2:
		text = "Your %s path can transcend its mortal limits. At Base Level %d and Job Level %d you may be reborn into a transcendent class (you are Base %d / Job %d)." % [jn, need_base, need_job, player.level, player.job_level]
	else:
		text = "You have mastered your transcendent path. At Base Level %d and Job Level %d you may take the third job and continue to Base Level 150 (you are Base %d / Job %d)." % [need_base, need_job, player.level, player.job_level]
	_dialog_state = "choose2"
	_dialog_choices = jobs
	var labels: Array = []
	for j in jobs:
		var reason := sim.job_change_unmet(player, j)
		labels.append(String(sim.job_db[j].name) + ("" if reason == "" else "  (locked)"))
	labels.append("Not yet")
	hud.dialog.show_page(npc.name, text, labels)


func _job_dialog_start(npc: Dictionary) -> void:
	_dialog_npc = npc
	var tier := int(sim.job_db.get(player.job, {}).get("tier", 0))
	if tier == 1:
		_second_job_dialog(npc)
		return
	if tier == 2 or tier == 3:
		var next_jobs := _advanced_jobs(player.job, tier)
		if not next_jobs.is_empty():
			_advanced_job_dialog(npc, next_jobs, tier)
			return
		var current_name := String(sim.job_db.get(player.job, {}).get("name", player.job))
		_dialog_state = "done"
		var closed_text := "No further job path is open for a %s in this build." % current_name
		if tier == 3:
			closed_text = "You have already walked the furthest path available to a %s." % current_name
		hud.dialog.show_page(npc.name, closed_text, ["Close"])
		return
	if player.job != "novice":
		var jn := String(sim.job_db.get(player.job, {}).get("name", player.job))
		_dialog_state = "done"
		var text := "You have already chosen your path, %s. Train hard and come back stronger!" % jn
		if tier >= 4:
			text = "You have already taken the third job, %s. Base Level 150 is now open to you." % jn
		hud.dialog.show_page(npc.name, text, ["Close"])
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
	if _net_dialog_open:
		_net_dialog_open = false
		_net.answer_dialog(i)
		return
	match _dialog_state:
		"choose":
			if i >= FIRST_JOBS.size():
				hud.dialog.close()
				return
			_dialog_job = FIRST_JOBS[i]
			_dialog_state = "confirm"
			var jn := String(sim.job_db.get(_dialog_job, {}).get("name", _dialog_job))
			var note := "" if not (sim.job_db.get(_dialog_job, {}).get("skills", []) as Array).is_empty() else "\n\n(Its guild skills are still being prepared in this build.)"
			var kit := sim.first_job_weapon_name(_dialog_job)
			var kit_note := "\n\nGuild issue: %s." % kit if kit != "" else ""
			hud.dialog.show_page(_dialog_npc.name, "Become a %s? This choice is permanent.%s%s" % [jn, note, kit_note], ["Become a %s" % jn, "Go back"])
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
	if _net_client or _leaving:
		return      # a client travels only when the host says so
	if _net_host:
		# NetSession moves the character between its map simulations.
		if not _net.host_travel(to_map, to_cell, _res):
			hud.notify("Could not travel to %s." % to_map, UiTheme.HP_MID)
			player.warping = false
			return
		player = _net.host_unit()
	else:
		player.walker = GridWalker.new(to_cell)
		player.target_id = 0
	_leaving = true
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
		npc_world = WorldBuilder.world(res)     # one parsed copy, shared with the co-op host
	return npc_world


## First arrival in the Training Grounds: ask whether to train or skip to Prontera.
func _maybe_offer_training() -> void:
	if _net_client or player == null:
		return
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
	if _npc_running or _net_client:
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


## An rAthena Kafra script ran `openstorage`: show the glass storage window.
func show_script_storage() -> void:
	var npc := sim._open_storage_of(player)
	if npc.is_empty():
		return
	hud.dialog.close()
	hud.storage.open(String(npc.name), player, sim.item_db)


## A guild Kafra script ran `guildopenstorage`: show the shared bag.
func show_guild_storage() -> void:
	var g := sim._open_guild_storage_of(player)
	if g.is_empty():
		return
	hud.dialog.close()
	hud.storage.open_guild(String(g.name), player, g.get("storage"), sim.item_db)


## warp "<map>",x,y from a script. Validates the map against the client.
func script_warp(to_map: String, x: int, y: int) -> void:
	if _net_client:
		return
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
	if npc_views.has(nid) or not sim.npcs.has(nid):
		return
	var v := NpcView.new()
	add_child(v)
	v.setup(sim.npcs[nid], _res, map)
	npc_views[nid] = v


func _create_item_view(gid: int) -> void:
	var g: Dictionary = sim.ground_items.get(gid, {})
	if g.is_empty() or item_views.has(gid):
		return
	var v := GroundItemView.new()
	add_child(v)
	v.setup(g, sim.item_db.get(str(g.item), {}), map)
	item_views[gid] = v


func _remove_item_view(gid: int) -> void:
	if item_views.has(gid):
		(item_views[gid] as Node).queue_free()
		item_views.erase(gid)
