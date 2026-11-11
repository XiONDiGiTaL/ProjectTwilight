class_name UnitView
extends Node3D
## Visual for one SimUnit (player or monster). Reads simulation state; never writes it.

const BODY_DIR := "data\\sprite\\인간족\\몸통\\"
const HEAD_DIR := "data\\sprite\\인간족\\머리통\\"
const MONSTER_DIR := "data\\sprite\\몬스터\\"
const DEATH_FADE := 0.6

var unit: SimUnit
var map: RoMap
var sprite: CharacterSprite
var camera_yaw := 0.0
var _fade := 1.0
var _was_dead := false


func build_player(res: Node, male: bool, hair_style: int, hair_color: int) -> bool:
	var sex := "남" if male else "여"
	var body := BODY_DIR + "%s\\%s_%s" % [sex, unit.sprite, sex]
	var head := HEAD_DIR + "%s\\%d_%s" % [sex, hair_style, sex]
	var bspr := SprFile.decode(res.read(body + ".spr"))
	var bact := ActFile.decode(res.read(body + ".act"))
	if bspr == null or bact == null:
		return false
	var pal: PackedByteArray = res.read("data\\palette\\머리\\머리%d_%s_%d.pal" % [hair_style, sex, hair_color]) if hair_color >= 0 else PackedByteArray()
	sprite = CharacterSprite.new()
	sprite.actions = CharacterSprite.PLAYER_ACTIONS
	add_child(sprite)
	sprite.setup(bspr, bact, SprFile.decode(res.read(head + ".spr")), ActFile.decode(res.read(head + ".act")), pal)
	return true


func build_monster(res: Node) -> bool:
	var base := MONSTER_DIR + unit.sprite
	var spr := SprFile.decode(res.read(base + ".spr"))
	var act := ActFile.decode(res.read(base + ".act"))
	if spr == null or act == null:
		return false
	sprite = CharacterSprite.new()
	sprite.actions = CharacterSprite.MONSTER_ACTIONS
	add_child(sprite)
	sprite.setup(spr, act)
	return true


## World position just above the sprite's head (for HP bars and text).
func head_position() -> Vector3:
	return global_position + Vector3(0, (sprite.top_height() if sprite else 8.0) + 3.5, 0)


func _process(delta: float) -> void:
	if unit == null or map == null or sprite == null:
		return
	position = map.cell_pos_to_world(unit.walker.position())
	var dir := PlayerAvatar.sprite_direction(unit.walker.direction, camera_yaw)
	if unit.dead:
		if not _was_dead:
			_was_dead = true
			sprite.play_once("dead", 0.0, true)
		sprite.set_action("idle", dir)
		_fade = maxf(0.0, _fade - delta / DEATH_FADE * (0.5 if unit.is_player() else 1.0))
		sprite.modulate.a = 1.0 if unit.is_player() else clampf(_fade * 1.6, 0.0, 1.0)
		return
	if _was_dead:
		_was_dead = false
		_fade = 1.0
		sprite.modulate.a = 1.0
		sprite.reset_action()
	sprite.set_action("walk" if unit.walker.is_moving() else "idle", dir)
