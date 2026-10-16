extends Node3D
## On foot at a Builder's facility, in three stages:
##  1. Breach: the site as the Builder laid it out. Destroy turrets, guard posts and the power
##     plant (which opens the core's blast door), or cut in quietly through a vent.
##  2. Loot: take the lifts down through one level per facility level; deeper is richer and better
##     guarded, and every minute inside brings in more guards.
##  3. Extraction: the safe room on the deepest level holds the vault, sometimes with a boss.
##     Opening it starts the self-destruct: get back up and aboard your ship before it ends.
##
## The server sends the layout and owns the loot, Heat, the clocks and every extraction; this
## scene simulates walking, the guards and the shooting, and reports what happened (see heist.js).
## Everything is built from simple shapes in code, like the rest of the prototype.

signal finished(result: Dictionary)

const InventoryView := preload("res://raid_inventory.gd")

# Movement, from the spec's starting values.
const WALK := 4.5
const SPRINT := 6.5
const CROUCH := 2.5
const JUMP := 4.2
const GRAVITY := 14.0
const EYE := 1.6
const EYE_CROUCHED := 1.0
const REACH := 2.4 # metres to use a container, door or guard
const LOOK_SPEED := 2.6 # rad/s with a gamepad or arrow keys at full deflection

# The rifle.
const MAG := 30
const RESERVE := 150
const FIRE_GAP := 0.1
const RELOAD_SECONDS := 2.0
const DAMAGE := 34.0
const RANGE := 120.0
const FOV := 90.0
const FOV_AIM := 60.0

# Noise radii (metres) that guards hear.
const NOISE_GUNSHOT := 120.0
const NOISE_SPRINT := 22.0
const NOISE_WALK := 8.0
const NOISE_DRILL := 60.0
const NOISE_EXTRACT := 150.0
const NOISE_BLAST := 90.0

# Guards.
const GUARD_HEALTH := 100.0
const GUARD_SPEED := 2.2
const GUARD_RUN := 4.6
const GUARD_DAMAGE := 12.0
const GUARD_SIGHT := 22.0
const GUARD_FOV := 0.6 # cosine of the half-angle they see (about 106 degrees wide)
const GUARD_REACTION := 0.45
const GUARD_TELL := 0.5 # the aiming laser shows this long before the first shot
const ATTACK_TOKENS := 2 # at most this many guards shoot at you at once
const POST_RESPAWN := 40.0 # a standing guard post sends out a new guard this often
const LIFT_REACH := 1.8
const VENT_REACH := 2.2

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_GUARDS := 4

const RARITY_COLOURS := {
	"common": Color(0.62, 0.64, 0.66), "uncommon": Color(0.4, 0.8, 0.4), "rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.45, 1.0), "legendary": Color(1.0, 0.78, 0.25),
}

var controls: Node # controls.gd, shared with flight
var god_mode := false # tests: guards can't hurt you

var brief: Dictionary
var layout: Dictionary
var room := 14.0
var rooms := {} # id -> room
var floors := 1
var floor_depth := 10.0
var breached := false
var door_open := false
var destroyed: Array = [] # site piece ids knocked out
var self_destruct := -1.0 # seconds left, once the vault is open
var heat := 0
var level := 0
var remaining := 0.0
var extract_states := {}
var vault_open := false
var inventory: Array = []
var health := 100.0
var ammo := MAG
var reserve := RESERVE
var over := false

var _player: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0
var _crouched := false
var _fire_cd := 0.0
var _reload_left := 0.0
var _recoil := 0.0
var _step_noise := 0.0
var _hit_flash := 0.0
var _hurt_flash := 0.0
var _hurt_from := Vector3.ZERO
var _gunshot_sent_at := -10000

var _guards: Array = [] # {"id", "body", "health", "state", "route", "leg", "target", "aware", "tell", "cd", "seen_at", "dead", "noticed", "laser", "elite"}
var _turrets: Array = []
var _tokens := 0
var _last_known := Vector3.INF # where any guard last saw you
var _elite_sent := false
var _floor := 0 # the level you're on: 0 is the surface (and the core's lobby)
var _floor_nodes := {} # level -> Node3D holding what's built there
var _into: Node3D # where _box and _label put what they build
var _pieces := {} # site piece id -> {"data", "node", "health", "dead"}
var _blast_door: Node3D
var _lifts: Array = [] # {"pos", "to", "to_floor", "name"}
var _vents := {} # id -> {"out", "in", "node", "cut"}
var _venting := ""
var _vent_left := -1.0
var _enter_sent := false
var _boom_light: OmniLight3D
var _containers := {} # id -> {"node", "data"}
var _vault_doors: Array[Node3D] = []
var _vault_room_centre := Vector3.ZERO
var _extract_nodes := {} # id -> {"node", "label", "data"}
var _drill: Node3D
var _drill_left := -1.0
var _extracting := "" # extract id while standing in one
var _extract_left := 0.0
var _open_container := ""

var _hud: Control
var _prompt: Label
var _status: Label
var _message: Label
var _message_time := 0.0
var _centre: Label
var _inv: Control
var _results: Control
var _paused: Control


func _init(briefing: Dictionary) -> void:
	brief = briefing
	layout = briefing.layout
	room = float(layout.room)
	heat = int(briefing.heat)
	level = int(briefing.level)
	remaining = float(briefing.remaining) / 1000.0
	extract_states = briefing.extracts
	vault_open = briefing.vaultOpen
	inventory = briefing.inventory
	floors = int(briefing.get("floors", 1))
	floor_depth = float(layout.get("floorDepth", 10))
	breached = briefing.get("breached") != null
	door_open = bool(briefing.get("doorOpen", false))
	destroyed = briefing.get("destroyed", [])
	if briefing.get("selfDestruct") != null:
		self_destruct = float(briefing.selfDestruct) / 1000.0


func _ready() -> void:
	for r in layout.rooms:
		rooms[int(r.id)] = r
	for n in range(floors + 1):
		var node := Node3D.new()
		node.name = "Level%d" % n
		add_child(node)
		_floor_nodes[n] = node
	_build_environment()
	_build_site()
	_build_rooms()
	_build_props()
	_into = null
	_build_player()
	_build_guards()
	_build_hud()
	_set_floor(0)
	Net.raid_event.connect(_on_raid_event)
	Net.server_error.connect(_on_server_error)
	controls.capture_mouse()
	if layout.powered == "core":
		_say("%s runs on its own power: the blast door won't open. Find a vent into the core." % brief.facility, 7.0)
	else:
		_say("%s. Knock out the power plant to open the blast door, or cut in through a vent." % brief.facility, 7.0)


func _exit_tree() -> void:
	if Net.raid_event.is_connected(_on_raid_event):
		Net.raid_event.disconnect(_on_raid_event)
		Net.server_error.disconnect(_on_server_error)


# --- Building the facility -----------------------------------------------------------

func _room_centre(id: int) -> Vector3:
	var r: Dictionary = rooms[id]
	return Vector3(r.pos[0], -floor_depth * int(r.floor), r.pos[1])


func _level(n: int) -> Dictionary:
	return layout.floors[n - 1]


## Which level a point is on (0: the surface).
func _floor_of(p: Vector3) -> int:
	return clampi(roundi(-p.y / floor_depth), 0, floors)


