class_name CombatHud
extends CanvasLayer
## Enhanced combat UI: world HP bars, target frame, player panel, floating
## combat text and the level-up flourish. Presentation only; it is driven by
## FieldSimulation events and unit state.

const WORLD_BAR_SIZE := Vector2(104, 14)
const BAR_FADE_AFTER_DEATH := 0.9

var camera: Camera3D
var numbers: DamageNumbers

var _world_bars: Dictionary = {}   # unit id -> {bar: OrnateBar, anchor: Callable, dying: float}
var _target_panel: Control
var _target_bar: OrnateBar
var _target_name: Label
var _target_hp: Label
var _target_id := 0
var _target_clear_in := 0.0

var status_panel: PlayerStatusPanel

var _ui_font: SystemFont
var _burst_shader: Shader


func _ready() -> void:
	layer = 5
	_ui_font = SystemFont.new()
	_ui_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Times New Roman"])
	_ui_font.font_weight = 700
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = "Root"
	add_child(root)
	numbers = DamageNumbers.new()
	root.add_child(numbers)
	_build_target_frame(root)
	status_panel = PlayerStatusPanel.new()
	root.add_child(status_panel)
	_burst_shader = Shader.new()
	_burst_shader.code = BURST_SHADER


# --- World HP bars ------------------------------------------------------------

## Shows (or keeps) the HP bar for a unit. `anchor` returns the world position
## above the unit's head. The bar stays until the unit dies.
func engage(unit_id: int, hp: int, max_hp: int, anchor: Callable) -> void:
	if _world_bars.has(unit_id):
		return
	var bar := OrnateBar.new()
	bar.size = WORLD_BAR_SIZE
	bar.sleek = true
	bar.show_diamond = false
	$Root.add_child(bar)
	$Root.move_child(bar, 0)  # behind numbers and panels
	bar.snap(hp, max_hp)
	bar.modulate.a = 0.0
	_world_bars[unit_id] = {"bar": bar, "anchor": anchor, "dying": -1.0, "fade_in": 0.0}


func update_hp(unit_id: int, hp: int, max_hp: int) -> void:
	if _world_bars.has(unit_id):
		(_world_bars[unit_id].bar as OrnateBar).set_value(hp, max_hp)
	if unit_id == _target_id:
		_target_bar.set_value(hp, max_hp)
		_target_hp.text = "%d / %d" % [hp, max_hp]


## Unit died: drain the bar to empty, then fade it out.
func unit_died(unit_id: int) -> void:
	if _world_bars.has(unit_id):
		var e: Dictionary = _world_bars[unit_id]
		(e.bar as OrnateBar).set_value(0, (e.bar as OrnateBar).max_value)
		e.dying = BAR_FADE_AFTER_DEATH
	if unit_id == _target_id:
		_target_clear_in = 1.4


func has_world_bar(unit_id: int) -> bool:
	return _world_bars.has(unit_id)


# --- Target frame ---------------------------------------------------------------

func set_target(unit_id: int, name: String, level: int, hp: int, max_hp: int) -> void:
	if unit_id != _target_id:
		_target_bar.snap(hp, max_hp)
	_target_id = unit_id
	_target_clear_in = 0.0
	_target_name.text = "%s   Lv.%d" % [name.to_upper(), level]
	_target_hp.text = "%d / %d" % [hp, max_hp]
	_target_panel.visible = true


func clear_target() -> void:
	_target_id = 0
	_target_panel.visible = false


func _build_target_frame(root: Control) -> void:
	_target_panel = VBoxContainer.new()
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_panel.add_theme_constant_override("separation", 1)
	root.add_child(_target_panel)
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_panel.offset_left = -210
	_target_panel.offset_right = 210
	_target_panel.offset_top = 10
	_target_name = _label("", 17, Color(1.0, 0.92, 0.75))
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_panel.add_child(_target_name)
	_target_bar = OrnateBar.new()
	_target_bar.sleek = true
	_target_bar.custom_minimum_size = Vector2(420, 26)
	_target_panel.add_child(_target_bar)
	_target_hp = _label("", 15, Color(1, 1, 1))
	_target_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_panel.add_child(_target_hp)
	_target_panel.visible = false


