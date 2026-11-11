class_name RoMap
extends Node3D
## A loaded classic map: ground mesh, water plane and walkability data.
## Rendering only reads GAT/GND/RSW; gameplay queries go through `gat`.

const TEXTURE_DIR := "data\\texture\\"

var map_name := ""
var gat: GatFile
var gnd: GndFile
var rsw: RswFile
var ground: MeshInstance3D
var load_ms := 0
var load_models := true
var models_root: Node3D
var model_stats := {"instances": 0, "unique": 0, "failed": 0}

var _textures: Dictionary = {}
## The RoResources VFS node (looked up at runtime so tools and tests can use RoMap).
var res: Node


## Loads "<name>.rsw/.gnd/.gat" through res. Returns false on failure.
func load_map(name: String) -> bool:
	var t0 := Time.get_ticks_msec()
	map_name = name
	if res == null:
		res = (Engine.get_main_loop() as SceneTree).root.get_node("RoResources")
	rsw = RswFile.decode(res.read("data\\%s.rsw" % name))
	var gnd_name := rsw.gnd_file if rsw and rsw.gnd_file != "" else name + ".gnd"
	var gat_name := rsw.gat_file if rsw and rsw.gat_file != "" else name + ".gat"
	gnd = GndFile.decode(res.read("data\\" + Cp949.decode_latin1(gnd_name)))
	gat = GatFile.decode(res.read("data\\" + Cp949.decode_latin1(gat_name)))
	if gnd == null:
		push_warning("Map %s: no ground (%s)" % [name, res.last_error])
		return false
	var builder := GroundMeshBuilder.new()
	builder.gnd = gnd
	builder.rsw = rsw
	builder.texture_loader = _load_texture
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = builder.build()
	add_child(ground)
	_add_water()
	if load_models:
		_add_models()
	load_ms = Time.get_ticks_msec() - t0
	return true


## Map extents in world units (x, z) and centre.
func world_size() -> Vector2:
	return Vector2(gnd.width * gnd.zoom, gnd.height * gnd.zoom)


func center() -> Vector3:
	var s := world_size()
	return Vector3(s.x / 2.0, 0.0, -s.y / 2.0)


## Godot position of the centre of GAT cell (x, y), on the ground.
func cell_to_world(x: int, y: int) -> Vector3:
	var half := gnd.zoom / 2.0
	var hgt := -gat.height_at(x, y) if gat else 0.0
	return Vector3((x + 0.5) * half, hgt, -(y + 0.5) * half)


## Godot position for a continuous GAT position (cell units, centre = n + 0.5).
func cell_pos_to_world(p: Vector2) -> Vector3:
	var half := gnd.zoom / 2.0
	var c := Vector2i(floori(p.x), floori(p.y))
	var hgt := -gat.height_at(c.x, c.y, p.x - c.x, p.y - c.y) if gat else 0.0
	return Vector3(p.x * half, hgt, -p.y * half)


## Ground hit for a ray (ray-marched against GAT heights). Returns (-1, -1) on miss.
func pick_cell(origin: Vector3, dir: Vector3, max_dist: float = 4000.0) -> Vector2i:
	if gat == null:
		return Vector2i(-1, -1)
	var half := gnd.zoom / 2.0
	var step := half * 0.25
	var t := 0.0
	while t < max_dist:
		var p := origin + dir * t
		var c := world_to_cell(p)
		if gat.in_bounds(c.x, c.y):
			var fx := p.x / half - c.x
			var fy := -p.z / half - c.y
			if p.y <= -gat.height_at(c.x, c.y, fx, fy):
				return c
		t += step
	return Vector2i(-1, -1)


func world_to_cell(p: Vector3) -> Vector2i:
	var half := gnd.zoom / 2.0
	return Vector2i(floori(p.x / half), floori(-p.z / half))


func _load_texture(latin1_name: String) -> Texture2D:
	if _textures.has(latin1_name):
		return _textures[latin1_name]
	var path := TEXTURE_DIR + Cp949.decode_latin1(latin1_name)
	var img := TextureLoader.load_image(res.read(path), path)
	var tex: Texture2D = null
	if img:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_textures[latin1_name] = tex
	return tex


func _add_models() -> void:
	if rsw == null:
		return
	models_root = Node3D.new()
	models_root.name = "Models"
	add_child(models_root)
	var cache := {}  # latin1 file -> ArrayMesh or null
	var light_dir := rsw.light_direction()
	var dif: Color = rsw.light.diffuse
	var amb: Color = rsw.light.ambient
	for entry in rsw.models:
		var file: String = entry.file
		if not cache.has(file):
			var path := "data\\model\\" + Cp949.decode_latin1(file)
			var rsm := RsmFile.decode(res.read(path))
			var mesh: ArrayMesh = null
			if rsm:
				var b := RsmMeshBuilder.new()
				b.rsm = rsm
				b.texture_loader = _load_texture
				mesh = b.build()
				for s in mesh.get_surface_count():
					var mat := mesh.surface_get_material(s) as ShaderMaterial
					mat.set_shader_parameter("light_dir", light_dir)
					mat.set_shader_parameter("light_diffuse", Vector3(dif.r, dif.g, dif.b))
					mat.set_shader_parameter("light_ambient", Vector3(amb.r, amb.g, amb.b))
			cache[file] = mesh
			if mesh == null:
				model_stats.failed += 1
		var m: ArrayMesh = cache[file]
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.transform = RsmMeshBuilder.instance_transform(entry, gnd)
		models_root.add_child(mi)
		model_stats.instances += 1
	model_stats.unique = cache.size()


func _add_water() -> void:
	var w: Dictionary = gnd.water if not gnd.water.is_empty() else (rsw.water if rsw else {})
	if w.is_empty():
		return
	var plane := MeshInstance3D.new()
	plane.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = world_size()
	plane.mesh = pm
	plane.position = center() + Vector3(0, -float(w.level), 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.55)
	var tex_path := "data\\texture\\워터\\water%d00.jpg" % int(w.type)
	var img := TextureLoader.load_image(res.read(tex_path), tex_path)
	if img:
		img.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.uv1_scale = Vector3(world_size().x / 40.0, world_size().y / 40.0, 1)
	else:
		mat.albedo_color = Color(0.2, 0.4, 0.6, 0.5)
	plane.material_override = mat
	add_child(plane)
