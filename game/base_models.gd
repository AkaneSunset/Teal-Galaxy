extends RefCounted
## Stand-in models for the Builder's base view, in the same style as models.gd: bevelled teal
## panels, navy trim and amber lights. A building uses the real model from models.gd once one
## with its name is listed in Models.ALL; until then the stand-in below is used.
## Sizes are in metres, origins at the base, fronts face -Z.

const Models := preload("res://models.gd")

## Which models.gd model stands for each building type.
const REAL_MODEL := {"habitat": "habitat_dome", "mine": "mine", "spaceport": "spaceport",
	"hydroponics": "hydroponics", "refinery": "refinery", "lab": "research_outpost", "spire": "data_spire", "foundry": "ship_foundry"}


static func building(type: String) -> Node3D:
	var real: String = REAL_MODEL.get(type, "")
	if real in Models.ALL:
		return Models.make(real)
	match type:
		"mine":
			return mine()
		"extractor":
			return ice_extractor()
		"spaceport":
			return spaceport()
		"hydroponics":
			return hydroponics()
		"refinery":
			return refinery()
		"lab":
			return research_outpost()
		"spire":
			return data_spire()
		"foundry":
			return ship_foundry()
	return Models.habitat_dome()


static func _b(n: Node3D, size: Vector3, kind: String, pos: Vector3, bevel := -1.0, rot := Vector3.ZERO) -> void:
	Models.block(n, size, kind, pos, bevel, rot)


static func _d(n: Node3D, r: float, h: float, kind: String, pos: Vector3, sides := 16, top := -1.0, rot := Vector3.ZERO) -> void:
	Models.drum(n, r, h, kind, pos, rot, sides, top)


## A build pad: a low octagonal platform with a navy rim and amber corner lights. 18 m across.
static func pad() -> Node3D:
	var n := Node3D.new()
	_d(n, 9.4, 0.6, "navy", Vector3(0, 0.3, 0), 8)
	_d(n, 8.6, 0.3, "steel", Vector3(0, 0.75, 0), 8)
	for i in 8:
		var a := (i + 0.5) * TAU / 8.0
		_b(n, Vector3(0.8, 0.3, 0.8), "amber", Vector3(cos(a), 0, sin(a)) * 8.7 + Vector3(0, 0.65, 0), 0.1)
	return n


## The base's centrepiece: a stepped command tower with a dish and a beacon lamp.
static func command_center() -> Node3D:
	var n := Node3D.new()
	_d(n, 10.0, 1.0, "navy", Vector3(0, 0.5, 0), 8)
	_b(n, Vector3(12, 5, 12), "teal", Vector3(0, 3.5, 0), 1.2)
	_b(n, Vector3(12.4, 0.8, 12.4), "navy", Vector3(0, 5.6, 0), 0.3)
	_b(n, Vector3(8, 5, 8), "teal_light", Vector3(0, 8.4, 0), 1.0)
	_b(n, Vector3(6.4, 1.6, 0.5), "amber", Vector3(0, 8.6, -4.0), 0.2)
	_b(n, Vector3(0.5, 1.6, 6.4), "amber", Vector3(-4.0, 8.6, 0), 0.2)
	_d(n, 2.0, 3.0, "navy", Vector3(0, 12.4, 0), 10)
	_d(n, 0.5, 4.0, "steel", Vector3(0, 15.5, 0), 8)
	Models.ball(n, 0.9, "amber", Vector3(0, 17.4, 0))
	var dish := Node3D.new()
	dish.position = Vector3(3.0, 11.6, 3.0)
	dish.rotation_degrees = Vector3(35, 45, 0)
	n.add_child(dish)
	_d(dish, 2.6, 0.4, "teal_light", Vector3.ZERO, 12, 1.4)
	_d(dish, 0.25, 1.8, "navy", Vector3(0, 0.9, 0), 6)
	for s in [-1, 1]:
		_b(n, Vector3(2.6, 3.0, 1.6), "teal_light", Vector3(s * 3.0, 2.0, -6.2), 0.4) # door posts
	_b(n, Vector3(3.2, 2.6, 0.6), "amber", Vector3(0, 1.8, -6.1), 0.2) # door
	return n


