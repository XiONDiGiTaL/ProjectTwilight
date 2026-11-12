class_name ArrowProjectile
extends Node3D
## Short-lived procedural arrow for bow normal attacks and bow skills.
## No client sprite is needed, so it works for every class and every arrow tier.

const GLOW_SHADER := preload("res://scripts/rendering/fx/fx_glow.gdshader")
const SPEED := 65.0
const ARC_HEIGHT := 1.1
const HIT_STAGGER := 0.16

var from := Vector3.ZERO
var to := Vector3.ZERO
var element := "neutral"
var delay := 0.0
var _age := 0.0
var _duration := 0.4


## Fires `hits` arrows from `from` to `to`, clearly staggered for multi-hit skills.
static func volley(parent: Node, from_pos: Vector3, to_pos: Vector3, p_element: String, hits: int) -> void:
	var count := maxi(1, hits)
	for i in count:
		var a := new()
		var jitter := Vector3(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), randf_range(-0.35, 0.35))
		a.from = from_pos + jitter
		a.to = to_pos + jitter * 0.4
		a.element = p_element
		a.delay = i * HIT_STAGGER
		parent.add_child(a)


func _ready() -> void:
	_duration = clampf(from.distance_to(to) / SPEED, 0.12, 0.7)
	_build_arrow()
	global_position = from
	_orient()
	visible = delay <= 0.0


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		visible = false
		return
	visible = true
	_age += delta
	var k := clampf(_age / _duration, 0.0, 1.0)
	var pos := from.lerp(to, k)
	pos.y += sin(k * PI) * ARC_HEIGHT
	global_position = pos
	_orient()
	if k >= 1.0:
		queue_free()


func _orient() -> void:
	if global_position.distance_squared_to(to) > 0.01:
		look_at(to, Vector3.UP)


func _build_arrow() -> void:
	var core := ElementPalette.core(element)
	var glow := ElementPalette.glow(element)
	var shaft_mat := _unshaded(core.darkened(0.45))
	var head_mat := _unshaded(glow)

	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.30, 0.30, 2.9)
	shaft.mesh = box
	shaft.material_override = shaft_mat
	shaft.position = Vector3(0, 0, -1.45)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)

	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 0.85
	cone.radial_segments = 6
	head.mesh = cone
	head.material_override = head_mat
	head.position = Vector3(0, 0, -2.15)
	head.rotation_degrees.x = -90.0
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)

	# Fletching and a small tip sparkle make the arrow read against bright ground.
	for side in [-1, 1]:
		var feather := MeshInstance3D.new()
		var feather_mesh := BoxMesh.new()
		feather_mesh.size = Vector3(0.55, 0.08, 0.55)
		feather.mesh = feather_mesh
		feather.material_override = head_mat
		feather.position = Vector3(0.22 * side, 0, 0.25)
		feather.rotation_degrees.z = 25.0 * side
		feather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(feather)

	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 1.35)
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = GLOW_SHADER
	halo_mat.set_shader_parameter("shape", 3)
	halo_mat.set_shader_parameter("billboard", true)
	halo_mat.set_shader_parameter("color", glow)
	halo_mat.set_shader_parameter("core", core)
	halo_mat.set_shader_parameter("intensity", 1.2)
	halo.mesh = quad
	halo.material_override = halo_mat
	halo.position = Vector3(0, 0, -2.15)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


static func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
