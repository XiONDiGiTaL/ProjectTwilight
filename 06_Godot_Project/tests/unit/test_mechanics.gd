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


func test_matk(_t) -> Variant:
	var v := StatRulesPreRenewal.matk_range(99)  # 99+14^2=295, 99+19^2=460
	return true if v == Vector2i(295, 460) else "got %s" % v
