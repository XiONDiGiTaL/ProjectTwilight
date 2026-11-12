class_name StorageWindow
extends GlassWindow
## Kafra storage: carried items on one tab, stored items on the other, with a
## quantity selector. Every move is requested from the simulation, which
## validates range, counts, capacity and carried weight.

signal deposit_requested(index: int, amount: int)
signal withdraw_requested(index: int, amount: int)
signal guild_deposit_requested(index: int, amount: int)
signal guild_withdraw_requested(index: int, amount: int)
signal storage_closed

var item_db: Dictionary = {}
var guild_mode := false
var guild: Inventory
var _unit: SimUnit
var _storing := false
var _selected := -1
var _list: VBoxContainer
var _qty: SpinBox
var _action: Button
var _tab_carry: Button
var _tab_store: Button
var _capacity: Label
var _hint: Label


func _init() -> void:
	super._init()
	title = "KAFRA STORAGE"
	window_id = "storage"


func _ready() -> void:
	super._ready()
	closed.connect(func(): storage_closed.emit())
	_capacity = UiTheme.label("", 10, Color(UiTheme.ACCENT, 0.85), 600, 2)
	body.add_child(_capacity)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	body.add_child(tabs)
	_tab_carry = _tab("CARRIED", false)
	_tab_store = _tab("STORAGE", true)
	tabs.add_child(_tab_carry)
	tabs.add_child(_tab_store)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 248)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_hint = UiTheme.label("Select an item to move.", 11, UiTheme.TEXT_DIM, 400)
	body.add_child(_hint)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	body.add_child(foot)
	foot.add_child(UiTheme.label("QTY", 10, Color(UiTheme.ACCENT, 0.85), 600, 2))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = 99
	_qty.value = 1
	_qty.custom_minimum_size = Vector2(80, 0)
	_qty.value_changed.connect(func(_v): _update_action())
	foot.add_child(_qty)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_action = Button.new()
	_action.text = "DEPOSIT"
	_action.custom_minimum_size = Vector2(110, 28)
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_override("font", UiTheme.font(600, 3))
	_action.add_theme_font_size_override("font_size", 12)
	_action.add_theme_color_override("font_color", UiTheme.TEXT)
	_action.add_theme_color_override("font_disabled_color", Color(UiTheme.TEXT_DIM, 0.4))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.ACCENT, 0.22)
	sb.border_color = Color(UiTheme.ACCENT, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_action.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(UiTheme.ACCENT, 0.4)
	_action.add_theme_stylebox_override("hover", sbh)
	var sbd := sb.duplicate() as StyleBoxFlat
	sbd.bg_color = Color(0, 0, 0, 0.15)
	sbd.border_color = Color(UiTheme.ACCENT, 0.2)
	_action.add_theme_stylebox_override("disabled", sbd)
	_action.pressed.connect(_on_action)
	foot.add_child(_action)
	visible = false


func _tab(text: String, store: bool) -> Button:
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
	b.pressed.connect(func(): _set_mode(store))
	return b


func open(npc_name: String, u: SimUnit, db: Dictionary) -> void:
	guild_mode = false
	guild = null
	_tab_store.text = "STORAGE"
	set_title("STORAGE  ·  " + npc_name.to_upper())
	_unit = u
	item_db = db
	_selected = -1
	_set_mode(false)
	toggle(true)
	refresh()


func open_guild(guild_name: String, u: SimUnit, bag: Inventory, db: Dictionary) -> void:
	guild_mode = true
	guild = bag
	_tab_store.text = "GUILD"
	set_title("GUILD STORAGE  ·  " + guild_name.to_upper())
	_unit = u
	item_db = db
	_selected = -1
	_set_mode(true)
	toggle(true)
	refresh()


func _set_mode(store: bool) -> void:
	_storing = store
	_tab_carry.button_pressed = not store
	_tab_store.button_pressed = store
	_selected = -1
	if _unit != null:
		refresh()


func _bag() -> Inventory:
	if not _storing:
		return _unit.inventory
	if guild_mode and guild != null:
		return guild
	return _unit.storage


func refresh() -> void:
	if _list == null or _unit == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var bag := _bag()
	for i in bag.entries.size():
		var e: Dictionary = bag.entries[i]
		var row := StorageRow.new()
		row.index = i
		row.def = item_db.get(str(e.id), {})
		row.amount = int(e.amount)
		row.selected = i == _selected
		row.custom_minimum_size = Vector2(360, 32)
		row.picked.connect(_select)
		_list.add_child(row)
	if guild_mode and guild != null:
		_capacity.text = "CARRIED  %d / %d        GUILD  %d / %d" % [
			_unit.inventory.entries.size(), _unit.inventory.max_entries,
			guild.entries.size(), guild.max_entries]
	else:
		_capacity.text = "CARRIED  %d / %d        STORAGE  %d / %d" % [
			_unit.inventory.entries.size(), _unit.inventory.max_entries,
			_unit.storage.entries.size(), _unit.storage.max_entries]
	_update_action()


func _select(index: int) -> void:
	_selected = index
	var bag := _bag()
	for c in _list.get_children():
		var row: StorageRow = c
		row.selected = row.index == index
		row.queue_redraw()
	if index >= 0 and index < bag.entries.size():
		var amount := int(bag.entries[index].amount)
		_qty.max_value = maxi(1, amount)
		_qty.value = clampf(_qty.value, 1, _qty.max_value)
		var def: Dictionary = item_db.get(str(int(bag.entries[index].id)), {})
		_hint.text = "%s  ×%d" % [String(def.get("name", "item")), amount]
	_update_action()


func _update_action() -> void:
	if _action == null:
		return
	_action.text = "WITHDRAW" if _storing else "DEPOSIT"
	_action.disabled = _selected < 0


func _on_action() -> void:
	if _selected < 0:
		return
	var amount := int(_qty.value)
	if guild_mode:
		if _storing:
			guild_withdraw_requested.emit(_selected, amount)
		else:
			guild_deposit_requested.emit(_selected, amount)
	elif _storing:
		withdraw_requested.emit(_selected, amount)
	else:
		deposit_requested.emit(_selected, amount)
	_selected = -1
	refresh()


class StorageRow extends Control:
	signal picked(index: int)
	var index := 0
	var def: Dictionary = {}
	var amount := 0
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
			draw_texture_rect(icon, Rect2(Vector2(6, 4), Vector2(24, 24)), false)
		draw_string(UiTheme.font(600), Vector2(40, size.y / 2 + 5), String(def.get("name", "?")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
		var txt := "×%d" % amount
		var w := UiTheme.font(600).get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(UiTheme.font(600), Vector2(size.x - w - 10, size.y / 2 + 5), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.CRIT)
