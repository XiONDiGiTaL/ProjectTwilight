class_name EquipmentWindow
extends GlassWindow
## Equipment window (classic Alt+Q): one row per slot with icon and name,
## ATK / DEF totals. Double-click an equipped row to unequip it.

signal unequip_requested(slot: String)

const SLOTS := [
	["head_top", "HEAD"], ["head_mid", "FACE"], ["head_low", "MOUTH"],
	["weapon", "WEAPON"], ["shield", "SHIELD"], ["body", "ARMOR"],
	["garment", "GARMENT"], ["shoes", "SHOES"], ["acc1", "ACCESSORY"], ["acc2", "ACCESSORY"],
]

var item_db: Dictionary = {}
var _unit: SimUnit
var _list: VBoxContainer
var _totals: Label


func _init() -> void:
	super._init()
	title = "EQUIPMENT"
	window_id = "equipment"


func _ready() -> void:
	super._ready()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	body.add_child(_list)
	_totals = UiTheme.label("", 12, UiTheme.TEXT, 600, 2)
	body.add_child(_totals)
	body.add_child(UiTheme.label("Double-click to unequip  ·  equip from the inventory", 10, UiTheme.TEXT_DIM, 400, 1))
	visible = false


func bind_unit(u: SimUnit, db: Dictionary) -> void:
	_unit = u
	item_db = db
	refresh()


func refresh() -> void:
	if _list == null or _unit == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for s in SLOTS:
		var slot: String = s[0]
		var id := int(_unit.equipment.get(slot, 0))
		_list.add_child(_row(slot, s[1], item_db.get(str(id), {}) if id != 0 else {}))
	_totals.text = "ATK  %d ~ %d      DEF  %d      ASPD  %d" % [_unit.atk_min, _unit.atk_max, _unit.hard_def,
		roundi(200.0 - _unit.attack_interval / 20.0)]
	reset_size()


func _row(slot: String, caption: String, def: Dictionary) -> Control:
	var row := EquipRow.new()
	row.slot = slot
	row.caption = caption
	row.def = def
	row.custom_minimum_size = Vector2(300, 30)
	row.activated.connect(func(s): unequip_requested.emit(s))
	return row


class EquipRow extends Control:
	signal activated(slot: String)
	var slot := ""
	var caption := ""
	var def: Dictionary = {}
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if not def.is_empty() and e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(slot)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.05, 0.09, 0.45))
		draw_rect(r.grow(-0.5), Color(UiTheme.ACCENT, 0.5 if _hover and not def.is_empty() else 0.14), false, 1.0)
		var f := UiTheme.font(600, 2)
		draw_string(f, Vector2(10, size.y / 2 + 4), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.ACCENT, 0.85))
		var icon := ItemIcons.icon(def) if not def.is_empty() else null
		if icon:
			draw_texture_rect(icon, Rect2(Vector2(96, 3), Vector2(24, 24)), false)
		var name := String(def.get("name", "—"))
		var col := UiTheme.TEXT if not def.is_empty() else Color(UiTheme.TEXT_DIM, 0.5)
		draw_string(UiTheme.font(600), Vector2(128, size.y / 2 + 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		var stat := ""
		if def.has("atk"):
			stat = "ATK %d" % def.atk
		elif def.has("def"):
			stat = "DEF %d" % def.def
		if stat != "":
			var w := UiTheme.font(400).get_string_size(stat, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(UiTheme.font(400), Vector2(size.x - w - 10, size.y / 2 + 4), stat, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
