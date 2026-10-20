extends Node3D
## The other pilots on foot in a shared space with you: everyone in the same station copy, aboard the
## same carrier, or walking the same Builder's base. Every place (carrier.gd, station.gd, surface.gd)
## has one of these; it draws each pilot as a simple figure and sends your own position.
##
## The server's shared spaces (server/spaces.js): the explorer enters a space ("station:cinder",
## "ship:Akane", "surface:aster") and sets the place's `space_id`. The server answers `space_joined`
## with who is there, then relays `walker` updates (position, facing, walk/run/sit) and `walker_left`.
## Positions are the place's own coordinates (the place sits at the scene origin): the point on the
## floor under the walker.

const SEND_EVERY := 1.0 / 12.0 # walk updates a second while moving (the server takes up to 15)
const KEEPALIVE := 2.0 # seconds between updates while standing still
const SKIN := Color(0.16, 0.17, 0.2) # the flight suit under the armour

var place: Node3D # the place.gd this belongs to; its `space_id` says which space we're in
var _figures := {} # id -> {"node", "body", "legs", "arms", "target", "yaw", "anim", "name", "faction", "phase"}
var _joined := "" # the space the server last told us we joined
var _send_in := 0.0
var _keepalive := 0.0
var _last_sent := {}


func _init(owner_place: Node3D = null) -> void:
	place = owner_place


func _ready() -> void:
	Net.message.connect(on_message)


func _exit_tree() -> void:
	if Net.message.is_connected(on_message):
		Net.message.disconnect(on_message)


func space() -> String:
	return str(place.get("space_id")) if place else ""


## Server messages about walkers. The explorer also hands over a `space_joined` that arrived before
## this place existed (boarding someone's carrier waits for the server's yes).
func on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"space_joined":
			if str(msg.get("space", "")) != space():
				return
			clear()
			_joined = space()
			_last_sent = {}
			for o in msg.get("others", []):
				if o is Dictionary:
					_upsert(o)
		"walker":
			if _joined != "" and _joined == space():
				_upsert(msg)
		"walker_left":
			_remove(int(msg.get("id", -1)))


## Who is here besides you: [{"name", "faction", "anim"}].
func people() -> Array:
	var out := []
	for id in _figures:
		var f: Dictionary = _figures[id]
		out.append({"name": f.name, "faction": f.faction, "anim": f.anim})
	return out


## The figure for a pilot by name, or null (for tests).
func figure_of(pilot: String) -> Node3D:
	for id in _figures:
		if _figures[id].name == pilot:
			return _figures[id].node
	return null


## A new connection: whoever we saw is gone until the server says again who is here.
func rejoin() -> void:
	_joined = ""
	clear()


func clear() -> void:
	for id in _figures:
		_figures[id].node.queue_free()
	_figures.clear()


func _upsert(o: Dictionary) -> void:
	var id := int(o.get("id", -1))
	if id < 0 or id == Net.my_id:
		return
	var p = o.get("pos", [])
	if not (p is Array) or p.size() != 3:
		return
	var target := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var faction = o.get("faction")
	if not _figures.has(id):
		var pilot := str(o.get("name", "Pilot"))
		var node := figure(pilot, _colour(faction))
		add_child(node)
		node.position = target
		_figures[id] = {"node": node, "body": node.get_node("Body"), "target": target, "yaw": float(o.get("yaw", 0.0)),
			"anim": "idle", "name": pilot, "faction": faction, "phase": 0.0}
		node.rotation.y = float(o.get("yaw", 0.0))
	var f: Dictionary = _figures[id]
	f.target = target
	f.yaw = float(o.get("yaw", f.yaw))
	f.anim = str(o.get("anim", "idle"))


func _remove(id: int) -> void:
	if _figures.has(id):
		_figures[id].node.queue_free()
		_figures.erase(id)


func _colour(faction) -> Color:
	var hex := str(Net.catalog.get("factions", {}).get(str(faction), {}).get("color", "")) if faction != null else ""
	return Color.html(hex) if Color.html_is_valid(hex) else Color(0.55, 0.6, 0.66)


func _process(delta: float) -> void:
	if _joined != space() and not _figures.is_empty():
		clear() # we've moved on to another space; its server answer brings the new crowd
	for id in _figures:
		_animate(_figures[id], delta)
	_send_own(delta)


