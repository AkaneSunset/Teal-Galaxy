extends "res://place.gd"
## The inside of a High Port, walked on foot in first person. Built in code from boxes, like the rest.
## Designed from Akane's concept art for the orbital station.
##
## Layout, seen from above: a ring-shaped Concourse lined with windows, wrapped around the
## Planetary Terminal Hall (the hologram of the planet below). Every compartment opens off the
## outside of the ring, one per slot:
##   0 Hangar and landing pads (you arrive here)   6 Cantina
##   (windows all round the ring between doors)   6 ... with the black market terminal in a corner
##                                                 7 a stretch of windows
##   2 Ship Services Dock                          8 Security Office
##   3 Supply Shop                                 9 Crew Cabins corridor
##   4 Commodity Exchange                         10 Observation Lounge
##   5 Planetary Builder Job Board                and benches facing the windows near 283 degrees
##
## The boards show live data: the planet's sites and raids, its jobs, the raid log and chat.
## You arrive seated in your ship on pad 06 in the Hangar (see place.gd). F uses things, Esc pauses.
##
## The same station orbits each contested world of the faction war as its orbital station
## ("Cinder Orbital"). Nobody's base is below one: its hologram shows the planet's sectors in their
## owners' colours and the outposts in them, tinted by faction (dim when dormant), and its Surface
## Transit consoles fly you to those outposts. Every station's Terminal Hall has two War
## terminals, and its Job Board a console for supply contracts.
##
## Stations are hubs: everyone in the same copy of a station (its 32 pads, see server/spaces.js)
## walks around in it together (walkers.gd). Pilots who fly fleet carriers (the demo) dock at
## berths outside the station instead of landing in the hangar: the hangar is then the Carrier Berth
## hall, with an airlock gate for your own carrier and boarding doors for the carriers docked in
## your copy ("Board Akane's carrier"), nine at a time (DOCK CONTROL shows the next nine). You
## arrive through your own gate and leave by it.

const R_IN := 21.6 # inner wall of the concourse ring (the Terminal Hall is inside it)
const R_OUT := 30.0 # outer wall of the ring, where compartments open
const RING_H := 5.0
const HALL_H := 7.5
const SEGMENTS := 120
const HALL_DOORS := [45.0, 135.0, 225.0, 315.0] # degrees

## The compartments: slot -> [name, width, depth, height]. Slot angle = slot * 30 degrees.
const ROOMS := {
	0: ["Hangar", 38.0, 44.0, 9.0],
	2: ["Ship Services Dock", 12.0, 11.0, 5.0],
	3: ["Supply Shop", 12.0, 11.0, 4.6],
	4: ["Commodity Exchange", 14.0, 12.0, 5.5],
	5: ["Job Board", 12.0, 10.0, 5.0],
	6: ["Cantina", 16.0, 14.0, 5.0],
	8: ["Security Office", 12.0, 10.0, 4.6],
	9: ["Crew Cabins", 4.4, 30.0, 3.6],
	10: ["Observation Lounge", 14.0, 12.0, 5.0],
}

var _station_name := ""
var _war := {} # the contested planet below an orbital station (g.war), or {} at a High Port
var _rooms := {} # slot -> room Node3D (origin at its door, +Z into the room)
var _globe: Node3D
var _globe_markers: Node3D
var _boards := {} # name -> Label3D, refreshed from the server state
var _chat_lines: Array[String] = []
var _price_time := 0.0

# Carrier berths (set by the explorer before the station is added).
var carrier_mode := false # pilots fly carriers: the hangar holds berth gates, not landed ships
var berth := {} # your own carrier's berth here: {"station", "copy", "pad"}, or {}
var gates_provider: Callable # returns the carriers docked in your copy: [{"name", "pad"}]
var arrive_from := "" # whose carrier you came off (its gate is where you arrive); "" is your own
const GATE_Z := [16.0, 22.0, 28.0, 34.0, 40.0]
var _gates := [] # {"root", "title", "body", "panel", "x", "z", "target", "name"}
var _gate_page := -1 # which of the docked carriers the boarding doors show, a gate's worth at a time (-1: the one you came off's)
var _gate_pages := 1
var _gate_console: Label3D
var _gate_time := 0.0
var _gate_wait := 0.0


func _build() -> void:
	_war = WarInfo.planet(planet_id) if _planet.is_empty() else {}
	_station_name = System.orbital_name(_war.name) if not _war.is_empty() else System.station_name(_planet.get("name", "Aster"))
	place_name = _station_name
	_build_environment()
	_build_space()
	_build_ring()
	_build_hall()
	for slot in ROOMS:
		var spec: Array = ROOMS[slot]
		_rooms[slot] = _room(slot, spec[1], spec[2], spec[3])
	_build_hangar(_rooms[0], 38.0, 44.0, 9.0)
	_build_services(_rooms[2], 12.0, 11.0, 5.0)
	_build_supply(_rooms[3], 12.0, 11.0, 4.6)
	_build_exchange(_rooms[4], 14.0, 12.0, 5.5)
	_build_jobs(_rooms[5], 12.0, 10.0, 5.0)
	_build_cantina(_rooms[6], 16.0, 14.0, 5.0)
	_build_security(_rooms[8], 12.0, 10.0, 4.6)
	_build_cabins(_rooms[9], 4.4, 30.0, 3.6)
	_build_observation(_rooms[10], 14.0, 12.0, 5.0)
	_build_window_stretch(283.0, 1.0)
	_directory(0.0)
	_directory(283.0)
	Net.state_changed.connect(_on_state)
	Net.chat_received.connect(_on_chat)


func _ready() -> void:
	super()
	_refresh_boards()


func _exit_tree() -> void:
	if Net.state_changed.is_connected(_on_state):
		Net.state_changed.disconnect(_on_state)
		Net.chat_received.disconnect(_on_chat)


# --- Space outside the windows --------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.006, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_energy = 0.32
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


## The planet and the stars outside. The planet hangs off one side of the station (toward 330 degrees,
## the Observation Lounge and the windows by the hangar), big and a little below the horizon, so it
## fills those windows as in the art. The sun lights only it (layer 2).
func _build_space() -> void:
	var body := System.builder_planet(planet_id)
	var colour: Color = body.get("color", Color(0.15, 0.55, 0.55))
	var noise := FastNoiseLite.new()
	noise.seed = hash(planet_id)
	noise.frequency = 0.01
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, colour.darkened(0.5))
	ramp.set_color(1, colour.lightened(0.45))
	ramp.add_point(0.55, colour)
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.9
	var sphere := SphereMesh.new()
	sphere.radius = 3600.0
	sphere.height = 7200.0
	sphere.radial_segments = 128
	sphere.rings = 64
	sphere.material = mat
	var planet := MeshInstance3D.new()
	planet.mesh = sphere
	planet.position = _polar(330.0, 5200.0, -2300.0)
	planet.layers = 2
	add_child(planet)

	var sun := DirectionalLight3D.new()
	sun.light_cull_mask = 2
	sun.light_energy = 1.3
	sun.basis = Basis.looking_at((planet.position + Vector3(0, -2600, 0)).rotated(Vector3.UP, 0.9).normalized(), Vector3.UP)
	add_child(sun)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := QuadMesh.new()
	dot.size = Vector2(3.0, 3.0)
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot_mat.albedo_color = Color(0.9, 0.93, 1.0)
	dot.material = dot_mat
	mm.mesh = dot
	mm.instance_count = 1500
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(1.6, 5.0)), d * 12000.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	add_child(stars)


# --- The Concourse Ring --------------------------------------------------------------------

func _angle_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## Half the angle a compartment's door wall covers on the ring, in degrees.
func _room_half_angle(slot: int) -> float:
	return rad_to_deg(asin(minf(0.99, (ROOMS[slot][1] / 2.0 + 0.2) / R_OUT)))


func _door_width(slot: int) -> float:
	return 8.0 if slot == 0 else (3.0 if slot == 9 else 3.4)


## Half the angle of a compartment's doorway on the ring. The ring wall stays closed everywhere
## else, so the gap between the curved ring and a room's flat front wall is never open.
func _door_half_angle(slot: int) -> float:
	return rad_to_deg(asin((_door_width(slot) / 2.0 + 0.1) / R_OUT))


