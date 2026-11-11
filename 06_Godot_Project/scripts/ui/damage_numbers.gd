class_name DamageNumbers
extends Control
## Screen-space floating combat text anchored to 3D positions.
##
## Styles:
##   NORMAL  white numerals with a dark outline (damage dealt by the player)
##   CRIT    large gold numerals, "CRITICAL" tag, punch-in and shake
##   TAKEN   red numerals (damage received by the player)
##   MISS    pale blue "MISS"
##   EXP     small gold "+N Base EXP" / green job EXP lines
## Each pops in with an overshoot, rises along an arc, then fades.

enum Kind { NORMAL, CRIT, TAKEN, MISS, EXP_BASE, EXP_JOB, HEAL }

const LIFETIME := 1.15

var camera: Camera3D
var _items: Array = []  # {node: Control, anchor: Vector3, age, kind, drift: Vector2, scale_peak}
var _number_font: SystemFont
var _text_font: SystemFont


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_number_font = SystemFont.new()
	_number_font.font_names = PackedStringArray(["Impact", "Arial Black", "Segoe UI Black"])
	_number_font.font_weight = 900
	_text_font = SystemFont.new()
	_text_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Times New Roman"])
	_text_font.font_weight = 700


## Like spawn(), with a fixed screen-space offset from the anchor (EXP lines).
func spawn_offset(world_pos: Vector3, screen_offset: Vector2, text: String, kind: Kind) -> void:
	spawn(world_pos, text, kind)
	_items[-1].offset = screen_offset


func spawn(world_pos: Vector3, text: String, kind: Kind) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -6)
	if kind == Kind.CRIT:
		box.add_child(_label("CRITICAL", _text_font, 15, Color(1.0, 0.95, 0.7), Color(0.45, 0.1, 0.0), 5))
	var l: Label
	match kind:
		Kind.CRIT:
			l = _label(text, _number_font, 46, Color(1.0, 0.78, 0.15), Color(0.35, 0.05, 0.0), 10)
		Kind.TAKEN:
			l = _label(text, _number_font, 30, Color(1.0, 0.25, 0.2), Color(0.18, 0.0, 0.0), 8)
		Kind.MISS:
			l = _label(text, _text_font, 24, Color(0.7, 0.85, 1.0), Color(0.05, 0.1, 0.25), 7)
		Kind.EXP_BASE:
			l = _label(text, _text_font, 17, Color(1.0, 0.86, 0.4), Color(0.2, 0.12, 0.0), 6)
		Kind.EXP_JOB:
			l = _label(text, _text_font, 17, Color(0.6, 1.0, 0.6), Color(0.0, 0.15, 0.05), 6)
		Kind.HEAL:
			l = _label(text, _number_font, 28, Color(0.5, 1.0, 0.5), Color(0.0, 0.2, 0.05), 8)
		_:
			l = _label(text, _number_font, 32, Color(1.0, 1.0, 1.0), Color(0.12, 0.08, 0.1), 8)
	box.add_child(l)
	add_child(box)
	var drift := Vector2(randf_range(-28.0, 28.0), 0.0)
	if kind == Kind.EXP_BASE or kind == Kind.EXP_JOB:
		drift = Vector2(0, 0)
	_items.append({"node": box, "anchor": world_pos, "age": 0.0, "kind": kind, "drift": drift, "offset": Vector2.ZERO})


func _label(text: String, font: Font, size: int, color: Color, outline: Color, outline_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	s.outline_size = outline_px
	s.outline_color = outline
	s.shadow_size = 4
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_offset = Vector2(2, 3)
	l.label_settings = s
	return l


func _process(delta: float) -> void:
	if camera == null:
		return
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it.age += delta
		var life := LIFETIME * (1.5 if it.kind == Kind.EXP_BASE or it.kind == Kind.EXP_JOB else 1.0)
		var t: float = it.age / life
		var node: Control = it.node
		if t >= 1.0 or camera.is_position_behind(it.anchor):
			node.queue_free()
			_items.remove_at(i)
			continue
		var base := camera.unproject_position(it.anchor)
		# Pop: overshoot to 1.35x (1.6x for crits) then settle to 1.0.
		var peak := 1.6 if it.kind == Kind.CRIT else 1.35
		var pop := 1.0
		if t < 0.08:
			pop = lerpf(0.3, peak, t / 0.08)
		elif t < 0.22:
			pop = lerpf(peak, 1.0, ease((t - 0.08) / 0.14, 0.5))
		var rise := -70.0 * ease(t, 0.45)
		var arc: Vector2 = it.drift * ease(t, 0.6)
		var shake := Vector2.ZERO
		if it.kind == Kind.CRIT and t < 0.25:
			shake = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		node.scale = Vector2(pop, pop)
		node.reset_size()
		node.pivot_offset = node.size / 2.0
		node.position = base + it.offset + Vector2(0, rise) + arc + shake - node.size / 2.0
		node.modulate.a = 1.0 if t < 0.65 else 1.0 - (t - 0.65) / 0.35