func _parent() -> Node:
	return _into if _into else self


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.48)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.1)
	env.fog_density = 0.012
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _box(size: Vector3, pos: Vector3, colour: Color, solid := true, glow := false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	if glow:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not solid:
		mi.position = pos
		_parent().add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.add_child(mi)
	_parent().add_child(body)
	return body


func _label(text: String, pos: Vector3, size := 48, colour := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = colour
	l.outline_size = 8
	_parent().add_child(l)
	return l


func _door_between(a: int, b: int) -> Dictionary:
	for d in layout.doors:
		if (int(d.a) == a and int(d.b) == b) or (int(d.a) == b and int(d.b) == a):
			return d
	return {}


func _build_rooms() -> void:
	var h := 4.0
	var t := 0.3
	var half := room / 2.0
	var door := 2.4
	var wall := Color(0.32, 0.35, 0.4)
	for id in rooms:
		var r: Dictionary = rooms[id]
		var lv := _level(int(r.floor))
		_into = _floor_nodes[int(r.floor)]
		var c := _room_centre(id)
		var ring: String = r.ring
		# Deeper levels run warmer and darker: you're further from the way out.
		var depth_tint := float(int(r.floor) - 1) / maxf(1.0, float(floors))
		var floor_col: Color = {"perimeter": Color(0.22, 0.24, 0.27), "interior": Color(0.18, 0.21, 0.27), "core": Color(0.25, 0.14, 0.14)}[ring]
		_box(Vector3(room, 0.2, room), c + Vector3(0, -0.1, 0), floor_col.lerp(Color(0.2, 0.14, 0.12), depth_tint * 0.5))
		_box(Vector3(room, 0.2, room), c + Vector3(0, h + 0.1, 0), Color(0.1, 0.11, 0.13), false)
		var light := OmniLight3D.new()
		light.position = c + Vector3(0, h - 0.4, 0)
		light.omni_range = room * 0.95
		light.light_energy = 1.6
		light.light_color = {"perimeter": Color(0.95, 0.95, 1.0), "interior": Color(0.7, 0.85, 1.0), "core": Color(1.0, 0.55, 0.45)}[ring].lerp(Color(1.0, 0.7, 0.5), depth_tint * 0.6)
		_into.add_child(light)
		_box(Vector3(2.5, 0.06, 0.4), c + Vector3(0, h - 0.05, 0), light.light_color, false, true)

		# Each room builds its east and south walls; the edge of the level gets the west and north.
		var x: int = int(r.x)
		var y: int = int(r.y)
		var cols := int(lv.cols)
		var sides := [[Vector3(half, 0, 0), true, x + 1 < cols, id + 1], [Vector3(0, 0, half), false, y + 1 < int(lv.rows), id + cols]]
		if x == 0:
			sides.append([Vector3(-half, 0, 0), true, false, -1])
		if y == 0:
			sides.append([Vector3(0, 0, -half), false, false, -1])
		for side in sides:
			var offset: Vector3 = side[0]
			var along_z: bool = side[1]
			var inside: bool = side[2]
			var d := _door_between(id, side[3]) if inside else {}
			var base := c + offset + Vector3(0, h / 2.0, 0)
			if d.is_empty():
				_box(Vector3(t, h, room) if along_z else Vector3(room, h, t), base, wall)
				continue
			var seg := (room - door) / 2.0
			for sgn in [-1, 1]:
				var shift: float = (door / 2.0 + seg / 2.0) * sgn
				_box(Vector3(t, h, seg) if along_z else Vector3(seg, h, t), base + (Vector3(0, 0, shift) if along_z else Vector3(shift, 0, 0)), wall)
			_box(Vector3(t, h - 2.6, door) if along_z else Vector3(door, h - 2.6, t), base + Vector3(0, 1.3, 0), wall)
			if d.locked:
				var slab := _box(Vector3(t * 0.6, 2.6, door) if along_z else Vector3(door, 2.6, t * 0.6), c + offset + Vector3(0, 1.3, 0), Color(0.75, 0.2, 0.15), true, true)
				_vault_doors.append(slab)
				slab.visible = not vault_open
				slab.get_child(0).disabled = vault_open

	# Lifts: each level's lift up sits under the lift down of the level above (level 1's under the
	# core's lobby), so riding one keeps you where you were on the map.
	for lv in layout.floors:
		var n := int(lv.n)
		_into = _floor_nodes[n]
		var up_to: Vector3 = Vector3.ZERO if n == 1 else _room_centre(int(_level(n - 1).down))
		_lift(_room_centre(int(lv.entrance)), up_to, n - 1, "Lift up to %s" % ("the surface" if n == 1 else "level %d" % (n - 1)))
		if int(lv.down) >= 0:
			_lift(_room_centre(int(lv.down)), _room_centre(int(_level(n + 1).entrance)), n + 1, "Lift down to level %d" % (n + 1))
	_into = _floor_nodes[0]
	_lift(Vector3.ZERO, _room_centre(int(_level(1).entrance)), 1, "Lift down to level 1")
	_vault_room_centre = _room_centre(int(layout.vault))


func _lift(pos: Vector3, to: Vector3, to_floor: int, text: String) -> void:
	var colour := Color(0.4, 0.75, 1.0)
	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.3
	mesh.bottom_radius = 1.3
	mesh.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(colour, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = colour
	mesh.material = mat
	pad.mesh = mesh
	pad.position = pos + Vector3(0, 0.03, 0)
	_into.add_child(pad)
	_label(text, pos + Vector3(0, 2.4, 0), 32, colour)
	_lifts.append({"pos": pos, "to": to, "to_floor": to_floor, "name": text})


# The surface: the site's grid as the Builder laid it out, the core with its lobby, blast door
# and vents, and the landing pad where your ship waits.
func _build_site() -> void:
	_into = _floor_nodes[0]
	var half := float(layout.half)
	var core := float(layout.core)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(0.8, 0.88, 1.0)
	_into.add_child(sun)
	# Ice all round, the site's deck on it, and its grid.
	_box(Vector3(260, 0.2, 260), Vector3(0, -0.25, 0), Color(0.55, 0.62, 0.7))
	_box(Vector3(half * 2.0, 0.2, half * 2.0), Vector3(0, -0.1, 0), Color(0.24, 0.27, 0.31))
	var tile := float(layout.tile)
	for i in range(int(layout.grid) + 1):
		var at := -half + i * tile
		_box(Vector3(0.06, 0.02, half * 2.0), Vector3(at, 0.01, 0), Color(0.18, 0.4, 0.4), false)
		_box(Vector3(half * 2.0, 0.02, 0.06), Vector3(0, 0.01, at), Color(0.18, 0.4, 0.4), false)

	# The core: a lobby with the lift down, a blast door in the south wall and vents in the others.
	var h := 6.0
	var t := 0.5
	var c := core / 2.0
	var shell := Color(0.4, 0.42, 0.48)
	var door_w := 3.0
	var seg := (core - door_w) / 2.0
	for sgn in [-1, 1]:
		_box(Vector3(seg, h, t), Vector3(sgn * (door_w / 2.0 + seg / 2.0), h / 2.0, c), shell)
	_box(Vector3(door_w, h - 3.2, t), Vector3(0, 3.2 + (h - 3.2) / 2.0, c), shell)
	_box(Vector3(core, h, t), Vector3(0, h / 2.0, -c), shell)
	_box(Vector3(t, h, core), Vector3(-c, h / 2.0, 0), shell)
	_box(Vector3(t, h, core), Vector3(c, h / 2.0, 0), shell)
	_box(Vector3(core + t, 0.4, core + t), Vector3(0, h + 0.2, 0), shell.darkened(0.3))
	_box(Vector3(core, 0.1, core), Vector3(0, 0.05, 0), Color(0.2, 0.22, 0.26))
	var lobby_light := OmniLight3D.new()
	lobby_light.position = Vector3(0, h - 1.0, 0)
	lobby_light.omni_range = core
	lobby_light.light_energy = 1.4
	_into.add_child(lobby_light)
	_label(brief.facility, Vector3(0, h + 1.6, c), 64, Color(0.35, 0.95, 0.88))
	_blast_door = _box(Vector3(door_w, 3.2, t * 0.6), Vector3(0, 1.6, c), Color(0.85, 0.55, 0.15), true, true)
	_set_blast_door(door_open)
	for v in layout.vents:
		var p := Vector3(v.pos[0], 0, v.pos[1])
		var outward := p.normalized()
		var grate_size := Vector3(0.2, 0.9, 1.4) if absf(outward.x) > 0.5 else Vector3(1.4, 0.9, 0.2)
		var grate := _box(grate_size, p + Vector3(0, 0.6, 0) + outward * 0.3, Color(0.3, 0.35, 0.38), false, false)
		_label("Vent", p + Vector3(0, 1.5, 0) + outward * 0.6, 24, Color(1, 1, 1, 0.6))
		_vents[v.id] = {"out": p + outward * 1.4, "in": p - outward * 1.4, "node": grate, "cut": breached}

	for piece in layout.pieces:
		_build_piece(piece)

	# The landing pad, your ship on it, and the boarding ring.
	var pad := Vector3(layout.pad[0], 0, layout.pad[1])
	_box(Vector3(18, 0.3, 18), pad + Vector3(0, -0.05, 0), Color(0.2, 0.22, 0.25))
	for sgn in [-1, 1]:
		_box(Vector3(18, 0.05, 0.3), pad + Vector3(0, 0.12, sgn * 9), Color(0.9, 0.6, 0.2), false, true)
	var ship := Vector3(pad.x + 4.5, 0, pad.z + 2)
	_box(Vector3(4.0, 2.2, 9.0), ship + Vector3(0, 1.8, 0), Color(0.6, 0.64, 0.7))
	_box(Vector3(9.5, 0.3, 3.5), ship + Vector3(0, 1.4, 1.5), Color(0.5, 0.54, 0.6))
	_box(Vector3(2.2, 0.9, 2.0), ship + Vector3(0, 2.9, -2.8), Color(0.35, 0.95, 0.88), false, true)
	for sgn in [-1, 1]:
		_box(Vector3(0.9, 0.9, 0.5), ship + Vector3(sgn * 1.2, 1.8, 4.6), Color(1.0, 0.55, 0.25), false, true)
	_boom_light = OmniLight3D.new()
	_boom_light.light_color = Color(1.0, 0.15, 0.05)
	_boom_light.light_energy = 0.0
	_boom_light.omni_range = 40.0
	add_child(_boom_light)


func _build_piece(piece: Dictionary) -> void:
	var size := Vector3(piece.size[0], 0, piece.size[1])
	var pos := Vector3(piece.pos[0], 0, piece.pos[1])
	var dead: bool = piece.id in destroyed
	var node: Node3D
	var extras: Array = [] # the parts that go when it's destroyed
	match piece.type:
		"turret":
			node = _box(Vector3(size.x * 0.4, 1.6, size.z * 0.4), pos + Vector3(0, 0.8, 0), Color(0.3, 0.3, 0.32))
			var head := _box(Vector3(0.9, 0.6, 1.6), pos + Vector3(0, 1.9, 0), Color(0.6, 0.15, 0.12), false, true)
			extras.append(head)
			_turrets.append({"base": node, "head": head, "pos": pos + Vector3(0, 1.9, 0), "health": float(piece.hp), "tell": 0.0, "cd": 0.0,
				"dead": dead, "laser": _laser(), "floor": 0, "piece": piece.id, "range": 34.0})
			head.visible = not dead
		"guardpost":
			node = _box(Vector3(size.x * 0.75, 3.0, size.z * 0.75), pos + Vector3(0, 1.5, 0), Color(0.42, 0.4, 0.3))
			extras.append(_box(Vector3(size.x * 0.85, 0.3, size.z * 0.85), pos + Vector3(0, 3.15, 0), Color(0.3, 0.28, 0.22), false))
			extras.append(_box(Vector3(0.8, 0.3, 0.3), pos + Vector3(0, 2.4, size.z * 0.38), Color(1.0, 0.75, 0.3), false, true))
		"power":
			node = _box(Vector3(size.x * 0.8, 3.4, size.z * 0.8), pos + Vector3(0, 1.7, 0), Color(0.3, 0.33, 0.38))
			for sgn in [-1, 1]:
				extras.append(_box(Vector3(0.5, 2.6, 0.5), pos + Vector3(sgn * size.x * 0.25, 4.6, 0), Color(0.35, 0.8, 1.0), false, true))
			extras.append(_label("Power plant", pos + Vector3(0, 6.6, 0), 40, Color(0.5, 0.85, 1.0)))
		"wall":
			node = _box(Vector3(size.x, 2.6, size.z), pos + Vector3(0, 1.3, 0), Color(0.45, 0.47, 0.5))
		"boulder":
			node = _box(Vector3(size.x * 0.8, 2.2, size.z * 0.7), pos + Vector3(0, 1.1, 0), Color(0.42, 0.4, 0.42))
		"crystals":
			node = _box(Vector3(size.x * 0.5, 1.8, size.z * 0.5), pos + Vector3(0, 0.9, 0), Color(0.55, 0.85, 1.0), true, true)
		"wreck":
			node = _box(Vector3(size.x * 0.9, 1.0, size.z * 0.6), pos + Vector3(0, 0.5, 0), Color(0.25, 0.24, 0.23))
		_:
			node = _box(Vector3(size.x * 0.8, 2.0, size.z * 0.8), pos + Vector3(0, 1.0, 0), Color(0.4, 0.4, 0.44))
	_pieces[piece.id] = {"data": piece, "node": node, "health": float(piece.hp), "dead": dead, "respawn": POST_RESPAWN, "extras": extras}
	if dead:
		_wreck(_pieces[piece.id])


func _set_blast_door(open: bool) -> void:
	door_open = open
	_blast_door.visible = not open
	_blast_door.get_child(0).disabled = open


# What's left of a destroyed piece: a scorched stump, no longer in the way.
func _wreck(p: Dictionary) -> void:
	for e in p.extras:
		e.visible = false
	var node: Node3D = p.node
	node.scale = Vector3(1.0, 0.25, 1.0)
	node.position.y *= 0.25
	var mi: MeshInstance3D = node.get_child(1)
	var mat: StandardMaterial3D = mi.mesh.material.duplicate()
	mat.albedo_color = Color(0.12, 0.1, 0.09)
	mat.emission_enabled = false
	mi.material_override = mat


func _build_props() -> void:
	var sizes := {"locker": Vector3(1.0, 2.0, 0.6), "crate": Vector3(1.4, 0.9, 1.0), "desk": Vector3(1.6, 0.8, 0.8), "rack": Vector3(0.8, 2.1, 1.0), "vault": Vector3(1.2, 1.2, 1.2)}
	var colours := {"locker": Color(0.4, 0.45, 0.5), "crate": Color(0.5, 0.42, 0.28), "desk": Color(0.35, 0.33, 0.3), "rack": Color(0.15, 0.17, 0.2), "vault": Color(0.75, 0.62, 0.2)}
	var names := {"locker": "Locker", "crate": "Crate", "desk": "Desk", "rack": "Server rack", "vault": "Vault box"}
	for c in layout.containers:
		_into = _floor_nodes[int(c.floor)]
		var size: Vector3 = sizes[c.type]
		var pos := _room_centre(int(c.room)) + Vector3(c.pos[0], size.y / 2.0, c.pos[1])
		var node := _box(size, pos, colours[c.type], true, c.type == "vault")
		var tag := _label(names[c.type], pos + Vector3(0, size.y / 2.0 + 0.3, 0), 28, Color(1, 1, 1, 0.7))
		_containers[c.id] = {"node": node, "data": c, "name": names[c.type], "tag": tag}

	_into = _floor_nodes[0]
	var ex_colours := {"ship": Color(0.3, 1.0, 0.6)}
	var ex_names := {"ship": "Your ship"}
	for ex in layout.extracts:
		var pos := Vector3(ex.pos[0], 0, ex.pos[1])
		var ring := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 2.2
		mesh.bottom_radius = 2.2
		mesh.height = 0.05
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(ex_colours[ex.kind], 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = ex_colours[ex.kind]
		mesh.material = mat
		ring.mesh = mesh
		ring.position = pos + Vector3(0, 0.03, 0)
		add_child(ring)
		var label := _label(ex_names[ex.kind], pos + Vector3(0, 2.6, 0), 40, ex_colours[ex.kind])
		_extract_nodes[ex.id] = {"node": ring, "label": label, "data": ex, "pos": pos, "name": ex_names[ex.kind]}
	_refresh_extract_labels()

	for t in layout.turrets:
		_into = _floor_nodes[int(t.floor)]
		var pos := _room_centre(int(t.room)) + Vector3(t.pos[0], 0, t.pos[1])
		var base := _box(Vector3(0.6, 1.2, 0.6), pos + Vector3(0, 0.6, 0), Color(0.3, 0.3, 0.32))
		var head := _box(Vector3(0.5, 0.35, 0.9), pos + Vector3(0, 1.4, 0), Color(0.6, 0.15, 0.12), false, true)
		_turrets.append({"base": base, "head": head, "pos": pos + Vector3(0, 1.4, 0), "health": 300.0, "tell": 0.0, "cd": 0.0, "dead": false,
			"laser": _laser(), "floor": int(t.floor), "piece": "", "range": 20.0, "room": int(t.room)})


func _pad() -> Vector3:
	return Vector3(layout.pad[0], 0, layout.pad[1])


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.collision_layer = LAYER_PLAYER
	_player.collision_mask = LAYER_WORLD | LAYER_GUARDS
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.shape.height = 1.8
	shape.position.y = 0.9
	_player.add_child(shape)
	_player.position = _pad() + Vector3(-2, 0.05, -2)
	add_child(_player)
	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 400.0
	_player.add_child(_camera)
	_camera.make_current()

	# The rifle, held low and to the right.
	var gun := Node3D.new()
	gun.position = Vector3(0.22, -0.2, -0.45)
	gun.name = "Gun"
	_camera.add_child(gun)
	var parts := [[Vector3(0.07, 0.09, 0.55), Vector3(0, 0, 0), Color(0.12, 0.13, 0.15)],
		[Vector3(0.04, 0.04, 0.3), Vector3(0, 0.015, -0.4), Color(0.08, 0.08, 0.09)],
		[Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, 0.08), Color(0.12, 0.13, 0.15)],
		[Vector3(0.03, 0.02, 0.12), Vector3(0, 0.065, -0.05), Color(0.35, 0.95, 0.88)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = p[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[2]
		if p[2].g > 0.9:
			mat.emission_enabled = true
			mat.emission = p[2]
		mesh.material = mat
		mi.mesh = mesh
		mi.position = p[1]
		gun.add_child(mi)


func _guard_body(elite := false) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = LAYER_GUARDS
	body.collision_mask = LAYER_WORLD | LAYER_PLAYER
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.38
	shape.shape.height = 1.85
	shape.position.y = 0.925
	body.add_child(shape)
	var colour := Color(0.75, 0.2, 0.2) if elite else Color(0.62, 0.55, 0.3)
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	cap.material = mat
	torso.mesh = cap
	torso.position.y = 0.75
	body.add_child(torso)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = colour.darkened(0.3)
	sphere.material = hmat
	head.mesh = sphere
	head.position.y = 1.65
	body.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.3, 0.07, 0.1)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(1.0, 0.3, 0.2)
	vmat.emission_enabled = true
	vmat.emission = Color(1.0, 0.3, 0.2)
	vm.material = vmat
	visor.mesh = vm
	visor.position = Vector3(0, 1.67, -0.18)
	visor.name = "Visor"
	body.add_child(visor)
	add_child(body)
	return body


func _laser() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	mi.mesh = mesh
	mi.visible = false
	add_child(mi)
	return mi


func _build_guards() -> void:
	for g in layout.guards:
		var route: Array = []
		for r in g.route:
			route.append(int(r))
		_spawn_guard(g.id, route, _room_centre(route[0]), false)
	# Outside, each guard post that's still standing has two guards walking round it.
	for id in _pieces:
		var p: Dictionary = _pieces[id]
		if p.data.type == "guardpost" and not p.dead:
			for i in 2:
				_post_guard(p)
	if layout.get("boss") != null:
		var boss := _spawn_guard("boss", [int(layout.boss.room)], _vault_room_centre, true)
		boss.health = float(layout.boss.health)
		boss.boss = true
		boss.state = "sleep"
		boss.body.scale = Vector3(1.35, 1.35, 1.35)
		var tag := Label3D.new()
		tag.text = "VAULT WARDEN"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.modulate = Color(1.0, 0.35, 0.25)
		tag.position.y = 2.4
		boss.body.add_child(tag)


func _post_guard(p: Dictionary) -> Dictionary:
	var at := Vector3(p.data.pos[0], 0, p.data.pos[1])
	var g := _spawn_guard("%s-%d" % [p.data.id, _guards.size()], [], at + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), false)
	g.post = p.data.id
	return g


func _spawn_guard(id: String, route: Array, at: Vector3, elite: bool) -> Dictionary:
	var body := _guard_body(elite)
	body.position = at + Vector3(randf_range(-2, 2), 0.05, randf_range(-2, 2))
	var g := {"id": id, "body": body, "health": GUARD_HEALTH * (2.0 if elite else 1.0), "state": "patrol", "route": route,
		"leg": 0, "path": [], "target": Vector3.ZERO, "aware": 0.0, "tell": 0.0, "cd": 0.0, "dead": false,
		"noticed": {}, "laser": _laser(), "elite": elite, "search": 0.0, "has_token": false, "burst": 0,
		"floor": _floor_of(at), "post": "", "boss": false}
	_guards.append(g)
	body.visible = g.floor == _floor
	_patrol_next(g)
	return g


# Where a patrolling guard walks next: round its rooms inside, round its post (or the core) outside.
func _patrol_next(g: Dictionary) -> void:
	if g.floor == 0:
		var centre := Vector3.ZERO
		if g.post != "" and _pieces.has(g.post):
			centre = Vector3(_pieces[g.post].data.pos[0], 0, _pieces[g.post].data.pos[1])
		var a := randf() * TAU
		_path_to(g, centre + Vector3(cos(a), 0, sin(a)) * randf_range(5.0, 9.0) + (Vector3.ZERO if g.post != "" else Vector3(0, 0, float(layout.core))))
		return
	if g.route.is_empty():
		return
	g.leg = (g.leg + 1) % g.route.size()
	_path_to(g, _room_centre(g.route[g.leg]) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))


# --- HUD -------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_status = Label.new()
	_status.position = Vector2(16, 16)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_status)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 170
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_prompt)
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position.y += 70
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.add_theme_font_size_override("font_size", 18)
	_message.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_message)
	_centre = Label.new()
	_centre.set_anchors_preset(Control.PRESET_CENTER)
	_centre.position.y -= 90
	_centre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_centre.add_theme_font_size_override("font_size", 30)
	_centre.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_centre)

	_inv = InventoryView.new()
	_inv.visible = false
	layer.add_child(_inv)
	_inv.take.connect(func(uid, to): Net.send({"type": "raid_take", "uid": uid, "to": to}))
	_inv.drop.connect(func(uid): Net.send({"type": "raid_drop", "uid": uid}))
	_inv.stow.connect(func(uid, to): Net.send({"type": "raid_stow", "uid": uid, "to": to}))
	_inv.closed.connect(_close_inventory)
	_inv.set_inventory(inventory, brief.backpack, brief.secure)

	_paused = _overlay_panel()
	layer.add_child(_paused)


