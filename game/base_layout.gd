extends RefCounted
## The layout of a Builder's home base, shared by the phone's base view (builder.gd) and the base
## pilots land at and walk around (surface.gd): the Command Centre in the middle and eight nodes
## around it in a square, one per building (the server's NODES), streets between them, and a wall
## with turrets all round. About 300 m across: a few city blocks.
## Positions are in metres on the ground, the Command Centre at the origin; the Star Port's side
## (+Z) is the front, where the gate is and pilots land.

const BaseModels := preload("res://base_models.gd")

## Node slot -> building type, as the server has it (galaxy.js NODES). Slot 8 is the Command Centre.
const NODES := ["spaceport", "extractor", "habitat", "hydroponics", "warehouse", "power", "foundry", "dock"]
const COMMAND_SLOT := 8
## Each slot's cell in the 3x3 square: (column, row), -1..1 on X and Z.
const CELLS := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0)]

const CELL := 80.0 # metres between node centres
const NODE_SIZE := 56.0 # a node's plate, square
const COMMAND_SIZE := 64.0
const STREET := 14.0 # the streets' width
const WALL := 150.0 # the wall's distance from the middle, on each side
const GATE := 28.0 # the gate's width, in the front wall
const MODEL_SCALE := 3.0 # the building models are drawn at about a third of this size
const COMMAND_SCALE := 3.4
const BERTH_ROW := CELL + NODE_SIZE * 0.5 + 21.0 # the Star Port's berths, along the front apron
const BERTH_RADIUS := 10.0
const BERTHS_MAX := 10
const FLAT := WALL * 1.5 # the terrain stays flat this far out, past the wall's corners

const STREET_COLOUR := Color(0.13, 0.16, 0.22)
const GROUND_COLOUR := Color(0.2, 0.25, 0.35)


## Where Star Port berth `i` (from 0) is: either side of the avenue, nearest the gate first.
static func berth_pos(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	return Vector3(side * (GATE * 0.5 + 16.0 + (i / 2) * 26.0), 0, BERTH_ROW)


## The Star Port's berths: a pad for each of BERTHS_MAX, lit when the Star Port's level opens it.
static func berths(open: int) -> Node3D:
	var n := Node3D.new()
	for i in BERTHS_MAX:
		var pad := BaseModels.landing_pad(BERTH_RADIUS, i < open)
		pad.position = berth_pos(i) + Vector3(0, 0.4, 0)
		n.add_child(pad)
	return n


static func slot_pos(slot: int) -> Vector3:
	var c: Vector2i = CELLS[slot]
	return Vector3(c.x * CELL, 0, c.y * CELL)


static func plate_size(slot: int) -> float:
	return COMMAND_SIZE if slot == COMMAND_SLOT else NODE_SIZE


## The slot whose plate is under a point on the ground, or -1.
static func slot_at(point: Vector3) -> int:
	for slot in CELLS.size():
		var d := point - slot_pos(slot)
		if absf(d.x) <= plate_size(slot) * 0.5 and absf(d.z) <= plate_size(slot) * 0.5:
			return slot
	return -1


## Which way a building on `slot` faces (its front, -Z, toward the Command Centre), as a yaw.
static func slot_yaw(slot: int) -> float:
	if slot == COMMAND_SLOT:
		return 0.0 # the door toward the gate
	var p := slot_pos(slot)
	return atan2(p.x, p.z)


## The model for a building of `type` at `level` (0: still being built), sized for the base.
static func building(type: String, level: int) -> Node3D:
	var m: Node3D
	if level == 0:
		m = BaseModels.construction(14.0)
	elif type == "command":
		m = BaseModels.command_center_at(level)
	else:
		m = BaseModels.building(type)
	m.scale = Vector3.ONE * (COMMAND_SCALE if type == "command" else MODEL_SCALE)
	return m


## The ground: the base's paved square, its streets, and a plate on every node.
static func ground(material: Callable) -> Node3D:
	var n := Node3D.new()
	var pave := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WALL * 2.0 + 8.0, 0.4, WALL * 2.0 + 8.0)
	pave.mesh = box
	pave.position.y = 0.2
	pave.material_override = material.call(GROUND_COLOUR)
	n.add_child(pave)
	# Streets: two each way between the rows and columns of nodes, and the avenue out to the gate.
	for i in [-1, 1]:
		var along: float = CELL * 0.5 * i
		for rot in [0.0, 90.0]:
			var street := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(STREET, 0.1, WALL * 2.0 - 10.0)
			street.mesh = sb
			street.position = Vector3(along, 0.42, 0) if rot == 0.0 else Vector3(0, 0.43, along)
			street.rotation_degrees.y = rot
			street.material_override = material.call(STREET_COLOUR)
			n.add_child(street)
	var avenue := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(GATE - 4.0, 0.1, WALL - CELL - NODE_SIZE * 0.5)
	avenue.mesh = ab
	avenue.position = Vector3(0, 0.43, WALL - ab.size.z * 0.5)
	avenue.material_override = material.call(STREET_COLOUR)
	n.add_child(avenue)
	for slot in CELLS.size():
		var plate := BaseModels.node_plate(plate_size(slot))
		plate.position = slot_pos(slot) + Vector3(0, 0.4, 0)
		n.add_child(plate)
	return n


