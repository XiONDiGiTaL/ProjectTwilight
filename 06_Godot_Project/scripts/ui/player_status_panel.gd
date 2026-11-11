class_name PlayerStatusPanel
extends PanelContainer
## Compact player status window, top-left like the classic client.
##
## * Sleek spear-tipped HP/SP bars with round badges, thin EXP bars.
## * Fades and dims when the cursor is elsewhere; snaps back to full
##   visibility on hover and briefly whenever HP/SP changes.
## * Collapsible to HP/SP only (chevron in the header); remembered in settings.

const IDLE_ALPHA := 0.45
const IDLE_DIM := 0.8
const WAKE_ON_CHANGE_SEC := 2.5
const FADE_SPEED := 6.0

var _font: SystemFont
var _title: Label
var _insignia: ClassInsignia
var _levels: Label
var _toggle: Button
var _expanded_rows: Array[Control] = []
var _value_labels: Array[Control] = []
var _hp: OrnateBar
var _sp: OrnateBar
var _base: OrnateBar
var _job: OrnateBar
var _hp_text: Label
var _sp_text: Label
var _base_text: Label
var _job_text: Label
var _collapsed := false
var _wake := 0.0
var _alpha := 1.0
var _last_hp := -1
var _last_sp := -1


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Bahnschrift", "Arial"])
	_font.font_weight = 600
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _glass())
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 12
	offset_top = 12
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(header)
	_insignia = ClassInsignia.new()
	_insignia.custom_minimum_size = Vector2(38, 38)
	header.add_child(_insignia)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(names)
	_title = _label("", 15, Color(1.0, 0.93, 0.78))
	names.add_child(_title)
	_levels = _label("", 12, Color(0.78, 0.74, 0.66))
	names.add_child(_levels)
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.tooltip_text = "Collapse / expand"
	_toggle.add_theme_color_override("font_color", Color(0.9, 0.8, 0.55))
	_toggle.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.75))
	_toggle.custom_minimum_size = Vector2(24, 20)
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle.pressed.connect(func(): set_collapsed(not _collapsed))
	header.add_child(_toggle)

	var hp_row := _bar_row(col, "HP", Color(0.75, 0.12, 0.1), OrnateBar.Style.HP, Vector2(230, 22))
	_hp = hp_row[0]; _hp_text = hp_row[1]
	var sp_row := _bar_row(col, "SP", Color(0.15, 0.35, 0.85), OrnateBar.Style.SP, Vector2(230, 20))
	_sp = sp_row[0]; _sp_text = sp_row[1]
	var be := _exp_row(col, "Base", OrnateBar.Style.BASE_EXP)
	_base = be[0]; _base_text = be[1]
	var je := _exp_row(col, "Job", OrnateBar.Style.JOB_EXP)
	_job = je[0]; _job_text = je[1]

	var settings := get_node_or_null("/root/Settings")
	set_collapsed(bool(settings.get_value("ui", "status_collapsed", false)) if settings else false, false)


func set_collapsed(value: bool, save := true) -> void:
	_collapsed = value
	_toggle.text = "▸" if _collapsed else "▾"
	for r in _expanded_rows:
		r.visible = not _collapsed
	for l in _value_labels:
		l.visible = not _collapsed
	_levels.visible = not _collapsed
	reset_size()
	_wake = WAKE_ON_CHANGE_SEC
	var settings := get_node_or_null("/root/Settings")
	if save and settings:
		settings.set_value("ui", "status_collapsed", _collapsed)


func is_collapsed() -> bool:
	return _collapsed


func update_unit(u: SimUnit, next_base: int, next_job: int, first := false) -> void:
	_title.text = u.name
	if _insignia.class_id != u.job:
		_insignia.set_class(u.job)
	var job_name := String(ClassInsignia.classes().get(u.job, {}).get("name", u.job.capitalize()))
	_levels.text = "%s  ·  Base %d  ·  Job %d" % [job_name, u.level, u.job_level]
	if first:
		_hp.snap(u.hp, u.max_hp)
		_sp.snap(u.sp, u.max_sp)
		_base.snap(u.base_exp, maxi(next_base, 1))
		_job.snap(u.job_exp, maxi(next_job, 1))
	else:
		_hp.set_value(u.hp, u.max_hp)
		_sp.set_value(u.sp, u.max_sp)
		_set_exp(_base, u.base_exp, maxi(next_base, 1))
		_set_exp(_job, u.job_exp, maxi(next_job, 1))
		if u.hp != _last_hp or u.sp != _last_sp:
			_wake = WAKE_ON_CHANGE_SEC
	_last_hp = u.hp
	_last_sp = u.sp
	_hp_text.text = "%d / %d" % [u.hp, u.max_hp]
	_sp_text.text = "%d / %d" % [u.sp, u.max_sp]
	_base_text.text = ("%.1f%%" % (100.0 * u.base_exp / next_base)) if next_base > 0 else "MAX"
	_job_text.text = ("%.1f%%" % (100.0 * u.job_exp / next_job)) if next_job > 0 else "MAX"


func _set_exp(bar: OrnateBar, value: int, maximum: int) -> void:
	# EXP only grows; a lower fraction means the level rolled over.
	if float(value) / maximum < bar.fraction():
		bar.snap(value, maximum)
	else:
		bar.set_value(value, maximum)


func _process(delta: float) -> void:
	var hovered := get_global_rect().grow(6).has_point(get_global_mouse_position())
	_wake = maxf(0.0, _wake - delta)
	var target := 1.0 if hovered or _wake > 0.0 else 0.0
	_alpha = move_toward(_alpha, target, delta * FADE_SPEED * (1.0 if target > _alpha else 0.35))
	var a := lerpf(IDLE_ALPHA, 1.0, _alpha)
	var dim := lerpf(IDLE_DIM, 1.0, _alpha)
	modulate = Color(dim, dim, dim, a)


func _bar_row(parent: Control, badge: String, badge_color: Color, style: OrnateBar.Style, bar_size: Vector2) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	row.add_child(_badge(badge, badge_color))
	var bar := OrnateBar.new()
	bar.style = style
	bar.sleek = true
	bar.show_diamond = false
	bar.custom_minimum_size = bar_size
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var txt := _label("", 12, Color(0.95, 0.95, 0.95))
	txt.custom_minimum_size = Vector2(74, 0)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(txt)
	_value_labels.append(txt)
	return [bar, txt]


func _exp_row(parent: Control, caption: String, style: OrnateBar.Style) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var cap := _label(caption, 11, Color(0.8, 0.75, 0.62))
	cap.custom_minimum_size = Vector2(30, 0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	var bar := OrnateBar.new()
	bar.style = style
	bar.sleek = true
	bar.show_diamond = false
	bar.custom_minimum_size = Vector2(230, 13)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var txt := _label("", 11, Color(0.9, 0.88, 0.8))
	txt.custom_minimum_size = Vector2(74, 0)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(txt)
	_expanded_rows.append(row)
	return [bar, txt]


func _badge(text: String, color: Color) -> Label:
	var l := _label(text, 10, Color(1, 1, 1))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(26, 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.border_color = Color(0.85, 0.7, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	l.add_theme_stylebox_override("normal", sb)
	l.label_settings.outline_size = 3
	return l


func _glass() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.065, 0.74)
	sb.border_color = Color(0.78, 0.62, 0.32, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = _font
	s.font_size = size
	s.font_color = color
	s.outline_size = 4
	s.outline_color = Color(0.02, 0.02, 0.03, 0.9)
	l.label_settings = s
	return l
