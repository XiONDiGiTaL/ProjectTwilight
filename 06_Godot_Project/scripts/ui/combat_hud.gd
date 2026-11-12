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
var _cast_box: VBoxContainer
var _cast_bar: GlassBar
var _cast_label: Label
var _cast_anchor: Callable
var _cast_total := 0.0     # ms
var _cast_elapsed := 0.0   # ms
var _cast_out := -1.0      # fade-out timer (s), -1 = not fading


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
	# Place defaults before entering the tree: GlassWindow restores a saved
	# position in _ready(), and assigning defaults afterwards would erase it.
	inventory = InventoryWindow.new()
	_add_window(inventory, Vector2(860, 120))
	status_window = StatusWindow.new()
	_add_window(status_window, Vector2(400, 160))
	equipment_window = EquipmentWindow.new()
	_add_window(equipment_window, Vector2(500, 120))
	shop = ShopWindow.new()
	_add_window(shop, Vector2(380, 140))
	storage = StorageWindow.new()
	_add_window(storage, Vector2(420, 130))
	guild_window = GuildWindow.new()
	_add_window(guild_window, Vector2(620, 130))
	skill_window = SkillWindow.new()
	_add_window(skill_window, Vector2(120, 200))
	hotkeys = HotkeyBar.new()
	_root.add_child(hotkeys)
	dialog = NpcDialog.new()
	_root.add_child(dialog)
	_build_minimap()
	_build_chat()


## Adds a draggable window at its default position. Saved positions win.
func _add_window(window: GlassWindow, at: Vector2) -> void:
	window.position = at
	_root.add_child(window)


# --- System feed and hover tag ---------------------------------------------------

var inventory: InventoryWindow
var status_window: StatusWindow
var equipment_window: EquipmentWindow
var shop: ShopWindow
var storage: StorageWindow
var guild_window: GuildWindow
var skill_window: SkillWindow
var hotkeys: HotkeyBar
var dialog: NpcDialog
var minimap: Minimap
var chat: ChatConsole
var _minimap_panel: GlassPanel
var _minimap_title: Label
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
	var ref: WeakRef = weakref(chip)   # trimmed chips are freed while their effect is queued
	_effects.append(func() -> bool:
		var c: Control = ref.get_ref()
		if c == null:
			return false
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		c.modulate.a = clampf(age / 0.2, 0.0, 1.0) * clampf((FEED_SECONDS - age) / 0.6, 0.0, 1.0)
		if age > FEED_SECONDS:
			c.queue_free()
			return false
		return true)


## SAO-style map title card shown when entering a map.
func map_banner(title: String, subtitle: String) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var line_top := ColorRect.new()
	line_top.custom_minimum_size = Vector2(380, 1)
	line_top.color = Color(UiTheme.ACCENT, 0.7)
	box.add_child(line_top)
	var t := UiTheme.label(title.to_upper(), 34, UiTheme.TEXT, 300, 10, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if subtitle != "":
		var st := UiTheme.label(subtitle.to_upper(), 11, UiTheme.ACCENT, 600, 4)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(st)
	var line_bot := ColorRect.new()
	line_bot.custom_minimum_size = Vector2(380, 1)
	line_bot.color = Color(UiTheme.ACCENT, 0.7)
	box.add_child(line_bot)
	_root.add_child(box)
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > 4.0:
			box.queue_free()
			return false
		box.reset_size()
		var vp := _root.get_viewport_rect().size
		box.position = Vector2((vp.x - box.size.x) / 2.0, vp.y * 0.3)
		var spread := ease(clampf(age / 0.6, 0.0, 1.0), 0.3)
		line_top.custom_minimum_size.x = 380.0 * spread
		line_bot.custom_minimum_size.x = 380.0 * spread
		box.modulate.a = clampf(age / 0.4, 0.0, 1.0) * clampf((4.0 - age) / 0.8, 0.0, 1.0)
		return true)


