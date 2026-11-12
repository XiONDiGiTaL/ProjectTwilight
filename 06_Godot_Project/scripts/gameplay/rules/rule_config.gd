class_name RuleConfig
extends RefCounted
## Server-tunable rules: EXP / drop rates, autoloot and the level cap.
##
## Sources, lowest to highest priority:
##   1. res://data/config.json            defaults shipped with the game
##   2. user://server.cfg                 the player's own overrides
##   3. <server_root>/conf/battle/exp.conf, drops.conf, levels.conf
##      (rAthena / Hercules layout, when a server tree is present)
##
## Only a small, documented key set is read and every value is clamped, so a
## full rAthena config can be pointed at safely: unknown keys are ignored.
## This is the seed of the MMO mode's server configuration loader.

const DEFAULTS_PATH := "res://data/config.json"
const USER_PATH := "user://server.cfg"

var exp_rate := 100        # percent; 100 = Pre-Renewal baseline (data/config.json ships 5000 = 50x)
var job_exp_rate := 100
var drop_rate := 100
var autoloot := false
var max_level := 99
## Zeny charged once when a Twilight Kafra storage is opened; 0 = free.
## rAthena's own Kafra scripts charge their own fee argument instead.
var kafra_fee := 0
## Files that contributed values, for @rates / diagnostics.
var sources: Array = []

## Recognised keys -> field. rAthena and Hercules spell several of these
## differently, so both spellings are accepted.
const KEYS := {
	"exp_rate": "exp_rate", "base_exp_rate": "exp_rate",
	"job_exp_rate": "job_exp_rate",
	"drop_rate": "drop_rate", "item_rate_common": "drop_rate",
	"autoloot": "autoloot", "mob_autoloot": "autoloot",
	"max_level": "max_level", "max_base_level": "max_level",
	"kafra_fee": "kafra_fee", "storage_fee": "kafra_fee",
}


static func load_config(server_root := "") -> RuleConfig:
	var r := RuleConfig.new()
	r._read_json(DEFAULTS_PATH)
	if FileAccess.file_exists(USER_PATH):
		r._read_kv(FileAccess.get_file_as_string(USER_PATH), USER_PATH)
	if server_root != "":
		for f in ["conf/battle/exp.conf", "conf/battle/drops.conf", "conf/battle/levels.conf"]:
			var p := server_root.path_join(f)
			if FileAccess.file_exists(p):
				r._read_kv(FileAccess.get_file_as_string(p), f)
	r._clamp()
	return r


## Effective multipliers only, for compact HUD notices.
func rate_summary() -> String:
	return "EXP x%s   JOB x%s   DROP x%s" % [
		_rate_label(exp_rate), _rate_label(job_exp_rate), _rate_label(drop_rate)]


## One line for the @rates command.
func describe() -> String:
	return "%s   MAX LV %d   AUTOLOOT %s" % [
		rate_summary(), max_level, "ON" if autoloot else "OFF"]


## Percent value -> player-facing multiplier (5000 -> "50", 150 -> "1.5").
static func _rate_label(rate: int) -> String:
	if rate % 100 == 0:
		return str(rate / 100)
	var label := "%.2f" % (rate / 100.0)
	return label.trim_suffix("0").trim_suffix("0").trim_suffix(".")


## Applies one whole-number multiplier to Base EXP, Job EXP and drops. The
## Settings presets use this so all three economy rates stay in step.
func apply_rate_multiplier(multiplier: int) -> void:
	if multiplier <= 0:
		return
	var percent := clampi(multiplier * 100, 0, 10000)
	exp_rate = percent
	job_exp_rate = percent
	drop_rate = percent


func _read_json(path: String) -> void:
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return
	for k in parsed:
		if String(k).begins_with("_"):
			continue
		_apply(String(k), parsed[k], path.get_file())


## "key: value" / "key = value" lines, with // and # comments. This is the
## format of both user://server.cfg and rAthena's conf/battle files.
func _read_kv(text: String, source: String) -> void:
	var used := false
	for raw in text.split("\n"):
		var line := raw
		var cut := line.find("//")
		if cut >= 0:
			line = line.substr(0, cut)
		cut = line.find("#")
		if cut >= 0:
			line = line.substr(0, cut)
		line = line.strip_edges()
		if line == "" or line.begins_with("["):
			continue
		var at := line.find(":")
		if at < 0:
			at = line.find("=")
		if at <= 0:
			continue
		var key := line.substr(0, at).strip_edges().to_lower()
		var value := line.substr(at + 1).strip_edges()
		if _apply(key, value, source):
			used = true
	if used and not sources.has(source):
		sources.append(source)


func _apply(key: String, value: Variant, source: String) -> bool:
	var field: String = KEYS.get(key, "")
	if field == "":
		return false
	match field:
		"autoloot":
			autoloot = _as_bool(value)
		"exp_rate":
			exp_rate = clampi(_as_int(value, exp_rate), 0, 10000)
		"job_exp_rate":
			job_exp_rate = clampi(_as_int(value, job_exp_rate), 0, 10000)
		"drop_rate":
			drop_rate = clampi(_as_int(value, drop_rate), 0, 10000)
		"max_level":
			max_level = clampi(_as_int(value, max_level), 1, 999)
		"kafra_fee":
			kafra_fee = clampi(_as_int(value, kafra_fee), 0, 1000000)
	if not sources.has(source):
		sources.append(source)
	return true


static func _as_int(value: Variant, fallback: int) -> int:
	if value is bool:
		return 1 if value else 0
	if value is int or value is float:
		return int(value)
	var s := String(value).strip_edges()
	return int(s.to_float()) if s.is_valid_float() else fallback


static func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	var s := String(value).strip_edges().to_lower()
	return s in ["1", "true", "yes", "on", "enabled"]


func _clamp() -> void:
	exp_rate = clampi(exp_rate, 0, 10000)
	job_exp_rate = clampi(job_exp_rate, 0, 10000)
	drop_rate = clampi(drop_rate, 0, 10000)
	max_level = clampi(max_level, 1, 999)
	kafra_fee = clampi(kafra_fee, 0, 1000000)
