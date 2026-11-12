extends Node
## Music and sound effects (autoload "GameAudio").
##
## Project Twilight ships no audio. Everything is read at run time from the
## player's own client: music from <client>/BGM/*.mp3 chosen by the client's
## data/mp3nametable.txt, effects from data/wav/*.wav inside the GRFs. A
## missing file is silently skipped, so the game runs the same without sound.
##
## Volumes (0..1) are stored in Settings under [audio].

const SFX_VOICES := 14
const MENU_TRACK := "01"
const FADE_SEC := 0.8
const BUTTON_SOUND := "버튼소리.wav"

## Hit sound by the attacker's weapon type.
const HIT_BY_WEAPON := {
	"dagger": "_hit_dagger.wav", "sword": "_hit_sword.wav", "two_hand_sword": "_hit_sword.wav",
	"katar": "_hit_dagger.wav", "spear": "_hit_spear.wav", "two_hand_spear": "_hit_spear.wav",
	"axe": "_hit_axe.wav", "two_hand_axe": "_hit_axe.wav", "mace": "_hit_mace.wav", "book": "_hit_mace.wav",
	"rod": "_hit_rod.wav", "staff": "_hit_rod.wav", "bow": "_hit_arrow.wav",
	"instrument": "_hit_mace.wav", "whip": "_hit_rod.wav",
}
const SWING_BY_WEAPON := {
	"dagger": "attack_short_sword.wav", "sword": "attack_sword.wav", "two_hand_sword": "attack_twohand_sword.wav",
	"katar": "attack_katar.wav", "spear": "attack_spear.wav", "two_hand_spear": "attack_spear.wav",
	"axe": "attack_axe.wav", "two_hand_axe": "attack_axe.wav", "mace": "attack_mace.wav", "book": "attack_book.wav",
	"rod": "attack_rod.wav", "staff": "attack_rod.wav", "bow": "attack_bow.wav", "whip": "attack_whip.wav",
}
const FIST_HITS := ["_hit_fist1.wav", "_hit_fist2.wav", "_hit_fist3.wav", "_hit_fist4.wav"]
const TAKEN_HITS := ["_enemy_hit_normal1.wav", "_enemy_hit_normal2.wav", "_enemy_hit_normal3.wav", "_enemy_hit_normal4.wav"]
const STATUS_SOUNDS := {
	"stun": "_stun.wav", "sleep": "_snore.wav", "stone": "_stonecurse.wav", "silence": "_silence.wav",
	"blind": "_blind.wav", "confusion": "_confusion.wav",
}
## Skill sound by code; the first key the code contains wins (checked in order).
const SKILL_SOUNDS := [
	["SONICBLOW", "effect/assasin_sonicblow.wav"], ["CROSSIMPACT", "effect/assasin_sonicblow.wav"],
	["MAGNUM", "effect/ef_magnumbreak.wav"], ["BOWLINGBASH", "effect/knight_bowling_bash.wav"],
	["AUTOCOUNTER", "effect/knight_autocounter.wav"], ["QUICKEN", "effect/knight_twohandquicken.wav"],
	["BOOMERANG", "effect/knight_spear_boomerang.wav"], ["SPEAR", "effect/knight_brandish_spear.wav"],
	["BASH", "effect/ef_bash.wav"], ["CRASH", "effect/ef_bash.wav"], ["GUILLOTINE", "effect/ef_bash.wav"],
	["FIREBOLT", "effect/ef_firearrow.wav"], ["COLDBOLT", "effect/ef_icearrow.wav"],
	["LIGHTNINGBOLT", "effect/ef_lightbolt.wav"], ["NAPALM", "effect/ef_napalmbeat.wav"],
	["SOULSTRIKE", "effect/ef_soulstrike.wav"], ["FIREWALL", "effect/ef_firewall.wav"],
	["FROST", "effect/ef_frostdiver.wav"], ["DIAMONDDUST", "effect/wizard_stormgust.wav"],
	["METEOR", "effect/wizard_meteor.wav"], ["COMET", "effect/wizard_meteor.wav"],
	["EARTHSPIKE", "effect/wizard_earthspike.wav"], ["HEAVENSDRIVE", "effect/wizard_earthspike.wav"],
	["EARTH", "effect/wizard_earthspike.wav"], ["THUNDER", "effect/ef_thunderstorm.wav"],
	["SANCTUARY", "effect/priest_sanctuary.wav"], ["MAGNUS", "effect/priest_magnus.wav"],
	["ASSUMPTIO", "effect/priest_kyrie_eleison_a.wav"], ["PROTECTION", "effect/priest_kyrie_eleison_a.wav"],
	["BLESSING", "effect/ef_blessing.wav"], ["PRAYER", "effect/priest_gloria.wav"],
	["WRATH", "effect/priest_impositio.wav"], ["MISTLETOE", "effect/priest_aspersio.wav"],
	["DARKWEAPON", "effect/priest_aspersio.wav"], ["COMFORT", "effect/priest_recovery.wav"],
	["HEAL", "_heal_effect.wav"], ["FIRSTAID", "_heal_effect.wav"], ["POTIONPITCHER", "_heal_effect.wav"],
	["HOLYLIGHT", "effect/ef_aqua.wav"], ["JUDGEMENT", "effect/priest_turn_undead.wav"],
	["DIVINE", "effect/priest_turn_undead.wav"], ["HOLYCROSS", "effect/priest_turn_undead.wav"],
	["GRANDCROSS", "effect/priest_magnus.wav"], ["RUWACH", "effect/ef_ruwach.wav"],
	["MAMMONITE", "effect/ef_coin2.wav"], ["ENVENOM", "effect/thief_invenom.wav"],
	["BLITZBEAT", "effect/hunter_blitzbeat.wav"], ["FALCON", "effect/hunter_blitzbeat.wav"],
	["ARROW", "attack_bow1.wav"], ["STRAFE", "attack_bow2.wav"], ["SHARPSHOOTING", "attack_bow2.wav"],
	["HAMMERFALL", "black_hammerfall.wav"], ["ENDURE", "effect/ef_endure.wav"],
]
const ELEMENT_SOUNDS := {
	"fire": "effect/ef_firearrow.wav", "water": "effect/ef_icearrow.wav", "wind": "effect/ef_lightbolt.wav",
	"earth": "effect/wizard_earthspike.wav", "holy": "effect/ef_aqua.wav", "ghost": "effect/ef_soulstrike.wav",
	"shadow": "effect/ef_napalmbeat.wav", "poison": "effect/ef_poisonattack.wav",
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _wav_cache: Dictionary = {}     # name -> AudioStreamWAV or null
var _last_play: Dictionary = {}     # name -> msec, to avoid stacking the same sound
var _table: Dictionary = {}         # map name -> track ("08")
var _table_loaded := false
var _track := ""
var _music_volume := 0.6
var _sfx_volume := 0.8
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		_music_volume = clampf(float(settings.get_value("audio", "bgm_volume", 0.6)), 0.0, 1.0)
		_sfx_volume = clampf(float(settings.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
	# Headless runs (tests, the co-op host test) stay silent and load nothing.
	enabled = DisplayServer.get_name() != "headless"
	get_tree().node_added.connect(_on_node_added)


func music_volume() -> float:
	return _music_volume


func sfx_volume() -> float:
	return _sfx_volume


func set_music_volume(v: float) -> void:
	_music_volume = clampf(v, 0.0, 1.0)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.set_value("audio", "bgm_volume", _music_volume)
	for p in [_music_a, _music_b]:
		if p.playing and p.volume_db > -40.0:
			p.volume_db = _db(_music_volume)


func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.set_value("audio", "sfx_volume", _sfx_volume)


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))


func _res() -> Node:
	var r := get_node_or_null("/root/RoResources")
	return r if r != null and r.is_mounted else null


# --- Music -------------------------------------------------------------------------

## Track number ("08") the client plays on a map, or "" when it has none.
func track_for_map(map_name: String) -> String:
	var res := _res()
	if res == null:
		return ""
	if not _table_loaded:
		_table_loaded = true
		_table = parse_table(Cp949.decode(res.read("data/mp3nametable.txt")) if res.exists("data/mp3nametable.txt") else "")
	var key := map_name.to_lower()
	if _table.has(key):
		return String(_table[key])
	var alias := String(MapAliases.client_map(res, map_name)).to_lower()
	return String(_table.get(alias, ""))


## Parses the client's mp3nametable.txt: `map.rsw#bgm\\08.mp3#` per line.
static func parse_table(text: String) -> Dictionary:
	var out := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("//"):
			continue
		var parts := line.split("#")
		if parts.size() < 2:
			continue
		var map_name := parts[0].strip_edges().to_lower().trim_suffix(".rsw").trim_suffix(".gat")
		var file := parts[1].strip_edges().replace("\\", "/").get_file().get_basename()
		if map_name != "" and file != "":
			out[map_name] = file
	return out


func play_map_music(map_name: String) -> void:
	play_track(track_for_map(map_name))


func play_menu_music() -> void:
	play_track(MENU_TRACK)


## Cross-fades to a BGM track ("08"); "" fades the music out.
func play_track(track: String) -> void:
	if not enabled or track == _track:
		return
	var res := _res()
	var stream: AudioStreamMP3 = null
	if track != "" and res != null:
		var data: PackedByteArray = res.read("BGM/%s.mp3" % track)
		if not data.is_empty():
			stream = AudioStreamMP3.new()
			stream.data = data
			stream.loop = true
	if track != "" and stream == null:
		return      # the client has no such file: keep what is playing
	_track = track
	var old := _music_a if _music_a.playing else _music_b
	var fresh := _music_b if old == _music_a else _music_a
	if old.playing:
		var out := create_tween()
		out.tween_property(old, "volume_db", -60.0, FADE_SEC)
		out.tween_callback(old.stop)
	if stream != null:
		fresh.stream = stream
		fresh.volume_db = -40.0
		fresh.play()
		create_tween().tween_property(fresh, "volume_db", _db(_music_volume), FADE_SEC)


func current_track() -> String:
	return _track


# --- Effects -----------------------------------------------------------------------

func _wav(name: String) -> AudioStreamWAV:
	if _wav_cache.has(name):
		return _wav_cache[name]
	var stream: AudioStreamWAV = null
	var res := _res()
	if res != null and res.exists("data/wav/" + name):
		var data: PackedByteArray = res.read("data/wav/" + name)
		if not data.is_empty():
			stream = AudioStreamWAV.load_from_buffer(data)
	_wav_cache[name] = stream
	return stream


func has_sound(name: String) -> bool:
	return enabled and _wav(name) != null


## Plays data/wav/<name>. `volume` scales the SFX volume; the same sound is
## not restarted within `gap_ms` (many hits in one frame would only add noise).
func play(name: String, volume := 1.0, gap_ms := 60) -> bool:
	if not enabled or name == "" or _sfx_volume <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -100000)) < gap_ms:
		return false
	var stream := _wav(name)
	if stream == null:
		return false
	_last_play[name] = now
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % SFX_VOICES
	p.stream = stream
	p.volume_db = _db(_sfx_volume * clampf(volume, 0.0, 1.5))
	p.play()
	return true