## Short burst at a world position when a skill lands.
func skill_flash(world_pos: Vector3, skill: String) -> void:
	var big := skill == "SM_MAGNUM"
	var ring := ColorRect.new()
	ring.size = Vector2(420, 420) if big else Vector2(160, 160)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _burst_shader()
	mat.set_shader_parameter("tint", Color(1.0, 0.55, 0.2) if big else Color(1.0, 0.9, 0.6))
	ring.material = mat
	_root.add_child(ring)
	_root.move_child(ring, 0)
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > 0.6 or camera == null:
			ring.queue_free()
			return false
		ring.position = camera.unproject_position(world_pos) - ring.size / 2.0
		mat.set_shader_parameter("age", age)
		return true)


static var _burst: Shader


static func _burst_shader() -> Shader:
	if _burst == null:
		_burst = Shader.new()
		_burst.code = """
shader_type canvas_item;
uniform float age = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y *= 1.6;
	float r = length(p);
	float t = clamp(age / 0.55, 0.0, 1.0);
	float radius = mix(0.1, 0.95, 1.0 - pow(1.0 - t, 3.0));
	float ring = exp(-pow((r - radius) * 12.0, 2.0));
	float core = exp(-r * r * 9.0) * (1.0 - t);
	float a = (ring * 0.9 + core) * (1.0 - t);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), core), a);
}
"""
	return _burst


## Full-screen glass transition shown while changing maps.
func transition(text: String) -> void:
	var cover := ColorRect.new()
	cover.color = Color(0.02, 0.03, 0.06, 0.0)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(cover)
	var l := UiTheme.label(text.to_upper() + "  …", 18, UiTheme.TEXT, 300, 6, true)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cover.add_child(l)
	var t0 := Time.get_ticks_msec()
	_effects.append(func() -> bool:
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		cover.color.a = clampf(age / 0.35, 0.0, 1.0)
		return is_instance_valid(cover))


# --- Minimap -----------------------------------------------------------------

## Corner overview of the current map: walkability, portals, monsters and the
## CPU adventurers. Bound once the field has loaded its map.
func _build_minimap() -> void:
	_minimap_panel = GlassPanel.new()
	_minimap_panel.chamfer = 10.0
	_minimap_panel.sweep = false
	_minimap_panel.padding = Vector4(6, 5, 6, 6)
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_minimap_panel)
	_minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap_panel.offset_left = -196
	_minimap_panel.offset_right = -16
	_minimap_panel.offset_top = 16
	_minimap_panel.offset_bottom = 216
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(col)
	_minimap_title = UiTheme.label("", 9, UiTheme.ACCENT, 600, 2)
	_minimap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_minimap_title)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(168, 168)
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(minimap)


func bind_minimap(gat: GatFile, sim: FieldSimulation, player_id: int, title: String) -> void:
	_minimap_title.text = title.to_upper()
	minimap.setup(gat, sim, player_id)


func toggle_minimap() -> void:
	_minimap_panel.visible = not _minimap_panel.visible


## Bottom-left command line (Enter to open).
func _build_chat() -> void:
	chat = ChatConsole.new()
	_root.add_child(chat)
	chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat.offset_left = 16
	chat.offset_right = 388   # clear of the centred hotkey bar
	chat.offset_bottom = -16
	chat.offset_top = -54


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
## Small, unobtrusive notice for level ups and job changes: a single glass
## chip that pops up above the character, drifts up a little and fades in
## under two seconds. Never blocks the view or input.
const NOTICE_SECONDS := 1.8


