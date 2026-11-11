class_name CombatHud
extends CanvasLayer
## Combat UI in the "Twilight Glass" style: world HP bars (shown once a player
## engages a monster, kept until it dies), target frame, player status panel,
## floating combat text and SYSTEM notifications. Presentation only; driven by
## FieldSimulation events and unit state.

const WORLD_BAR_SIZE := Vector2(92, 10)
const BAR_FADE_AFTER_DEATH := 0.9

var camera: Camera3D
var numbers: DamageNumbers
var status_panel: PlayerStatusPanel

var _root: Control
var _world_bars: Dictionary = {}   # unit id -> {node, bar, anchor: Callable, dying, fade_in}
var _target_panel: GlassPanel
var _target_bar: GlassBar
var _target_name: Label
var _target_level: Label
var _target_hp: Label
var _target_pct: Label
var _target_id := 0
var _target_clear_in := 0.0
var _effects: Array = []   # Callables returning false when finished
var _ring_shader: Shader


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.name = "Root"
	add_child(_root)
	numbers = DamageNumbers.new()
	_root.add_child(numbers)
	_build_target_frame()
	status_panel = PlayerStatusPanel.new()
	_root.add_child(status_panel)
	_ring_shader = Shader.new()
	_ring_shader.code = RING_SHADER
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 4)
	_root.add_child(_feed)
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = -380
	_feed.offset_right = -16
	_feed.offset_top = -260
	_feed.offset_bottom = -16
	_hover_tag = GlassPanel.new()
	_hover_tag.chamfer = 6.0
	_hover_tag.sweep = false
	_hover_tag.padding = Vector4(8, 3, 8, 4)
	_hover_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label = UiTheme.label("", 11, UiTheme.TEXT, 600, 2)
	_hover_tag.add_child(_hover_label)
	_root.add_child(_hover_tag)
	_hover_tag.visible = false
	inventory = InventoryWindow.new()
	_root.add_child(inventory)
	inventory.position = Vector2(860, 120)
	status_window = StatusWindow.new()
	_root.add_child(status_window)
	status_window.position = Vector2(400, 160)
	equipment_window = EquipmentWindow.new()
	_root.add_child(equipment_window)
	equipment_window.position = Vector2(500, 120)
	shop = ShopWindow.new()
	_root.add_child(shop)
	shop.position = Vector2(380, 140)
	skill_window = SkillWindow.new()
	_root.add_child(skill_window)
	skill_window.position = Vector2(120, 200)
	hotkeys = HotkeyBar.new()
	_root.add_child(hotkeys)


# --- System feed and hover tag ---------------------------------------------------

var inventory: InventoryWindow
var status_window: StatusWindow
var equipment_window: EquipmentWindow
var shop: ShopWindow
var skill_window: SkillWindow
var hotkeys: HotkeyBar
var _feed: VBoxContainer
var _hover_tag: GlassPanel
var _hover_label: Label

const FEED_SECONDS := 4.5
const FEED_MAX := 6


## Adds a message chip to the bottom-right system feed.
func notify(text: String, color := UiTheme.TEXT) -> void:
	var chip := GlassPanel.new()
	chip.chamfer = 6.0
	chip.sweep = false
	chip.padding = Vector4(12, 4, 12, 5)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.add_child(UiTheme.label(text, 12, color, 600, 1))
	_feed.add_child(chip)
	while _feed.get_child_count() > FEED_MAX:
		_feed.get_child(0).queue_free()
		_feed.remove_child(_feed.get_child(0))
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		if not is_instance_valid(chip):
			return false
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		chip.modulate.a = clampf(age / 0.2, 0.0, 1.0) * clampf((FEED_SECONDS - age) / 0.6, 0.0, 1.0)
		if age > FEED_SECONDS:
			chip.queue_free()
			return false
		return true)


## Shows a small name tag at a screen position (ground item hover); "" hides it.
func hover_tag(text: String, screen_pos: Vector2) -> void:
	_hover_tag.visible = text != ""
	if text == "":
		return
	_hover_label.text = text.to_upper()
	_hover_tag.reset_size()
	_hover_tag.position = screen_pos - Vector2(_hover_tag.size.x / 2.0, _hover_tag.size.y + 6.0)


# --- World HP bars ------------------------------------------------------------

