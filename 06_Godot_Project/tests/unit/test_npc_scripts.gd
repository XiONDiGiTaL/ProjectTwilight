extends RefCounted
## rAthena-format NPC scripts: parser, interpreter, Project Twilight service
## NPCs and (when the resource pack has rAthena's npc folder) the real
## rAthena custom scripts. Runs headless through RaHost.


static func _gat(w := 60, h := 60) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _player(sim: FieldSimulation) -> SimUnit:
	var p := sim.add_player("Scripter", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	p.zeny = 5000
	return p


## Loads `text` as a script file and runs the NPC `name` with scripted answers.
static func _run(text: String, name: String, answers: Array = [], sim: FieldSimulation = null, p: SimUnit = null) -> Array:
	var world := RaWorld.new()
	world.load_text(text, "test")
	world._resolve_duplicates()
	if sim == null:
		sim = FieldSimulation.new(_gat(), 3)
	if p == null:
		p = _player(sim)
	var host := RaHost.new()
	host.answers = answers.duplicate()
	var vm := RaInterpreter.new(world, host, sim, p, world.find_npc(name))
	await vm.run()
	return [host, vm, p, world]


func test_parser_and_expressions(_t) -> Variant:
	var src := "prontera,1,1,4\tscript\tCalc\t4_F_KAFRA1,{\n" + \
		"\t.@a = 2 + 3 * 4;\n\tset .@b$, (.@a > 10) ? \"big\" : \"small\";\n\t.@c += 5; .@c++;\n" + \
		"\tsetarray .@arr[0], 7, 8, 9;\n\tfor (.@i = 0; .@i < getarraysize(.@arr); .@i++) .@sum += .@arr[.@i];\n" + \
		"\tmes .@a + \" \" + .@b$ + \" \" + .@c + \" \" + .@sum + \" \" + (1 << 4 | 1) + \" \" + callfunc(\"F_InsertComma\", 1234567);\n\tclose;\n}\n"
	var r: Array = await _run(src, "Calc")
	var host: RaHost = r[0]
	var vm: RaInterpreter = r[1]
	if vm.error != "":
		return vm.error
	return true if host.transcript.has("14 big 6 24 17 1,234,567") else "transcript: %s" % [host.transcript]


func test_menu_labels_switch_and_functions(_t) -> Variant:
	var src := "-\tscript\tMenu\t-1,{\n" + \
		"function Add;\n" + \
		"\tmenu \"One\",L_One,\"Two\",L_Two;\n" + \
		"L_One:\n\tmes \"one\";\n\tend;\n" + \
		"L_Two:\n\tswitch (select(\"a:b:c\")) {\n\tcase 1: mes \"A\"; break;\n\tcase 3: mes \"C=\" + Add(2, 3); break;\n\tdefault: mes \"other\";\n\t}\n\tcallsub S_Sub, 4;\n\tend;\n" + \
		"S_Sub:\n\tmes \"sub \" + getarg(0);\n\treturn;\n" + \
		"function Add {\n\treturn getarg(0) + getarg(1);\n}\n}\n"
	var r: Array = await _run(src, "Menu", [2, 3])
	var host: RaHost = r[0]
	var vm: RaInterpreter = r[1]
	if vm.error != "":
		return vm.error
	var t: Array = host.transcript
	if not t.has("C=5") or not t.has("sub 4") or t.has("one"):
		return "flow wrong: %s" % [t]
	# Cancelling a menu ends the script.
	var r2: Array = await _run(src, "Menu", [])
	return true if not (r2[0] as RaHost).transcript.has("one") else "cancel did not stop the script"


func test_variables_persist_on_character(_t) -> Variant:
	var src := "-\tscript\tVars\t-1,{\n\tvisits = visits + 1;\n\t@temp = 9;\n\tlastmap$ = \"prontera\";\n\tend;\n}\n"
	var sim := FieldSimulation.new(_gat(), 4)
	var p := _player(sim)
	await _run(src, "Vars", [], sim, p)
	await _run(src, "Vars", [], sim, p)
	if int(p.script_vars.get("visits", {}).get(0, 0)) != 2:
		return "permanent var not kept: %s" % [p.script_vars]
	var data := SaveGame.capture(p, "prontera")
	var back := SaveGame.validate(JSON.parse_string(JSON.stringify(data)), FieldSimulation._load_json(FieldSimulation.ITEM_DB), ClassInsignia.classes())
	var q := FieldSimulation.new(_gat(), 5).add_player_from_save(back.character)
	return true if int(q.script_vars.get("visits", {}).get(0, 0)) == 2 and String(q.script_vars.get("lastmap$", {}).get(0, "")) == "prontera" else "script vars not saved"


func test_twilight_services(_t) -> Variant:
	var world := RaWorld.new()
	world.load_all(null)
	if not world.errors.is_empty():
		return "script errors: %s" % [world.errors]
	var sim := FieldSimulation.new(_gat(), 6)
	var p := _player(sim)
	# Healer.
	p.hp = 1
	var host := RaHost.new()
	await RaInterpreter.new(world, host, sim, p, world.find_npc("Healer#tw_prt")).run()
	if p.hp != p.max_hp:
		return "healer did not heal (pack healer loaded? %s)" % [world.loaded_files]
	# Job Master: novice -> swordman.
	p.job_level = 10
	p.skills.NV_BASIC = 9
	host = RaHost.new()
	host.answers = [1]
	await RaInterpreter.new(world, host, sim, p, world.find_npc("Job Master#tw")).run()
	if p.job != "swordman":
		return "job master did not change job: %s" % [host.transcript]
	# Job Master: swordman 40 -> dark knight.
	p.job_level = 40
	host = RaHost.new()
	host.answers = [1]
	await RaInterpreter.new(world, host, sim, p, world.find_npc("Job Master#tw")).run()
	if p.job != "dark_knight":
		return "dark knight change failed: %s" % [host.transcript]
	# Stylist: hair colour next, then keep.
	var before := p.hair_color
	host = RaHost.new()
	host.answers = [2, 1, 4]
	await RaInterpreter.new(world, host, sim, p, world.find_npc("Stylist#tw")).run()
	if p.hair_color != before + 1:
		return "stylist hair colour %d -> %d" % [before, p.hair_color]
	# Reset: skills.
	p.skills.DK_BLOODYCRASH = 3
	var pts := p.skill_points
	host = RaHost.new()
	host.answers = [1]
	await RaInterpreter.new(world, host, sim, p, world.find_npc("Reset Master#tw")).run()
	if p.skill_points < pts + 3 or int(p.skills.DK_BLOODYCRASH) != 0:
		return "reset skills failed"
	return true


func test_rathena_custom_scripts(_t) -> Variant:
	var pack := Settings_path()
	if pack == "" or not FileAccess.file_exists(pack.path_join("rathena/npc/custom/healer.txt")):
		return "SKIP rAthena npc folder not in the resource pack"
	var world := RaWorld.new()
	for f in ["other/Global_Functions.txt", "custom/healer.txt", "custom/warper.txt", "custom/jobmaster.txt",
			"custom/platinum_skills.txt", "custom/stylist.txt", "custom/breeder.txt", "custom/resetnpc.txt"]:
		world.load_text(FileAccess.get_file_as_string(pack.path_join("rathena/npc/" + f)), f)
	world._resolve_duplicates()
	if not world.errors.is_empty():
		return "rAthena parse errors: %s" % [world.errors.slice(0, 5)]
	var sim := FieldSimulation.new(_gat(), 7)
	var p := _player(sim)
	# OnInit for the job master (sets its config variables).
	var jm := world.find_npc("Job Master")
	await RaInterpreter.new(world, RaHost.new(), sim, p, jm).run("OnInit")
	# Healer (rAthena): percentheal 100,100.
	p.hp = 1
	var host := RaHost.new()
	var vm := RaInterpreter.new(world, host, sim, p, world.find_npc("Healer#prt"))
	await vm.run()
	if p.hp != p.max_hp or vm.error != "":
		return "rAthena healer failed: %s %s" % [vm.error, host.transcript]
	# Warper: Towns -> Geffen.
	host = RaHost.new()
	host.answers = [2, 13]
	vm = RaInterpreter.new(world, host, sim, p, world.find_npc("Warper"))
	await vm.run()
	if host.warps.is_empty() or String(host.warps[0][0]) != "geffen":
		return "rAthena warper: %s %s %s" % [vm.error, host.warps, host.transcript.slice(0, 4)]
	if String(p.script_vars.get("lastwarp$", {}).get(0, "")) != "geffen":
		return "warper did not remember the last warp"
	# Platinum skills.
	p.skills.erase("NV_FIRSTAID")
	host = RaHost.new()
	host.answers = [1]
	vm = RaInterpreter.new(world, host, sim, p, world.find_npc("Platinum Skill NPC"))
	await vm.run()
	if int(p.skills.get("NV_FIRSTAID", 0)) != 1:
		return "platinum skills: %s %s" % [vm.error, host.transcript]
	# Stylist: hairstyle, next, then cancel.
	host = RaHost.new()
	host.answers = [2, 1]
	vm = RaInterpreter.new(world, host, sim, p, world.find_npc("Stylist"))
	await vm.run()
	if p.hair_style != 2 or vm.error != "":
		return "rAthena stylist: style %d %s" % [p.hair_style, vm.error]
	# Job master: novice at job 10 -> first option.
	p.job_level = 10
	p.skills.NV_BASIC = 9
	host = RaHost.new()
	host.answers = [1, 1, 1, 1]
	vm = RaInterpreter.new(world, host, sim, p, jm)
	await vm.run()
	if p.job == "novice":
		return "rAthena job master did not change job: %s / %s" % [vm.error, host.transcript.slice(0, 12)]
	# Rental: no qualifying skill -> message, no crash.
	host = RaHost.new()
	vm = RaInterpreter.new(world, host, sim, p, world.find_npc("Universal Rental NPC"))
	await vm.run()
	return true if vm.error == "" else "rental: " + vm.error


static func Settings_path() -> String:
	var st: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	return st.resource_pack_path() if st else ""
