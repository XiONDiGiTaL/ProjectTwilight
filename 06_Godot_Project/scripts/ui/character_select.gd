extends Control
## Character select and creation in the Twilight Glass style.
##   left   - character slots
##   centre - live rotating preview of the selected / new character
##   right  - details with PLAY / DELETE, or the creation form
## Characters are local saves (SaveGame slots); the chosen slot is handed to
## the field through the GameSession autoload.

const FIELD_SCENE := "res://scenes/game/field.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const DESIGN_WIDTH := 1280.0

## Horizontal offset that centres the designed 1280-pixel composition on a
## wider viewport. At 1280 it is zero; 21:9 and wider keep equal side margins.
static func layout_shift(viewport_width: float) -> float:
	return maxf(0.0, (viewport_width - DESIGN_WIDTH) * 0.5)

var _item_db: Dictionary = {}
var _slots: Array = []
var _selected := 0
var _creating := false

var _slot_list: VBoxContainer
var _preview: CharacterPreview
var _detail_panel: GlassPanel
var _detail_box: VBoxContainer
var _create_box: VBoxContainer
var _name_edit: LineEdit
var _male := true
var _hair_style := 2
var _hair_color := 0
var _sex_buttons: Array[Button] = []
var _style_label: Label
var _aura_row: HFlowContainer
var _hair_label: Label
var _cloth_label: Label
var _cloth := 0
const MAX_HAIR_PALETTES := 132
const MAX_CLOTH_PALETTES := 700
var _aura := "class"
var _hexagon: StatHexagon
var _error: Label
var _confirm_layer: Control
var _layout_controls: Array[Control] = []
var _layout_shift := 0.0
var _confirm_focus_return: Control


func _ready() -> void:
	var res := get_node("/root/RoResources")
	if not res.is_mounted:
		res.mount()
	_item_db = FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	_item_db.erase("_provenance")
	var backdrop := MenuBackdrop.new()
	add_child(backdrop)

	var title := UiTheme.label("SELECT  CHARACTER", 22, UiTheme.TEXT, 300, 8, true)
	title.position = Vector2(40, 30)
	add_child(title)
	_layout_controls.append(title)
	var sub := UiTheme.label("PROJECT TWILIGHT  ·  OFFLINE", 11, UiTheme.ACCENT, 600, 4)
	sub.position = Vector2(42, 64)
	add_child(sub)
	_layout_controls.append(sub)

	var left := GlassPanel.new()
	left.position = Vector2(40, 100)
	left.custom_minimum_size = Vector2(330, 0)
	add_child(left)
	_layout_controls.append(left)
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 6)
	left.add_child(_slot_list)

	_preview = CharacterPreview.new()
	_preview.position = Vector2(440, 150)
	_preview.size = Vector2(300, 380)
	add_child(_preview)
	_layout_controls.append(_preview)
	var platform := _Platform.new()
	platform.position = Vector2(440, 470)
	platform.size = Vector2(300, 70)
	add_child(platform)
	_layout_controls.append(platform)
	move_child(platform, get_child_count() - 2)

	_detail_panel = GlassPanel.new()
	_detail_panel.position = Vector2(800, 100)
	_detail_panel.custom_minimum_size = Vector2(440, 0)
	add_child(_detail_panel)
	_layout_controls.append(_detail_panel)
	var stack := VBoxContainer.new()
	_detail_panel.add_child(stack)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	stack.add_child(_detail_box)
	_create_box = VBoxContainer.new()
	_create_box.add_theme_constant_override("separation", 6)
	stack.add_child(_create_box)
	_build_create_form()

	var back := Button.new()
	back.text = "BACK"
	UiTheme.style_button(back)
	back.position = Vector2(40, 650)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	add_child(back)
	_layout_controls.append(back)
	resized.connect(_layout_columns)
	_layout_columns.call_deferred()
	_reload_slots()
	var audio := get_node_or_null("/root/GameAudio")
	if audio:
		audio.play_menu_music()


# --- Slots ------------------------------------------------------------------------

func _layout_columns(viewport_width := -1.0) -> void:
	var width := viewport_width if viewport_width >= 0.0 else get_viewport_rect().size.x
	var shift := layout_shift(width)
	if is_equal_approx(shift, _layout_shift):
		return
	var delta := shift - _layout_shift
	for control in _layout_controls:
		if is_instance_valid(control):
			control.position.x += delta
	_layout_shift = shift


