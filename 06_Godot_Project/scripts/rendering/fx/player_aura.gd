class_name PlayerAura
extends Node3D
## Cosmetic aura around a player: a soft ground halo with a slow dashed ring,
## rising motes and (for some styles) a faint light column. Chosen per
## character (saved), cycled in the field with U. Original design.

const CIRCLE_SHADER := preload("res://scripts/rendering/fx/casting_circle.gdshader")
const GLOW_SHADER := preload("res://scripts/rendering/fx/fx_glow.gdshader")
const RADIUS := 7.5

## id -> {name, element (palette) or "" for class colour, motes, pillar, rise}
const STYLES := {
	"class":   {"name": "Class colours", "element": "", "motes": 10, "pillar": false, "rise": 5.0},
	"azure":   {"name": "Azure",         "element": "neutral", "motes": 12, "pillar": false, "rise": 5.0},
	"ember":   {"name": "Ember",         "element": "fire", "motes": 16, "pillar": false, "rise": 8.0},
	"frost":   {"name": "Frost",         "element": "water", "motes": 12, "pillar": false, "rise": 3.5},
	"verdant": {"name": "Verdant",       "element": "earth", "motes": 12, "pillar": false, "rise": 4.0},
	"storm":   {"name": "Storm",         "element": "wind", "motes": 14, "pillar": false, "rise": 7.0},
	"radiant": {"name": "Radiant",       "element": "holy", "motes": 14, "pillar": true, "rise": 6.0},
	"void":    {"name": "Void",          "element": "shadow", "motes": 12, "pillar": true, "rise": 4.5},
	"none":    {"name": "None",          "element": "", "motes": 0, "pillar": false, "rise": 0.0},
}
const ORDER := ["class", "azure", "ember", "frost", "verdant", "storm", "radiant", "void", "none"]

var style := "class"
var job := "novice"
var dim := 1.0                 # 0..1, lowered while casting / sitting
var _ring_mat := ShaderMaterial.new()
var _pillar_mat: ShaderMaterial
var _built_for := ""
var _dim_now := 1.0


static func next_style(current: String) -> String:
	var i := ORDER.find(current)
	return ORDER[(i + 1) % ORDER.size()]


static func is_valid(id: String) -> bool:
	return STYLES.has(id)


static func colors_for(p_style: String, p_job: String) -> Array:
	var el := String(STYLES.get(p_style, STYLES.class).element)
	if el == "":
		var fam := ClassInsignia.family_color(p_job)
		return [fam.lightened(0.55), fam.lightened(0.15)]
	return [ElementPalette.core(el), ElementPalette.glow(el)]


func set_style(p_style: String, p_job: String) -> void:
	style = p_style if is_valid(p_style) else "class"
	job = p_job
	_rebuild()


func _ready() -> void:
	if _built_for == "":
		_rebuild()


func _rebuild() -> void:
	_built_for = style + "|" + job
	for c in get_children():
		c.queue_free()
	_pillar_mat = null
	var def: Dictionary = STYLES[style]
	if style == "none":
		return
	var cols := colors_for(style, job)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(RADIUS * 2, RADIUS * 2)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	ring.position.y = 0.3
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = CIRCLE_SHADER
	_ring_mat.set_shader_parameter("aura_mode", true)
	_ring_mat.set_shader_parameter("core_color", cols[0])
	_ring_mat.set_shader_parameter("glow_color", cols[1])
	_ring_mat.set_shader_parameter("spin", 0.6)
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if bool(def.pillar):
		var p := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = RADIUS * 0.45
		cyl.bottom_radius = RADIUS * 0.6
		cyl.height = 18.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 32
		p.mesh = cyl
		p.position.y = 9.0
		_pillar_mat = ShaderMaterial.new()
		_pillar_mat.shader = GLOW_SHADER
		_pillar_mat.set_shader_parameter("shape", 4)
		_pillar_mat.set_shader_parameter("color", cols[1])
		_pillar_mat.set_shader_parameter("core", cols[0])
		_pillar_mat.set_shader_parameter("streak_speed", 0.35)
		p.material_override = _pillar_mat
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
	if int(def.motes) > 0:
		add_child(CastingCircle.make_sparks(cols[0], cols[1], RADIUS * 0.7, int(def.motes), 2.2, float(def.rise)))
	_apply()


func _process(delta: float) -> void:
	if _built_for != style + "|" + job:
		_rebuild()
	_dim_now = move_toward(_dim_now, dim, delta * 3.0)
	_apply()


func _apply() -> void:
	if style == "none":
		return
	var breathe := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.0021)
	_ring_mat.set_shader_parameter("intensity", 0.55 * breathe * _dim_now)
	if _pillar_mat:
		_pillar_mat.set_shader_parameter("intensity", 0.22 * breathe * _dim_now)
