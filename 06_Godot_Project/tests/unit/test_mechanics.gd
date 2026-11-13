extends RefCounted
## Golden values are well-documented Pre-Renewal reference numbers.


func test_total_status_points_at_99(_t) -> Variant:
	var v := StatRulesPreRenewal.total_status_points(99)
	return true if v == 1273 else "expected 1273, got %d" % v


func test_raise_cost_1_to_99(_t) -> Variant:
	var v := StatRulesPreRenewal.total_raise_cost(1, 99)
	return true if v == 628 else "expected 628, got %d" % v


func test_raise_cost_steps(_t) -> Variant:
	var r := StatRulesPreRenewal
	if r.raise_cost(1) != 2 or r.raise_cost(10) != 2 or r.raise_cost(11) != 3 or r.raise_cost(98) != 11:
		return "step costs wrong"
	return true if r.raise_cost(99) == -1 else "99 should be capped"


func test_status_atk(_t) -> Variant:
	# STR 90, DEX 30, LUK 10 melee -> 90 + 81 + 6 + 2 = 179
	var v := StatRulesPreRenewal.status_atk(90, 30, 10)
	return true if v == 179 else "expected 179, got %d" % v


func test_ranged_status_atk(_t) -> Variant:
	# DEX 90, STR 30, LUK 10 ranged -> 90 + 9^2 + 30/5 + 10/5 = 179.
	if StatRulesPreRenewal.status_atk(30, 90, 10, true) != 179:
		return "ranged status ATK wrong: %d" % StatRulesPreRenewal.status_atk(30, 90, 10, true)
	if StatRulesPreRenewal.status_atk(30, 90, 10, false) != 59:
		return "melee status ATK changed: %d" % StatRulesPreRenewal.status_atk(30, 90, 10, false)
	for wt in ["bow", "instrument", "whip"]:
		if not StatRulesPreRenewal.is_ranged_weapon(wt):
			return "%s should be DEX-primary" % wt
	for wt in ["fist", "dagger", "sword", "two_hand_sword", "axe", "mace", "rod"]:
		if StatRulesPreRenewal.is_ranged_weapon(wt):
			return "%s should be STR-primary" % wt
	return true


func test_player_soft_def_display(_t) -> Variant:
	# floor(VIT/2) + max(floor(VIT*0.3), floor(VIT^2/150) - 1).
	var cases := {1: 0, 10: 8, 30: 24, 50: 40, 99: 113}
	for vit in cases:
		var got := CombatRulesPreRenewal.player_soft_def(vit)
		if got != cases[vit]:
			return "VIT %d soft DEF expected %d, got %d" % [vit, cases[vit], got]
	return true


func test_soft_mdef(_t) -> Variant:
	# Pre-Renewal soft MDEF = INT + floor(VIT / 2).
	return true if ElementRulesPreRenewal.soft_mdef(50, 21) == 60 else "soft MDEF wrong: %d" % ElementRulesPreRenewal.soft_mdef(50, 21)


func test_matk(_t) -> Variant:
	var v := StatRulesPreRenewal.matk_range(99)  # 99+14^2=295, 99+19^2=460
	return true if v == Vector2i(295, 460) else "got %s" % v