## Where the wall's turrets stand at a Command Centre `level`: the corners from the start, either
## side of the gate and the middle of the other walls from level 3, and every quarter from level 5.
static func turret_spots(level: int) -> Array:
	var out := []
	for x in [-1, 1]:
		for z in [-1, 1]:
			out.append(Vector3(x * WALL, 0, z * WALL))
	if level >= 3:
		out.append_array([Vector3(-GATE, 0, WALL), Vector3(GATE, 0, WALL), Vector3(0, 0, -WALL), Vector3(-WALL, 0, 0), Vector3(WALL, 0, 0)])
	if level >= 5:
		for f in [-0.5, 0.5]:
			out.append_array([Vector3(f * WALL, 0, -WALL), Vector3(-WALL, 0, f * WALL), Vector3(WALL, 0, f * WALL)])
		out.append_array([Vector3(-WALL * 0.6, 0, WALL), Vector3(WALL * 0.6, 0, WALL)])
	return out


## The wall all round, with corner towers, the gate in the front, and turrets for the level.
static func wall(level: int) -> Node3D:
	var n := Node3D.new()
	var side := WALL * 2.0
	for i in 3: # back, left, right: one stretch each
		var w := BaseModels.wall(side)
		w.position = [Vector3(0, 0, -WALL), Vector3(-WALL, 0, 0), Vector3(WALL, 0, 0)][i]
		w.rotation_degrees.y = [0.0, 90.0, 90.0][i]
		n.add_child(w)
	var stretch := WALL - GATE * 0.5 # the front, either side of the gate
	for s in [-1, 1]:
		var w := BaseModels.wall(stretch)
		w.position = Vector3(s * (GATE * 0.5 + stretch * 0.5), 0, WALL)
		n.add_child(w)
		var post := BaseModels.wall_tower()
		post.position = Vector3(s * GATE * 0.5, 0, WALL)
		post.scale = Vector3(0.8, 1.2, 0.8)
		n.add_child(post)
	for x in [-1, 1]:
		for z in [-1, 1]:
			var t := BaseModels.wall_tower()
			t.position = Vector3(x * WALL, 0, z * WALL)
			n.add_child(t)
	for spot in turret_spots(level):
		var tur := BaseModels.turret()
		var on_tower: bool = absf(absf(spot.x) - WALL) < 1.0 and absf(absf(spot.z) - WALL) < 1.0
		tur.position = spot + Vector3(0, 14.0 if on_tower else 9.8, 0)
		tur.scale = Vector3.ONE * 2.2
		tur.rotation.y = atan2(-spot.x, -spot.z) # facing out
		n.add_child(tur)
	return n