func _reload_slots() -> void:
	_slots = SaveGame.list_slots(CharacterRules.MAX_SLOTS, _item_db, ClassInsignia.classes())
	for c in _slot_list.get_children():
		_slot_list.remove_child(c)
		c.queue_free()
	_slot_list.add_child(UiTheme.label("CHARACTERS", 11, UiTheme.ACCENT, 600, 4))
	for i in _slots.size():
		var row := _SlotRow.new()
		row.entry = _slots[i]
		row.selected = i == _selected
		row.custom_minimum_size = Vector2(300, 58)
		row.picked.connect(_select.bind(i))
		_slot_list.add_child(row)
	_select(_selected)


func _select(i: int) -> void:
	_selected = i
	for c in _slot_list.get_children():
		if c is _SlotRow:
			c.selected = c.entry == _slots[i]
			c.queue_redraw()
	var entry: Dictionary = _slots[i]
	if entry.ok:
		_show_details(entry)
	elif entry.error != "":
		_show_message("This save could not be read:\n%s" % entry.error)
	else:
		_start_create()


func _show_details(entry: Dictionary) -> void:
	_creating = false
	_create_box.visible = false
	_detail_box.visible = true
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var ch: Dictionary = entry.character
	_preview.walking = false
	var cj := String(ch.get("job", "novice"))
	_preview.set_look(bool(ch.male), int(ch.hair_style), int(ch.hair_color), String(PlayerSprites.jobs().get(cj, {}).get("sprite", "초보자")), int(ch.get("cloth_color", 0)), cj)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_detail_box.add_child(header)
	var ins := ClassInsignia.new()
	ins.custom_minimum_size = Vector2(54, 54)
	header.add_child(ins)
	ins.set_class(String(ch.job))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	header.add_child(names)
	names.add_child(UiTheme.label(String(ch.name), 24, UiTheme.TEXT, 600, 1))
	var job_name := String(ClassInsignia.classes().get(String(ch.job), {}).get("name", "Novice"))
	names.add_child(UiTheme.label("%s   ·   BASE LV %d   ·   JOB LV %d" % [job_name.to_upper(), ch.level, ch.job_level], 11, UiTheme.TEXT_DIM, 600, 2))
	_detail_box.add_child(_divider())
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	_detail_box.add_child(grid)
	for k in ["str", "agi", "vit", "int", "dex", "luk"]:
		grid.add_child(UiTheme.label(k.to_upper(), 11, UiTheme.ACCENT, 600, 2))
		grid.add_child(UiTheme.label(str(ch.stats[k]), 14, UiTheme.TEXT, 600))
	var loc := UiTheme.label("LOCATION   %s  (%d, %d)      ZENY   %s" % [String(ch.map).to_upper(), ch.cell.x, ch.cell.y,
		InventoryWindow._fmt_zeny(int(ch.zeny))], 11, UiTheme.TEXT_DIM, 600, 2)
	_detail_box.add_child(loc)
	_detail_box.add_child(_divider())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_detail_box.add_child(buttons)
	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(180, 38)
	UiTheme.style_button(play, true, false, 15)
	play.pressed.connect(_play.bind(String(entry.slot)))
	buttons.add_child(play)
	var del := Button.new()
	del.text = "DELETE"
	UiTheme.style_button(del, false, true)
	del.focus_mode = Control.FOCUS_ALL
	del.add_theme_stylebox_override("focus", _focus_ring(UiTheme.HP_LOW))
	del.pressed.connect(_confirm_delete.bind(entry))
	buttons.add_child(del)
	_build_coop_rows(String(entry.slot))


func _show_message(text: String) -> void:
	_create_box.visible = false
	_detail_box.visible = true
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var l := UiTheme.label(text, 13, UiTheme.HP_MID, 400)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	_detail_box.add_child(l)


func _play(slot: String) -> void:
	get_node("/root/NetSession").leave()
	get_node("/root/GameSession").slot = slot
	get_tree().change_scene_to_file(FIELD_SCENE)


# --- Private co-op ------------------------------------------------------------------

var _coop_status: Label
var _joining := false


