extends RefCounted
## UI layout contract: labels share a vertical centre, buttons share a usable
## height, and draggable windows keep a saved position instead of accepting a
## hardcoded default after they enter the tree.

const TEST_WINDOW := "__ui_layout_test"
const SETTINGS_WINDOW := preload("res://scripts/ui/settings_window.gd")


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


func test_windows_snap_to_each_other(t: SceneTree) -> Variant:
	var a := GlassWindow.new()
	var b := GlassWindow.new()
	t.root.add_child(a)
	t.root.add_child(b)
	await t.process_frame
	a.size = Vector2(200, 150)
	b.size = Vector2(200, 150)
	a.position = Vector2(100, 100)
	b.position = Vector2(500, 100)
	a.start_drag(a.global_position)
	a.drag_to(Vector2(306, 100))
	var got := a.global_position
	var ok := got.is_equal_approx(Vector2(300, 100))
	a.end_drag()
	a.queue_free()
	b.queue_free()
	await t.process_frame
	return true if ok else "a dragged window should snap flush to a neighbour's edge: %s" % got


func test_edge_snap_state_tracks_viewport_border(t: SceneTree) -> Variant:
	var w := GlassWindow.new()
	t.root.add_child(w)
	await t.process_frame
	w.size = Vector2(300, 200)
	w.position = Vector2(100, 100)
	w.start_drag(w.global_position)
	w.drag_to(Vector2(4, 100))
	if not w._edge_snapped:
		return "a window flush to the viewport should enter its edge-snap state"
	w.drag_to(Vector2(100, 100))
	var ok := not w._edge_snapped
	w.end_drag()
	w.queue_free()
	await t.process_frame
	return true if ok else "edge-snap state should clear when the window leaves the border"


func test_overhead_name_scale_is_clamped(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old: float = settings.overhead_name_scale()
	settings.set_overhead_name_scale(-1.0)
	var low_ok := is_equal_approx(settings.overhead_name_scale(), 0.5)
	settings.set_overhead_name_scale(9.0)
	var high_ok := is_equal_approx(settings.overhead_name_scale(), 1.25)
	settings.set_overhead_name_scale(old)
	if not low_ok:
		return "overhead name scale should clamp to 50%"
	if not high_ok:
		return "overhead name scale should clamp to 125%"
	return true


func test_settings_window_updates_scale_live(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old: float = settings.overhead_name_scale()
	var w = SETTINGS_WINDOW.new()
	t.root.add_child(w)
	await t.process_frame
	var starts_hidden: bool = not w.visible
	w.toggle()
	await t.process_frame
	var opens: bool = w.visible
	w.slider.value = 0.55
	await t.process_frame
	var updates: bool = is_equal_approx(settings.overhead_name_scale(), 0.55) \
		and w.value_label.text == "55%"
	w.reset_button.pressed.emit()
	await t.process_frame
	var resets: bool = is_equal_approx(settings.overhead_name_scale(), 0.7) \
		and w.value_label.text == "70%"
	w.toggle(false)
	w.queue_free()
	settings.set_overhead_name_scale(old)
	await t.process_frame
	if not starts_hidden:
		return "SettingsWindow should start hidden"
	if not opens:
		return "SettingsWindow.toggle() should open it"
	if not updates:
		return "the Settings slider should update and display the live scale"
	if not resets:
		return "the Settings reset action should restore the 70% default"
	return true


func test_hud_settings_button_toggles_overlay(t: SceneTree) -> Variant:
	var hud := CombatHud.new()
	t.root.add_child(hud)
	await t.process_frame
	if hud.settings_button == null or hud.settings_window == null:
		return "the HUD should expose a Settings button and overlay"
	if hud.settings_button.text != "SETTINGS":
		return "the HUD Settings button should be labelled"
	hud.settings_button.pressed.emit()
	await t.process_frame
	var opened: bool = hud.settings_window.visible
	hud.settings_button.pressed.emit()
	await t.process_frame
	var closed: bool = not hud.settings_window.visible
	hud.queue_free()
	await t.process_frame
	if not opened:
		return "the HUD Settings button should open the overlay"
	if not closed:
		return "the HUD Settings button should close the overlay"
	return true


func test_settings_window_remembers_dragged_position(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old: Variant = settings.get_value("ui_windows", "settings", null)
	settings.set_value("ui_windows", "settings", Vector2(120, 100))
	var w = SETTINGS_WINDOW.new()
	t.root.add_child(w)
	await t.process_frame
	w.toggle()
	await t.process_frame
	w.start_drag(w.global_position)
	w.drag_to(Vector2(240, 180))
	w.end_drag()
	var saved: Variant = settings.get_value("ui_windows", "settings", null)
	var saved_ok := false
	if saved is Vector2:
		var at: Vector2 = saved
		saved_ok = at.is_equal_approx(Vector2(240, 180))
	w.toggle(false)
	w.queue_free()
	await t.process_frame
	var w2 = SETTINGS_WINDOW.new()
	t.root.add_child(w2)
	await t.process_frame
	var restored: bool = w2.position.is_equal_approx(Vector2(240, 180))
	w2.queue_free()
	settings.set_value("ui_windows", "settings", old)
	await t.process_frame
	if not saved_ok:
		return "ending a Settings drag should save its position"
	if not restored:
		return "a new Settings window should restore the saved position"
	return true
