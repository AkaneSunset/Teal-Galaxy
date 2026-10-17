extends RefCounted
## The game's 3D models, built in code so they need no external files.
## Style: chunky bevelled panels, teal hull, navy trim, warm amber lights, like soft toy plastic.
## Sizes are in metres. Fronts face -Z. Origins sit at the centre, or at the base for buildings.
##   const Models := preload("res://models.gd")
##   add_child(Models.starter_ship())

const TEAL := Color(0.36, 0.78, 0.78)
const TEAL_LIGHT := Color(0.5, 0.88, 0.88)
const NAVY := Color(0.13, 0.2, 0.42)
const AMBER := Color(1.0, 0.58, 0.1)
const STEEL := Color(0.5, 0.53, 0.58)
const ROCK := Color(0.56, 0.63, 0.74)
const SILVER := Color(0.86, 0.88, 0.92)

static var _materials := {}

## Every ship has an exit ramp. Where each model's ramp folds out, in the model's own space: the hatch
## under the hull, which way the ramp runs out from it, its width, and how high the model's origin
## stands above the ground when the ship is landed on its gear.
const RAMPS := {
	"starter_ship": {"hatch": Vector3(0, -1.35, 2.2), "out": Vector3(0, 0, 1), "width": 1.5, "landed_height": 2.85},
}

## Every model, by name, for the showcase and the exporter.
const ALL := ["starter_ship", "mining_laser", "ice_canister", "nav_beacon", "loot_crate",
	"keycard", "habitat_dome", "ice_asteroid", "metal_asteroid"]


static func make(model: String) -> Node3D:
	return Callable(load("res://models.gd"), model).call()


# --- Materials ---------------------------------------------------------------------

