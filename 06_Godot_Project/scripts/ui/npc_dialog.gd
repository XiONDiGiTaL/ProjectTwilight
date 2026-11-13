class_name NpcDialog
extends GlassPanel
## RO-style NPC dialogue in the glass style: speaker name, text and choice
## buttons along the bottom. show_page() replaces the content; the chosen
## index is emitted (or -1 when closed).

signal chosen(index: int)

var _name: Label
var _text: Label
var _choices: HBoxContainer
var _preview: CharacterPreview


func _ready() -> void:
	chamfer = 14.0
	padding = Vector4(22, 14, 22, 16)
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_name = UiTheme.label("", 13, UiTheme.ACCENT, 600, 4)
	col.add_child(_name)
	_preview = CharacterPreview.new()
	_preview.custom_minimum_size = Vector2(150, 190)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.visible = false
	col.add_child(_preview)
	_text = UiTheme.label("", 15, UiTheme.TEXT, 400)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 60)
	col.add_child(_text)
	_choices = HBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	col.add_child(_choices)
	visible = false


## Shows a page of dialogue. choices: Array of button labels. Short choice
## lists sit in a row; long ones (menus, warper lists) become a scrolling
## column. cancellable adds a CANCEL button that emits -1. look optionally
## shows a live target-job body above the text (used by job confirmations).
func show_page(speaker: String, text: String, choices: Array, cancellable := false, look: Dictionary = {}) -> void:
	_name.text = speaker.to_upper()
	_text.text = text
	_text.visible = text != ""
	_show_preview(look)
	_clear_choices()
	var vertical := choices.size() > 4
	var holder: Container
	if vertical:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(560, mini(choices.size(), 8) * 34)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		_choices.add_child(scroll)
		holder = list
	else:
		holder = _choices
	for i in choices.size():
		var label := String(choices[i]).strip_edges().trim_prefix("~").strip_edges()   # rAthena " ~ " bullets
		var b := Button.new()
		b.text = label.to_upper() if label != "" else "—"
		b.visible = label != ""           # empty rAthena options are hidden but keep their index
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT if vertical else HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_button(b, i == 0 and not vertical, false, 12)
		b.pressed.connect(func(): chosen.emit(i))
		holder.add_child(b)
	if cancellable:
		var c := Button.new()
		c.text = "CANCEL"
		UiTheme.style_button(c, false, false, 12)
		c.pressed.connect(func(): chosen.emit(-1))
		_choices.add_child(c)
	_show()


signal number_entered(value: int)


## Numeric input (rAthena "input"): a spin box plus OK.
func ask_number(speaker: String, text: String, lo: int, hi: int) -> void:
	_name.text = speaker.to_upper()
	_text.text = text
	_text.visible = text != ""
	_show_preview({})
	_clear_choices()
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.value = lo
	spin.custom_minimum_size = Vector2(140, 0)
	_choices.add_child(spin)
	var ok := Button.new()
	ok.text = "OK"
	UiTheme.style_button(ok, true, false, 12)
	ok.pressed.connect(func(): number_entered.emit(int(spin.value)))
	_choices.add_child(ok)
	_show()


## Shows the target job's body above the page; an empty look hides it.
func _show_preview(look: Dictionary) -> void:
	if _preview == null:
		return
	_preview.visible = not look.is_empty()
	if _preview.visible:
		_preview.set_look(bool(look.get("male", true)), int(look.get("hair_style", 0)),
			int(look.get("hair_color", 0)), String(look.get("job_sprite", "초보자")),
			int(look.get("cloth", 0)), String(look.get("job", "")))


func _clear_choices() -> void:
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()


func _show() -> void:
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	# The confirmation preview makes the page taller; keep it above the chat
	# window so the target body and the decision text are both readable.
	var bottom_margin := 250.0 if _preview != null and _preview.visible else 96.0
	position = Vector2(roundf((vp.x - size.x) / 2.0), vp.y - size.y - bottom_margin)


func close() -> void:
	visible = false