func _build_ring() -> void:
	var step := 360.0 / SEGMENTS
	for i in SEGMENTS:
		var deg := (i + 0.5) * step
		var f := Node3D.new()
		f.rotation.y = PI / 2 - deg_to_rad(deg)
		add_child(f)
		var arc := func(r: float) -> float: return TAU * r / SEGMENTS * 1.08
		var mid := (R_IN + R_OUT) / 2.0
		# Floor, ceiling, and the strips of light along them.
		_box(f, Vector3(arc.call(R_OUT + 1.0), 0.2, R_OUT + 1.0 - R_IN), Vector3(0, -0.1, (R_IN + R_OUT + 1.0) / 2.0), FLOOR)
		_box(f, Vector3(arc.call(R_OUT + 0.8), 0.2, R_OUT + 0.8 - R_IN), Vector3(0, RING_H + 0.1, (R_IN + R_OUT + 0.8) / 2.0), PANEL)
		_box(f, Vector3(arc.call(R_IN + 0.7), 0.02, 0.1), Vector3(0, 0.01, R_IN + 0.7), CYAN, false, 2.5)
		_box(f, Vector3(arc.call(R_OUT - 0.7), 0.02, 0.1), Vector3(0, 0.01, R_OUT - 0.7), CYAN, false, 2.5)
		if i % 2 == 0:
			_box(f, Vector3(arc.call(R_IN + 3.0) * 0.6, 0.02, 0.5), Vector3(0, 0.012, R_IN + 3.0), Color(0.15, 0.55, 0.6), false, 0.6)
		_box(f, Vector3(arc.call(mid), 0.03, 0.5), Vector3(0, RING_H - 0.02, mid), Color(0.95, 0.97, 1.0), false, 2.0)
		if i % 2 == 1:
			_box(f, Vector3(arc.call(mid) * 0.7, 0.04, 2.2), Vector3(0, RING_H - 0.03, mid), FLOOR_DARK, false)
		# Inner wall, up to the Terminal Hall's ceiling, with four doorways into the hall.
		var hall_door := false
		for d in HALL_DOORS:
			if _angle_diff(deg, d) < rad_to_deg(2.4 / R_IN):
				hall_door = true
		if hall_door:
			_box(f, Vector3(arc.call(R_IN), HALL_H - 3.6, 0.4), Vector3(0, 3.6 + (HALL_H - 3.6) / 2.0, R_IN - 0.2), WALL)
		else:
			_box(f, Vector3(arc.call(R_IN), HALL_H, 0.4), Vector3(0, HALL_H / 2.0, R_IN - 0.2), WALL)
			if i % 2 == 0:
				_box(f, Vector3(arc.call(R_IN) * 1.6, 2.2, 0.06), Vector3(0, 2.1, R_IN + 0.02), PANEL, false)
		# Outer wall: windows onto the planet, except where a compartment opens.
		var room_here := false
		var door_here := false
		for slot in ROOMS:
			if _angle_diff(deg, slot * 30.0) < _room_half_angle(slot):
				room_here = true
			if _angle_diff(deg, slot * 30.0) < _door_half_angle(slot):
				door_here = true
		if room_here and not door_here:
			_box(f, Vector3(arc.call(R_OUT), RING_H, 0.4), Vector3(0, RING_H / 2.0, R_OUT + 0.2), WALL)
			if i % 2 == 0:
				_box(f, Vector3(arc.call(R_OUT) * 1.6, 2.2, 0.06), Vector3(0, 2.1, R_OUT - 0.02), PANEL, false)
		elif not room_here:
			var w: float = arc.call(R_OUT)
			_box(f, Vector3(w, 1.0, 0.5), Vector3(0, 0.5, R_OUT + 0.2), WALL)
			_box(f, Vector3(w, 0.12, 0.62), Vector3(0, 1.02, R_OUT + 0.1), TRIM, false)
			_box(f, Vector3(w, 3.0, 0.05), Vector3(0, 2.5, R_OUT + 0.25), Color(0.6, 0.8, 1.0), true, 0.0, 0.07)
			_box(f, Vector3(w, 1.0, 0.5), Vector3(0, 4.5, R_OUT + 0.2), WALL)
		# Ribs: an arched frame every few metres, as in the concourse art.
		if i % 4 == 0:
			var ribf := Node3D.new()
			ribf.rotation.y = deg_to_rad(step * 0.5)
			f.add_child(ribf)
			_box(ribf, Vector3(0.5, 0.5, R_OUT - R_IN), Vector3(0, RING_H - 0.25, mid), TRIM, false)
			if not hall_door:
				_box(ribf, Vector3(0.6, RING_H, 0.5), Vector3(0, RING_H / 2.0, R_IN + 0.2), PANEL)
				_box(ribf, Vector3(0.06, 0.5, 0.04), Vector3(0, 2.6, R_IN + 0.47), CYAN, false, 3.0)
			if not room_here:
				_box(ribf, Vector3(0.6, RING_H, 0.6), Vector3(0, RING_H / 2.0, R_OUT - 0.1), PANEL)
				_box(ribf, Vector3(0.5, 0.35, 0.35), Vector3(0, 0.7, R_OUT - 0.5), TRIM, false)
				_box(ribf, Vector3(0.3, 0.12, 0.02), Vector3(0, 0.75, R_OUT - 0.68), CYAN, false, 2.5, 1.0, Vector3(0, 0, 0))
		if i % 10 == 5:
			_light(f, Vector3(0, RING_H - 0.6, mid), Color(0.85, 0.92, 1.0), 1.1, 11.0)
	# Signs over the compartment doors, on the ring side, and directions at each hall door.
	for slot in ROOMS:
		var room_name: String = ROOMS[slot][0] if slot != 9 else "Crew Cabins · Deck 3"
		var f := Node3D.new()
		f.rotation.y = PI / 2 - deg_to_rad(slot * 30.0)
		add_child(f)
		_sign(f, room_name.to_upper(), Vector3(0, 4.25, R_OUT - 0.08), Vector3.FORWARD, 56)
	for d in HALL_DOORS:
		var f := Node3D.new()
		f.rotation.y = PI / 2 - deg_to_rad(d)
		add_child(f)
		_sign(f, "PLANETARY TERMINAL", Vector3(0, 4.3, R_IN + 0.05), Vector3.BACK, 48)
		_box(f, Vector3(0.08, 3.6, 0.06), Vector3(-2.4, 1.8, R_IN + 0.03), CYAN, false, 2.5)
		_box(f, Vector3(0.08, 3.6, 0.06), Vector3(2.4, 1.8, R_IN + 0.03), CYAN, false, 2.5)


## A stretch of the ring with nothing but windows: benches facing them, planters and info kiosks.
## A frame on the ring at `deg` degrees: +Z points straight out to the windows.
func _ring_frame(deg: float) -> Node3D:
	var f := Node3D.new()
	f.rotation.y = PI / 2 - deg_to_rad(deg)
	add_child(f)
	return f


## Degrees along the ring that `metres` of walking covers at radius `r`.
func _arc_deg(metres: float, r: float) -> float:
	return rad_to_deg(metres / r)


## `side` puts the info kiosk on the end away from the nearest hall doorway. Every piece sits at its
## own angle around the ring, so it lines up with the curved walls.
func _build_window_stretch(deg: float, side: float) -> void:
	var r := R_IN + 1.2
	for off in [-2.0, 2.0]:
		_bench(_ring_frame(deg + _arc_deg(off, r)), Vector3(0, 0, r), Vector3.BACK, 3.4)
	for off in [-4.2, 0.0, 4.2]:
		_planter(_ring_frame(deg + _arc_deg(off, r)), Vector3(0, 0, r))
	var kiosk := _console(_ring_frame(deg - side * _arc_deg(6.5, r)), Vector3(0, 0, R_IN + 1.0), Vector3.BACK, "INFO", "Concourse Ring\nCompartments are signed\nover each door.", 1.0)
	kiosk.font_size = 18


## The list of compartments, on the ring's inner wall at `deg` degrees.
func _directory(deg: float) -> void:
	var dir := _screen(_ring_frame(deg), Vector3(0, 3.0, R_IN + 0.08), Vector3.BACK, Vector2(4.6, 1.5), "CONCOURSE RING", "", 44, 26)
	var lines := []
	for slot in [2, 3, 4, 5, 6, 8, 9, 10]:
		lines.append(ROOMS[slot][0])
	dir.text = "   ".join(lines.slice(0, 5)) + "\n" + "   ".join(lines.slice(5))


# --- The Planetary Terminal Hall ------------------------------------------------------------

func _build_hall() -> void:
	_cyl(self, R_IN, 0.2, Vector3(0, -0.1, 0), FLOOR, true, 0.0, -1.0, 96)
	_cyl(self, R_IN, 0.2, Vector3(0, HALL_H + 0.1, 0), PANEL, true, 0.0, -1.0, 96)
	for r in [6.5, 14.0]:
		_ring_line(self, r, Vector3(0, 0.01, 0), HAZARD, 0.1, 1.2)
	_ring_line(self, 18.5, Vector3(0, 0.01, 0), CYAN, 0.1, 2.0)
	for r in [8.0, 16.0]:
		_ring_line(self, r, Vector3(0, HALL_H - 0.02, 0), Color(0.95, 0.97, 1.0), 0.3, 1.6)
	# The hologram pedestal and the planet globe floating over it, marked with every site.
	_cyl(self, 3.6, 0.3, Vector3(0, 0.15, 0), TRIM)
	_cyl(self, 2.8, 0.7, Vector3(0, 0.65, 0), PANEL)
	_cyl(self, 2.0, 0.5, Vector3(0, 1.25, 0), TRIM, true, 0.0, 1.7)
	_ring_line(self, 2.7, Vector3(0, 1.0, 0), CYAN, 0.08, 3.0)
	_ring_line(self, 1.8, Vector3(0, 1.52, 0), CYAN, 0.12, 4.0)
	_cyl(self, 1.7, 0.04, Vector3(0, 1.5, 0), Color(0.4, 0.75, 1.0), false, 3.0)
	var beam := _cyl(self, 1.6, 1.4, Vector3(0, 2.2, 0), Color(0.4, 0.75, 1.0), false, 1.5, 2.4)
	(beam as MeshInstance3D).mesh.material = _mat(Color(0.4, 0.75, 1.0), 1.5, 0.12)
	_globe = Node3D.new()
	_globe.position = Vector3(0, 4.4, 0)
	add_child(_globe)
	var body := System.builder_planet(planet_id)
	var holo := StandardMaterial3D.new()
	holo.albedo_color = Color(0.45, 0.75, 1.0, 0.42)
	holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo.emission_enabled = true
	holo.emission = Color(body.get("color", Color(0.3, 0.6, 0.9))).lerp(Color(0.4, 0.7, 1.0), 0.6)
	holo.emission_energy_multiplier = 0.9
	holo.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not _war.is_empty():
		# Fainter over a contested world, so its sectors' colours show.
		holo.albedo_color = Color(0.4, 0.6, 0.8, 0.3)
		holo.emission_energy_multiplier = 0.45
	var noise := FastNoiseLite.new()
	noise.seed = hash(planet_id)
	noise.frequency = 0.012
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	holo.albedo_texture = tex
	var sphere := SphereMesh.new()
	sphere.radius = 2.9
	sphere.height = 5.8
	sphere.material = holo
	var g := MeshInstance3D.new()
	g.mesh = sphere
	_globe.add_child(g)
	_globe_markers = Node3D.new()
	_globe.add_child(_globe_markers)
	_light(self, Vector3(0, 4.4, 0), Color(0.45, 0.7, 1.0), 2.0, 12.0)
	_light(self, Vector3(9, HALL_H - 0.8, 0), Color(0.85, 0.92, 1.0), 0.9, 14.0)
	_light(self, Vector3(-9, HALL_H - 0.8, 0), Color(0.85, 0.92, 1.0), 0.9, 14.0)

	# Consoles around the globe, and two big status walls between the doorways.
	_boards.hall_status = _screen(self, _polar(90.0, R_IN - 0.45, 4.2), _inward(90.0), Vector2(7.5, 3.6), "PLANETARY STATUS", "", 60, 34)
	_boards.hall_ops = _screen(self, _polar(270.0, R_IN - 0.45, 4.2), _inward(270.0), Vector2(7.5, 3.6), "ACTIVE OPERATIONS", "", 60, 34, ALERT)
	_boards.hall_sector = _screen(self, _polar(180.0, R_IN - 0.45, 4.2), _inward(180.0), Vector2(5.0, 2.6), "WAR FRONT · %s" % str(Net.state.get("system", {}).get("name", "TEAL PRIME")).to_upper(), "", 52, 32)
	_screen(self, _polar(0.0, R_IN - 0.45, 5.6), _inward(0.0), Vector2(5.0, 1.4), "WELCOME TO %s" % _station_name.to_upper(), "Hangar and pads through the concourse ->", 44, 28)
	# Surface Transit at 20, 110, 200 and 290 degrees, War terminals at 160 and 340, site monitors between.
	for deg in [20.0, 70.0, 110.0, 160.0, 200.0, 250.0, 290.0, 340.0]:
		var travel := int(deg) % 90 == 20
		var war: bool = deg == 160.0 or deg == 340.0
		if travel:
			_console(self, _polar(deg, 11.0, 0.0), _inward(deg), "SURFACE TRANSIT",
				("Shuttles to every\noutpost on %s.\nPress F." % _planet_name()) if not _war.is_empty() else "Shuttles to the Spaceport\nand every facility.\nPress F.", 1.8)
			_use(self, _polar(deg, 10.3, 1.0), func(): return "Press %s to plan a trip to the surface" % _key(), func(): wants_menu.emit())
		elif war:
			_console(self, _polar(deg, 11.0, 0.0), _inward(deg), "WAR TERMINAL", "The front, sector\nby sector.\nPress F.", 1.8)
			_use(self, _polar(deg, 10.3, 1.0), func(): return "Press %s for the War terminal" % _key(), func(): service.emit("war"))
		else:
			_boards["monitor_%d" % deg] = _console(self, _polar(deg, 11.0, 0.0), _inward(deg), "SITE MONITOR", "", 1.8)