func level_up(world_pos: Vector3, text: String, detail := "") -> void:
	_ring_pulse(world_pos)
	var chip := GlassPanel.new()
	chip.chamfer = 6.0
	chip.sweep = false
	chip.padding = Vector4(10, 3, 10, 4)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(UiTheme.label("◆ " + text.to_upper(), 12, UiTheme.ACCENT.lightened(0.3), 700, 2))
	if detail != "":
		row.add_child(UiTheme.label(detail, 11, UiTheme.TEXT, 400, 0))
	chip.set_glow(0.8)
	var t0 := Time.get_ticks_msec()
	var ref: WeakRef = weakref(chip)
	_effects.append(func() -> bool:
		var c: GlassPanel = ref.get_ref()
		if c == null:
			return false
		var age := (Time.get_ticks_msec() - t0) / 1000.0
		if age > NOTICE_SECONDS or camera == null:
			c.queue_free()
			return false
		c.reset_size()
		var anchor := world_pos + Vector3(0, 14, 0)
		var at := camera.unproject_position(anchor) if not camera.is_position_behind(anchor) else _root.get_viewport_rect().size * Vector2(0.5, 0.3)
		var rise := 18.0 * ease(clampf(age / NOTICE_SECONDS, 0.0, 1.0), 0.6)
		var pop := lerpf(0.85, 1.0, clampf(age / 0.12, 0.0, 1.0))
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(pop, pop)
		c.position = at - Vector2(c.size.x / 2.0, c.size.y + rise)
		c.modulate.a = clampf(age / 0.12, 0.0, 1.0) * (1.0 if age < 1.2 else 1.0 - (age - 1.2) / (NOTICE_SECONDS - 1.2))
		c.set_glow(maxf(0.0, 0.8 - age * 1.6))
		return true)


func _ring_pulse(world_pos: Vector3) -> void:
	var ring := ColorRect.new()
	ring.size = Vector2(170, 170)
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


## Cast bar above the caster's head: element-coloured, fills over the cast time.
func cast_begin(anchor: Callable, duration_ms: float, text: String, color: Color) -> void:
	if _cast_box == null:
		_cast_box = VBoxContainer.new()
		_cast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cast_box.add_theme_constant_override("separation", 1)
		_cast_label = UiTheme.label("", 11, UiTheme.TEXT, 600, 2)
		_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cast_box.add_child(_cast_label)
		_cast_bar = GlassBar.new()
		_cast_bar.style = GlassBar.Style.SP
		_cast_bar.ticks = 0.0
		_cast_bar.glow_px = 3.0
		_cast_bar.custom_minimum_size = Vector2(120, 8)
		_cast_box.add_child(_cast_bar)
		_root.add_child(_cast_box)
	_cast_anchor = anchor
	_cast_total = maxf(duration_ms, 1.0)
	_cast_elapsed = 0.0
	_cast_out = -1.0
	_cast_label.text = text.to_upper()
	_cast_label.add_theme_color_override("font_color", color.lightened(0.45))
	_cast_bar.set_fill_color(color.lightened(0.15))
	_cast_bar.snap(0.0, 1.0)
	_cast_box.modulate = Color.WHITE
	_cast_box.visible = true


func cast_end(ok: bool) -> void:
	if _cast_box == null or not _cast_box.visible:
		return
	if ok:
		_cast_bar.snap(1.0, 1.0)
	else:
		_cast_label.text = "INTERRUPTED"
		_cast_label.add_theme_color_override("font_color", UiTheme.HP_LOW)
	_cast_out = 0.35


func is_casting_shown() -> bool:
	return _cast_box != null and _cast_box.visible and _cast_out < 0.0


func _update_cast_bar(delta: float) -> void:
	if _cast_box == null or not _cast_box.visible or camera == null:
		return
	if _cast_out >= 0.0:
		_cast_out -= delta
		_cast_box.modulate.a = clampf(_cast_out / 0.35, 0.0, 1.0)
		if _cast_out <= 0.0:
			_cast_box.visible = false
			return
	else:
		_cast_elapsed += delta * 1000.0
		_cast_bar.snap(minf(_cast_elapsed / _cast_total, 1.0), 1.0)
	var anchor: Vector3 = _cast_anchor.call() + Vector3(0, 4.0, 0)
	if camera.is_position_behind(anchor):
		return
	_cast_box.reset_size()
	_cast_box.position = camera.unproject_position(anchor) - Vector2(_cast_box.size.x / 2.0, _cast_box.size.y)


func _process(delta: float) -> void:
	_update_cast_bar(delta)
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
