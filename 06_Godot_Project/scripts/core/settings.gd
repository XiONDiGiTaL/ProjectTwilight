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

## In-game presentation options. A negative hue means "keep the default UI".
const UI_HUE_DEFAULT := -1.0
const CHAT_WIDTH_MIN := 320.0
const CHAT_WIDTH_MAX := 720.0
const CHAT_WIDTH_DEFAULT := 372.0
const CHAT_WIDTH_STEP := 8.0
const CHAT_HEIGHT_MIN := 42.0
const CHAT_HEIGHT_MAX := 120.0
const CHAT_HEIGHT_DEFAULT := 42.0
const CHAT_HEIGHT_STEP := 4.0
const NAMES_FADE_DEFAULT := 1.2
const NAMES_FADE_MIN := 0.0
const NAMES_FADE_MAX := 4.0
const NAMES_FADE_STEP := 0.1
const CAMERA_DISTANCE_MIN := 80.0
const CAMERA_DISTANCE_MAX := 520.0
const CAMERA_DISTANCE_DEFAULT := 240.0
const CAMERA_DISTANCE_STEP := 10.0
const CAMERA_PITCH_MIN := 25.0
const CAMERA_PITCH_MAX := 75.0
const CAMERA_PITCH_DEFAULT := 50.0
const CAMERA_PITCH_STEP := 1.0
const CAMERA_YAW_MIN := 0.0
const CAMERA_YAW_MAX := 360.0
const CAMERA_YAW_DEFAULT := 0.0
const CAMERA_YAW_STEP := 5.0

## Server-rate presets offered in Settings, as effective multipliers.
## RuleConfig stores percentages, so 25 here means 2500 (25x).
const RATE_PRESETS := [1, 25, 50]
const RATE_PRESET_NONE := 0

signal overhead_name_scale_changed(scale: float)
signal ui_hue_changed(tint: Color)
signal chat_size_changed(size: Vector2)
signal name_display_changed(hover_only: bool, fade_seconds: float)
signal camera_view_changed(distance: float, pitch: float, yaw: float)
signal rate_preset_changed(multiplier: int)

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


func overhead_name_font(base: float, minimum := 8) -> int:
	return maxi(minimum, roundi(base * overhead_name_scale()))


func overhead_name_outline(base: float, minimum := 4) -> int:
	return maxi(minimum, roundi(base * overhead_name_scale()))


## UI hue tint. -1 means the untouched Twilight Glass palette.
func ui_hue() -> float:
	return clampf(float(get_value("ui", "hue", UI_HUE_DEFAULT)), -1.0, 1.0)


func ui_tint() -> Color:
	var hue := ui_hue()
	return Color.WHITE if hue < 0.0 else Color.from_hsv(hue, 0.32, 1.0)


func set_ui_hue(value: float) -> void:
	var hue := clampf(value, -1.0, 1.0)
	if hue >= 0.0:
		hue = snappedf(hue, 0.01)
	if is_equal_approx(hue, ui_hue()):
		return
	set_value("ui", "hue", hue)
	ui_hue_changed.emit(ui_tint())


func chat_size() -> Vector2:
	return Vector2(
		clampf(snappedf(float(get_value("ui", "chat_width", CHAT_WIDTH_DEFAULT)), CHAT_WIDTH_STEP), CHAT_WIDTH_MIN, CHAT_WIDTH_MAX),
		clampf(snappedf(float(get_value("ui", "chat_height", CHAT_HEIGHT_DEFAULT)), CHAT_HEIGHT_STEP), CHAT_HEIGHT_MIN, CHAT_HEIGHT_MAX))


func set_chat_size(size: Vector2) -> void:
	var next := Vector2(
		clampf(snappedf(size.x, CHAT_WIDTH_STEP), CHAT_WIDTH_MIN, CHAT_WIDTH_MAX),
		clampf(snappedf(size.y, CHAT_HEIGHT_STEP), CHAT_HEIGHT_MIN, CHAT_HEIGHT_MAX))
	if next.is_equal_approx(chat_size()):
		return
	set_value("ui", "chat_width", next.x)
	set_value("ui", "chat_height", next.y)
	chat_size_changed.emit(next)


func names_hover_only() -> bool:
	return bool(get_value("ui", "names_hover_only", false))


func names_fade_seconds() -> float:
	return clampf(snappedf(float(get_value("ui", "names_fade_seconds", NAMES_FADE_DEFAULT)), NAMES_FADE_STEP), NAMES_FADE_MIN, NAMES_FADE_MAX)


func set_names_hover_only(enabled: bool) -> void:
	if enabled == names_hover_only():
		return
	set_value("ui", "names_hover_only", enabled)
	name_display_changed.emit(enabled, names_fade_seconds())


func set_names_fade_seconds(seconds: float) -> void:
	var value := clampf(snappedf(seconds, NAMES_FADE_STEP), NAMES_FADE_MIN, NAMES_FADE_MAX)
	if is_equal_approx(value, names_fade_seconds()):
		return
	set_value("ui", "names_fade_seconds", value)
	name_display_changed.emit(names_hover_only(), value)


func camera_view() -> Vector3:
	return Vector3(
		clampf(snappedf(float(get_value("camera", "distance", CAMERA_DISTANCE_DEFAULT)), CAMERA_DISTANCE_STEP), CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX),
		clampf(snappedf(float(get_value("camera", "pitch", CAMERA_PITCH_DEFAULT)), CAMERA_PITCH_STEP), CAMERA_PITCH_MIN, CAMERA_PITCH_MAX),
		fposmod(float(get_value("camera", "yaw", CAMERA_YAW_DEFAULT)), 360.0))


func set_camera_view(distance: float, pitch: float, yaw: float) -> void:
	var next := Vector3(
		clampf(snappedf(distance, CAMERA_DISTANCE_STEP), CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX),
		clampf(snappedf(pitch, CAMERA_PITCH_STEP), CAMERA_PITCH_MIN, CAMERA_PITCH_MAX),
		fposmod(yaw, 360.0))
	var current := camera_view()
	if next.is_equal_approx(current):
		return
	set_value("camera", "distance", next.x)
	set_value("camera", "pitch", next.y)
	set_value("camera", "yaw", next.z)
	camera_view_changed.emit(next.x, next.y, next.z)


## The stored UI preset, or RATE_PRESET_NONE when the loaded server rule
## config is authoritative. Only known presets are accepted.
func rate_preset() -> int:
	var preset := int(get_value("rules", "rate_preset", RATE_PRESET_NONE))
	return preset if RATE_PRESETS.has(preset) else RATE_PRESET_NONE


## Remembers the chosen preset, or clears it for DEFAULT; the field applies the
## result live and on every load.
func set_rate_preset(multiplier: int) -> void:
	if multiplier != RATE_PRESET_NONE and not RATE_PRESETS.has(multiplier):
		return
	if multiplier == rate_preset():
		return
	set_value("rules", "rate_preset", multiplier)
	rate_preset_changed.emit(multiplier)


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
