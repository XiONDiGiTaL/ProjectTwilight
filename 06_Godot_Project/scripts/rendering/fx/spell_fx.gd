class_name SpellFx
extends Node3D
## Short-lived spell release effects, element-coloured:
##   bolts  - streaks dropping onto the target, one per hit (Fire/Cold/Lightning Bolt)
##   orbs   - spirit orbs flying from caster to target (Soul Strike)
##   burst  - expanding ring and flash at the target (Napalm Beat, impacts)
## Purely visual; damage is resolved by the simulation.

const GLOW_SHADER := preload("res://scripts/rendering/fx/fx_glow.gdshader")
const BOLT_INTERVAL := 0.14
const BOLT_FALL := 0.18
const ORB_FLIGHT := 0.35

var _parts: Array = []   # {node, mat, t, life, kind, from, to, delay}
var _age := 0.0
var _life := 0.5


static func _mat(shape: int, color: Color, core: Color, billboard := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("billboard", billboard)
	return m


func _quad(size: Vector2, mat: ShaderMaterial, flat := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	if flat:
		q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Bolts dropping from above onto `at`.
static func bolts(parent: Node, at: Vector3, element: String, hits: int) -> SpellFx:
	var fx := SpellFx.new()
	parent.add_child(fx)
	fx.global_position = at
	var glow := ElementPalette.glow(element)
	var core := ElementPalette.core(element)
	for i in hits:
		var delay := i * BOLT_INTERVAL
		var jitter := Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		var streak := fx._quad(Vector2(3.2, 22.0), _mat(2, glow, core, false))
		fx._parts.append({"node": streak, "kind": "fall", "delay": delay, "life": BOLT_FALL, "t": 0.0,
			"from": jitter + Vector3(0, 60, 0), "to": jitter + Vector3(0, 8, 0), "zig": element == "wind"})
		var ring := fx._quad(Vector2(16, 16), _mat(1, glow, core), true)
		fx._parts.append({"node": ring, "kind": "ring", "delay": delay + BOLT_FALL, "life": 0.45, "t": 0.0, "from": jitter + Vector3(0, 0.6, 0)})
		var flash := fx._quad(Vector2(14, 14), _mat(0, glow, core, true))
		fx._parts.append({"node": flash, "kind": "flash", "delay": delay + BOLT_FALL, "life": 0.25, "t": 0.0, "from": jitter + Vector3(0, 5, 0)})
	fx._life = hits * BOLT_INTERVAL + BOLT_FALL + 0.5
	return fx


## Orbs flying from `from` to `to` (world positions).
static func orbs(parent: Node, from: Vector3, to: Vector3, element: String, hits: int) -> SpellFx:
	var fx := SpellFx.new()
	parent.add_child(fx)
	fx.global_position = to
	var glow := ElementPalette.glow(element)
	var core := ElementPalette.core(element)
	for i in hits:
		var delay := i * 0.12
		var orb := fx._quad(Vector2(6, 6), _mat(0, glow, core, true))
		var side := Vector3(randf_range(-6, 6), randf_range(4, 10), randf_range(-6, 6))
		fx._parts.append({"node": orb, "kind": "orb", "delay": delay, "life": ORB_FLIGHT, "t": 0.0,
			"from": from - to + Vector3(0, 8, 0), "to": Vector3(0, 6, 0), "arc": side})
		var flash := fx._quad(Vector2(12, 12), _mat(3, glow, core, true))
		fx._parts.append({"node": flash, "kind": "flash", "delay": delay + ORB_FLIGHT, "life": 0.25, "t": 0.0, "from": Vector3(0, 6, 0)})
	fx._life = hits * 0.12 + ORB_FLIGHT + 0.4
	return fx


## Expanding ring and flash at `at`, sized to `radius_cells` (0 = single target).
static func burst(parent: Node, at: Vector3, element: String, radius_cells: int) -> SpellFx:
	var fx := SpellFx.new()
	parent.add_child(fx)
	fx.global_position = at
	var glow := ElementPalette.glow(element)
	var core := ElementPalette.core(element)
	var size := 14.0 + radius_cells * 10.0
	var ring := fx._quad(Vector2(size, size), _mat(1, glow, core), true)
	fx._parts.append({"node": ring, "kind": "ring", "delay": 0.0, "life": 0.5, "t": 0.0, "from": Vector3(0, 0.6, 0)})
	var flash := fx._quad(Vector2(size * 0.8, size * 0.8), _mat(0, glow, core, true))
	fx._parts.append({"node": flash, "kind": "flash", "delay": 0.0, "life": 0.3, "t": 0.0, "from": Vector3(0, 5, 0)})
	var sparks := CastingCircle.make_sparks(core, glow, size * 0.3, 18, 0.7, 16.0)
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	fx.add_child(sparks)
	fx._life = 0.8
	return fx


func _process(delta: float) -> void:
	_age += delta
	for p in _parts:
		var node: MeshInstance3D = p.node
		var mat := node.material_override as ShaderMaterial
		if _age < p.delay:
			continue
		p.t += delta
		var k: float = clampf(p.t / p.life, 0.0, 1.0)
		node.visible = k < 1.0
		match p.kind:
			"fall":
				var pos: Vector3 = (p.from as Vector3).lerp(p.to, k * k)
				if p.zig:
					pos += Vector3(sin(p.t * 90.0) * 1.2, 0, cos(p.t * 70.0) * 1.2)
				node.position = pos
				_face_camera_upright(node)
				mat.set_shader_parameter("intensity", 2.2)
			"ring":
				node.position = p.from
				node.scale = Vector3.ONE * (0.3 + 1.1 * (1.0 - pow(1.0 - k, 3.0)))
				mat.set_shader_parameter("intensity", 1.6 * (1.0 - k))
			"flash":
				node.position = p.from
				node.scale = Vector3.ONE * (0.6 + 0.8 * k)
				mat.set_shader_parameter("intensity", 2.0 * (1.0 - k))
			"orb":
				var a: Vector3 = p.from
				var b: Vector3 = p.to
				node.position = a.lerp(b, k) + (p.arc as Vector3) * sin(k * PI)
				mat.set_shader_parameter("intensity", 1.8)
	if _age >= _life:
		queue_free()


## Rotates a vertical streak quad about Y so it faces the camera.
func _face_camera_upright(node: Node3D) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var to_cam := cam.global_position - node.global_position
	to_cam.y = 0.0
	if to_cam.length() > 0.01:
		node.global_basis = Basis(Vector3.UP, atan2(to_cam.x, to_cam.z))