func _overlay_panel() -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0.02, 0.05, 0.85)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := Label.new()
	title.text = "Paused (the raid clock keeps running)"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var resume := Button.new()
	resume.text = "Back to the raid (Esc)"
	resume.pressed.connect(func(): _set_paused(false))
	col.add_child(resume)
	var bail := Button.new()
	bail.name = "Bail"
	bail.text = "Bail out (only in the first 2 minutes; you keep nothing you found)"
	bail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bail.pressed.connect(func(): Net.send({"type": "raid_bail"}); _set_paused(false))
	col.add_child(bail)
	return root


func _say(text: String, seconds := 4.0) -> void:
	_message.text = text
	_message_time = seconds


func _set_paused(on: bool) -> void:
	_paused.visible = on
	if on:
		controls.release_mouse()
	elif not _inv.visible:
		controls.capture_mouse()


# --- Input -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if over:
		return
	if _paused.visible:
		if event.is_action_pressed("menu"):
			_set_paused(false)
		return
	if event.is_action_pressed("menu"):
		if _inv.visible:
			_close_inventory()
		else:
			_set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("foot_inventory"):
		if _inv.visible:
			_close_inventory()
		else:
			_open_inventory()
		get_viewport().set_input_as_handled()
		return
	if _inv.visible:
		if event.is_action_pressed("interact"):
			_close_inventory()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = controls.mouse_sensitivity * 0.0022 * (FOV_AIM / FOV if _aiming() else 1.0)
		var dy: float = -event.relative.y if controls.invert_mouse else event.relative.y
		_look(-event.relative.x * s, -dy * s)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		controls.capture_mouse()
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("foot_reload"):
		_reload()
	elif event.is_action_pressed("foot_heal"):
		_heal()
	elif event.is_action_pressed("foot_crouch"):
		_crouched = not _crouched


