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
var _feigning := false
var aura: PlayerAura
var body_source := ""   # client | pack | sheet | fallback (see PlayerSprites)
var name_tag: Label3D   # CPU adventurers show their name; the local player does not
var _tag_color := Color.WHITE


func build_player(res: Node, male: bool, hair_style: int, hair_color: int) -> bool:
	_male = male
	var sex := "남" if male else "여"
	var head := HEAD_DIR + "%s\\%d_%s" % [sex, hair_style, sex]
	var look := PlayerSprites.body_for(res, PlayerSprites.jobs(), unit.job, unit.sprite, male)
	var bspr: SprFile = look.spr
	var bact: ActFile = look.act
	if bspr == null or bact == null:
		return false
	body_source = String(look.source)
	var pal: PackedByteArray = res.read("data\\palette\\머리\\머리%d_%s_%d.pal" % [hair_style, sex, hair_color]) if hair_color >= 0 else PackedByteArray()
	sprite = CharacterSprite.new()
	sprite.actions = CharacterSprite.PLAYER_ACTIONS
	add_child(sprite)
	sprite.setup(bspr, bact, SprFile.decode(res.read(head + ".spr")), ActFile.decode(res.read(head + ".act")), pal,
		PlayerSprites.cloth_palette(res, String(look.sprite), male, unit.cloth_color) if look.source != "sheet" else PackedByteArray())
	if aura == null:
		aura = PlayerAura.new()
		add_child(aura)
	aura.set_style(unit.aura, unit.job)
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


## Weapon type -> Korean sprite suffix used by the client's job sprites.
const WEAPON_SPRITES := {"dagger": "단검", "sword": "검", "two_hand_sword": "양손검", "axe": "도끼", "two_hand_axe": "양손도끼", "rod": "롯드", "mace": "클럽", "book": "책"}
const JOB_SPRITE_DIR := "data/sprite/인간족/"
var _male := true
var _weapon_shown := ""


## Rebuilds a player's sprite (after a job change swaps the body).
func rebuild_player(res: Node) -> void:
	if sprite:
		sprite.queue_free()
		sprite = null
	_weapon_shown = "?"
	build_player(res, unit.male, unit.hair_style, unit.hair_color)
	update_weapon(res)


## Shows the equipped weapon on a player's sprite (the client's per-job weapon layer).
func update_weapon(res: Node) -> void:
	if sprite == null or not unit.is_player():
		return
	if unit.weapon_type == _weapon_shown:
		return
	_weapon_shown = unit.weapon_type
	if not WEAPON_SPRITES.has(unit.weapon_type):
		sprite.set_weapon(null, null)
		return
	var sex := "남" if _male else "여"
	var bases: Array = [JOB_SPRITE_DIR + "%s/%s_%s_%s" % [unit.sprite, unit.sprite, sex, WEAPON_SPRITES[unit.weapon_type]]]
	if body_source == "pack":
		bases = PlayerSprites.pack_weapon_paths(PlayerSprites.jobs(), unit.job, _male, WEAPON_SPRITES[unit.weapon_type])
	elif body_source == "sheet":
		bases = []   # sheet bodies draw their own staff
	for base in bases:
		if res.exists(base + ".spr"):
			sprite.set_weapon(SprFile.decode(res.read(base + ".spr")), ActFile.decode(res.read(base + ".act")))
			return
	sprite.set_weapon(null, null)


## Tints the sprite for visible statuses (stone grey, sleep / stun dim, blind dark).
func set_status_tint(u: SimUnit) -> void:
	if sprite == null:
		return
	var c := Color.WHITE
	if u.has_status("stone"):
		c = Color(0.55, 0.55, 0.58)
	elif u.has_status("stun") or u.has_status("sleep"):
		c = Color(0.8, 0.8, 0.95)
	elif u.has_status("dark_breath") or u.has_status("shadow_quicken") or u.has_status("dark_weapon"):
		c = Color(0.85, 0.7, 1.0)
	elif u.has_status("blind"):
		c = Color(0.65, 0.65, 0.75)
	sprite.modulate = Color(c, sprite.modulate.a)


## Floating name above the sprite, used for the CPU adventurers so the maps
## read like a populated world.
func set_name_tag(text: String, color := Color(0.72, 0.9, 1.0)) -> void:
	if name_tag == null:
		name_tag = Label3D.new()
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.no_depth_test = true
		name_tag.fixed_size = false
		name_tag.font = UiTheme.font(600, 1)
		var settings := get_node_or_null("/root/Settings")
		var name_scale: float = settings.overhead_name_scale() if settings else 1.0
		name_tag.font_size = maxi(10, roundi(40.0 * name_scale))
		name_tag.pixel_size = 0.045
		name_tag.outline_size = maxi(6, roundi(12.0 * name_scale))
		name_tag.outline_modulate = Color(0.02, 0.04, 0.08, 0.85)
		name_tag.render_priority = 2
		add_child(name_tag)
	_tag_color = color
	name_tag.modulate = color
	name_tag.text = text


## World position just above the sprite's head (for HP bars and text).
func head_position() -> Vector3:
	return global_position + Vector3(0, (sprite.top_height() if sprite else 8.0) + 3.5, 0)


func _process(delta: float) -> void:
	if unit == null or map == null or sprite == null:
		return
	position = map.cell_pos_to_world(unit.walker.position())
	var dir := PlayerAvatar.sprite_direction(unit.walker.direction, camera_yaw)
	if name_tag:
		name_tag.position = Vector3(0, sprite.top_height() + 7.0, 0)
		name_tag.modulate = Color(_tag_color, 0.4) if unit.dead else _tag_color
	if unit.dead:
		if aura:
			aura.visible = false
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
	# Play Dead holds the collapse frame without fading; getting up restores it.
	if unit.trickdead:
		if not _feigning:
			_feigning = true
			sprite.play_once("dead", 300.0, true)
		sprite.set_action("idle", dir)
		return
	if _feigning:
		_feigning = false
		sprite.reset_action()
	if aura:
		aura.visible = true
		aura.job = unit.job
		aura.style = unit.aura if PlayerAura.is_valid(unit.aura) else "class"
		aura.dim = 0.3 if unit.is_casting() else (0.6 if unit.sitting else 1.0)
	if unit.sitting:
		sprite.set_action("sit", dir)
		return
	if unit.is_casting():
		sprite.set_action("cast", dir)
		return
	sprite.set_action("walk" if unit.walker.is_moving() else "idle", dir)
