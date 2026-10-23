extends "res://place.gd"
## Inside a fleet carrier (the demo's ship), on foot in first person. Built in code from boxes, like
## the stations. Leave the pilot's chair (Leave seat, G) and the carrier holds still where it is while
## you walk around it; sit in the chair again (F) to fly. Docked at a station's berth, the chair is
## where you undock, and the airlock on the Hangar Deck leads into the station.
##
## The carrier sits at the scene origin with its bow toward -Z, and the explorer draws space around
## it turned to match the ship (see explorer.gd), so the windows look out on the real sky: the star,
## the planets, the station you're berthed at and the other carriers.
##
## Two levels joined by a lift:
##   Command level (floor y = 0), bow to stern:
##     Bridge          the pilot's chair on its dais, a wide forward window, side consoles
##     Command Deck    the holo table (F: Sector Battles), the GALAXY MAP terminal (F: FTL jump to
##                     any system or planet), the war log wall, a window and the planet-below screen
##     Main corridor   with the lift lobby to starboard
##     Crew Lounge     the lobby: seats, the bar, who's aboard, the crew channel
##   Hangar Deck (floor y = -16): a tall bay with parked drones (tanks, strikers, gunships) and
##   landers, the launch doors at the stern, the lift up, and the airlock to the station to port.
##
## Other people aboard are drawn by walkers.gd: anyone may board your carrier from a station where
## you're both docked (the boarding doors in its hangar), and they ride along as crew if you fly off.

const HANGAR_Y := -16.0
const HANGAR_H := 14.0
const BATTLE_MENU := "res://battle/battle_menu.gd"

# Warship colours: darker and colder than the stations, with the owner's faction as the accent.
const HULL := Color(0.34, 0.36, 0.4)
const HULL_PANEL := Color(0.28, 0.3, 0.34)
const DECK := Color(0.24, 0.26, 0.29)
const DECK_DARK := Color(0.17, 0.18, 0.21)
const GLASS := Color(0.6, 0.8, 1.0)

var owner_name := "" # whose carrier this is
var mine := true
var docked_at := "" # the station (planet id) this carrier is clamped at, or "" in open space
var berth_text := "" # "Berth 12, Cinder Orbital (1)"
var over := "" # the contested world whose orbit the carrier is in, or ""
var home_carrier := "" # aboard someone else's: where your own carrier is, for the shuttle console
## Whether other pilots may board your carrier (the COMMS console on the Bridge; server ship_open).
## Kept for the session, and told to the server again whenever your carrier is built.
static var open_to_visitors := true

var _accent := CYAN
var _chair_eye: Marker3D
var _chair_stand: Marker3D
var _airlock_in: Marker3D
var _lift_top: Marker3D
var _lift_bottom: Marker3D
var _boards := {} # name -> Label3D
var _holo: Node3D
var _holo_markers: Node3D
var _holo_for := "-" # the planet the hologram shows
var _chat_lines: Array[String] = []
var _refresh_in := 0.0
var _airlock_wait := 0.0
var _battle_menu: Control


func _init(owner := "", planet := "") -> void:
	super(planet)
	owner_name = owner


func _build() -> void:
	mine = owner_name == "" or owner_name == Net.my_name
	if owner_name == "":
		owner_name = Net.my_name
	place_name = "Your fleet carrier" if mine else "%s's fleet carrier" % owner_name
	var side = Net.state.get("pilots", {}).get(owner_name, {}).get("faction") if not Net.state.is_empty() else null
	_accent = WarInfo.faction_color(side).lightened(0.15) if side != null else CYAN
	_build_bridge()
	_build_corridors()
	_build_command_deck()
	_build_lounge()
	_build_hangar()
	Net.chat_received.connect(_on_chat)


func _exit_tree() -> void:
	if Net.chat_received.is_connected(_on_chat):
		Net.chat_received.disconnect(_on_chat)


# --- Shells: floors, ceilings and walls with holes in them ----------------------------------

## A room's floor and ceiling over x0..x1, z0..z1, standing on `y`, `h` tall, with light strips.
func _floor_ceiling(x0: float, x1: float, z0: float, z1: float, y: float, h: float, lights := true) -> void:
	var c := Vector3((x0 + x1) / 2.0, y, (z0 + z1) / 2.0)
	var w := x1 - x0
	var d := z1 - z0
	_box(self, Vector3(w + 0.4, 0.2, d + 0.4), c + Vector3(0, -0.1, 0), DECK)
	_box(self, Vector3(w + 0.4, 0.2, d + 0.4), c + Vector3(0, h + 0.1, 0), HULL_PANEL)
	for z in range(int(z0) + 3, int(z1), 3):
		_box(self, Vector3(w - 0.4, 0.012, 0.05), Vector3(c.x, y + 0.006, z), DECK_DARK, false)
	if lights:
		for x in ([c.x] if w < 8.0 else [x0 + w * 0.25, x1 - w * 0.25]):
			# a dark housing with lit panels in it, so the ceiling reads as fittings, not one glaring bar
			_box(self, Vector3(0.6, 0.06, d - 1.0), Vector3(x, y + h - 0.03, c.z), DECK_DARK, false)
			var n := maxi(1, int((d - 1.0) / 3.0))
			var step := (d - 1.0) / n
			for k in n:
				_box(self, Vector3(0.36, 0.03, step - 0.9), Vector3(x, y + h - 0.075, z0 + 0.5 + step * (k + 0.5)), Color(0.78, 0.86, 0.95), false, 0.7)


## A wall across x (at z) from x0 to x1, with holes: [centre x, width, bottom, top, glass].
## A door is a hole from 0; a window has a sill and glass. Each hole gets a frame.
func _wall_x(z: float, x0: float, x1: float, y: float, h: float, holes := [], colour := HULL) -> void:
	_wall(false, z, x0, x1, y, h, holes, colour)


## A wall along z (at x) from z0 to z1, with holes as for _wall_x but centred on z.
func _wall_z(x: float, z0: float, z1: float, y: float, h: float, holes := [], colour := HULL) -> void:
	_wall(true, x, z0, z1, y, h, holes, colour)


func _wall(along_z: bool, at: float, from: float, to: float, y: float, h: float, holes: Array, colour: Color) -> void:
	var cursor := from
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for hole in sorted:
		var a: float = hole[0] - hole[1] / 2.0
		var b: float = hole[0] + hole[1] / 2.0
		_seg(along_z, at, cursor, a, y, y + h, colour)
		_seg(along_z, at, a, b, y, y + hole[2], colour)
		_seg(along_z, at, a, b, y + hole[3], y + h, colour)
		if hole.size() > 4 and hole[4]:
			_seg(along_z, at, a, b, y + hole[2], y + hole[3], GLASS, true, 0.0, 0.07, 0.06)
			# Mullions every 4 m, and a chunky frame.
			var n := int((b - a) / 4.0)
			for k in range(1, n + 1):
				var m := a + (b - a) * k / (n + 1)
				_seg(along_z, at, m - 0.12, m + 0.12, y + hole[2], y + hole[3], TRIM, false, 0.0, 1.0, 0.3)
			_seg(along_z, at, a - 0.2, b + 0.2, y + hole[2] - 0.15, y + hole[2] + 0.1, TRIM, false, 0.0, 1.0, 0.6)
			_seg(along_z, at, a - 0.2, b + 0.2, y + hole[3] - 0.1, y + hole[3] + 0.15, TRIM, false, 0.0, 1.0, 0.6)
		else:
			_seg(along_z, at, a - 0.25, a, y, y + hole[3], TRIM, false, 0.0, 1.0, 0.55)
			_seg(along_z, at, b, b + 0.25, y, y + hole[3], TRIM, false, 0.0, 1.0, 0.55)
			_seg(along_z, at, a - 0.25, b + 0.25, y + hole[3], y + hole[3] + 0.25, TRIM, false, 0.0, 1.0, 0.55)
			_seg(along_z, at, a - 0.08, a - 0.02, y + 0.1, y + hole[3] - 0.1, _accent, false, 3.0, 1.0, 0.6)
			_seg(along_z, at, b + 0.02, b + 0.08, y + 0.1, y + hole[3] - 0.1, _accent, false, 3.0, 1.0, 0.6)
		cursor = b
	_seg(along_z, at, cursor, to, y, y + h, colour)


