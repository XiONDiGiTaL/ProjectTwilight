class_name MenuBackdrop
extends SubViewportContainer
## Animated menu background: a classic map from the user's client, slowly
## orbited by the camera, rendered in its own viewport behind the glass UI.
## Falls back to a dark gradient when no client is mounted.

@export var map_name := "prontera"
@export var orbit_speed_deg := 3.0

var _vp: SubViewport
var _cam: RoCamera
var _map: RoMap


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.04, 0.05, 0.09)
	_vp.add_child(env)
	_cam = RoCamera.new()
	_cam.distance = 520.0
	_cam.pitch_deg = 38.0
	_vp.add_child(_cam)
	var res := get_node_or_null("/root/RoResources")
	if res and (res.is_mounted or res.mount()):
		_map = RoMap.new()
		_vp.add_child(_map)
		if _map.load_map(map_name):
			_cam.focus = _map.center() + Vector3(-60, 0, -330)  # a quieter street, off the fountain
	# Darkening vignette so the glass UI stays readable.
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - 0.5;
	float v = smoothstep(0.25, 0.85, length(p * vec2(1.0, 1.3)));
	COLOR = vec4(0.02, 0.03, 0.06, 0.35 + 0.5 * v);
}
"""
	shade.material = mat
	add_sibling.call_deferred(shade)


func _process(delta: float) -> void:
	if _cam:
		_cam.yaw_deg = fposmod(_cam.yaw_deg + orbit_speed_deg * delta, 360.0)
