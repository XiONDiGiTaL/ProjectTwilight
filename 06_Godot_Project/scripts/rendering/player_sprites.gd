class_name PlayerSprites
extends RefCounted
## Resolves the body sprite (and weapon layer) for a player's job.
##
## * Client jobs: data/sprite/인간족/몸통/<sex>/<sprite>_<sex>.spr/.act
## * jobs.json "pack_sprite" (resource pack, never committed):
##     {"kind": "spr", "name": "운영자"}  body from the pack (overlay / pack GRF)
##     {"kind": "sheet", "file": "Shaman.jpg", "map": "res://data/sprites/..."}
##       a sprite sheet image sliced at runtime into a synthetic SPR/ACT
##   When the pack file is missing, the job's client "sprite" is used instead
##   (a documented placeholder look).
## * Optional body palette (cloth dye): data/palette/몸/<sprite>_<sex>_<n>.pal

const BODY_DIR := "data/sprite/인간족/몸통/"
const PAL_DIR := "data/palette/몸/"

static var _sheet_cache: Dictionary = {}   # file -> [SprFile, ActFile]
static var _jobs: Dictionary = {}


static func jobs() -> Dictionary:
	if _jobs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/prerenewal/jobs.json"))
		if parsed is Dictionary:
			_jobs = parsed
	return _jobs


## Returns {"spr": SprFile, "act": ActFile, "sprite": String (client name used),
##          "source": "client"|"pack"|"sheet"|"fallback", "has_head": bool}
static func body_for(res: Node, job_db: Dictionary, job: String, client_sprite: String, male: bool) -> Dictionary:
	var sex := "남" if male else "여"
	var pack: Dictionary = job_db.get(job, {}).get("pack_sprite", {})
	match String(pack.get("kind", "")):
		"spr":
			var base := BODY_DIR + "%s/%s_%s" % [sex, pack.name, sex]
			if res.has_method("from_pack") and res.from_pack(base + ".spr"):
				var spr := SprFile.decode(res.read(base + ".spr"))
				var act := ActFile.decode(res.read(base + ".act"))
				if spr and act:
					return {"spr": spr, "act": act, "sprite": String(pack.name), "source": "pack", "has_head": true}
		"sheet":
			var built := sheet_body(res, String(pack.file), String(pack.map))
			if not built.is_empty():
				return {"spr": built[0], "act": built[1], "sprite": client_sprite, "source": "sheet", "has_head": true}
	var cbase := BODY_DIR + "%s/%s_%s" % [sex, client_sprite, sex]
	var cspr := SprFile.decode(res.read(cbase + ".spr"))
	var cact := ActFile.decode(res.read(cbase + ".act"))
	return {"spr": cspr, "act": cact, "sprite": client_sprite,
		"source": "client" if pack.is_empty() else "fallback", "has_head": true}


## Weapon layer for pack bodies (e.g. 운영자_남_검); "" when none.
static func pack_weapon_paths(job_db: Dictionary, job: String, male: bool, weapon_suffix: String) -> Array:
	var pack: Dictionary = job_db.get(job, {}).get("pack_sprite", {})
	if String(pack.get("kind", "")) != "spr":
		return []
	var sex := "남" if male else "여"
	var n := String(pack.name)
	return ["data/sprite/인간족/%s/%s_%s_%s" % [n, n, sex, weapon_suffix],
		"data/sprite/인간족/몸통/%s/%s_%s_%s" % [n, n, sex, weapon_suffix]]


## Body palette bytes for a cloth dye (0 = the sprite's own palette).
static func cloth_palette(res: Node, sprite: String, male: bool, dye: int) -> PackedByteArray:
	if dye <= 0:
		return PackedByteArray()
	return res.read(PAL_DIR + "%s_%s_%d.pal" % [sprite, "남" if male else "여", dye])


