class_name StatusWindow
extends GlassWindow
## Status window (classic Alt+A): base stats with raise buttons and costs,
## remaining status points, and derived combat values.

signal raise_requested(stat: String)

const STATS := ["str", "agi", "vit", "int", "dex", "luk"]

var _unit: SimUnit
var _rows: Dictionary = {}   # stat -> {value: Label, cost: Label, button: Button}
var _points: Label
var _derived: Dictionary = {}


func _init() -> void:
	super._init()
	title = "STATUS"
	window_id = "status"


func _ready() -> void:
	super._ready()
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	for s in STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		left.add_child(row)
		var name := UiTheme.label(s.to_upper(), 12, Color(UiTheme.ACCENT, 0.9), 600, 3)
		name.custom_minimum_size = Vector2(40, 0)
		row.add_child(name)
		var value := UiTheme.label("", 15, UiTheme.TEXT, 600)
		value.custom_minimum_size = Vector2(34, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		var b := Button.new()
		b.text = "+"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(24, 22)
		b.add_theme_font_override("font", UiTheme.font(600))
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_disabled_color", Color(UiTheme.TEXT_DIM, 0.35))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.ACCENT, 0.14)
		sb.border_color = Color(UiTheme.ACCENT, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate() as StyleBoxFlat
		sbh.bg_color = Color(UiTheme.ACCENT, 0.3)
		b.add_theme_stylebox_override("hover", sbh)
		var sbd := sb.duplicate() as StyleBoxFlat
		sbd.bg_color = Color(0, 0, 0, 0.1)
		sbd.border_color = Color(UiTheme.ACCENT, 0.15)
		b.add_theme_stylebox_override("disabled", sbd)
		b.pressed.connect(func(): raise_requested.emit(s))
		row.add_child(b)
		var cost := UiTheme.label("", 10, UiTheme.TEXT_DIM, 400, 1)
		cost.custom_minimum_size = Vector2(46, 0)
		row.add_child(cost)
		_rows[s] = {"value": value, "cost": cost, "button": b}
	_points = UiTheme.label("", 12, UiTheme.CRIT, 600, 2)
	left.add_child(_points)
	var right := GridContainer.new()
	right.columns = 2
	right.add_theme_constant_override("h_separation", 14)
	right.add_theme_constant_override("v_separation", 4)
	cols.add_child(right)
	for k in ["ATK", "MATK", "HIT", "FLEE", "CRIT", "ASPD", "SOFT DEF", "WEIGHT"]:
		right.add_child(UiTheme.label(k, 11, Color(UiTheme.ACCENT, 0.85), 600, 2))
		var v := UiTheme.label("", 13, UiTheme.TEXT, 600)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(70, 0)
		right.add_child(v)
		_derived[k] = v
	visible = false


func bind_unit(u: SimUnit) -> void:
	_unit = u
	refresh()


func refresh() -> void:
	if _unit == null or _rows.is_empty():
		return
	for s in STATS:
		var v := int(_unit.stats[s])
		var cost := StatRulesPreRenewal.raise_cost(v)
		var r: Dictionary = _rows[s]
		(r.value as Label).text = str(v)
		(r.cost as Label).text = ("cost %d" % cost) if cost > 0 else "max"
		(r.button as Button).disabled = cost < 0 or cost > _unit.status_points
	_points.text = "STATUS POINTS   %d" % _unit.status_points
	var st := _unit.stats
	var m := StatRulesPreRenewal.matk_range(int(st.int))
	var aspd := CombatRulesPreRenewal.aspd(FieldSimulation.NOVICE_FIST_BTBA, int(st.agi), int(st.dex))
	(_derived["ATK"] as Label).text = str(_unit.atk_max)
	(_derived["MATK"] as Label).text = "%d ~ %d" % [m.x, m.y]
	(_derived["HIT"] as Label).text = str(_unit.hit())
	(_derived["FLEE"] as Label).text = "%d + %d" % [_unit.flee(), StatRulesPreRenewal.perfect_dodge(int(st.luk))]
	(_derived["CRIT"] as Label).text = "%.1f%%" % StatRulesPreRenewal.critical_rate(int(st.luk))
	(_derived["ASPD"] as Label).text = str(roundi(aspd))
	(_derived["SOFT DEF"] as Label).text = str(int(st.vit))
	(_derived["WEIGHT"] as Label).text = str(_unit.max_weight())