## HOST opens a session with this character; JOIN enters a friend's session
## with it, using the invitation code they sent.
func _build_coop_rows(slot: String) -> void:
	_detail_box.add_child(_divider())
	_detail_box.add_child(UiTheme.label("PRIVATE CO-OP", 11, UiTheme.ACCENT, 600, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail_box.add_child(row)
	var host := Button.new()
	host.text = "HOST CO-OP"
	host.tooltip_text = "Play this character and let friends join with an invitation code."
	UiTheme.style_button(host, false, false, 12)
	host.pressed.connect(_host.bind(slot))
	row.add_child(host)
	var code := LineEdit.new()
	code.placeholder_text = "Invitation code"
	code.custom_minimum_size = Vector2(190, 0)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_line_edit(code)
	code.add_theme_font_size_override("font_size", 12)
	row.add_child(code)
	var join := Button.new()
	join.text = "JOIN"
	UiTheme.style_button(join, false, false, 12)
	join.pressed.connect(func(): _join(slot, code.text))
	code.text_submitted.connect(func(t): _join(slot, t))
	row.add_child(join)
	_coop_status = UiTheme.label("", 11, UiTheme.TEXT_DIM, 400, 1)
	_coop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coop_status.custom_minimum_size = Vector2(400, 0)
	_detail_box.add_child(_coop_status)


func _coop_say(text: String, bad := false) -> void:
	if is_instance_valid(_coop_status):
		_coop_status.text = text
		_coop_status.add_theme_color_override("font_color", UiTheme.HP_MID if bad else UiTheme.TEXT_DIM)


func _host(slot: String) -> void:
	var ns := get_node("/root/NetSession")
	var settings := get_node("/root/Settings")
	var port := int(settings.get_value("coop", "port", ns.DEFAULT_PORT))
	var code: String = ns.host(port, String(settings.get_value("coop", "advertised_ip", "")))
	if code == "":
		_coop_say(String(ns.last_error), true)
		return
	get_node("/root/GameSession").slot = slot
	get_tree().change_scene_to_file(FIELD_SCENE)


func _join(slot: String, code: String) -> void:
	if _joining:
		return
	var ns := get_node("/root/NetSession")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path_for(slot)))
	if not (parsed is Dictionary):
		_coop_say("This character's save could not be read.", true)
		return
	if code.strip_edges() == "":
		_coop_say("Paste the invitation code the host sent you.", true)
		return
	if not ns.join(code.strip_edges(), parsed):
		_coop_say(String(ns.last_error), true)
		return
	_joining = true
	_coop_say("Connecting to the host…")
	if not ns.session_failed.is_connected(_on_join_failed):
		ns.session_failed.connect(_on_join_failed)
		ns.session_ended.connect(_on_join_failed)
		ns.map_entered.connect(_on_joined.bind(slot))
	# A host that never answers (wrong address, closed port) must not hang the menu.
	await get_tree().create_timer(12.0).timeout
	if _joining and is_inside_tree():
		ns.leave()
		_on_join_failed("The host did not answer. Check the code, and that the host's port is reachable.")


func _on_join_failed(message: String) -> void:
	_joining = false
	_coop_say(message, true)


func _on_joined(_map: String, slot: String) -> void:
	if not _joining:
		return
	_joining = false
	get_node("/root/GameSession").slot = slot
	get_tree().change_scene_to_file(FIELD_SCENE)


# --- Creation -----------------------------------------------------------------------

