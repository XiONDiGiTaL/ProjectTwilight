extends RefCounted
## Integration tests against a real, user-supplied client. Read-only.

static var _grf: GrfArchive
static var _root := ""


static func _client() -> String:
	if _root != "":
		return _root
	var p := OS.get_environment("TWILIGHT_RO_CLIENT")
	if p == "":
		var cfg := ConfigFile.new()
		if cfg.load("res://twilight.local.cfg") == OK:
			p = cfg.get_value("resources", "client_path", "")
	_root = p
	return p


static func _archive() -> GrfArchive:
	if _grf == null:
		var root := _client()
		if root == "" or not FileAccess.file_exists(root.path_join("data.grf")):
			return null
		_grf = GrfArchive.new()
		var t0 := Time.get_ticks_msec()
		if _grf.open(root.path_join("data.grf")) != OK:
			push_error(_grf.last_error)
			_grf = null
			return null
		print("    [grf] indexed %d files in %d ms (v0x%X, collisions=%d)" % [
			_grf.entry_count(), Time.get_ticks_msec() - t0, _grf.version, _grf.key_collisions])
	return _grf


func test_grf_index(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	if g.entry_count() < 1000:
		return "suspiciously few entries: %d" % g.entry_count()
	if g.key_collisions != 0:
		return "case-folding collisions: %d" % g.key_collisions
	return true


func test_grf_read_gat(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	var key := GrfArchive.key_for("data\\prontera.gat")
	if not g.has_file(key):
		return "prontera.gat missing"
	var data := g.read(key)
	if data.size() != g.stat(key).size:
		return "size mismatch: %s" % g.last_error
	if data.slice(0, 4).get_string_from_ascii() != "GRAT":
		return "bad GAT magic"
	return true


func test_new_field_monster_sprites(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	for name in ["hornet", "pupa", "creamy", "poporing", "thief_bug", "rocker", "drops",
			"farmiliar", "condor", "spore", "thief_bug_egg", "thief_bug_female", "thief_bug_male",
			"poison_spore", "desert_wolf_b", "drainliar", "plankton", "savage_babe", "tarou", "cramp"]:
		var base: String = "data\\sprite\\몬스터\\" + String(name)
		var spr := SprFile.decode(g.read(GrfArchive.key_for(base + ".spr")))
		var act := ActFile.decode(g.read(GrfArchive.key_for(base + ".act")))
		if spr == null or act == null:
			return "%s sprite/act did not decode: %s" % [name, g.last_error]
		if spr.frame_count() == 0 or act.actions.size() < 8:
			return "%s has spr frames %d, act actions %d" % [name, spr.frame_count(), act.actions.size()]
	return true


func test_decode_poring(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	var base := "data\\sprite\\몬스터\\poring"
	var spr := SprFile.decode(g.read(GrfArchive.key_for(base + ".spr")))
	var act := ActFile.decode(g.read(GrfArchive.key_for(base + ".act")))
	if spr == null or act == null:
		return "decode failed: %s" % g.last_error
	if spr.frame_count() == 0 or act.actions.size() < 8:
		return "unexpected counts spr=%d act=%d" % [spr.frame_count(), act.actions.size()]
	print("    [poring] spr v0x%X %d frames, act v0x%X %d actions" % [spr.version, spr.frame_count(), act.version, act.actions.size()])
	return true


func test_decode_novice_body(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	var base := "data\\sprite\\인간족\\몸통\\남\\초보자_남"
	var spr := SprFile.decode(g.read(GrfArchive.key_for(base + ".spr")))
	var act := ActFile.decode(g.read(GrfArchive.key_for(base + ".act")))
	if spr == null or act == null:
		return "decode failed: %s" % g.last_error
	var anchored: bool = not act.actions[0].frames[0].anchors.is_empty()
	print("    [novice] spr %d frames, act v0x%X %d actions, anchors=%s" % [spr.frame_count(), act.version, act.actions.size(), anchored])
	return true if anchored else "body frames should carry head anchors"


## Bulk decode a sample of every Nth sprite to catch format variants.
func test_bulk_sprite_sample(_t) -> Variant:
	var g := _archive()
	if g == null:
		return "SKIP no client configured"
	var names := g.list_raw_names()
	var tried := 0
	var bad: Array = []
	var versions := {}
	for i in range(0, names.size(), 97):
		var n: String = names[i]
		var key := GrfArchive.normalize(n)
		if key.ends_with(".spr"):
			var s := SprFile.new()
			tried += 1
			if not s._parse(g.read(key)):
				bad.append("%s: %s" % [Cp949.decode_latin1(n), s.last_error])
			else:
				versions["spr%x" % s.version] = versions.get("spr%x" % s.version, 0) + 1
		elif key.ends_with(".act"):
			var a := ActFile.new()
			tried += 1
			if not a._parse(g.read(key)):
				bad.append("%s: %s" % [Cp949.decode_latin1(n), a.last_error])
			else:
				versions["act%x" % a.version] = versions.get("act%x" % a.version, 0) + 1
	print("    [bulk] decoded %d sampled spr/act, failures=%d, versions=%s" % [tried, bad.size(), versions])
	if not bad.is_empty():
		return "first failures: %s" % str(bad.slice(0, 5))
	return true
