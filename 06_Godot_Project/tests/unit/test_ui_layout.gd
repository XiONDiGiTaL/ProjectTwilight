extends RefCounted
## UI layout contract: labels share a vertical centre, buttons share a usable
## height, and draggable windows keep a saved position instead of accepting a
## hardcoded default after they enter the tree.

const TEST_WINDOW := "__ui_layout_test"


func test_labels_are_vertically_centred(_t) -> Variant:
	var l := UiTheme.label("ALIGN", 12)
	if l.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
		return "UiTheme labels should centre vertically by default"
	return true


func test_buttons_have_a_consistent_height(_t) -> Variant:
	var b := Button.new()
	UiTheme.style_button(b)
	if b.custom_minimum_size.y < 28.0:
		return "styled buttons should be at least 28 px tall"
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null or sb.content_margin_top < 4.0:
		return "styled buttons should keep content away from the border"
	b.free()
	return true


func test_saved_position_wins_over_default(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	settings.set_value("ui_windows", TEST_WINDOW, Vector2(123, 45))
	var w := GlassWindow.new()
	w.window_id = TEST_WINDOW
	w.position = Vector2(10, 20)   # default assigned by CombatHud before add_child
	t.root.add_child(w)
	await t.process_frame
	var ok := w.position.is_equal_approx(Vector2(123, 45))
	w.queue_free()
	settings.set_value("ui_windows", TEST_WINDOW, Vector2(-1, -1))
	return true if ok else "GlassWindow should restore the saved position in _ready()"


func test_window_drag_tracks_pointer_and_clamps(t: SceneTree) -> Variant:
	var w := GlassWindow.new()
	t.root.add_child(w)
	await t.process_frame
	w.position = Vector2(100, 100)
	var start := w.global_position + Vector2(8, 8)
	w.start_drag(start)
	if not w._dragging:
		return "start_drag() did not begin a drag"
	w.drag_to(start + Vector2(40, 30))
	if not w.global_position.is_equal_approx(Vector2(140, 130)):
		return "dragging did not track the pointer: %s" % w.global_position
	w.drag_to(Vector2(-9999, -9999))
	if w.global_position != Vector2.ZERO:
		return "dragging should clamp inside the viewport: %s" % w.global_position
	w.end_drag()
	if w._dragging:
		return "end_drag() did not finish the drag"
	w.queue_free()
	await t.process_frame
	return true


func test_dragging_snaps_to_screen_edges(t: SceneTree) -> Variant:
	var w := GlassWindow.new()
	t.root.add_child(w)
	await t.process_frame
	w.size = Vector2(300, 200)
	w.position = Vector2(100, 100)
	var max_pos := (w.get_viewport_rect().size - w.size).max(Vector2.ZERO)
	w.start_drag(w.global_position)
	w.drag_to(Vector2(max_pos.x - 4.0, max_pos.y - 4.0))
	if not w.global_position.is_equal_approx(max_pos):
		return "dragging near the bottom-right should snap to both edges: %s" % w.global_position
	w.drag_to(Vector2(4, 4))
	if w.global_position != Vector2.ZERO:
		return "dragging near the top-left should snap to both edges: %s" % w.global_position
	w.end_drag()
	w.queue_free()
	await t.process_frame
	return true


func test_double_click_resets_position(t: SceneTree) -> Variant:
	var w := GlassWindow.new()
	w.position = Vector2(110, 80)
	t.root.add_child(w)
	await t.process_frame
	w.position = Vector2(420, 300)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	w._on_title_input(e)
	var got := w.global_position
	var ok := got.is_equal_approx(Vector2(110, 80))
	w.queue_free()
	await t.process_frame
	return true if ok else "a title-bar double-click should restore the default position: %s" % got
