class_name GroundMeshBuilder
extends RefCounted
## Converts a GndFile into an ArrayMesh (one surface per ground texture).
##
## World mapping (RO -> Godot): x -> x, height h -> -h (RO heights grow
## downward), cell y -> -z (north is -Z). One GND cube is `gnd.zoom` units wide.

const SHADER := preload("res://scripts/rendering/map/ground.gdshader")
const LM_BORDER := 1  # lightmap tiles carry a 1-texel border for filtering

var gnd: GndFile
var rsw: RswFile
## Callable(texture_name_latin1: String) -> Texture2D (or null)
var texture_loader: Callable

var _lm_tex: ImageTexture
var _lm_per_row := 256
var _lm_size := Vector2.ONE
# texture index -> {"v": PackedVector3Array, "n": PackedVector3Array, "uv": PackedVector2Array,
#                   "uv2": PackedVector2Array, "c": PackedColorArray}
var _buckets: Dictionary = {}


func build() -> ArrayMesh:
	var atlas := gnd.build_lightmap_atlas()
	var img: Image = atlas.image
	_lm_tex = ImageTexture.create_from_image(img)
	_lm_per_row = atlas.per_row
	_lm_size = Vector2(img.get_width(), img.get_height())
	var w := gnd.width
	var h := gnd.height
	var z := gnd.zoom
	var smooth := _smooth_normals()
	var gw := w + 1
	for y in h:
		for x in w:
			var i := x + y * w
			var hb := i * 4
			var h0 := -gnd.cube_heights[hb]
			var h1 := -gnd.cube_heights[hb + 1]
			var h2 := -gnd.cube_heights[hb + 2]
			var h3 := -gnd.cube_heights[hb + 3]
			var sw := Vector3(x * z, h0, -y * z)
			var se := Vector3((x + 1) * z, h1, -y * z)
			var nw := Vector3(x * z, h2, -(y + 1) * z)
			var ne := Vector3((x + 1) * z, h3, -(y + 1) * z)
			var top := gnd.cube_top[i]
			if top >= 0:
				var g := x + y * gw
				_quad(top, sw, se, nw, ne, Vector3.UP,
					[smooth[g], smooth[g + 1], smooth[g + gw], smooth[g + gw + 1]])
			# Wall between this cube's north edge and the cube to the north.
			var front := gnd.cube_front[i]
			if front >= 0 and y + 1 < h:
				var nb := (i + w) * 4
				var b_sw := Vector3(x * z, -gnd.cube_heights[nb], -(y + 1) * z)
				var b_se := Vector3((x + 1) * z, -gnd.cube_heights[nb + 1], -(y + 1) * z)
				var north_lower := (nw.y + ne.y) > (b_sw.y + b_se.y)
				_quad(front, nw, ne, b_sw, b_se, Vector3(0, 0, -1) if north_lower else Vector3(0, 0, 1))
			# Wall between this cube's east edge and the cube to the east.
			var right := gnd.cube_right[i]
			if right >= 0 and x + 1 < w:
				var eb := (i + 1) * 4
				var e_sw := Vector3((x + 1) * z, -gnd.cube_heights[eb], -y * z)
				var e_nw := Vector3((x + 1) * z, -gnd.cube_heights[eb + 2], -(y + 1) * z)
				var east_lower := (ne.y + se.y) > (e_nw.y + e_sw.y)
				_quad(right, ne, se, e_nw, e_sw, Vector3(1, 0, 0) if east_lower else Vector3(-1, 0, 0))
	return _commit()