## One piece of a wall: from a to b along it, y0 to y1 up it.
func _seg(along_z: bool, at: float, a: float, b: float, y0: float, y1: float, col: Color, solid := true, glow := 0.0, alpha := 1.0, thick := 0.4) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (a + b) / 2.0
	var size := Vector3(thick, y1 - y0, b - a) if along_z else Vector3(b - a, y1 - y0, thick)
	var pos := Vector3(at, (y0 + y1) / 2.0, mid) if along_z else Vector3(mid, (y0 + y1) / 2.0, at)
	_box(self, size, pos, col, solid, glow, alpha)


## Rib frames and a glowing strip along a wall's foot, every few metres, so long walls read as a ship.
func _ribs_z(x: float, z0: float, z1: float, y: float, h: float, inward: float, step := 4.0) -> void:
	var z := z0 + step / 2.0
	while z < z1:
		_box(self, Vector3(0.35, h, 0.5), Vector3(x + inward * 0.18, y + h / 2.0, z), HULL_PANEL, false)
		z += step
	_box(self, Vector3(0.05, 0.05, z1 - z0 - 0.6), Vector3(x + inward * 0.22, y + 0.15, (z0 + z1) / 2.0), _accent, false, 2.0)


# --- Bridge ----------------------------------------------------------------------------------

func _build_bridge() -> void:
	var x0 := -13.0
	var x1 := 13.0
	var z0 := -62.0
	var z1 := -42.0
	var h := 6.5
	_floor_ceiling(x0, x1, z0, z1, 0.0, h)
	_wall_x(z0, x0, x1, 0.0, h, [[0.0, 24.0, 1.0, 5.8, true]])
	_wall_x(z1, x0, x1, 0.0, h, [[0.0, 3.2, 0.0, 3.2]])
	for s in [-1, 1]:
		_wall_z(s * 13.0, z0, z1, 0.0, h, [[-57.5, 8.0, 1.2, 5.0, true]])
		_ribs_z(s * 13.0, -52.0, z1, 0.0, h, -s)
	_sign(self, "BRIDGE", Vector3(0, 4.3, z1 + 0.25), Vector3.BACK, 64)
	# The pilot's chair, raised on a dais in the middle, facing the window.
	_cyl(self, 2.4, 0.4, Vector3(0, 0.2, -55.0), TRIM)
	_ring_line(self, 2.3, Vector3(0, 0.41, -55.0), _accent, 0.08, 2.5)
	var chair := Node3D.new()
	chair.position = Vector3(0, 0.4, -55.0)
	add_child(chair)
	_cyl(chair, 0.18, 0.45, Vector3(0, 0.22, 0), TRIM, false)
	_box(chair, Vector3(0.8, 0.16, 0.8), Vector3(0, 0.52, 0), Color(0.18, 0.2, 0.23), false)
	_box(chair, Vector3(0.7, 0.1, 0.65), Vector3(0, 0.63, 0.02), CUSHION.darkened(0.3), false)
	_box(chair, Vector3(0.75, 1.1, 0.14), Vector3(0, 1.15, 0.38), Color(0.18, 0.2, 0.23), false, 0.0, 1.0, Vector3(-8, 0, 0))
	_box(chair, Vector3(0.6, 0.9, 0.06), Vector3(0, 1.15, 0.3), CUSHION.darkened(0.3), false, 0.0, 1.0, Vector3(-8, 0, 0))
	for s in [-1, 1]:
		_box(chair, Vector3(0.14, 0.12, 0.7), Vector3(s * 0.46, 0.85, -0.05), TRIM, false)
		_box(chair, Vector3(0.24, 0.06, 0.32), Vector3(s * 0.5, 0.92, -0.25), Color(0.05, 0.12, 0.14), false, 1.0)
		_box(chair, Vector3(0.05, 0.03, 0.2), Vector3(s * 0.5, 0.96, -0.25), _accent, false, 3.0)
	# A flight console in front of the chair, low enough to see over.
	_box(chair, Vector3(1.6, 0.7, 0.4), Vector3(0, 0.35, -1.2), PANEL)
	_box(chair, Vector3(1.7, 0.06, 0.6), Vector3(0, 0.74, -1.15), TRIM, false, 0.0, 1.0, Vector3(14, 0, 0))
	_boards.helm = _text(chair, "", Vector3(0, 0.79, -1.1), Vector3(0, 1, 0.25).normalized(), 22, SCREEN_TEXT)
	_chair_eye = Marker3D.new()
	_chair_eye.position = Vector3(0, 0.4 + 1.3, -55.1)
	_chair_eye.rotation_degrees.x = -4.0
	add_child(_chair_eye)
	_chair_stand = Marker3D.new()
	_chair_stand.position = Vector3(0, 0.45, -53.6)
	_chair_stand.rotation_degrees.y = 180.0 # +Z of the marker is the way you face: the window
	add_child(_chair_stand)
	_arrival = _chair_stand
	_use(self, Vector3(0, 1.0, -54.6), _chair_prompt, func(): seated_down.emit())
	# Side consoles along the walls, facing in, and a crew pit on each side.
	var stations := [["HELM", "Heading hold\nThrusters nominal"], ["NAVIGATION", "Phase-shift drive\nready"], ["SENSORS", "Long range: clear"],
		["WEAPONS", "Turrets safe\nPoint defence on"], ["COMMS", "Fleet channel open"], ["ENGINEERING", "Reactor 94%\nShields holding"]]
	for i in 6:
		var s := -1.0 if i < 3 else 1.0
		var z := -58.5 + (i % 3) * 3.4
		var b := _console(self, Vector3(s * 11.6, 0, z), Vector3(-s, 0, 0), stations[i][0], stations[i][1], 2.2)
		if i == 2:
			_boards.sensors = b
		if i == 4:
			_boards.comms = b
			if mine:
				b.text = "Fleet channel open\nVisitors: %s" % ("welcome" if open_to_visitors else "not allowed")
				_use(self, Vector3(s * 10.6, 1.0, z), _comms_prompt, _toggle_visitors)
	if mine and not open_to_visitors:
		Net.send({"type": "ship_open", "open": false})
	for s in [-1, 1]:
		_box(self, Vector3(4.0, 0.06, 7.0), Vector3(s * 7.0, 0.02, -51.0), DECK_DARK, false)
		_box(self, Vector3(4.2, 0.03, 0.08), Vector3(s * 7.0, 0.05, -47.4), HAZARD, false, 0.5)
	# The star map table behind the chair.
	_box(self, Vector3(3.2, 0.95, 1.8), Vector3(0, 0.47, -46.5), PANEL)
	_box(self, Vector3(3.0, 0.04, 1.6), Vector3(0, 0.96, -46.5), Color(0.05, 0.12, 0.16), false, 1.2)
	_boards.starmap = _text(self, "", Vector3(0, 0.99, -46.5), Vector3.UP, 26, SCREEN_TEXT)
	_boards.starmap.rotate_y(PI)
	_screen(self, Vector3(-6.0, 5.4, -61.7), Vector3.BACK, Vector2(3.0, 0.8), "", "", 20, 18)
	_boards.berth = _screen(self, Vector3(0, 6.15, -61.7), Vector3.BACK, Vector2(9.0, 0.55), "", "", 30, 24)
	for x in [-8.0, 0.0, 8.0]:
		_light(self, Vector3(x, h - 0.6, -50.0), Color(0.8, 0.88, 1.0), 1.2, 12.0)
		_light(self, Vector3(x, h - 0.8, -58.5), Color(0.8, 0.88, 1.0), 0.8, 9.0)
	_light(self, Vector3(0, 2.5, -56.0), _accent, 0.5, 6.0)


