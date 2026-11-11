extends Node3D
## Offline field: one map, the player, monsters and combat.
## The FieldSimulation is authoritative; this scene only presents it and
## turns mouse input into simulation commands.

@export var map_name := "prt_fild08"
@export var start_cell := Vector2i(170, 200)
@export var spawns := {"1002": 25, "1063": 12, "1007": 12}  # Poring, Lunatic, Fabre
@export var sim_seed := 1

const PICK_RADIUS_PX := 34.0

var map: RoMap
var sim: FieldSimulation
var player: SimUnit
var views: Dictionary = {}  # unit id -> UnitView
var camera: RoCamera
var hud: CombatHud
var walker: GridWalker:      # kept for tools/tests that inspect the player walker
	get:
		return player.walker if player else null
var _target_marker: MeshInstance3D
var _res: Node


func _ready() -> void:
	_res = get_node("/root/RoResources")
	if not _res.is_mounted:
		_res.mount()
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
	player = sim.add_player("Adventurer", start_cell, {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
	for mob in spawns:
		sim.spawn_random(mob, int(spawns[mob]))

	camera = RoCamera.new()
	camera.distance = 240.0
	add_child(camera)
	hud = CombatHud.new()
	add_child(hud)
	hud.camera = camera
	hud.numbers.camera = camera
	_build_marker()
	_consume_events()  # creates views for the initial spawns
	camera.follow = views[player.id]
	hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player), true)


func _build_marker() -> void:
	_target_marker = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.5, 4.5)
	quad.orientation = PlaneMesh.FACE_Y
	_target_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 0.4, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_marker.material_override = mat
	_target_marker.visible = false
	add_child(_target_marker)


# --- Input -------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var target := monster_at_screen(e.position)
	if target != 0:
		attack(target)
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


func _consume_events() -> void:
	var player_changed := false
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
				hud.numbers.spawn_offset(pv.global_position, Vector2(110, -40), "+%d BASE EXP" % ev.base, DamageNumbers.Kind.EXP_BASE)
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
			"revive":
				player_changed = player_changed or ev.id == player.id
	if player_changed:
		hud.update_player(player, sim.next_base_exp(player), sim.next_job_exp(player))


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
	var ok := v.build_player(_res, true, 2, 0) if u.is_player() else v.build_monster(_res)
	if not ok:
		push_warning("No sprite for %s (%s)" % [u.name, u.sprite])
	v.position = map.cell_pos_to_world(u.walker.position())
	views[u.id] = v