## Eases a figure toward its last reported spot and moves its limbs: a walk or run cycle, standing,
## or sitting (thighs forward, shins down).
func _animate(f: Dictionary, delta: float) -> void:
	var node: Node3D = f.node
	var from := node.position
	if from.distance_to(f.target) > 6.0:
		node.position = f.target # too far to walk it: they went through a door or a lift
	else:
		node.position = from.lerp(f.target, minf(1.0, delta * 10.0))
	var moved := Vector2(node.position.x - from.x, node.position.z - from.z).length() / maxf(delta, 0.001)
	node.rotation.y = lerp_angle(node.rotation.y, f.yaw, minf(1.0, delta * 10.0))
	var body: Node3D = f.body
	var sitting: bool = f.anim == "sit"
	var stride := 0.0
	if not sitting and (moved > 0.3 or f.anim == "walk" or f.anim == "run"):
		var speed := maxf(moved, 4.2 if f.anim == "walk" else (7.0 if f.anim == "run" else 0.0))
		f.phase += delta * speed * 2.1
		stride = 0.55 if speed > 5.5 else 0.4
	else:
		f.phase = lerpf(f.phase, roundf(f.phase / PI) * PI, minf(1.0, delta * 8.0))
	var swing := sin(f.phase) * stride
	body.position.y = (-0.42 if sitting else absf(sin(f.phase)) * stride * 0.08)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var thigh: Node3D = body.get_node("Thigh%d" % i)
		var shin: Node3D = thigh.get_node("Shin")
		var arm: Node3D = body.get_node("Arm%d" % i)
		if sitting:
			thigh.rotation.x = PI / 2.0
			shin.rotation.x = -PI / 2.0
			arm.rotation.x = 0.5
		else:
			thigh.rotation.x = swing * side
			shin.rotation.x = -maxf(0.0, -sin(f.phase) * side) * stride * 1.4
			arm.rotation.x = -swing * side * 0.8


## Your own position for the others, while the server has us in this place's space.
func _send_own(delta: float) -> void:
	_send_in -= delta
	_keepalive -= delta
	if _joined == "" or _joined != space() or not place.has_method("walker_pose"):
		return
	var pose: Dictionary = place.walker_pose()
	if pose.is_empty() or _send_in > 0.0:
		return
	var pos: Vector3 = pose.pos
	var changed: bool = _last_sent.is_empty() or pos.distance_to(_last_sent.pos) > 0.03 or absf(angle_difference(float(pose.yaw), float(_last_sent.yaw))) > 0.03 or pose.anim != _last_sent.anim
	if not changed and _keepalive > 0.0:
		return
	_send_in = SEND_EVERY
	_keepalive = KEEPALIVE
	_last_sent = pose
	Net.send({"type": "walk", "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": snappedf(float(pose.yaw), 0.001), "anim": pose.anim})


## A pilot on foot: boots, legs, a flight suit, armour in their faction's colour (chest plate,
## shoulders, helmet), a lit visor and a name tag. About 1.85 m tall; feet at the origin, facing -Z.
## The limbs hang from pivots so the walk cycle can swing them.
static func figure(pilot: String, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Walker"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var armour := colour.lerp(Color(0.6, 0.62, 0.66), 0.25)
	for i in 2:
		var x := 0.12 if i == 0 else -0.12
		var thigh := Node3D.new()
		thigh.name = "Thigh%d" % i
		thigh.position = Vector3(x, 0.92, 0)
		body.add_child(thigh)
		_part(thigh, BoxMesh.new(), Vector3(0.17, 0.46, 0.2), Vector3(0, -0.23, 0), SKIN)
		_part(thigh, BoxMesh.new(), Vector3(0.19, 0.16, 0.22), Vector3(0, -0.12, -0.01), armour)
		var shin := Node3D.new()
		shin.name = "Shin"
		shin.position = Vector3(0, -0.46, 0)
		thigh.add_child(shin)
		_part(shin, BoxMesh.new(), Vector3(0.15, 0.4, 0.18), Vector3(0, -0.2, 0), SKIN)
		_part(shin, BoxMesh.new(), Vector3(0.18, 0.1, 0.3), Vector3(0, -0.41, -0.05), Color(0.1, 0.1, 0.12)) # boot
		var arm := Node3D.new()
		arm.name = "Arm%d" % i
		arm.position = Vector3(x * 2.6, 1.52, 0)
		body.add_child(arm)
		_part(arm, BoxMesh.new(), Vector3(0.12, 0.58, 0.14), Vector3(0, -0.29, 0), SKIN)
		_part(arm, BoxMesh.new(), Vector3(0.2, 0.16, 0.22), Vector3(0, 0.02, 0), armour) # shoulder pad
	var torso := CapsuleMesh.new()
	torso.radius = 0.22
	torso.height = 0.78
	_part(body, torso, Vector3.ONE, Vector3(0, 1.3, 0), SKIN)
	_part(body, BoxMesh.new(), Vector3(0.44, 0.4, 0.12), Vector3(0, 1.36, -0.18), armour) # chest plate
	_part(body, BoxMesh.new(), Vector3(0.36, 0.46, 0.16), Vector3(0, 1.32, 0.21), Color(0.24, 0.26, 0.3)) # pack
	_part(body, BoxMesh.new(), Vector3(0.42, 0.08, 0.36), Vector3(0, 0.98, 0), Color(0.1, 0.1, 0.12)) # belt
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	_part(body, head, Vector3.ONE, Vector3(0, 1.75, 0), armour.lightened(0.15)) # helmet
	_part(body, BoxMesh.new(), Vector3(0.22, 0.08, 0.06), Vector3(0, 1.77, -0.13), Color(0.3, 0.9, 1.0), 2.0) # visor
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = pilot
	tag.position = Vector3(0, 2.2, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = 48
	tag.outline_size = 10
	tag.modulate = colour.lightened(0.45)
	root.add_child(tag)
	return root


static func _part(parent: Node3D, mesh: PrimitiveMesh, size: Vector3, pos: Vector3, colour: Color, glow := 0.0) -> void:
	if mesh is BoxMesh:
		mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
