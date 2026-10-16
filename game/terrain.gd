extends Node3D
## The icy planet surface around a base or satellite site: flat where the base stands, rising into
## snow-dusted rock, mesas and jagged peaks further out, with mist drifting through the valleys.
## Generated from a seed (the planet or site id), so no two bases look the same, and the same
## base always looks the same. Faceted (flat-shaded) to match the game's low-poly models.

const RADIUS := 700.0 # metres to the edge of the terrain
const RINGS := 72
const SEGMENTS := 112

# Albedo before the sun and ambient light brighten it (snow ends up pale blue-grey on screen).
const SNOW := Color(0.34, 0.38, 0.47)
const FROST := Color(0.23, 0.26, 0.34)
const ROCK := Color(0.14, 0.15, 0.2)
const DARK_ROCK := Color(0.08, 0.085, 0.11)

var _key := ""
var _mesh: MeshInstance3D
var _props: Node3D
var _mist: Array[Sprite3D] = []
var _clock := 0.0

var _base := FastNoiseLite.new() # gentle rolling ground
var _ridge := FastNoiseLite.new() # jagged peaks
var _mesa := FastNoiseLite.new() # where flat-topped rock tables stand
var _detail := FastNoiseLite.new() # small bumps and cracks
var _flat := 60.0
var _bias := FastNoiseLite.new() # which sides of the base get the high ground
var _cliff := {} # dir, edge, height: a sheer rise (or drop) off one side of the base
var _canyon := {} # normal, along, offset, width, depth: a winding gorge past another side


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	_mesh.material_override = mat
	add_child(_mesh)
	_props = Node3D.new()
	add_child(_props)


func _process(delta: float) -> void:
	_clock += delta
	for i in _mist.size(): # mist drifts slowly and breathes
		var m := _mist[i]
		var home: Vector3 = m.get_meta("home")
		m.position = home + Vector3(sin(_clock * 0.05 + i) * 12.0, 0, cos(_clock * 0.04 + i * 1.7) * 12.0)
		m.modulate.a = 0.16 + 0.06 * sin(_clock * 0.3 + i)


## Builds the terrain for `id` (a planet or site id), keeping a flat clearing of `flat` metres
## around the middle. Does nothing if it's already showing that terrain.
func generate(id: String, flat: float) -> void:
	var key := "%s:%d" % [id, int(flat)]
	if key == _key:
		return
	_key = key
	_flat = flat
	var seed := hash(id)
	for n in [_base, _ridge, _mesa, _detail]:
		n.seed = seed
		seed = hash(seed)
	_base.frequency = 0.004
	_base.fractal_octaves = 3
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_ridge.frequency = 0.006 + (hash(id + "f") % 100) / 100.0 * 0.006 # some planets have tighter ranges
	_mesa.frequency = 0.008
	_detail.frequency = 0.05
	_bias.seed = hash(id + "bias")
	_bias.frequency = 0.9
	_pick_landforms(hash(id + "landforms"))
	_build_mesh()
	_scatter(hash(id + "props"))


## Height of the ground at (x, z).
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var out := smoothstep(_flat, _flat + 60.0, d) # 0 in the clearing, 1 well past it
	var far := smoothstep(_flat + 40.0, _flat + 260.0, d) # peaks grow taller further out
	# The big peaks crowd some sides of the base and leave others open, so it isn't a crater.
	var ang := atan2(z, x)
	var side := _bias.get_noise_2d(cos(ang), sin(ang)) * 0.5 + 0.5
	far *= smoothstep(0.25, 0.75, side)
	var h := _base.get_noise_2d(x, z) * 8.0 + _detail.get_noise_2d(x, z) * 1.5
	# Ridged noise gives sharp crests; cubing it keeps the peaks narrow and the valleys wide.
	var r := maxf(0.0, _ridge.get_noise_2d(x, z) * 0.5 + 0.5)
	h += pow(r, 2.2) * (14.0 * lerpf(0.3, 1.0, side) + 80.0 * far)
	# Mesas: where the mesa noise is high the ground lifts into a flat-topped table with sheer sides.
	var m := _mesa.get_noise_2d(x, z)
	if m > 0.35:
		h = maxf(h, (16.0 + 10.0 * far) * smoothstep(0.35, 0.42, m) + _detail.get_noise_2d(z, x) * 0.8)
	h *= out
	var p := Vector2(x, z)
	if not _cliff.is_empty():
		# A wall of rock (or a ledge dropping away) along a wobbly line off one side.
		var s: float = p.dot(_cliff.dir) - _cliff.edge - _base.get_noise_2d(z * 2.0, x * 2.0) * 14.0
		h += smoothstep(0.0, 5.0, s) * _cliff.height
	if not _canyon.is_empty():
		# A winding gorge with steep walls and a stepped floor, well clear of the base.
		var along: float = p.dot(_canyon.along)
		var off: float = p.dot(_canyon.normal) - _canyon.offset - _base.get_noise_2d(along, 7.0) * 40.0
		var w: float = _canyon.width
		var cut := 1.0 - smoothstep(w * 0.55, w, absf(off))
		var floor_step := smoothstep(0.3, 0.5, _mesa.get_noise_2d(along * 0.5, off))
		h = lerpf(h, -_canyon.depth * (0.55 + 0.45 * floor_step), cut)
	return h