func _build_create_form() -> void:
	_create_box.add_child(UiTheme.label("NEW  CHARACTER", 18, UiTheme.TEXT, 300, 6, true))
	_create_box.add_child(_divider())
	_create_box.add_child(UiTheme.label("NAME", 11, UiTheme.ACCENT, 600, 3))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "4 – 23 letters or numbers"
	_name_edit.max_length = CharacterRules.NAME_MAX
	UiTheme.style_line_edit(_name_edit)
	_name_edit.text_changed.connect(func(_t): _error.text = "")
	_create_box.add_child(_name_edit)

	var look := HBoxContainer.new()
	look.add_theme_constant_override("separation", 14)
	_create_box.add_child(look)
	var sex_col := VBoxContainer.new()
	look.add_child(sex_col)
	sex_col.add_child(UiTheme.label("SEX", 11, UiTheme.ACCENT, 600, 3))
	var sex_row := HBoxContainer.new()
	sex_col.add_child(sex_row)
	for m in [true, false]:
		var b := Button.new()
		b.text = "MALE" if m else "FEMALE"
		b.toggle_mode = true
		UiTheme.style_button(b, false, false, 12)
		b.pressed.connect(func(): _male = m; _refresh_look())
		sex_row.add_child(b)
		_sex_buttons.append(b)
	var style_col := VBoxContainer.new()
	look.add_child(style_col)
	style_col.add_child(UiTheme.label("HAIR STYLE", 11, UiTheme.ACCENT, 600, 3))
	var style_row := HBoxContainer.new()
	style_col.add_child(style_row)
	var prev := Button.new()
	prev.text = "◀"
	UiTheme.style_button(prev, false, false, 12)
	prev.pressed.connect(_step_style.bind(-1))
	style_row.add_child(prev)
	_style_label = UiTheme.label("", 15, UiTheme.TEXT, 600)
	_style_label.custom_minimum_size = Vector2(44, 0)
	_style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	style_row.add_child(_style_label)
	var nxt := Button.new()
	nxt.text = "▶"
	UiTheme.style_button(nxt, false, false, 12)
	nxt.pressed.connect(_step_style.bind(1))
	style_row.add_child(nxt)

	# Hair colour and cloth dye steppers: palettes come from the client and
	# the resource pack (2025 Palettes: up to 132 hair / 700 cloth palettes).
	var dye_row := HBoxContainer.new()
	dye_row.add_theme_constant_override("separation", 18)
	_create_box.add_child(dye_row)
	_hair_label = _stepper(dye_row, "HAIR COLOUR", _step_hair)
	_cloth_label = _stepper(dye_row, "CLOTH DYE", _step_cloth)

	_create_box.add_child(UiTheme.label("AURA", 11, UiTheme.ACCENT, 600, 3))
	_aura_row = HFlowContainer.new()
	_aura_row.add_theme_constant_override("h_separation", 6)
	_aura_row.add_theme_constant_override("v_separation", 6)
	_create_box.add_child(_aura_row)
	for id in PlayerAura.ORDER:
		var b := Button.new()
		b.text = String(PlayerAura.STYLES[id].name).to_upper()
		b.toggle_mode = true
		b.tooltip_text = "Cosmetic aura (change it in the field with U)."
		UiTheme.style_button(b, false, false, 11)
		var cols := PlayerAura.colors_for(id, "novice")
		if id != "none":
			b.add_theme_color_override("font_color", (cols[1] as Color).lightened(0.35))
		b.pressed.connect(func(): _aura = id; _refresh_look())
		_aura_row.add_child(b)

	var stats_row := HBoxContainer.new()
	_create_box.add_child(stats_row)
	_hexagon = StatHexagon.new()
	stats_row.add_child(_hexagon)
	_hexagon.custom_minimum_size = Vector2(250, 196)   # after _ready, which sets its default
	var help := UiTheme.label("Click a stat to raise it.\nIts opposite lowers, keeping\neach pair at 10 (classic\nPre-Renewal creation).\n\nAll 48 starting points are\nspent by the hexagon.", 11, UiTheme.TEXT_DIM, 400)
	help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_row.add_child(help)

	_error = UiTheme.label("", 12, UiTheme.HP_LOW, 600)
	_create_box.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_create_box.add_child(buttons)
	var create := Button.new()
	create.text = "CREATE"
	create.custom_minimum_size = Vector2(180, 38)
	UiTheme.style_button(create, true, false, 15)
	create.pressed.connect(_create)
	buttons.add_child(create)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	UiTheme.style_button(cancel)
	cancel.pressed.connect(func(): _select(_first_used_slot()))
	buttons.add_child(cancel)
	_create_box.visible = false


func _start_create() -> void:
	_creating = true
	_detail_box.visible = false
	_create_box.visible = true
	_name_edit.text = ""
	_error.text = ""
	_hexagon.set_stats(CharacterRules.stats_from_pairs(5, 5, 5))
	_preview.walking = false
	_refresh_look()
	_name_edit.grab_focus.call_deferred()


