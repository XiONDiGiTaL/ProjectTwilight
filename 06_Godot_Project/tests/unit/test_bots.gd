extends RefCounted
## CPU adventurers (BotBrain) and the minimap silhouette.
## Bots are ordinary player units: they act only through simulation commands,
## share combat / EXP / loot / death rules, and never touch the local save.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const MELEE := 0
const CASTER := 5
const SUPPORT := 6


static func _gat(w := 140, h := 140) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func _field(seed_value := 21) -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), seed_value)
	sim.map_name = "twilight_test"
	sim.respawn_cell = Vector2i(70, 70)
	return sim


func test_spawn_is_an_ordinary_player(_t) -> Variant:
	var sim := _field()
	var bot := BotBrain.spawn(sim, Vector2i(60, 60), 40, MELEE)
	if not bot.is_bot or not bot.is_player():
		return "a bot should be a player unit flagged is_bot"
	if bot.job != "swordman" or bot.level != 40:
		return "job/level wrong: %s %d" % [bot.job, bot.level]
	if bot.hp != bot.max_hp or bot.max_sp <= 0:
		return "bots should start at full HP/SP"
	if int(bot.equipment.get("weapon", 0)) != 1116:
		return "swordman bot should hold the Katana: %s" % str(bot.equipment)
	if int(bot.skills.get("NV_BASIC", 0)) != 9:
		return "bots must be able to sit (Basic Skill 9)"
	if not PlayerAura.is_valid(bot.aura) or bot.aura == "none":
		return "bot aura should be a real style: %s" % bot.aura
	return true if bot.save_map == "" else "bots have no cross-map save point"


func test_bot_hunts_and_kills(_t) -> Variant:
	var sim := _field(31)
	var bot := BotBrain.spawn(sim, Vector2i(70, 70), 30, MELEE)
	var mob := sim.add_monster("1002", Vector2i(73, 70), 0)
	if mob == null:
		return "test monster missing"
	sim.drain_events()
	var hits := 0
	var deaths := 0
	for i in 240:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "damage" and ev.src == bot.id:
				hits += 1
			elif ev.type == "death" and ev.id == mob.id:
				deaths += 1
	if hits == 0:
		return "the bot never attacked the monster"
	return true if deaths == 1 else "the bot should have killed the monster (%d deaths)" % deaths


func test_bot_picks_up_loot(_t) -> Variant:
	var sim := _field(101)
	var bot := BotBrain.spawn(sim, Vector2i(70, 70), 30, MELEE)
	var dropped := sim.spawn_ground_item(501, 1, Vector2i(73, 70))
	sim.drain_events()
	for i in 120:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "pickup" and ev.id == bot.id and ev.ground == dropped:
				return true
	return "the bot never picked up the loot lying beside it"


func test_bot_waits_to_be_revived(_t) -> Variant:
	var sim := _field(41)
	var bot := BotBrain.spawn(sim, Vector2i(70, 70), 20, MELEE)
	sim._kill(bot, bot)
	if not bot.dead or bot.respawn_in != BotBrain.BOT_REVIVE_MS:
		return "a fallen bot should wait for revival, not the 3 s player revive"
	sim.drain_events()
	sim.tick(BotBrain.BOT_REVIVE_MS - 1000.0)
	if not bot.dead:
		return "the bot revived too early"
	sim.tick(1500.0)
	if bot.dead or bot.hp != bot.max_hp:
		return "the bot should return to its save point at full HP"
	return true


func test_support_bot_heals_the_player(_t) -> Variant:
	var sim := _field(51)
	var healer := BotBrain.spawn(sim, Vector2i(70, 70), 40, SUPPORT)
	if healer.bot_role != "support" or int(healer.skills.get("SH_COMFORT", 0)) <= 0:
		return "support archetype should know Spiritual Comfort"
	var p := sim.add_player("Ally", Vector2i(73, 70), FLAT)
	p.hp = maxi(1, p.max_hp / 3)
	sim.drain_events()
	for i in 300:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "heal" and ev.id == p.id and ev.amount > 0:
				return true
	return "the healer bot never healed a nearby wounded player"


func test_support_bot_revives_the_fallen(_t) -> Variant:
	var sim := _field(61)
	var healer := BotBrain.spawn(sim, Vector2i(70, 70), 45, SUPPORT)
	var p := sim.add_player("Fallen", Vector2i(72, 70), FLAT)
	sim._kill(p, p)
	p.respawn_in = 999999.0   # offline auto-revive off: only the bot can help
	sim.drain_events()
	for i in 400:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "resurrect" and ev.id == p.id:
				return true
	return "the healer bot never used Spiritual Prayer on a fallen player"


func test_caster_picks_a_strong_element(_t) -> Variant:
	var sim := _field(71)
	var mage := BotBrain.spawn(sim, Vector2i(70, 70), 40, CASTER)
	var mob := sim.add_monster("1002", Vector2i(74, 70), 0)   # water 1: wind hurts most
	sim.drain_events()
	for i in 200:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "cast_start" and ev.id == mage.id:
				return true if ev.skill == "MG_LIGHTNINGBOLT" else "picked %s against water" % ev.skill
	return true if mob == null else "the mage never started casting"


func test_populate_is_unique_and_avoidant(_t) -> Variant:
	var sim := _field(81)
	sim.add_monster("1002", Vector2i(20, 20), 0)
	var bots := BotBrain.populate(sim, 3, BotBrain.map_level(sim), Vector2i(70, 70))
	if bots.size() != 3:
		return "expected 3 bots, got %d" % bots.size()
	var names := {}
	for b in bots:
		if not b.is_bot:
			return "populate should only create bots"
		names[b.name] = true
		if FieldSimulation._chebyshev(b.walker.cell, Vector2i(70, 70)) < 14:
			return "a bot spawned on top of the player"
	return true if names.size() == 3 else "bot names should be unique on a map"


func test_bots_never_take_portals(_t) -> Variant:
	var sim := _field(91)
	sim.warps = [{"cell": Vector2i(60, 60), "span": Vector2i(1, 1), "to_map": "prontera",
		"to_cell": Vector2i(156, 191), "label": "Prontera"}]
	var bot := BotBrain.spawn(sim, Vector2i(60, 60), 20, MELEE)
	sim.drain_events()
	for i in 40:
		sim.tick(100.0)
		for ev in sim.drain_events():
			if ev.type == "warp" and ev.id == bot.id:
				return "a CPU adventurer must not be warped off the map"
	return true if not bot.warping else "bot is stuck in a warp"


func test_minimap_silhouette(_t) -> Variant:
	var img := Minimap.build_image(_gat(320, 240))
	if img == null:
		return "minimap should build an image"
	if img.get_width() > Minimap.MAX_TEX or img.get_height() > Minimap.MAX_TEX:
		return "minimap image should be downsampled (%dx%d)" % [img.get_width(), img.get_height()]
	if img.get_pixel(0, 0).a <= 0.0:
		return "minimap cells should be opaque"
	return true