# --- Corridors and the lift ------------------------------------------------------------------

func _build_corridors() -> void:
	var h := 3.6
	# Bridge to Command Deck.
	_floor_ceiling(-2.0, 2.0, -42.0, -36.0, 0.0, h)
	_wall_z(-2.0, -42.0, -36.0, 0.0, h)
	_wall_z(2.0, -42.0, -36.0, 0.0, h)
	# The main corridor, Command Deck to the Crew Lounge, with the lift lobby to starboard.
	_floor_ceiling(-2.0, 2.0, -14.0, 4.0, 0.0, h)
	_wall_z(-2.0, -14.0, 4.0, 0.0, h)
	_wall_z(2.0, -14.0, 4.0, 0.0, h, [[-10.0, 4.6, 0.0, 3.2]])
	for z in [-12.0, -4.0, 1.0]:
		for s in [-1, 1]:
			_box(self, Vector3(0.3, h, 0.4), Vector3(s * 1.82, h / 2.0, z), HULL_PANEL, false)
	_box(self, Vector3(0.05, 0.05, 17.0), Vector3(-1.76, 0.15, -5.0), _accent, false, 2.0)
	_sign(self, "LIFT · HANGAR DECK  >", Vector3(-1.75, 2.7, -10.0), Vector3.RIGHT, 40)
	_sign(self, "< BRIDGE · COMMAND", Vector3(1.75, 2.7, -3.0), Vector3.LEFT, 36)
	_sign(self, "CREW LOUNGE >", Vector3(-1.75, 2.7, -3.0), Vector3.RIGHT, 36)
	_light(self, Vector3(0, h - 0.5, -8.0), Color(0.85, 0.92, 1.0), 0.8, 8.0)
	_light(self, Vector3(0, h - 0.5, 1.0), Color(0.85, 0.92, 1.0), 0.8, 8.0)
	_light(self, Vector3(0, h - 0.5, -39.0), Color(0.85, 0.92, 1.0), 0.8, 7.0)
	# The lift lobby and its cab door.
	_floor_ceiling(2.0, 6.6, -12.3, -7.7, 0.0, 3.3, false)
	_wall_x(-12.3, 2.0, 6.6, 0.0, 3.3)
	_wall_x(-7.7, 2.0, 6.6, 0.0, 3.3)
	_wall_z(6.6, -12.3, -7.7, 0.0, 3.3)
	_lift_doors(Vector3(6.35, 0.0, -10.0), Vector3.LEFT, "HANGAR DECK")
	_lift_top = Marker3D.new()
	_lift_top.position = Vector3(4.6, 0.05, -10.0)
	_lift_top.rotation_degrees.y = -90.0 # facing -X, back into the corridor
	add_child(_lift_top)
	_use(self, Vector3(5.6, 1.0, -10.0), func(): return "Press %s to take the lift down to the Hangar Deck" % _key(), func(): _ride_lift(false))
	_light(self, Vector3(4.3, 2.8, -10.0), Color(1.0, 0.9, 0.7), 0.8, 5.0)


## The lift's doors on a wall: a frame, two closed leaves and a call panel.
func _lift_doors(pos: Vector3, facing: Vector3, label: String) -> void:
	var d := Node3D.new()
	d.position = pos
	d.basis = _facing_basis(facing)
	add_child(d)
	_box(d, Vector3(2.4, 2.9, 0.1), Vector3(0, 1.45, 0.02), TRIM, false)
	for s in [-1, 1]:
		_box(d, Vector3(1.0, 2.6, 0.06), Vector3(s * 0.52, 1.3, 0.08), Color(0.5, 0.53, 0.57), false)
	_box(d, Vector3(0.04, 2.6, 0.08), Vector3(0, 1.3, 0.1), _accent, false, 2.5)
	_box(d, Vector3(0.3, 0.45, 0.06), Vector3(1.6, 1.3, 0.05), Color(0.05, 0.12, 0.14), false, 1.0)
	_text(d, "LIFT\n" + label, Vector3(0, 3.2, 0.08), Vector3.BACK, 32, SCREEN_TEXT)


## Up or down in the lift: a short ride, then you step out on the other level.
func _ride_lift(up: bool) -> void:
	_stand_at(_lift_top if up else _lift_bottom)
	_pitch = 0.0
	_camera.rotation.x = 0.0
	_say("Command level: Bridge, Command Deck, Crew Lounge" if up else "Hangar Deck", 2.5)


# --- Command Deck ----------------------------------------------------------------------------

