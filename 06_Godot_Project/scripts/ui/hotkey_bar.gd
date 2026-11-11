class_name HotkeyBar
extends GlassPanel
## F1–F9 hotkey bar (bottom centre). Drop skills from the skill window or
## usable items from the inventory onto a slot; press the key or click to use;
## right-click clears. Item slots show how many are left.

signal activate_requested(index: int)
signal changed

const SLOT_COUNT := 9
const SLOT := 46.0

var item_db: Dictionary = {}
var skill_db: Dictionary = {}
var _unit: SimUnit
var _slots: Array[HotkeySlot] = []


func _ready() -> void:
	chamfer = 10.0
	padding = Vector4(10, 8, 10, 8)
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	add_child(row)
	for i in SLOT_COUNT:
		var s := HotkeySlot.new()
		s.index = i
		s.bar = self
		s.custom_minimum_size = Vector2(SLOT, SLOT)
		row.add_child(s)
		_slots.append(s)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _process(_d: float) -> void:
	# Keep the bar bottom-centre at any window size.
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2(roundf((vp.x - size.x) / 2.0), vp.y - size.y - 14.0)


func bind_unit(u: SimUnit, items: Dictionary, skills: Dictionary) -> void:
	_unit = u
	item_db = items
	skill_db = skills
	refresh()


func entry(i: int) -> Variant:
	return _unit.hotkeys[i] if _unit and i < _unit.hotkeys.size() else null


func set_entry(i: int, e: Variant) -> void:
	if _unit == null:
		return
	# A skill or item lives in one slot at a time.
	if e != null:
		for k in _unit.hotkeys.size():
			var other: Variant = _unit.hotkeys[k]
			if other != null and other.type == e.type and str(other.id) == str(e.id):
				_unit.hotkeys[k] = null
	_unit.hotkeys[i] = e
	refresh()
	changed.emit()


func refresh() -> void:
	for s in _slots:
		s.queue_redraw()


## Icon / count / label for a slot, resolved against the unit's state.
func describe(i: int) -> Dictionary:
	var e: Variant = entry(i)
	if e == null:
		return {}
	if e.type == "item":
		var def: Dictionary = item_db.get(str(int(e.id)), {})
		return {"icon": ItemIcons.icon(def), "count": _unit.inventory.count(int(e.id)), "name": def.get("name", ""), "dim": _unit.inventory.count(int(e.id)) == 0}
	var s: Dictionary = skill_db.get(String(e.id), {})
	var active: bool = String(e.id) == "NV_TRICKDEAD" and _unit.trickdead
	var icon_def := s.duplicate()
	if active:
		icon_def.resname = String(s.resname) + "_on"
	return {"icon": ItemIcons.icon(icon_def), "count": -1, "name": s.get("name", ""),
		"dim": int(_unit.skills.get(String(e.id), 0)) == 0, "active": active}


class HotkeySlot extends Control:
	var index := 0
	var bar: HotkeyBar
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				bar.activate_requested.emit(index)
				accept_event()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				bar.set_entry(index, null)
				accept_event()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and String(data.get("type", "")) in ["item", "skill"]

	func _drop_data(_at: Vector2, data: Variant) -> void:
		bar.set_entry(index, {"type": String(data.type), "id": data.id})

	func _get_drag_data(_at: Vector2) -> Variant:
		var e: Variant = bar.entry(index)
		if e == null:
			return null
		bar.set_entry(index, null)
		return e

	func _make_custom_tooltip(_t: String) -> Object:
		return null

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.05, 0.09, 0.55))
		var d := bar.describe(index)
		var border_a := 0.6 if _hover else 0.2
		if d.get("active", false):
			border_a = 1.0
			draw_rect(r.grow(-1.5), Color(UiTheme.ACCENT, 0.15))
		draw_rect(r.grow(-0.5), Color(UiTheme.ACCENT, border_a), false, 1.0)
		var icon: Texture2D = d.get("icon")
		if icon:
			var isz := icon.get_size()
			var k := minf((size.x - 14) / isz.x, (size.y - 14) / isz.y)
			draw_texture_rect(icon, Rect2((size - isz * k) / 2.0 + Vector2(0, 2), isz * k), false,
				Color(1, 1, 1, 0.35 if d.get("dim", false) else 1.0))
		var f := UiTheme.font(600, 1)
		draw_string_outline(f, Vector2(4, 12), "F%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(4, 12), "F%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UiTheme.ACCENT, 0.9))
		var count := int(d.get("count", -1))
		if count >= 0:
			var txt := str(count)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string_outline(f, Vector2(size.x - w - 4, size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(size.x - w - 4, size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.HP_LOW if count == 0 else UiTheme.TEXT)
		if _hover and d.has("name"):
			tooltip_text = String(d.name)
