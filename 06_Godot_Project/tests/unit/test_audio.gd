extends RefCounted
## Audio lookups: the client's map -> BGM table, skill sound choice, falloff.

const GameAudio := preload("res://scripts/audio/game_audio.gd")


func test_bgm_table_parsing(_t) -> Variant:
	var text := "// comment\r\nprontera.rsw#bgm\\\\08.mp3#\r\nprt_fild08.rsw#bgm\\\\12.mp3#\r\n\r\nbroken line\r\nGEFFEN.RSW#BGM\\\\13.MP3#\r\n"
	var t := GameAudio.parse_table(text)
	if t.size() != 3:
		return "expected 3 maps, got %s" % [t]
	if String(t.get("prontera", "")) != "08" or String(t.get("prt_fild08", "")) != "12":
		return "wrong tracks: %s" % [t]
	return true if String(t.get("geffen", "")) == "13" else "map names and files should be case-insensitive: %s" % [t]


func test_skill_sounds(_t) -> Variant:
	if GameAudio.skill_sound("AS_SONICBLOW") != "effect/assasin_sonicblow.wav":
		return "sonic blow sound wrong"
	if GameAudio.skill_sound("MG_FIREBOLT", "fire") != "effect/ef_firearrow.wav":
		return "fire bolt sound wrong"
	# Magnum Break must not be caught by a shorter key.
	if GameAudio.skill_sound("SM_MAGNUM") != "effect/ef_magnumbreak.wav":
		return "magnum break sound wrong"
	if GameAudio.skill_sound("XX_UNKNOWN", "wind") != "effect/ef_lightbolt.wav":
		return "unknown skills fall back to the element"
	return true if GameAudio.skill_sound("XX_UNKNOWN") == "" else "unknown neutral skill should have no sound"


func test_every_skill_resolves_or_falls_back(_t) -> Variant:
	var db := FieldSimulation._load_json(FieldSimulation.SKILL_DB)
	var named := 0
	for code in db:
		if String(code).begins_with("_"):
			continue
		if GameAudio.skill_sound(String(code), String(db[code].get("element", ""))) != "":
			named += 1
	return true if named >= 40 else "only %d skills have a sound" % named


func test_falloff(_t) -> Variant:
	if GameAudioFalloff.at(0.0) != 1.0 or GameAudioFalloff.at(3.0) != 1.0:
		return "nearby sounds play at full volume"
	if GameAudioFalloff.at(100.0) != 0.0:
		return "distant sounds are silent"
	var mid := GameAudioFalloff.at(14.0)
	return true if mid > 0.3 and mid < 0.7 else "falloff should be gradual, got %f" % mid