func _build_command_deck() -> void:
	var x0 := -12.0
	var x1 := 12.0
	var z0 := -36.0
	var z1 := -14.0
	var h := 6.0
	_floor_ceiling(x0, x1, z0, z1, 0.0, h)
	_wall_x(z0, x0, x1, 0.0, h, [[0.0, 3.2, 0.0, 3.2]])
	_wall_x(z1, x0, x1, 0.0, h, [[0.0, 3.2, 0.0, 3.2]])
	_wall_z(x0, z0, z1, 0.0, h, [[-29.0, 9.0, 1.2, 4.8, true]])
	_wall_z(x1, z0, z1, 0.0, h)
	_ribs_z(x1, z0, z1, 0.0, h, -1.0)
	_sign(self, "COMMAND DECK", Vector3(0, 4.2, z0 + 0.25), Vector3.BACK, 64)
	_sign(self, "COMMAND DECK", Vector3(0, 4.2, z1 - 0.25), Vector3.FORWARD, 56)
	# The holo table: a round table with a glowing top, the planet below floating over it.
	var c := Vector3(0, 0, -25.0)
	_cyl(self, 3.2, 0.3, c + Vector3(0, 0.15, 0), TRIM)
	_cyl(self, 2.7, 0.75, c + Vector3(0, 0.67, 0), PANEL)
	_cyl(self, 2.9, 0.12, c + Vector3(0, 1.1, 0), TRIM, true)
	_cyl(self, 2.5, 0.03, c + Vector3(0, 1.17, 0), Color(0.12, 0.32, 0.5), false, 0.9) # the projector glass, lit but not glaring
	_ring_line(self, 2.8, c + Vector3(0, 1.17, 0), _accent, 0.1, 1.6)
	var beam := _cyl(self, 1.9, 1.2, c + Vector3(0, 1.8, 0), Color(0.4, 0.75, 1.0), false, 1.5, 2.2)
	(beam as MeshInstance3D).mesh.material = _mat(Color(0.4, 0.75, 1.0), 1.5, 0.1)
	(beam as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo = Node3D.new()
	_holo.position = c + Vector3(0, 3.1, 0)
	add_child(_holo)
	_holo_markers = Node3D.new()
	_holo.add_child(_holo_markers)
	_boards.holo_title = _text(self, "", c + Vector3(0, 5.1, 0), Vector3.BACK, 44, SCREEN_TEXT)
	_boards.holo_title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_light(self, c + Vector3(0, 3.2, 0), Color(0.45, 0.7, 1.0), 1.6, 9.0)
	for k in 4:
		var a := k * TAU / 4.0
		_use(self, c + Vector3(cos(a), 0, sin(a)) * 2.7 + Vector3(0, 1.0, 0), _holo_prompt, _open_battles)
	# Tactical stations round the table, clear of the way through.
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var at := c + Vector3(cos(a), 0, sin(a)) * 6.8
		_console(self, at, (c - at).normalized(), ["TACTICAL", "FLEET", "DRONE CONTROL", "GALAXY MAP"][k], ["Sectors below", "Carrier group", "Drones ready", "FTL jump ready"][k], 1.6)
		if k == 3:
			# The galaxy map: jump the carrier to any system or planet (explorer.gd, jump_panel.gd).
			_use(self, at + (c - at).normalized() * 1.2 + Vector3(0, 1.0, 0), _jump_prompt, func(): service.emit("jump"))
	# The war log on the starboard wall, the planet below to port beside the window.
	_boards.war_log = _screen(self, Vector3(x1 - 0.5, 3.2, -25.0), Vector3.LEFT, Vector2(12.0, 4.0), "WAR LOG", "", 60, 40, ALERT) # in front of the ribs
	_boards.below = _screen(self, Vector3(x0 + 0.25, 3.0, -19.0), Vector3.RIGHT, Vector2(4.8, 3.2), "PLANET BELOW", "", 40, 24)
	_text(self, "VIEW PORT", Vector3(x0 + 0.26, 5.2, -29.0), Vector3.RIGHT, 36, SCREEN_TEXT)
	for x in [-6.0, 6.0]:
		_light(self, Vector3(x, h - 0.6, -30.0), Color(0.8, 0.88, 1.0), 0.8, 12.0)
		_light(self, Vector3(x, h - 0.6, -19.0), Color(0.8, 0.88, 1.0), 0.8, 12.0)


# --- Crew Lounge -----------------------------------------------------------------------------

func _build_lounge() -> void:
	var x0 := -11.0
	var x1 := 11.0
	var z0 := 4.0
	var z1 := 24.0
	var h := 4.5
	_floor_ceiling(x0, x1, z0, z1, 0.0, h)
	_wall_x(z0, x0, x1, 0.0, h, [[0.0, 3.2, 0.0, 3.2]])
	_wall_x(z1, x0, x1, 0.0, h)
	_wall_z(x0, z0, z1, 0.0, h, [[14.0, 12.0, 0.9, 3.7, true]])
	_wall_z(x1, z0, z1, 0.0, h)
	_sign(self, "CREW LOUNGE", Vector3(0, 3.7, z0 + 0.25), Vector3.BACK, 60)
	# Carpet, and soft light.
	_box(self, Vector3(12.0, 0.02, 14.0), Vector3(-3.0, 0.012, 14.0), Color(0.36, 0.3, 0.32), false)
	_box(self, Vector3(12.2, 0.025, 0.08), Vector3(-3.0, 0.014, 7.0), _accent, false, 1.5)
	# The bar along the starboard wall, its shelf of bottles, and stools.
	var bx := 7.6
	_box(self, Vector3(1.1, 1.1, 11.0), Vector3(bx, 0.55, 14.0), PANEL)
	_box(self, Vector3(1.3, 0.1, 11.2), Vector3(bx, 1.15, 14.0), TRIM, false)
	_box(self, Vector3(0.04, 0.05, 11.0), Vector3(bx - 0.66, 1.08, 14.0), _accent, false, 3.0)
	for y in [1.4, 2.1]:
		_box(self, Vector3(0.5, 0.06, 8.0), Vector3(x1 - 0.5, y, 14.0), TRIM)
		for i in 18:
			_cyl(self, 0.07, 0.36, Vector3(x1 - 0.5, y + 0.21, 10.6 + i * 0.4), [Color(0.55, 0.35, 0.15), Color(0.2, 0.45, 0.3), Color(0.6, 0.6, 0.65)][i % 3], false, 0.4)
	_sign(self, "THE HANGAR BAR", Vector3(x1 - 0.3, 3.3, 14.0), Vector3.LEFT, 56)
	for z in range(10, 20, 2):
		var stool := Vector3(bx - 1.2, 0, z)
		_seat(self, stool)
		_use(self, stool + Vector3(0, 1.0, 0), func(): return "Press %s to sit at the bar" % _key(), sit_on.bind(stool + Vector3(0, 0.3, 0), -PI / 2.0))
	_light(self, Vector3(bx, 2.6, 14.0), _accent.lerp(Color(1, 0.8, 0.5), 0.5), 1.0, 8.0)
	# Sofas by the window, facing in, and low tables.
	for z in [9.5, 14.0, 18.5]:
		_bench(self, Vector3(x0 + 1.0, 0, z), Vector3.RIGHT, 3.2)
		_use(self, Vector3(x0 + 1.4, 1.0, z), func(): return "Press %s to sit down" % _key(), sit_on.bind(Vector3(x0 + 1.05, 0.0, z), -PI / 2.0))
		_cyl(self, 0.6, 0.45, Vector3(x0 + 2.8, 0.22, z), PANEL)
		_ring_line(self, 0.58, Vector3(x0 + 2.8, 0.45, z), _accent, 0.03, 2.0)
	for t: Vector3 in [Vector3(-1.0, 0, 10.5), Vector3(0.5, 0, 17.5)]:
		_cyl(self, 0.12, 0.9, t + Vector3(0, 0.45, 0), TRIM, false)
		_cyl(self, 0.85, 0.08, t + Vector3(0, 0.9, 0), PANEL, true)
		for k in 3:
			var a := k * TAU / 3.0 + 0.5
			var p := t + Vector3(cos(a) * 1.3, 0, sin(a) * 1.3)
			_seat(self, p, 0.5)
			var face := atan2(-(t - p).x, -(t - p).z)
			_use(self, p + Vector3(0, 0.8, 0), func(): return "Press %s to sit down" % _key(), sit_on.bind(p, face))
	_planter(self, Vector3(x0 + 0.8, 0, 5.3))
	_planter(self, Vector3(x0 + 0.8, 0, 22.7))
	# Who's aboard, and the crew channel, on the aft wall.
	_boards.aboard = _screen(self, Vector3(-4.0, 2.4, z1 - 0.25), Vector3.FORWARD, Vector2(6.0, 2.8), "ABOARD", "", 50, 30)
	_boards.chat = _screen(self, Vector3(4.2, 2.4, z1 - 0.25), Vector3.FORWARD, Vector2(5.0, 2.8), "CHANNEL: PILOTS", "", 44, 24)
	_use(self, Vector3(4.2, 1.0, z1 - 1.2), func(): return "Press %s to talk on the pilots' channel" % _chat_key(), func(): _chat.open())
	for z in [8.0, 18.0]:
		_light(self, Vector3(-4.0, h - 0.5, z), Color(1.0, 0.88, 0.72), 0.9, 10.0)


# --- Hangar Deck -----------------------------------------------------------------------------

func _build_hangar() -> void:
	var x0 := -20.0
	var x1 := 20.0
	var z0 := -16.0
	var z1 := 46.0
	var y := HANGAR_Y
	var h := HANGAR_H
	_floor_ceiling(x0, x1, z0, z1, y, h, false)
	_wall_x(z0, x0, x1, y, h, [[4.3, 4.6, 0.0, 3.2]])
	_wall_z(x0, z0, z1, y, h, [[8.0, 3.4, 0.0, 3.6]])
	_wall_z(x1, z0, z1, y, h)
	_ribs_z(x0, z0, 6.0, y, h, 1.0, 6.0)
	_ribs_z(x0, 10.0, z1, y, h, 1.0, 6.0)
	_ribs_z(x1, z0, z1, y, h, -1.0, 6.0)
	# The launch doors at the stern: open, behind a pressure shield you can see space through.
	_wall_x(z1, x0, x1, y, h, [[0.0, 30.0, 0.0, 11.0]])
	_box(self, Vector3(30.0, 11.0, 0.06), Vector3(0, y + 5.5, z1), Color(0.3, 0.6, 1.0), true, 0.6, 0.08)
	for s in [-1, 1]:
		_box(self, Vector3(2.5, 11.0, 1.2), Vector3(s * 13.75, y + 5.5, z1 - 0.8), Color(0.42, 0.44, 0.48), false)
		for k in 6:
			_box(self, Vector3(0.6, 0.6, 0.05), Vector3(s * 12.4, y + 0.8 + k * 1.8, z1 - 1.45), HAZARD if k % 2 == 0 else Color(0.08, 0.08, 0.08), false, 0.3, 1.0, Vector3(0, 0, 45))
	_box(self, Vector3(31.0, 0.5, 1.4), Vector3(0, y + 11.25, z1 - 0.8), TRIM, false)
	_box(self, Vector3(29.0, 0.06, 0.06), Vector3(0, y + 10.8, z1 - 1.5), HAZARD, false, 3.0)
	_sign(self, "LAUNCH BAY · DOORS OPEN", Vector3(0, y + 12.4, z1 - 0.3), Vector3.FORWARD, 90, HAZARD)
	_sign(self, "HANGAR DECK · DRONE BAY", Vector3(-8.0, y + 6.5, z0 + 0.3), Vector3.BACK, 100)
	# Deck markings: the launch lane down the middle, bays for each craft.
	for z in range(-12, 44, 4):
		_box(self, Vector3(0.5, 0.015, 2.0), Vector3(0, y + 0.008, z), HAZARD, false, 0.3)
	for x in [-3.2, 3.2]:
		_box(self, Vector3(0.12, 0.015, 56.0), Vector3(x, y + 0.008, 16.0), Color(0.9, 0.9, 0.92), false, 0.2)
	# Gantry rails and cranes overhead, lamps hung under them.
	for x in [-11.0, 11.0]:
		_box(self, Vector3(0.6, 0.8, z1 - z0), Vector3(x, y + h - 1.2, (z0 + z1) / 2.0), TRIM, false)
		for z in [0.0, 22.0]:
			_box(self, Vector3(4.0, 0.6, 1.0), Vector3(x, y + h - 1.9, z), Color(0.5, 0.42, 0.18), false)
			_box(self, Vector3(0.08, 3.0, 0.08), Vector3(x, y + h - 3.6, z), TRIM, false)
	for z in [-6.0, 8.0, 22.0, 36.0]:
		for x in [-11.0, 0.0, 11.0]:
			_box(self, Vector3(2.4, 0.06, 0.5), Vector3(x, y + h - 0.05, z), Color(0.95, 0.97, 1.0), false, 2.2)
		_light(self, Vector3(-9.0, y + h - 2.0, z), Color(0.85, 0.92, 1.0), 1.4, 20.0)
		_light(self, Vector3(9.0, y + h - 2.0, z), Color(0.85, 0.92, 1.0), 1.4, 20.0)
	# The craft: tanks to port, strikers and gunships to starboard, two landers by the doors.
	for z in [-9.0, -1.5, 17.0]:
		_bay(Vector3(-12.0, y, z), Vector2(6.0, 7.0))
		_tank(Vector3(-12.0, y, z), 90.0)
	for z in [-10.0, -5.5, -1.0, 3.5]:
		_bay(Vector3(12.5, y, z), Vector2(4.0, 4.0))
		_striker(Vector3(12.5, y, z), -90.0)
	for z in [13.0, 23.0]:
		_bay(Vector3(12.0, y, z), Vector2(9.0, 8.0))
		_gunship(Vector3(12.0, y, z), -90.0)
	for z in [28.0, 39.0]:
		_bay(Vector3(-11.0, y, z), Vector2(10.0, 10.0))
		_lander(Vector3(-11.0, y, z), 90.0)
	# Crates, fuel lines along the starboard wall, and the hangar console.
	for k in 4:
		_crate(self, Vector3(1.6, 1.2, 1.2), Vector3(16.0 + (k % 2) * 1.8, y, 30.0 + (k / 2) * 1.6), "MUNITIONS" if k == 0 else "")
	_crate(self, Vector3(1.4, 1.0, 1.2), Vector3(16.9, y + 1.2, 30.8))
	for k in 3:
		_cyl(self, 0.22, z1 - z0 - 4.0, Vector3(x1 - 0.5, y + 2.0 + k * 0.6, 15.0), [HAZARD, Color(0.3, 0.55, 0.8), Color(0.6, 0.2, 0.18)][k], false).rotation_degrees.x = 90.0
	_console(self, Vector3(-5.0, y, -12.0), Vector3.BACK, "HANGAR CONTROL", "Doors: OPEN\nShield: holding\nDrones: 11 ready", 2.2)
	# The lift cab, in the forward wall.
	_floor_ceiling(2.0, 6.6, -20.6, -16.0, y, 3.3, false)
	_wall_x(-20.6, 2.0, 6.6, y, 3.3)
	_wall_z(2.0, -20.6, -16.0, y, 3.3)
	_wall_z(6.6, -20.6, -16.0, y, 3.3)
	_lift_doors(Vector3(4.3, y, -20.35), Vector3.BACK, "COMMAND LEVEL")
	_sign(self, "LIFT · COMMAND LEVEL", Vector3(4.3, y + 4.2, -15.7), Vector3.BACK, 44)
	_lift_bottom = Marker3D.new()
	_lift_bottom.position = Vector3(4.3, y + 0.05, -18.4)
	add_child(_lift_bottom) # facing +Z, out into the hangar
	_use(self, Vector3(4.3, y + 1.0, -19.6), func(): return "Press %s to take the lift up to the Bridge and Command Deck" % _key(), func(): _ride_lift(true))
	_light(self, Vector3(4.3, y + 2.8, -18.4), Color(1.0, 0.9, 0.7), 0.8, 5.0)
	_build_airlock(y)


## The airlock to port: through its inner door into a short chamber; docked at a station, walking
## to the outer door takes you into the station. In open space the outer door stays sealed.
func _build_airlock(y: float) -> void:
	var z := 8.0
	_floor_ceiling(-24.6, -20.0, z - 1.7, z + 1.7, y, 3.6, false)
	_wall_x(z - 1.7, -24.6, -20.0, y, 3.6)
	_wall_x(z + 1.7, -24.6, -20.0, y, 3.6)
	_box(self, Vector3(0.4, 3.6, 3.4), Vector3(-24.6, y + 1.8, z), HULL)
	_box(self, Vector3(0.1, 3.0, 2.4), Vector3(-24.35, y + 1.5, z), Color(0.5, 0.53, 0.57), false)
	_box(self, Vector3(0.12, 0.08, 2.6), Vector3(-24.3, y + 3.05, z), HAZARD, false, 2.5)
	_box(self, Vector3(0.12, 3.0, 0.08), Vector3(-24.3, y + 1.5, z - 1.25), HAZARD, false, 2.5)
	_box(self, Vector3(0.12, 3.0, 0.08), Vector3(-24.3, y + 1.5, z + 1.25), HAZARD, false, 2.5)
	_light(self, Vector3(-22.3, y + 3.0, z), Color(1.0, 0.8, 0.5), 0.9, 5.0)
	_sign(self, "AIRLOCK · STATION", Vector3(-19.7, y + 4.3, z), Vector3.RIGHT, 56, HAZARD)
	_boards.airlock = _screen(self, Vector3(-19.75, y + 2.0, z + 3.2), Vector3.RIGHT, Vector2(2.4, 1.4), "AIRLOCK", "", 32, 22)
	_airlock_in = Marker3D.new()
	_airlock_in.position = Vector3(-18.6, y + 0.05, z)
	_airlock_in.rotation_degrees.y = 90.0 # facing +X, into the hangar
	add_child(_airlock_in)
	# Aboard someone else's carrier: the shuttle back to your own.
	if not mine:
		var at := Vector3(-17.0, y, 15.0)
		_console(self, at, Vector3.RIGHT, "SHUTTLE", "To your own\ncarrier.\nPress F.", 1.6)
		_use(self, at + Vector3(0.7, 1.0, 0), func(): return "Press %s to take the shuttle back to your own carrier" % _key(), func(): wants_space.emit("ship:" + Net.my_name))


## Painted lines on the deck round a craft's bay.
func _bay(at: Vector3, size: Vector2) -> void:
	for s in [-1, 1]:
		_box(self, Vector3(size.x, 0.015, 0.12), at + Vector3(0, 0.009, s * size.y / 2.0), HAZARD, false, 0.4)
		_box(self, Vector3(0.12, 0.015, size.y), at + Vector3(s * size.x / 2.0, 0.009, 0), HAZARD, false, 0.4)


## A craft on the deck: a frame at `at`, turned `yaw` degrees, with one solid box to bump into.
func _craft(at: Vector3, yaw: float, footprint: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation_degrees.y = yaw
	add_child(n)
	_box(n, footprint, Vector3(0, footprint.y / 2.0, 0), Color(0, 0, 0), true, 0.0, 0.0)
	return n


## A drone tank: tracks, a hull with a stripe in the owner's colours, a turret and a long gun.
func _tank(at: Vector3, yaw: float) -> void:
	var n := _craft(at, yaw, Vector3(3.8, 2.2, 5.6))
	var armour := Color(0.42, 0.45, 0.48)
	for s in [-1, 1]:
		_box(n, Vector3(1.0, 1.1, 5.8), Vector3(s * 1.7, 0.55, 0), Color(0.12, 0.12, 0.14), false)
		for k in 5:
			_cyl(n, 0.42, 0.9, Vector3(s * 1.7, 0.5, -2.2 + k * 1.1), TRIM, false).rotation_degrees.z = 90.0
	_box(n, Vector3(2.6, 0.9, 5.0), Vector3(0, 1.4, 0), armour, false)
	_box(n, Vector3(2.62, 0.18, 1.2), Vector3(0, 1.6, 1.4), _accent, false, 0.6)
	_box(n, Vector3(2.0, 0.8, 2.2), Vector3(0, 2.25, 0.3), armour.lightened(0.1), false)
	_box(n, Vector3(0.32, 0.32, 3.4), Vector3(0, 2.3, -2.4), TRIM, false)
	_box(n, Vector3(0.3, 0.12, 0.3), Vector3(0.6, 2.72, 0.8), Color(0.3, 0.9, 1.0), false, 2.0)


## A striker: a light two-legged assault bot with guns for arms.
func _striker(at: Vector3, yaw: float) -> void:
	var n := _craft(at, yaw, Vector3(2.2, 3.2, 1.8))
	var armour := Color(0.46, 0.48, 0.52)
	for s in [-1, 1]:
		_box(n, Vector3(0.45, 1.5, 0.55), Vector3(s * 0.5, 0.75, 0.1), TRIM, false, 0.0, 1.0, Vector3(-8, 0, 0))
		_box(n, Vector3(0.6, 0.2, 0.9), Vector3(s * 0.5, 0.1, -0.05), Color(0.12, 0.12, 0.14), false)
		_box(n, Vector3(0.4, 0.4, 1.6), Vector3(s * 1.05, 2.25, -0.5), Color(0.2, 0.21, 0.24), false)
		_box(n, Vector3(0.18, 0.18, 0.5), Vector3(s * 1.05, 2.25, -1.5), TRIM, false)
	_box(n, Vector3(1.2, 0.5, 0.9), Vector3(0, 1.6, 0), TRIM, false)
	_box(n, Vector3(1.7, 1.1, 1.3), Vector3(0, 2.4, 0), armour, false)
	_box(n, Vector3(1.72, 0.2, 1.32), Vector3(0, 2.55, 0), _accent, false, 0.6)
	_box(n, Vector3(0.6, 0.4, 0.5), Vector3(0, 3.1, -0.2), armour.darkened(0.2), false)
	_box(n, Vector3(0.45, 0.1, 0.06), Vector3(0, 3.12, -0.47), Color(1.0, 0.35, 0.3), false, 2.5)


## A gunship on its skids: a fuselage with a canopy, stub wings and a ducted fan at each tip.
func _gunship(at: Vector3, yaw: float) -> void:
	var n := _craft(at, yaw, Vector3(8.0, 3.0, 7.4))
	var armour := Color(0.4, 0.43, 0.47)
	for s in [-1, 1]:
		_box(n, Vector3(0.12, 0.12, 4.0), Vector3(s * 1.0, 0.1, 0), TRIM, false)
		_box(n, Vector3(0.1, 0.8, 0.1), Vector3(s * 1.0, 0.5, -1.2), TRIM, false)
		_box(n, Vector3(0.1, 0.8, 0.1), Vector3(s * 1.0, 0.5, 1.2), TRIM, false)
		_box(n, Vector3(2.8, 0.25, 1.6), Vector3(s * 2.4, 1.8, 0.3), armour, false)
		_cyl(n, 1.15, 0.7, Vector3(s * 3.8, 1.85, 0.3), TRIM, false)
		_cyl(n, 0.95, 0.06, Vector3(s * 3.8, 2.22, 0.3), Color(0.15, 0.16, 0.18), false)
		_box(n, Vector3(0.24, 0.24, 1.6), Vector3(s * 1.5, 1.4, -1.6), Color(0.2, 0.21, 0.24), false)
	_box(n, Vector3(2.0, 1.5, 6.4), Vector3(0, 1.75, 0), armour, false)
	_box(n, Vector3(2.02, 0.22, 2.0), Vector3(0, 2.2, 1.6), _accent, false, 0.6)
	_box(n, Vector3(1.6, 0.8, 1.6), Vector3(0, 2.5, -1.9), Color(0.35, 0.8, 0.95), false, 0.6)
	_box(n, Vector3(0.2, 1.2, 1.4), Vector3(0, 2.9, 2.6), armour, false)


## A lander: the boxy dropship that carries drones down, its rear ramp down on the deck.
func _lander(at: Vector3, yaw: float) -> void:
	var n := _craft(at, yaw, Vector3(7.4, 5.4, 12.0))
	var armour := Color(0.44, 0.46, 0.5)
	for x in [-2.8, 2.8]:
		for z in [-4.0, 4.0]:
			_box(n, Vector3(0.3, 1.2, 0.3), Vector3(x, 0.6, z), TRIM, false)
			_box(n, Vector3(0.9, 0.12, 0.9), Vector3(x, 0.06, z), TRIM, false)
	_box(n, Vector3(6.4, 3.6, 10.0), Vector3(0, 3.0, 0), armour, false)
	_box(n, Vector3(4.6, 2.0, 2.8), Vector3(0, 3.4, -6.2), armour.lightened(0.08), false)
	_box(n, Vector3(3.4, 0.7, 0.2), Vector3(0, 3.9, -7.6), Color(0.35, 0.8, 0.95), false, 0.6)
	_box(n, Vector3(6.42, 0.4, 10.02), Vector3(0, 4.0, 0), _accent, false, 0.6)
	for s in [-1, 1]:
		_box(n, Vector3(1.4, 1.6, 4.0), Vector3(s * 3.8, 3.6, 2.0), TRIM, false)
		_cyl(n, 0.6, 0.3, Vector3(s * 3.8, 3.6, 4.15), HAZARD, false, 2.0).rotation_degrees.x = 90.0
	var ramp := _box(n, Vector3(4.0, 0.15, 3.6), Vector3(0, 0.7, 6.6), Color(0.35, 0.37, 0.4), false)
	ramp.rotation_degrees.x = -20.0
	_text(n, "LANDER", Vector3(3.22, 3.1, 0), Vector3.RIGHT, 120, Color(0.9, 0.92, 0.95))


# --- Seats and standing -----------------------------------------------------------------------

## Sitting in the pilot's chair: looking out of the bridge window. Docked, that's where the ship's
## menu (undock) comes up; in open space the explorer flies from here.
func sit() -> void:
	seated = true
	_sitting = false
	if not _chair_eye:
		return
	_player.global_position = _chair_stand.global_position
	_player.velocity = Vector3.ZERO
	_camera.top_level = true
	_camera.global_transform = _chair_eye.global_transform
	if controls:
		controls.release_mouse()


## Where to stand when you arrive: "bridge" (beside the pilot's chair), "hangar" (inside the
## airlock, from a station or a boarding door) or "lift".
func arrive(at: String) -> void:
	if seated:
		stand()
	match at:
		"hangar":
			_stand_at(_airlock_in)
		"lift":
			_stand_at(_lift_bottom)
		_:
			_stand_at(_chair_stand)


func walker_pose() -> Dictionary:
	if seated:
		return {"pos": _chair_stand.global_position + Vector3(0, 0.0, -1.5), "yaw": 0.0, "anim": "sit"}
	return super()


## The pilot's chair, where the explorer seats you: for the others aboard it's a seated figure.
func chair_pose() -> Dictionary:
	return {"pos": _chair_stand.global_position + Vector3(0, 0.0, -1.5), "yaw": 0.0, "anim": "sit"}


func _fall_limit() -> float:
	return HANGAR_Y - 20.0


func _seated_text() -> String:
	return "%s · in the pilot's chair%s" % [place_name, (" · " + berth_text) if berth_text != "" else ""]


func _leave_hint() -> String:
	return "Sit in the pilot's chair on the Bridge to fly. Docked, the airlock on the Hangar Deck leads into the station."


func _chair_prompt() -> String:
	if not mine:
		return "%s's chair: only the captain flies this carrier" % owner_name
	if docked_at != "":
		return "Press %s to sit in the pilot's chair (undock from there)" % _key()
	return "Press %s to sit in the pilot's chair and fly" % _key()


func _comms_prompt() -> String:
	return "Press %s to %s your carrier to visitors (now %s)" % [_key(), "close" if open_to_visitors else "open", "open" if open_to_visitors else "closed"]


## The COMMS console: open or close your carrier to other pilots (those aboard stay aboard).
func _toggle_visitors() -> void:
	open_to_visitors = not open_to_visitors
	Net.send({"type": "ship_open", "open": open_to_visitors})
	_boards.comms.text = "Fleet channel open\nVisitors: %s" % ("welcome" if open_to_visitors else "not allowed")
	_say("Your carrier is %s to visitors." % ("open" if open_to_visitors else "closed"), 3.0)


func _jump_prompt() -> String:
	if not mine:
		return "Galaxy map: only %s can jump this carrier" % owner_name
	return "Galaxy map: press %s to jump the carrier to any system or planet" % _key()


func _holo_prompt() -> String:
	if over == "":
		return "Holo table: press %s for Sector Battles (fly to a contested world's orbit to fight)" % _key()
	return "Holo table: press %s for Sector Battles on %s" % [_key(), WarInfo.planet(over).get("name", over.capitalize())]


## The holo table's F: the Sector Battles screen (game/battle/battle_menu.gd) for the planet below.
## Until that screen is in the build, the War terminal stands in for it.
func _open_battles() -> void:
	if not _has_static(BATTLE_MENU, "open"):
		_say("Sector battles aren't in this build yet: here's the War terminal.")
		service.emit("war")
		return
	_battle_menu = load(BATTLE_MENU).open(self, over)
	if _battle_menu == null:
		_say("Sector Battles couldn't open. Re-import the project (see the README) and try again.")
		return
	set_menu_open(true)
	if _battle_menu.has_signal("closed"):
		_battle_menu.closed.connect(_battle_menu_closed, CONNECT_ONE_SHOT)


func _battle_menu_closed() -> void:
	_battle_menu = null
	await get_tree().process_frame
	if not battle_active() and is_inside_tree():
		set_menu_open(false)


static func _has_static(path: String, method: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var script = load(path)
	if not (script is Script):
		return false
	for m in script.get_script_method_list():
		if m.name == method:
			return true
	return false


# --- Every frame --------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	if _holo:
		_holo.rotate_y(0.15 * delta)
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 1.0
		_refresh_boards()
	_check_airlock(delta)


## Walking into the airlock chamber: through to the station when docked; sealed in open space.
func _check_airlock(delta: float) -> void:
	_airlock_wait -= delta
	if seated or _airlock_wait > 0.0:
		return
	var p := _player.global_position
	if p.y > HANGAR_Y + 2.0 or p.x > -22.6 or absf(p.z - 8.0) > 1.6:
		return
	_airlock_wait = 3.0
	var to := _airlock_station()
	if to == "":
		_say("The outer door is sealed: %s." % ("the carrier isn't docked" if mine else "%s's carrier isn't docked at a station" % owner_name), 3.0)
		_stand_at(_airlock_in)
		return
	wants_space.emit("station:" + to)


## The station the airlock opens onto: where this carrier is docked, or "".
func _airlock_station() -> String:
	return docked_at


## Which part of the ship you're in, for the HUD.
func _location() -> String:
	var p := _player.global_position
	if p.y < -6.0:
		return "Airlock" if p.x < -20.0 else "Hangar Deck"
	if p.x > 2.2 and p.z > -12.5 and p.z < -7.5:
		return "Lift"
	if p.z < -42.0:
		return "Bridge"
	if p.z < -36.0 or (p.z > -14.0 and p.z < 4.0):
		return "Corridor"
	if p.z < -14.0:
		return "Command Deck"
	return "Crew Lounge"


func _on_chat(sender: String, _role: String, text: String) -> void:
	_chat_lines.append("<%s> %s" % [sender, text])
	if _chat_lines.size() > 6:
		_chat_lines.pop_front()
	if _boards.has("chat"):
		_boards.chat.text = "\n".join(_chat_lines)


## The live screens: who's aboard, the war log, the planet below and its hologram, the berth.
func _refresh_boards() -> void:
	var crew := ["%s  · captain" % owner_name]
	if not mine:
		crew.append("%s  · you" % Net.my_name)
	if walkers:
		for w in walkers.people():
			if w.name != owner_name:
				crew.append("%s  · %s%s" % [w.name, WarInfo.faction_name(w.faction), "  (seated)" if w.anim == "sit" else ""])
	_boards.aboard.text = "\n".join(crew.slice(0, 9)) + ("\n...and %d more" % (crew.size() - 9) if crew.size() > 9 else "")
	if _chat_lines.is_empty():
		_boards.chat.text = "Nobody's said anything yet.\nPress %s to talk." % _chat_key()
	var log: Array = Net.state.get("war", {}).get("log", []) if not Net.state.is_empty() else []
	var lines := []
	for k in range(log.size() - 1, maxi(-1, log.size() - 8), -1):
		lines.append(str(log[k].get("text", "")))
	_boards.war_log.text = "\n".join(lines) if not lines.is_empty() else "No battles reported yet."
	var wp := WarInfo.planet(over) if over != "" else {}
	if wp.is_empty():
		_boards.below.text = "Open space.\nNo contested world below.\n\nFly to a contested world's\norbital station to fight\nfor its sectors."
	else:
		var lock := WarInfo.lock_left(wp)
		_boards.below.text = "%s\nHeld by %s\n%d of %d sectors theirs\n%s%s\n\nHolo table: Sector Battles" % [wp.name.to_upper(), WarInfo.faction_name(wp.owner),
			WarInfo.held(wp, wp.owner), wp.sectors.size(), WarInfo.contention(wp).capitalize(), ("\nLocked " + lock) if lock != "" else ""]
	if _holo_for != over:
		_holo_for = over
		_build_holo(wp)
	_boards.berth.text = berth_text.to_upper() if berth_text != "" else ("IN OPEN SPACE · HOLDING POSITION" if mine else "%s'S CARRIER" % owner_name.to_upper())
	_boards.helm.text = "DOCKED" if docked_at != "" else "HOLDING"
	_boards.starmap.text = "%s\n%s" % [str(Net.state.get("system", {}).get("name", "Teal Prime")).to_upper(), ("ORBIT: " + wp.name.to_upper()) if not wp.is_empty() else "DEEP SPACE"]
	var to := _airlock_station()
	_boards.airlock.text = ("OPEN\nTo %s" % _station_label(to)) if to != "" else "SEALED\nNot docked"


func _station_label(id: String) -> String:
	var wp := WarInfo.planet(id)
	if not wp.is_empty():
		return System.orbital_name(wp.name)
	return System.station_name(str(Net.planet(id).get("name", id.capitalize())))


## The hologram over the table: the planet below with its sectors in their owners' colours (the
## capital sector bigger), or the system's contested worlds when there's no planet below.
func _build_holo(wp: Dictionary) -> void:
	for child in _holo_markers.get_children():
		child.queue_free()
	var holo := StandardMaterial3D.new()
	holo.albedo_color = Color(0.4, 0.62, 0.85, 0.3)
	holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo.emission_enabled = true
	holo.emission = Color(0.35, 0.65, 1.0)
	holo.emission_energy_multiplier = 0.5
	holo.cull_mode = BaseMaterial3D.CULL_DISABLED
	if wp.is_empty():
		_boards.holo_title.text = "NO PLANET BELOW"
		var worlds := WarInfo.planets_in(str(Net.state.get("system", {}).get("id", "teal-prime"))) if not Net.state.is_empty() else []
		for i in worlds.size():
			var a := i * TAU / maxf(1.0, worlds.size())
			var dot := _holo_dot(Vector3(cos(a), 0, sin(a)) * 1.5, WarInfo.faction_color(worlds[i].owner), 0.18, 2.0)
			var tag := Label3D.new()
			tag.text = worlds[i].name
			tag.position = dot + Vector3(0, 0.35, 0)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.pixel_size = 0.004
			tag.font_size = 64
			tag.modulate = WarInfo.faction_color(worlds[i].owner).lightened(0.3)
			_holo_markers.add_child(tag)
		_holo_dot(Vector3.ZERO, Color(1.0, 0.85, 0.5), 0.3, 3.0)
		return
	_boards.holo_title.text = "%s · %s" % [wp.name.to_upper(), WarInfo.faction_name(wp.owner).to_upper()]
	var sphere := SphereMesh.new()
	sphere.radius = 1.45
	sphere.height = 2.9
	sphere.material = holo
	var g := MeshInstance3D.new()
	g.mesh = sphere
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # light, not matter
	_holo_markers.add_child(g)
	for sec in wp.get("sectors", []):
		var lat := deg_to_rad(float(sec.lat))
		var lon := deg_to_rad(float(sec.lon))
		var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * 1.48
		_holo_dot(p, WarInfo.faction_color(sec.owner), 0.13 if sec.get("capital", false) else 0.08, 2.0)


func _holo_dot(p: Vector3, colour: Color, radius: float, glow: float) -> Vector3:
	var dot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _mat(colour, glow)
	dot.mesh = mesh
	dot.position = p
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo_markers.add_child(dot)
	return p
