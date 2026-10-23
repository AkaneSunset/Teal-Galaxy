extends Node3D
## A place you walk around on foot in first person: the base class of the High Port interior
## (station.gd) and a Builder's base on a planet's surface (surface.gd).
##
## You arrive seated in your own ship, landed with its ramp down. The ship's menu (drawn by the
## explorer) decides what happens next: leave your seat and walk down the ramp, fly somewhere, or
## launch. Walking back up your ship's ramp sits you down in it again. Esc pauses; the only way
## out of a place is your ship.
##
## Subclasses build their world in `_build()`, may add per-frame work in `_tick()`, and name where
## the player is in `_location()`. Building blocks (boxes, screens, signs, consoles, lights, things
## to use with F, landed ships with ramps) are shared from here.
## `planet_id` is a Builder's home planet, or a contested world of the war (its orbital station),
## which has no record in the system's planets: `_planet` is empty there.
##
## Places are shared: other pilots in the same space (see walkers.gd) walk around in them too. The
## explorer enters the server's space and sets `space_id`; `walker_pose()` is what others see of you.
## While a sector battle's RTS view is up (game/battle/, BattleView.active), the explorer hides and
## disables the place; `battle_active()` says so.

const System := preload("res://teal_prime.gd")
const Models := preload("res://models.gd")
const ChatBox := preload("res://chat_box.gd")
const WarInfo := preload("res://war_info.gd")
const Walkers := preload("res://walkers.gd")
const BATTLE_VIEW := "res://battle/battle_view.gd"
const DEFENSE_VIEW := "res://defense/defense_view.gd"
const FACILITY_VIEW := "res://facility/facility_view.gd"
const SPACE_VIEW := "res://space/space_view.gd"

signal seated_down # walked up your own ship's ramp and sat down
signal service(kind: String) # "repair", "war" (a War terminal), "contracts", "dock_market"
signal wants_menu # used a console that opens the ship's menu (the transit terminal)
signal wants_space(space: String) # walked through a door into another shared space (an airlock, a boarding door)

const WALK := 4.2
const SPRINT := 7.0
const JUMP := 4.0
const GRAVITY := 14.0
const EYE := 1.65
const LOOK_SPEED := 2.6
const REACH := 2.6
const SIT_EYE := 1.15

# Colours, sampled from the station concept art: light grey panels, darker trim, cyan light strips.
const WALL := Color(0.56, 0.58, 0.61)
const PANEL := Color(0.47, 0.49, 0.53)
const TRIM := Color(0.27, 0.29, 0.32)
const FLOOR := Color(0.43, 0.45, 0.48)
const FLOOR_DARK := Color(0.32, 0.34, 0.37)
const CYAN := Color(0.25, 0.95, 0.92)
const SCREEN_TEXT := Color(0.5, 0.97, 0.95)
const CUSHION := Color(0.24, 0.47, 0.52)
const HAZARD := Color(0.95, 0.74, 0.18)
const ALERT := Color(1.0, 0.32, 0.28)

var controls: Node
var planet_id := "aster"
var place_name := ""
var seated := true # sitting in your ship (the ship's menu is up)
var menu_open := false # the explorer has the ship's menu up while you stand (the transit terminal)
var space_id := "" # the shared space the server has us in here ("station:cinder"), set by the explorer
var walkers: Node3D # the other pilots here (walkers.gd)
var hud_layer: CanvasLayer

var _planet := {} # the server's planet record
var _player: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0
var _mats := {}
var _uses := [] # {"node": Node3D, "prompt": Callable, "action": Callable}
var _ships := [] # landed ships: {"root", "entry", "spawn", "seat", "owner", "open", "mine", "pad"}
var _arrival: Marker3D # where you stand when you leave your seat, in a place with no landed ship of yours
var _sitting := false # sitting on a seat (a lounge chair), not in your ship
var _own: Array[Node] = [] # what the place built, to hide while a battle's RTS view is up
var _battle_envs: Array[Node] = []

var _prompt: Label
var _chat: VBoxContainer
var _where: Label
var _message: Label
var _message_time := 0.0
var _paused: PanelContainer


func _init(planet := "aster") -> void:
	planet_id = planet


func _ready() -> void:
	_planet = Net.planet(planet_id)
	_build()
	_build_player()
	_build_hud()
	walkers = Walkers.new(self)
	add_child(walkers)
	_own.assign(get_children())
	sit()


