extends SceneTree
## Diagnostic: prints model placement data for one map.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_models.gd -- prontera


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var res: Node = root.get_node("RoResources")
	res.mount()
	var args := OS.get_cmdline_user_args()
	var name := args[0] if args.size() > 0 else "prontera"
	var map := RoMap.new()
	root.add_child(map)
	map.load_map(name)
	print("map size ", map.world_size(), " centre ", map.center(), " ground aabb ", map.ground.get_aabb())
	var shown := 0
	for mi in map.models_root.get_children():
		if shown >= 8:
			break
		var m: MeshInstance3D = mi
		var aabb := m.mesh.get_aabb()
		var verts := 0
		for s in m.mesh.get_surface_count():
			verts += m.mesh.surface_get_array_len(s)
		var tex_ok := 0
		for s in m.mesh.get_surface_count():
			if (m.mesh.surface_get_material(s) as ShaderMaterial).get_shader_parameter("albedo_tex") != null:
				tex_ok += 1
		print("inst origin ", m.transform.origin, " local aabb ", aabb, " world aabb ", m.transform * aabb,
			" verts ", verts, " surfaces ", m.mesh.get_surface_count(), " textured ", tex_ok)
		shown += 1
	var e: Dictionary = map.rsw.models[0]
	dump_rsm(res, e.file)
	print("rsw[0] ", e.file, " pos ", e.pos, " rot ", e.rot, " scale ", e.scale)
	quit(0)


static func dump_rsm(res: Node, latin1_file: String) -> void:
	var rsm := RsmFile.decode(res.read("data/model/" +Cp949.decode_latin1(latin1_file)))
	if rsm == null:
		print("decode null")
		return
	print("rsm v%x shade %d textures %d nodes %d" % [rsm.version, rsm.shade_type, rsm.textures.size(), rsm.nodes.size()])
	for n in rsm.nodes:
		print("  node '%s' parent '%s' tex %d verts %d uvs %d faces %d" % [n.name, n.parent, n.textures.size(), n.vertices.size(), n.uvs.size(), n.faces.size() / 8])