# --- Player panel -------------------------------------------------------------------

func update_player(u: SimUnit, next_base: int, next_job: int, first := false) -> void:
	status_panel.update_unit(u, next_base, next_job, first)


# --- Level up ---------------------------------------------------------------------

func level_up(world_pos: Vector3, text: String) -> void:
	var burst := ColorRect.new()
	burst.size = Vector2(320, 320)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _burst_shader
	burst.material = mat
	$Root.add_child(burst)
	var title := _label(text, 34, Color(1.0, 0.86, 0.35))
	title.label_settings.outline_size = 10
	title.label_settings.outline_color = Color(0.35, 0.12, 0.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Root.add_child(title)
	var t0 := Time.get_ticks_msec()
	var updater := func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > 2.2 or camera == null:
			burst.queue_free()
			title.queue_free()
			return false
		var sp := camera.unproject_position(world_pos)
		burst.position = sp - burst.size / 2.0
		mat.set_shader_parameter("age", age)
		title.reset_size()
		var s := 1.0 + 0.6 * maxf(0.0, 0.25 - age) * 4.0
		title.pivot_offset = title.size / 2.0
		title.scale = Vector2(s, s)
		title.position = sp - title.size / 2.0 - Vector2(0, 90 + age * 18.0)
		title.modulate.a = 1.0 if age < 1.6 else 1.0 - (age - 1.6) / 0.6
		return true
	_effects.append(updater)


var _effects: Array = []


func _process(delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		if not (_effects[i] as Callable).call():
			_effects.remove_at(i)
	if _target_clear_in > 0.0:
		_target_clear_in -= delta
		if _target_clear_in <= 0.0:
			clear_target()
	if camera == null:
		return
	for id in _world_bars.keys():
		var e: Dictionary = _world_bars[id]
		var bar: OrnateBar = e.bar
		if e.dying >= 0.0:
			e.dying -= delta
			bar.modulate.a = clampf(e.dying / 0.4, 0.0, 1.0)
			if e.dying <= 0.0:
				bar.queue_free()
				_world_bars.erase(id)
				continue
		else:
			e.fade_in = minf(1.0, e.fade_in + delta * 6.0)
			bar.modulate.a = e.fade_in
		var anchor: Vector3 = (e.anchor as Callable).call()
		if camera.is_position_behind(anchor):
			bar.visible = false
			continue
		bar.visible = true
		bar.position = camera.unproject_position(anchor) - Vector2(bar.size.x / 2.0, bar.size.y)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = _ui_font
	s.font_size = size
	s.font_color = color
	s.outline_size = 5
	s.outline_color = Color(0.05, 0.03, 0.02)
	s.shadow_size = 3
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_offset = Vector2(1, 2)
	l.label_settings = s
	return l


const BURST_SHADER := """
shader_type canvas_item;
uniform float age = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float grow = clamp(age / 0.35, 0.0, 1.0);
	float fade = 1.0 - clamp((age - 0.6) / 1.4, 0.0, 1.0);
	float rays = pow(0.5 + 0.5 * sin(a * 12.0 + age * 2.5), 6.0) * smoothstep(1.0 * grow, 0.1, r);
	float ring = smoothstep(0.08, 0.0, abs(r - grow * 0.85)) * (1.0 - grow * 0.6);
	float glow = smoothstep(0.7, 0.0, r) * 0.45;
	vec3 col = mix(vec3(1.0, 0.75, 0.25), vec3(1.0, 0.97, 0.8), rays);
	COLOR = vec4(col, (rays * 0.7 + ring + glow) * fade);
}
"""