func _stepper(parent: Control, caption: String, step: Callable) -> Label:
	var col := VBoxContainer.new()
	parent.add_child(col)
	col.add_child(UiTheme.label(caption, 11, UiTheme.ACCENT, 600, 3))
	var row := HBoxContainer.new()
	col.add_child(row)
	var prev := Button.new()
	prev.text = "◀"
	UiTheme.style_button(prev, false, false, 12)
	prev.pressed.connect(step.bind(-1))
	row.add_child(prev)
	var l := UiTheme.label("", 14, UiTheme.TEXT, 600)
	l.custom_minimum_size = Vector2(78, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var nxt := Button.new()
	nxt.text = "▶"
	UiTheme.style_button(nxt, false, false, 12)
	nxt.pressed.connect(step.bind(1))
	row.add_child(nxt)
	return l


## Steps to the next hair palette that exists for the current style (0 = default).
func _step_hair(step: int) -> void:
	var res := get_node_or_null("/root/RoResources")
	var sex := "남" if _male else "여"
	for i in MAX_HAIR_PALETTES:
		_hair_color = wrapi(_hair_color + step, 0, MAX_HAIR_PALETTES)
		if _hair_color == 0 or res == null or res.exists("data/palette/머리/머리%d_%s_%d.pal" % [_hair_style, sex, _hair_color]):
			break
	_refresh_look()


## Steps to the next cloth dye palette for the Novice body (0 = default).
func _step_cloth(step: int) -> void:
	var res := get_node_or_null("/root/RoResources")
	var sex := "남" if _male else "여"
	for i in MAX_CLOTH_PALETTES:
		_cloth = wrapi(_cloth + step, 0, MAX_CLOTH_PALETTES)
		if _cloth == 0 or res == null or res.exists("data/palette/몸/초보자_%s_%d.pal" % [sex, _cloth]):
			break
	_refresh_look()


func _step_style(step: int) -> void:
	for i in CharacterRules.HAIR_STYLES:
		_hair_style = wrapi(_hair_style + step, 1, CharacterRules.HAIR_STYLES + 1)
		if CharacterPreview.has_style(_male, _hair_style):
			break
	_refresh_look()


func _refresh_look() -> void:
	if not CharacterPreview.has_style(_male, _hair_style):
		_hair_style = 1
	_sex_buttons[0].button_pressed = _male
	_sex_buttons[1].button_pressed = not _male
	_style_label.text = str(_hair_style)
	_hair_label.text = str(_hair_color) if _hair_color > 0 else "DEFAULT"
	_cloth_label.text = str(_cloth) if _cloth > 0 else "DEFAULT"
	for i in _aura_row.get_child_count():
		(_aura_row.get_child(i) as Button).button_pressed = PlayerAura.ORDER[i] == _aura
	_preview.set_look(_male, _hair_style, _hair_color, "초보자", _cloth)


func _create() -> void:
	var names := []
	for s in _slots:
		if s.ok:
			names.append(s.character.name)
	var name := _name_edit.text
	var err := CharacterRules.validate_name(name, names)
	if err != "":
		_error.text = err
		return
	if not CharacterRules.valid_hexagon(_hexagon.stats):
		_error.text = "Invalid stat distribution."
		return
	var slot := String(_slots[_selected].slot) if not _slots[_selected].ok else _first_free_slot()
	if slot == "":
		_error.text = "All %d character slots are in use." % CharacterRules.MAX_SLOTS
		return
	var ch := CharacterRules.new_character(name, _male, _hair_style, _hair_color, _hexagon.stats)
	ch.cell = [ch.cell.x, ch.cell.y]
	ch.aura = _aura
	ch.cloth_color = _cloth
	var data := {"format": SaveGame.FORMAT, "version": SaveGame.VERSION,
		"saved_at": int(Time.get_unix_time_from_system()), "character": ch}
	var werr := SaveGame.write(slot, data)
	if werr != OK:
		_error.text = "Could not save the character (%s)." % error_string(werr)
		return
	_selected = int(slot.trim_prefix("slot")) - 1
	_reload_slots()


func _first_free_slot() -> String:
	for s in _slots:
		if not s.ok and s.error == "":
			return s.slot
	return ""


func _first_used_slot() -> int:
	for i in _slots.size():
		if _slots[i].ok:
			return i
	return 0


# --- Delete confirmation ------------------------------------------------------------

## Escape cancels the confirmation without deleting. The dialog's safe default
## focus is KEEP, so pressing Enter immediately cannot destroy a character.
func _unhandled_input(event: InputEvent) -> void:
	if _confirm_layer == null:
		return
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)
	if not cancel:
		return
	_close_confirm_delete()
	get_viewport().set_input_as_handled()