func _polar(deg: float, r: float, y: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * r, y, sin(a) * r)


func _inward(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return -Vector3(cos(a), 0, sin(a))


# --- Compartments ---------------------------------------------------------------------------

## The shell of a compartment off the ring: walls, floor, ceiling, lights and its doorway.
## Returns a node whose origin is the middle of the doorway, with +Z running into the room.
func _room(slot: int, w: float, d: float, h: float) -> Node3D:
	var f := Node3D.new()
	f.rotation.y = PI / 2 - deg_to_rad(slot * 30.0)
	add_child(f)
	var room := Node3D.new()
	room.position = Vector3(0, 0, R_OUT)
	room.name = ROOMS[slot][0]
	f.add_child(room)
	var door_w := _door_width(slot)
	var door_h := 4.6 if slot == 0 else 3.3
	var near_h := maxf(h, RING_H)
	var side := (w - door_w) / 2.0
	# Doorway wall, closing the ring around the door.
	_box(room, Vector3(side, near_h, 0.4), Vector3(-(door_w + side) / 2.0, near_h / 2.0, 0.2), WALL)
	_box(room, Vector3(side, near_h, 0.4), Vector3((door_w + side) / 2.0, near_h / 2.0, 0.2), WALL)
	_box(room, Vector3(door_w, near_h - door_h, 0.4), Vector3(0, door_h + (near_h - door_h) / 2.0, 0.2), WALL)
	for s in [-1, 1]:
		_box(room, Vector3(0.3, door_h, 0.55), Vector3(s * (door_w / 2.0 + 0.15), door_h / 2.0, 0.2), TRIM, false)
		_box(room, Vector3(0.06, door_h - 0.2, 0.04), Vector3(s * (door_w / 2.0 + 0.15), door_h / 2.0, -0.1), CYAN, false, 3.0)
	_box(room, Vector3(door_w + 0.6, 0.3, 0.55), Vector3(0, door_h + 0.15, 0.2), TRIM, false)
	# Side walls, reaching back into the ring wall so no gap shows.
	for s in [-1, 1]:
		_box(room, Vector3(0.4, h, d + 1.4), Vector3(s * (w / 2.0 + 0.2), h / 2.0, d / 2.0 - 0.5), WALL)
		for z in range(2, int(d) - 1, 3):
			_box(room, Vector3(0.05, h * 0.5, 2.4), Vector3(s * (w / 2.0 - 0.03), h * 0.45, z + 0.5), PANEL, false)
			_box(room, Vector3(0.06, 0.04, 2.2), Vector3(s * (w / 2.0 - 0.04), 0.18, z + 0.5), CYAN, false, 2.0)
	_box(room, Vector3(w + 0.8, 0.2, d + 1.4), Vector3(0, -0.105, d / 2.0 - 0.5), FLOOR)
	_box(room, Vector3(w + 0.8, 0.2, d + 0.2), Vector3(0, h + 0.1, d / 2.0 + 0.5), PANEL)
	for x in [-w / 4.0, w / 4.0]:
		_box(room, Vector3(0.4, 0.03, d - 1.0), Vector3(x, h - 0.02, d / 2.0 + 0.3), Color(0.95, 0.97, 1.0), false, 1.8)
	# Floor panel seams.
	for z in range(3, int(d), 3):
		_box(room, Vector3(w - 0.4, 0.012, 0.05), Vector3(0, 0.006, z), FLOOR_DARK, false)
	_light(room, Vector3(0, h - 0.6, d * 0.3), Color(0.85, 0.92, 1.0), 1.0, maxf(w, d) * 0.8)
	_light(room, Vector3(0, h - 0.6, d * 0.78), Color(0.85, 0.92, 1.0), 1.0, maxf(w, d) * 0.8)
	_hull(room, w, d, h)
	return room


## The outside of a compartment, as seen through the ring's windows: one-sided hull plates facing
## out, so from inside the room they're invisible and never block its own windows.
func _hull(room: Node3D, w: float, d: float, h: float) -> void:
	var hull := Color(0.33, 0.35, 0.39)
	var o := 0.45
	var depth := d + 0.4 + 0.8
	var mid := Vector3(0, h / 2.0, 0.4 + depth / 2.0)
	_plate(room, Vector2(depth, h + 2 * o), Vector3(w / 2.0 + o, h / 2.0, mid.z), Vector3.RIGHT, hull)
	_plate(room, Vector2(depth, h + 2 * o), Vector3(-w / 2.0 - o, h / 2.0, mid.z), Vector3.LEFT, hull)
	_plate(room, Vector2(w + 2 * o, depth), Vector3(0, h + o, mid.z), Vector3.UP, hull)
	_plate(room, Vector2(w + 2 * o, depth), Vector3(0, -o, mid.z), Vector3.DOWN, hull)
	_plate(room, Vector2(w + 2 * o, h + 2 * o), Vector3(0, h / 2.0, 0.4 + depth), Vector3.BACK, hull)
	# Running lights along the hull's edges.
	for s in [-1, 1]:
		_plate(room, Vector2(depth - 1.0, 0.12), Vector3(s * (w / 2.0 + o + 0.01), h - 0.3, mid.z), Vector3(s, 0, 0), CYAN, 2.5)


func _plate(parent: Node3D, size: Vector2, pos: Vector3, outward: Vector3, colour: Color, glow := 0.0) -> void:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.basis = _facing_basis(outward)
	parent.add_child(mi)


## The far wall of a compartment, with a window `ww` wide (centred at `wx`) from `sill` to `top`.
func _far_wall(room: Node3D, w: float, d: float, h: float, ww := 0.0, wx := 0.0, sill := 1.0, top := 4.0) -> void:
	var z := d + 0.2
	if ww <= 0.0:
		_box(room, Vector3(w, h, 0.4), Vector3(0, h / 2.0, z), WALL)
		return
	var l := wx - ww / 2.0 + w / 2.0
	var r := w / 2.0 - (wx + ww / 2.0)
	if l > 0.01:
		_box(room, Vector3(l, h, 0.4), Vector3(-w / 2.0 + l / 2.0, h / 2.0, z), WALL)
	if r > 0.01:
		_box(room, Vector3(r, h, 0.4), Vector3(w / 2.0 - r / 2.0, h / 2.0, z), WALL)
	_box(room, Vector3(ww, sill, 0.4), Vector3(wx, sill / 2.0, z), WALL)
	_box(room, Vector3(ww, h - top, 0.4), Vector3(wx, top + (h - top) / 2.0, z), WALL)
	_box(room, Vector3(ww, top - sill, 0.05), Vector3(wx, (sill + top) / 2.0, z), Color(0.6, 0.8, 1.0), true, 0.0, 0.07)
	# A chunky frame with cut corners, like the art's windows.
	_box(room, Vector3(ww + 0.5, 0.35, 0.3), Vector3(wx, sill, z - 0.3), TRIM, false)
	_box(room, Vector3(ww + 0.5, 0.35, 0.3), Vector3(wx, top, z - 0.3), TRIM, false)
	for s in [-1, 1]:
		_box(room, Vector3(0.35, top - sill, 0.3), Vector3(wx + s * ww / 2.0, (sill + top) / 2.0, z - 0.3), TRIM, false)
		_box(room, Vector3(0.6, 0.6, 0.3), Vector3(wx + s * (ww / 2.0 - 0.15), top - 0.15, z - 0.32), TRIM, false, 0.0, 1.0, Vector3(0, 0, 45))
		_box(room, Vector3(0.6, 0.6, 0.3), Vector3(wx + s * (ww / 2.0 - 0.15), sill + 0.15, z - 0.32), TRIM, false, 0.0, 1.0, Vector3(0, 0, 45))
	_box(room, Vector3(ww - 0.4, 0.04, 0.04), Vector3(wx, top - 0.22, z - 0.47), CYAN, false, 2.5)


func _build_hangar(room: Node3D, w: float, d: float, h: float) -> void:
	if carrier_mode:
		_build_berth_hall(room, w, d, h)
		return
	# The far end is open to space behind a faint blue pressure shield.
	_box(room, Vector3(w, h, 0.05), Vector3(0, h / 2.0, d + 0.2), Color(0.3, 0.6, 1.0), true, 0.6, 0.06)
	_box(room, Vector3(w, 0.6, 1.0), Vector3(0, h - 0.3, d), TRIM, false)
	_box(room, Vector3(w, 0.3, 1.0), Vector3(0, 0.15, d), TRIM)
	_box(room, Vector3(w - 1.0, 0.05, 0.05), Vector3(0, h - 0.65, d - 0.5), CYAN, false, 3.0)
	# Walkway, railings and hazard stripes between the concourse and the pads.
	for x in [-11.0, 11.0]:
		_box(room, Vector3(15.0, 0.08, 0.08), Vector3(x, 1.05, 6.0), TRIM, false)
		_box(room, Vector3(15.0, 0.08, 0.08), Vector3(x, 0.6, 6.0), TRIM, false)
		_box(room, Vector3(15.0, 1.1, 0.1), Vector3(x, 0.55, 6.0), Color(0, 0, 0), true, 0.0, 0.0)
		for px in range(-6, 7, 3):
			_box(room, Vector3(0.12, 1.1, 0.12), Vector3(x + px, 0.55, 6.0), PANEL, false)
	for i in 18:
		_box(room, Vector3(0.9, 0.015, 0.35), Vector3(-17.0 + i * 2.0, 0.008, 6.6), HAZARD if i % 2 == 0 else Color(0.08, 0.08, 0.08), false, 0.3, 1.0, Vector3(0, 30, 0))
	# Six pads: 01 to 06. Yours is 06.
	# 13 m apart side by side (wings span 11 m) and 16 m front to back (a ship and its ramp are 13 m).
	var pads := [Vector3(-13, 0, 16), Vector3(0, 0, 16), Vector3(13, 0, 16), Vector3(-13, 0, 32), Vector3(0, 0, 32), Vector3(13, 0, 32)]
	# Who is on which pad, and whether their ship is open (landed, ramp down) or locked (ramp up).
	var parked := {0: ["Rook", true], 3: ["BlueLeader", false], 5: [Net.my_name if Net.my_name != "" else "You", true]}
	for i in pads.size():
		var p: Vector3 = pads[i]
		_cyl(room, 4.0, 0.35, p + Vector3(0, 0.17, 0), TRIM)
		_cyl(room, 3.4, 0.06, p + Vector3(0, 0.37, 0), Color(0.18, 0.22, 0.26), false)
		_ring_line(room, 3.7, p + Vector3(0, 0.37, 0), CYAN, 0.15, 3.0)
		_ring_line(room, 2.2, p + Vector3(0, 0.41, 0), HAZARD if parked.has(i) else CYAN, 0.06, 2.0)
		_text(room, "%02d" % (i + 1), p + Vector3(0, 0.42, -3.0), Vector3.UP, 120, Color(0.85, 0.9, 0.95)).rotate_y(PI) # read from the walkway
		if parked.has(i):
			_landed_ship(room, p, 180.0, parked[i][0], parked[i][1], i == 5, i + 1)
	_sign(room, "DOCK 07 · PADS 01-06", Vector3(0, 6.0, 0.5), Vector3.BACK, 80)
	_sign(room, "PRESSURIZED", Vector3(-6.5, 5.2, 0.5), Vector3.BACK, 44, Color(0.4, 1.0, 0.55))
	var board := _screen(room, Vector3(-w / 2.0 + 0.3, 4.6, 9.0), Vector3.RIGHT, Vector2(8.0, 4.0), "PAD ASSIGNMENTS", "", 80, 52)
	board.text = "01  ROOK · OPEN           02  AVAILABLE\n\n03  AVAILABLE             04  BLUELEADER · LOCKED\n\n05  AVAILABLE             06  YOU · OPEN"
	_console(room, Vector3(-w / 2.0 + 1.2, 0, 3.0), Vector3.RIGHT, "DOCK CONTROL", "Shield: holding\nTraffic: light", 2.2)
	for x in [-13.0, -4.5, 4.5, 13.0]:
		for z in [12.0, 24.0, 36.0]:
			_box(room, Vector3(2.4, 0.04, 0.3), Vector3(x, h - 0.02, z), Color(0.95, 0.97, 1.0), false, 2.0)
	_light(room, Vector3(-10, h - 1, 16), Color(0.85, 0.92, 1.0), 1.4, 20.0)
	_light(room, Vector3(10, h - 1, 16), Color(0.85, 0.92, 1.0), 1.4, 20.0)
	_light(room, Vector3(-10, h - 1, 32), Color(0.85, 0.92, 1.0), 1.2, 20.0)
	_light(room, Vector3(10, h - 1, 32), Color(0.85, 0.92, 1.0), 1.2, 20.0)


# --- The Carrier Berth hall (the hangar, for carriers) -----------------------------------------

## The hangar for pilots who fly fleet carriers: their ships are clamped at berths outside, so the
## hall holds the airlock gates along both side walls: yours first, then one per carrier docked in
## your copy. The far end still looks out through the pressure shield.
func _build_berth_hall(room: Node3D, w: float, d: float, h: float) -> void:
	_box(room, Vector3(w, h, 0.05), Vector3(0, h / 2.0, d + 0.2), Color(0.3, 0.6, 1.0), true, 0.6, 0.06)
	_box(room, Vector3(w, 0.6, 1.0), Vector3(0, h - 0.3, d), TRIM, false)
	_box(room, Vector3(w, 0.3, 1.0), Vector3(0, 0.15, d), TRIM)
	_box(room, Vector3(w - 1.0, 0.05, 0.05), Vector3(0, h - 0.65, d - 0.5), CYAN, false, 3.0)
	# A walkway down the middle, lit, with benches and crates either side.
	_box(room, Vector3(6.0, 0.02, d - 4.0), Vector3(0, 0.012, d / 2.0 + 1.0), Color(0.2, 0.3, 0.34), false, 0.2)
	for x in [-3.0, 3.0]:
		_box(room, Vector3(0.1, 0.025, d - 4.0), Vector3(x, 0.016, d / 2.0 + 1.0), CYAN, false, 2.0)
	for z in [14.0, 26.0, 38.0]:
		_bench(room, Vector3(-6.5, 0, z), Vector3.RIGHT, 3.0)
		_bench(room, Vector3(6.5, 0, z), Vector3.LEFT, 3.0)
	_crate(room, Vector3(1.6, 1.2, 1.2), Vector3(-8.0, 0, 20.0), "CARGO")
	_crate(room, Vector3(1.4, 1.0, 1.2), Vector3(8.2, 0, 32.0))
	_planter(room, Vector3(-8.0, 0, 31.5))
	_planter(room, Vector3(8.0, 0, 19.5))
	_sign(room, "CARRIER BERTHS · 01-32", Vector3(0, 6.0, 0.5), Vector3.BACK, 80)
	_sign(room, "PRESSURIZED", Vector3(-6.5, 5.2, 0.5), Vector3.BACK, 44, Color(0.4, 1.0, 0.55))
	_boards.berths = _screen(room, Vector3(-w / 2.0 + 0.3, 4.8, 9.0), Vector3.RIGHT, Vector2(7.0, 3.2), "BERTH ASSIGNMENTS", "", 70, 40)
	_gate_console = _console(room, Vector3(-w / 2.0 + 1.2, 0, 3.0), Vector3.RIGHT, "DOCK CONTROL", "Berth ring: holding
Clamps: secure", 2.2)
	_use(room, Vector3(-w / 2.0 + 1.9, 1.0, 3.0), _page_prompt, _next_gate_page)
	for s in [-1, 1]:
		for z in GATE_Z:
			_gate(room, s, z)
	for x in [-10.0, 10.0]:
		for z in [12.0, 24.0, 36.0]:
			_box(room, Vector3(2.4, 0.04, 0.3), Vector3(x, h - 0.02, z), Color(0.95, 0.97, 1.0), false, 2.0)
		_light(room, Vector3(x, h - 1, 18), Color(0.85, 0.92, 1.0), 1.3, 20.0)
		_light(room, Vector3(x, h - 1, 34), Color(0.85, 0.92, 1.0), 1.2, 20.0)
	_refresh_gates()


## One airlock gate on a side wall (`side` -1 port, 1 starboard): a frame, a door that lights up
## when a carrier is clamped behind it, and a sign over it saying whose it is.
func _gate(room: Node3D, side: int, z: float) -> void:
	var g := Node3D.new()
	var x := side * 18.8
	g.position = Vector3(x, 0, z)
	g.basis = _facing_basis(Vector3(-side, 0, 0))
	room.add_child(g)
	for s in [-1, 1]:
		_box(g, Vector3(0.45, 3.8, 0.5), Vector3(s * 1.75, 1.9, 0.0), TRIM, false)
		_box(g, Vector3(0.06, 3.4, 0.06), Vector3(s * 1.5, 1.8, 0.27), HAZARD, false, 2.0)
	_box(g, Vector3(4.0, 0.45, 0.5), Vector3(0, 3.95, 0), TRIM, false)
	var panel := _box(g, Vector3(3.0, 3.4, 0.08), Vector3(0, 1.7, -0.05), Color(0.12, 0.13, 0.15), false)
	_box(g, Vector3(3.0, 0.05, 0.1), Vector3(0, 1.7, 0.0), Color(0.05, 0.05, 0.06), false)
	var plate := Node3D.new()
	plate.position = Vector3(0, 4.85, 0.1)
	g.add_child(plate)
	_box(plate, Vector3(3.8, 1.1, 0.1), Vector3(0, 0, -0.05), Color(0.16, 0.18, 0.2), false)
	var title := _text(plate, "", Vector3(0, 0.22, 0.02), Vector3.BACK, 56, SCREEN_TEXT)
	var body := _text(plate, "", Vector3(0, -0.22, 0.02), Vector3.BACK, 34, SCREEN_TEXT)
	var spot := Marker3D.new()
	spot.position = Vector3(0, 0.05, 1.6)
	g.add_child(spot) # +Z: facing out into the hall
	var gate := {"root": g, "title": title, "body": body, "panel": panel, "side": side, "z": z, "target": "", "name": "", "spot": spot}
	_gates.append(gate)
	_use(g, Vector3(0, 1.0, 0.9), _gate_prompt.bind(gate), _through_gate.bind(gate))


## Who's behind each gate: your carrier first (or the shuttle to it when it's berthed elsewhere),
## then the carriers docked in your copy, by berth: one page of them (DOCK CONTROL turns it).
func _refresh_gates() -> void:
	var docked: Array = gates_provider.call() if gates_provider.is_valid() else []
	docked = docked.filter(func(c): return c.name != Net.my_name)
	docked.sort_custom(func(a, b): return int(a.pad) < int(b.pad))
	var per := maxi(1, _gates.size() - 1)
	_gate_pages = maxi(1, ceili(docked.size() / float(per)))
	if _gate_page < 0:
		var came := docked.map(func(c): return c.name).find(arrive_from)
		_gate_page = floori(came / float(per)) if came >= 0 else 0
	_gate_page %= _gate_pages
	if _gate_console:
		var first := _gate_page * per
		_gate_console.text = "Gates: %d of %d carriers\nPage %d of %d · %s: next" % [mini(per, docked.size() - first), docked.size(), _gate_page + 1, _gate_pages, _key()] if _gate_pages > 1 else "Berth ring: holding\nClamps: secure"
	docked = docked.slice(_gate_page * per)
	var mine_here: bool = berth.get("station", "") == planet_id
	var lines := []
	for i in _gates.size():
		var g: Dictionary = _gates[i]
		var panel: MeshInstance3D = (g.panel as StaticBody3D).get_child(1) if g.panel is StaticBody3D else g.panel
		if i == 0:
			g.target = "ship:" + Net.my_name
			g.name = Net.my_name
			g.title.text = "BERTH %02d" % int(berth.pad) if mine_here else "SHUTTLE"
			g.body.text = "YOUR CARRIER" if mine_here else "TO YOUR CARRIER"
			g.title.modulate = Color(0.45, 1.0, 0.6)
			panel.mesh.material = _mat(Color(0.25, 0.75, 0.5), 0.8)
		elif i - 1 < docked.size():
			var c: Dictionary = docked[i - 1]
			g.target = "ship:" + str(c.name)
			g.name = str(c.name)
			g.title.text = "BERTH %02d" % int(c.pad)
			g.body.text = "BOARD %s'S CARRIER" % str(c.name).to_upper()
			g.title.modulate = SCREEN_TEXT
			panel.mesh.material = _mat(Color(0.25, 0.6, 0.75), 0.6)
		else:
			g.target = ""
			g.name = ""
			g.title.text = "BERTH --"
			g.body.text = "NO CARRIER"
			g.title.modulate = Color(0.6, 0.62, 0.65)
			panel.mesh.material = _mat(Color(0.12, 0.13, 0.15))
		if g.target != "":
			lines.append("%s  %s" % [g.title.text, g.body.text])
		if g.name == (arrive_from if arrive_from != "" else Net.my_name):
			_arrival = g.spot
	if _boards.has("berths"):
		_boards.berths.text = "\n".join(lines.slice(0, 7)) if not lines.is_empty() else "No carriers docked in this copy."
	if _arrival == null and not _gates.is_empty():
		_arrival = _gates[0].spot


func _page_prompt() -> String:
	if _gate_pages <= 1:
		return "Dock Control: every carrier docked in this copy has a gate"
	return "Press %s to show the next carriers' gates (page %d of %d)" % [_key(), _gate_page + 1, _gate_pages]


func _next_gate_page() -> void:
	if _gate_pages <= 1:
		return
	_gate_page = (_gate_page + 1) % _gate_pages
	_refresh_gates()
	_say("The boarding gates now show page %d of %d." % [_gate_page + 1, _gate_pages], 3.0)


func _gate_prompt(g: Dictionary) -> String:
	if g.target == "":
		return "Nobody's carrier is clamped behind this gate"
	if g.name == Net.my_name:
		return "Your carrier's airlock: walk through (or press %s) to go aboard" % _key()
	return "Press %s (or walk through) to board %s's carrier" % [_key(), g.name]


func _through_gate(g: Dictionary) -> void:
	if g.target != "" and _gate_wait <= 0.0:
		_gate_wait = 2.5
		wants_space.emit(g.target)


## Walking into a gate's doorway takes you through it.
func _check_gates(delta: float) -> void:
	_gate_wait -= delta
	_gate_time -= delta
	if _gate_time <= 0.0:
		_gate_time = 1.5
		_refresh_gates()
	if seated or _gate_wait > 0.0 or not _rooms.has(0):
		return
	var p: Vector3 = _rooms[0].to_local(_player.global_position)
	for g in _gates:
		if g.target != "" and absf(p.x) > 18.2 and signf(p.x) == g.side and absf(p.z - g.z) < 1.3:
			_through_gate(g)
			return


func _leave_hint() -> String:
	if carrier_mode:
		return "To leave, walk back through your carrier's airlock gate in the Carrier Berths."
	return super()


func _build_services(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h, 8.0, 0.5, 0.8, 4.1)
	# The repair bay behind the window: a ship with a hole in its hull and a drone arm welding it.
	var bay := Node3D.new()
	bay.position = Vector3(0, 0, d + 0.4)
	room.add_child(bay)
	_box(bay, Vector3(22, 0.3, 18), Vector3(0, -1.5, 9), FLOOR_DARK, false)
	_box(bay, Vector3(22, 0.3, 18), Vector3(0, 10, 9), TRIM, false)
	_box(bay, Vector3(0.3, 11.5, 18), Vector3(-11, 4.2, 9), TRIM, false)
	_box(bay, Vector3(0.3, 11.5, 18), Vector3(11, 4.2, 9), TRIM, false)
	_box(bay, Vector3(22, 11.5, 0.3), Vector3(0, 4.2, 18), Color(0.2, 0.22, 0.25), false)
	for x in [-8.0, -3.0, 2.0, 7.0]:
		_box(bay, Vector3(0.4, 11.5, 0.6), Vector3(x, 4.2, 17.6), PANEL, false)
		_box(bay, Vector3(1.6, 0.06, 0.3), Vector3(x, 9.8, 9), Color(0.95, 0.97, 1.0), false, 2.0)
	var hull := Models.starter_ship()
	hull.scale = Vector3.ONE * 1.5
	hull.position = Vector3(1.5, 2.2, 9.5)
	hull.rotation_degrees.y = 75.0
	bay.add_child(hull)
	_box(bay, Vector3(1.6, 1.4, 0.4), Vector3(-0.6, 2.6, 5.3), Color(0.05, 0.05, 0.06), false, 0.0, 1.0, Vector3(0, -15, 10))
	var arm_base := _cyl(bay, 0.9, 1.0, Vector3(-6.5, -1.0, 4.5), TRIM, false)
	arm_base.visible = true
	_box(bay, Vector3(0.6, 4.2, 0.6), Vector3(-6.0, 1.3, 4.5), PANEL, false, 0.0, 1.0, Vector3(0, 0, -20))
	_box(bay, Vector3(0.5, 3.6, 0.5), Vector3(-3.6, 3.6, 4.7), PANEL, false, 0.0, 1.0, Vector3(0, 0, -75))
	_box(bay, Vector3(0.4, 1.4, 0.4), Vector3(-1.5, 3.1, 5.0), TRIM, false, 0.0, 1.0, Vector3(0, 0, -20))
	var spark := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.18
	s_mesh.height = 0.36
	s_mesh.material = _mat(Color(1.0, 0.75, 0.35), 6.0)
	spark.mesh = s_mesh
	spark.position = Vector3(-1.1, 2.5, 5.2)
	bay.add_child(spark)
	_light(bay, Vector3(-1.1, 2.6, 4.6), Color(1.0, 0.7, 0.35), 2.5, 7.0)
	_light(bay, Vector3(0, 8, 9), Color(0.75, 0.85, 1.0), 1.4, 16.0)
	# Inside: status panels, the bay console and a floor grate.
	_sign(room, "SHIP SERVICES DOCK\nBAY 03 · REPAIR & MAINTENANCE", Vector3(-w / 2.0 + 0.25, 3.7, 3.5), Vector3.RIGHT, 40)
	_screen(room, Vector3(-w / 2.0 + 0.25, 2.2, 3.5), Vector3.RIGHT, Vector2(2.6, 1.3), "DOCK STATUS", "OPERATIONAL\nPower 82%   Pressure 74%", 34, 26)
	_screen(room, Vector3(-w / 2.0 + 0.25, 2.2, 6.8), Vector3.RIGHT, Vector2(2.6, 1.3), "TOOL STATUS", "Welding arm   READY\nPatch applicator  READY\nScan drone   STANDBY", 34, 24)
	_screen(room, Vector3(w / 2.0 - 0.25, 2.4, d - 1.6), Vector3.LEFT, Vector2(1.6, 2.4), "REPAIR DRONE 07", "Status: ACTIVE\nTask: hull patching\nProgress: 62%", 30, 22)
	_sign(room, "BAY 03 · REPAIR IN PROGRESS", Vector3(0.5, h - 0.45, d - 0.05), Vector3.FORWARD, 40)
	_box(room, Vector3(3.2, 0.03, 2.2), Vector3(0.5, 0.015, d / 2.0), Color(0.12, 0.13, 0.15), false)
	for i in 9:
		_box(room, Vector3(0.04, 0.035, 2.0), Vector3(-0.9 + i * 0.35, 0.02, d / 2.0), TRIM, false)
	_box(room, Vector3(w - 1, 0.014, 0.25), Vector3(0, 0.008, d - 2.0), Color(0.2, 0.6, 0.62), false, 0.8)
	_console(room, Vector3(-3.0, 0, d - 3.0), Vector3.BACK.rotated(Vector3.UP, 0.3) * -1, "BAY 03 OVERVIEW", "Press F to repair\nyour ship", 2.0)
	_use(room, Vector3(-3.0, 1.0, d - 3.6), func(): return "Press %s to repair and recharge your ship" % _key(), func(): service.emit("repair"); _say("Ship Services: hull and shields restored."))


func _build_supply(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h, 2.6, 3.2, 1.2, 3.8)
	var x := -w / 2.0 + 0.6
	_sign(room, "GEAR RACK  +", Vector3(x - 0.3, 3.9, 5.0), Vector3.RIGHT, 64)
	for y in [0.35, 1.25, 2.15]:
		_box(room, Vector3(0.9, 0.08, 6.0), Vector3(x, y, 5.0), TRIM)
		_box(room, Vector3(0.03, 0.03, 5.8), Vector3(x + 0.46, y - 0.05, 5.0), CYAN, false, 2.0)
	for i in 3:
		var z := 3.0 + i * 2.0
		# Top shelf: trauma kits. Middle: ammo packs. Bottom: drill charges.
		_box(room, Vector3(0.6, 0.5, 1.4), Vector3(x, 2.45, z), Color(0.2, 0.22, 0.25), false)
		_text(room, "+", Vector3(x + 0.31, 2.5, z), Vector3.RIGHT, 90, CYAN)
		_text(room, "TRAUMA KIT", Vector3(x + 0.31, 2.28, z), Vector3.RIGHT, 18, Color(0.85, 0.88, 0.9))
		_box(room, Vector3(0.6, 0.55, 1.4), Vector3(x, 1.57, z), [Color(0.2, 0.55, 0.55), Color(0.85, 0.65, 0.15), Color(0.7, 0.2, 0.18)][i], false)
		_text(room, "AMMO\nPACK", Vector3(x + 0.31, 1.57, z), Vector3.RIGHT, 22, Color(0.1, 0.1, 0.1))
		_cyl(room, 0.3, 0.75, Vector3(x, 0.77, z), Color(0.5, 0.52, 0.55), false)
		_ring_line(room, 0.31, Vector3(x, 1.0, z), CYAN, 0.04, 2.0)
		_text(room, "DRILL\nCHARGE", Vector3(x + 0.31, 0.75, z), Vector3.RIGHT, 18, HAZARD)
	# The counter, its register, and crates.
	_box(room, Vector3(3.6, 1.1, 1.3), Vector3(0.6, 0.55, 6.5), PANEL)
	_box(room, Vector3(3.8, 0.1, 1.5), Vector3(0.6, 1.15, 6.5), TRIM, false)
	_box(room, Vector3(3.4, 0.04, 0.04), Vector3(0.6, 0.95, 5.84), CYAN, false, 2.5)
	_sign(room, "SUPPLY SHOP\nAUTHORIZED PERSONNEL ONLY", Vector3(0.6, 0.55, 5.83), Vector3.FORWARD, 30, Color(0.85, 0.88, 0.9), Vector2(2.6, 0.7))
	_screen(room, Vector3(0.2, 1.55, 6.6), Vector3(0, 0.5, -1).normalized(), Vector2(0.7, 0.45), "REGISTER", "", 20, 16)
	_use(room, Vector3(0.6, 1.0, 5.6), func(): return "Supply Shop: press %s to browse raid gear" % _key(), func(): _say("Trauma kits, ammo and drill charges go on sale once the server can sell them."))
	_crate(room, Vector3(1.6, 1.1, 1.2), Vector3(4.4, 0, 8.6), "SUPPLY CRATE\nCLASS B")
	_crate(room, Vector3(1.6, 1.0, 1.2), Vector3(4.4, 1.1, 8.6))
	_crate(room, Vector3(1.4, 1.2, 1.2), Vector3(4.6, 0, 6.8), "ORDNANCE\nLOCKER")
	_crate(room, Vector3(1.2, 0.9, 1.0), Vector3(2.6, 0, 9.4))
	_sign(room, "ORBITAL STATION · SUPPLY & ORDNANCE", Vector3(-0.5, 4.15, d - 0.05), Vector3.FORWARD, 36)
	_screen(room, Vector3(-3.8, 2.4, d - 0.05), Vector3.FORWARD, Vector2(1.3, 1.6), "STATION SYS", "Life support  OK\nGravity  stable\nHull integrity  OK", 26, 20)
	_screen(room, Vector3(w / 2.0 - 0.25, 3.2, 5.5), Vector3.LEFT, Vector2(1.2, 0.6), "LOCAL TIME", "", 24, 30)
	_planter(room, Vector3(-3.4, 0, 8.8))


func _build_exchange(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h, 4.6, 4.0, 0.9, 4.6)
	_boards.prices = _screen(room, Vector3(-2.6, 3.4, d - 0.05), Vector3.FORWARD, Vector2(8.2, 3.6), "STATION COMMODITY EXCHANGE", "", 64, 34)
	for i in 3:
		var label: String = ["TRADE EXECUTION\nA-01", "CONTRACTS & CLEARING\nA-02", "MARKET INFORMATION\nA-03"][i]
		var kx := -5.0 + i * 2.8
		_box(room, Vector3(2.4, 1.3, 0.8), Vector3(kx, 0.65, d - 0.6), PANEL)
		_screen(room, Vector3(kx, 1.15, d - 1.02), Vector3(0, 0.6, -1).normalized(), Vector2(1.6, 0.35), "", "", 20, 16)
		_sign(room, label, Vector3(kx, 1.75, d - 0.08), Vector3.FORWARD, 26, SCREEN_TEXT, Vector2(2.2, 0.55))
	_use(room, Vector3(-5.0, 1.0, d - 1.6), func(): return "Trade Execution A-01: press %s" % _key(), func(): _say("Selling cargo here opens once the server has station prices. The board is live."))
	_boards.depth = _console(room, Vector3(-3.5, 0, 4.0), Vector3.FORWARD, "MARKET DEPTH · ICE", "", 2.2)
	_console(room, Vector3(0.5, 0, 5.0), Vector3.FORWARD, "PORTFOLIO OVERVIEW", "Your cargo, priced live", 2.0)
	_console(room, Vector3(3.8, 0, 6.2), Vector3.FORWARD, "CONTRACT DETAILS", "", 2.0)
	_screen(room, Vector3(w / 2.0 - 0.25, 2.6, d - 3.0), Vector3.LEFT, Vector2(1.0, 2.0), "ENVIRONMENT", "STABLE\nO2 21%\n101.3 kPa", 24, 22)


func _build_jobs(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h)
	_boards.jobs = _screen(room, Vector3(0.8, 2.9, d - 0.05), Vector3.FORWARD, Vector2(8.8, 3.6), "PLANETARY BUILDER JOB BOARD", "", 64, 34)
	_screen(room, Vector3(-w / 2.0 + 0.25, 3.0, d - 2.0), Vector3.RIGHT, Vector2(1.6, 2.6), "STATION STATUS", "Orbit  STABLE\nPower  NOMINAL\nLife support  OPTIMAL\nComms  SECURE\n\nBuilder Net\nCONNECTED", 28, 22)
	# The desk with the Builder's transmission, and the console in front of the board.
	_box(room, Vector3(2.6, 0.9, 1.0), Vector3(-4.0, 0.45, 3.5), PANEL)
	_box(room, Vector3(2.8, 0.08, 1.1), Vector3(-4.0, 0.92, 3.5), TRIM, false)
	_boards.transmission = _screen(room, Vector3(-4.0, 1.5, 3.4), Vector3(0.6, 0, 1).normalized(), Vector2(1.3, 0.8), "INCOMING TRANSMISSION", "", 22, 20)
	_cyl(room, 0.1, 0.16, Vector3(-3.0, 1.04, 3.3), Color(0.2, 0.22, 0.25), false)
	_planter(room, Vector3(-5.0, 0.96, 3.5))
	_console(room, Vector3(0.8, 0, d - 3.0), Vector3.FORWARD, "DELIVERIES", "Press F to deliver cargo\nfor the open job", 2.6)
	_use(room, Vector3(0.8, 1.0, d - 3.7), _jobs_prompt, _deliver)
	# Supply contracts: pilots ask Builders of their faction for war goods.
	var contracts := Vector3(3.6, 0, d - 2.6)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, 0.4)
	_console(room, contracts, facing, "CONTRACTS", "Supply contracts\nfor war goods.\nPress F.", 1.5)
	_use(room, contracts + facing * 0.7 + Vector3(0, 1.0, 0), func(): return "Press %s for supply contracts" % _key(), func(): service.emit("contracts"))


func _build_cantina(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h, 9.0, 2.5, 0.9, 4.2)
	# The bar along the left, its glowing edge, the back shelf of bottles, and stools.
	var bx := -w / 2.0 + 2.6
	_box(room, Vector3(1.2, 1.1, 9.0), Vector3(bx, 0.55, 7.5), PANEL)
	_box(room, Vector3(1.4, 0.1, 9.2), Vector3(bx, 1.15, 7.5), TRIM, false)
	_box(room, Vector3(0.04, 0.05, 9.0), Vector3(bx + 0.7, 1.08, 7.5), CYAN, false, 3.0)
	_box(room, Vector3(0.04, 0.05, 9.0), Vector3(bx + 0.62, 0.12, 7.5), CYAN, false, 3.0)
	for z in range(4, 12, 2):
		_seat(room, Vector3(bx + 1.2, 0, z))
	var sx := -w / 2.0 + 0.5
	for y in [1.4, 2.1]:
		_box(room, Vector3(0.5, 0.06, 6.0), Vector3(sx, y, 7.5), TRIM)
		for i in 14:
			var bottle := _cyl(room, 0.07, 0.36, Vector3(sx, y + 0.21, 4.9 + i * 0.4), [Color(0.55, 0.35, 0.15), Color(0.2, 0.45, 0.3), Color(0.6, 0.6, 0.65)][i % 3], false, 0.4)
			bottle.visible = true
	_sign(room, "%s CANTINA" % _planet_name().to_upper(), Vector3(sx + 0.1, 3.4, 7.5), Vector3.RIGHT, 80)
	# The chat terminal stands on the end of the bar, facing the door.
	_box(room, Vector3(0.16, 0.5, 0.16), Vector3(bx, 1.45, 2.6), TRIM, false)
	_boards.chat = _screen(room, Vector3(bx, 2.0, 2.55), Vector3(0.25, 0.1, -1).normalized(), Vector2(1.5, 0.9), "CHANNEL: PILOTS", "", 22, 18)
	_use(room, Vector3(bx + 0.4, 1.0, 1.6), func(): return "Press %s to talk on the pilots' channel" % _chat_key(), func(): _chat.open())
	# Round tables with stools on the right, by the window.
	for t in [Vector3(3.0, 0, 5.0), Vector3(5.2, 0, 9.5), Vector3(1.5, 0, 10.5)]:
		_cyl(room, 0.12, 1.0, t + Vector3(0, 0.5, 0), TRIM, false)
		_cyl(room, 0.95, 0.1, t + Vector3(0, 1.0, 0), PANEL, true)
		_ring_line(room, 0.94, t + Vector3(0, 0.95, 0), CYAN, 0.04, 2.0)
		for k in 4:
			var a := k * TAU / 4.0 + 0.4
			_seat(room, t + Vector3(cos(a) * 1.4, 0, sin(a) * 1.4), 0.5)
	_screen(room, Vector3(-w / 2.0 + 0.25, 3.6, 3.2), Vector3.RIGHT, Vector2(1.3, 1.0), "TRAFFIC", "", 22, 18)
	# The black market: a battered terminal in the dim back corner, past the end of the bar, where
	# the Fence buys raided loot for half its value.
	var bm := Vector3(-w / 2.0 + 1.8, 0, d - 0.6)
	_box(room, Vector3(1.4, 2.0, 0.8), bm + Vector3(0, 1.0, 0), Color(0.2, 0.21, 0.23))
	_box(room, Vector3(1.0, 0.1, 0.4), bm + Vector3(0, 1.25, -0.5), TRIM, false)
	_box(room, Vector3(1.3, 0.04, 0.04), bm + Vector3(0, 0.15, -0.42), ALERT, false, 2.0)
	_boards.fence = _screen(room, bm + Vector3(0, 1.75, -0.42), Vector3.FORWARD, Vector2(1.1, 0.7), "BLACK MARKET", "", 22, 18, ALERT)
	_crate(room, Vector3(1.2, 0.9, 1.0), bm + Vector3(1.8, 0, -0.2))
	_crate(room, Vector3(1.0, 0.7, 0.9), bm + Vector3(1.9, 0.9, -0.2))
	_light(room, bm + Vector3(0, 2.6, -1.2), Color(1.0, 0.35, 0.3), 0.8, 4.0)
	_use(room, bm + Vector3(0, 1.0, -1.1), _fence_prompt, func(): Net.send({"type": "sell"}))
	_light(room, Vector3(bx, 2.6, 7.5), Color(0.35, 0.9, 1.0), 1.0, 7.0)


func _build_security(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h)
	_boards.wanted = _screen(room, Vector3(0, 2.6, d - 0.05), Vector3.FORWARD, Vector2(7.0, 3.2), "WANTED PILOTS · HIGH HEAT", "", 60, 32, ALERT)
	_screen(room, Vector3(-w / 2.0 + 0.25, 2.6, 4.0), Vector3.RIGHT, Vector2(1.6, 2.2), "STATION STATUS", "Power  NOMINAL\nLife support  NOMINAL\nDocking ring  SECURE\nCameras  ACTIVE", 28, 22)
	_boards.threat = _screen(room, Vector3(w / 2.0 - 0.25, 2.6, 4.5), Vector3.LEFT, Vector2(1.6, 1.8), "THREAT LEVEL", "", 30, 26, ALERT)
	_sign(room, "SECURITY IS OUR ORBIT", Vector3(w / 2.0 - 0.25, 4.0, 7.5), Vector3.LEFT, 30)
	for desk in [[Vector3(-2.8, 0, 4.0), "DOCKING RING OVERVIEW"], [Vector3(3.0, 0, 6.5), "SECURITY FEED"]]:
		var p: Vector3 = desk[0]
		_box(room, Vector3(2.6, 0.85, 1.1), p + Vector3(0, 0.42, 0), PANEL)
		_box(room, Vector3(2.8, 0.08, 1.2), p + Vector3(0, 0.88, 0), TRIM, false)
		_screen(room, p + Vector3(0, 1.45, 0.25), Vector3.FORWARD, Vector2(1.5, 0.8), desk[1], "", 22, 16)
		_box(room, Vector3(0.9, 0.04, 0.3), p + Vector3(0, 0.93, -0.25), TRIM, false)
		_box(room, Vector3(0.6, 0.08, 0.6), p + Vector3(0, 0.5, -1.0), Color(0.2, 0.21, 0.24), false)
		_box(room, Vector3(0.6, 0.8, 0.08), p + Vector3(0, 0.9, -1.3), Color(0.2, 0.21, 0.24), false)
		_cyl(room, 0.06, 0.5, p + Vector3(0, 0.25, -1.0), TRIM, false)
	_cyl(room, 0.07, 0.14, Vector3(-3.7, 0.99, 3.8), Color(0.92, 0.92, 0.92), false)
	_planter(room, Vector3(4.6, 0.92, 6.8))


func _build_cabins(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h)
	for i in 10:
		var s := -1 if i % 2 == 0 else 1
		var z := 3.5 + (i / 2) * 5.5
		var x := s * (w / 2.0 - 0.06)
		_box(room, Vector3(0.1, 2.6, 1.3), Vector3(x, 1.3, z), Color(0.5, 0.52, 0.55), false)
		_box(room, Vector3(0.12, 2.8, 0.06), Vector3(x, 1.4, z - 0.7), CYAN, false, 2.5)
		_box(room, Vector3(0.12, 2.8, 0.06), Vector3(x, 1.4, z + 0.7), CYAN, false, 2.5)
		_text(room, "CABIN %02d" % (i + 1), Vector3(x - s * 0.08, 2.1, z), Vector3(-s, 0, 0), 40, Color(0.2, 0.22, 0.25))
		_box(room, Vector3(0.12, 0.08, 0.35), Vector3(x - s * 0.06, 1.1, z + 0.35), TRIM, false)
		_screen(room, Vector3(x - s * 0.02, 1.5, z - 1.3), Vector3(-s, 0, 0), Vector2(0.4, 0.4), "", "", 12, 12)
		var n := i + 1
		_use(room, Vector3(x - s * 0.8, 1.0, z), func(): return "Cabin %02d" % n, func(): _say("Cabin %02d is locked. Renting a cabin is coming later." % n))
	for z in range(2, int(d), 3):
		_box(room, Vector3(w, 0.35, 0.4), Vector3(0, h - 0.17, z), TRIM, false)
		_box(room, Vector3(0.9, 0.03, 0.5), Vector3(0, h - 0.36, z + 1.5), Color(0.95, 0.97, 1.0), false, 2.0)
	for i in 6:
		for s in [-1, 1]:
			_box(room, Vector3(0.6, 0.015, 0.14), Vector3(s * 0.9, 0.008, 5.0 + i * 4.0), HAZARD, false, 0.4, 1.0, Vector3(0, s * 40.0, 0))
	_box(room, Vector3(2.6, 0.012, 1.2), Vector3(0, 0.006, 2.0), HAZARD, false, 0.4)
	_box(room, Vector3(2.4, 0.014, 1.0), Vector3(0, 0.008, 2.0), FLOOR, false)
	var arrow := _text(room, "TO CONCOURSE  <-", Vector3(0, 0.02, 2.0), Vector3.UP, 56, Color(0.15, 0.15, 0.17))
	arrow.rotate_y(PI)
	_sign(room, "DECK 3 · CREW RING", Vector3(0, 2.9, d - 0.05), Vector3.FORWARD, 32)
	_box(room, Vector3(1.6, 2.5, 0.1), Vector3(0, 1.25, d - 0.02), Color(0.5, 0.52, 0.55), false)
	_light(room, Vector3(0, h - 0.5, d * 0.5), Color(0.85, 0.92, 1.0), 0.8, 10.0)


func _build_observation(room: Node3D, w: float, d: float, h: float) -> void:
	_far_wall(room, w, d, h, 11.0, 0.0, 0.6, 4.5)
	# Railing in front of the window.
	for y in [0.55, 1.0]:
		_box(room, Vector3(10.0, 0.08, 0.08), Vector3(0, y, d - 1.2), TRIM, false)
	for x in range(-5, 6, 2):
		_box(room, Vector3(0.12, 1.05, 0.12), Vector3(x, 0.52, d - 1.2), PANEL, false)
	_box(room, Vector3(10.0, 1.05, 0.12), Vector3(0, 0.52, d - 1.2), Color(0, 0, 0), true, 0.0, 0.0)
	# The curved sofa with cushions on the right, a planter, the radar console and a stool on the left.
	for k in 4:
		var a := deg_to_rad(-20.0 + k * 22.0)
		var p := Vector3(4.6 - cos(a) * 1.2, 0, 6.0 + sin(a) * 3.0)
		var facing := Vector3(-cos(a), 0, sin(a) * 0.3).normalized()
		_bench(room, p, facing, 2.2)
		var cushion := _box(room, Vector3(0.6, 0.45, 0.18), p + Vector3(0, 0.8, 0) - facing * 0.15, Color(0.36, 0.6, 0.65), false)
		cushion.basis = _facing_basis(facing)
	_planter(room, Vector3(5.6, 0, 9.8))
	_console(room, Vector3(-4.5, 0, 4.0), Vector3(1, 0, 0.6).normalized(), "LONG RANGE", "Teal Prime system\nAll quiet", 1.8)
	_seat(room, Vector3(-3.0, 0, 6.5), 0.5)
	_screen(room, Vector3(-w / 2.0 + 0.25, 3.2, 3.0), Vector3.RIGHT, Vector2(1.0, 1.4), "VIEW", "Look down: %s" % _planet_name(), 22, 20)


## For tests and screenshots: stand somewhere in a compartment's space, looking at a point in it.
func view(slot: int, at: Vector3, look: Vector3) -> void:
	view_at(_rooms[slot] if slot >= 0 else self, at, look)


func _tick(delta: float) -> void:
	if _globe:
		_globe.rotate_y(0.12 * delta)
	if carrier_mode:
		_check_gates(delta)
	_price_time -= delta
	if _price_time <= 0.0:
		_price_time = 2.0
		_refresh_prices()


## Which compartment the player is in, from where they stand on the station's plan.
func _location() -> String:
	var p := _player.global_position
	if _rooms.has(0):
		var h: Vector3 = _rooms[0].to_local(p)
		if h.z > 0.0 and h.z < ROOMS[0][2] and absf(h.x) < ROOMS[0][1] / 2.0:
			return "Carrier Berths" if carrier_mode else ROOMS[0][0]
	var r := Vector2(p.x, p.z).length()
	if r < R_IN:
		return "Planetary Terminal Hall"
	if r < R_OUT:
		return "Concourse Ring"
	var deg := fposmod(rad_to_deg(atan2(p.z, p.x)), 360.0)
	var slot := int(round(deg / 30.0)) % 12
	return ROOMS[slot][0] if ROOMS.has(slot) else "Concourse Ring"


# --- HUD and live boards ------------------------------------------------------------------

func _on_state(_s: Dictionary) -> void:
	_planet = Net.planet(planet_id)
	if not _war.is_empty():
		_war = WarInfo.planet(planet_id)
	_refresh_boards()


func _on_chat(sender: String, _role: String, text: String) -> void:
	_chat_lines.append("<%s> %s" % [sender, text])
	if _chat_lines.size() > 5:
		_chat_lines.pop_front()
	if _boards.has("chat"):
		_boards.chat.text = "\n".join(_chat_lines)


func _sites() -> Array:
	return Net.facilities().filter(func(f): return f.planet == planet_id or Net.planet(f.planet).get("parent", "") == planet_id)


## Where a base or site sits on its planet, [lat, lon] in degrees, as the server placed it.
## Older servers didn't place them; fall back to a spot from its id.
func _surface_spot(id: String) -> Vector2:
	var surface = Net.planet(id).get("surface")
	if surface is Array and surface.size() == 2:
		return Vector2(float(surface[0]), float(surface[1]))
	var h := absi(hash(id))
	return Vector2(float(h % 100) - 50.0, float((h / 100) % 360))


func _lat_lon(id: String) -> String:
	var s := _surface_spot(id)
	var lon := wrapf(s.y, -180.0, 180.0)
	return "%d°%s %d°%s" % [absi(int(s.x)), "N" if s.x >= 0 else "S", absi(int(lon)), "E" if lon >= 0 else "W"]


func _site_name(f: Dictionary) -> String:
	var site := Net.planet(f.planet)
	return site.name if site.get("kind", "") == "satellite" else f.name


func _refresh_boards() -> void:
	if Net.state.is_empty():
		return
	var owner: String = str(_planet.get("owner", "nobody")) if _planet.get("owner") != null else "nobody"
	var sites := _sites()
	var mine := WarInfo.my_faction()
	# Terminal Hall: the planet (its base, or who holds it in the war), every site, its security
	# and whether it's under raid; the globe's markers.
	var status := []
	if _war.is_empty():
		status.append("%s's home base   %s   %s" % [owner, _lat_lon(planet_id), "SPACEPORT OPEN" if Net.has_building("spaceport", planet_id) else "NO SPACEPORT"])
	else:
		var lock := WarInfo.lock_left(_war)
		status.append("%s   held by %s, %d of %d sectors   %s%s" % [_war.name.to_upper(), WarInfo.faction_name(_war.owner) if _war.owner != null else "nobody",
			WarInfo.held(_war, _war.owner), _war.sectors.size(), WarInfo.contention(_war).to_upper(), ("   LOCKED %s" % lock.to_upper()) if lock != "" else ""])
	var ops := []
	for f in sites:
		var site := Net.planet(f.planet)
		var raided := not Net.raid_on(f.planet, f.slot).is_empty()
		var side = site.get("faction")
		var state := "UNDER RAID" if raided else ("DORMANT" if site.get("dormant", false) else "SECURE")
		status.append("%s   %s%s   %s   tier %d   %s" % [_site_name(f), site.get("owner", "?"), (" · " + WarInfo.faction_name(side)) if side != null else "", _lat_lon(f.planet), int(f.building.security), state])
		if raided:
			var r := Net.raid_on(f.planet, f.slot)
			ops.append("%s   UNDER RAID   heat %d" % [_site_name(f), int(r.get("heat", 0))])
	if sites.is_empty() and not _war.is_empty():
		status.append("No outposts on %s yet." % _war.name)
	if ops.is_empty():
		ops.append("No raids in progress.")
	_boards.hall_status.text = "\n".join(status)
	_boards.hall_ops.text = "\n".join(ops)
	# The war front: the contested worlds of the system.
	var front := []
	for wp in WarInfo.planets_in(str(Net.state.get("system", {}).get("id", "teal-prime"))):
		front.append("%-9s %-18s %-10s%s" % [wp.name, WarInfo.faction_name(wp.owner), WarInfo.contention(wp), "  LOCKED" if WarInfo.lock_left(wp) != "" else ""])
	# The fleets over the system, a Coma armada as plainly as any Builder's fleet.
	var orbit := []
	for fl in WarInfo.fleets_at(str(Net.state.get("system", {}).get("id", "teal-prime"))):
		orbit.append("%s%s" % [WarInfo.fleet_name(fl), "" if fl.status == "stationed" else " (inbound)"])
	front.append("In orbit: " + (", ".join(orbit.slice(0, 3)) + (" and %d more" % (orbit.size() - 3) if orbit.size() > 3 else "") if not orbit.is_empty() else "no fleets"))
	front.append("Your side: %s   Threat level: %s" % [WarInfo.faction_name(mine) if mine != "" else "none yet", "HIGH" if ops[0] != "No raids in progress." else "MODERATE"])
	_boards.hall_sector.text = "\n".join(front)
	for key in _boards:
		if str(key).begins_with("monitor_"):
			_boards[key].text = "\n".join(status.slice(1, 4)) if status.size() > 1 else "No sites yet"
	_refresh_globe(owner, sites)

	# Job board: this planet's jobs, posted by its Builder, then supply contracts of your side.
	var jobs := []
	for j in Net.state.get("jobs", []):
		if j.get("planet", "aster") == planet_id:
			jobs.append(j)
	jobs.reverse()
	var lines := ["Posted by: %s   LIVE" % owner, ""] if _war.is_empty() else ["No Builder lives on %s: supply contracts only." % _war.name, ""]
	for j in jobs.slice(0, 6):
		lines.append("JOB #%d // %s   reward %d CR   %d/%d   %s" % [j.id, str(j.resource).to_upper(), int(j.reward), int(j.delivered), int(j.amount), str(j.status).to_upper()])
	if jobs.is_empty() and _war.is_empty():
		lines.append("No jobs posted yet.")
	var open: Array = Net.state.get("contracts", []).filter(func(c): return c.status == "open" and c.faction == mine)
	lines.append("")
	lines.append("SUPPLY CONTRACTS · %s" % (WarInfo.faction_name(mine).to_upper() if mine != "" else "CHOOSE A FACTION TO SEE YOUR SIDE'S"))
	for c in open.slice(0, 4):
		lines.append("#%d  %s wants %s   %d/%d   %d CR" % [int(c.id), c.pilot, WarInfo.amount_of(c.item, int(c.amount)), int(c.filled), int(c.amount), int(c.reward)])
	if open.is_empty() and mine != "":
		lines.append("None open. Post one at the console.")
	_boards.jobs.text = "\n".join(lines)
	_boards.transmission.text = "%s\n%s" % [owner, "Open job waiting" if not Net.open_job(planet_id).is_empty() else "No open jobs"] if _war.is_empty() else "Sector Command\n%d contract(s) open" % open.size()

	# Security: the raid log, newest first, scored by what was taken.
	var wanted := []
	var raid_log: Array = Net.state.get("raidLog", [])
	for k in range(raid_log.size() - 1, -1, -1):
		var e: Dictionary = raid_log[k]
		if wanted.size() >= 6:
			break
		var heat := mini(99, int(e.get("value", 0)) / 50 + 20)
		wanted.append("%-12s %-24s %-10s heat %d" % [str(e.pilot), str(e.facility), str(e.outcome).to_upper(), heat])
	_boards.wanted.text = "\n".join(wanted) if not wanted.is_empty() else "No raids on record. Report sightings to Sector Command."
	_boards.threat.text = "ELEVATED\n%d raid(s) live" % (ops.size() if ops[0] != "No raids in progress." else 0) if ops[0] != "No raids in progress." else "NORMAL\nPatrols on standby"

	# The Fence: what's in your stash.
	var stash: Array = _me().get("stash", [])
	_boards.fence.text = "%d items to sell\nworth about %d CR" % [stash.size(), _stash_value() / 2] if not stash.is_empty() else "Nothing to sell"
	if not _boards.has("chat_init"):
		_boards.chat_init = true
		_boards.chat.text = "No one's said anything yet.\nPress %s to say something." % _chat_key()


## The hologram's markers: the Builder's base at a High Port, or at an orbital station every sector
## of the contested world as a small dot in its owner's colour (the capital sector bigger). Then
## every outpost, tinted by its faction (red while raided, dim while dormant), with one label per
## sector listing the outposts standing in it.
func _refresh_globe(owner: String, sites: Array) -> void:
	for child in _globe_markers.get_children():
		child.queue_free()
	if _war.is_empty():
		var home := _globe_dot(_surface_spot(planet_id), CYAN, 0.22, 4.0)
		_globe_tag(home * 1.18, "%s's base" % owner, SCREEN_TEXT, 96)
	else:
		for sec in _war.get("sectors", []):
			_globe_dot(Vector2(float(sec.lat), float(sec.lon)), WarInfo.faction_color(sec.owner), 0.17 if sec.get("capital", false) else 0.11, 1.0)
	var groups := {} # sector id (or site id) -> {"at": Vector3, "lines": [[text, colour]]}
	for f in sites:
		var site := Net.planet(f.planet)
		var raided := not Net.raid_on(f.planet, f.slot).is_empty()
		var dormant: bool = site.get("dormant", false)
		var col: Color = WarInfo.faction_color(site.faction) if site.get("faction") != null else CYAN
		var text_col := col.lightened(0.25)
		if raided:
			col = ALERT
			text_col = ALERT
		elif dormant:
			col = col.darkened(0.6)
			text_col = Color(text_col, 0.5)
		var p := _globe_dot(_surface_spot(f.planet), col, 0.15, 0.3 if dormant else 1.6)
		var key: String = str(site.get("sector", f.planet))
		if not groups.has(key):
			groups[key] = {"at": p, "lines": []}
			var sec := WarInfo.sector(_war, key)
			if not sec.is_empty():
				groups[key].lines.append([str(sec.name).to_upper(), WarInfo.faction_color(sec.owner).lightened(0.3)])
		var line := "%s · %s" % [WarInfo.short_site_name(site) if site.has("sector") else _site_name(f), site.get("owner", "?")]
		if raided:
			line += "  UNDER RAID"
		elif dormant:
			line += "  DORMANT"
		groups[key].lines.append([line, text_col])
	for key in groups:
		var lines: Array = groups[key].lines
		var base: Vector3 = groups[key].at * 1.2
		for i in lines.size():
			_globe_tag(base + Vector3(0, (lines.size() - 1 - i) * 0.32, 0), lines[i][0], lines[i][1], 80)


## A marker on the hologram at [lat, lon]; returns where it is in the globe's space.
func _globe_dot(spot: Vector2, colour: Color, radius: float, glow: float) -> Vector3:
	var lat := deg_to_rad(spot.x)
	var lon := deg_to_rad(spot.y)
	var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * 2.95
	var dot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _mat(colour, glow)
	dot.mesh = mesh
	dot.position = p
	_globe_markers.add_child(dot)
	return p


func _globe_tag(at: Vector3, text: String, colour: Color, size := 96) -> void:
	var tag := Label3D.new()
	tag.text = text
	tag.position = at
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = size
	tag.modulate = colour
	_globe_markers.add_child(tag)


## The exchange board: prices drift a little every couple of seconds.
func _refresh_prices() -> void:
	if not _boards.has("prices"):
		return
	var t := Time.get_ticks_msec() / 1000.0
	var rows := [["Water ice", "ICE-H2O", 10.0], ["Metal", "FE-ORE", 6.0], ["Alloy plate", "AL-PLT", 40.0], ["Isotope cell", "ISO-CL", 140.0],
		["Data shard", "DT-SHD", 300.0], ["Design drive", "DS-DRV", 1100.0], ["Exotic matter", "EX-MTR", 900.0]]
	var lines := ["%-14s %-8s %8s %8s %7s" % ["COMMODITY", "SYMBOL", "BID", "ASK", "24H"]]
	for i in rows.size():
		var base: float = rows[i][2]
		var wobble := sin(t * 0.3 + i * 1.7) * 0.03
		var bid := base * (1.0 + wobble)
		lines.append("%-14s %-8s %8.1f %8.1f %+6.1f%%" % [rows[i][0], rows[i][1], bid, bid * 1.03, wobble * 100.0])
	_boards.prices.text = "\n".join(lines) + "\n\nMARKET STATUS: OPEN"
	var ice := 10.0 * (1.0 + sin(t * 0.3) * 0.03)
	_boards.depth.text = "Bid %.2f   Ask %.2f\nYour ice: %d" % [ice, ice * 1.03, int(_me().get("cargo", {}).get("ice", 0))]


func _stash_value() -> int:
	var total := 0
	for k in _me().get("stash", []):
		total += int(Net.catalog.get("items", {}).get(k.item, {}).get("value", 0)) * int(k.qty)
	return total


func _jobs_prompt() -> String:
	var job := Net.open_job(planet_id)
	if job.is_empty():
		return "No open jobs on %s right now" % _planet_name()
	var have := int(_me().get("cargo", {}).get(job.resource, 0))
	if have <= 0:
		return "Job #%d wants %s. You have none." % [job.id, job.resource]
	return "Press %s to deliver %d %s for job #%d" % [_key(), have, job.resource, job.id]


func _deliver() -> void:
	var job := Net.open_job(planet_id)
	if not job.is_empty() and int(_me().get("cargo", {}).get(job.resource, 0)) > 0:
		Net.send({"type": "deliver", "job": int(job.id)})
		_say("Delivered for job #%d." % job.id)


func _fence_prompt() -> String:
	var stash: Array = _me().get("stash", [])
	if stash.is_empty():
		return "Black market: nothing of yours to buy"
	return "Black market: press %s to sell %d raided items for %d credits" % [_key(), stash.size(), _stash_value() / 2]
