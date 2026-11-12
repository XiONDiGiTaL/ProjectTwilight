class_name ShopWindow
extends GlassWindow
## NPC shop: greeting, BUY / SELL tabs, item rows with icons and prices,
## quantity selector, running total and Zeny. Trades are requested from the
## simulation, which validates them (Zeny, weight, distance).

signal buy_requested(item_id: int, amount: int)
signal sell_requested(index: int, amount: int)
signal shop_closed

var item_db: Dictionary = {}
var _unit: SimUnit
var _catalog: Array = []
var _selling := false
var _selected := -1           # buy: catalog index; sell: inventory index
var _greeting: Label
var _list: VBoxContainer
var _qty: SpinBox
var _total: Label
var _zeny: Label
var _confirm: Button
var _tab_buy: Button
var _tab_sell: Button


func _init() -> void:
	super._init()
	title = "SHOP"
	window_id = "shop"


func _ready() -> void:
	super._ready()
	closed.connect(func(): shop_closed.emit())
	_greeting = UiTheme.label("", 12, UiTheme.TEXT_DIM, 400)
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.custom_minimum_size = Vector2(360, 0)
	body.add_child(_greeting)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	body.add_child(tabs)
	_tab_buy = _tab("BUY", false)
	_tab_sell = _tab("SELL", true)
	tabs.add_child(_tab_buy)
	tabs.add_child(_tab_sell)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	body.add_child(foot)
	foot.add_child(UiTheme.label("QTY", 10, Color(UiTheme.ACCENT, 0.85), 600, 2))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = 99
	_qty.value = 1
	_qty.custom_minimum_size = Vector2(80, 0)
	_qty.value_changed.connect(func(_v): _update_total())
	foot.add_child(_qty)
	_total = UiTheme.label("", 12, UiTheme.TEXT, 600, 1)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_total)
	_confirm = Button.new()
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.custom_minimum_size = Vector2(90, 28)
	_confirm.add_theme_font_override("font", UiTheme.font(600, 3))
	_confirm.add_theme_font_size_override("font_size", 12)
	_confirm.add_theme_color_override("font_color", UiTheme.TEXT)
	_confirm.add_theme_color_override("font_disabled_color", Color(UiTheme.TEXT_DIM, 0.4))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.ACCENT, 0.22)
	sb.border_color = Color(UiTheme.ACCENT, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_confirm.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(UiTheme.ACCENT, 0.4)
	_confirm.add_theme_stylebox_override("hover", sbh)
	var sbd := sb.duplicate() as StyleBoxFlat
	sbd.bg_color = Color(0, 0, 0, 0.15)
	sbd.border_color = Color(UiTheme.ACCENT, 0.2)
	_confirm.add_theme_stylebox_override("disabled", sbd)
	_confirm.pressed.connect(_on_confirm)
	foot.add_child(_confirm)
	var zrow := HBoxContainer.new()
	body.add_child(zrow)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zrow.add_child(sp)
	zrow.add_child(UiTheme.label("ZENY  ", 10, Color(UiTheme.ACCENT, 0.85), 600, 2))
	_zeny = UiTheme.label("", 13, UiTheme.CRIT, 600)
	zrow.add_child(_zeny)
	visible = false


func _tab(text: String, sell: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(90, 28)
	b.add_theme_font_override("font", UiTheme.font(600, 3))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		var active: bool = String(state).contains("pressed")
		sb.bg_color = Color(UiTheme.ACCENT, 0.16 if active else 0.04)
		sb.border_color = Color(UiTheme.ACCENT, 0.7 if active else 0.25)
		sb.border_width_bottom = 2 if active else 1
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): _set_mode(sell))
	return b


## Opens the shop for a unit with the NPC's catalog.
func open(npc_name: String, greeting: String, catalog: Array, u: SimUnit, db: Dictionary) -> void:
	title = "SHOP  ·  " + npc_name.to_upper()
	set_title(title)
	_greeting.text = "“%s”" % greeting if greeting != "" else ""
	_catalog = catalog
	_unit = u
	item_db = db
	_set_mode(false)
	toggle(true)