## A drill rig over an ore pit, with a hopper and a lit cab.
static func mine() -> Node3D:
	var n := Node3D.new()
	_d(n, 4.0, 0.6, "steel", Vector3(0, 0.3, 0), 10)
	for x in [-1, 1]:
		for z in [-1, 1]:
			_b(n, Vector3(0.7, 9.0, 0.7), "navy", Vector3(x * 2.6, 4.8, z * 2.6), 0.15, Vector3(-z * 8, 0, x * 8))
	_b(n, Vector3(5.0, 1.2, 5.0), "teal", Vector3(0, 9.4, 0), 0.4)
	_d(n, 0.9, 7.0, "steel", Vector3(0, 4.6, 0), 8)
	_d(n, 1.5, 1.4, "amber", Vector3(0, 1.0, 0), 8, 0.6) # drill head
	_b(n, Vector3(4.6, 3.6, 4.0), "teal", Vector3(5.6, 1.8, 1.0), 0.6) # hopper
	_b(n, Vector3(4.8, 0.6, 4.2), "navy", Vector3(5.6, 3.7, 1.0), 0.2)
	_b(n, Vector3(3.0, 2.6, 3.0), "teal_light", Vector3(-5.2, 1.3, -1.4), 0.5) # cab
	_b(n, Vector3(2.2, 1.0, 0.3), "amber", Vector3(-5.2, 1.8, -2.95), 0.1)
	for i in 3:
		Models.ball(n, 0.9, "ore", Vector3(4.6 + i * 1.0, 4.2, 0.2 + i * 0.7))
	return n


## A landing pad on legs with a control tower and a parked shuttle.
static func spaceport() -> Node3D:
	var n := Node3D.new()
	for a in 4:
		var ang := (a + 0.5) * TAU / 4.0
		_b(n, Vector3(1.0, 3.0, 1.0), "navy", Vector3(cos(ang), 0, sin(ang)) * 5.0 + Vector3(0, 1.5, 0), 0.2)
	_d(n, 7.6, 0.8, "teal", Vector3(0, 3.4, 0), 8)
	_d(n, 6.4, 0.2, "navy", Vector3(0, 3.9, 0), 8)
	for i in 8:
		var a := (i + 0.5) * TAU / 8.0
		_b(n, Vector3(0.6, 0.2, 0.6), "amber", Vector3(cos(a), 0, sin(a)) * 7.0 + Vector3(0, 3.95, 0), 0.08)
	_b(n, Vector3(2.4, 9.0, 2.4), "teal", Vector3(-6.8, 4.5, 4.0), 0.4) # tower
	_b(n, Vector3(3.6, 2.2, 3.6), "glass", Vector3(-6.8, 9.8, 4.0), 0.5)
	_b(n, Vector3(3.8, 0.5, 3.8), "navy", Vector3(-6.8, 11.1, 4.0), 0.2)
	Models.ball(n, 0.4, "amber", Vector3(-6.8, 11.6, 4.0))
	var ship := Models.starter_ship()
	ship.scale = Vector3.ONE * 0.6
	ship.position = Vector3(0.5, 5.0, 0)
	ship.rotation_degrees.y = 30
	n.add_child(ship)
	return n


## Greenhouse tunnels: glass half-cylinders over green beds, with a water tank.
static func hydroponics() -> Node3D:
	var n := Node3D.new()
	for z in [-3.0, 3.0]:
		_b(n, Vector3(12, 0.8, 4.6), "navy", Vector3(0, 0.4, z), 0.2)
		var bed := Node3D.new()
		n.add_child(bed)
		Models.block(bed, Vector3(11, 0.6, 3.6), "teal", Vector3(0, 1.0, z), 0.1).material_override = _green()
		_d(n, 2.3, 11.4, "glass", Vector3(0, 0.8, z), 10, -1.0, Vector3(0, 0, 90))
		for x in [-5.6, 0.0, 5.6]:
			_d(n, 2.45, 0.4, "navy", Vector3(x, 0.8, z), 10, -1.0, Vector3(0, 0, 90))
	_d(n, 1.6, 5.0, "teal_light", Vector3(7.6, 2.5, 0), 10) # water tank
	_d(n, 1.7, 0.4, "navy", Vector3(7.6, 5.1, 0), 10)
	_b(n, Vector3(0.3, 2.0, 0.3), "amber", Vector3(7.6, 2.6, -1.65), 0.05)
	return n


static func _green() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.8, 0.4)
	m.roughness = 0.8
	return m