## Adds a quad for surface `s`. Corners are given in the surface's UV order
## (0, 1, 2, 3) = (SW, SE, NW, NE) for top faces. `facing` orients the normal
## (up for top faces, toward the lower neighbour for walls).
func _quad(s: int, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, facing := Vector3.UP, corner_normals: Array = []) -> void:
	if s >= gnd.surface_count():
		return
	var tex := gnd.surf_texture[s]
	if tex < 0:
		return
	if not _buckets.has(tex):
		_buckets[tex] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"uv2": PackedVector2Array(), "c": PackedColorArray()}
	var b: Dictionary = _buckets[tex]
	var u := s * 4
	var uv0 := gnd.surf_uv[u]
	var uv1 := gnd.surf_uv[u + 1]
	var uv2 := gnd.surf_uv[u + 2]
	var uv3 := gnd.surf_uv[u + 3]
	var lm := gnd.surf_lightmap[s]
	var ox := float((lm % _lm_per_row) * gnd.lightmap_px)
	var oy := float((lm / _lm_per_row) * gnd.lightmap_py)
	var l0 := Vector2(ox + LM_BORDER, oy + LM_BORDER) / _lm_size
	var l1 := Vector2(ox + gnd.lightmap_px - LM_BORDER, oy + LM_BORDER) / _lm_size
	var l2 := Vector2(ox + LM_BORDER, oy + gnd.lightmap_py - LM_BORDER) / _lm_size
	var l3 := Vector2(ox + gnd.lightmap_px - LM_BORDER, oy + gnd.lightmap_py - LM_BORDER) / _lm_size
	var col := gnd.surf_color[s]
	var n := (c1 - c0).cross(c2 - c0).normalized()
	if n.dot(facing) < 0.0:
		n = -n
	var v: PackedVector3Array = b.v
	v.append_array([c0, c1, c2, c1, c3, c2])
	var nn: PackedVector3Array = b.n
	if corner_normals.size() == 4:
		var n0: Vector3 = corner_normals[0]
		var n1: Vector3 = corner_normals[1]
		var n2: Vector3 = corner_normals[2]
		var n3: Vector3 = corner_normals[3]
		nn.append_array([n0, n1, n2, n1, n3, n2])
	else:
		nn.append_array([n, n, n, n, n, n])
	var t: PackedVector2Array = b.uv
	t.append_array([uv0, uv1, uv2, uv1, uv3, uv2])
	var t2: PackedVector2Array = b.uv2
	t2.append_array([l0, l1, l2, l1, l3, l2])
	var cc: PackedColorArray = b.c
	cc.append_array([col, col, col, col, col, col])


## Per grid-point normals: the average of the top-face normals of the (up to)
## four cubes sharing that corner, as the classic client smooths ground lighting.
## Grid is (width + 1) x (height + 1).
func _smooth_normals() -> PackedVector3Array:
	var w := gnd.width
	var h := gnd.height
	var z := gnd.zoom
	var face := PackedVector3Array()
	face.resize(w * h)
	for i in w * h:
		var hb := i * 4
		# Top face spans (z, dh) along x and (-z, dh) along -y; average its two triangles.
		var a := Vector3(z, gnd.cube_heights[hb] - gnd.cube_heights[hb + 1], 0)        # SW->SE (negated heights)
		var b := Vector3(0, gnd.cube_heights[hb] - gnd.cube_heights[hb + 2], -z)       # SW->NW
		var c := Vector3(z, gnd.cube_heights[hb + 2] - gnd.cube_heights[hb + 3], 0)    # NW->NE
		var d := Vector3(0, gnd.cube_heights[hb + 1] - gnd.cube_heights[hb + 3], -z)   # SE->NE
		face[i] = (a.cross(b) + c.cross(d)).normalized()
	var gw := w + 1
	var out := PackedVector3Array()
	out.resize(gw * (h + 1))
	for gy in h + 1:
		for gx in gw:
			var sum := Vector3.ZERO
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var cx: int = gx + ox
					var cy: int = gy + oy
					if cx >= 0 and cy >= 0 and cx < w and cy < h and gnd.cube_top[cx + cy * w] >= 0:
						sum += face[cx + cy * w]
			out[gx + gy * gw] = sum.normalized() if sum != Vector3.ZERO else Vector3.UP
	return out


func _commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var light_dir := rsw.light_direction() if rsw else Vector3(0.5, 0.7, -0.5).normalized()
	for tex_idx in _buckets:
		var b: Dictionary = _buckets[tex_idx]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.v
		arrays[Mesh.ARRAY_NORMAL] = b.n
		arrays[Mesh.ARRAY_TEX_UV] = b.uv
		arrays[Mesh.ARRAY_TEX_UV2] = b.uv2
		arrays[Mesh.ARRAY_COLOR] = b.c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var albedo: Texture2D = null
		if texture_loader.is_valid() and tex_idx < gnd.textures.size():
			albedo = texture_loader.call(gnd.textures[tex_idx])
		mat.set_shader_parameter("albedo_tex", albedo)
		mat.set_shader_parameter("lightmap_tex", _lm_tex)
		mat.set_shader_parameter("light_dir", light_dir)
		if rsw:
			var d: Color = rsw.light.diffuse
			var a: Color = rsw.light.ambient
			mat.set_shader_parameter("light_diffuse", Vector3(d.r, d.g, d.b))
			mat.set_shader_parameter("light_ambient", Vector3(a.r, a.g, a.b))
			mat.set_shader_parameter("light_opacity", float(rsw.light.opacity))
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh
