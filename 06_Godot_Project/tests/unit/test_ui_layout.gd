extends RefCounted
## UI layout contract: labels share a vertical centre, buttons share a usable
## height, and draggable windows keep a saved position instead of accepting a
## hardcoded default after they enter the tree.

const TEST_WINDOW := "__ui_layout_test"
const SETTINGS_WINDOW := preload("res://scripts/ui/settings_window.gd")
const FIELD_SCENE := preload("res://scripts/game/field_scene.gd")
const SETTINGS_POSITION_TEST := "__settings_position_test"


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


func test_settings_window_rate_presets(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old: int = settings.rate_preset()
	settings.set_value("rules", "rate_preset", Settings.RATE_PRESET_NONE)
	var w = SETTINGS_WINDOW.new()
	t.root.add_child(w)
	await t.process_frame
	w.toggle()
	await t.process_frame
	var labels: Array = []
	for b in w.rate_buttons:
		labels.append(b.text)
	var labels_ok: bool = labels == ["1×", "25×", "50×", "DEFAULT"]
	for b in w.rate_buttons:
		if int(b.get_meta("rate_multiplier", 0)) == 25:
			b.pressed.emit()
	await t.process_frame
	var stored: bool = settings.rate_preset() == 25
	var selected := false
	for b in w.rate_buttons:
		if int(b.get_meta("rate_multiplier", 0)) == 25:
			selected = b.button_pressed
	var live_rule := RuleConfig.new()
	live_rule.apply_rate_multiplier(settings.rate_preset())
	var rates_ok: bool = live_rule.exp_rate == 2500 and live_rule.drop_rate == 2500
	for b in w.rate_buttons:
		if int(b.get_meta("rate_multiplier", -1)) == 0:
			b.pressed.emit()
	await t.process_frame
	var cleared: bool = settings.rate_preset() == Settings.RATE_PRESET_NONE
	var default_selected := false
	for b in w.rate_buttons:
		if int(b.get_meta("rate_multiplier", -1)) == 0:
			default_selected = b.button_pressed
	w.toggle(false)
	w.queue_free()
	settings.set_value("rules", "rate_preset", old)
	await t.process_frame
	if not labels_ok:
		return "Settings should offer 1x, 25x, 50x and DEFAULT: %s" % [labels]
	if not stored:
		return "choosing a preset should persist it"
	if not selected:
		return "the chosen preset button should stay highlighted"
	if not rates_ok:
		return "a 25x preset should become 2500%% for EXP and drops"
	if not cleared:
		return "DEFAULT should clear the stored rate preset"
	if not default_selected:
		return "the DEFAULT button should stay highlighted after clearing the preset"
	return true


func test_rate_change_notices_show_effective_rates(t: SceneTree) -> Variant:
	var gat := GatFile.new()
	gat.width = 1
	gat.height = 1
	gat.heights.resize(4)
	gat.types.resize(1)
	var rules := RuleConfig.new()
	var scene = FIELD_SCENE.new()
	scene.sim = FieldSimulation.new(gat, 1, rules)
	scene._config_exp_rate = 5000
	scene._config_job_exp_rate = 5000
	scene._config_drop_rate = 5000
	var hud := CombatHud.new()
	t.root.add_child(hud)
	await t.process_frame
	scene.hud = hud
	scene._apply_rate_preset(25)
	await t.process_frame
	var set_text: String = str(_feed_texts(hud)[-1])
	scene._apply_rate_preset(Settings.RATE_PRESET_NONE)
	await t.process_frame
	var restored_text: String = str(_feed_texts(hud)[-1])
	var restored_rates: bool = rules.exp_rate == 5000 and rules.job_exp_rate == 5000 and rules.drop_rate == 5000
	scene.free()
	hud.queue_free()
	await t.process_frame
	if set_text != "Rates set:  EXP x25   JOB x25   DROP x25":
		return "a preset change should announce its rates: %s" % set_text
	if restored_text != "Rates restored:  EXP x50   JOB x50   DROP x50":
		return "DEFAULT should announce the restored config rates: %s" % restored_text
	if not restored_rates:
		return "DEFAULT should restore the config rates captured by the field"
	return true


func _feed_texts(hud: CombatHud) -> Array:
	var texts: Array = []
	for chip in hud._feed.get_children():
		for child in chip.get_children():
			if child is Label:
				texts.append(child.text)
	return texts


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
	var old: Variant = settings.get_value("ui_windows", SETTINGS_POSITION_TEST, null)
	settings.set_value("ui_windows", SETTINGS_POSITION_TEST, Vector2(120, 100))
	var w = SETTINGS_WINDOW.new()
	w.storage_key = SETTINGS_POSITION_TEST
	t.root.add_child(w)
	await t.process_frame
	w.toggle()
	await t.process_frame
	w.start_drag(w.global_position)
	w.drag_to(Vector2(240, 180))
	w.end_drag()
	var saved: Variant = settings.get_value("ui_windows", SETTINGS_POSITION_TEST, null)
	var saved_ok := false
	if saved is Vector2:
		var at: Vector2 = saved
		saved_ok = at.is_equal_approx(Vector2(240, 180))
	w.toggle(false)
	w.queue_free()
	await t.process_frame
	var w2 = SETTINGS_WINDOW.new()
	w2.storage_key = SETTINGS_POSITION_TEST
	t.root.add_child(w2)
	await t.process_frame
	var restored: bool = w2.position.is_equal_approx(Vector2(240, 180))
	w2.queue_free()
	settings.set_value("ui_windows", SETTINGS_POSITION_TEST, old)
	await t.process_frame
	if not saved_ok:
		return "ending a Settings drag should save its position"
	if not restored:
		return "a new Settings window should restore the saved position"
	return true


func test_settings_window_keeps_surface_positions_separate(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var menu_key: String = SETTINGS_WINDOW.MENU_STORAGE_KEY
	var game_key: String = SETTINGS_WINDOW.GAME_STORAGE_KEY
	var old_menu: Variant = settings.get_value("ui_windows", menu_key, null)
	var old_game: Variant = settings.get_value("ui_windows", game_key, null)
	settings.set_value("ui_windows", menu_key, Vector2(70, 80))
	settings.set_value("ui_windows", game_key, Vector2(500, 360))
	var menu := SETTINGS_WINDOW.new()
	menu.storage_key = menu_key
	t.root.add_child(menu)
	var game := SETTINGS_WINDOW.new()
	game.storage_key = game_key
	t.root.add_child(game)
	await t.process_frame
	var menu_ok: bool = menu.position.is_equal_approx(Vector2(70, 80))
	var game_ok: bool = game.position.is_equal_approx(Vector2(500, 360))
	menu.queue_free()
	game.queue_free()
	settings.set_value("ui_windows", menu_key, old_menu)
	settings.set_value("ui_windows", game_key, old_game)
	await t.process_frame
	if not menu_ok:
		return "the title-screen Settings position should load independently"
	if not game_ok:
		return "the in-game Settings position should load independently"
	return true


func test_hud_reset_ui_layout_returns_windows(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var hud := CombatHud.new()
	t.root.add_child(hud)
	await t.process_frame
	var saved: Dictionary = {}
	for node in hud._root.get_children():
		if node is GlassWindow and node.window_id != "":
			saved[node.window_id] = settings.get_value("ui_windows", node.window_id, null)
	var inventory_pos: Vector2 = hud.inventory._default_position
	hud.inventory.position = Vector2(200, 200)
	hud.toggle_settings()
	await t.process_frame
	await t.process_frame
	hud.settings_window.reset_layout_button.pressed.emit()
	await t.process_frame
	var inventory_ok: bool = hud.inventory.position.is_equal_approx(inventory_pos)
	var expected := ((hud.settings_window.get_viewport_rect().size - hud.settings_window.size) / 2.0).max(Vector2.ZERO)
	var settings_ok: bool = hud.settings_window.position.is_equal_approx(expected)
	var feed_ok := false
	for chip in hud._feed.get_children():
		for child in chip.get_children():
			if child is Label and child.text == "UI layout reset.":
				feed_ok = true
	for id in saved:
		settings.set_value("ui_windows", id, saved[id])
	hud.queue_free()
	await t.process_frame
	if not inventory_ok:
		return "Reset UI Layout should restore the inventory position"
	if not settings_ok:
		return "Reset UI Layout should re-center Settings"
	if not feed_ok:
		return "Reset UI Layout should confirm through the system feed"
	return true