func _look(yaw: float, pitch: float) -> void:
	_player.rotate_y(yaw)
	_pitch = clampf(_pitch + pitch, -1.45, 1.45)
	_camera.rotation.x = _pitch + _recoil


func _aiming() -> bool:
	return Input.is_action_pressed("foot_aim") and not _inv.visible and not _paused.visible


func _active() -> bool:
	return not over and not _inv.visible and not _paused.visible


# --- Simulation ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	if self_destruct >= 0.0:
		self_destruct = maxf(0.0, self_destruct - delta)
	_message_time -= delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if over:
		return
	_move_player(delta)
	_shoot(delta)
	_update_guards(delta)
	_update_turrets(delta)
	_update_drill(delta)
	_update_vent(delta)
	_check_door()
	_update_extract(delta)
	_reinforce(delta)
	_update_self_destruct(delta)
	_update_prompt()
	_update_hud()


func _move_player(delta: float) -> void:
	var input := Vector2.ZERO
	var look := Vector2.ZERO
	if _active():
		input = Input.get_vector("foot_left", "foot_right", "foot_forward", "foot_back")
		look = Input.get_vector("foot_look_left", "foot_look_right", "foot_look_up", "foot_look_down")
	if look.length() > 0.1:
		_look(-look.x * LOOK_SPEED * delta, -look.y * LOOK_SPEED * delta)
	var sprinting: bool = _active() and Input.is_action_pressed("foot_sprint") and input.y < -0.1 and not _crouched
	var speed := CROUCH if _crouched else (SPRINT if sprinting else WALK)
	if _aiming():
		speed = minf(speed, WALK * 0.6)
	var dir := (_player.global_basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
	_player.velocity.x = dir.x * speed
	_player.velocity.z = dir.z * speed
	if _player.is_on_floor():
		if _active() and Input.is_action_just_pressed("foot_jump"):
			_player.velocity.y = JUMP
	else:
		_player.velocity.y -= GRAVITY * delta
	_player.move_and_slide()
	_camera.position.y = lerpf(_camera.position.y, EYE_CROUCHED if _crouched else EYE, minf(1.0, delta * 10.0))
	if _player.position.y < -floor_depth * (floors + 1):
		teleport_to(_pad())

	# Footsteps: guards hear sprinting further than walking, and crouching not at all.
	if input.length() > 0.1 and _player.is_on_floor() and not _crouched:
		_step_noise -= delta
		if _step_noise <= 0.0:
			_step_noise = 0.4
			_noise(_player.position, NOISE_SPRINT if sprinting else NOISE_WALK, false)

	_camera.fov = lerpf(_camera.fov, FOV_AIM if _aiming() else FOV, minf(1.0, delta * 12.0))
	_recoil = lerpf(_recoil, 0.0, minf(1.0, delta * 6.0))
	_camera.rotation.x = _pitch + _recoil


func _shoot(delta: float) -> void:
	_fire_cd -= delta
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var n := mini(MAG - ammo, reserve)
			ammo += n
			reserve -= n
		return
	if not _active() or not Input.is_action_pressed("foot_fire") or _fire_cd > 0.0:
		return
	if ammo <= 0:
		if Input.is_action_just_pressed("foot_fire"):
			_say("Empty. Reload with %s." % controls.binding_text("foot_reload", false), 2.0)
		return
	_fire_cd = FIRE_GAP
	ammo -= 1
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length()
	var spread := (0.004 if _aiming() else 0.02) + moving * 0.004
	var dir := -_camera.global_basis.z + _camera.global_basis.x * randf_range(-spread, spread) + _camera.global_basis.y * randf_range(-spread, spread)
	var from := _camera.global_position
	var hit := _ray(from, from + dir.normalized() * RANGE, LAYER_WORLD | LAYER_GUARDS)
	_recoil += 0.012
	_tracer(from + _camera.global_basis * Vector3(0.22, -0.18, -0.9), hit.get("position", from + dir.normalized() * RANGE))
	if hit and hit.collider is CharacterBody3D:
		var head: bool = hit.position.y - hit.collider.global_position.y > 1.45
		_damage_guard(hit.collider, DAMAGE * (2.0 if head else 1.0))
	elif hit:
		_damage_structure(hit.collider, DAMAGE)
	_noise(_player.position, NOISE_GUNSHOT, true)
	if Time.get_ticks_msec() - _gunshot_sent_at > 1000: # the server counts one a second
		_gunshot_sent_at = Time.get_ticks_msec()
		Net.send({"type": "raid_noise", "kind": "gunshot"})
	if ammo == 0 and reserve > 0:
		_reload()


## A shot that hit a turret, or a piece of the site's defences.
func _damage_structure(collider: Object, amount: float) -> void:
	for t in _turrets:
		if not t.dead and collider == t.base and t.piece == "":
			t.health -= amount
			_hit_flash = 0.15
			if t.health <= 0:
				t.dead = true
				t.head.visible = false
				t.laser.visible = false
			return
	for id in _pieces:
		var p: Dictionary = _pieces[id]
		if p.dead or collider != p.node or float(p.data.hp) <= 0.0:
			continue
		p.health -= amount
		_hit_flash = 0.15
		if p.health <= 0.0:
			destroy_piece(id)
		return


## Knocks out a piece of the site's defences (tests call this directly).
func destroy_piece(id: String) -> void:
	var p: Dictionary = _pieces[id]
	if p.dead:
		return
	p.dead = true
	p.health = 0.0
	_wreck(p)
	for t in _turrets:
		if t.piece == id:
			t.dead = true
			t.head.visible = false
			t.laser.visible = false
	var at: Vector3 = p.node.global_position
	_blast(at)
	_noise(at, NOISE_BLAST, false)
	Net.send({"type": "raid_destroy", "piece": id})
	var names := {"turret": "Turret", "guardpost": "Guard post", "power": "Power plant"}
	_say("%s destroyed.%s" % [names.get(p.data.type, "Defence"), " The core is on backup power: the blast door is opening." if p.data.type == "power" else ""], 3.0)


# A flash and a fireball where something blew up.
func _blast(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = 18.0
	add_child(light)
	light.global_position = at + Vector3(0, 2, 0)
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 2.5
	mesh.height = 5.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	ball.mesh = mesh
	add_child(ball)
	ball.global_position = at + Vector3(0, 1.5, 0)
	var tw := create_tween()
	tw.tween_property(ball, "scale", Vector3(2, 2, 2), 0.5)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.6)
	tw.tween_callback(ball.queue_free)
	tw.tween_callback(light.queue_free)


func _reload() -> void:
	if _reload_left > 0.0 or ammo == MAG or reserve <= 0:
		return
	_reload_left = RELOAD_SECONDS
	_say("Reloading", RELOAD_SECONDS)


func _heal() -> void:
	for it in inventory:
		if it.cat == "medical":
			Net.send({"type": "raid_use", "uid": it.uid})
			return
	_say("No trauma kits. Search lockers and crates.", 2.0)


func _tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.6)
	mesh.material = mat
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = (from + to) / 2.0
	if length > 0.01:
		mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(0.04).timeout.connect(mi.queue_free)