## Shows (or keeps) the HP bar for a unit. `anchor` returns the world position
## above the unit's head. The bar stays until the unit dies.
func engage(unit_id: int, hp: int, max_hp: int, anchor: Callable, name := "") -> void:
	if _world_bars.has(unit_id):
		return
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	if name != "":
		var l := UiTheme.label(name.to_upper(), 10, UiTheme.TEXT, 600, 2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var bar := GlassBar.new()
	bar.ticks = 5.0
	bar.glow_px = 2.0
	bar.custom_minimum_size = WORLD_BAR_SIZE
	box.add_child(bar)
	_root.add_child(box)
	_root.move_child(box, 0)  # behind numbers and panels
	bar.snap(hp, max_hp)
	box.modulate.a = 0.0
	_world_bars[unit_id] = {"node": box, "bar": bar, "anchor": anchor, "dying": -1.0, "fade_in": 0.0}


func update_hp(unit_id: int, hp: int, max_hp: int) -> void:
	if _world_bars.has(unit_id):
		(_world_bars[unit_id].bar as GlassBar).set_value(hp, max_hp)
	if unit_id == _target_id:
		_target_bar.set_value(hp, max_hp)
		_set_target_text(hp, max_hp)


## Unit died: drain the bar to empty, then fade it out.
func unit_died(unit_id: int) -> void:
	if _world_bars.has(unit_id):
		var e: Dictionary = _world_bars[unit_id]
		(e.bar as GlassBar).set_value(0, (e.bar as GlassBar).max_value)
		e.dying = BAR_FADE_AFTER_DEATH
	if unit_id == _target_id:
		_target_clear_in = 1.4


func has_world_bar(unit_id: int) -> bool:
	return _world_bars.has(unit_id)


func target_id() -> int:
	return _target_id


# --- Target frame ---------------------------------------------------------------

func set_target(unit_id: int, name: String, level: int, hp: int, max_hp: int) -> void:
	if unit_id != _target_id:
		_target_bar.snap(hp, max_hp)
	_target_id = unit_id
	_target_clear_in = 0.0
	_target_name.text = name.to_upper()
	_target_level.text = "LV %d" % level
	_set_target_text(hp, max_hp)
	_target_panel.visible = true


func _set_target_text(hp: int, max_hp: int) -> void:
	_target_hp.text = "%d / %d" % [hp, max_hp]
	_target_pct.text = "%d%%" % roundi(100.0 * hp / maxi(max_hp, 1))


func clear_target() -> void:
	_target_id = 0
	_target_panel.visible = false


func _build_target_frame() -> void:
	_target_panel = GlassPanel.new()
	_target_panel.chamfer = 10.0
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_target_panel)
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_panel.offset_left = -200
	_target_panel.offset_right = 200
	_target_panel.offset_top = 14
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_panel.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_target_name = UiTheme.label("", 15, UiTheme.TEXT, 600, 3)
	_target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_target_name)
	_target_level = UiTheme.label("", 11, UiTheme.ACCENT, 600, 2)
	_target_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_target_level)
	_target_bar = GlassBar.new()
	_target_bar.custom_minimum_size = Vector2(372, 14)
	col.add_child(_target_bar)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	_target_hp = UiTheme.label("", 11, UiTheme.TEXT_DIM, 400, 1)
	_target_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_target_hp)
	_target_pct = UiTheme.label("", 11, UiTheme.TEXT, 600, 1)
	bottom.add_child(_target_pct)
	_target_panel.visible = false


# --- Player panel -------------------------------------------------------------------

func update_player(u: SimUnit, next_base: int, next_job: int, first := false) -> void:
	status_panel.update_unit(u, next_base, next_job, first)


# --- SYSTEM notifications ----------------------------------------------------------

## Solo-Leveling-style system window plus a ring pulse at `world_pos`.
func level_up(world_pos: Vector3, text: String, detail := "") -> void:
	_ring_pulse(world_pos)
	var panel := GlassPanel.new()
	panel.chamfer = 14.0
	panel.padding = Vector4(28, 12, 28, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var tag := UiTheme.label("◆  SYSTEM", 11, UiTheme.ACCENT, 600, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var title := UiTheme.label(text, 30, UiTheme.TEXT, 300, 8, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if detail != "":
		var d := UiTheme.label(detail, 12, UiTheme.TEXT_DIM, 400, 1)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(d)
	panel.set_glow(1.0)
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > 3.2:
			panel.queue_free()
			return false
		panel.reset_size()
		var vp := _root.get_viewport_rect().size
		var slide := 14.0 * (1.0 - ease(clampf(age / 0.3, 0.0, 1.0), 0.4))
		panel.position = Vector2((vp.x - panel.size.x) / 2.0, vp.y * 0.2 - slide)
		panel.modulate.a = clampf(age / 0.25, 0.0, 1.0) * (1.0 if age < 2.6 else 1.0 - (age - 2.6) / 0.6)
		panel.set_glow(maxf(0.0, 1.0 - age * 1.5))
		return true)


func _ring_pulse(world_pos: Vector3) -> void:
	var ring := ColorRect.new()
	ring.size = Vector2(260, 260)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	ring.material = mat
	_root.add_child(ring)
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > 1.0 or camera == null:
			ring.queue_free()
			return false
		ring.position = camera.unproject_position(world_pos) - ring.size / 2.0
		mat.set_shader_parameter("age", age)
		return true)


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
		var node: Control = e.node
		if e.dying >= 0.0:
			e.dying -= delta
			node.modulate.a = clampf(e.dying / 0.4, 0.0, 1.0)
			if e.dying <= 0.0:
				node.queue_free()
				_world_bars.erase(id)
				continue
		else:
			e.fade_in = minf(1.0, e.fade_in + delta * 6.0)
			node.modulate.a = e.fade_in
		var anchor: Vector3 = (e.anchor as Callable).call()
		if camera.is_position_behind(anchor):
			node.visible = false
			continue
		node.visible = true
		node.reset_size()
		node.position = camera.unproject_position(anchor) - Vector2(node.size.x / 2.0, node.size.y)


const RING_SHADER := """
shader_type canvas_item;
uniform float age = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y *= 2.2;                       // flattened: reads as a ring on the ground
	float r = length(p);
	float t = clamp(age / 0.9, 0.0, 1.0);
	float radius = mix(0.15, 0.95, 1.0 - pow(1.0 - t, 3.0));
	float ring = exp(-pow((r - radius) * 26.0, 2.0));
	float inner = exp(-pow((r - radius * 0.7) * 40.0, 2.0)) * 0.5;
	float fade = 1.0 - t;
	vec3 col = mix(vec3(0.42, 0.86, 1.0), vec3(0.9, 0.97, 1.0), ring);
	COLOR = vec4(col, (ring + inner) * fade);
}
"""
