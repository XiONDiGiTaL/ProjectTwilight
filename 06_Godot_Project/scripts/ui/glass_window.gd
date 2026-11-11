class_name GlassWindow
extends GlassPanel
## Draggable glass window with a title bar and close button. Subclasses add
## their content to `body`. Position is remembered per window in settings.

signal closed

var title := "WINDOW"
var body: VBoxContainer
var window_id := ""

var _dragging := false
var _drag_offset := Vector2.ZERO
var _title_bar: HBoxContainer


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title_bar = HBoxContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_input)
	col.add_child(_title_bar)
	var t := UiTheme.label(title, 13, UiTheme.TEXT, 600, 4)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_bar.add_child(t)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_override("font", UiTheme.font(400))
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	close.add_theme_color_override("font_hover_color", UiTheme.HP_LOW)
	close.pressed.connect(func(): toggle(false))
	_title_bar.add_child(close)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(UiTheme.ACCENT, 0.22)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	_restore_position()


func toggle(show: Variant = null) -> void:
	visible = (not visible) if show == null else bool(show)
	if visible:
		_clamp_to_screen.call_deferred()
		move_to_front()
	else:
		closed.emit()


func _on_title_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
		_drag_offset = get_global_mouse_position() - global_position
		if e.pressed:
			move_to_front()
		else:
			_save_position()
	elif e is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_screen()


func _clamp_to_screen() -> void:
	var vp := get_viewport_rect().size
	global_position = global_position.clamp(Vector2.ZERO, (vp - size).max(Vector2.ZERO))


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _save_position() -> void:
	var s := _settings()
	if s and window_id != "":
		s.set_value("ui_windows", window_id, position)


func _restore_position() -> void:
	var s := _settings()
	if s and window_id != "":
		var p: Variant = s.get_value("ui_windows", window_id, null)
		if p is Vector2:
			position = p
