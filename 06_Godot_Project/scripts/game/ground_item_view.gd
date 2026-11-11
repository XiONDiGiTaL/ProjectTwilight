class_name GroundItemView
extends Node3D
## Visual for an item lying on the ground: the client's item sprite with a
## short drop hop, plus a faint glow ring so loot is easy to spot.

const HOP_TIME := 0.35
const HOP_HEIGHT := 4.0

var ground_id := 0
var item_id := 0
var item_name := ""
var sprite: CharacterSprite
var _age := 0.0
var _base := Vector3.ZERO
var _glow: MeshInstance3D


func setup(g: Dictionary, def: Dictionary, map: RoMap) -> void:
	ground_id = int(g.id)
	item_id = int(g.item)
	item_name = String(def.get("name", "Item"))
	var cell: Vector2i = g.cell
	var off: Vector2 = g.offset
	_base = map.cell_pos_to_world(Vector2(cell) + off)
	position = _base
	var parts := ItemIcons.ground_sprite(def)
	if not parts.is_empty():
		sprite = CharacterSprite.new()
		sprite.actions = CharacterSprite.MONSTER_ACTIONS
		add_child(sprite)
		sprite.setup(parts[0], parts[1])
	_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.5, 5.5)
	quad.orientation = PlaneMesh.FACE_Y
	_glow.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _glow_shader()
	_glow.material_override = mat
	_glow.position = Vector3(0, 0.25, 0)
	add_child(_glow)


func head_position() -> Vector3:
	return global_position + Vector3(0, (sprite.top_height() if sprite else 3.0) + 1.0, 0)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / HOP_TIME, 0.0, 1.0)
	position = _base + Vector3(0, sin(t * PI) * HOP_HEIGHT, 0)


static var _shader: Shader


static func _glow_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float ring = exp(-pow((r - 0.55) * 7.0, 2.0)) * 0.55 + exp(-r * r * 4.0) * 0.25;
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	ALBEDO = vec3(0.42, 0.86, 1.0) * ring * pulse;
	ALPHA = clamp(ring * pulse, 0.0, 1.0);
}
"""
	return _shader
