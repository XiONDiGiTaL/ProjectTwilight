extends SceneTree
## Checks that music and effects really play from the player's client.
##   godot --path 06_Godot_Project -s res://tests/diag_audio_play.gd   (not headless)
## Starts the field on Prontera, reports the BGM track and the master-bus
## level, then probes every effect name the game uses.


func _initialize() -> void:
	_run.call_deferred()


var _max_peak := -200.0


## Waits and records the loudest master-bus level seen meanwhile.
func _wait(sec: float) -> void:
	_max_peak = -200.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
		_max_peak = maxf(_max_peak, maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0)))


func _peak() -> float:
	return _max_peak


func _run() -> void:
	var tmp := "user://audio_diag_saves/"
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + f)
	SaveGame.save_dir = tmp
	var ch := CharacterRules.new_character("Listener", true, 2, 0, CharacterRules.stats_from_pairs(5, 5, 5))
	ch.cell = [156, 187]
	ch.map = "prontera"
	ch.script_vars = {"TW_TRAIN_ASKED": {"0": 1}}
	SaveGame.write("slot1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var audio: Node = root.get_node("GameAudio")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(6.0)
	print("AUDIO menu track=", audio.current_track(), " peak dB=", snappedf(_peak(), 0.1))
	root.get_node("GameSession").slot = "slot1"
	change_scene_to_file("res://scenes/game/field.tscn")
	await _wait(6.0)
	print("AUDIO prontera track=", audio.current_track(), " (table says ", audio.track_for_map("prontera"), ") peak dB=", snappedf(_peak(), 0.1))
	for m in ["prt_fild08", "geffen", "payon", "new_1-1", "moc_fild01", "prt_sewb1"]:
		print("AUDIO table ", m, " -> ", audio.track_for_map(m))
	audio.set_music_volume(0.0)
	await _wait(1.2)
	print("AUDIO silence peak dB=", snappedf(_peak(), 0.1))
	audio.play("levelup.wav")
	await _wait(0.6)
	print("AUDIO levelup peak dB=", snappedf(_peak(), 0.1))
	var names := {}
	for table in [audio.HIT_BY_WEAPON, audio.SWING_BY_WEAPON, audio.STATUS_SOUNDS, audio.ELEMENT_SOUNDS]:
		for k in table:
			names[String(table[k])] = true
	for pair in audio.SKILL_SOUNDS:
		names[String(pair[1])] = true
	for n in audio.FIST_HITS + audio.TAKEN_HITS + ["levelup.wav", "effect/st_job_level_up.wav", "_heal_effect.wav", "die_male.wav",
			"effect/ef_portal.wav", "effect/ef_beginspell.wav", "effect/ef_hit2.wav", "20th_monster_die.wav", "attack_fist.wav",
			audio.BUTTON_SOUND, "poring_die.wav", "poring_damage.wav", "poring_attack.wav", "lunatic_die.wav", "fabre_die.wav"]:
		names[String(n)] = true
	var missing := []
	for n in names:
		if not audio.has_sound(n):
			missing.append(n)
	print("AUDIO effects probed=", names.size(), " missing=", missing)
	audio.set_music_volume(0.6)
	quit(0)
