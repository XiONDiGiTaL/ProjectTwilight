extends RefCounted
## Custom class art: Dread Knight/Abyss Knight use a local Thanatos-based
## sheet with class weapon layers, while Oracle and Spirit Sage reuse the
## client's fourth-job Arch Mage and Soul Ascetic bodies.

const MAP_PATH := "res://data/sprites/dread_knight_sheet.json"


func _job(id: String) -> Dictionary:
	return PlayerSprites.jobs().get(id, {})


func test_custom_class_sprite_assignments(_t) -> Variant:
	for id in ["dread_knight", "abyss_knight"]:
		var pack: Dictionary = _job(id).get("pack_sprite", {})
		if String(pack.get("kind", "")) != "sheet":
			return "%s is not assigned the Dread Knight sheet" % id
		if String(pack.get("file", "")) != "DreadKnight.png":
			return "%s sheet file is wrong" % id
		if String(pack.get("map", "")) != MAP_PATH:
			return "%s sheet map is wrong" % id
	if String(_job("oracle").get("sprite", "")) != "arch_mage":
		return "Oracle should reuse the Arch Mage body"
	if String(_job("spirit_sage").get("sprite", "")) != "soul_ascetic":
		return "Spirit Sage should reuse the Soul Ascetic body"
	if not FileAccess.file_exists(MAP_PATH):
		return "missing Dread Knight sheet map"
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not (map is Dictionary):
		return "Dread Knight sheet map is not valid JSON"
	if bool(map.get("has_head", true)):
		return "the Dread Knight sheet carries its own head and must not overlay one"
	if not bool(map.get("weapon_layer", false)):
		return "the Dread Knight sheet must draw the equipped weapon layer"
	var frames: Dictionary = map.get("frames", {})
	var groups: Dictionary = map.get("groups", {})
	if frames.is_empty() or groups.is_empty():
		return "Dread Knight sheet has no frames or groups"
	for group in 13:
		var g: Dictionary = groups.get(str(group), {})
		if g.is_empty():
			return "Dread Knight sheet is missing action group %d" % group
		var dirs: Dictionary = g.get("dirs", {})
		for direction in 8:
			var ids: Array = dirs.get(str(direction), [])
			if ids.is_empty():
				return "group %d direction %d is empty" % [group, direction]
			for id in ids:
				if not frames.has(id):
					return "group %d references missing frame %s" % [group, id]
	return true


func test_custom_bodies_load(t: SceneTree) -> Variant:
	var res = t.root.get_node_or_null("/root/RoResources")
	if res == null:
		return "SKIP no RoResources autoload"
	if not res.is_mounted and not res.mount():
		return "SKIP no Ragnarok client configured"
	if not res.pack_file("DreadKnight.png"):
		return "SKIP DreadKnight.png is not installed in the resource pack"
	var jobs := PlayerSprites.jobs()
	for id in ["dread_knight", "abyss_knight"]:
		var j: Dictionary = jobs[id]
		for male in [true, false]:
			var sex := "male" if male else "female"
			var look := PlayerSprites.body_for(res, jobs, id, String(j.get("sprite", "")), male)
			if String(look.get("source", "")) != "sheet":
				return "%s %s did not use the local sheet: %s" % [id, sex, look.get("source", "none")]
			if bool(look.get("has_head", true)) or not bool(look.get("weapon_layer", false)):
				return "%s %s sheet flags are wrong" % [id, sex]
			if look.act == null or look.act.actions.size() != 104:
				return "%s %s sheet should build 13 x 8 actions" % [id, sex]
			if look.spr == null or look.spr.frame_count() < 100:
				return "%s %s sheet has too few frames" % [id, sex]
			for action in look.act.actions:
				if action.frames.is_empty():
					return "%s %s sheet has an empty action" % [id, sex]
			for suffix in ["검", "도끼"]:
				if not _any_exists(res, PlayerSprites.weapon_paths(jobs, id, male, suffix)):
					return "%s %s has no %s weapon layer" % [id, sex, suffix]
	for spec in [["oracle", "arch_mage"], ["spirit_sage", "soul_ascetic"]]:
		var id: String = spec[0]
		var body: String = spec[1]
		var look := PlayerSprites.body_for(res, jobs, id, body, false)
		if String(look.get("source", "")) != "client":
			return "%s did not use the client's %s body" % [id, body]
		if not bool(look.get("has_head", false)):
			return "%s should keep the player head" % id
		if look.act == null or look.act.actions.size() < 104:
			return "%s body has too few actions" % id
		if not _any_exists(res, PlayerSprites.weapon_paths(jobs, id, false, "롯드")):
			return "%s has no rod weapon layer" % id
	return true


func _any_exists(res: Node, bases: Array) -> bool:
	for base in bases:
		if res.exists(base + ".spr") and res.exists(base + ".act"):
			return true
	return false
