class_name PlayerAvatar
extends Node3D
## Visual representation of a walking character on an RoMap.
## Owns no gameplay rules: it mirrors a GridWalker's position and direction.

const BODY_DIR := "data\\sprite\\인간족\\몸통\\"
const HEAD_DIR := "data\\sprite\\인간족\\머리통\\"

var walker: GridWalker
var map: RoMap
var sprite: CharacterSprite
## Camera yaw in degrees, used to pick which of the 8 sprite directions to show.
var camera_yaw := 0.0


## job_sprite: body sprite base name such as "초보자" (Novice). male: sex.
func build(res: Node, job_sprite: String, male: bool, hair_style: int, hair_color: int = -1) -> bool:
	var sex := "남" if male else "여"
	var body := BODY_DIR + "%s\\%s_%s" % [sex, job_sprite, sex]
	var head := HEAD_DIR + "%s\\%d_%s" % [sex, hair_style, sex]
	var bspr := SprFile.decode(res.read(body + ".spr"))
	var bact := ActFile.decode(res.read(body + ".act"))
	if bspr == null or bact == null:
		push_warning("Body sprite missing: %s" % body)
		return false
	var hspr := SprFile.decode(res.read(head + ".spr"))
	var hact := ActFile.decode(res.read(head + ".act"))
	var pal := PackedByteArray()
	if hair_color >= 0:
		pal = res.read("data\\palette\\머리\\머리%d_%s_%d.pal" % [hair_style, sex, hair_color])
	sprite = CharacterSprite.new()
	sprite.name = "Sprite"
	add_child(sprite)
	sprite.setup(bspr, bact, hspr, hact, pal)
	return true


func _process(_delta: float) -> void:
	if walker == null or map == null:
		return
	position = map.cell_pos_to_world(walker.position())
	if sprite:
		var group := CharacterSprite.Group.WALK if walker.is_moving() else CharacterSprite.Group.IDLE
		sprite.set_state(group, sprite_direction(walker.direction, camera_yaw))


## World direction -> displayed sprite direction for a camera rotated by yaw
## degrees (counter-clockwise when viewed from above).
static func sprite_direction(world_dir: int, yaw_deg: float) -> int:
	var steps := roundi(fposmod(yaw_deg, 360.0) / 45.0)
	return (world_dir + steps) & 7