## Builds [SprFile, ActFile] from a sprite-sheet image and its frame map.
static func sheet_body(res: Node, file: String, map_path: String) -> Array:
	if _sheet_cache.has(file):
		return _sheet_cache[file]
	var path: String = res.pack_file(file) if res.has_method("pack_file") else ""
	if path == "" or not FileAccess.file_exists(map_path):
		return []
	var img := Image.load_from_file(path)
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	if img == null or not (map is Dictionary):
		return []
	img.convert(Image.FORMAT_RGBA8)
	var built := build_from_sheet(img, map)
	_sheet_cache[file] = built
	return built


## Slices `img` per `map` (see data/sprites/shaman_sheet.json) into a synthetic
## SPR (RGBA frames) and ACT (13 groups x 8 directions, feet-relative layers,
## head anchor at the neck).
static func build_from_sheet(img: Image, map: Dictionary) -> Array:
	var bgp: Array = map.get("bg_sample", [2, 2])
	var bg := img.get_pixel(int(bgp[0]), int(bgp[1]))
	var tol := float(map.get("key_tolerance", 54)) / 255.0
	var neck := int(map.get("neck_from_top", 14))
	var spr := SprFile.new()
	var index := {}    # frame id -> [sprite index, feet x offset, height, width]
	var frames: Dictionary = map.frames
	for id in frames:
		var r: Array = frames[id]
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var sub := img.get_region(rect)
		_key_out(sub, bg, tol)
		# Feet x: centre of the opaque pixels in the bottom 10 rows (keeps the
		# figure steady when a staff swings out to one side).
		var sum := 0.0
		var n := 0
		for y in range(maxi(0, sub.get_height() - 10), sub.get_height()):
			for x in sub.get_width():
				if sub.get_pixel(x, y).a > 0.5:
					sum += x
					n += 1
		var feet_x := sum / n if n > 0 else sub.get_width() / 2.0
		index[id] = [spr.rgba_frames.size(), feet_x, sub.get_height(), sub.get_width()]
		spr.rgba_frames.append(sub)
	var act := ActFile.new()
	act.version = 0x205
	var mirror_dirs: Array = map.get("mirror_dirs", [])
	var front_dirs: Array = map.get("front_dirs", [0, 1, 2, 6, 7])
	var groups: Dictionary = map.groups
	for g in 13:
		var gd: Dictionary = groups.get(str(g), groups.get("0"))
		for d in 8:
			var ids: Array
			if gd.has("dirs"):
				ids = gd.dirs.get(str(d), gd.dirs.get("0"))
			else:
				ids = gd.front if front_dirs.has(d) else gd.back
			var mirror := mirror_dirs.has(d)
			var fl: Array = []
			for id in ids:
				var e: Array = index.get(id, index.values()[0])
				var w := float(e[3])
				var h := int(e[2])
				var fx: float = e[1]
				var cx := w / 2.0 - fx   # image centre relative to the feet
				if mirror:
					cx = -cx
				var layer := {"pos": Vector2i(roundi(cx), -h / 2), "sprite": int(e[0]), "mirror": mirror,
					"color": Color.WHITE, "scale": Vector2.ONE, "rotation": 0, "type": 1}
				fl.append({"layers": [layer], "sound": -1, "anchors": [Vector2i(roundi(cx * 0.0), -h + neck)]})
			act.actions.append({"frames": fl, "interval": float(gd.get("interval", 150))})
	return [spr, act]


static func _key_out(sub: Image, bg: Color, tol: float) -> void:
	for y in sub.get_height():
		for x in sub.get_width():
			var c := sub.get_pixel(x, y)
			var d := maxf(absf(c.r - bg.r), maxf(absf(c.g - bg.g), absf(c.b - bg.b)))
			if d < tol:
				sub.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d < tol * 1.6:
				# JPEG fringe: fade it and pull the grey out of the edge.
				var k := (d - tol) / (tol * 0.6)
				sub.set_pixel(x, y, Color(c.r, c.g, c.b, k))