func _ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q)


# --- Guards ----------------------------------------------------------------------------

func _guard_for(body: Node) -> Dictionary:
	for g in _guards:
		if g.body == body:
			return g
	return {}


func _damage_guard(body: Node, amount: float) -> void:
	var g := _guard_for(body)
	if g.is_empty() or g.dead:
		return
	_hit_flash = 0.15
	g.health -= amount
	if g.health <= 0:
		_kill_guard(g)
	elif g.state != "combat":
		g.state = "combat"
		g.aware = GUARD_REACTION
		_last_known = _player.position


func _kill_guard(g: Dictionary) -> void:
	g.dead = true
	g.laser.visible = false
	if g.has_token:
		_tokens -= 1
		g.has_token = false
	var body: CharacterBody3D = g.body
	body.collision_layer = 0
	body.collision_mask = 0
	body.rotation.x = -PI / 2.0
	body.position.y = -floor_depth * int(g.floor) + 0.35
	body.get_node("Visor").visible = false


func _path_to(g: Dictionary, goal: Vector3) -> void:
	# Room to room through doors (the vault only once it's open), then straight to the goal.
	# Outside, guards walk straight there; nobody follows you onto another level.
	if _floor_of(goal) != g.floor:
		g.path = []
		return
	var from := _room_at(g.body.position)
	var to := _room_at(goal)
	var path: Array = []
	if from >= 0 and to >= 0 and from != to:
		var prev := {from: -1}
		var queue := [from]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			if cur == to:
				break
			for d in layout.doors:
				if d.locked and not vault_open:
					continue
				var other := -1
				if int(d.a) == cur:
					other = int(d.b)
				elif int(d.b) == cur:
					other = int(d.a)
				if other >= 0 and not prev.has(other):
					prev[other] = cur
					queue.append(other)
		if prev.has(to):
			var rooms_path := []
			var at := to
			while at != -1:
				rooms_path.push_front(at)
				at = prev[at]
			for i in range(1, rooms_path.size()):
				path.append((_room_centre(rooms_path[i - 1]) + _room_centre(rooms_path[i])) / 2.0)
				path.append(_room_centre(rooms_path[i]))
	path.append(goal)
	g.path = path


## The room a point is in, or -1 outside any (the surface counts as outside).
func _room_at(p: Vector3) -> int:
	var n := _floor_of(p)
	if n == 0:
		return -1
	var lv := _level(n)
	var x := floori((p.x - float(lv.origin[0]) + room / 2.0) / room)
	var y := floori((p.z - float(lv.origin[1]) + room / 2.0) / room)
	if x < 0 or y < 0 or x >= int(lv.cols) or y >= int(lv.rows):
		return -1
	return n * 100 + y * int(lv.cols) + x


func _can_see(from: Vector3, to: Vector3, exclude: Array) -> bool:
	return _ray(from, to, LAYER_WORLD, exclude).is_empty()


func _update_guards(delta: float) -> void:
	var eye := _player.position + Vector3(0, _camera.position.y, 0)
	for g in _guards:
		if g.dead or g.floor != _floor:
			continue
		if g.boss and g.state == "sleep":
			# The Warden waits in the safe room until someone gets in.
			if vault_open or _room_at(_player.position) == int(layout.vault):
				g.state = "combat"
				g.aware = GUARD_REACTION
				_last_known = _player.position
				_say("The Vault Warden is awake.", 3.0)
			else:
				continue
		var body: CharacterBody3D = g.body
		var head := body.position + Vector3(0, 1.65, 0)
		var to_player := eye - head
		var dist := to_player.length()
		var facing := -body.global_basis.z
		var sight := GUARD_SIGHT * (1.3 if level >= 1 else 1.0) * (0.6 if _crouched else 1.0)
		var sees := dist < sight and facing.dot(to_player.normalized()) > GUARD_FOV and _can_see(head, eye, [body])
		if dist < 2.0 and _can_see(head, eye, [body]):
			sees = true # too close to miss

		if sees:
			g.aware += delta * (2.0 if g.state in ["investigate", "search"] else 1.0)
			if g.aware >= GUARD_REACTION and g.state != "combat":
				g.state = "combat"
				Net.send({"type": "raid_noise", "kind": "spotted"})
				_say("You've been spotted!", 2.0)
			if g.state == "combat":
				_last_known = _player.position
		else:
			g.aware = maxf(0.0, g.aware - delta * 0.5)

		# A guard who finds a body raises the alarm once per body.
		if g.state != "combat":
			for other in _guards:
				if other.dead and other.floor == g.floor and not g.noticed.has(other.id) and body.position.distance_to(other.body.position) < 12.0 \
						and _can_see(head, other.body.position + Vector3(0, 0.4, 0), [body]):
					g.noticed[other.id] = true
					Net.send({"type": "raid_noise", "kind": "body"})
					_investigate(g, other.body.position)

		match g.state:
			"patrol":
				if level >= 2 and _last_known != Vector3.INF:
					_investigate(g, _last_known)
				elif _follow(g, GUARD_SPEED, delta):
					_patrol_next(g)
			"investigate":
				if _follow(g, GUARD_RUN if level >= 2 else GUARD_SPEED, delta):
					g.state = "search"
					g.search = 6.0
			"search":
				body.rotate_y(delta * 1.2)
				g.search -= delta
				if g.search <= 0.0:
					g.state = "patrol"
					_patrol_next(g)
			"combat":
				_guard_combat(g, sees, dist, delta)
		_stand(body, delta)


