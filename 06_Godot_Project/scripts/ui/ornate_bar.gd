class_name OrnateBar
extends Control
## Animated resource bar using ornate_bar.gdshader.
##
## Decline is shown in two stages, like modern action RPGs: the fill drops
## quickly to the new value while a pale "chip" holds the old value for a
## moment and then drains down to meet it.

const SHADER := preload("res://scripts/ui/ornate_bar.gdshader")

enum Style { HP, SP, BASE_EXP, JOB_EXP }

@export var style := Style.HP
@export var show_diamond := true
@export var show_horns := true
## Slim frame with pointed spear tips instead of the ornate horned frame.
@export var sleek := false

var max_value := 1.0
var current := 1.0

var _shown := 1.0        # displayed fill fraction
var _trail := 1.0        # displayed chip fraction
var _hold := 0.0         # seconds before the chip starts draining
var _flash := 0.0
var _mat := ShaderMaterial.new()
var _rect := ColorRect.new()

const TRAIL_HOLD := 0.45
const TRAIL_DRAIN_PER_SEC := 0.55
const FILL_SPEED := 9.0


func _ready() -> void:
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_style()
	resized.connect(_on_resized)
	_on_resized()


func _apply_style() -> void:
	_mat.set_shader_parameter("show_diamond", show_diamond)
	_mat.set_shader_parameter("show_horns", show_horns)
	_mat.set_shader_parameter("sleek", sleek)
	match style:
		Style.SP:
			_set_fill(Color(0.02, 0.08, 0.4), Color(0.1, 0.35, 0.95), Color(0.55, 0.85, 1.0), Color(0.75, 0.9, 1.0))
			_mat.set_shader_parameter("low_pulse", 0.0)
		Style.BASE_EXP:
			_set_fill(Color(0.35, 0.22, 0.02), Color(0.85, 0.62, 0.12), Color(1.0, 0.93, 0.55), Color(1, 1, 0.85))
			_mat.set_shader_parameter("low_pulse", 0.0)
			_mat.set_shader_parameter("flow_speed", 0.4)
		Style.JOB_EXP:
			_set_fill(Color(0.02, 0.25, 0.1), Color(0.15, 0.7, 0.3), Color(0.7, 1.0, 0.6), Color(0.9, 1, 0.85))
			_mat.set_shader_parameter("low_pulse", 0.0)
			_mat.set_shader_parameter("flow_speed", 0.4)
		_:
			pass  # HP uses the shader's molten-red defaults


func _set_fill(dark: Color, mid: Color, hot: Color, chip: Color) -> void:
	_mat.set_shader_parameter("fill_dark", dark)
	_mat.set_shader_parameter("fill_mid", mid)
	_mat.set_shader_parameter("fill_hot", hot)
	_mat.set_shader_parameter("trail_color", chip)


func _on_resized() -> void:
	_mat.set_shader_parameter("size", size)


## Sets the bar instantly (no decline animation), e.g. when first shown.
func snap(value: float, maximum: float) -> void:
	max_value = maxf(maximum, 1.0)
	current = clampf(value, 0.0, max_value)
	_shown = current / max_value
	_trail = _shown
	_push()


## Sets a new value; decreases animate with the lingering chip, increases fill up.
func set_value(value: float, maximum: float) -> void:
	var old_frac := current / max_value if max_value > 0.0 else 0.0
	max_value = maxf(maximum, 1.0)
	current = clampf(value, 0.0, max_value)
	var frac := current / max_value
	if frac < old_frac - 0.0001:
		_trail = maxf(_trail, old_frac)
		_hold = TRAIL_HOLD
		_flash = 1.0
	elif frac > _trail:
		_trail = frac


func fraction() -> float:
	return current / max_value if max_value > 0.0 else 0.0


func displayed_fraction() -> float:
	return _shown


func trail_fraction() -> float:
	return _trail


func _process(delta: float) -> void:
	var target := fraction()
	_shown = move_toward(_shown, target, delta * FILL_SPEED * maxf(0.05, absf(_shown - target)) + delta * 0.2)
	if _hold > 0.0:
		_hold -= delta
	else:
		_trail = maxf(target, _trail - TRAIL_DRAIN_PER_SEC * delta)
	_trail = maxf(_trail, _shown)
	_flash = maxf(0.0, _flash - delta * 5.0)
	_push()


func _push() -> void:
	_mat.set_shader_parameter("value", _shown)
	_mat.set_shader_parameter("trail", _trail)
	_mat.set_shader_parameter("flash", _flash)