## Ice Extractor: a heated drill shaft over frozen ground, feeding a tall glass meltwater tank.
static func ice_extractor() -> Node3D:
	var n := Node3D.new()
	_b(n, Vector3(11, 0.8, 9), "navy", Vector3(0, 0.4, 0), 0.25)
	_d(n, 3.4, 1.0, "ice", Vector3(-2.4, 1.2, 0), 10) # frozen bore hole
	_d(n, 1.0, 9.0, "steel", Vector3(-2.4, 5.0, 0), 8) # drill shaft
	_b(n, Vector3(3.6, 2.2, 3.6), "teal", Vector3(-2.4, 9.4, 0), 0.4) # drill head housing
	_b(n, Vector3(3.8, 0.4, 3.8), "amber", Vector3(-2.4, 10.7, 0), 0.1)
	_d(n, 2.2, 7.0, "glass", Vector3(3.2, 4.3, 0), 12) # meltwater tank
	_d(n, 2.4, 0.5, "navy", Vector3(3.2, 0.9, 0), 12)
	_d(n, 2.4, 0.5, "navy", Vector3(3.2, 7.9, 0), 12)
	_d(n, 1.7, 5.0, "teal_light", Vector3(3.2, 3.6, 0), 12) # the water inside
	_b(n, Vector3(4.0, 0.6, 0.6), "steel", Vector3(0.4, 6.4, 0), 0.1) # pipe from drill to tank
	for z in [-3.4, 3.4]:
		_b(n, Vector3(0.6, 1.2, 0.6), "amber", Vector3(-5.0, 1.2, z), 0.1)
	return n


## Mining Refinery: a smelter block with two chimneys and an ore conveyor.
static func refinery() -> Node3D:
	var n := Node3D.new()
	_b(n, Vector3(10, 5, 7), "teal", Vector3(0, 2.5, 0), 0.8)
	_b(n, Vector3(10.4, 0.7, 7.4), "navy", Vector3(0, 4.6, 0), 0.25)
	for x in [-2.8, 2.2]:
		_d(n, 1.2, 7.0, "navy", Vector3(x, 8.0, 1.2), 10)
		_d(n, 1.35, 0.6, "amber", Vector3(x, 11.6, 1.2), 10)
	_b(n, Vector3(3.0, 2.4, 0.4), "amber", Vector3(-2.5, 2.0, -3.55), 0.2) # furnace glow
	_b(n, Vector3(2.0, 3.2, 0.6), "teal_light", Vector3(2.8, 1.6, -3.6), 0.3) # door
	_b(n, Vector3(1.8, 0.6, 8.0), "steel", Vector3(6.2, 2.6, -1.0), 0.2, Vector3(22, 0, 0)) # conveyor
	_b(n, Vector3(3.4, 3.4, 3.4), "navy", Vector3(6.2, 1.7, 4.4), 0.5) # vault box
	_b(n, Vector3(1.2, 1.2, 0.3), "amber", Vector3(6.2, 1.9, 2.6), 0.1)
	return n


## Research Outpost: a lab dome on a deck with a telescope arm and a solar wing.
static func research_outpost() -> Node3D:
	var n := Node3D.new()
	_b(n, Vector3(11, 1.4, 9), "navy", Vector3(0, 0.7, 0), 0.4)
	_d(n, 4.4, 0.6, "teal", Vector3(-1.5, 1.7, 0), 16)
	Models.ball(n, 4.0, "glass", Vector3(-1.5, 2.0, 0), true)
	_d(n, 1.6, 2.4, "teal_light", Vector3(-1.5, 3.2, 0), 10)
	_b(n, Vector3(3.6, 3.0, 4.0), "teal", Vector3(3.8, 2.9, 1.5), 0.5)
	_d(n, 0.9, 4.6, "steel", Vector3(3.8, 6.0, 1.5), 10, 0.6, Vector3(-40, 0, 0)) # telescope
	_d(n, 1.0, 0.3, "amber", Vector3(3.8, 7.8, -0.2), 10, -1.0, Vector3(-40, 0, 0))
	_b(n, Vector3(0.4, 3.0, 0.4), "navy", Vector3(4.0, 1.5, -3.0), 0.1)
	_b(n, Vector3(5.0, 0.2, 2.4), "navy", Vector3(4.0, 3.2, -3.0), 0.05, Vector3(-25, 0, 0)) # solar wing
	_b(n, Vector3(4.6, 0.25, 2.0), "teal_light", Vector3(4.0, 3.25, -3.0), 0.05, Vector3(-25, 0, 0))
	return n