func _investigate(g: Dictionary, where: Vector3) -> void:
	if g.state == "combat":
		return
	g.state = "investigate"
	_path_to(g, where)


func _stand(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * delta
	else:
		body.velocity.y = 0.0
	body.move_and_slide()


## Walks a guard along its path. Returns true once it's at the end.
func _follow(g: Dictionary, speed: float, _delta: float) -> bool:
	var body: CharacterBody3D = g.body
	while not g.path.is_empty():
		var p: Vector3 = g.path[0]
		var flat := Vector3(p.x - body.position.x, 0, p.z - body.position.z)
		if flat.length() < 0.5:
			g.path.pop_front()
			continue
		var dir := flat.normalized()
		body.velocity.x = dir.x * speed
		body.velocity.z = dir.z * speed
		body.look_at(body.position + dir, Vector3.UP)
		return false
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	return true


func _guard_combat(g: Dictionary, sees: bool, dist: float, delta: float) -> void:
	var body: CharacterBody3D = g.body
	var laser: MeshInstance3D = g.laser
	if not sees:
		laser.visible = false
		g.tell = 0.0
		if g.has_token:
			_tokens -= 1
			g.has_token = false
		# Lost sight: chase to where you were last seen.
		if _last_known == Vector3.INF:
			g.state = "search"
			g.search = 4.0
			return
		if g.path.is_empty() or g.path[-1].distance_to(_last_known) > 1.0:
			_path_to(g, _last_known)
		if _follow(g, GUARD_RUN, delta):
			g.state = "search"
			g.search = 8.0
		return
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	var flat := Vector3(_player.position.x - body.position.x, 0, _player.position.z - body.position.z)
	if flat.length() > 0.01:
		body.look_at(body.position + flat, Vector3.UP)
	if not g.has_token:
		if _tokens >= ATTACK_TOKENS:
			if dist > 6.0:
				_path_to(g, _player.position)
				_follow(g, GUARD_SPEED, delta) # close in while waiting for a turn to shoot
			return
		_tokens += 1
		g.has_token = true
		g.tell = 0.0
	# Every first shot is telegraphed by the aiming laser.
	var muzzle := body.position + Vector3(0, 1.4, 0)
	var target := _player.position + Vector3(0, _camera.position.y - 0.3, 0)
	_aim_laser(laser, muzzle, target)
	g.tell += delta
	if g.tell < GUARD_TELL:
		return
	g.cd -= delta
	if g.cd > 0.0:
		return
	g.cd = 0.18 if g.elite else 0.3
	g.burst += 1
	if g.burst >= 4:
		g.burst = 0
		g.cd = 0.9
	# Accuracy tightens over two seconds of firing.
	var accuracy := clampf(0.25 + (g.tell - GUARD_TELL) * 0.35, 0.25, 0.85) * (1.0 if dist < 15.0 else 0.7)
	_noise(body.position, NOISE_GUNSHOT, false)
	if randf() < accuracy:
		_hurt(GUARD_DAMAGE * (2.0 if g.boss else 1.5 if g.elite else 1.0), body.position)


func _aim_laser(laser: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	laser.visible = true
	var length := from.distance_to(to)
	laser.scale = Vector3(1, 1, length)
	laser.global_position = (from + to) / 2.0
	laser.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)


func _update_turrets(delta: float) -> void:
	var eye := _player.position + Vector3(0, _camera.position.y - 0.2, 0)
	for t in _turrets:
		if t.dead or t.floor != _floor:
			continue
		# The site's turrets always watch; inside, a turret wakes once security is Alerted or you're in its room.
		var awake: bool = t.floor == 0 or level >= 2 or _room_at(_player.position) == t.room
		var sees: bool = awake and t.pos.distance_to(eye) < t.range and _can_see(t.pos, eye, [t.base])
		if not sees:
			t.laser.visible = false
			t.tell = 0.0
			continue
		t.head.look_at(eye, Vector3.UP)
		_aim_laser(t.laser, t.pos, eye)
		t.tell += delta
		t.cd -= delta
		if t.tell >= 0.6 and t.cd <= 0.0:
			t.cd = 0.25
			_noise(t.pos, NOISE_GUNSHOT, false)
			if randf() < 0.5:
				_hurt(8.0, t.pos)


func _hurt(amount: float, from: Vector3) -> void:
	if god_mode or over:
		return
	health -= amount
	_hurt_flash = 0.35
	_hurt_from = from
	if health <= 0.0:
		health = 0.0
		over = true
		_centre.text = "You're down."
		Net.send({"type": "raid_died"})


## A sound in the facility: guards in range come to look.
func _noise(at: Vector3, radius: float, from_player: bool) -> void:
	var on := _floor_of(at)
	for g in _guards:
		if g.dead or g.state == "combat" or g.boss or g.floor != on:
			continue
		# Guards follow your footsteps; of other sounds, only loud ones (gunfire, the drill) carry.
		if g.body.position.distance_to(at) <= radius and (from_player or radius >= NOISE_DRILL):
			_investigate(g, _player.position if from_player else at)


func _reinforce(delta: float) -> void:
	# Guard posts that still stand send out a new guard now and then, while you're outside.
	if _floor == 0:
		for id in _pieces:
			var p: Dictionary = _pieces[id]
			if p.dead or p.data.type != "guardpost":
				continue
			var alive := _guards.filter(func(g): return g.post == id and not g.dead).size()
			if alive >= 2:
				continue
			p.respawn -= delta
			if p.respawn <= 0.0:
				p.respawn = POST_RESPAWN
				_investigate(_post_guard(p), _player.position)
	if level >= 4 and not _elite_sent:
		_elite_sent = true
		_spawn_away(1, true)
		_say("PURGE: an elite security team is hunting you.", 4.0)


## Sends `count` guards after you, from somewhere on your level out of sight (never within 25 m).
func _spawn_away(count: int, elite: bool) -> void:
	for i in count:
		var at := Vector3.INF
		if _floor == 0:
			# Outside: from the far edge of the site.
			var half := float(layout.half)
			for tries in 12:
				var a := randf() * TAU
				var p := Vector3(cos(a), 0, sin(a)) * half * 1.1
				if p.distance_to(_player.position) > 25.0:
					at = p
					break
		else:
			var best := -1
			for id in rooms:
				if int(rooms[id].floor) != _floor or id == int(layout.vault):
					continue
				var c := _room_centre(id)
				if c.distance_to(_player.position) > 25.0 and (best < 0 or (randf() < 0.5 and c.distance_to(_player.position) > 25.0)):
					best = id
			if best >= 0:
				at = _room_centre(best)
		if at == Vector3.INF:
			return
		var g := _spawn_guard("w%d" % _guards.size(), [], at, elite)
		if _floor > 0:
			g.route = [_room_at(at)]
		_investigate(g, _player.position)


# --- Interacting -----------------------------------------------------------------------

## For tests: stand somewhere, stopped (on whichever level `pos` is on).
func teleport_to(pos: Vector3) -> void:
	var n := _floor_of(pos)
	_player.position = Vector3(pos.x, -floor_depth * n + 0.05, pos.z)
	_player.velocity = Vector3.ZERO
	if n != _floor:
		_set_floor(n)


## Shows only the level you're on (and wakes only its guards).
func _set_floor(n: int) -> void:
	_floor = n
	for k in _floor_nodes:
		_floor_nodes[k].visible = k == n
	for g in _guards:
		g.body.visible = g.floor == n
		g.laser.visible = false
		if g.has_token:
			_tokens -= 1
			g.has_token = false
		# Whoever was after you lost you when you took the lift.
		if g.state in ["combat", "investigate"]:
			g.state = "search"
			g.search = 4.0
			g.path = []
	for t in _turrets:
		if t.floor != n:
			t.laser.visible = false
	_last_known = Vector3.INF
	if breached and n > 0:
		Net.send({"type": "raid_floor", "floor": n})


func _near_lift() -> Dictionary:
	if not breached:
		return {}
	for l in _lifts:
		if _floor_of(l.pos) == _floor and Vector2(l.pos.x - _player.position.x, l.pos.z - _player.position.z).length() < LIFT_REACH:
			return l
	return {}


func _ride(l: Dictionary) -> void:
	teleport_to(l.to)
	_say("Back on the surface." if int(l.to_floor) == 0 else "Level %d of %d." % [int(l.to_floor), floors], 2.0)
	if int(l.to_floor) == floors and not vault_open:
		_say("The deepest level. The safe room is here: find the keycard, or drill the door.", 4.0)


func _near_vent() -> String:
	if _floor != 0:
		return ""
	for id in _vents:
		var v: Dictionary = _vents[id]
		for side in ["out", "in"]:
			var p: Vector3 = v[side]
			if Vector2(p.x - _player.position.x, p.z - _player.position.z).length() < VENT_REACH:
				return id
	return ""


func _in_lobby() -> bool:
	var c := float(layout.core) / 2.0
	return _floor == 0 and absf(_player.position.x) < c and absf(_player.position.z) < c


func _near_container() -> String:
	var best := ""
	var best_d := REACH + 0.6
	for id in _containers:
		if int(_containers[id].data.floor) != _floor:
			continue
		var node: Node3D = _containers[id].node
		var d := Vector2(node.global_position.x - _player.position.x, node.global_position.z - _player.position.z).length()
		if d < best_d:
			best = id
			best_d = d
	return best


func _near_vault_door() -> bool:
	if vault_open:
		return false
	for slab in _vault_doors:
		if slab.global_position.distance_to(_player.position + Vector3(0, 1.0, 0)) < REACH + 0.4:
			return true
	return false


func _guard_to_take_down() -> Dictionary:
	for g in _guards:
		if g.dead or g.state == "combat" or g.floor != _floor or g.boss:
			continue
		var to_guard: Vector3 = g.body.position - _player.position
		to_guard.y = 0
		if to_guard.length() < 1.8 and (-g.body.global_basis.z).dot(to_guard.normalized()) > 0.2:
			return g # behind them, facing the same way
	return {}


func _holding(item: String) -> bool:
	for it in inventory:
		if it.item == item:
			return true
	return false


func _interact() -> void:
	var g := _guard_to_take_down()
	if not g.is_empty():
		_kill_guard(g)
		_say("Silent takedown.", 2.0)
		return
	var lift := _near_lift()
	if not lift.is_empty():
		_ride(lift)
		return
	var vent := _near_vent()
	if vent != "":
		if _vents[vent].cut:
			# Through a vent that's already open, either way.
			var inside := _in_lobby()
			teleport_to(_vents[vent]["out" if inside else "in"])
			_say("Through the vent.", 1.5)
		elif _vent_left < 0.0:
			_venting = vent
			Net.send({"type": "raid_vent_start", "vent": vent})
		return
	if _near_vault_door():
		if _holding("keycard"):
			Net.send({"type": "raid_keycard"})
		elif _drill_left < 0.0:
			Net.send({"type": "raid_drill_start"})
		return
	var c := _near_container()
	if c != "":
		open_container(c)


func open_container(id: String) -> void:
	_open_container = id
	Net.send({"type": "raid_open", "container": id})
	_open_inventory()
	_inv.set_container(_containers[id].name, [], [3, 3], "Opening...")


func _open_inventory() -> void:
	_inv.visible = true
	controls.release_mouse()


func _close_inventory() -> void:
	_inv.visible = false
	if _open_container != "":
		Net.send({"type": "raid_close"})
		_open_container = ""
		_inv.set_container("", [], [0, 0], "")
	if not over:
		controls.capture_mouse()


func _update_drill(delta: float) -> void:
	if _drill_left < 0.0:
		return
	_drill_left -= delta
	_noise(_drill.global_position, NOISE_DRILL, false)
	if _drill_left <= 0.0:
		_drill_left = -1.0
		Net.send({"type": "raid_drill_finish"})


func _start_drill(seconds: float) -> void:
	_drill_left = seconds
	if _drill == null:
		var slab: Node3D = _vault_doors[0]
		for s in _vault_doors:
			if s.global_position.distance_to(_player.position) < slab.global_position.distance_to(_player.position):
				slab = s
		_drill = _box(Vector3(0.5, 0.5, 0.5), slab.global_position + (_player.position - slab.global_position).normalized() * 0.5 * Vector3(1, 0, 1), Color(1.0, 0.6, 0.1), false, true)
	_say("Drill placed. It's loud: guards will come.", 3.0)


func _update_vent(delta: float) -> void:
	if _venting == "" or _vent_left < 0.0:
		return
	if _near_vent() != _venting:
		Net.send({"type": "raid_vent_stop"})
		_venting = ""
		_vent_left = -1.0
		_say("You stopped cutting.", 2.0)
		return
	_vent_left -= delta
	if _vent_left <= 0.0:
		_vent_left = -2.0 # sent; wait for the server
		Net.send({"type": "raid_vent_finish"})


# Walking in through the open blast door counts as getting inside.
func _check_door() -> void:
	if not breached and door_open and not _enter_sent and _in_lobby():
		_enter_sent = true
		Net.send({"type": "raid_enter"})


func _update_extract(delta: float) -> void:
	var inside := ""
	for id in _extract_nodes if _floor == 0 else []:
		var e: Dictionary = _extract_nodes[id]
		if Vector2(e.pos.x - _player.position.x, e.pos.z - _player.position.z).length() < 2.2:
			inside = id
	if inside != _extracting:
		if _extracting != "":
			Net.send({"type": "raid_extract_stop"})
			_centre.text = ""
		_extracting = inside
		_extract_left = -1.0
		if inside != "":
			Net.send({"type": "raid_extract_start", "extract": inside})
	if _extracting != "" and _extract_left >= 0.0:
		_extract_left -= delta
		_centre.text = "Boarding: %.1f s" % maxf(0.0, _extract_left)
		if _extract_left <= 0.0:
			_extract_left = -2.0 # sent; wait for the server
			Net.send({"type": "raid_extract_finish"})


func _update_self_destruct(_delta: float) -> void:
	if self_destruct < 0.0:
		return
	# A red pulse that quickens as the timer runs down, wherever you are.
	var rate := 2.0 + 6.0 * (1.0 - clampf(self_destruct / 120.0, 0.0, 1.0))
	_boom_light.global_position = _player.position + Vector3(0, 3, 0)
	_boom_light.light_energy = 1.5 + 1.5 * sin(Time.get_ticks_msec() / 1000.0 * rate)


func _update_prompt() -> void:
	var key: String = controls.binding_text("interact", false)
	var text := ""
	var lift := _near_lift()
	var vent := _near_vent()
	if _inv.visible:
		text = ""
	elif not _guard_to_take_down().is_empty():
		text = "%s: silent takedown" % key
	elif not lift.is_empty():
		text = "%s: %s" % [key, lift.name.to_lower()]
	elif vent != "":
		if _vents[vent].cut:
			text = "%s: crawl through the vent" % key
		elif _vent_left >= 0.0:
			text = "Cutting the vent grate: %d s" % ceili(_vent_left)
		else:
			text = "%s: cut through the vent grate (quiet, %d s)" % [key, 6]
	elif _floor == 0 and not door_open and not breached and _player.position.distance_to(Vector3(0, 0, float(layout.core) / 2.0)) < 4.0:
		text = "The blast door is sealed. %s" % ("Knock out the power plant to open it." if layout.powered == "plant" else "The core has its own power: find a vent.")
	elif _near_vault_door():
		if _holding("keycard"):
			text = "%s: swipe the access keycard (silent)" % key
		elif _drill_left >= 0.0:
			text = "Drilling: %d s" % ceili(_drill_left)
		else:
			text = "Vault door: %s to drill it open (loud, %d s), or find an access keycard" % [key, 30]
	elif _near_container() != "":
		text = "%s: search the %s" % [key, _containers[_near_container()].name.to_lower()]
	_prompt.text = text


func _refresh_extract_labels() -> void:
	for id in _extract_nodes:
		var e: Dictionary = _extract_nodes[id]
		var st: Dictionary = extract_states.get(id, {})
		var line: String = e.name
		if not st.is_empty():
			line += ": stand here %d s to board" % int(st.countdown)
		e.label.text = line
		e.node.visible = st.get("open", true)


func _update_hud() -> void:
	var levels: Array = Net.catalog.get("heatLevels", [{"name": "?"}])
	var carried := 0
	for it in inventory:
		carried += int(it.value) * int(it.qty)
	_status.text = "%s\n%s\nTime left %d:%02d\nHeat %d  %s\nHealth %d   Ammo %d / %d\nCarrying %d credits of loot" % [
		brief.facility, _objective(), int(remaining) / 60, int(remaining) % 60, heat, levels[mini(level, levels.size() - 1)].name.to_upper(),
		ceili(health), ammo, reserve, carried]
	if _message_time <= 0.0:
		_message.text = ""
	_hud.queue_redraw()


## What to do next, for the HUD.
func _objective() -> String:
	if self_destruct >= 0.0:
		return "ESCAPE: get back aboard your ship"
	if not breached:
		var left := 0
		for id in _pieces:
			if not _pieces[id].dead and _pieces[id].data.type in ["turret", "guardpost"]:
				left += 1
		var way := "cut in through a vent" if layout.powered == "core" else ("walk in through the blast door" if door_open else "knock out the power plant, or cut in through a vent")
		return "BREACH: %s (%d defences standing)" % [way, left]
	if _floor == 0:
		return "Take the lift in the lobby down to level 1"
	if _floor < floors:
		return "LEVEL %d of %d: loot it, then find the lift down" % [_floor, floors]
	return "LEVEL %d of %d: the safe room is here. Keycard or drill." % [_floor, floors] if not vault_open else "The vault is open"


func _draw_hud() -> void:
	var size := _hud.size
	var c := size * 0.5
	var white := Color(0.35, 0.95, 0.88)
	if not _inv.visible:
		var gap := 6.0 if _aiming() else 10.0
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_hud.draw_line(c + d * gap, c + d * (gap + 8.0), white, 2.0)
		if _hit_flash > 0.0:
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				_hud.draw_line(c + d * 6.0, c + d * 13.0, Color.WHITE, 2.0)

	# Heat bar, top centre, marked at each level.
	var w := 320.0
	var bar := Rect2(c.x - w / 2.0, 24, w, 10)
	_hud.draw_rect(bar, Color(1, 1, 1, 0.15))
	var hot := Color(0.35, 0.95, 0.88).lerp(Color(1.0, 0.25, 0.15), heat / 100.0)
	_hud.draw_rect(Rect2(bar.position, Vector2(w * heat / 100.0, 10)), hot)
	for mark in [20, 40, 60, 80]:
		_hud.draw_line(Vector2(bar.position.x + w * mark / 100.0, 22), Vector2(bar.position.x + w * mark / 100.0, 36), Color(1, 1, 1, 0.5), 1.0)
	var levels: Array = Net.catalog.get("heatLevels", [{"name": "?"}])
	_hud.draw_string(_hud.get_theme_default_font(), Vector2(c.x - w / 2.0, 52), "HEAT  " + levels[mini(level, levels.size() - 1)].name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hot)

	if self_destruct >= 0.0:
		var t := "SELF-DESTRUCT  %d:%02d" % [int(self_destruct) / 60, int(self_destruct) % 60]
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		var font := _hud.get_theme_default_font()
		var w2 := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_hud.draw_string(font, Vector2(c.x - w2 / 2.0, 150), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 0.2, 0.1, pulse))

	# Lifts on this level.
	for l in _lifts:
		if _floor_of(l.pos) != _floor or (_floor == 0 and not breached):
			continue
		var lp: Vector3 = l.pos + Vector3(0, 1.5, 0)
		if not _camera.is_position_behind(lp):
			var sp := _camera.unproject_position(lp)
			if Rect2(Vector2.ZERO, size).grow(-20).has_point(sp):
				_hud.draw_circle(sp, 4, Color(0.4, 0.75, 1.0))
				_hud.draw_string(_hud.get_theme_default_font(), sp + Vector2(8, 5), "%s %d m" % [l.name, roundi(lp.distance_to(_player.position))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.75, 1.0))

	# Extract markers, on screen or at its edge.
	for id in _extract_nodes:
		var e: Dictionary = _extract_nodes[id]
		var st: Dictionary = extract_states.get(id, {})
		var p: Vector3 = e.pos + Vector3(0, 1.5, 0)
		var col := Color(0.4, 1.0, 0.6) if st.get("open", true) else Color(1, 1, 1, 0.3)
		var text := "%s %d m" % [e.name, roundi(p.distance_to(_player.position))]
		if _floor > 0:
			text = "%s (%d level%s up)" % [e.name, _floor, "" if _floor == 1 else "s"]
		if not _camera.is_position_behind(p):
			var sp := _camera.unproject_position(p)
			if Rect2(Vector2.ZERO, size).grow(-20).has_point(sp):
				_hud.draw_circle(sp, 4, col)
				_hud.draw_string(_hud.get_theme_default_font(), sp + Vector2(8, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	# Damage: red at the screen edge toward whoever hit you.
	if _hurt_flash > 0.0:
		var local := _camera.global_basis.inverse() * (_hurt_from - _player.position)
		var dir := Vector2(local.x, local.z).normalized()
		var a := _hurt_flash / 0.35
		_hud.draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, 0.12 * a))
		var p := c + dir * minf(size.x, size.y) * 0.35
		_hud.draw_circle(p, 18, Color(1.0, 0.1, 0.05, 0.6 * a))