func _close_confirm_delete(restore_focus := true) -> void:
	var layer := _confirm_layer
	_confirm_layer = null
	if is_instance_valid(layer):
		layer.queue_free()
	if restore_focus and is_instance_valid(_confirm_focus_return):
		_confirm_focus_return.grab_focus.call_deferred()
	_confirm_focus_return = null


func _confirm_delete(entry: Dictionary) -> void:
	if _confirm_layer != null:
		return
	_confirm_focus_return = get_viewport().gui_get_focus_owner()
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var panel := GlassPanel.new()
	panel.padding = Vector4(26, 18, 26, 20)
	_confirm_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiTheme.label("◆  DELETE CHARACTER", 12, UiTheme.HP_LOW, 600, 4))
	var msg := UiTheme.label("Permanently delete %s (Lv %d)?\nThis removes the save file and cannot be undone." % [
		entry.character.name, entry.character.level], 14, UiTheme.TEXT, 400)
	col.add_child(msg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var yes := Button.new()
	yes.text = "DELETE"
	UiTheme.style_button(yes, true, true)
	yes.focus_mode = Control.FOCUS_ALL
	yes.add_theme_stylebox_override("focus", _focus_ring(UiTheme.HP_LOW))
	yes.pressed.connect(func():
		if _confirm_layer == null:
			return
		SaveGame.delete(String(entry.slot))
		_close_confirm_delete(false)
		_reload_slots())
	row.add_child(yes)
	var no := Button.new()
	no.text = "KEEP"
	UiTheme.style_button(no)
	no.focus_mode = Control.FOCUS_ALL
	no.add_theme_stylebox_override("focus", _focus_ring(UiTheme.ACCENT))
	no.pressed.connect(_close_confirm_delete)
	row.add_child(no)
	no.grab_focus.call_deferred()
	await get_tree().process_frame
	panel.position = (get_viewport_rect().size - panel.size) / 2.0


func _focus_ring(accent: Color) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = accent
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(3)
	return ring


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color = Color(UiTheme.ACCENT, 0.22)
	return d


## One character slot row.
class _SlotRow extends Control:
	signal picked
	var entry: Dictionary = {}
	var selected := false
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(UiTheme.ACCENT, 0.14) if selected else Color(0.02, 0.05, 0.09, 0.4))
		draw_rect(r.grow(-0.5), Color(UiTheme.ACCENT, 0.8 if selected else (0.4 if _hover else 0.14)), false, 1.0)
		if selected:
			draw_rect(Rect2(0, 0, 3, size.y), UiTheme.ACCENT)
		var ch: Dictionary = entry.get("character", {})
		if entry.get("ok", false):
			draw_string(UiTheme.font(600, 1), Vector2(16, 24), String(ch.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.TEXT)
			var job := String(ClassInsignia.classes().get(String(ch.job), {}).get("name", "Novice")).to_upper()
			draw_string(UiTheme.font(600, 2), Vector2(16, 44), "%s  ·  LV %d  ·  %s" % [job, ch.level, String(ch.map).to_upper()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT_DIM)
		elif String(entry.get("error", "")) != "":
			draw_string(UiTheme.font(600, 2), Vector2(16, 34), "DAMAGED SAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.HP_MID)
		else:
			draw_string(UiTheme.font(600, 3), Vector2(16, 34), "+   CREATE NEW CHARACTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(UiTheme.ACCENT, 0.9 if _hover or selected else 0.55))


## Glowing ring the preview character stands on.
class _Platform extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var t := Time.get_ticks_msec() / 1000.0
		for k in 3:
			var rx := size.x * (0.26 + k * 0.08)
			var pts := PackedVector2Array()
			for i in 65:
				var a := TAU * i / 64.0
				pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.22))
			draw_polyline(pts, Color(UiTheme.ACCENT, (0.55 - k * 0.15) * (0.75 + 0.25 * sin(t * 2.0 + k))), 1.5, true)