func _set_mode(sell: bool) -> void:
	_selling = sell
	_tab_buy.button_pressed = not sell
	_tab_sell.button_pressed = sell
	_selected = -1
	refresh()


func refresh() -> void:
	if _list == null or _unit == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _selling:
		for i in _unit.inventory.entries.size():
			var e: Dictionary = _unit.inventory.entries[i]
			var def: Dictionary = item_db.get(str(e.id), {})
			_list.add_child(_row(i, def, int(def.get("price", 0)) / 2, int(e.amount)))
	else:
		for i in _catalog.size():
			var def: Dictionary = item_db.get(str(_catalog[i]), {})
			_list.add_child(_row(i, def, int(def.get("price", 0)), -1))
	_zeny.text = InventoryWindow._fmt_zeny(_unit.zeny)
	_update_total()


func _row(index: int, def: Dictionary, price: int, owned: int) -> Control:
	var row := ShopRow.new()
	row.index = index
	row.def = def
	row.price = price
	row.owned = owned
	row.selected = index == _selected
	row.custom_minimum_size = Vector2(350, 34)
	row.picked.connect(func(i):
		_selected = i
		for c in _list.get_children():
			(c as ShopRow).selected = (c as ShopRow).index == i
			(c as ShopRow).queue_redraw()
		_qty.max_value = owned if owned > 0 else 99
		_qty.value = clampf(_qty.value, 1, _qty.max_value)
		_update_total())
	return row


func _update_total() -> void:
	if _total == null:
		return
	if _selected < 0:
		_total.text = "Select an item"
		_confirm.disabled = true
		_confirm.text = "SELL" if _selling else "BUY"
		return
	var def: Dictionary
	var unit_price: int
	if _selling:
		var e: Dictionary = _unit.inventory.entries[_selected] if _selected < _unit.inventory.entries.size() else {}
		def = item_db.get(str(e.get("id", 0)), {})
		unit_price = int(def.get("price", 0)) / 2
	else:
		def = item_db.get(str(_catalog[_selected]), {})
		unit_price = int(def.get("price", 0))
	var total := unit_price * int(_qty.value)
	_total.text = "%s %s z" % ["+" if _selling else "−", InventoryWindow._fmt_zeny(total)]
	_total.label_settings.font_color = UiTheme.HP_HIGH if _selling else (UiTheme.HP_LOW if total > _unit.zeny else UiTheme.TEXT)
	_confirm.text = "SELL" if _selling else "BUY"
	_confirm.disabled = (not _selling and total > _unit.zeny) or def.is_empty()


func _on_confirm() -> void:
	if _selected < 0:
		return
	if _selling:
		sell_requested.emit(_selected, int(_qty.value))
		_selected = -1
	else:
		buy_requested.emit(int(_catalog[_selected]), int(_qty.value))
	refresh()


class ShopRow extends Control:
	signal picked(index: int)
	var index := 0
	var def: Dictionary = {}
	var price := 0
	var owned := -1
	var selected := false
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(index)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(UiTheme.ACCENT, 0.14) if selected else Color(0.02, 0.05, 0.09, 0.45))
		draw_rect(r.grow(-0.5), Color(UiTheme.ACCENT, 0.75 if selected else (0.4 if _hover else 0.12)), false, 1.0)
		var icon := ItemIcons.icon(def)
		if icon:
			draw_texture_rect(icon, Rect2(Vector2(6, 5), Vector2(24, 24)), false)
		draw_string(UiTheme.font(600), Vector2(40, size.y / 2 + 5), String(def.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
		if owned > 0:
			draw_string(UiTheme.font(400), Vector2(190, size.y / 2 + 4), "×%d" % owned, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
		var p := "%s z" % InventoryWindow._fmt_zeny(price)
		var w := UiTheme.font(600).get_string_size(p, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(UiTheme.font(600), Vector2(size.x - w - 10, size.y / 2 + 5), p, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.CRIT)
