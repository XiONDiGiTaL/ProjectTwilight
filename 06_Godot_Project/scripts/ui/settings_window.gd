class_name SettingsWindow
extends GlassWindow
## Shared Settings overlay, opened from the title screen or with Esc in game.
## The overhead-name slider updates every live name tag through Settings'
## change signal, so the result is visible before closing the window.

var slider: HSlider
var value_label: Label


func _ready() -> void:
	title = "SETTINGS"
	custom_minimum_size = Vector2(410, 0)
	padding = Vector4(18, 12, 18, 16)
	visible = false
	super._ready()
	_build()


func toggle(show: Variant = null) -> void:
	super.toggle(show)
	if visible:
		_center.call_deferred()


func _build() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
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
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "Scale overhead names from 50%% to 125%%"
	UiTheme.style_slider(slider)
	row.add_child(slider)
	value_label = UiTheme.label("%d%%" % roundi(slider.value * 100.0), 13, UiTheme.TEXT, 600, 2)
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		settings.set_overhead_name_scale(v)
		value_label.text = "%d%%" % roundi(v * 100.0))
	body.add_child(UiTheme.label("NPC · MONSTER · PLAYER NAMES", 9, UiTheme.TEXT_DIM, 400, 2))


func _center() -> void:
	if not visible:
		return
	reset_size()
	await get_tree().process_frame
	if not visible:
		return
	var at := ((get_viewport_rect().size - size) / 2.0).max(Vector2.ZERO)
	position = at
	set_home_position(at)