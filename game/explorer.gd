extends Node3D
## Explorer mode (PC): fly a ship around Teal Prime, mine ice, land at the Spaceport, deliver jobs.
## Everything is built from simple shapes in code, so there are no art assets yet.
##
## Controls: W/S thrust, A/D turn, R/F pitch, Space brake, hold E to mine or deliver.

const ACCEL := 30.0
const MAX_SPEED := 60.0
const TURN := 1.6
const SEND_EVERY := 0.1
const MINE_EVERY := 0.4

const PLANET_POS := Vector3(0, 0, -200)
const PLANET_RADIUS := 40.0
const PORT_POS := Vector3(0, PLANET_RADIUS + 2, -200)
const FIELD_POS := Vector3(120, 10, -80)

var _ship: Node3D
var _velocity := Vector3.ZERO
var _port: Node3D
var _asteroids: Array[Node3D] = []
var _others := {} # id -> {"node": Node3D, "pos": Vector3, "rot": Vector3}
var _hud: Label
var _prompt: Label
var _send_timer := 0.0
var _mine_timer := 0.0


func _ready() -> void:
	_build_space()
	_ship = _make_ship(Color(0.3, 0.9, 0.85))
	_ship.position = Vector3(0, 0, 60)
	add_child(_ship)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3, 11)
	cam.rotation_degrees.x = -8
	cam.far = 4000
	_ship.add_child(cam)
	cam.make_current()
	_build_hud()

	Net.state_changed.connect(_on_state)
	Net.ship_moved.connect(_on_ship_moved)
	Net.ship_left.connect(_on_ship_left)
	Net.server_error.connect(func(reason): _prompt.text = "Server: " + reason)


# --- World -------------------------------------------------------------------

func _build_space() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.4)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -40, 0)
	add_child(sun)

	_add_sphere(Vector3(-600, 100, -900), 60, Color(1.0, 0.85, 0.5), true) # the star
	_add_sphere(PLANET_POS, PLANET_RADIUS, Color(0.15, 0.55, 0.55), false) # planet Aster

	var rng := RandomNumberGenerator.new()
	rng.seed = 7 # same field for every player
	for i in 30:
		var offset := Vector3(rng.randf_range(-40, 40), rng.randf_range(-15, 15), rng.randf_range(-40, 40))
		_asteroids.append(_add_sphere(FIELD_POS + offset, rng.randf_range(1.5, 4.0), Color(0.75, 0.85, 0.95), false))

	# Background stars.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 2.0
	dot.height = 4.0
	dot.material = _material(Color.WHITE, true)
	mm.mesh = dot
	mm.instance_count = 500
	for i in mm.instance_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(), dir * 2500))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	add_child(stars)

	# The Spaceport only appears once a builder has built it on the phone.
	_port = Node3D.new()
	_port.position = PORT_POS
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(14, 2, 14)
	box.material = _material(Color(0.9, 0.6, 0.2), false)
	pad.mesh = box
	_port.add_child(pad)
	var tag := Label3D.new()
	tag.text = "Spaceport"
	tag.position = Vector3(0, 6, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 96
	_port.add_child(tag)
	_port.visible = false
	add_child(_port)


func _add_sphere(pos: Vector3, radius: float, color: Color, glow: bool) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.material = _material(color, glow)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	add_child(node)
	return node


func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _make_ship(color: Color) -> Node3D:
	var ship := Node3D.new()
	var body := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.4, 4, 0.8)
	prism.material = _material(color, false)
	body.mesh = prism
	body.rotation_degrees.x = -90 # tip points forward (-Z)
	ship.add_child(body)
	return ship


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 16)
	layer.add_child(_hud)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 60
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", 20)
	layer.add_child(_prompt)


# --- Flying ------------------------------------------------------------------

