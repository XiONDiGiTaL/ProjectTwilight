class_name RegenRulesPreRenewal
extends RefCounted
## Pre-Renewal natural HP/SP regeneration. Medium-high confidence (iRO Wiki
## classic "HP/SP Recovery"; rAthena pre-re status.cpp behaviour as reference).
##   HP: every 6 s standing / 3 s sitting:  max(1, floor(MaxHP / 200)) + floor(VIT / 5)
##   SP: every 8 s standing / 4 s sitting:  1 + floor(MaxSP / 100) + floor(INT / 6)
## No natural regeneration at 50% weight or more, while dead, or while playing dead.

const HP_INTERVAL_MS := 6000.0
const SP_INTERVAL_MS := 8000.0


static func hp_amount(max_hp: int, vit: int) -> int:
	return maxi(1, max_hp / 200) + vit / 5


static func sp_amount(max_sp: int, int_: int) -> int:
	return 1 + max_sp / 100 + int_ / 6


static func interval(base_ms: float, sitting: bool) -> float:
	return base_ms / 2.0 if sitting else base_ms


static func blocked_by_weight(weight: int, max_weight: int) -> bool:
	return weight * 2 >= max_weight