## Subclasses build their world here.
func _build() -> void:
	pass


## Subclasses' per-frame work.
func _tick(_delta: float) -> void:
	pass


## Where the player is, for the top-left of the HUD.
func _location() -> String:
	return ""


# --- Materials and building blocks ---------------------------------------------------------

func _mat(colour: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [colour, glow, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(colour, alpha)
	m.roughness = 0.75
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## A box in `parent`'s space. Solid boxes block the player.
func _box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, solid := true, glow := 0.0, alpha := 1.0, rot := Vector3.ZERO) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(colour, glow, alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if alpha < 1.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node: Node3D = mi
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = size
		body.add_child(shape)
		body.add_child(mi)
		node = body
	node.position = pos
	node.rotation_degrees = rot
	parent.add_child(node)
	return node


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, colour: Color, solid := true, glow := 0.0, top := -1.0, sides := 24) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.material = _mat(colour, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var node: Node3D = mi
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = CylinderShape3D.new()
		shape.shape.radius = maxf(radius, mesh.top_radius)
		shape.shape.height = height
		body.add_child(shape)
		body.add_child(mi)
		node = body
	node.position = pos
	parent.add_child(node)
	return node


## A flat glowing ring on the floor or around a pad.
func _ring_line(parent: Node3D, radius: float, pos: Vector3, colour: Color, width := 0.12, glow := 2.0) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width * 0.5
	mesh.outer_radius = radius + width * 0.5
	mesh.rings = 64
	mesh.material = _mat(colour, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = Vector3(1, 0.15, 1)
	parent.add_child(mi)


## Words in the world, facing `facing` (readable from that side).
func _text(parent: Node3D, text: String, pos: Vector3, facing: Vector3, size := 48, colour := SCREEN_TEXT, left := false, width := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = colour
	l.outline_size = 0
	l.position = pos
	l.basis = _facing_basis(facing)
	if left:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = width / l.pixel_size
	parent.add_child(l)
	return l


func _facing_basis(facing: Vector3) -> Basis:
	if absf(facing.y) > 0.99:
		return Basis(Vector3.RIGHT, -signf(facing.y) * PI / 2)
	return Basis.looking_at(-facing, Vector3.UP)


## A wall screen: a dark bezel, a faintly glowing face, a title and a body. Returns the body label.
func _screen(parent: Node3D, pos: Vector3, facing: Vector3, size: Vector2, title: String, body := "", title_size := 56, body_size := 34, accent := CYAN) -> Label3D:
	var s := Node3D.new()
	s.position = pos
	s.basis = _facing_basis(facing)
	parent.add_child(s)
	_box(s, Vector3(size.x + 0.24, size.y + 0.24, 0.14), Vector3(0, 0, -0.07), TRIM, false)
	_box(s, Vector3(size.x, size.y, 0.02), Vector3(0, 0, 0.01), Color(0.02, 0.07, 0.085), false, 1.0)
	_box(s, Vector3(size.x, 0.04, 0.02), Vector3(0, size.y / 2 - 0.02, 0.025), accent, false, 2.5)
	var top_left := Vector3(-size.x / 2 + 0.16, size.y / 2 - 0.14, 0.03)
	_text(s, title, top_left, Vector3.BACK, title_size, accent, true, size.x - 0.3)
	return _text(s, body, top_left + Vector3(0, -title_size * 0.004 - 0.12, 0), Vector3.BACK, body_size, SCREEN_TEXT, true, size.x - 0.3)


## A sign: words in bold on a dark plate.
func _sign(parent: Node3D, text: String, pos: Vector3, facing: Vector3, size := 72, colour := SCREEN_TEXT, plate := Vector2.ZERO) -> Label3D:
	var s := Node3D.new()
	s.position = pos
	s.basis = _facing_basis(facing)
	parent.add_child(s)
	var w := plate.x if plate.x > 0.0 else text.length() * size * 0.0026 + 0.6
	var h := plate.y if plate.y > 0.0 else size * 0.004 * (text.count("\n") + 1) + 0.35
	_box(s, Vector3(w, h, 0.1), Vector3(0, 0, -0.05), Color(0.16, 0.18, 0.2), false)
	_box(s, Vector3(w, 0.03, 0.02), Vector3(0, -h / 2 + 0.06, 0.01), colour, false, 2.0)
	return _text(s, text, Vector3(0, 0.02, 0.02), Vector3.BACK, size, colour)


func _light(parent: Node3D, pos: Vector3, colour := Color(0.85, 0.92, 1.0), energy := 1.0, reach := 9.0) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.0
	parent.add_child(l)


## Something to use with F. `prompt` returns the words shown when close; `action` runs on F.
func _use(parent: Node3D, pos: Vector3, prompt: Callable, action: Callable) -> void:
	var m := Marker3D.new()
	m.position = pos
	parent.add_child(m)
	_uses.append({"node": m, "prompt": prompt, "action": action})


func _seat(parent: Node3D, pos: Vector3, height := 0.75) -> void:
	_cyl(parent, 0.1, height, pos + Vector3(0, height / 2, 0), TRIM, false)
	_cyl(parent, 0.36, 0.06, pos + Vector3(0, 0.03, 0), TRIM, true)
	_cyl(parent, 0.34, 0.16, pos + Vector3(0, height, 0), Color(0.2, 0.22, 0.25), false)
	_ring_line(parent, 0.33, pos + Vector3(0, height - 0.09, 0), CYAN, 0.04, 2.5)


## A terminal: a pedestal with a sloped control deck in front and an upright screen standing on its
## back edge, facing `facing`. Returns the screen's body label.
func _console(parent: Node3D, pos: Vector3, facing: Vector3, title: String, body := "", width := 1.6) -> Label3D:
	var c := Node3D.new()
	c.position = pos
	c.basis = _facing_basis(facing)
	parent.add_child(c)
	_box(c, Vector3(width, 0.9, 0.7), Vector3(0, 0.45, 0), PANEL)
	_box(c, Vector3(width + 0.06, 0.08, 0.76), Vector3(0, 0.04, 0), TRIM, false)
	_box(c, Vector3(width - 0.1, 0.04, 0.04), Vector3(0, 0.22, 0.36), CYAN, false, 2.0)
	# The control deck: a slab on top, its front edge tipped down 14 degrees, with a few lit keys.
	var deck := Node3D.new()
	deck.position = Vector3(0, 0.93, 0.08)
	deck.rotation_degrees.x = 14.0
	c.add_child(deck)
	_box(deck, Vector3(width + 0.04, 0.06, 0.56), Vector3.ZERO, TRIM, false)
	for i in 5:
		_box(deck, Vector3(0.12, 0.025, 0.1), Vector3(-width / 2.0 + 0.22 + i * 0.18, 0.04, 0.12), [CYAN, HAZARD, CYAN, ALERT, CYAN][i], false, 2.0)
	_box(deck, Vector3(width * 0.3, 0.02, 0.18), Vector3(width * 0.25, 0.04, 0.08), Color(0.05, 0.12, 0.14), false, 1.0)
	# The screen, on a short stand at the back, leaning back a little.
	var sw := width * 0.9
	var sh := 0.62
	_box(c, Vector3(0.18, 0.2, 0.12), Vector3(0, 1.02, -0.26), TRIM, false)
	return _screen(c, Vector3(0, 1.12 + sh / 2.0 + 0.12, -0.3), Vector3(0, 0.22, 1).normalized(), Vector2(sw, sh), title, body, 28, 20)


func _crate(parent: Node3D, size: Vector3, pos: Vector3, label := "") -> void:
	_box(parent, size, pos + Vector3(0, size.y / 2, 0), Color(0.36, 0.38, 0.41))
	_box(parent, Vector3(size.x + 0.04, 0.08, size.z + 0.04), pos + Vector3(0, size.y * 0.75, 0), TRIM, false)
	_box(parent, Vector3(size.x * 0.6, 0.04, 0.02), pos + Vector3(0, size.y * 0.75, size.z / 2 + 0.03), CYAN, false, 2.0)
	if label != "":
		_text(parent, label, pos + Vector3(0, size.y * 0.4, size.z / 2 + 0.03), Vector3.BACK, 28, Color(0.85, 0.87, 0.9))


func _planter(parent: Node3D, pos: Vector3) -> void:
	_box(parent, Vector3(0.8, 0.6, 0.8), pos + Vector3(0, 0.3, 0), PANEL)
	for i in 5:
		var leaf := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.5
		mesh.material = _mat(Color(0.22, 0.5, 0.25))
		leaf.mesh = mesh
		leaf.position = pos + Vector3(cos(i * 1.3) * 0.18, 0.75 + (i % 2) * 0.12, sin(i * 1.3) * 0.18)
		parent.add_child(leaf)


func _bench(parent: Node3D, pos: Vector3, facing: Vector3, length := 3.0) -> void:
	var b := Node3D.new()
	b.position = pos
	b.basis = _facing_basis(facing)
	parent.add_child(b)
	_box(b, Vector3(length, 0.45, 0.7), Vector3(0, 0.22, 0), PANEL)
	_box(b, Vector3(length - 0.1, 0.14, 0.62), Vector3(0, 0.52, 0.02), CUSHION, false)
	_box(b, Vector3(length - 0.1, 0.55, 0.16), Vector3(0, 0.85, -0.3), CUSHION, false)



# --- Landed ships ---------------------------------------------------------------------------

## A ship standing on a pad on its landing gear. Every ship has an exit ramp under its hull: while the
## ship is open the ramp is down and anyone can walk up it and board; while locked the ramp is up.
func _landed_ship(room: Node3D, pad: Vector3, yaw: float, owner: String, open: bool, mine: bool, pad_no: int) -> void:
	var spec: Dictionary = Models.RAMPS.starter_ship
	var root := Node3D.new()
	root.position = pad
	root.rotation_degrees.y = yaw
	room.add_child(root)
	var lift: float = 0.37 + spec.landed_height # the pad's top, plus the gear
	var ship := Models.starter_ship()
	ship.position = Vector3(0, lift, 0)
	root.add_child(ship)
	# Landing gear: four struts with feet, clear of the ramp.
	for g in [Vector3(-1.9, 0, -2.8), Vector3(1.9, 0, -2.8), Vector3(-1.9, 0, 3.4), Vector3(1.9, 0, 3.4)]:
		var top := lift - 1.3
		_cyl(root, 0.12, top - 0.37, g + Vector3(0, 0.37 + (top - 0.37) / 2.0, 0), TRIM, false)
		_cyl(root, 0.32, 0.12, g + Vector3(0, 0.43, 0), PANEL, false)
		_cyl(root, 0.2, 0.3, g + Vector3(0, top - 0.1, 0), PANEL, false)
	# The hull blocks walking underneath it.
	_box(root, Vector3(4.6, 2.6, 9.6), Vector3(0, lift, 0.6), Color(0, 0, 0), true, 0.0, 0.0)
	# The hatch, and the ramp: down to the floor when open, folded up under the hull when locked.
	var hatch: Vector3 = spec.hatch + Vector3(0, lift, 0)
	var width: float = spec.width
	_box(root, Vector3(width, 0.04, 1.8), hatch + Vector3(0, 0.02, 0.9), Color(0.03, 0.03, 0.04), false)
	var foot := Vector3(0, 0.03, hatch.z + 4.2)
	var run := foot - hatch
	var ramp := Node3D.new()
	root.add_child(ramp)
	if open:
		ramp.position = (hatch + foot) / 2.0
		ramp.rotation.x = atan2(-run.y, run.z)
		_light(root, hatch + Vector3(0, -0.4, 0.6), Color(1.0, 0.85, 0.6), 1.2, 4.0)
	else:
		ramp.position = hatch + Vector3(0, -0.06, run.length() / 2.0 - 0.3)
	var length := run.length()
	_box(ramp, Vector3(width, 0.1, length), Vector3.ZERO, Color(0.4, 0.42, 0.45), open)
	for s in [-1, 1]:
		_box(ramp, Vector3(0.06, 0.06, length - 0.2), Vector3(s * (width / 2.0 - 0.05), 0.07, 0), CYAN if open else ALERT, false, 2.5)
	for k in range(1, int(length / 0.45)):
		_box(ramp, Vector3(width - 0.2, 0.03, 0.05), Vector3(0, 0.06, -length / 2.0 + k * 0.45), TRIM, false)
	var tag := Label3D.new()
	tag.text = "%s\n%s" % ["YOUR SHIP" if mine else "%s'S SHIP" % owner.to_upper(), "OPEN · RAMP DOWN" if open else "LOCKED"]
	tag.position = Vector3(0, lift + 3.4, 1.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = 64
	tag.outline_size = 8
	tag.modulate = Color(0.45, 1.0, 0.6) if open else ALERT
	root.add_child(tag)
	var entry := Marker3D.new()
	entry.position = foot + Vector3(0, 0.5, -1.2) # a step or two up the ramp
	root.add_child(entry)
	var spawn := Marker3D.new()
	spawn.position = foot + Vector3(0, 0.1, 2.6)
	root.add_child(spawn)
	# The pilot's seat: under the canopy, looking out past the nose.
	var seat := Marker3D.new()
	seat.position = Vector3(0, lift + 1.55, -3.6)
	seat.rotation_degrees.x = 2.0
	root.add_child(seat)
	_ships.append({"root": root, "entry": entry, "spawn": spawn, "seat": seat, "owner": owner, "open": open, "mine": mine, "pad": pad_no})


## The landed ship nearest the player, if any is close: {"ship", "distance"}.
func _near_ship(range_m: float) -> Dictionary:
	var best := {}
	for sh in _ships:
		var e: Vector3 = sh.entry.global_position
		var d := Vector2(e.x - _player.global_position.x, e.z - _player.global_position.z).length()
		if d < range_m and (best.is_empty() or d < best.distance):
			best = {"ship": sh, "distance": d}
	return best


## Walking up an open ship's ramp takes you aboard. Your own ship takes you back to its cockpit.
func _check_ramps() -> void:
	var near := _near_ship(1.1)
	if near.is_empty():
		return
	var sh: Dictionary = near.ship
	if not sh.open or _player.global_position.y < 0.15:
		return
	if sh.mine:
		sit()
		seated_down.emit()
	else:
		_stand_at(sh.spawn)
		_say("You step aboard %s's ship and look around. Ship interiors come with the ship cabin." % sh.owner, 5.0)


## Puts the player on a marker, facing away from the ship it belongs to.
func _stand_at(marker: Marker3D) -> void:
	_player.global_position = marker.global_position
	_player.velocity = Vector3.ZERO
	var away: Vector3 = marker.global_basis.z
	_player.rotation.y = atan2(-away.x, -away.z)


# --- The player ---------------------------------------------------------------------------

func _build_player() -> void:
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.shape.height = 1.8
	shape.position.y = 0.9
	_player.add_child(shape)
	add_child(_player)
	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = 80.0
	_camera.near = 0.05
	_camera.far = 16000.0
	_player.add_child(_camera)
	_camera.make_current()


func _my_ship() -> Dictionary:
	for sh in _ships:
		if sh.mine:
			return sh
	return {}


## Sit in your own ship's pilot seat, looking out past its nose. The explorer shows the ship's menu.
func sit() -> void:
	seated = true
	var sh := _my_ship()
	if sh.is_empty():
		return
	_player.global_position = sh.spawn.global_position
	_player.velocity = Vector3.ZERO
	_camera.top_level = true
	_camera.global_transform = sh.seat.global_transform
	_show_canopy(sh, false)
	if controls:
		controls.release_mouse()


## The canopy glass is hidden while you sit under it, so the view out isn't tinted.
func _show_canopy(sh: Dictionary, on: bool) -> void:
	var glass := Models.material("glass")
	for node in sh.root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.material_override == glass:
			mi.visible = on


## Leave your seat and walk down the ramp: you stand at its foot, facing away from the ship.
## A place with no landed ship of yours stands you at its arrival point instead.
func stand() -> void:
	seated = false
	menu_open = false
	_sitting = false
	_camera.top_level = false
	_camera.transform = Transform3D(Basis(), Vector3(0, EYE, 0))
	_pitch = 0.0
	var sh := _my_ship()
	if not sh.is_empty():
		_stand_at(sh.spawn)
		_show_canopy(sh, true)
	elif _arrival:
		_stand_at(_arrival)
	if controls:
		controls.capture_mouse()


## Sit down on a seat (a lounge chair or a bar stool): the view drops to a sitting eye height and the
## others see you sitting. Walking stands you up again.
func sit_on(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.rotation.y = yaw
	_camera.position.y = SIT_EYE
	_sitting = true


func _stand_up() -> void:
	_sitting = false
	_camera.position.y = EYE
	_player.global_position += _player.global_basis * Vector3(0, 0.05, -0.7)


## What the other pilots in this space see of you: {"pos", "yaw", "anim"}, or {} to send nothing
## (seated in your ship, which they see as a landed ship).
func walker_pose() -> Dictionary:
	if seated:
		return {}
	var v := Vector2(_player.velocity.x, _player.velocity.z).length()
	var anim := "sit" if _sitting else ("run" if v > WALK + 0.5 else ("walk" if v > 0.4 else "idle"))
	return {"pos": _player.global_position, "yaw": _player.rotation.y, "anim": anim}


## True while a sector battle's RTS view is up (game/battle/battle_view.gd sets BattleView.active).
## The view may not be built yet, so it's looked up rather than named.
static func battle_active() -> bool:
	for path in [BATTLE_VIEW, DEFENSE_VIEW, FACILITY_VIEW, SPACE_VIEW]: # a sector battle's RTS view, or an FPS match (Supremacy's view is a Facility one)
		if ResourceLoader.exists(path):
			var view = load(path)
			if view != null and view.get("active") == true:
				return true
	return false


## For tests and screenshots: stand at a point (in `space`'s coordinates) looking at another.
func view_at(space: Node3D, at: Vector3, look: Vector3) -> void:
	if seated:
		stand()
	_player.global_position = space.to_global(at) - Vector3(0, EYE, 0)
	_player.velocity = Vector3.ZERO
	var dir: Vector3 = space.to_global(look) - space.to_global(at)
	_player.rotation.y = atan2(-dir.x, -dir.z)
	_pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	_camera.rotation.x = _pitch


func _walking() -> bool:
	return not seated and not menu_open and not _paused.visible and not _chat.is_typing() and not battle_active()


## Mouse look is read in _input, before any on-screen control can catch the motion.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _walking():
		var sens: float = (controls.mouse_sensitivity if controls else 1.0) * 0.0022
		var dy: float = -event.relative.y if controls and controls.invert_mouse else event.relative.y
		_look(-event.relative.x * sens, -dy * sens)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if seated or menu_open or _chat.is_typing() or battle_active():
		return
	if event.is_action_pressed("menu"):
		_set_paused(not _paused.visible)
		get_viewport().set_input_as_handled()
		return
	if _paused.visible:
		return
	if event.is_action_pressed("chat"):
		_chat.open()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and controls:
		controls.capture_mouse()
	if event.is_action_pressed("interact"):
		var u := _nearest_use()
		if not u.is_empty():
			u.action.call()


func _set_paused(on: bool) -> void:
	_paused.visible = on
	if controls:
		if on:
			controls.release_mouse()
		else:
			controls.capture_mouse()


## The explorer opens or closes the ship's menu over the place while you're standing.
func set_menu_open(on: bool) -> void:
	menu_open = on
	if controls and not seated:
		if on:
			controls.release_mouse()
		else:
			controls.capture_mouse()


func _look(yaw: float, pitch: float) -> void:
	_player.rotate_y(yaw)
	_pitch = clampf(_pitch + pitch, -1.45, 1.45)
	_camera.rotation.x = _pitch


## Hides the place (and takes it out of the physics) while a sector battle's RTS view is up, or
## brings it back. Only what the place built itself: screens a battle added stay as they are.
func battle_hide(on: bool) -> void:
	if on:
		_battle_envs.clear()
	for node in _own:
		if not is_instance_valid(node):
			continue
		if node is WorldEnvironment:
			if on and node.get_parent() == self:
				remove_child(node)
				_battle_envs.append(node)
		elif node is Node3D or node is CanvasLayer:
			node.visible = not on
			node.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if not on:
		for env in _battle_envs:
			add_child(env)
			move_child(env, 0)
		_battle_envs.clear()
		_player.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if battle_active() or _player.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	var walking := _walking()
	var input := Input.get_vector("foot_left", "foot_right", "foot_forward", "foot_back") if walking else Vector2.ZERO
	var look := Input.get_vector("foot_look_left", "foot_look_right", "foot_look_up", "foot_look_down") if walking else Vector2.ZERO
	if look.length() > 0.1:
		_look(-look.x * LOOK_SPEED * delta, -look.y * LOOK_SPEED * delta)
	if _sitting and input.length() > 0.3:
		_stand_up()
	if _sitting:
		input = Vector2.ZERO
		_player.velocity = Vector3.ZERO
	if not seated and not _sitting:
		var speed := SPRINT if walking and Input.is_action_pressed("foot_sprint") else WALK
		var dir := (_player.global_basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
		_player.velocity.x = dir.x * speed
		_player.velocity.z = dir.z * speed
		if _player.is_on_floor():
			if walking and Input.is_action_just_pressed("foot_jump"):
				_player.velocity.y = JUMP
		else:
			_player.velocity.y -= GRAVITY * delta
		_player.move_and_slide()
		if _player.position.y < _fall_limit():
			stand()
		_check_ramps()
	_tick(delta)
	_update_hud(delta)


func _nearest_use() -> Dictionary:
	var best := {}
	var best_d := REACH
	var eye := _camera.global_position
	var forward := -_camera.global_basis.z
	for u in _uses:
		var p: Vector3 = u.node.global_position
		var d := Vector2(p.x - eye.x, p.z - eye.z).length()
		if d < best_d and forward.dot((p - eye).normalized()) > 0.2:
			best_d = d
			best = u
	return best


# --- HUD ----------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_layer = layer
	_where = Label.new()
	_where.position = Vector2(20, 16)
	_where.add_theme_font_size_override("font_size", 20)
	_where.modulate = SCREEN_TEXT
	_where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_where)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 120
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_prompt)
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position.y += 70
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 20)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_message)
	_chat = ChatBox.new()
	_chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat.position += Vector2(20, -40)
	_chat.modulate = SCREEN_TEXT.lightened(0.3)
	_chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_chat)
	# The crosshair. It ignores the mouse: a control under a captured cursor would eat mouse look.
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.7)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.name = "Crosshair"
	layer.add_child(dot)
	# Paused: Esc while walking. You don't leave a place from here, only by your ship.
	_paused = PanelContainer.new()
	_paused.set_anchors_preset(Control.PRESET_CENTER)
	_paused.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_paused.grow_vertical = Control.GROW_DIRECTION_BOTH
	_paused.visible = false
	layer.add_child(_paused)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_paused.add_child(margin)
	margin.add_child(col)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)
	var hint := Label.new()
	hint.text = _leave_hint()
	col.add_child(hint)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): _set_paused(false))
	col.add_child(resume)


