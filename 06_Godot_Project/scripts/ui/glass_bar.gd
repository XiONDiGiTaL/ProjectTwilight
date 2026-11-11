class_name GlassBar
extends Control
## Sleek animated resource bar (glass_bar.gdshader).
##
## Decline is shown in two stages: the fill drops quickly while a white chip
## holds the old value for a moment and then drains down to meet it. HP bars
## shift colour with remaining health (green -> amber -> red).

const SHADER := preload("res://scripts/ui/glass_bar.gdshader")

enum Style { HP, SP, BASE_EXP, JOB_EXP }

@export var style := Style.HP
@export var ticks := 10.0
@export var glow_px := 3.0

var max_value := 1.0
var current := 1.0

var _shown := 1.0
var _trail := 1.0
var _hold := 0.0
var _flash := 0.0
var _mat := ShaderMaterial.new()
var _rect := ColorRect.new()

const TRAIL_HOLD := 0.45
const TRAIL_DRAIN_PER_SEC := 0.6
const FILL_SPEED := 10.0


func _ready() -> void:
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.set_shader_parameter("ticks", ticks)
	_mat.set_shader_parameter("glow_px", glow_px)
	match style:
		Style.SP: _mat.set_shader_parameter("fill_color", UiTheme.SP)
		Style.BASE_EXP: _mat.set_shader_parameter("fill_color", UiTheme.EXP_BASE)
		Style.JOB_EXP: _mat.set_shader_parameter("fill_color", UiTheme.EXP_JOB)
		_: _mat.set_shader_parameter("fill_color", UiTheme.HP_HIGH)
	resized.connect(func(): _mat.set_shader_parameter("size", size))
	_mat.set_shader_parameter("size", size)
	_push()


func snap(value: float, maximum: float) -> void:
	max_value = maxf(maximum, 1.0)
	current = clampf(value, 0.0, max_value)
	_shown = current / max_value
	_trail = _shown
	_push()


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
	_flash = maxf(0.0, _flash - delta * 6.0)
	_push()


func _push() -> void:
	if _rect == null or _mat.shader == null:
		return
	_mat.set_shader_parameter("value", _shown)
	_mat.set_shader_parameter("trail", _trail)
	_mat.set_shader_parameter("flash", _flash)
	if style == Style.HP:
		_mat.set_shader_parameter("fill_color", UiTheme.hp_color(_shown))
		_mat.set_shader_parameter("pulse", 1.0 if _shown < 0.2 and _shown > 0.0 else 0.0)
