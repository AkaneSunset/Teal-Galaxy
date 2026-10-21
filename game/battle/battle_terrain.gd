extends Node3D
## The ground of a sector battle: a SIZE x SIZE metre heightmap (gentle hills, a few ridges, flat
## build areas round the landing zones and mass points), ringed by higher ground past the map's
## edge, with rocks (and on green worlds, trees) scattered over it. Drawn from the battle's seed,
## so every pilot in the battle sees the same field. The height is only for looks: the server
## simulates the battle flat.
##
## (0, 0) is a corner of the map and x, z run to SIZE, as on the server.

const SIZE := 1600.0
const SKIRT := 420.0 # metres of high ground drawn past each edge
const CELL := 12.5 # metres per grid cell
const N := int((SIZE + 2.0 * SKIRT) / CELL) # cells along a side

## A colour scheme per kind of world: low ground, high ground, rock, the peaks, and the glow of
## the sky (for the sky and fog).
const PALETTES := {
	"frost": {"low": Color(0.42, 0.47, 0.53), "high": Color(0.62, 0.67, 0.75), "rock": Color(0.25, 0.27, 0.32), "peak": Color(0.86, 0.9, 0.96),
		"sky": Color(0.55, 0.66, 0.8), "horizon": Color(0.74, 0.8, 0.88), "sun": Color(1.0, 0.95, 0.88)},
	"dust": {"low": Color(0.56, 0.42, 0.27), "high": Color(0.68, 0.55, 0.37), "rock": Color(0.36, 0.25, 0.18), "peak": Color(0.78, 0.66, 0.5),
		"sky": Color(0.62, 0.52, 0.42), "horizon": Color(0.86, 0.72, 0.56), "sun": Color(1.0, 0.86, 0.7)},
	"moss": {"low": Color(0.27, 0.36, 0.2), "high": Color(0.4, 0.45, 0.27), "rock": Color(0.32, 0.3, 0.27), "peak": Color(0.66, 0.66, 0.62),
		"sky": Color(0.42, 0.58, 0.78), "horizon": Color(0.7, 0.78, 0.84), "sun": Color(1.0, 0.96, 0.86)},
	"ash": {"low": Color(0.27, 0.26, 0.26), "high": Color(0.38, 0.36, 0.35), "rock": Color(0.16, 0.15, 0.15), "peak": Color(0.52, 0.47, 0.44),
		"sky": Color(0.36, 0.28, 0.27), "horizon": Color(0.62, 0.42, 0.32), "sun": Color(1.0, 0.8, 0.62)},
}

