extends SceneTree
## Reports which class body sprites the player's client has, for the
## candidate names in CANDIDATES (kRO body file stems), per sex.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_job_sprites.gd
## Prints a JSON object {job: sprite} of the first candidate found.

const BODY := "data/sprite/인간족/몸통/"
const CANDIDATES := {
	"knight": ["기사"], "priest": ["프리스트"], "wizard": ["위저드"], "blacksmith": ["제철공"],
	"hunter": ["헌터"], "assassin": ["어세신"], "crusader": ["크루세이더"], "monk": ["몽크"],
	"sage": ["세이지"], "rogue": ["로그"], "alchemist": ["연금술사"], "bard": ["바드"], "dancer": ["무희"],
	"lord_knight": ["로드나이트"], "high_priest": ["하이프리"], "high_wizard": ["하이위저드"],
	"whitesmith": ["화이트스미스"], "sniper": ["스나이퍼"], "assassin_cross": ["어쌔신크로스"],
	"paladin": ["팔라딘"], "champion": ["챔피온"], "professor": ["프로페서"], "stalker": ["스토커"],
	"creator": ["크리에이터"], "clown": ["클라운"], "gypsy": ["집시"],
	"rune_knight": ["룬나이트"], "warlock": ["워록"], "ranger": ["레인져", "레인저"], "arch_bishop": ["아크비숍"],
	"mechanic": ["미케닉"], "guillotine_cross": ["길로틴크로스"], "royal_guard": ["가드", "로얄가드"],
	"sorcerer": ["소서러"], "minstrel": ["민스트럴"], "wanderer": ["원더러"], "sura": ["슈라"],
	"genetic": ["제네릭"], "shadow_chaser": ["쉐도우체이서"],
}
const SINGLE_SEX := {"bard": "남", "clown": "남", "minstrel": "남", "dancer": "여", "gypsy": "여", "wanderer": "여"}


func _initialize() -> void:
	var res := root.get_node("RoResources")
	if not res.is_mounted:
		res.mount()
	var found := {}
	var missing := []
	for job in CANDIDATES:
		var hit := ""
		for name in CANDIDATES[job]:
			var ok := true
			for sex in ["남", "여"]:
				if SINGLE_SEX.has(job) and SINGLE_SEX[job] != sex:
					continue
				for ext in [".spr", ".act"]:
					ok = ok and res.exists(BODY + "%s/%s_%s%s" % [sex, name, sex, ext])
				if ok:
					var spr := SprFile.decode(res.read(BODY + "%s/%s_%s.spr" % [sex, name, sex]))
					var act := ActFile.decode(res.read(BODY + "%s/%s_%s.act" % [sex, name, sex]))
					if spr == null or act == null:
						print("DECODE FAIL ", job, " ", sex)
						ok = false
					elif spr.repaired_frames > 0:
						print("repaired ", job, " ", sex, ": ", spr.repaired_frames, " frame(s)")
			if ok:
				hit = String(name)
				break
		if hit != "":
			found[job] = hit
		else:
			missing.append(job)
	var f := FileAccess.open("user://job_sprites_found.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(found))
	f.close()
	print("found ", found.size(), " missing ", missing)
	quit(0)
