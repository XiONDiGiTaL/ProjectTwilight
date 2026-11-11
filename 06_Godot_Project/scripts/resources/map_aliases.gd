class_name MapAliases
extends RefCounted
## Maps that scripts refer to by a classic name the player's client no longer
## ships. Modern kRO clients renamed the Pre-Renewal Novice Training Grounds
## new_1-1 ... new_5-4 to new_zone01 ... new_zone04 (one set for all five
## copies). Evidence: every NPC, spawn and portal cell rAthena's pre-re
## novice.txt and jobquests.txt use on new_1-1..4 is walkable on
## new_zone01..04 (see REVERSE_ENGINEERING_LOG.md). The logical name stays in
## scripts, warps and saves; only the files are read from the alias.


## Client map whose files to load for `map_name`.
static func client_map(res: Node, map_name: String) -> String:
	if res == null or res.exists("data/%s.gat" % map_name):
		return map_name
	var alias := _alias(map_name)
	if alias != "" and res.exists("data/%s.gat" % alias):
		return alias
	return map_name


## True if the client can load `map_name` (directly or through an alias).
static func exists(res: Node, map_name: String) -> bool:
	return res != null and res.exists("data/%s.gat" % client_map(res, map_name))


static func _alias(map_name: String) -> String:
	# new_<copy>-<room>, copy 1..5, room 1..4 -> new_zone0<room>
	var re := RegEx.new()
	re.compile("^new_([1-5])-([1-4])$")
	var m := re.search(map_name)
	if m:
		return "new_zone0%s" % m.get_string(2)
	return ""
