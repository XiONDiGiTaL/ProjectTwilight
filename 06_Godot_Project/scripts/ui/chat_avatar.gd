class_name ChatAvatar
extends Control
## Small square player portrait for the chat dock and DM popups.
##
## The portrait is composed from the player's real body + head sprites, so it
## works without a separate screenshot step. A saved portrait (including one
## captured from the field through the chat options) wins when present; the
## class badge is the fallback when the client data is unavailable.

const HEAD_DIR := "data/sprite/인간족/머리통/"
const SIZE := 40.0
static var _cache: Dictionary = {}

var _frame: PanelContainer
var _texture: TextureRect
var _fallback: ClassInsignia
var _contact: Dictionary = {}
var _key := ""


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = PanelContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.11, 0.86)
	sb.border_color = Color(UiTheme.ACCENT, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	_frame.add_theme_stylebox_override("panel", sb)
	add_child(_frame)
	_texture = TextureRect.new()
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_texture)
	_fallback = ClassInsignia.new()
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_fallback)


## Contact data uses the same shape as NetSession.directory().
func set_contact(contact: Dictionary) -> void:
	_contact = contact.duplicate(true)
	_refresh()


func contact() -> Dictionary:
	return _contact


func _refresh() -> void:
	var key := "%s|%s|%s|%d|%d|%d|%s" % [
		String(_contact.get("name", "")),
		String(_contact.get("job", "novice")),
		String(_contact.get("sprite", _contact.get("job_sprite", "초보자"))),
		int(_contact.get("hair_style", 0)),
		int(_contact.get("hair_color", 0)),
		int(_contact.get("cloth_color", 0)),
		String(_contact.get("portrait_path", "")),
	]
	if key == _key and (_texture.texture != null or _fallback.visible):
		return
	_key = key
	var tex := _texture_for(_contact)
	_texture.texture = tex
	_texture.visible = tex != null
	_fallback.visible = tex == null
	if tex == null:
		_fallback.set_class(String(_contact.get("job", "novice")))


static func _texture_for(contact: Dictionary) -> Texture2D:
	var path := String(contact.get("portrait_path", ""))
	if path != "" and FileAccess.file_exists(path):
		var saved := Image.load_from_file(ProjectSettings.globalize_path(path))
		if saved != null:
			saved.convert(Image.FORMAT_RGBA8)
			return ImageTexture.create_from_image(saved)
	var key := "%s|%s|%s|%d|%d|%d|%d" % [
		String(contact.get("job", "novice")),
		String(contact.get("sprite", contact.get("job_sprite", "초보자"))),
		str(contact.get("male", true)),
		int(contact.get("hair_style", 0)),
		int(contact.get("hair_color", 0)),
		int(contact.get("cloth_color", 0)),
		int(contact.get("sex", 0)),
	]
	if _cache.has(key):
		return _cache[key]
	var tex := _render_portrait(contact)
	if tex != null:
		_cache[key] = tex
	return tex


static func _render_portrait(contact: Dictionary) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	var res: Node = tree.root.get_node_or_null("RoResources") if tree else null
	if res == null or not res.is_mounted:
		return null
	var male := bool(contact.get("male", true))
	var sex := "남" if male else "여"
	var job := String(contact.get("job", "novice"))
	var sprite := String(contact.get("sprite", contact.get("job_sprite", "초보자")))
	var look := PlayerSprites.body_for(res, PlayerSprites.jobs(), job, sprite, male)
	var body_spr: SprFile = look.get("spr")
	var body_act: ActFile = look.get("act")
	if body_spr == null or body_act == null:
		return null
	var head_base := HEAD_DIR + "%s/%d_%s" % [sex, int(contact.get("hair_style", 0)), sex]
	var head_spr := SprFile.decode(res.read(head_base + ".spr"))
	var head_act := ActFile.decode(res.read(head_base + ".act"))
	if head_spr == null or head_act == null:
		return null
	var hair_palette := PackedByteArray()
	if int(contact.get("hair_color", 0)) > 0:
		hair_palette = res.read("data/palette/머리/머리%d_%s_%d.pal" % [
			int(contact.get("hair_style", 0)), sex, int(contact.get("hair_color", 0))])
	var body_palette := PackedByteArray()
	if String(look.get("source", "")) != "sheet":
		body_palette = PlayerSprites.cloth_palette(res, String(look.get("sprite", sprite)), male, int(contact.get("cloth_color", 0)))
	var sprite_node := CharacterSprite.new()
	sprite_node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite_node.setup(body_spr, body_act, head_spr, head_act, hair_palette, body_palette)
	var source: Texture2D = sprite_node.texture
	if source == null:
		sprite_node.free()
		return null
	var img := source.get_image()
	sprite_node.free()
	if img == null:
		return null
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	# Crop the head and shoulders from the feet-relative composite. This keeps
	# the face readable at 40 px while preserving the character's silhouette.
	var w := img.get_width()
	var h := img.get_height()
	var crop_h := maxi(1, int(h * 0.62))
	var crop_w := mini(w, maxi(crop_h, int(w * 0.72)))
	var crop := img.get_region(Rect2i(maxi(0, (w - crop_w) / 2), 0, crop_w, crop_h))
	if crop.get_width() <= 0 or crop.get_height() <= 0:
		return null
	crop.resize(64, 64, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(crop)