## The ground's material: the vertex colours (in sRGB) with fine detail mixed in close up, so
## the field reads as ground (patches, speckle, a hint of grass) rather than a painted plain when
## the camera is down among the units; the detail fades out with distance, where it would shimmer.
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
varying vec3 world;
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(1.8)) * 1.3; // sRGB to linear, kept a little lighter than exact
	c = mix(vec3(dot(c, vec3(0.3, 0.55, 0.15))), c, 0.85); // a touch less saturated than the palette
	float near = 1.0 - smoothstep(120.0, 700.0, length(VERTEX));
	float patches = noise(world.xz * 0.045) * 0.6 + noise(world.xz * 0.11) * 0.4;
	float speck = noise(world.xz * 0.7) * 0.6 + noise(world.xz * 2.3) * 0.4;
	c *= 0.86 + 0.26 * patches;
	c *= mix(1.0, 0.8 + 0.36 * speck, near);
	// Darker, cooler hollows between the speckle: the ground has some depth close up.
	c = mix(c, c * vec3(0.78, 0.84, 0.8), near * smoothstep(0.45, 0.2, speck) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.94;
	SPECULAR = 0.2;
}
"""

var palette := {}
var palette_name := ""
## Where the ground is held flat for building: {"x", "z", "r", "h"} (the landing zones, the
## defender's base, each mass point).
var flats: Array = []

var _heights := PackedFloat32Array()
var _base := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _ridge_mask := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _mesh: MeshInstance3D


## Builds the field for a battle: `seed` from battle_joined, `planet` its planet id (which kind of
## world it is), the landing zones and the mass points that must stay flat.
func generate(seed: int, planet: String, lz: Dictionary, enemy_lz: Dictionary, mass_points: Array) -> void:
	var kinds := {"cinder": "ash", "vesper": "moss", "halcyon": "frost", "morrow": "dust"}
	palette_name = kinds.get(planet, PALETTES.keys()[absi(hash(planet)) % PALETTES.size()])
	palette = PALETTES[palette_name]
	var s := seed
	for n in [_base, _hills, _ridge, _ridge_mask, _detail, _tint]:
		n.seed = s
		s = hash(s)
	_base.frequency = 0.0016
	_base.fractal_octaves = 3
	_hills.frequency = 0.005
	_hills.fractal_octaves = 3
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.frequency = 0.0028
	_ridge.fractal_octaves = 3
	_ridge_mask.frequency = 0.0014
	_detail.frequency = 0.03
	_tint.frequency = 0.012
	flats.clear()
	flats.append({"x": float(lz.x), "z": float(lz.z), "r": float(lz.get("r", 120)) + 40.0})
	flats.append({"x": float(enemy_lz.x), "z": float(enemy_lz.z), "r": float(enemy_lz.get("r", 120)) + 70.0})
	for p in mass_points:
		flats.append({"x": float(p.x), "z": float(p.z), "r": 26.0})
	for f in flats: # each flat area sits at the natural height of its middle
		f.h = _raw(f.x, f.z)
	_heights.resize((N + 1) * (N + 1))
	for j in N + 1:
		for i in N + 1:
			_heights[j * (N + 1) + i] = _shaped(-SKIRT + i * CELL, -SKIRT + j * CELL)
	_build_mesh()
	_scatter(seed)


## The ground's height at (x, z), from the grid (what the mesh shows).
func height(x: float, z: float) -> float:
	var fx := clampf((x + SKIRT) / CELL, 0.0, N - 0.001)
	var fz := clampf((z + SKIRT) / CELL, 0.0, N - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := _heights[j * (N + 1) + i]
	var b := _heights[j * (N + 1) + i + 1]
	var c := _heights[(j + 1) * (N + 1) + i]
	var d := _heights[(j + 1) * (N + 1) + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Where a ray from the camera meets the ground, or `fallback` if it never does.
func pick(from: Vector3, dir: Vector3, fallback := Vector3(-1, 0, -1)) -> Vector3:
	if dir.y > -0.01:
		return fallback
	var step := clampf(from.y * 0.02, 2.0, 40.0)
	var p := from
	var prev := from
	for k in 600:
		p = from + dir * (step * k)
		if p.y <= height(p.x, p.z):
			# Close in on where it crossed.
			var lo := prev
			var hi := p
			for m in 10:
				var mid := (lo + hi) * 0.5
				if mid.y <= height(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
		if p.y < -200.0:
			break
	return fallback


## A small picture of the map for the minimap: the ground's colours, lit from the north-west.
func minimap_image(px := 256) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	for j in px:
		for i in px:
			var x := (i + 0.5) / px * SIZE
			var z := (j + 0.5) / px * SIZE
			var h := height(x, z)
			var shade := clampf(1.0 + (height(x - 6.0, z - 6.0) - h) * 0.06, 0.6, 1.35)
			img.set_pixel(i, j, (_colour(x, z, h, _slope(x, z)) * shade).clamp())
	return img


# --- Building the ground ----------------------------------------------------------------------

## The natural ground before the flat areas: wide rolling land, hills, a few ridges (where the
## ridge mask allows), small bumps; rising into mountains past the map's edge.
func _raw(x: float, z: float) -> float:
	var h := _base.get_noise_2d(x, z) * 26.0 + _hills.get_noise_2d(x, z) * 9.0
	var mask := smoothstep(0.15, 0.45, _ridge_mask.get_noise_2d(x, z))
	h += (1.0 - absf(_ridge.get_noise_2d(x, z))) * 38.0 * mask - 14.0 * mask
	h += _detail.get_noise_2d(x, z) * 1.2
	var out := maxf(maxf(-x, x - SIZE), maxf(-z, z - SIZE)) # metres past the edge
	if out > -60.0:
		var t := clampf((out + 60.0) / (SKIRT * 0.8), 0.0, 1.0)
		h += t * t * (110.0 + 60.0 * _ridge.get_noise_2d(x * 2.0, z * 2.0))
	return h


func _shaped(x: float, z: float) -> float:
	var h := _raw(x, z)
	for f in flats:
		var d := Vector2(x - f.x, z - f.z).length()
		if d < f.r * 1.6:
			var t := 1.0 - smoothstep(f.r * 0.75, f.r * 1.6, d)
			h = lerpf(h, f.h, t)
	return h


func _slope(x: float, z: float) -> float:
	var dx := height(x + CELL, z) - height(x - CELL, z)
	var dz := height(x, z + CELL) - height(x, z - CELL)
	return Vector2(dx, dz).length() / (2.0 * CELL)


## The ground's colour: low ground to high ground with height, rock on slopes, the peaks pale,
## and a little mottling so it doesn't look painted. Darker past the map's edge.
func _colour(x: float, z: float, h: float, slope: float) -> Color:
	var c: Color = (palette.low as Color).lerp(palette.high, clampf((h + 10.0) / 50.0, 0.0, 1.0))
	c = c.lerp(palette.rock, smoothstep(0.35, 0.8, slope))
	c = c.lerp(palette.peak, smoothstep(70.0, 130.0, h) * (1.0 - smoothstep(0.6, 1.1, slope) * 0.6))
	var m := _tint.get_noise_2d(x, z) + _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.5
	c = c * (1.0 + m * 0.22)
	var out := maxf(maxf(-x, x - SIZE), maxf(-z, z - SIZE))
	if out > 0.0:
		c = c * (1.0 - clampf(out / 300.0, 0.0, 0.35))
	return c


func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var idx := PackedInt32Array()
	var n1 := N + 1
	verts.resize(n1 * n1)
	normals.resize(n1 * n1)
	colours.resize(n1 * n1)
	for j in n1:
		for i in n1:
			var k := j * n1 + i
			var x := -SKIRT + i * CELL
			var z := -SKIRT + j * CELL
			var h := _heights[k]
			verts[k] = Vector3(x, h, z)
			var hl := _heights[k - 1] if i > 0 else h
			var hr := _heights[k + 1] if i < N else h
			var hd := _heights[k - n1] if j > 0 else h
			var hu := _heights[k + n1] if j < N else h
			normals[k] = Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			var slope := Vector2(hr - hl, hu - hd).length() / (2.0 * CELL)
			colours[k] = _colour(x, z, h, slope)
	idx.resize(N * N * 6)
	var w := 0
	for j in N:
		for i in N:
			var a := j * n1 + i
			idx[w] = a
			idx[w + 1] = a + 1
			idx[w + 2] = a + n1
			idx[w + 3] = a + 1
			idx[w + 4] = a + n1 + 1
			idx[w + 5] = a + n1
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_mesh.material_override = mat
		add_child(_mesh)
	_mesh.mesh = mesh
	# The world past the high ground: a dark plain out to the horizon.
	var far := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16000, 16000)
	far.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = (palette.rock as Color) * 0.8
	fm.roughness = 1.0
	far.material_override = fm
	far.position = Vector3(SIZE * 0.5, -60.0, SIZE * 0.5)
	add_child(far)


## Rocks over the field (and trees on a green world), away from the flat areas. One MultiMesh each.
func _scatter(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rock := _rock_mesh()
	var rocks: Array[Transform3D] = []
	var trees: Array[Transform3D] = []
	var tries := 0
	while rocks.size() < 700 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-SKIRT * 0.6, SIZE + SKIRT * 0.6)
		var z := rng.randf_range(-SKIRT * 0.6, SIZE + SKIRT * 0.6)
		if _near_flat(x, z, 1.4):
			continue
		var s := rng.randf_range(0.8, 4.5) * (1.0 + _slope(x, z) * 2.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.5, 1.0), s))
		rocks.append(Transform3D(b, Vector3(x, height(x, z) - s * 0.25, z)))
	if palette_name == "moss" or palette_name == "frost":
		tries = 0
		while trees.size() < 1600 and tries < 8000:
			tries += 1
			var x := rng.randf_range(-SKIRT * 0.5, SIZE + SKIRT * 0.5)
			var z := rng.randf_range(-SKIRT * 0.5, SIZE + SKIRT * 0.5)
			if _near_flat(x, z, 1.25) or _slope(x, z) > 0.5 or _tint.get_noise_2d(x * 0.5, z * 0.5) < 0.05:
				continue # trees stand in woods (where the mottling is high), not on bare slopes
			var s := rng.randf_range(0.7, 1.4)
			trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), Vector3(x, height(x, z), z)))
	_multi(rock, rocks, (palette.rock as Color).lerp(palette.high, 0.25))
	if not trees.is_empty():
		var tree_colour := Color(0.16, 0.27, 0.15) if palette_name == "moss" else Color(0.2, 0.3, 0.3)
		_multi(_tree_mesh(), trees, tree_colour)


func _near_flat(x: float, z: float, k: float) -> bool:
	for f in flats:
		if Vector2(x - f.x, z - f.z).length() < f.r * k:
			return true
	return false


func _multi(mesh: Mesh, xforms: Array[Transform3D], colour: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.95
	inst.material_override = mat
	add_child(inst)


## A lumpy low-poly boulder about a metre across.
func _rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.6
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.frequency = 1.3
	for i in verts.size():
		verts[i] *= 1.0 + noise.get_noise_3dv(verts[i]) * 0.35
	arrays[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.deindex()
	st.generate_normals() # faceted, like the game's other rocks
	return st.commit()


## A conifer: a trunk and two stacked cones, about 9 m tall.
func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in [[0.0, 2.6, 0.5, 0.5], [2.0, 4.6, 2.6, 0.0], [4.6, 3.8, 1.8, 0.0]]:
		var y0: float = layer[0]
		var h: float = layer[1]
		var r0: float = layer[2]
		var r1: float = layer[3]
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var t0 := Vector3(cos(a0) * r1, y0 + h, sin(a0) * r1)
			var t1 := Vector3(cos(a1) * r1, y0 + h, sin(a1) * r1)
			for v in [b0, b1, t0, b1, t1, t0]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
