class_name CharacterSprite
extends Sprite3D
## Camera-facing billboard that composes classic body + head sprites.
##
## The head is attached through ACT anchors:
##   head_offset = body_frame.anchors[0] - head_frame.anchors[0]
## Each (action, frame) composite is built once with Image.blend_rect and cached.
## Image origin = the character's feet (ACT layer positions are feet-relative).
##
## Rendering only: gameplay state comes from a GridWalker or the network.

const PIXELS_PER_CELL := 35.0  # sprite pixels per GAT cell (Medium confidence, tuned visually)
const GAT_CELL_UNITS := 5.0

enum Group { IDLE = 0, WALK = 1, SIT = 2, PICKUP = 3, READY = 4, ATTACK = 5, HURT = 6, DEAD = 8 }

var body_spr: SprFile
var body_act: ActFile
var head_spr: SprFile
var head_act: ActFile
var hair_palette := PackedByteArray()
var body_palette := PackedByteArray()   # cloth dye (empty = sprite's own)

var group := Group.IDLE
var direction := 0  # sprite-space direction (already adjusted for camera yaw)

var _frame := 0
var _elapsed := 0.0
var _cache: Dictionary = {}  # "action:frame" -> {texture, origin: Vector2i}
var _shown_key := ""


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	shaded = false
	double_sided = true
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel_size = GAT_CELL_UNITS / PIXELS_PER_CELL
	centered = true


func setup(p_body_spr: SprFile, p_body_act: ActFile, p_head_spr: SprFile = null,
		p_head_act: ActFile = null, p_hair_palette := PackedByteArray(), p_body_palette := PackedByteArray()) -> void:
	body_palette = p_body_palette
	body_spr = p_body_spr
	body_act = p_body_act
	head_spr = p_head_spr
	head_act = p_head_act
	hair_palette = p_hair_palette
	_cache.clear()
	_shown_key = ""
	_refresh()


var weapon_spr: SprFile
var weapon_act: ActFile


## Sets (or clears, with nulls) the weapon layer drawn with the body.
func set_weapon(p_spr: SprFile, p_act: ActFile) -> void:
	weapon_spr = p_spr
	weapon_act = p_act
	_cache.clear()
	_shown_key = ""
	_refresh()


## Action-name -> action group. Players and monsters number their groups differently.
const PLAYER_ACTIONS := {"idle": 0, "walk": 1, "sit": 2, "attack": 5, "hurt": 6, "dead": 8, "cast": 12}
const MONSTER_ACTIONS := {"idle": 0, "walk": 1, "attack": 2, "hurt": 3, "dead": 4}

var actions: Dictionary = PLAYER_ACTIONS
var _base_group := Group.IDLE
var _once_group := -1       # group playing once (attack/hurt), -1 = none
var _once_ms := 0.0         # total duration of the one-shot
var _hold_last := false     # keep the final frame (death)


## Changes the action group and/or direction; restarts the animation on group change.
func set_state(p_group: int, p_direction: int) -> void:
	_base_group = p_group
	if _once_group < 0 and not _hold_last and p_group != group:
		group = p_group
		_frame = 0
		_elapsed = 0.0
	direction = p_direction & 7


## Sets the looping base action by name ("idle", "walk").
func set_action(action: String, p_direction: int) -> void:
	set_state(actions.get(action, 0), p_direction)


## Plays an action once over `duration_ms` (0 = native ACT timing), then returns
## to the base action. With hold = true the last frame stays (death).
func play_once(action: String, duration_ms: float = 0.0, hold := false) -> void:
	if not actions.has(action) or body_act == null:
		return
	_once_group = actions[action]
	group = _once_group
	_frame = 0
	_elapsed = 0.0
	_hold_last = hold
	var frames: int = body_act.actions[_action_index()].frames.size()
	var native: float = maxf(body_act.actions[_action_index()].interval, 10.0) * frames
	_once_ms = duration_ms if duration_ms > 0.0 else native


## Returns to normal looping (e.g. when a dead unit respawns).
func reset_action() -> void:
	_once_group = -1
	_hold_last = false
	group = _base_group
	_frame = 0
	_elapsed = 0.0


## Height of the sprite's top above the feet, in world units (for HP bars).
func top_height() -> float:
	if texture == null or not _cache.has(_shown_key):
		return 8.0
	return float(texture.get_height()) * pixel_size


## Largest composed idle/walk frame in world units, measured across all eight
## directions. Menus use this to frame tall hair and side profiles without
## clipping; the current action is restored before returning.
func frame_bounds() -> Vector2:
	if body_spr == null or body_act == null:
		return Vector2.ZERO
	var saved_group := group
	var saved_dir := direction
	var saved_frame := _frame
	var out := Vector2.ZERO
	for g in [Group.IDLE, Group.WALK]:
		for d in 8:
			group = g
			direction = d
			_frame = 0
			_refresh()
			if texture != null:
				out.x = maxf(out.x, float(texture.get_width()) * pixel_size)
				out.y = maxf(out.y, float(texture.get_height()) * pixel_size)
	group = saved_group
	direction = saved_dir
	_frame = saved_frame
	_shown_key = ""
	_refresh()
	return out


func _process(delta: float) -> void:
	if body_act == null:
		return
	var act_idx := _action_index()
	var frames: Array = body_act.actions[act_idx].frames
	var n := frames.size()
	if _once_group >= 0:
		_elapsed += delta * 1000.0
		var t := _elapsed / maxf(_once_ms, 1.0)
		if t >= 1.0:
			if _hold_last:
				_frame = n - 1
			else:
				_once_group = -1
				group = _base_group
				_frame = 0
				_elapsed = 0.0
		else:
			_frame = mini(int(t * n), n - 1)
	elif group == Group.IDLE or group == Group.SIT:
		_frame = 0  # idle frames 0-2 are head turns, not an animation
	elif n > 1:
		var interval: float = maxf(body_act.actions[act_idx].interval, 10.0) / 1000.0
		_elapsed += delta
		while _elapsed >= interval:
			_elapsed -= interval
			_frame = (_frame + 1) % n
	_refresh()


