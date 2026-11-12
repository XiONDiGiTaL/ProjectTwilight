class_name InventoryWindow
extends GlassWindow
## Inventory in the glass style: ITEM / EQUIP / ETC tabs (as in the classic
## client), slot grid with client icons and stack counts, rich tooltips,
## weight bar and Zeny. Double-click a usable item to use it.

signal use_requested(index: int)
signal equip_requested(index: int)

const COLUMNS := 7
const ROWS := 4
const SLOT := 46.0
const TABS := [["ITEM", "usable"], ["EQUIP", "weapon"], ["ETC", "etc"]]

var item_db: Dictionary = {}
var _unit: SimUnit
var _tab := 0
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _weight_bar: GlassBar
var _weight_text: Label
var _zeny_text: Label


func _init() -> void:
	super._init()
	title = "INVENTORY"
	window_id = "inventory"


func _ready() -> void:
	super._ready()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	body.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][0]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(80, 28)
		b.add_theme_font_override("font", UiTheme.font(600, 3))
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		b.add_theme_stylebox_override("normal", _tab_style(false))
		b.add_theme_stylebox_override("hover", _tab_style(false, true))
		b.add_theme_stylebox_override("pressed", _tab_style(true))
		b.add_theme_stylebox_override("hover_pressed", _tab_style(true))
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(_grid)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	body.add_child(foot)
	foot.add_child(UiTheme.label("WEIGHT", 10, Color(UiTheme.ACCENT, 0.85), 600, 2))
	_weight_bar = GlassBar.new()
	_weight_bar.style = GlassBar.Style.BASE_EXP
	_weight_bar.ticks = 0.0
	_weight_bar.glow_px = 2.0
	_weight_bar.custom_minimum_size = Vector2(120, 8)
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_weight_bar)
	_weight_text = UiTheme.label("", 11, UiTheme.TEXT_DIM)
	_weight_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_weight_text)
	foot.add_child(UiTheme.label("ZENY", 10, Color(UiTheme.ACCENT, 0.85), 600, 2))
	_zeny_text = UiTheme.label("0", 12, UiTheme.CRIT, 600)
	foot.add_child(_zeny_text)
	_select_tab(0)
	visible = false


func _tab_style(active: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.ACCENT, 0.16 if active else (0.08 if hover else 0.03))
	sb.border_color = Color(UiTheme.ACCENT, 0.7 if active else 0.25)
	sb.border_width_bottom = 2 if active else 1
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _select_tab(i: int) -> void:
	_tab = i
	for k in _tab_buttons.size():
		_tab_buttons[k].button_pressed = k == i
	refresh()


func bind_unit(u: SimUnit, db: Dictionary) -> void:
	_unit = u
	item_db = db
	refresh()


func refresh() -> void:
	if _grid == null or _unit == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var want: String = TABS[_tab][1]
	var shown := 0
	for i in _unit.inventory.entries.size():
		var e: Dictionary = _unit.inventory.entries[i]
		var def: Dictionary = item_db.get(str(e.id), {})
		var t := String(def.get("type", "etc"))
		var bucket := "weapon" if t in ["weapon", "armor"] else ("usable" if t == "ammo" else t)
		if bucket != want:
			continue
		_grid.add_child(_slot(i, e, def))
		shown += 1
	for k in range(shown, COLUMNS * ROWS):
		_grid.add_child(_slot(-1, {}, {}))
	var w := _unit.inventory.weight(item_db)
	var mw := _unit.max_weight()
	_weight_bar.set_value(w, mw)
	_weight_text.text = "%d / %d" % [w, mw]
	_zeny_text.text = _fmt_zeny(_unit.zeny)
	reset_size()


func _slot(index: int, e: Dictionary, def: Dictionary) -> Control:
	var slot := ItemSlot.new()
	slot.custom_minimum_size = Vector2(SLOT, SLOT)
	slot.index = index
	if index >= 0:
		slot.icon = ItemIcons.icon(def)
		slot.amount = int(e.amount)
		slot.def = def
		slot._item_id = int(e.id)
		if String(def.get("equip", "")) != "":
			slot.activated.connect(func(i): equip_requested.emit(i))
		elif String(def.get("type", "")) == "usable":
			slot.activated.connect(func(i): use_requested.emit(i))
	return slot


static func _fmt_zeny(z: int) -> String:
	var s := str(z)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


## One inventory slot: glass cell, icon, stack count, glass tooltip.
class ItemSlot extends Control:
	signal activated(index: int)
	var index := -1
	var icon: Texture2D
	var amount := 0
	var def: Dictionary = {}
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if index >= 0 else Control.MOUSE_FILTER_IGNORE
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())
		if index >= 0:
			tooltip_text = String(def.get("name", ""))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(index)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.05, 0.09, 0.55))
		var border := Color(UiTheme.ACCENT, 0.55 if _hover else 0.18)
		draw_rect(r.grow(-0.5), border, false, 1.0)
		if _hover:
			draw_rect(r.grow(-1.5), Color(UiTheme.ACCENT, 0.08))
		if icon:
			var s := minf(size.x, size.y) - 12.0
			var isz := icon.get_size()
			var k := minf(s / isz.x, s / isz.y)
			var dst := Rect2((size - isz * k) / 2.0, isz * k)
			draw_texture_rect(icon, dst, false)
		if amount > 1:
			var f := UiTheme.font(600)
			var txt := str(amount)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var pos := Vector2(size.x - w - 4, size.y - 4)
			draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.8))
			draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)

	func _get_drag_data(_at: Vector2) -> Variant:
		if index < 0 or def.get("type", "") != "usable" or icon == null:
			return null
		var preview := TextureRect.new()
		preview.texture = icon
		preview.custom_minimum_size = Vector2(32, 32)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return {"type": "item", "id": _item_id}

	var _item_id := 0

	func _make_custom_tooltip(_text: String) -> Object:
		var p := GlassPanel.new()
		p.chamfer = 8.0
		p.sweep = false
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		p.add_child(col)
		col.add_child(UiTheme.label(String(def.get("name", "")), 14, UiTheme.TEXT, 600, 1))
		var kind := String(def.get("type", "etc")).to_upper()
		col.add_child(UiTheme.label("%s   ·   WEIGHT %d" % [kind, int(def.get("weight", 0))], 10, UiTheme.ACCENT, 600, 2))
		if def.has("heal_hp"):
			var h: Array = def.heal_hp
			col.add_child(UiTheme.label("Restores %d – %d HP" % [h[0], h[1]], 12, UiTheme.HP_HIGH))
		if def.has("atk"):
			col.add_child(UiTheme.label("ATK %d   ·   Slots %d" % [def.atk, def.get("slots", 0)], 12, UiTheme.TEXT))
		var d := UiTheme.label(String(def.get("desc", "")), 12, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(230, 0)
		col.add_child(d)
		if def.get("type", "") == "usable":
			col.add_child(UiTheme.label("Double-click to use", 10, Color(UiTheme.ACCENT, 0.8), 400, 1))
		elif String(def.get("equip", "")) != "":
			col.add_child(UiTheme.label("Double-click to equip", 10, Color(UiTheme.ACCENT, 0.8), 400, 1))
		if def.has("def"):
			col.add_child(UiTheme.label("DEF %d" % def.def, 12, UiTheme.TEXT))
		return p
