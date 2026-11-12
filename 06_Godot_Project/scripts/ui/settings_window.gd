class_name SettingsWindow
extends GlassWindow
## Shared Settings overlay, opened from the title screen or with Esc in game.
## The overhead-name slider updates every live name tag through Settings'
## change signal, so the result is visible before closing the window.

signal reset_layout_requested

const MENU_STORAGE_KEY := "settings_menu"
const GAME_STORAGE_KEY := "settings_game"

var slider: HSlider
var value_label: Label
var rate_buttons: Array[Button] = []
var reset_button: Button
var reset_layout_button: Button
var hue_slider: HSlider
var hue_value: Label
var names_hover_button: Button
var camera_distance_slider: HSlider
var camera_pitch_slider: HSlider
var camera_yaw_slider: HSlider
var camera_value_labels: Dictionary = {}
## Set before add_child(): each surface keeps its own dragged position.
var storage_key := "settings"


func _ready() -> void:
	window_id = storage_key
	title = "SETTINGS"
	custom_minimum_size = Vector2(410, 0)
	padding = Vector4(18, 12, 18, 16)
	visible = false
	super._ready()
	_build()


func toggle(show: Variant = null) -> void:
	super.toggle(show)
	if visible:
		_place.call_deferred()


func _build() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	# The full options list can exceed a 720p viewport; keep it in a scroll area.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	body = content
	body.add_child(UiTheme.label("SERVER RATES · EXP & DROP", 11, UiTheme.ACCENT, 700, 3))
	var rate_row := HBoxContainer.new()
	rate_row.add_theme_constant_override("separation", 6)
	body.add_child(rate_row)
	var group := ButtonGroup.new()
	var active: int = settings.rate_preset()
	for multiplier in Settings.RATE_PRESETS + [Settings.RATE_PRESET_NONE]:
		var b := Button.new()
		var is_default: bool = multiplier == Settings.RATE_PRESET_NONE
		b.text = "DEFAULT" if is_default else "%d×" % multiplier
		b.tooltip_text = "Use the rates loaded from server config" if is_default \
			else "Set Base EXP, Job EXP and drops to %d×" % multiplier
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("rate_multiplier", multiplier)
		UiTheme.style_button(b, false, false, 11)
		b.pressed.connect(func(): settings.set_rate_preset(multiplier))
		rate_row.add_child(b)
		rate_buttons.append(b)
		b.set_pressed_no_signal(multiplier == active)
	body.add_child(UiTheme.label("BASE EXP · JOB EXP · DROPS    DEFAULT = SERVER CONFIG", 9, UiTheme.TEXT_DIM, 400, 2))
	body.add_child(UiTheme.label("OVERHEAD NAME SCALE", 11, UiTheme.ACCENT, 700, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	slider = HSlider.new()
	var limits: Vector2 = settings.overhead_name_scale_range()
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = Settings.OVERHEAD_NAME_STEP
	slider.value = settings.overhead_name_scale()
	slider.custom_minimum_size = Vector2(200, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "Scale overhead names from 50%% to 125%%"
	UiTheme.style_slider(slider)
	row.add_child(slider)
	value_label = UiTheme.label("%d%%" % roundi(slider.value * 100.0), 13, UiTheme.TEXT, 600, 2)
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.tooltip_text = "Reset overhead names to %d%%" % roundi(Settings.OVERHEAD_NAME_DEFAULT * 100.0)
	reset_button.custom_minimum_size = Vector2(74, 0)
	UiTheme.style_button(reset_button, false, false, 9)
	reset_button.add_theme_color_override("font_color", UiTheme.ACCENT)
	reset_button.pressed.connect(_reset_overhead_scale)
	row.add_child(reset_button)
	slider.value_changed.connect(func(v: float) -> void:
		settings.set_overhead_name_scale(v)
		value_label.text = "%d%%" % roundi(v * 100.0))
	body.add_child(UiTheme.label("NPC · MONSTER · PLAYER NAMES", 9, UiTheme.TEXT_DIM, 400, 2))
	body.add_child(UiTheme.label("INTERFACE HUE", 11, UiTheme.ACCENT, 700, 3))
	var hue_row := HBoxContainer.new()
	hue_row.add_theme_constant_override("separation", 10)
	body.add_child(hue_row)
	hue_slider = _slider_widget(hue_row, "HUE", 0.0, 1.0, 0.01, maxf(0.0, settings.ui_hue()),
		func(v): settings.set_ui_hue(v),
		func(v): return "DEFAULT" if settings.ui_hue() < 0.0 else "%d°" % roundi(v * 360.0))
	hue_value = hue_slider.get_meta("value_label")
	var hue_reset := Button.new()
	hue_reset.text = "DEFAULT"
	hue_reset.tooltip_text = "Restore the original Twilight Glass UI hue"
	hue_reset.custom_minimum_size = Vector2(82, 0)
	UiTheme.style_button(hue_reset, false, false, 9)
	hue_reset.pressed.connect(func():
		hue_slider.set_value_no_signal(0.0)
		settings.set_ui_hue(Settings.UI_HUE_DEFAULT)
		hue_value.text = "DEFAULT")
	hue_row.add_child(hue_reset)
	body.add_child(UiTheme.label("TINTS THE IN-GAME GLASS HUD", 9, UiTheme.TEXT_DIM, 400, 2))

	body.add_child(UiTheme.label("CHAT WINDOW", 11, UiTheme.ACCENT, 700, 3))
	var chat_size: Vector2 = settings.chat_size()
	var chat_w := chat_size.x
	var chat_h := chat_size.y
	var chat_apply := func(): settings.set_chat_size(Vector2(chat_w, chat_h))
	var chat_width := _slider_widget(body, "WIDTH", Settings.CHAT_WIDTH_MIN, Settings.CHAT_WIDTH_MAX, Settings.CHAT_WIDTH_STEP, chat_w,
		func(v): chat_w = v; chat_apply.call(),
		func(v): return "%d px" % roundi(v))
	chat_width.tooltip_text = "Width of the chat box"
	var chat_height := _slider_widget(body, "HEIGHT", Settings.CHAT_HEIGHT_MIN, Settings.CHAT_HEIGHT_MAX, Settings.CHAT_HEIGHT_STEP, chat_h,
		func(v): chat_h = v; chat_apply.call(),
		func(v): return "%d px" % roundi(v))
	chat_height.tooltip_text = "Height of the chat box"

	body.add_child(UiTheme.label("NAMEPLATES", 11, UiTheme.ACCENT, 700, 3))
	var names_row := HBoxContainer.new()
	names_row.add_theme_constant_override("separation", 8)
	body.add_child(names_row)
	names_hover_button = Button.new()
	names_hover_button.toggle_mode = true
	names_hover_button.button_pressed = settings.names_hover_only()
	names_hover_button.text = "HOVER ONLY" if names_hover_button.button_pressed else "ALWAYS"
	names_hover_button.tooltip_text = "Show player names only while hovering, then fade out"
	UiTheme.style_button(names_hover_button, false, false, 10)
	names_hover_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names_hover_button.pressed.connect(func():
		settings.set_names_hover_only(names_hover_button.button_pressed)
		names_hover_button.text = "HOVER ONLY" if names_hover_button.button_pressed else "ALWAYS")
	names_row.add_child(names_hover_button)
	var names_note := UiTheme.label("PLAYER HP BAR STAYS VISIBLE", 9, UiTheme.TEXT_DIM, 400, 1)
	names_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names_row.add_child(names_note)
	_slider_widget(body, "NAME FADE", Settings.NAMES_FADE_MIN, Settings.NAMES_FADE_MAX, Settings.NAMES_FADE_STEP, settings.names_fade_seconds(),
		func(v): settings.set_names_fade_seconds(v),
		func(v): return "%.1fs" % v)

	body.add_child(UiTheme.label("CAMERA", 11, UiTheme.ACCENT, 700, 3))
	var camera: Vector3 = settings.camera_view()
	var cam_distance := camera.x
	var cam_pitch := camera.y
	var cam_yaw := camera.z
	var camera_apply := func(): settings.set_camera_view(cam_distance, cam_pitch, cam_yaw)
	camera_distance_slider = _slider_widget(body, "ZOOM", Settings.CAMERA_DISTANCE_MIN, Settings.CAMERA_DISTANCE_MAX, Settings.CAMERA_DISTANCE_STEP, cam_distance,
		func(v): cam_distance = v; camera_apply.call(),
		func(v): return "%d" % roundi(v))
	camera_pitch_slider = _slider_widget(body, "TILT", Settings.CAMERA_PITCH_MIN, Settings.CAMERA_PITCH_MAX, Settings.CAMERA_PITCH_STEP, cam_pitch,
		func(v): cam_pitch = v; camera_apply.call(),
		func(v): return "%d°" % roundi(v))
	camera_yaw_slider = _slider_widget(body, "ANGLE", Settings.CAMERA_YAW_MIN, Settings.CAMERA_YAW_MAX, Settings.CAMERA_YAW_STEP, cam_yaw,
		func(v): cam_yaw = v; camera_apply.call(),
		func(v): return "%d°" % roundi(v))
	camera_value_labels = {
		"distance": camera_distance_slider.get_meta("value_label"),
		"pitch": camera_pitch_slider.get_meta("value_label"),
		"yaw": camera_yaw_slider.get_meta("value_label"),
	}
	var camera_reset := Button.new()
	camera_reset.text = "RESET CAMERA"
	camera_reset.tooltip_text = "Restore the classic 240 zoom, 50° tilt and 0° angle"
	UiTheme.style_button(camera_reset, false, false, 9)
	camera_reset.pressed.connect(_reset_camera)
	body.add_child(camera_reset)
	body.add_child(UiTheme.label("RIGHT-DRAG ROTATES · SHIFT+RIGHT-DRAG TILTS\nWHEEL OR PGUP/PGDN ZOOMS · HOME RESETS", 9, UiTheme.TEXT_DIM, 400, 2))

	var audio := get_node_or_null("/root/GameAudio")
	if audio:
		body.add_child(UiTheme.label("AUDIO", 11, UiTheme.ACCENT, 700, 3))
		_volume_row("MUSIC", audio.music_volume(), audio.set_music_volume)
		_volume_row("SOUND", audio.sfx_volume(), audio.set_sfx_volume)
		body.add_child(UiTheme.label("PLAYED FROM YOUR CLIENT'S BGM FOLDER AND DATA/WAV", 9, UiTheme.TEXT_DIM, 400, 2))
	reset_layout_button = Button.new()
	reset_layout_button.text = "RESET UI LAYOUT"
	reset_layout_button.tooltip_text = "Return every glass window to its default position"
	UiTheme.style_button(reset_layout_button, false, false, 9)
	reset_layout_button.pressed.connect(func(): reset_layout_requested.emit())
	body.add_child(reset_layout_button)
	if not settings.rate_preset_changed.is_connected(_sync_rate_buttons):
		settings.rate_preset_changed.connect(_sync_rate_buttons)


## Adds a labelled slider row and returns it. The label is exposed as metadata
## so callers can update it later (for example a reset button).
func _slider_widget(parent: Node, title: String, lo: float, hi: float, step: float, value: float, apply: Callable, format: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var name_label := UiTheme.label(title, 10, UiTheme.TEXT_DIM, 600, 2)
	name_label.custom_minimum_size = Vector2(62, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(190, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_slider(s)
	row.add_child(s)
	var shown := UiTheme.label(String(format.call(value)), 13, UiTheme.TEXT, 600, 2)
	shown.custom_minimum_size = Vector2(52, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(shown)
	s.set_meta("value_label", shown)
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		shown.text = String(format.call(v)))
	return s


func _reset_camera() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	camera_distance_slider.set_value_no_signal(Settings.CAMERA_DISTANCE_DEFAULT)
	camera_pitch_slider.set_value_no_signal(Settings.CAMERA_PITCH_DEFAULT)
	camera_yaw_slider.set_value_no_signal(Settings.CAMERA_YAW_DEFAULT)
	settings.set_camera_view(Settings.CAMERA_DISTANCE_DEFAULT, Settings.CAMERA_PITCH_DEFAULT, Settings.CAMERA_YAW_DEFAULT)
	if camera_value_labels.has("distance"):
		(camera_value_labels.distance as Label).text = "%d" % roundi(Settings.CAMERA_DISTANCE_DEFAULT)
	if camera_value_labels.has("pitch"):
		(camera_value_labels.pitch as Label).text = "%d°" % roundi(Settings.CAMERA_PITCH_DEFAULT)
	if camera_value_labels.has("yaw"):
		(camera_value_labels.yaw as Label).text = "%d°" % roundi(Settings.CAMERA_YAW_DEFAULT)


## A labelled 0-100% volume slider that applies and stores on change.
func _volume_row(title: String, value: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var name_label := UiTheme.label(title, 10, UiTheme.TEXT_DIM, 600, 2)
	name_label.custom_minimum_size = Vector2(52, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(200, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_slider(s)
	row.add_child(s)
	var pct := UiTheme.label("%d%%" % roundi(value * 100.0), 13, UiTheme.TEXT, 600, 2)
	pct.custom_minimum_size = Vector2(44, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		pct.text = "%d%%" % roundi(v * 100.0))


func _sync_rate_buttons(multiplier: int) -> void:
	for b in rate_buttons:
		b.set_pressed_no_signal(int(b.get_meta("rate_multiplier", 0)) == multiplier)


func _reset_overhead_scale() -> void:
	slider.value = Settings.OVERHEAD_NAME_DEFAULT


func _place() -> void:
	if not visible:
		return
	reset_size()
	await get_tree().process_frame
	if not visible:
		return
	var settings := get_node_or_null("/root/Settings")
	var saved: Variant = settings.get_value("ui_windows", window_id, null) if settings else null
	if saved is Vector2:
		_clamp_to_screen()
	else:
		position = ((get_viewport_rect().size - size) / 2.0).max(Vector2.ZERO)
	set_home_position(position)


## Moves Settings itself to the viewport centre and remembers that home spot.
func center_position() -> void:
	if not visible:
		return
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).max(Vector2.ZERO)
	_clamp_to_screen()
	set_home_position(position)
	_save_position()
