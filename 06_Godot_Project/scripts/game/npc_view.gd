class_name NpcView
extends Node3D
## Visual for an NPC: the client's NPC sprite plus a floating name tag.

const NPC_DIR := "data/sprite/npc/"

var npc_id := 0
var npc_name := ""
var sprite: CharacterSprite
var _tag: Label3D


func setup(npc: Dictionary, res: Node, map: RoMap) -> void:
	npc_id = int(npc.id)
	npc_name = String(npc.name)
	var cell: Vector2i = npc.cell
	position = map.cell_to_world(cell.x, cell.y)
	var spr := SprFile.decode(res.read(NPC_DIR + String(npc.sprite) + ".spr"))
	var act := ActFile.decode(res.read(NPC_DIR + String(npc.sprite) + ".act"))
	if spr and act:
		sprite = CharacterSprite.new()
		sprite.actions = CharacterSprite.MONSTER_ACTIONS
		add_child(sprite)
		sprite.setup(spr, act)
		sprite.set_state(0, int(npc.get("direction", 0)))
	_tag = Label3D.new()
	_tag.text = npc_name.to_upper()
	_tag.font = UiTheme.font(600, 2)
	_tag.font_size = 44
	_tag.pixel_size = 0.06
	_tag.modulate = UiTheme.ACCENT
	_tag.outline_size = 10
	_tag.outline_modulate = Color(0.0, 0.03, 0.06, 0.85)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = false
	add_child(_tag)


func head_position() -> Vector3:
	return global_position + Vector3(0, (sprite.top_height() if sprite else 10.0) + 1.0, 0)


func _process(_delta: float) -> void:
	if _tag:
		_tag.position = Vector3(0, (sprite.top_height() if sprite else 10.0) + 3.0, 0)
