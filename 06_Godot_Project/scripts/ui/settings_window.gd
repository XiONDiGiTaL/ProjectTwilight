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
	reset_layout_button = Button.new()
	reset_layout_button.text = "RESET UI LAYOUT"
	reset_layout_button.tooltip_text = "Return every glass window to its default position"
	UiTheme.style_button(reset_layout_button, false, false, 9)
	reset_layout_button.pressed.connect(func(): reset_layout_requested.emit())
	body.add_child(reset_layout_button)
	if not settings.rate_preset_changed.is_connected(_sync_rate_buttons):
		settings.rate_preset_changed.connect(_sync_rate_buttons)


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
