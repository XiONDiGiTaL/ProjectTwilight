class_name PlayerStatusPanel
extends GlassPanel
## Player status window, top-left like the classic client, in the glass style.
##
## * Class insignia beside name and class title.
## * Slanted HP / SP bars (HP shifts green -> amber -> red) and thin EXP lines.
## * Fades and dims when the cursor is elsewhere; returns to full visibility on
##   hover and briefly whenever HP/SP changes.
## * Collapsible to HP/SP only (chevron); remembered in user settings.

const IDLE_ALPHA := 0.42
const IDLE_DIM := 0.82
const WAKE_ON_CHANGE_SEC := 2.5
const FADE_IN_SPEED := 7.0
const FADE_OUT_SPEED := 2.0
const BAR_WIDTH := 220.0

var _title: Label
var _level_chip: Label
var _subtitle: Label
var _insignia: ClassInsignia
var _toggle: Button
var _divider: ColorRect
var _expanded_only: Array[Control] = []
var _hp: GlassBar
var _sp: GlassBar
var _base: GlassBar
var _job: GlassBar
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
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 14
	offset_top = 14
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(header)
	_insignia = ClassInsignia.new()
	_insignia.custom_minimum_size = Vector2(40, 40)
	header.add_child(_insignia)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(names)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(name_row)
	_title = UiTheme.label("", 17, UiTheme.TEXT, 600, 1)
	name_row.add_child(_title)
	# SAO-style level chip.
	_level_chip = UiTheme.label("", 11, Color.WHITE, 700, 1)
	_level_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(UiTheme.ACCENT, 0.45)
	chip.border_color = Color(0.85, 0.95, 1.0, 0.8)
	chip.border_width_left = 1
	chip.border_width_bottom = 1
	chip.skew = Vector2(-0.25, 0)
	chip.content_margin_left = 7
	chip.content_margin_right = 7
	chip.content_margin_top = 0
	chip.content_margin_bottom = 1
	_level_chip.add_theme_stylebox_override("normal", chip)
	_level_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_level_chip)
	_subtitle = UiTheme.label("", 10, UiTheme.TEXT_DIM, 600, 2)
	names.add_child(_subtitle)
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.tooltip_text = "Collapse / expand"
	_toggle.add_theme_font_override("font", UiTheme.font(600))
	_toggle.add_theme_font_size_override("font_size", 13)
	_toggle.add_theme_color_override("font_color", UiTheme.ACCENT)
	_toggle.add_theme_color_override("font_hover_color", Color.WHITE)
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle.pressed.connect(func(): set_collapsed(not _collapsed))
	header.add_child(_toggle)

	_divider = ColorRect.new()
	_divider.custom_minimum_size = Vector2(0, 1)
	_divider.color = Color(UiTheme.ACCENT, 0.22)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_divider)
	_expanded_only.append(_divider)

	# SAO party plate: wide HP bar, thinner SP bar beneath, numbers in a plate.
	_hp = GlassBar.new()
	_hp.style = GlassBar.Style.HP
	_hp.custom_minimum_size = Vector2(BAR_WIDTH + 86, 17)
	col.add_child(_hp)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 8)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(under)
	_sp = GlassBar.new()
	_sp.style = GlassBar.Style.SP
	_sp.ticks = 0.0
	_sp.glow_px = 2.0
	_sp.custom_minimum_size = Vector2(BAR_WIDTH - 40, 10)
	_sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	under.add_child(_sp)
	var plate := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.06, 0.1, 0.7)
	psb.border_color = Color(0.85, 0.93, 1.0, 0.45)
	psb.set_border_width_all(1)
	psb.content_margin_left = 8
	psb.content_margin_right = 8
	psb.content_margin_top = 1
	psb.content_margin_bottom = 2
	plate.add_theme_stylebox_override("panel", psb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(plate)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 6)
	plate.add_child(nums)
	_hp_text = UiTheme.label("", 12, UiTheme.TEXT, 600)
	nums.add_child(_hp_text)
	nums.add_child(UiTheme.label("|", 11, Color(UiTheme.TEXT_DIM, 0.6), 400))
	_sp_text = UiTheme.label("", 11, Color(0.75, 0.88, 1.0), 600)
	nums.add_child(_sp_text)
	var be := _row(col, "BASE", GlassBar.Style.BASE_EXP, 8.0, 11, true)
	_base = be[0]; _base_text = be[1]
	var je := _row(col, "JOB", GlassBar.Style.JOB_EXP, 8.0, 11, true)
	_job = je[0]; _job_text = je[1]

	var settings := get_node_or_null("/root/Settings")
	set_collapsed(bool(settings.get_value("ui", "status_collapsed", false)) if settings else false, false)


func _row(parent: Control, caption: String, style: GlassBar.Style, height: float, text_size: int, exp_row: bool) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var cap := UiTheme.label(caption, 10, Color(UiTheme.ACCENT, 0.85), 600, 2)
	cap.custom_minimum_size = Vector2(36, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	var bar := GlassBar.new()
	bar.style = style
	bar.ticks = 0.0 if exp_row else 10.0
	bar.glow_px = 2.0 if exp_row else 3.0
	bar.custom_minimum_size = Vector2(BAR_WIDTH, height)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var txt := UiTheme.label("", text_size, UiTheme.TEXT if not exp_row else UiTheme.TEXT_DIM, 600 if not exp_row else 400)
	txt.custom_minimum_size = Vector2(70, 0)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(txt)
	if exp_row:
		_expanded_only.append(row)
	return [bar, txt]


func set_collapsed(value: bool, save := true) -> void:
	_collapsed = value
	_toggle.text = "▸" if _collapsed else "▾"
	for r in _expanded_only:
		r.visible = not _collapsed
	_subtitle.visible = not _collapsed
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
	_level_chip.text = "Lv.%d" % u.level
	_subtitle.text = "%s   ·   JOB LV %d" % [job_name.to_upper(), u.job_level]
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
	_sp_text.text = "SP %d / %d" % [u.sp, u.max_sp]
	_base_text.text = ("%.1f%%" % (100.0 * u.base_exp / next_base)) if next_base > 0 else "MAX"
	_job_text.text = ("%.1f%%" % (100.0 * u.job_exp / next_job)) if next_job > 0 else "MAX"


func _set_exp(bar: GlassBar, value: int, maximum: int) -> void:
	# EXP only grows; a lower fraction means the level rolled over.
	if float(value) / maximum < bar.fraction():
		bar.snap(value, maximum)
	else:
		bar.set_value(value, maximum)


func _process(delta: float) -> void:
	var hovered := get_global_rect().grow(6).has_point(get_global_mouse_position())
	_wake = maxf(0.0, _wake - delta)
	var target := 1.0 if hovered or _wake > 0.0 else 0.0
	var speed := FADE_IN_SPEED if target > _alpha else FADE_OUT_SPEED
	_alpha = move_toward(_alpha, target, delta * speed)
	var a := lerpf(IDLE_ALPHA, 1.0, _alpha)
	var dim := lerpf(IDLE_DIM, 1.0, _alpha)
	modulate = Color(dim, dim, dim, a)
	set_glow(0.35 * _alpha if hovered else 0.0)