# --- Server events ---------------------------------------------------------------------

func _on_server_error(reason: String) -> void:
	_say(reason, 3.0)


func _on_raid_event(msg: Dictionary) -> void:
	match msg.ev:
		"container":
			if msg.container == null or msg.container != _open_container:
				return
			_inv.set_container(_containers[msg.container].name, msg.slots, msg.grid, "Searching..." if msg.slots.any(func(s): return not s.has("item")) else "")
		"reveal":
			if msg.container == _open_container:
				_inv.reveal(msg.item)
		"inventory":
			inventory = msg.items
			_inv.set_inventory(inventory, brief.backpack, brief.secure)
		"heat":
			var before := level
			heat = int(msg.heat)
			level = int(msg.level)
			remaining = float(msg.remaining) / 1000.0
			extract_states = msg.extracts
			_refresh_extract_labels()
			if msg.get("doorOpen", false) and not door_open:
				_set_blast_door(true)
			if msg.get("breached") != null and not breached:
				_on_breached(str(msg.breached))
			if msg.get("selfDestruct") != null:
				var armed := self_destruct < 0.0
				self_destruct = float(msg.selfDestruct) / 1000.0
				if armed:
					_set_blast_door(true) # unlocked for the evacuation
					_say("SELF-DESTRUCT ARMED. You have %d:%02d to get back aboard your ship." % [int(self_destruct) / 60, int(self_destruct) % 60], 6.0)
			if msg.vaultOpen and not vault_open:
				_open_vault()
			if level > before:
				var levels: Array = Net.catalog.get("heatLevels", [])
				_say("Security: %s" % (levels[level].name if levels else str(level)), 3.0)
		"heal":
			health = minf(100.0, health + float(msg.amount))
			_say("Patched up.", 2.0)
		"drill":
			_start_drill(float(msg.seconds))
		"vent":
			if msg.vent == _venting:
				_vent_left = float(msg.seconds)
				_say("Cutting the grate. Stay close.", 2.0)
		"wave":
			_spawn_away(int(msg.count), false)
			_say("Reinforcements: %d more guard%s inbound." % [int(msg.count), "" if int(msg.count) == 1 else "s"], 3.0)
		"extracting":
			if msg.extract == _extracting:
				_extract_left = float(msg.countdown)
				if msg.loud:
					_noise(_extract_nodes[_extracting].pos, NOISE_EXTRACT, false)
		"end":
			_show_results(msg.result)
		"begin":
			pass # a resumed run while already inside: nothing to rebuild