static func material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	m.roughness = 0.5
	match kind:
		"teal":
			m.albedo_color = TEAL
		"teal_light":
			m.albedo_color = TEAL_LIGHT
		"navy":
			m.albedo_color = NAVY
		"steel":
			m.albedo_color = STEEL
			m.metallic = 0.5
			m.roughness = 0.35
		"amber":
			m.albedo_color = AMBER
			m.emission_enabled = true
			m.emission = AMBER
			m.emission_energy_multiplier = 0.7
		"glass":
			m.albedo_color = Color(0.35, 0.95, 1.0, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(0.1, 0.45, 0.5)
		"ice":
			m.albedo_color = Color(0.62, 0.92, 1.0, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.15
			m.emission_enabled = true
			m.emission = Color(0.2, 0.55, 0.65)
		"rock":
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.75
		"ore":
			m.albedo_color = SILVER
			m.metallic = 0.2
			m.roughness = 0.3
			m.emission_enabled = true # reads as shiny metal even without reflections
			m.emission = Color(0.3, 0.32, 0.36)
	_materials[kind] = m
	return m


# --- Building blocks ---------------------------------------------------------------

## A box with its edges and corners cut at 45 degrees: the basic panel of every model.
static func bevel_box(size: Vector3, bevel: float) -> ArrayMesh:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var d := Vector3(dx, dy, dz)
				var axes := []
				for i in 3:
					if d[i] != 0:
						axes.append(i)
				if axes.is_empty():
					continue
				var pts := []
				match axes.size():
					1: # flat face
						var a: int = axes[0]
						for s1 in [-1, 1]:
							for s2 in [-1, 1]:
								var p := Vector3()
								var others := [0, 1, 2].filter(func(i): return i != a)
								p[a] = h[a] * d[a]
								p[others[0]] = (h[others[0]] - b) * s1
								p[others[1]] = (h[others[1]] - b) * s2
								pts.append(p)
					2: # bevelled edge
						var a: int = axes[0]
						var c: int = axes[1]
						var t: int = 3 - a - c
						for s in [-1, 1]:
							var p1 := Vector3()
							p1[a] = h[a] * d[a]
							p1[c] = (h[c] - b) * d[c]
							p1[t] = (h[t] - b) * s
							var p2 := Vector3()
							p2[a] = (h[a] - b) * d[a]
							p2[c] = h[c] * d[c]
							p2[t] = (h[t] - b) * s
							pts.append(p1)
							pts.append(p2)
					3: # cut corner
						for i in 3:
							var p := Vector3()
							for j in 3:
								p[j] = (h[j] if i == j else h[j] - b) * d[j]
							pts.append(p)
				_polygon(st, pts, d)
	return st.commit()


## Adds a flat convex polygon, wound to face `outward`.
static func _polygon(st: SurfaceTool, pts: Array, outward: Vector3) -> void:
	var centre := Vector3()
	for p in pts:
		centre += p
	centre /= pts.size()
	var n := outward.normalized()
	var u: Vector3 = (pts[0] - centre).normalized()
	var v := n.cross(u)
	pts.sort_custom(func(p, q): return atan2((p - centre).dot(v), (p - centre).dot(u)) > atan2((q - centre).dot(v), (q - centre).dot(u)))
	# Sorted clockwise as seen from outside, which Godot treats as the front face.
	var normal: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if normal.dot(n) < 0:
		normal = -normal
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(normal)
			st.add_vertex(p)


static func part(parent: Node3D, mesh: Mesh, kind: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material(kind)
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


static func block(parent: Node3D, size: Vector3, kind: String, pos := Vector3.ZERO, bevel := -1.0, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	if bevel < 0.0:
		bevel = minf(size.x, minf(size.y, size.z)) * 0.22
	return part(parent, bevel_box(size, bevel), kind, pos, rot_deg)


## A cylinder along Y. Few sides give the faceted, chunky look.
static func drum(parent: Node3D, radius: float, height: float, kind: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, sides := 16, top := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return part(parent, c, kind, pos, rot_deg)


static func ball(parent: Node3D, radius: float, kind: String, pos := Vector3.ZERO, hemisphere := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius if hemisphere else radius * 2.0
	s.is_hemisphere = hemisphere
	s.radial_segments = 24
	s.rings = 12
	return part(parent, s, kind, pos)


static func _root(model_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = model_name.to_pascal_case()
	return n


# --- Ships and equipment -----------------------------------------------------------

## The starter ship: a stubby shuttle with a big canopy and twin engines. About 14 m long.
static func starter_ship() -> Node3D:
	var n := _root("starter_ship")
	block(n, Vector3(4.2, 2.4, 9.0), "teal", Vector3(0, 0, 0.6), 0.6) # hull
	block(n, Vector3(4.4, 1.0, 8.0), "navy", Vector3(0, -0.9, 0.9), 0.4) # belly band
	block(n, Vector3(3.6, 2.0, 3.6), "teal_light", Vector3(0, -0.1, -4.6), 0.9) # nose
	block(n, Vector3(3.0, 1.5, 3.0), "glass", Vector3(0, 0.75, -3.9), 0.6) # canopy
	block(n, Vector3(3.3, 0.35, 0.6), "navy", Vector3(0, 0.9, -2.3), 0.12) # canopy frame
	block(n, Vector3(3.0, 0.7, 4.0), "teal_light", Vector3(0, 1.45, 1.4), 0.3) # spine
	for s in [-1, 1]:
		block(n, Vector3(3.2, 0.5, 3.4), "navy", Vector3(3.2 * s, -0.4, 2.6), 0.2) # wing root
		block(n, Vector3(2.4, 0.45, 2.4), "teal", Vector3(4.6 * s, -0.35, 3.0), 0.2) # wing tip
		block(n, Vector3(0.5, 0.2, 0.25), "amber", Vector3(5.5 * s, -0.35, 2.0), 0.05) # nav light
		block(n, Vector3(1.6, 1.6, 3.2), "navy", Vector3(1.3 * s, 0.6, 5.0), 0.35) # engine pod
		drum(n, 0.65, 0.5, "amber", Vector3(1.3 * s, 0.6, 6.7), Vector3(90, 0, 0), 12) # exhaust
		block(n, Vector3(1.0, 0.45, 1.4), "teal_light", Vector3(1.3 * s, 1.5, 5.0), 0.15) # pod cap
		for z in [-2.2, 0.2]:
			block(n, Vector3(0.12, 0.35, 0.9), "amber", Vector3(2.15 * s, -0.3, z), 0.04) # side lights
	return n


## The mining laser emitter that sits under the ship's nose. About 3 m long.
static func mining_laser() -> Node3D:
	var n := _root("mining_laser")
	drum(n, 0.55, 2.2, "teal", Vector3.ZERO, Vector3(90, 0, 0), 10)
	for z in [-0.75, 0.55]:
		drum(n, 0.6, 0.3, "navy", Vector3(0, 0, z), Vector3(90, 0, 0), 10)
	drum(n, 0.5, 0.4, "navy", Vector3(0, 0, -1.25), Vector3(90, 0, 0), 10)
	drum(n, 0.33, 0.06, "amber", Vector3(0, 0, -1.47), Vector3(90, 0, 0), 12) # lens
	drum(n, 0.38, 0.35, "amber", Vector3(0, 0, 1.25), Vector3(90, 0, 0), 10) # power cell
	block(n, Vector3(0.5, 0.35, 0.9), "navy", Vector3(0, -0.6, 0), 0.1) # mount
	block(n, Vector3(0.7, 0.3, 0.6), "teal_light", Vector3(0, 0.6, 0.6), 0.1)
	for x in [-0.56, 0.56]:
		block(n, Vector3(0.06, 0.22, 0.12), "amber", Vector3(x, 0, -0.95), 0.02)
	return n


## A caged canister of ice, the cargo a pilot carries. About 2 m across.
static func ice_canister() -> Node3D:
	var n := _root("ice_canister")
	block(n, Vector3(1.8, 1.8, 1.8), "ice", Vector3.ZERO, 0.55)
	# Three straps crossing at right angles make the cage: thin slices of a slightly larger rounded cube.
	for squash in [Vector3(1, 1, 0.17), Vector3(0.17, 1, 1), Vector3(1, 0.17, 1)]:
		block(n, Vector3(1.92, 1.92, 1.92), "navy", Vector3.ZERO, 0.6).scale = squash
	for p in [Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0), Vector3(0, 0, 1.0), Vector3(0, 0, -1.0)]:
		block(n, Vector3(0.36, 0.5, 0.36) + p.abs() * -0.12, "navy", p, 0.12) # side locks
	drum(n, 0.17, 0.08, "amber", Vector3(0, 0.98, 0), Vector3.ZERO, 8)
	for a in 8:
		var ang := (a + 0.5) * TAU / 8.0
		var p := Vector3(cos(ang), 0, sin(ang)) * 0.93
		block(n, Vector3(0.1, 0.1, 0.1), "amber", p * Vector3(1, 0, 1) + Vector3(0, 0.0, 0), 0.02)
	return n


## A navigation beacon tower with a lamp on top. About 12 m tall, origin at the base.
static func nav_beacon() -> Node3D:
	var n := _root("nav_beacon")
	drum(n, 1.6, 0.8, "navy", Vector3(0, 0.4, 0), Vector3.ZERO, 12)
	block(n, Vector3(2.2, 3.2, 2.2), "teal", Vector3(0, 2.3, 0), 0.4)
	block(n, Vector3(1.9, 3.4, 1.9), "teal_light", Vector3(0, 5.5, 0), 0.35)
	block(n, Vector3(1.7, 1.2, 1.7), "navy", Vector3(0, 7.8, 0), 0.3)
	block(n, Vector3(1.6, 1.7, 1.6), "teal", Vector3(0, 9.2, 0), 0.3)
	block(n, Vector3(0.5, 9.0, 0.7), "navy", Vector3(0.95, 5.0, 0), 0.12) # spine
	drum(n, 0.6, 0.5, "navy", Vector3(0, 10.3, 0), Vector3.ZERO, 12)
	ball(n, 0.6, "amber", Vector3(0, 10.55, 0), true) # lamp
	for y in [2.6, 4.8, 7.0, 9.0]:
		block(n, Vector3(0.12, 0.6, 0.35), "amber", Vector3(1.22, y, 0), 0.04)
	for s in [-1, 1]:
		block(n, Vector3(0.12, 0.8, 0.6), "navy", Vector3(-1.1, 3.0 + s * 0.9, 0), 0.04) # vents
	return n


# --- Raid props --------------------------------------------------------------------

## A locked loot crate. About 1.2 m long, origin at the base.
static func loot_crate() -> Node3D:
	var n := _root("loot_crate")
	block(n, Vector3(1.2, 0.8, 0.8), "teal", Vector3(0, 0.4, 0), 0.08)
	block(n, Vector3(1.22, 0.1, 0.82), "navy", Vector3(0, 0.5, 0), 0.03) # lid seam
	block(n, Vector3(0.36, 0.82, 0.82), "teal_light", Vector3(0, 0.41, 0), 0.06) # centre band
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				block(n, Vector3(0.24, 0.24, 0.24), "navy", Vector3(0.5 * x, 0.4 + 0.3 * y, 0.3 * z), 0.06) # corners
	block(n, Vector3(0.22, 0.28, 0.08), "steel", Vector3(0, 0.45, -0.42), 0.04) # lock
	block(n, Vector3(0.1, 0.1, 0.02), "amber", Vector3(0, 0.42, -0.465), 0.01)
	for x in [-0.3, 0.3]:
		block(n, Vector3(0.08, 0.2, 0.05), "amber", Vector3(x, 0.5, -0.415), 0.01) # clasps
	for s in [-1, 1]:
		block(n, Vector3(0.05, 0.08, 0.36), "amber", Vector3(0.62 * s, 0.55, 0), 0.01) # handles
	return n


## A facility keycard. Credit-card sized: 8.6 cm long.
static func keycard() -> Node3D:
	var n := _root("keycard")
	block(n, Vector3(0.054, 0.006, 0.086), "teal", Vector3.ZERO, 0.0025)
	block(n, Vector3(0.056, 0.0062, 0.02), "navy", Vector3(0, 0, 0.022), 0.002, Vector3(0, -20, 0))
	block(n, Vector3(0.012, 0.007, 0.034), "amber", Vector3(0, 0, -0.004), 0.001) # chip strip
	block(n, Vector3(0.012, 0.0065, 0.004), "navy", Vector3(0.016, 0, -0.036), 0.001) # lanyard slot
	return n


# --- Buildings ---------------------------------------------------------------------

## A habitat dome with lit windows and a door. About 14 m across, origin at the base.
static func habitat_dome() -> Node3D:
	var n := _root("habitat_dome")
	drum(n, 7.4, 1.2, "navy", Vector3(0, 0.6, 0), Vector3.ZERO, 24)
	drum(n, 7.0, 0.5, "navy", Vector3(0, 1.4, 0), Vector3.ZERO, 24)
	ball(n, 6.6, "teal", Vector3(0, 1.4, 0), true)
	drum(n, 1.4, 0.4, "teal_light", Vector3(0, 8.0, 0), Vector3.ZERO, 8) # roof hatch
	for a in [-35.0, 35.0, 145.0, 215.0]:
		var dir := Vector3(sin(deg_to_rad(a)), 0, -cos(deg_to_rad(a)))
		var w := Node3D.new()
		w.position = Vector3(0, 3.6, 0) + dir * 6.0
		w.rotation.y = -deg_to_rad(a)
		w.rotation_degrees.x = 18
		n.add_child(w)
		block(w, Vector3(3.6, 3.8, 0.9), "navy", Vector3.ZERO, 0.6) # window frame
		block(w, Vector3(2.9, 3.1, 0.4), "amber", Vector3(0, 0, -0.38), 0.45) # lit window
	var door := Node3D.new()
	door.position = Vector3(0, 0, -6.4)
	n.add_child(door)
	block(door, Vector3(2.0, 2.6, 1.4), "teal_light", Vector3(0, 2.4, 0), 0.3)
	block(door, Vector3(1.2, 1.4, 0.4), "amber", Vector3(0, 2.2, -0.6), 0.15)
	block(n, Vector3(1.6, 0.6, 0.6), "navy", Vector3(2.4, 7.0, -2.6), 0.15, Vector3(-40, 0, 0)) # vent
	return n


# --- Asteroids ---------------------------------------------------------------------

## A lumpy ice asteroid with pale crystals poking out. `radius` in metres; `seed` picks the shape.
static func ice_asteroid(radius := 20.0, seed := 1) -> Node3D:
	var n := _root("ice_asteroid")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	part(n, _rock_mesh(radius, seed), "rock")
	for i in rng.randi_range(8, 12):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var length := radius * rng.randf_range(0.45, 0.9)
		var crystal := Node3D.new()
		crystal.position = dir * radius * 0.7
		n.add_child(crystal)
		crystal.basis = Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, rng.randf() * TAU)
		var w := length * 0.26
		drum(crystal, w, length, "ice", Vector3(0, length * 0.5, 0), Vector3.ZERO, 6)
		drum(crystal, w, length * 0.35, "ice", Vector3(0, length + length * 0.175, 0), Vector3.ZERO, 6, 0.0)
	return n


## A grey-blue asteroid with raised veins of shiny metal ore.
static func metal_asteroid(radius := 20.0, seed := 1) -> Node3D:
	var n := _root("metal_asteroid")
	part(n, _rock_mesh(radius, seed, ROCK.darkened(0.2)), "rock")
	var noise := _rock_noise(seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5
	for v in 5:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var start := axis.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		var span := rng.randf_range(2.2, 3.4)
		var steps := 14
		var prev := Vector3.ZERO
		for i in steps + 1:
			var dir := start.rotated(axis, span * i / steps).rotated(axis.cross(start).normalized(), 0.18 * sin(i * 0.9 + v))
			var p := _rock_surface(dir.normalized(), radius, noise) * 1.02
			if i > 0:
				var mid := (p + prev) * 0.5
				var seg := Node3D.new()
				seg.position = mid
				n.add_child(seg)
				seg.look_at_from_position(mid, p, mid.normalized() if absf(mid.normalized().dot((p - prev).normalized())) < 0.99 else Vector3.UP)
				block(seg, Vector3(radius * 0.13, radius * 0.07, prev.distance_to(p) * 1.15), "ore", Vector3.ZERO, radius * 0.03)
			prev = p
	return n


static func _rock_noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.4
	return noise


const ROCK_STRETCH := Vector3(1.15, 0.85, 1.0)


## Where the rock's surface is in direction `u` (a unit vector).
static func _rock_surface(u: Vector3, radius: float, noise: FastNoiseLite) -> Vector3:
	var bump := 1.0 + 0.28 * noise.get_noise_3dv(u) + 0.08 * noise.get_noise_3dv(u * 3.0)
	return u * bump * radius * ROCK_STRETCH


static func _rock_mesh(radius: float, seed: int, base := ROCK) -> ArrayMesh:
	var noise := _rock_noise(seed)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 18
	sphere.rings = 11
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	for v in verts:
		moved.append(_rock_surface(v.normalized(), radius, noise))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := moved[idx[t]]
		var b := moved[idx[t + 1]]
		var c := moved[idx[t + 2]]
		var centre := (a + b + c) / 3.0
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(centre) < 0:
			normal = -normal
			var swap := b
			b = c
			c = swap
		var col := base.darkened(0.18 * (0.5 + 0.5 * noise.get_noise_3dv(centre / radius * 2.0)))
		for p in [a, c, b]: # clockwise from outside
			st.set_color(col)
			st.set_normal(normal)
			st.add_vertex(p)
	return st.commit()
