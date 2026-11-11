extends Node3D
## Offline exploration scene: one map, one player, click-to-walk.
## First step toward the Phase 4 playable build.

@export var map_name := "prontera"
@export var start_cell := Vector2i(156, 180)

var map: RoMap
var walker: GridWalker
var pathfinder: GridPathfinder
var avatar: PlayerAvatar
var camera: RoCamera
var _hud: Label
var _target_marker: MeshInstance3D


func _ready() -> void:
	var res: Node = get_node("/root/RoResources")
	if not res.is_mounted:
		res.mount()
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
	pathfinder = GridPathfinder.new(map.gat)
	var spawn := pathfinder.nearest_walkable(start_cell, 20)
	walker = GridWalker.new(spawn)

	avatar = PlayerAvatar.new()
	avatar.name = "Player"
	avatar.walker = walker
	avatar.map = map
	add_child(avatar)
	avatar.build(res, "초보자", true, 2, 0)

	camera = RoCamera.new()
	camera.distance = 260.0
	camera.follow = avatar
	add_child(camera)

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

	var ui := CanvasLayer.new()
	add_child(ui)
	_hud = Label.new()
	_hud.position = Vector2(8, 8)
	ui.add_child(_hud)
	var back := Button.new()
	back.text = "◀ Menu"
	back.position = Vector2(8, 680)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	ui.add_child(back)


## Orders the player to walk to `cell`. Returns false if unreachable.
func walk_to(cell: Vector2i) -> bool:
	var path := pathfinder.find_path(walker.planning_origin(), cell)
	if path.is_empty():
		return false
	walker.walk(path)
	_target_marker.position = map.cell_to_world(cell.x, cell.y) + Vector3(0, 0.3, 0)
	_target_marker.visible = true
	return true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var from := camera.project_ray_origin(e.position)
		var dir := camera.project_ray_normal(e.position)
		var cell := map.pick_cell(from, dir)
		if cell.x >= 0:
			walk_to(cell)


func _process(delta: float) -> void:
	if walker == null:
		return
	walker.advance(delta * 1000.0)
	avatar.camera_yaw = camera.yaw_deg
	if not walker.is_moving():
		_target_marker.visible = false
	_hud.text = "%s  (%d, %d)  dir %d  |  left-click to walk, right-drag to rotate, wheel to zoom" % [
		map_name, walker.cell.x, walker.cell.y, walker.direction]