func _on_breached(via: String) -> void:
	breached = true
	if via == "vent" and _venting != "":
		_vents[_venting].cut = true
		_vents[_venting].node.visible = false
		teleport_to(_vents[_venting]["in"])
		_venting = ""
		_vent_left = -1.0
	_say("You're in. Take the lift down. Every minute inside brings more guards.", 4.0)


func _open_vault() -> void:
	vault_open = true
	for slab in _vault_doors:
		slab.visible = false
		slab.get_child(0).disabled = true
	if _drill:
		_drill.queue_free()
		_drill = null
	_drill_left = -1.0
	_say("The vault is open.", 3.0)


func _show_results(result: Dictionary) -> void:
	over = true
	_inv.visible = false
	_paused.visible = false
	_centre.text = ""
	controls.release_mouse()
	var titles := {"extracted": "EXTRACTED", "killed": "KILLED IN ACTION", "destroyed": "LOST IN THE SELF-DESTRUCT", "mia": "MISSING IN ACTION", "bailed": "BAILED OUT"}
	var root := ColorRect.new()
	root.color = Color(0, 0.02, 0.05, 0.9)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.get_parent().add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	var title := Label.new()
	title.text = titles.get(result.outcome, result.outcome)
	title.add_theme_font_size_override("font_size", 34)
	title.modulate = Color(0.4, 1.0, 0.6) if result.outcome == "extracted" else Color(1.0, 0.4, 0.35)
	col.add_child(title)
	var lines := ["%s   %d:%02d in the facility   peak Heat %d" % [brief.facility, int(result.seconds) / 60, int(result.seconds) % 60, int(result.heatPeak)]]
	if result.outcome == "destroyed":
		lines.append("The facility blew with you inside, and took your ship with it. Only your Secure Case survived.")
	if result.kept.is_empty():
		lines.append("You came away with nothing.")
	else:
		lines.append("\nYou kept, worth %d credits:" % int(result.value))
		for k in result.kept:
			lines.append("  %d x %s%s" % [k.qty, Net.item_name(k.item), "  (found in raid)" if k.fih else ""])
	if not result.lost.is_empty():
		lines.append("\nLost:")
		for k in result.lost:
			lines.append("  %d x %s" % [k.qty, Net.item_name(k.item)])
	if not result.stolen.is_empty():
		var s := []
		for id in result.stolen:
			s.append("%d %s" % [result.stolen[id], Net.item_name(id)])
		lines.append("\nTaken from the owner's vault: " + ", ".join(s))
	lines.append("\nSell loot to the Fence at the Spaceport.")
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var back := Button.new()
	back.text = "Back to the ship" if result.outcome != "destroyed" else "Respawn at the spaceport"
	back.pressed.connect(func(): finished.emit(result))
	col.add_child(back)
	back.grab_focus()
