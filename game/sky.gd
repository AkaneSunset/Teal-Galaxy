extends SubViewport
## Draws the star, planets and background stars at true scale, behind the local scene.
##
## Planets are millions of metres across and billions of metres away, far beyond what the main
## camera's depth range can hold next to a ship a few metres from your face. So the sky lives in
## its own world, measured in kilometres, with a camera that copies the pilot's view. The main
## view shows this texture as its background.

const System := preload("res://teal_prime.gd")
const KM := 1000.0

var _camera: Camera3D
var _bodies := [] # {"node": Node3D, "pos": Array, "radius": float}


func _init() -> void:
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.08)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	_camera = Camera3D.new()
	_camera.far = 3.0e9
	_camera.near = 1.0
	add_child(_camera)
	_camera.make_current()

	for body in System.bodies():
		_bodies.append({"node": _make_body(body), "pos": body.pos, "radius": body.radius})

	# The star lights the planets.
	var light := OmniLight3D.new()
	light.omni_range = 4.0e9
	light.omni_attenuation = 0.0
	light.light_energy = 1.4
	_bodies[0].node.add_child(light)

	_add_background_stars()


## Adds a planet that appeared after the sky was built (a new Builder's home).
func add_body(body: Dictionary) -> void:
	_bodies.append({"node": _make_body(body), "pos": body.pos, "radius": body.radius})


func _make_body(body: Dictionary) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = body.radius / KM
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	if body.kind == "star":
		mat.albedo_color = body.color
		mat.emission_enabled = true
		mat.emission = body.color
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.albedo_texture = _surface(body)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	add_child(node)
	return node


func _surface(body: Dictionary) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = hash(body.id)
	noise.frequency = 0.012 if not body.bands else 0.004
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	var c: Color = body.color
	ramp.set_color(0, c.darkened(0.45))
	ramp.set_color(1, c.lightened(0.35))
	ramp.add_point(0.5, c)
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 256
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	if body.bands:
		# Stretch the noise sideways so a gas giant gets bands.
		tex.width = 64
		tex.height = 512
	return tex


func _add_background_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var dot := QuadMesh.new()
	dot.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	mm.mesh = dot
	mm.instance_count = 1500
	var distance := 2.0e9
	for i in mm.instance_count:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size := distance * rng.randf_range(0.0008, 0.0022)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), dir * distance))
		var warm := rng.randf()
		mm.set_instance_color(i, Color(0.8 + 0.2 * warm, 0.85, 1.0 - 0.25 * warm) * rng.randf_range(0.5, 1.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.name = "Stars"
	add_child(stars)


## Point the sky camera like the pilot's camera, from the ship's position in the system.
func follow(ship_pos: Array, view: Basis) -> void:
	_camera.global_basis = view
	var nearest := INF
	for b in _bodies:
		var rel := System.diff(b.pos, ship_pos) / KM
		b.node.position = rel
		nearest = minf(nearest, rel.length() - b.radius / KM)
	# Keep the near plane as far out as possible so the depth buffer stays precise.
	_camera.near = clampf(nearest * 0.5, 0.05, 50_000.0)
