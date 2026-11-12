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

## Overhead name tags are world-space labels, so their scale is independent of
## the HUD. Keep the default restrained; players who prefer the old size can
## raise it from Settings.
const OVERHEAD_NAME_MIN := 0.5
const OVERHEAD_NAME_MAX := 1.25
const OVERHEAD_NAME_DEFAULT := 0.7
const OVERHEAD_NAME_STEP := 0.05

signal overhead_name_scale_changed(scale: float)

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


func overhead_name_scale_range() -> Vector2:
	return Vector2(OVERHEAD_NAME_MIN, OVERHEAD_NAME_MAX)


func overhead_name_scale() -> float:
	var value := float(get_value("ui", "overhead_name_scale", OVERHEAD_NAME_DEFAULT))
	return clampf(value, OVERHEAD_NAME_MIN, OVERHEAD_NAME_MAX)


func set_overhead_name_scale(value: float) -> void:
	var scaled := snappedf(clampf(value, OVERHEAD_NAME_MIN, OVERHEAD_NAME_MAX), OVERHEAD_NAME_STEP)
	if is_equal_approx(scaled, overhead_name_scale()):
		return
	set_value("ui", "overhead_name_scale", scaled)
	overhead_name_scale_changed.emit(scaled)


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


## Optional resource-pack folder (extra GRFs, loose sprite overlays, fonts,
## sprite sheets). Defaults to <repo>/Resources next to the Godot project, or
## <executable dir>/Resources in exported builds. Never copied or committed.
func resource_pack_path() -> String:
	var p: String = _cfg.get_value("resources", "pack_path", "")
	if p != "" and DirAccess.dir_exists_absolute(p):
		return p
	p = OS.get_environment("TWILIGHT_RESOURCE_PACK")
	if p != "" and DirAccess.dir_exists_absolute(p):
		return p
	for c in [ProjectSettings.globalize_path("res://").path_join("../Resources").simplify_path(),
			OS.get_executable_path().get_base_dir().path_join("Resources")]:
		if DirAccess.dir_exists_absolute(c):
			return c
	return ""


func set_client_path(p: String) -> void:
	set_value("resources", "client_path", p)