func play_any(names: Array, volume := 1.0) -> bool:
	return play(String(names[randi() % names.size()]), volume) if not names.is_empty() else false


## 0..1 by how far something is from the listener (cells); silent past `reach`.
static func falloff(distance_cells: float, reach := 22.0) -> float:
	return clampf(1.0 - distance_cells / reach, 0.0, 1.0)


func hit(weapon_type: String, volume := 1.0) -> void:
	if HIT_BY_WEAPON.has(weapon_type):
		play(String(HIT_BY_WEAPON[weapon_type]), volume)
	else:
		play_any(FIST_HITS, volume)


func swing(weapon_type: String, volume := 1.0) -> void:
	play(String(SWING_BY_WEAPON.get(weapon_type, "attack_fist.wav")), volume * 0.8)


func taken(volume := 1.0) -> void:
	play_any(TAKEN_HITS, volume)


## A monster's own voice: <sprite>_attack / _damage / _die .wav when the client has it.
func monster(sprite: String, action: String, volume := 1.0) -> bool:
	var base := sprite.to_lower()
	if base == "":
		return false
	return play("%s_%s.wav" % [base, action], volume, 120)


static func skill_sound(code: String, element := "") -> String:
	var c := code.to_upper()
	for pair in SKILL_SOUNDS:
		if c.contains(String(pair[0])):
			return String(pair[1])
	return String(ELEMENT_SOUNDS.get(element, ""))


func skill(code: String, element := "", volume := 1.0) -> void:
	var s := skill_sound(code, element)
	if s == "" or not play(s, volume):
		play("effect/ef_hit2.wav", volume * 0.8)


func status(status_name: String, volume := 1.0) -> void:
	play(String(STATUS_SOUNDS.get(status_name, "")), volume)


# --- UI ------------------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n is CheckBox) and not n.pressed.is_connected(_click):
		n.pressed.connect(_click)


func _click() -> void:
	play(BUTTON_SOUND, 0.7, 40)
