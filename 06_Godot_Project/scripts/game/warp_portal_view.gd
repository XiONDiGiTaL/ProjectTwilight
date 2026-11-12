class_name WarpPortalView
extends Node3D
## Warp portal: a swirling cyan ground sigil, a soft light column and a
## destination tag. Original effect (shaders), not a client asset.

var _tag: Label3D


func setup(warp: Dictionary, map: RoMap) -> void:
	var cell: Vector2i = warp.cell
	position = map.cell_to_world(cell.x, cell.y)
	var disc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	quad.orientation = PlaneMesh.FACE_Y
	disc.mesh = quad
	disc.position = Vector3(0, 0.3, 0)
	disc.material_override = _mat(SIGIL)
	add_child(disc)
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.5
	cyl.bottom_radius = 5.5
	cyl.height = 26.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	column.mesh = cyl
	column.position = Vector3(0, 13.0, 0)
	column.material_override = _mat(COLUMN)
	add_child(column)
	_tag = Label3D.new()
	_tag.text = "▸  " + String(warp.get("label", warp.to_map)).to_upper()
	_tag.font = UiTheme.font(600, 2)
	var settings := get_node_or_null("/root/Settings")
	var name_scale: float = settings.overhead_name_scale() if settings else 1.0
	_tag.font_size = maxi(10, roundi(40.0 * name_scale))
	_tag.pixel_size = 0.06
	_tag.modulate = UiTheme.ACCENT
	_tag.outline_size = maxi(6, roundi(10.0 * name_scale))
	_tag.outline_modulate = Color(0.0, 0.03, 0.06, 0.85)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position = Vector3(0, 22, 0)
	add_child(_tag)


static func _mat(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	return m


const SIGIL := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 6.0 - r * 14.0 + TIME * 3.0);
	float ring = exp(-pow((r - 0.82) * 14.0, 2.0)) + exp(-pow((r - 0.55) * 18.0, 2.0)) * 0.6;
	float body = smoothstep(1.0, 0.2, r) * swirl * 0.45;
	float glow = (ring + body) * smoothstep(1.0, 0.92, r);
	vec3 col = mix(vec3(0.3, 0.75, 1.0), vec3(0.85, 0.97, 1.0), ring);
	ALBEDO = col * glow;
	ALPHA = clamp(glow, 0.0, 1.0);
}
"""

const COLUMN := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void fragment() {
	float h = UV.y;   // 0 top .. 1 bottom
	float fade = pow(h, 1.6);
	float streaks = 0.6 + 0.4 * sin(UV.x * 40.0 + TIME * 2.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 5.0 + UV.x * 7.0);
	vec3 col = vec3(0.35, 0.8, 1.0) * fade * streaks * flicker * 0.55;
	ALBEDO = col;
	ALPHA = clamp(fade * 0.5, 0.0, 1.0);
}
"""
