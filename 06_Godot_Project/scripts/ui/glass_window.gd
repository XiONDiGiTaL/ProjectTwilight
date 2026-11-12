class_name GlassWindow
extends GlassPanel
## Draggable glass window with a title bar and close button. Subclasses add
## their content to `body`. Position is remembered per window in settings.
## Drag capture continues while the pointer leaves the title bar, so windows
## can be repositioned like the classic client instead of snapping back.

signal closed

const TITLE_HEIGHT := 30.0
const CLOSE_SIZE := Vector2(26, 24)

var title := "WINDOW"
var body: VBoxContainer
var window_id := ""
var title_label: Label

var _dragging := false
var _drag_offset := Vector2.ZERO
var _title_bar: HBoxContainer
var _drag_grip: Label


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.name = "Frame"
	col.add_theme_constant_override("separation", 9)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title_bar = HBoxContainer.new()
	_title_bar.name = "TitleBar"
	_title_bar.custom_minimum_size = Vector2(0, TITLE_HEIGHT)
	_title_bar.add_theme_constant_override("separation", 5)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.tooltip_text = "Drag to move this window"
	_title_bar.gui_input.connect(_on_title_input)
	col.add_child(_title_bar)
	# A quiet grip makes the draggable surface obvious without adding chrome.
	_drag_grip = UiTheme.label("⋮⋮", 10, Color(UiTheme.ACCENT, 0.62), 600, 1)
	_drag_grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_grip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_drag_grip.tooltip_text = "Drag to move"
	_title_bar.add_child(_drag_grip)
	title_label = UiTheme.label("◆  " + title, 13, UiTheme.TEXT, 600, 3)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_bar.add_child(title_label)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.custom_minimum_size = CLOSE_SIZE
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_override("font", UiTheme.font(600))
	close.add_theme_font_size_override("font_size", 11)
	close.add_theme_color_override("font_color", UiTheme.TEXT)
	close.add_theme_color_override("font_hover_color", Color.WHITE)
	close.tooltip_text = "Close"
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.8, 0.2, 0.25, 0.85) if state != "normal" else Color(1, 1, 1, 0.08)
		sb.border_color = Color(1, 1, 1, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		close.add_theme_stylebox_override(state, sb)
	close.pressed.connect(func(): toggle(false))
	_title_bar.add_child(close)
	# Gradient title band sized to the title row (drawn by the glass shader).
	_title_bar.resized.connect(func(): set_header(_title_bar.position.y + _title_bar.size.y + 5.0))
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	_restore_position()


## Updates the heading without losing the diamond marker.
func set_title(text: String) -> void:
	title = text
	if title_label != null:
		title_label.text = "◆  " + text


func toggle(show: Variant = null) -> void:
	visible = (not visible) if show == null else bool(show)
	if visible:
		_clamp_to_screen.call_deferred()
		move_to_front()
	else:
		_dragging = false
		closed.emit()


func start_drag(at: Vector2) -> void:
	if not visible:
		return
	_dragging = true
	_drag_offset = at - global_position
	move_to_front()


func drag_to(at: Vector2) -> void:
	if not _dragging:
		return
	global_position = at - _drag_offset
	_clamp_to_screen()


func end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_clamp_to_screen()
	_save_position()


func _on_title_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			start_drag(get_global_mouse_position())
		else:
			end_drag()
		_title_bar.accept_event()
	elif e is InputEventMouseMotion and _dragging:
		drag_to(get_global_mouse_position())
		_title_bar.accept_event()


## Keep receiving motion/release after the pointer leaves the title bar.
func _input(e: InputEvent) -> void:
	if not _dragging:
		return
	if e is InputEventMouseMotion:
		drag_to(get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		end_drag()
		get_viewport().set_input_as_handled()


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
