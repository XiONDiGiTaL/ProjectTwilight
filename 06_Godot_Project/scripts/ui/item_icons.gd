class_name ItemIcons
extends RefCounted
## Item icon and ground-sprite lookup from the user's client (read-only).
##   icon:   data\texture\유저인터페이스\item\<resname>.bmp
##   sprite: data\sprite\아이템\<resname>.spr / .act

const ICON_DIR := "data\\texture\\유저인터페이스\\item\\"
const SPRITE_DIR := "data\\sprite\\아이템\\"

static var _icons: Dictionary = {}


static func _res() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("RoResources")


static func icon(def: Dictionary) -> Texture2D:
	var resname := String(def.get("resname", ""))
	if resname == "":
		return null
	if _icons.has(resname):
		return _icons[resname]
	var res := _res()
	var tex: Texture2D = null
	if res:
		var path := ICON_DIR + resname + ".bmp"
		var img := TextureLoader.load_image(res.read(path), path)
		if img:
			tex = ImageTexture.create_from_image(img)
	_icons[resname] = tex
	return tex


## Returns [SprFile, ActFile] for the ground sprite, or [] if missing.
static func ground_sprite(def: Dictionary) -> Array:
	var res := _res()
	var resname := String(def.get("resname", ""))
	if res == null or resname == "":
		return []
	var spr := SprFile.decode(res.read(SPRITE_DIR + resname + ".spr"))
	var act := ActFile.decode(res.read(SPRITE_DIR + resname + ".act"))
	return [spr, act] if spr and act else []
