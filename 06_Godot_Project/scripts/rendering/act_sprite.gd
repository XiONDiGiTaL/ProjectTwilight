class_name ActSprite
extends Node2D
## Draws and animates an SPR/ACT pair the way the classic client composes it:
## every frame is a stack of layers, each image centred on its layer offset,
## then mirrored, scaled, rotated and tinted.
##
## Rendering only: gameplay code sets `action` / `direction` and never reads pixels.

signal animation_finished(action: int)

## Classic action groups (each group has 8 directions). Monsters use a subset.
enum ActionType { IDLE, WALK, SIT, PICKUP, READY, ATTACK1, HURT, FREEZE, DEAD }

var spr: SprFile
var act: ActFile
var palette_override := PackedByteArray()
var action: int = 0:
	set(v):
		if v != action:
			action = v
			_frame = 0
			_elapsed = 0.0
			queue_redraw()
var looping := true
var speed_scale := 1.0

var _frame := 0
var _elapsed := 0.0
var _textures: Dictionary = {}  # "type:index" -> Texture2D


func setup(p_spr: SprFile, p_act: ActFile, p_palette := PackedByteArray()) -> void:
	spr = p_spr
	act = p_act
	palette_override = p_palette
	_textures.clear()
	_frame = 0
	_elapsed = 0.0
	queue_redraw()


## Selects action = group * 8 + direction (0 = south, counter-clockwise in RO order).
func play(group: int, direction: int) -> void:
	if act == null:
		return
	var idx := group * 8 + (direction & 7)
	action = clampi(idx, 0, act.actions.size() - 1)


func frame_count() -> int:
	if act == null or act.actions.is_empty():
		return 0
	return act.actions[action].frames.size()


func current_frame() -> int:
	return _frame


func _process(delta: float) -> void:
	var n := frame_count()
	if n <= 1:
		return
	var interval: float = maxf(act.actions[action].interval, 10.0) / 1000.0
	_elapsed += delta * speed_scale
	while _elapsed >= interval:
		_elapsed -= interval
		_frame += 1
		if _frame >= n:
			if looping:
				_frame = 0
			else:
				_frame = n - 1
				animation_finished.emit(action)
				set_process(false)
		queue_redraw()


func _texture(index: int, type: int) -> Texture2D:
	var key := "%d:%d" % [type, index]
	if _textures.has(key):
		return _textures[key]
	var img := spr.image_for(index, type, palette_override)
	var tex: Texture2D = ImageTexture.create_from_image(img) if img else null
	_textures[key] = tex
	return tex


func _draw() -> void:
	if spr == null or act == null or act.actions.is_empty():
		return
	var frames: Array = act.actions[action].frames
	if frames.is_empty():
		return
	var frame: Dictionary = frames[mini(_frame, frames.size() - 1)]
	for layer in frame.layers:
		if layer.sprite < 0:
			continue
		var tex := _texture(layer.sprite, layer.type)
		if tex == null:
			continue
		var sc: Vector2 = layer.scale
		if layer.mirror:
			sc.x = -sc.x
		draw_set_transform(Vector2(layer.pos), deg_to_rad(layer.rotation), sc)
		draw_texture(tex, -tex.get_size() / 2.0, layer.color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
