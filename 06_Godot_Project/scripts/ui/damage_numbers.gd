class_name DamageNumbers
extends Control
## Screen-space floating combat text anchored to 3D positions.
##
## Styles (battle font, blue-glass palette, damage_text.gdshader):
##   NORMAL  soft sky-blue gradient, white outline (normal hits)
##   HIT     small softer numerals (the individual hits of a combo)
##   BIG     vibrant glowing blue with a sheen sweep (multi-hit totals, big hits)
##   CRIT    BIG style plus a "CRITICAL" tag and shake
##   TAKEN   coral-red gradient (damage received by the player)
##   MISS    pale "MISS";  HEAL green;  EXP small gold / green lines
## Each pops in with an overshoot, rises along an arc, then fades.
## spawn_combo() plays the per-hit numbers, then the built-up total.

enum Kind { NORMAL, CRIT, TAKEN, MISS, EXP_BASE, EXP_JOB, HEAL, BIG, HIT }

const TEXT_SHADER := preload("res://scripts/ui/damage_text.gdshader")
## Damage at or above this is shown in the BIG style even as a single hit.
const BIG_DAMAGE := 400
## kind -> [size, top, bottom, outline, glow, outline_px, glow_px, shine]
const STYLES := {
	Kind.NORMAL: [30, Color(0.95, 0.99, 1.0), Color(0.55, 0.8, 1.0), Color(1, 1, 1, 0.95), Color(0.3, 0.6, 1.0, 0.35), 4, 8, 0.0],
	Kind.HIT:    [20, Color(0.92, 0.97, 1.0), Color(0.66, 0.84, 1.0), Color(1, 1, 1, 0.85), Color(0.4, 0.65, 1.0, 0.25), 3, 6, 0.0],
	Kind.BIG:    [44, Color(0.78, 1.0, 1.0), Color(0.06, 0.45, 1.0), Color(1, 1, 1, 1.0), Color(0.15, 0.6, 1.0, 0.85), 5, 18, 1.0],
	Kind.CRIT:   [44, Color(1.0, 1.0, 1.0), Color(0.18, 0.55, 1.0), Color(1, 1, 1, 1.0), Color(0.25, 0.7, 1.0, 0.9), 5, 18, 1.0],
	Kind.TAKEN:  [28, Color(1.0, 0.88, 0.88), Color(1.0, 0.32, 0.36), Color(1, 1, 1, 0.9), Color(1.0, 0.25, 0.3, 0.35), 4, 8, 0.0],
	Kind.HEAL:   [26, Color(0.92, 1.0, 0.88), Color(0.42, 0.95, 0.45), Color(1, 1, 1, 0.9), Color(0.3, 0.95, 0.5, 0.35), 4, 8, 0.0],
	Kind.MISS:   [20, Color(0.88, 0.93, 1.0), Color(0.6, 0.7, 0.86), Color(1, 1, 1, 0.7), Color(0.4, 0.55, 0.8, 0.25), 3, 6, 0.0],
}

const LIFETIME := 1.15

var camera: Camera3D
var _items: Array = []  # {node: Control, anchor: Vector3, age, kind, drift: Vector2, scale_peak}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Like spawn(), with a fixed screen-space offset from the anchor (EXP lines).
func spawn_offset(world_pos: Vector3, screen_offset: Vector2, text: String, kind: Kind) -> void:
	spawn(world_pos, text, kind)
	_items[-1].offset = screen_offset


func spawn(world_pos: Vector3, text: String, kind: Kind, delay := 0.0) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -6)
	if kind == Kind.CRIT:
		box.add_child(_styled("CRITICAL", Kind.MISS, 14))
	var l: Label
	match kind:
		Kind.EXP_BASE:
			l = _label(text, UiTheme.font(600, 2), 14, UiTheme.EXP_BASE, 5)
		Kind.EXP_JOB:
			l = _label(text, UiTheme.font(600, 2), 14, UiTheme.EXP_JOB, 5)
		_:
			l = _styled(text, kind)
	box.add_child(l)
	add_child(box)
	box.visible = delay <= 0.0
	var drift := Vector2(randf_range(-28.0, 28.0), 0.0)
	if kind in [Kind.EXP_BASE, Kind.EXP_JOB, Kind.BIG]:
		drift = Vector2.ZERO
	_items.append({"node": box, "anchor": world_pos, "age": -delay, "kind": kind, "drift": drift, "offset": Vector2.ZERO})