func _update_hud(delta: float) -> void:
	var crosshair := _prompt.get_parent().get_node("Crosshair") as Control
	crosshair.visible = not seated
	if seated:
		_where.text = _seated_text()
		_prompt.text = ""
	else:
		var here := _location()
		_where.text = "%s%s\nW A S D walk   Shift run   Mouse look   %s use   %s chat   Esc pause" % [place_name, (" · " + here) if here != "" else "", _key(), _chat_key()]
		var u := _nearest_use()
		_prompt.text = u.prompt.call() if not u.is_empty() and not menu_open else ""
		var near := _near_ship(4.5)
		if _prompt.text == "" and not near.is_empty() and not menu_open:
			var sh: Dictionary = near.ship
			if sh.mine:
				_prompt.text = "Your ship. Walk up the ramp to take your seat"
			elif sh.open:
				_prompt.text = "%s's ship is open. Walk up the ramp to step aboard" % sh.owner
			else:
				_prompt.text = "%s's ship is locked, ramp up" % sh.owner
	_message_time -= delta
	_message.visible = _message_time > 0.0


## Below this height you've fallen out of the place: back to the start.
func _fall_limit() -> float:
	return -10.0


## The top-left line while you sit in your ship.
func _seated_text() -> String:
	return "%s · in your ship" % place_name


## How to leave, on the pause screen.
func _leave_hint() -> String:
	return "To leave, walk back up your ship's ramp and take your seat."


func _say(text: String, seconds := 4.0) -> void:
	_message.text = text
	_message_time = seconds
	_message.visible = true


func _chat_key() -> String:
	return controls.binding_text("chat", false) if controls else "Enter"


func _key() -> String:
	return controls.binding_text("interact", false) if controls else "F"


func _me() -> Dictionary:
	return Net.state.get("pilots", {}).get(Net.my_name, {}) if not Net.state.is_empty() else {}


## The planet's name: a Builder's home, or a contested world of the war.
func _planet_name() -> String:
	if _planet.has("name"):
		return str(_planet.name)
	return str(WarInfo.planet(planet_id).get("name", planet_id.capitalize()))
