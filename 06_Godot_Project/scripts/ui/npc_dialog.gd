class_name NpcDialog
extends GlassPanel
## RO-style NPC dialogue in the glass style: speaker name, text and choice
## buttons along the bottom. show_page() replaces the content; the chosen
## index is emitted (or -1 when closed).

signal chosen(index: int)

var _name: Label
var _text: Label
var _choices: HBoxContainer


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
	_text = UiTheme.label("", 15, UiTheme.TEXT, 400)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 60)
	col.add_child(_text)
	_choices = HBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	col.add_child(_choices)
	visible = false


## Shows a page of dialogue. choices: Array of button labels.
func show_page(speaker: String, text: String, choices: Array) -> void:
	_name.text = speaker.to_upper()
	_text.text = text
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	for i in choices.size():
		var b := Button.new()
		b.text = String(choices[i]).to_upper()
		UiTheme.style_button(b, i == 0, false, 12)
		b.pressed.connect(func(): chosen.emit(i))
		_choices.add_child(b)
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2(roundf((vp.x - size.x) / 2.0), vp.y - size.y - 96.0)


func close() -> void:
	visible = false
