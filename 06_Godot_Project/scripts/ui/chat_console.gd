class_name ChatConsole
extends Control
## Bottom-left chat line. Enter opens it; the field runs @commands through the
## simulation and echoes plain text as local speech. Up / Down recall history,
## Escape closes without sending.

signal submitted(text: String)

const MAX_HISTORY := 20

var input: LineEdit
var _history: Array = []
var _index := 0
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := GlassPanel.new()
	panel.chamfer = 8.0
	panel.sweep = false
	panel.padding = Vector4(10, 6, 10, 7)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	_hint = UiTheme.label("CHAT", 9, UiTheme.ACCENT, 600, 2)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_hint)
	input = LineEdit.new()
	input.placeholder_text = "Say something   ·   /g <message> guild chat   ·   @help"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(360, 26)
	UiTheme.style_line_edit(input)
	input.add_theme_font_size_override("font_size", 13)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input)
	row.add_child(input)
	visible = false


func open(prefill := "") -> void:
	visible = true
	_hint.text = "COMMAND"
	input.text = prefill
	input.grab_focus()
	input.caret_column = input.text.length()


func close() -> void:
	visible = false
	input.release_focus()
	_hint.text = "CHAT"


func is_open() -> bool:
	return visible


func _on_submit(text: String) -> void:
	var clean := text.strip_edges()
	if clean != "":
		_history.append(clean)
		if _history.size() > MAX_HISTORY:
			_history.remove_at(0)
	_index = _history.size()
	submitted.emit(clean)
	close()


func _on_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_ESCAPE:
			close()
			accept_event()
		KEY_UP:
			_recall(-1)
			accept_event()
		KEY_DOWN:
			_recall(1)
			accept_event()


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_index = clampi(_index + step, 0, _history.size())
	input.text = "" if _index == _history.size() else String(_history[_index])
	input.caret_column = input.text.length()