## Data Spire: a tall faceted tower ringed with lit data bands.
static func data_spire() -> Node3D:
	var n := Node3D.new()
	_d(n, 5.0, 1.2, "navy", Vector3(0, 0.6, 0), 6)
	_d(n, 3.6, 6.0, "teal", Vector3(0, 4.2, 0), 6, 3.0)
	_d(n, 3.1, 0.6, "amber", Vector3(0, 7.4, 0), 6)
	_d(n, 3.0, 6.0, "teal_light", Vector3(0, 10.7, 0), 6, 2.2)
	_d(n, 2.3, 0.6, "amber", Vector3(0, 13.9, 0), 6)
	_d(n, 2.2, 5.0, "teal", Vector3(0, 16.7, 0), 6, 0.6)
	Models.ball(n, 0.8, "amber", Vector3(0, 19.6, 0))
	for a in 3:
		var ang := a * TAU / 3.0
		_b(n, Vector3(1.0, 8.0, 1.0), "navy", Vector3(cos(ang), 0, sin(ang)) * 4.0 + Vector3(0, 4.0, 0), 0.2)
	return n


## Ship Foundry: a dry dock with a warship hull half-built inside a gantry, a crane and welding lights.
static func ship_foundry() -> Node3D:
	var n := Node3D.new()
	_b(n, Vector3(14, 1.0, 9), "navy", Vector3(0, 0.5, -1.0), 0.3) # dock floor
	_b(n, Vector3(12, 0.3, 6.6), "steel", Vector3(0, 1.1, -1.0), 0.1)
	for x in [-5.6, 0.0, 5.6]:
		for z in [-4.6, 2.6]:
			_b(n, Vector3(0.8, 8.0, 0.8), "teal", Vector3(x, 5.0, z), 0.2) # gantry legs
		_b(n, Vector3(0.9, 0.9, 8.0), "teal_light", Vector3(x, 9.2, -1.0), 0.25) # gantry beams
	_b(n, Vector3(12.4, 0.8, 0.8), "navy", Vector3(0, 9.6, -4.6), 0.2)
	_b(n, Vector3(12.4, 0.8, 0.8), "navy", Vector3(0, 9.6, 2.6), 0.2)
	# The hull on the slipway: finished bow, bare ribs at the stern.
	_b(n, Vector3(3.4, 2.6, 4.6), "teal", Vector3(-2.6, 2.8, -1.0), 0.6, Vector3(0, 90, 0))
	_b(n, Vector3(2.6, 2.0, 2.6), "teal_light", Vector3(-5.2, 2.6, -1.0), 0.7)
	_b(n, Vector3(1.6, 0.9, 1.4), "glass", Vector3(-3.8, 4.3, -1.0), 0.3)
	for x in [0.4, 1.8, 3.2]:
		_b(n, Vector3(0.35, 3.0, 3.6), "navy", Vector3(x, 2.9, -1.0), 0.15) # ribs
	_b(n, Vector3(5.0, 0.4, 0.5), "navy", Vector3(1.8, 4.2, -1.0), 0.1) # keel spine
	for p in [Vector3(1.1, 4.0, 0.9), Vector3(2.5, 1.9, -2.9), Vector3(-0.6, 3.6, -2.9)]:
		Models.ball(n, 0.3, "amber", p) # welding sparks
	# Crane trolley hanging from the middle beam, lifting a hull plate.
	_b(n, Vector3(1.6, 1.0, 1.6), "navy", Vector3(2.6, 8.4, -1.0), 0.2)
	_d(n, 0.12, 2.6, "steel", Vector3(2.6, 6.6, -1.0), 6)
	_b(n, Vector3(2.4, 0.3, 2.0), "teal", Vector3(2.6, 5.2, -1.0), 0.08)
	# Control booth with a lit window.
	_b(n, Vector3(3.0, 3.0, 2.4), "teal_light", Vector3(6.4, 1.5, 4.8), 0.4)
	_b(n, Vector3(2.2, 1.0, 0.3), "amber", Vector3(6.4, 2.0, 3.55), 0.1)
	return n


## A security turret, shown around a facility once its tier adds turrets.
static func turret() -> Node3D:
	var n := Node3D.new()
	_d(n, 1.4, 1.2, "navy", Vector3(0, 0.6, 0), 8)
	_b(n, Vector3(2.0, 1.4, 2.2), "teal", Vector3(0, 1.9, 0), 0.4)
	for s in [-1, 1]:
		_d(n, 0.22, 2.4, "steel", Vector3(s * 0.45, 1.9, -1.8), 8, -1.0, Vector3(90, 0, 0))
	_b(n, Vector3(0.8, 0.3, 0.1), "amber", Vector3(0, 2.2, -1.12), 0.05)
	return n


## A low boulder for scenery.
static func boulder(radius: float, seed: int) -> Node3D:
	var n := Node3D.new()
	Models.part(n, Models._rock_mesh(radius, seed), "rock").scale = Vector3(1, 0.55, 1)
	return n
