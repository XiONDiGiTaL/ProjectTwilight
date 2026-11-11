class_name RoCamera
extends Camera3D
## Classic-style isometric follow camera: fixed pitch, rotatable yaw, zoom.
## Controls: right-drag rotates, wheel zooms, WASD/arrows pan (when no target).

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
			distance = maxf(min_distance, distance * 0.9)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)
	elif e is InputEventMouseMotion and _rotating:
		yaw_deg = fposmod(yaw_deg - e.relative.x * 0.3, 360.0)


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
