extends RefCounted
## Decodes every GAT/GND/RSW in the configured client. Read-only.

const ClientGrf := preload("res://tests/integration/test_client_grf.gd")


func test_prontera_consistency(_t) -> Variant:
	var g: GrfArchive = ClientGrf._archive()
	if g == null:
		return "SKIP no client configured"
	var gat := GatFile.decode(g.read(GrfArchive.key_for("data\\prontera.gat")))
	var gnd := GndFile.decode(g.read(GrfArchive.key_for("data\\prontera.gnd")))
	var rsw := RswFile.decode(g.read(GrfArchive.key_for("data\\prontera.rsw")))
	if gat == null or gnd == null or rsw == null:
		return "decode failed"
	if gat.width != gnd.width * 2 or gat.height != gnd.height * 2:
		return "GAT %dx%d is not 2x GND %dx%d" % [gat.width, gat.height, gnd.width, gnd.height]
	if rsw.gnd_file.to_lower() != "prontera.gnd":
		return "rsw gnd name: %s" % rsw.gnd_file
	if not rsw.objects_complete or rsw.models.is_empty():
		return "rsw objects incomplete: %s" % rsw.last_error
	print("    [prontera] gat %dx%d v%x, gnd %dx%d v%x (%d tex, %d lightmaps, %d surfaces), rsw v%x: %d models, %d lights, %d sounds, %d effects" % [
		gat.width, gat.height, gat.version, gnd.width, gnd.height, gnd.version, gnd.textures.size(),
		gnd.lightmap_count, gnd.surface_count(), rsw.version, rsw.models.size(), rsw.lights.size(),
		rsw.sounds.size(), rsw.effects.size()])
	return true


func test_all_maps_decode(_t) -> Variant:
	var g: GrfArchive = ClientGrf._archive()
	if g == null:
		return "SKIP no client configured"
	var counts := {"gat": 0, "gnd": 0, "rsw": 0}
	var bad: Array = []
	var incomplete: Array = []
	var odd_light: Array = []
	var t0 := Time.get_ticks_msec()
	for raw in g.list_raw_names():
		var key := GrfArchive.normalize(raw)
		var ext := key.get_extension()
		if not counts.has(ext):
			continue
		counts[ext] += 1
		var data := g.read(key)
		var nice := Cp949.decode_latin1(raw)
		match ext:
			"gat":
				var o := GatFile.new()
				if not o._parse(data): bad.append("%s: %s" % [nice, o.last_error])
			"gnd":
				var o := GndFile.new()
				if not o._parse(data): bad.append("%s: %s" % [nice, o.last_error])
			"rsw":
				var o := RswFile.new()
				if not o._parse(data):
					bad.append("%s: %s" % [nice, o.last_error])
				else:
					if not o.objects_complete:
						incomplete.append("%s v%x b%d: %s" % [nice, o.version, o.build, o.last_error])
					var lat: int = o.light.latitude
					var amb: Color = o.light.ambient
					if lat < 0 or lat > 360 or amb.r < 0.0 or amb.r > 4.0:
						odd_light.append("%s v%x" % [nice, o.version])
	print("    [maps] %s in %d ms; failures=%d, rsw objects incomplete=%d, odd light=%d" % [
		counts, Time.get_ticks_msec() - t0, bad.size(), incomplete.size(), odd_light.size()])
	if not incomplete.is_empty():
		print("      incomplete sample: %s" % str(incomplete.slice(0, 6)))
	if not odd_light.is_empty():
		print("      odd light sample: %s" % str(odd_light.slice(0, 6)))
	if not bad.is_empty():
		return "failures: %s" % str(bad.slice(0, 6))
	if not incomplete.is_empty() or not odd_light.is_empty():
		return "RSW layout gaps (see above)"
	return true


## Decodes and bakes a sample of every RSM/RSM2 in the client.
func test_model_sample_builds(_t) -> Variant:
	var g: GrfArchive = ClientGrf._archive()
	if g == null:
		return "SKIP no client configured"
	var tried := 0
	var bad: Array = []
	var empty := 0
	var versions := {}
	var i := 0
	for raw in g.list_raw_names():
		var key := GrfArchive.normalize(raw)
		if not (key.ends_with(".rsm") or key.ends_with(".rsm2")):
			continue
		i += 1
		if i % 13 != 0:
			continue
		tried += 1
		var r := RsmFile.new()
		if not r._parse(g.read(key)):
			if r.last_error.contains("not supported yet"):
				versions["unsupported"] = versions.get("unsupported", 0) + 1
				continue
			bad.append("%s: %s" % [Cp949.decode_latin1(raw), r.last_error])
			continue
		versions["%x" % r.version] = versions.get("%x" % r.version, 0) + 1
		var b := RsmMeshBuilder.new()
		b.rsm = r
		if b.build().get_surface_count() == 0:
			empty += 1
	print("    [models] sampled %d, failures=%d, empty meshes=%d, versions=%s" % [tried, bad.size(), empty, versions])
	if not bad.is_empty():
		return "failures: %s" % str(bad.slice(0, 5))
	return true
