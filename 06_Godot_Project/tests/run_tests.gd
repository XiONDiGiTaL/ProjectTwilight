extends SceneTree
## Headless test runner.
##   godot --headless --path 06_Godot_Project -s res://tests/run_tests.gd
## Unit tests use synthetic fixtures only. Integration tests run when a client
## directory is configured (TWILIGHT_RO_CLIENT or twilight.local.cfg) and are
## reported as SKIPPED otherwise.

var _passed := 0
var _failed := 0
var _skipped := 0
var _current := ""


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	var suites := [
		preload("res://tests/unit/test_cp949.gd"),
		preload("res://tests/unit/test_spr_act.gd"),
		preload("res://tests/unit/test_invitation_code.gd"),
		preload("res://tests/unit/test_mechanics.gd"),
		preload("res://tests/unit/test_map_formats.gd"),
		preload("res://tests/unit/test_movement.gd"),
		preload("res://tests/unit/test_combat.gd"),
		preload("res://tests/unit/test_items.gd"),
		preload("res://tests/unit/test_equipment_shop.gd"),
		preload("res://tests/unit/test_character.gd"),
		preload("res://tests/unit/test_magic.gd"),
		preload("res://tests/unit/test_dark_knight.gd"),
		preload("res://tests/unit/test_shaman.gd"),
		preload("res://tests/unit/test_skills.gd"),
		preload("res://tests/unit/test_warps.gd"),
		preload("res://tests/unit/test_bots.gd"),
		preload("res://tests/unit/test_jobs.gd"),
		preload("res://tests/unit/test_npc_scripts.gd"),
		preload("res://tests/integration/test_client_grf.gd"),
		preload("res://tests/integration/test_client_maps.gd"),
	]
	for s in suites:
		var suite: Object = s.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			_current = "%s.%s" % [s.resource_path.get_file().get_basename(), name]
			var result = await suite.call(name, self)   # suites may be async (NPC scripts)
			if result is String and result.begins_with("SKIP"):
				_skipped += 1
				print("  SKIP  %s  (%s)" % [_current, result])
			elif result is bool and result:
				# Success must be an explicit `return true`; a script error makes
				# the call return null, which is counted as a failure.
				_passed += 1
				print("  PASS  %s" % _current)
			else:
				_failed += 1
				print("  FAIL  %s  -> %s" % [_current, str(result)])
	print("\n%d passed, %d failed, %d skipped" % [_passed, _failed, _skipped])
	quit(1 if _failed > 0 else 0)


## Helper used by suites: returns null on success or a failure message.
func check(cond: bool, msg: String) -> Variant:
	return null if cond else msg