## Multi-hit skills: the hits tick up as small numbers, then the total lands big.
func spawn_combo(world_pos: Vector3, total: int, hits: int, crit := false) -> void:
	hits = maxi(1, hits)
	if hits == 1:
		spawn(world_pos, str(total), Kind.CRIT if crit else (Kind.BIG if total >= BIG_DAMAGE else Kind.NORMAL))
		return
	var each := total / hits
	for i in hits:
		var v := each + (total - each * hits if i == hits - 1 else 0)
		spawn(world_pos, str(v), Kind.HIT, i * 0.09)
		_items[-1].offset = Vector2((i - (hits - 1) / 2.0) * 14.0, 22.0)
	spawn(world_pos, str(total), Kind.CRIT if crit else Kind.BIG, hits * 0.09 + 0.06)
	_items[-1].offset = Vector2(0, -18)


func _styled(text: String, kind: Kind, size_override := 0) -> Label:
	var st: Array = STYLES.get(kind, STYLES[Kind.NORMAL])
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = UiTheme.battle_font(1 if kind != Kind.MISS else 3, -0.12 if kind in [Kind.BIG, Kind.CRIT] else 0.0)
	ls.font_size = size_override if size_override > 0 else int(st[0])
	ls.font_color = Color.WHITE                 # marker: fill
	ls.outline_size = int(st[5])
	ls.outline_color = Color(0, 1, 0, 1)        # marker: outline
	ls.shadow_size = int(st[6])
	ls.shadow_color = Color(1, 0, 0, 1)         # marker: glow
	ls.shadow_offset = Vector2.ZERO
	l.label_settings = ls
	var m := ShaderMaterial.new()
	m.shader = TEXT_SHADER
	m.set_shader_parameter("top_color", st[1])
	m.set_shader_parameter("bottom_color", st[2])
	m.set_shader_parameter("outline_color", st[3])
	m.set_shader_parameter("glow_color", st[4])
	m.set_shader_parameter("shine", st[7])
	m.set_shader_parameter("height", float(ls.font_size) * 1.25)
	l.material = m
	return l


func _label(text: String, font: Font, size: int, color: Color, glow_px: int, glow := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	var g := glow if glow.a > 0.0 else color
	s.outline_size = glow_px
	s.outline_color = Color(g.r * 0.35, g.g * 0.35, g.b * 0.45, 0.75)
	s.shadow_size = glow_px + 6
	s.shadow_color = Color(g.r, g.g, g.b, 0.28)
	s.shadow_offset = Vector2.ZERO
	l.label_settings = s
	return l


func _process(delta: float) -> void:
	if camera == null:
		return
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it.age += delta
		var node0: Control = it.node
		if it.age < 0.0:
			continue
		node0.visible = true
		var life := LIFETIME * (1.5 if it.kind == Kind.EXP_BASE or it.kind == Kind.EXP_JOB else 1.0)
		if it.kind == Kind.HIT:
			life = LIFETIME * 0.65
		elif it.kind == Kind.BIG or it.kind == Kind.CRIT:
			life = LIFETIME * 1.3
		var t: float = it.age / life
		var node: Control = it.node
		if t >= 1.0 or camera.is_position_behind(it.anchor):
			node.queue_free()
			_items.remove_at(i)
			continue
		var base := camera.unproject_position(it.anchor)
		# Pop: overshoot to 1.35x (1.6x for crits) then settle to 1.0.
		var peak := 1.55 if it.kind == Kind.CRIT or it.kind == Kind.BIG else (1.1 if it.kind == Kind.HIT else 1.2)
		var pop := 1.0
		if t < 0.08:
			pop = lerpf(0.3, peak, t / 0.08)
		elif t < 0.22:
			pop = lerpf(peak, 1.0, ease((t - 0.08) / 0.14, 0.5))
		var rise := -70.0 * ease(t, 0.45)
		var arc: Vector2 = it.drift * ease(t, 0.6)
		var shake := Vector2.ZERO
		if (it.kind == Kind.CRIT or it.kind == Kind.BIG) and t < 0.25:
			shake = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		node.scale = Vector2(pop, pop)
		node.reset_size()
		node.pivot_offset = node.size / 2.0
		node.position = base + it.offset + Vector2(0, rise) + arc + shake - node.size / 2.0
		node.modulate.a = 1.0 if t < 0.65 else 1.0 - (t - 0.65) / 0.35
