class_name SkillWindow
extends GlassWindow
## Skill window (classic Alt+S): skill rows with client icons, level, learn
## button and tooltips; active skills can be dragged onto the hotkey bar or
## double-clicked to use.

signal learn_requested(code: String)
signal use_requested(code: String)

var skill_db: Dictionary = {}
## Callable(unit) -> Array of skill codes available to the unit's class.
var available: Callable
## Callable(unit, code) -> "" or the unmet prerequisite text.
var requirements: Callable
var _unit: SimUnit
var _list: VBoxContainer
var _points: Label


func _init() -> void:
	super._init()
	title = "SKILLS"
	window_id = "skills"


func _ready() -> void:
	super._ready()
	_points = UiTheme.label("", 12, UiTheme.CRIT, 600, 2)
	body.add_child(_points)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	body.add_child(_list)
	body.add_child(UiTheme.label("Drag active skills to the hotkey bar  ·  double-click to use", 10, UiTheme.TEXT_DIM, 400, 1))
	visible = false


func bind_unit(u: SimUnit, db: Dictionary) -> void:
	_unit = u
	skill_db = db
	refresh()


func refresh() -> void:
	if _list == null or _unit == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_points.text = "SKILL POINTS   %d" % _unit.skill_points
	var codes: Array = available.call(_unit) if available.is_valid() else skill_db.keys()
	for code in codes:
		var s: Dictionary = skill_db[code]
		var lv := int(_unit.skills.get(code, 0))
		var unmet: String = requirements.call(_unit, code) if requirements.is_valid() else ""
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var entry := SkillEntry.new()
		entry.code = code
		entry.def = s
		entry.level = lv
		entry.unmet = unmet
		entry.custom_minimum_size = Vector2(300, 40)
		entry.activated.connect(func(c): use_requested.emit(c))
		row.add_child(entry)
		var b := Button.new()
		b.text = "+"
		b.custom_minimum_size = Vector2(30, 30)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiTheme.style_button(b, false, false, 13)
		b.disabled = s.get("quest", false) or lv >= int(s.max_level) or _unit.skill_points <= 0 or unmet != ""
		b.tooltip_text = "Quest skill" if s.get("quest", false) else (unmet if unmet != "" else "Learn one level")
		b.pressed.connect(func(): learn_requested.emit(code))
		row.add_child(b)
	reset_size()


## One skill row: icon, name, level bar, tooltip; drag source for active skills.
class SkillEntry extends Control:
	signal activated(code: String)
	var code := ""
	var def: Dictionary = {}
	var level := 0
	var unmet := ""
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = String(def.get("name", ""))
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _usable() -> bool:
		return level > 0 and def.get("type", "passive") != "passive"

	func _gui_input(e: InputEvent) -> void:
		if _usable() and e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(code)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if not _usable():
			return null
		var icon := TextureRect.new()
		icon.texture = ItemIcons.icon(def)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.modulate.a = 0.8
		set_drag_preview(icon)
		return {"type": "skill", "id": code}

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.05, 0.09, 0.45))
		draw_rect(r.grow(-0.5), Color(UiTheme.ACCENT, 0.45 if _hover else 0.14), false, 1.0)
		var icon := ItemIcons.icon(def)
		if icon:
			draw_texture_rect(icon, Rect2(Vector2(8, 8), Vector2(24, 24)), false, Color(1, 1, 1, 1.0 if level > 0 else 0.35))
		var name_col := UiTheme.TEXT if level > 0 else UiTheme.TEXT_DIM
		draw_string(UiTheme.font(600), Vector2(42, 18), String(def.get("name", code)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
		var kind := String(def.get("type", "")).to_upper() + ("  ·  QUEST" if def.get("quest", false) else "")
		draw_string(UiTheme.font(600, 2), Vector2(42, 33), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UiTheme.ACCENT, 0.75))
		var maxl := int(def.get("max_level", 1))
		var lvtxt := "LV %d / %d" % [level, maxl]
		var w := UiTheme.font(600).get_string_size(lvtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(UiTheme.font(600), Vector2(size.x - w - 10, 18), lvtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)
		# Level pips.
		var pip_w := 8.0
		for i in maxl:
			var x := size.x - 10 - (maxl - i) * (pip_w + 2)
			draw_rect(Rect2(x, 26, pip_w, 4), UiTheme.ACCENT if i < level else Color(UiTheme.ACCENT, 0.15))

	func _make_custom_tooltip(_t: String) -> Object:
		var p := GlassPanel.new()
		p.chamfer = 8.0
		p.sweep = false
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		p.add_child(col)
		col.add_child(UiTheme.label(String(def.get("name", "")), 14, UiTheme.TEXT, 600, 1))
		var d := UiTheme.label(String(def.get("desc", "")), 12, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(260, 0)
		col.add_child(d)
		if def.has("unlocks"):
			for lv in def.unlocks:
				var have := int(lv) <= level
				col.add_child(UiTheme.label("LV %s   %s" % [lv, def.unlocks[lv]], 11, UiTheme.HP_HIGH if have else UiTheme.TEXT_DIM, 600 if have else 400))
		if def.has("sp_cost"):
			var costs: Array = def.sp_cost
			var shown := int(costs[clampi(maxi(level, 1) - 1, 0, costs.size() - 1)])
			col.add_child(UiTheme.label("SP COST  %d" % shown, 11, UiTheme.SP, 600, 2))
		if unmet != "":
			col.add_child(UiTheme.label(unmet, 11, UiTheme.HP_MID, 600))
		return p
