class_name CharacterPreview
extends SubViewportContainer
## Live character preview for menus: the client's body + head sprites composed
## by CharacterSprite in a private 3D viewport, turning through all 8
## directions (or walking) so the player sees their look from every side.

const TURN_SECONDS := 0.9
const BODY_DIR := "data/sprite/인간족/몸통/"
const HEAD_DIR := "data/sprite/인간족/머리통/"
## The old fixed 14-unit frame clipped tall hair at the top of the preview.
## Leave enough room for both the tallest head and the widest side profile.
const FRAME_MARGIN := 1.25
const MIN_FRAME_HEIGHT := 14.0

var walking := false
var _vp: SubViewport
var _sprite: CharacterSprite
var _cam: Camera3D
var _dir := 0
var _t := 0.0
var _key := ""
var _shape_key := ""
var _framed_shape := ""
var _framed_bounds := Vector2.ZERO


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = MIN_FRAME_HEIGHT
	_cam.position = Vector3(0, 5.5, 20)
	_vp.add_child(_cam)
	resized.connect(_frame_look)
	_sprite = CharacterSprite.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_vp.add_child(_sprite)


## Loads the look from the mounted client. job_sprite e.g. "초보자".
func set_look(male: bool, hair_style: int, hair_color: int, job_sprite := "초보자", cloth := 0, job := "") -> void:
	var key := "%s:%d:%d:%s:%d:%s" % [male, hair_style, hair_color, job_sprite, cloth, job]
	if key == _key:
		return
	_key = key
	# Hair/cloth palettes only recolor the same silhouette. Keep the measured
	# bounds when only a palette changes so steppers do not re-compose all 16
	# preview frames on every click.
	_shape_key = "%s:%d:%s:%s" % [male, hair_style, job_sprite, job]
	var res := get_node_or_null("/root/RoResources")
	if res == null or not res.is_mounted:
		return
	var sex := "남" if male else "여"
	var head := HEAD_DIR + "%s/%d_%s" % [sex, hair_style, sex]
	var pal: PackedByteArray = res.read("data/palette/머리/머리%d_%s_%d.pal" % [hair_style, sex, hair_color]) if hair_color > 0 else PackedByteArray()
	var look := PlayerSprites.body_for(res, PlayerSprites.jobs(), job, job_sprite, male)
	_sprite.setup(look.spr, look.act, SprFile.decode(res.read(head + ".spr")), ActFile.decode(res.read(head + ".act")), pal,
		PlayerSprites.cloth_palette(res, String(look.sprite), male, cloth) if look.source != "sheet" else PackedByteArray())
	_frame_look()
	# The container may receive its final size after the menu's first layout.
	# Re-frame once more so a tall hairstyle cannot be clipped at either end.
	_frame_look.call_deferred()


## Orthogonal frame height needed to show the whole composed character (feet
## through the tallest hair pixel), with a little breathing room. `size` on an
## orthogonal Camera3D is its vertical extent when KEEP_HEIGHT is set.
static func frame_height(sprite_height: float, sprite_width: float, aspect: float) -> float:
	var a := aspect if aspect > 0.01 else 300.0 / 380.0
	var needed := maxf(maxf(sprite_height, 0.0), maxf(sprite_width, 0.0) / a)
	return maxf(MIN_FRAME_HEIGHT, needed * FRAME_MARGIN)


func _frame_look() -> void:
	if _sprite == null or _sprite.texture == null or _cam == null:
		return
	var bounds := _framed_bounds
	if _shape_key != _framed_shape or bounds == Vector2.ZERO:
		bounds = _sprite.frame_bounds()
		if bounds == Vector2.ZERO:
			return
		_framed_shape = _shape_key
		_framed_bounds = bounds
	var aspect := _vp.size.x / maxf(_vp.size.y, 1.0)
	_cam.size = frame_height(bounds.y, bounds.x, aspect)
	_cam.position.y = bounds.y * 0.5


## True if the client has a head sprite for this style.
static func has_style(male: bool, hair_style: int) -> bool:
	var res := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RoResources")
	if res == null or not res.is_mounted:
		return false
	var sex := "남" if male else "여"
	return res.exists(HEAD_DIR + "%s/%d_%s.spr" % [sex, hair_style, sex])


func _process(delta: float) -> void:
	_t += delta
	if _t >= TURN_SECONDS:
		_t = 0.0
		_dir = (_dir + 1) % 8
	_sprite.set_state(CharacterSprite.Group.WALK if walking else CharacterSprite.Group.IDLE, _dir)
