class_name RoCamera
extends Camera3D
## Classic-style isometric follow camera: rotatable yaw and pitch, zoom.
## Controls: right-drag rotates, Shift+right-drag tilts, wheel zooms,
## PageUp/PageDown or +/- zoom, Home resets, WASD/arrows pan (when no target).

@export var pitch_deg := 50.0
@export var yaw_deg := 0.0
@export var distance := 320.0
@export var min_distance := 80.0
@export var max_distance := 900.0
@export var pan_speed := 400.0

var focus := Vector3.ZERO
var follow: Node3D

var _rotating := false


func _ready() -> void:
	fov = 30.0
	far = 6000.0
	_apply()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.9)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.1)
	elif e is InputEventMouseMotion and _rotating:
		yaw_deg = fposmod(yaw_deg - e.relative.x * 0.3, 360.0)
		if e.shift_pressed:
			pitch_deg = clampf(pitch_deg - e.relative.y * 0.2, 20.0, 80.0)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_PAGEUP, KEY_EQUAL:
				zoom_by(0.9)
			KEY_PAGEDOWN, KEY_MINUS:
				zoom_by(1.1)
			KEY_HOME:
				reset_view()


## Multiplies the camera distance, clamped to its configured limits.
func zoom_by(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)


## Restores the classic starting angle and zoom.
func reset_view() -> void:
	distance = 240.0
	pitch_deg = 50.0
	yaw_deg = 0.0


func _process(delta: float) -> void:
	if follow:
		focus = follow.global_position
	else:
		var v := Vector2(
			Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		if v != Vector2.ZERO:
			var basis_yaw := Basis(Vector3.UP, deg_to_rad(yaw_deg))
			focus += basis_yaw * Vector3(v.x, 0, v.y).normalized() * pan_speed * delta * (distance / 320.0)
	_apply()


func _apply() -> void:
	var dir := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg)) * Vector3(0, 0, 1)
	global_position = focus + dir * distance
	look_at(focus, Vector3.UP)
