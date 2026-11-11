extends Node
## Persistent user settings (user://settings.cfg).
##
## The game never ships Gravity resources. Players point Project Twilight at their
## own legally obtained Ragnarok client directory, which is opened read-only.
## Resolution order for the client directory:
##   1. user://settings.cfg  [resources] client_path
##   2. TWILIGHT_RO_CLIENT environment variable
##   3. res://twilight.local.cfg [resources] client_path  (developer-local, git-ignored)

const SETTINGS_PATH := "user://settings.cfg"
const LOCAL_DEV_PATH := "res://twilight.local.cfg"

var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(SETTINGS_PATH)


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if not _cfg.has_section_key(section, key):
		return default
	return _cfg.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(SETTINGS_PATH)


func client_path() -> String:
	var p: String = _cfg.get_value("resources", "client_path", "")
	if p != "" and DirAccess.dir_exists_absolute(p):
		return p
	p = OS.get_environment("TWILIGHT_RO_CLIENT")
	if p != "" and DirAccess.dir_exists_absolute(p):
		return p
	var local := ConfigFile.new()
	if local.load(LOCAL_DEV_PATH) == OK:
		p = local.get_value("resources", "client_path", "")
		if p != "" and DirAccess.dir_exists_absolute(p):
			return p
	return ""


func set_client_path(p: String) -> void:
	set_value("resources", "client_path", p)