## Picks the big landforms for this base: usually a cliff on one side, often a canyon on another.
func _pick_landforms(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 4:
		rng.randi() # the first draws from nearby seeds come out alike
	_cliff = {}
	_canyon = {}
	var roll := rng.randf()
	var cliff_ang := rng.randf() * TAU
	if roll < 0.75:
		var height := rng.randf_range(28.0, 55.0)
		if rng.randf() < 0.35:
			height *= -0.8 # a ledge: the ground drops away instead of rising
		_cliff = {
			dir = Vector2(cos(cliff_ang), sin(cliff_ang)),
			edge = _flat + rng.randf_range(12.0, 45.0),
			height = height,
		}
	if roll > 0.35:
		var a := cliff_ang + rng.randf_range(PI * 0.6, PI * 1.4) # away from the cliff
		var width := rng.randf_range(18.0, 34.0)
		_canyon = {
			normal = Vector2(cos(a), sin(a)),
			along = Vector2(-sin(a), cos(a)),
			offset = _flat + width + rng.randf_range(8.0, 50.0),
			width = width,
			depth = rng.randf_range(30.0, 60.0),
		}


func _build_mesh() -> void:
	# Rings packed close near the clearing (where the camera looks) and spread out far away.
	var radii: Array[float] = [0.0]
	for i in RINGS:
		var t := float(i + 1) / RINGS
		radii.append(lerpf(_flat * 0.8, RADIUS, t * t))
	var points := []
	for r in radii:
		var ring := []
		var segs := 1 if r == 0.0 else SEGMENTS
		for s in segs:
			var a := TAU * s / SEGMENTS
			var x := cos(a) * r
			var z := sin(a) * r
			ring.append(Vector3(x, height_at(x, z), z))
		points.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size()):
		var inner: Array = points[i - 1]
		var outer: Array = points[i]
		for s in SEGMENTS:
			var o0: Vector3 = outer[s]
			var o1: Vector3 = outer[(s + 1) % SEGMENTS]
			if inner.size() == 1:
				_tri(st, inner[0], o1, o0)
			else:
				var i0: Vector3 = inner[s]
				var i1: Vector3 = inner[(s + 1) % SEGMENTS]
				_tri(st, i0, o1, o0)
				_tri(st, i0, i1, o1)
	_mesh.mesh = st.commit()


## One flat-shaded triangle, coloured by how steep and how high it is: snow on flats and high
## ground, frost on gentle slopes, bare dark rock on cliffs.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	var mid := (a + b + c) / 3.0
	var steep := 1.0 - n.y # 0 flat, 1 vertical
	var col := SNOW.lerp(FROST, smoothstep(0.08, 0.3, steep))
	col = col.lerp(ROCK, smoothstep(0.3, 0.55, steep))
	col = col.lerp(DARK_ROCK, smoothstep(0.6, 0.85, steep))
	col = col.lerp(SNOW, smoothstep(50.0, 90.0, mid.y) * 0.35) # snow clings to the summits
	col *= 0.94 + 0.12 * (_detail.get_noise_2d(mid.z * 3.0, mid.x * 3.0) * 0.5 + 0.5) # break up flat colour
	st.set_normal(n)
	st.set_color(col)
	# Godot draws clockwise faces (seen from the front), so with an upward normal go a, c, b.
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


## Boulders, ice crystals and mist banks, placed on the terrain from the same seed.
func _scatter(seed: int) -> void:
	for c in _props.get_children():
		c.queue_free()
	_mist.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 40:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(_flat + 8.0, _flat + 160.0)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		p.y = height_at(p.x, p.z)
		var prop: Node3D
		if i % 3 == 0:
			prop = Models.ice_asteroid(rng.randf_range(1.5, 3.0), i)
			p.y += 0.6
		else:
			prop = BaseModels.boulder(rng.randf_range(1.5, 5.0), seed + i)
		prop.position = p
		prop.rotation.y = rng.randf() * TAU
		_props.add_child(prop)
	var tex := _mist_texture()
	for i in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(_flat + 70.0, _flat + 360.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.no_depth_test = false
		s.pixel_size = rng.randf_range(0.3, 0.6)
		s.modulate = Color(0.85, 0.9, 1.0, 0.18)
		s.position = Vector3(x, height_at(x, z) + rng.randf_range(3.0, 8.0), z)
		s.set_meta("home", s.position)
		_props.add_child(s)
		_mist.append(s)


func _mist_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 64
	return t


const Models := preload("res://models.gd")
const BaseModels := preload("res://base_models.gd")
