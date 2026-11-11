class_name CastingCircle
extends Node3D
## Element-coloured magic circle under a caster, with a rising light pillar
## and sparkles. Fades in on cast start, fills its rune band with progress,
## flashes on release and fades out (or collapses quickly when interrupted).

const CIRCLE_SHADER := preload("res://scripts/rendering/fx/casting_circle.gdshader")
const GLOW_SHADER := preload("res://scripts/rendering/fx/fx_glow.gdshader")
const BASE_RADIUS := 11.0   # world units (a cell is ~5)
const FADE_IN := 0.25
const FADE_OUT := 0.45

var element := "neutral"
var level := 1
var duration := 1.0          # seconds
var elapsed := 0.0
var _state := 0              # 0 casting, 1 released, 2 interrupted
var _out := 0.0
var _circle: MeshInstance3D
var _pillar: MeshInstance3D
var _sparks: GPUParticles3D
var _circle_mat := ShaderMaterial.new()
var _pillar_mat := ShaderMaterial.new()


static func make(p_element: String, p_level: int, p_duration_s: float) -> CastingCircle:
	var c := CastingCircle.new()
	c.element = p_element
	c.level = p_level
	c.duration = maxf(p_duration_s, 0.05)
	return c


func radius() -> float:
	return BASE_RADIUS * (1.0 + 0.035 * (level - 1))


func _ready() -> void:
	var core := ElementPalette.core(element)
	var glow := ElementPalette.glow(element)
	var r := radius()
	_circle = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(r * 2.0, r * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	_circle.mesh = quad
	_circle.position.y = 0.35
	_circle_mat.shader = CIRCLE_SHADER
	_circle_mat.set_shader_parameter("core_color", core)
	_circle_mat.set_shader_parameter("glow_color", glow)
	_circle_mat.set_shader_parameter("motif", ElementPalette.motif(element))
	_circle_mat.set_shader_parameter("rune_seed", float(hash(element) % 97))
	_circle.material_override = _circle_mat
	_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_circle)

	_pillar = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.62
	cyl.bottom_radius = r * 0.7
	cyl.height = 26.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 48
	_pillar.mesh = cyl
	_pillar.position.y = 13.0
	_pillar_mat.shader = GLOW_SHADER
	_pillar_mat.set_shader_parameter("shape", 4)
	_pillar_mat.set_shader_parameter("color", glow)
	_pillar_mat.set_shader_parameter("core", core)
	_pillar.material_override = _pillar_mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)

	_sparks = make_sparks(core, glow, r * 0.8, 28, 1.6, 9.0)
	add_child(_sparks)
	_apply(0.0)


## Rising sparkles emitted from a ring (shared with auras and spell bursts).
static func make_sparks(core: Color, glow: Color, ring_r: float, amount: int, lifetime: float, rise: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = lifetime
	ps.local_coords = true
	ps.visibility_aabb = AABB(Vector3(-ring_r - 4, -2, -ring_r - 4), Vector3(ring_r * 2 + 8, rise * lifetime + 20, ring_r * 2 + 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = ring_r
	pm.emission_ring_inner_radius = ring_r * 0.15
	pm.emission_ring_height = 0.5
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = rise * 0.5
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0, rise * 0.15, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(core, 0.0))
	grad.set_color(1, Color(glow, 0.0))
	grad.add_point(0.15, Color(core, 1.0))
	grad.add_point(0.7, Color(glow, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	ps.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("shape", 3)
	m.set_shader_parameter("billboard", true)
	m.set_shader_parameter("color", Color.WHITE)
	m.set_shader_parameter("core", Color.WHITE)
	q.material = m
	ps.draw_pass_1 = q
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ps


## The spell went off: flash, then fade.
func release() -> void:
	if _state == 0:
		_state = 1
		_out = 0.0


## The cast was interrupted: collapse quickly without a flash.
func interrupt() -> void:
	if _state == 0:
		_state = 2
		_out = 0.0


func is_finished() -> bool:
	return _state != 0 and _out >= FADE_OUT


func progress() -> float:
	return clampf(elapsed / duration, 0.0, 1.0)


func _process(delta: float) -> void:
	elapsed += delta
	if _state != 0:
		_out += delta * (1.0 if _state == 1 else 1.8)
		if is_finished():
			queue_free()
			return
	_apply(delta)


func _apply(_delta: float) -> void:
	var fade := clampf(elapsed / FADE_IN, 0.0, 1.0)
	var flash := 0.0
	var scale_k := 1.0
	if _state != 0:
		var k := clampf(_out / FADE_OUT, 0.0, 1.0)
		fade *= 1.0 - k
		if _state == 1:
			flash = 1.0 - k
			scale_k = 1.0 + 0.25 * k
		else:
			scale_k = 1.0 - 0.4 * k
	# Ease-out pop when appearing.
	var pop := 0.75 + 0.25 * (1.0 - pow(1.0 - clampf(elapsed / FADE_IN, 0.0, 1.0), 3.0))
	_circle.scale = Vector3.ONE * pop * scale_k
	_circle_mat.set_shader_parameter("intensity", fade * 1.2)
	_circle_mat.set_shader_parameter("progress", progress() if _state == 0 else 1.0)
	_circle_mat.set_shader_parameter("flash", flash)
	_circle_mat.set_shader_parameter("spin", 1.0 + progress() * 1.5)
	_pillar_mat.set_shader_parameter("intensity", fade * (0.7 + 0.8 * progress()) + flash * 1.2)
	_pillar.scale = Vector3(scale_k, 0.6 + 0.4 * fade, scale_k)
	if _sparks:
		_sparks.emitting = _state == 0