func _action_index() -> int:
	return clampi(group * 8 + direction, 0, body_act.actions.size() - 1)


## Weapon ACTs use different action groups from the body.  Their attack and skill
## animations live at groups 4 and 10 (the body uses 5 and 12); the first weapon
## frame is reused while idle or walking so the equipped item stays visible.
func _weapon_action_index(body_act_idx: int) -> int:
	var group := body_act_idx / 8
	var dir := body_act_idx % 8
	match group:
		5:
			return 4 * 8 + dir
		12:
			return 10 * 8 + dir
		0, 1, 2, 3:
			return 4 * 8 + dir
	return -1


func _refresh() -> void:
	if body_act == null or body_spr == null:
		texture = null
		return
	var act_idx := _action_index()
	var frames: Array = body_act.actions[act_idx].frames
	if frames.is_empty():
		return
	var f := _frame % frames.size()
	var key := "%d:%d" % [act_idx, f]
	if key == _shown_key:
		return
	if not _cache.has(key):
		_cache[key] = _compose(act_idx, f)
	var entry: Dictionary = _cache[key]
	texture = entry.texture
	# Anchor the composite's bottom edge, not the ACT origin. RO frames carry
	# opaque shoe pixels below that origin, which a depth-tested ground clips.
	var size: Vector2 = entry.texture.get_size() if entry.texture else Vector2.ONE
	var origin: Vector2 = entry.origin
	offset = Vector2(size.x / 2.0 - origin.x, size.y / 2.0)
	_shown_key = key


## Builds the composite image for body action/frame plus the matching head frame.
func _compose(act_idx: int, f: int) -> Dictionary:
	var parts: Array = []  # [Image, Vector2i top_left (feet-relative)]
	var body_frame: Dictionary = body_act.actions[act_idx].frames[f]
	_collect(parts, body_spr, body_frame, Vector2i.ZERO, body_palette)
	if head_spr and head_act and act_idx < head_act.actions.size():
		var head_frames: Array = head_act.actions[act_idx].frames
		if not head_frames.is_empty():
			var head_frame: Dictionary = head_frames[f % head_frames.size()]
			var shift := Vector2i.ZERO
			if not body_frame.anchors.is_empty() and not head_frame.anchors.is_empty():
				shift = body_frame.anchors[0] - head_frame.anchors[0]
			_collect(parts, head_spr, head_frame, shift, hair_palette)
	var w_act_idx := _weapon_action_index(act_idx)
	if weapon_spr and weapon_act and w_act_idx >= 0 and w_act_idx < weapon_act.actions.size():
		var wframes: Array = weapon_act.actions[w_act_idx].frames
		if not wframes.is_empty():
			var wframe := f
			if act_idx / 8 <= 3:
				wframe = 0
			var wparts: Array = []
			_collect(wparts, weapon_spr, wframes[wframe % wframes.size()], Vector2i.ZERO, PackedByteArray())
			# Weapon goes behind the body when the character faces away (N, NE, NW).
			var dir := act_idx % 8
			if dir >= 3 and dir <= 5:
				parts = wparts + parts
			else:
				parts.append_array(wparts)
	if parts.is_empty():
		return {"texture": null, "origin": Vector2i.ZERO}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for p in parts:
		var img: Image = p[0]
		lo = Vector2i(mini(lo.x, p[1].x), mini(lo.y, p[1].y))
		hi = Vector2i(maxi(hi.x, p[1].x + img.get_width()), maxi(hi.y, p[1].y + img.get_height()))
	var canvas := Image.create_empty(maxi(1, hi.x - lo.x), maxi(1, hi.y - lo.y), false, Image.FORMAT_RGBA8)
	for p in parts:
		var img: Image = p[0]
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), p[1] - lo)
	return {"texture": ImageTexture.create_from_image(canvas), "origin": -lo}


func _collect(parts: Array, spr: SprFile, frame: Dictionary, shift: Vector2i, pal: PackedByteArray) -> void:
	for layer in frame.layers:
		if layer.sprite < 0:
			continue
		var tint: Color = layer.color
		if tint.a <= 0.01:
			continue  # fully faded layer (e.g. the end of a death splash)
		var src := spr.image_for(layer.sprite, layer.type, pal)
		if src == null:
			continue
		var img := src.duplicate() as Image
		if not tint.is_equal_approx(Color.WHITE):
			_tint(img, tint)
		if layer.mirror:
			img.flip_x()
		var sc: Vector2 = layer.scale
		if not sc.is_equal_approx(Vector2.ONE) and sc.x > 0.01 and sc.y > 0.01:
			img.resize(maxi(1, roundi(img.get_width() * sc.x)), maxi(1, roundi(img.get_height() * sc.y)), Image.INTERPOLATE_NEAREST)
		var tl: Vector2i = layer.pos + shift - Vector2i(img.get_width() / 2, img.get_height() / 2)
		parts.append([img, tl])


## Multiplies every pixel by the ACT layer colour (RGBA), as the client does.
static func _tint(img: Image, c: Color) -> void:
	var px := img.get_data()
	var r := c.r8
	var g := c.g8
	var b := c.b8
	var a := c.a8
	for i in range(0, px.size(), 4):
		px[i] = px[i] * r / 255
		px[i + 1] = px[i + 1] * g / 255
		px[i + 2] = px[i + 2] * b / 255
		px[i + 3] = px[i + 3] * a / 255
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)