func _process(delta: float) -> void:
	var throttle := _key(KEY_W) - _key(KEY_S)
	var yaw := _key(KEY_A) - _key(KEY_D)
	var pitch := _key(KEY_R) - _key(KEY_F)
	_ship.rotate_object_local(Vector3.UP, yaw * TURN * delta)
	_ship.rotate_object_local(Vector3.RIGHT, pitch * TURN * delta)
	_velocity += -_ship.global_basis.z * throttle * ACCEL * delta
	if Input.is_physical_key_pressed(KEY_SPACE):
		_velocity = _velocity.move_toward(Vector3.ZERO, ACCEL * 2 * delta)
	_velocity = (_velocity * (1.0 - 0.3 * delta)).limit_length(MAX_SPEED)
	_ship.position += _velocity * delta

	# Keep the ship out of the planet.
	var from_planet := _ship.position - PLANET_POS
	if from_planet.length() < PLANET_RADIUS + 3:
		_ship.position = PLANET_POS + from_planet.normalized() * (PLANET_RADIUS + 3)
		_velocity = Vector3.ZERO

	_send_timer -= delta
	if _send_timer <= 0:
		_send_timer = SEND_EVERY
		var p := _ship.position
		var r := _ship.rotation
		Net.send({"type": "ship", "pos": [p.x, p.y, p.z], "rot": [r.x, r.y, r.z]})

	for id in _others:
		var o: Dictionary = _others[id]
		o.node.position = o.node.position.lerp(o.pos, min(1.0, delta * 10))
		o.node.rotation = o.rot

	_mine_timer -= delta
	_interact()
	_update_hud()


func _key(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0


func _interact() -> void:
	var holding_e := Input.is_physical_key_pressed(KEY_E)
	if _near_asteroid():
		_prompt.text = "Hold E to mine ice"
		if holding_e and _mine_timer <= 0:
			_mine_timer = MINE_EVERY
			Net.send({"type": "collect", "resource": "ice", "amount": 1})
	elif _port.visible and _ship.position.distance_to(PORT_POS) < 18:
		var job := Net.open_job()
		if job.is_empty():
			_prompt.text = "Landed at the Spaceport. No open jobs."
		elif _cargo(job.resource) <= 0:
			_prompt.text = "Job #%d wants %s. Go mine some." % [job.id, job.resource]
		else:
			_prompt.text = "Press E to deliver %d %s for job #%d" % [_cargo(job.resource), job.resource, job.id]
			if holding_e and _mine_timer <= 0:
				_mine_timer = 1.0
				Net.send({"type": "deliver", "job": int(job.id)})
	else:
		_prompt.text = ""


func _near_asteroid() -> bool:
	for a in _asteroids:
		if _ship.position.distance_to(a.position) < 10:
			return true
	return false


func _me() -> Dictionary:
	if Net.state.is_empty():
		return {}
	return Net.state.pilots.get(Net.my_name, {})


func _cargo(resource: String) -> int:
	var me := _me()
	return int(me.get("cargo", {}).get(resource, 0)) if not me.is_empty() else 0


func _update_hud() -> void:
	var me := _me()
	var job := Net.open_job()
	_hud.text = "%s\nSpeed %d\nIce in cargo %d\nCredits %d   Reputation %d\n%s\n\nW/S thrust  A/D turn  R/F pitch  Space brake  E interact" % [
		Net.my_name,
		_velocity.length(),
		_cargo("ice"),
		int(me.get("credits", 0)),
		int(me.get("reputation", 0)),
		("Job #%d: deliver %s %d/%d to the Spaceport on Aster" % [job.id, job.resource, job.delivered, job.amount]) if not job.is_empty() else "No open jobs",
	]


# --- Server events -----------------------------------------------------------

func _on_state(_state: Dictionary) -> void:
	_port.visible = Net.has_building("spaceport")


func _on_ship_moved(id: int, pilot_name: String, pos: Vector3, rot: Vector3) -> void:
	if not _others.has(id):
		var node := _make_ship(Color(0.95, 0.4, 0.6))
		var tag := Label3D.new()
		tag.text = pilot_name
		tag.position = Vector3(0, 3, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 64
		node.add_child(tag)
		node.position = pos
		add_child(node)
		_others[id] = {"node": node, "pos": pos, "rot": rot}
	_others[id].pos = pos
	_others[id].rot = rot


func _on_ship_left(id: int) -> void:
	if _others.has(id):
		_others[id].node.queue_free()
		_others.erase(id)
