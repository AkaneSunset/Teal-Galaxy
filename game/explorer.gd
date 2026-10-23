extends Node3D
## Explorer mode (PC): fly from the pilot's seat around Teal Prime, mine ice, deliver jobs,
## and raid Builders' facilities on foot (raid.gd).
## Every Builder planet has a High Port in orbit. Docking there opens the transit menu, which
## shuttles the pilot down to the planet's Star Port (jobs and the Fence) or into one of its
## facilities to raid it.
## The faction war: a pilot picks a side once (faction_picker.gd). The contested worlds (Cinder,
## Vesper, Halcyon, Morrow) have orbital stations instead, over the Builders' outposts in their
## sectors; outposts of other factions are raided from there. The War terminal (war_panel.gd)
## shows the front, the Carrier Dock market and supply contracts are in trade_panel.gd.
## Everything is built from simple shapes in code, so there are no art assets yet.
##
## The ship always sits at the scene origin and the system is drawn around it (a floating
## origin), because positions out here are far too large for 32-bit coordinates.
## See controls.gd for the bindings; Esc opens settings to change them.
##
## The fleet carrier (DEMO: the server's catalog says `carrier`): every pilot flies a 260 m carrier
## instead of the small ship. Leave seat (G) holds it still and walks you around inside it
## (carrier.gd), with space drawn around it through the windows: everything in space hangs off
## `_space`, which is turned to the ship while you're aboard so the interior can stay level.
## Docking is automated: ask for a berth (dock_request), and on dock_granted the carrier flies itself
## to its numbered berth on the station's berth ring, where the clamps take it. Aboard, the airlock
## leads into the station, where every carrier docked in your copy has a boarding door.
## Shared spaces (server/spaces.js): `_sync_space()` keeps the server told which space you're in
## (your carrier, someone else's, a station's copy, a base), and walkers.gd shows who else is there.
## Sector battles (game/battle/): while its RTS view is up (BattleView.active) everything here is
## hidden and ignores input; when it closes, the view and the controls come back.

const System := preload("res://teal_prime.gd")
const Flight := preload("res://flight.gd")
const Controls := preload("res://controls.gd")
const SkyView := preload("res://sky.gd")
const NavMap := preload("res://nav_map.gd")
const SettingsMenu := preload("res://settings_menu.gd")
const ChatBox := preload("res://chat_box.gd")
const Models := preload("res://models.gd")
const Raid := preload("res://raid.gd")
const Station := preload("res://station.gd")
const Surface := preload("res://surface.gd")
const WarInfo := preload("res://war_info.gd")
const FactionPicker := preload("res://faction_picker.gd")
const WarPanel := preload("res://war_panel.gd")
const JumpPanel := preload("res://jump_panel.gd")
const TradePanel := preload("res://trade_panel.gd")
const Carrier := preload("res://carrier.gd")
const Place := preload("res://place.gd")

const SEND_EVERY := 0.1
const MINE_EVERY := 0.4
const HUD_ICONS := {
	"boost": preload("res://ui/hud_icons/boost.png"),
	"phase": preload("res://ui/hud_icons/phase.png"),
	"mass_lock": preload("res://ui/hud_icons/mass_lock.png"),
}
const MINE_ENERGY := 1.2 # from the weapons capacitor, per tick
const MINE_RANGE := 150.0 # metres from a rock's surface
const DOCK_RANGE := 1_500.0 # metres from a High Port to dock
const DOCK_SPEED := 80.0 # m/s or slower to dock
const PORT_RADIUS := 300.0
const LOCAL_RANGE := 150_000.0 # local objects further than this aren't drawn
const ARRIVE_DISTANCE := 1_000.0
const PLANET_FLOOR := 80_000.0 # landing isn't in yet; ships are held this high
const SHIP_RADIUS := 6.0
const CARRIER_RADIUS := 60.0
const CARRIER_DOCK_RANGE := 4_000.0 # metres from a station to ask for a berth
const CARRIER_DOCK_SPEED := 150.0
const OVER_RANGE := 30_000.0 # within this of a contested world's orbital station, you're over it
const BERTHS := 32 # one copy of a station holds this many ships (server/spaces.js PADS)
const BERTH_RING := 780.0 # metres from a station's axis to a berthed carrier's middle
const BERTH_TIER := 80.0 # berths 1-16 above the station's ring, 17-32 below
const CHAIR_POSE := {"pos": [0.0, 0.45, -55.1], "yaw": 0.0, "anim": "sit"} # the pilot's chair, in carrier.gd
const WAYPOINTS_PATH := "user://waypoints.cfg"

var flight := Flight.new()
var controls: Node
var _pos: Array = System.SPAWN_POS.duplicate() # metres from the star, 64-bit
var _ship: Node3D
var _camera: Camera3D
var _cockpit_screens: Array[Label3D] = []
var _accent: StandardMaterial3D
var _sun: DirectionalLight3D
var _sky: SubViewport
var _stations := {} # planet id -> {"node", "pos", "name", "planet", "orbital"}: High Ports and orbital stations
var _docked := "" # the planet whose High Port (or base) we're landed at, or ""
var _at_spaceport := false # landed at the planet's base, on its surface, rather than in its High Port
var _dock_panel: PanelContainer
var _dock_title: Label
var _dock_list: VBoxContainer
var _field: Node3D
var _rocks := [] # {"node": Node3D, "radius": float}
var _dust: MultiMeshInstance3D
var _dust_points := PackedVector3Array()
var _others := {} # id -> {"node": Node3D, "pos": Array, "shown": Array}
var _waypoints := [] # {"id", "name", "pos"}
var _raid: Node3D # the on-foot raid while one is running
var _raid_from := "" # the station (a High Port or an orbital, by planet id) the raid left from, to return to
var _station: Node3D # where the ship is landed: the High Port's hangar (station.gd) or a base (surface.gd)
var _menu_standing := false # the ship's menu is up over the place while you stand (the transit terminal)
var _world_env: WorldEnvironment
var _sky_layer: CanvasLayer
var _hud_layer: CanvasLayer
var _route: Array = []
var _space: Node3D # everything out in space: stations, the field, dust, the sun, other ships
var _cockpit: Node3D # the pilot's seat: dash, struts and monitors around the camera
var _hull: Node3D # your fleet carrier, seen from its bridge (the demo's ship)
var _hull_side := "-" # the faction it's painted for
var _chase: Camera3D # the outside view (V), and the docking approach
var _outside := false
var _carrier := false # flying a fleet carrier (Net.catalog.carrier, the demo)
var _berth := {} # the pad the server gave us: {"station", "copy", "pad"}, "local" when it didn't answer
var _dock_wait := "" # the station we asked to dock at, waiting for dock_granted
var _dock_wait_time := 0.0
var _land_wait := "" # the base we asked for a Star Port berth at, waiting for berth_granted
var _land_wait_time := 0.0
var _land_problem := "" # why the last land_request was refused (the berths are full, say)
var _sell_qty := 1 # how many to sell to a Builder at once
var _approach := {} # the automated docking approach while it flies: {"station", "t", "legs"}
var _hold_rate := 0.0 # m/s² the carrier sheds its speed at while you're out of the chair
var _space_id := "" # the shared space the server has us in ("ship:Akane", "station:cinder", ...)
var _boarding := "" # whose carrier we asked to board, until the server answers
var _boarding_time := 0.0
var _crew := {} # aboard someone else's carrier: {"owner", "pos", "basis"} (your own ship's, to go back to)
var _at_station := "" # the station you're walking in, off a carrier (maybe not where yours is docked), or ""
var _battle := false # a sector battle's RTS view is up
var _battle_env: Array = [] # [node, parent] of world environments taken out for it
var _seat_button: Button

var _hud: Control
var _info: Label
var _flight_info: Label
var _prompt: Label
var _hint: Label
var _phase_tint: ColorRect
var _nav: Control
var _settings: Control
var _picker: Control # the faction choice, for a pilot with no side yet
var _picker_dismissed := false # "Not now": the ship's menu offers it again
var _war_panel: Control
var _jump_panel: Control # the carrier's galaxy map (GALAXY MAP terminal): FTL jumps
var _jump := {} # a jump under way: {"system", "planet", "owner", "left", "total", "arrived"}
var _jump_veil: ColorRect
var _jump_text: Label
const JUMP_FLASH_S := 1.2 # the flash out of the jump
var _trade: Control # the Carrier Dock market and supply contracts
var _refusal: PanelContainer # why the server turned this pilot away (a Coma character without the admin key)
var _refusal_text: Label
var _chat: VBoxContainer
var _message := ""
var _message_time := 0.0
var _send_timer := 0.0
var _mine_timer := 0.0
var _nav_timer := 0.0


func _ready() -> void:
	controls = Controls.new()
	add_child(controls)
	flight.drift = controls.drift_default
	_space = Node3D.new()
	_space.name = "Space"
	add_child(_space)
	_build_sky()
	_build_local_space()
	_build_ship()
	_build_hud()
	_load_waypoints()

	Net.state_changed.connect(_on_state)
	Net.ship_moved.connect(_on_ship_moved)
	Net.ship_left.connect(_on_ship_left)
	Net.server_error.connect(func(reason):
		_refresh_refusal()
		if Net.refused == "":
			_say("Server: " + reason))
	Net.connection_changed.connect(func(_on): _refresh_refusal())
	Net.raid_event.connect(_on_raid_event)
	Net.message.connect(_on_net_message)
	controls.capture_mouse()


# --- World -------------------------------------------------------------------

func _build_sky() -> void:
	_sky = SkyView.new()
	_sky.size = get_viewport().get_visible_rect().size
	add_child(_sky)
	get_viewport().size_changed.connect(func(): _sky.size = get_viewport().get_visible_rect().size)
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	_sky_layer = layer
	var rect := TextureRect.new()
	rect.texture = _sky.get_texture()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(rect)

	# The local scene draws over the sky.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.24, 0.32)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	_world_env = world

	_sun = DirectionalLight3D.new()
	_sun.light_energy = 1.2
	_sun.directional_shadow_max_distance = 160.0
	_space.add_child(_sun)


func _build_local_space() -> void:
	_add_station("aster", System.PORT_NAME, System.PORT_POS)

	_field = Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 # same field for every player
	for i in 40:
		var radius := rng.randf_range(15.0, 90.0)
		var rock := Models.ice_asteroid(radius, i + 1)
		rock.position = Vector3(rng.randf_range(-1500, 1500), rng.randf_range(-400, 400), rng.randf_range(-1500, 1500))
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		_field.add_child(rock)
		_rocks.append({"node": rock, "radius": radius})
	var field_beacon := Models.nav_beacon()
	field_beacon.scale = Vector3.ONE * 4.0
	field_beacon.position = Vector3(0, -30, 0)
	_field.add_child(field_beacon)
	_space.add_child(_field)

	# Dust drifting past the canopy, so speed can be felt with nothing else nearby.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := QuadMesh.new()
	dot.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = mat
	mm.mesh = dot
	mm.instance_count = 400
	for i in mm.instance_count:
		_dust_points.append(Vector3(rng.randf_range(-200, 200), rng.randf_range(-200, 200), rng.randf_range(-200, 200)))
	_dust = MultiMeshInstance3D.new()
	_dust.multimesh = mm
	_space.add_child(_dust)


## A High Port: the orbital station over a Builder planet, where pilots dock to go down to the surface.
## `orbital`: a contested world's station (Cinder Orbital), the same build, with no base below it.
func _add_station(planet_id: String, station_name: String, pos: Array, orbital := false) -> void:
	var port := Node3D.new()
	var hub := _mesh(CylinderMesh.new(), Color(0.55, 0.58, 0.62))
	hub.mesh.top_radius = 60
	hub.mesh.bottom_radius = 60
	hub.mesh.height = 240
	port.add_child(hub)
	var ring := _mesh(TorusMesh.new(), Color(0.7, 0.72, 0.75))
	ring.mesh.inner_radius = 230
	ring.mesh.outer_radius = 280
	ring.mesh.rings = 64
	ring.name = "Ring"
	port.add_child(ring)
	for i in 4:
		var spoke := _mesh(BoxMesh.new(), Color(0.5, 0.52, 0.55))
		spoke.mesh.size = Vector3(460, 14, 14)
		spoke.rotation.y = i * PI / 4.0
		ring.add_child(spoke)
	for side in [-1, 1]:
		var beacon := Models.nav_beacon()
		beacon.scale = Vector3.ONE * 2.0
		beacon.position = Vector3(45 * side, 122, 45)
		port.add_child(beacon)
	var pad := _mesh(BoxMesh.new(), Color(0.95, 0.6, 0.2), true)
	pad.mesh.size = Vector3(70, 4, 70)
	pad.position = Vector3(0, 122, 0)
	port.add_child(pad)
	var tag := Label3D.new()
	tag.text = station_name
	tag.position = Vector3(0, 340, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0006
	tag.font_size = 48
	tag.no_depth_test = true
	tag.name = "Tag"
	port.add_child(tag)
	_space.add_child(port)
	_stations[planet_id] = {"node": port, "pos": pos, "name": station_name, "planet": planet_id, "orbital": orbital}
	if _carrier:
		_add_berths(port)


## The berth ring round a station, for fleet carriers: 32 docking arms reaching out from its ring,
## 16 above it and 16 below, each ending in a numbered clamp cradle a carrier lies alongside.
func _add_berths(port: Node3D) -> void:
	if port.has_node("Berths"):
		return
	var ring := Node3D.new()
	ring.name = "Berths"
	port.add_child(ring)
	for tier in 2:
		var y := BERTH_TIER if tier == 0 else -BERTH_TIER
		var torus := _mesh(TorusMesh.new(), Color(0.45, 0.48, 0.52))
		torus.mesh.inner_radius = BERTH_RING - 52.0
		torus.mesh.outer_radius = BERTH_RING - 44.0
		torus.mesh.rings = 96
		torus.position.y = y
		ring.add_child(torus)
	for pad in range(1, BERTHS + 1):
		var b := _berth_frame(pad)
		var out: Vector3 = b.out
		var arm_from := 280.0
		var arm_to := BERTH_RING - 40.0
		var arm := _mesh(BoxMesh.new(), Color(0.5, 0.52, 0.56))
		arm.mesh.size = Vector3(arm_to - arm_from, 8, 8)
		arm.position = out * (arm_from + arm_to) / 2.0 + Vector3(0, b.hull.y, 0)
		arm.rotation.y = -atan2(out.z, out.x)
		ring.add_child(arm)
		var strut := _mesh(BoxMesh.new(), Color(0.4, 0.42, 0.46))
		strut.mesh.size = Vector3(10, absf(b.hull.y) + 4.0, 10)
		strut.position = out * arm_from + Vector3(0, b.hull.y / 2.0, 0)
		ring.add_child(strut)
		# The cradle: a collar where the arm meets the carrier's port airlock, with lights.
		var cradle := _mesh(BoxMesh.new(), Color(0.32, 0.34, 0.38))
		cradle.mesh.size = Vector3(6, 22, 40)
		cradle.position = b.hull + out * -40.0 + Vector3(0, -2, 0)
		cradle.basis = b.basis
		ring.add_child(cradle)
		var lamp := _mesh(BoxMesh.new(), Color(1.0, 0.6, 0.2), true)
		lamp.mesh.size = Vector3(6.4, 1.6, 42)
		lamp.position = cradle.position + Vector3(0, 11.5, 0)
		lamp.basis = b.basis
		ring.add_child(lamp)
		var tag := Label3D.new()
		tag.text = "%02d" % pad
		tag.position = b.hull + out * -40.0 + Vector3(0, 34 if b.hull.y > 0 else -30, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.25
		tag.font_size = 64
		tag.outline_size = 8
		tag.modulate = Color(1.0, 0.75, 0.35)
		ring.add_child(tag)


## A berth's place round its station: {"hull": the carrier's middle from the station, "basis": how
## it lies (port side to the station, bow round the ring), "out": straight out from the station}.
func _berth_frame(pad: int) -> Dictionary:
	var tier := 0 if pad <= 16 else 1
	var a := deg_to_rad(((pad - 1) % 16) * 22.5 + tier * 11.25)
	var out := Vector3(cos(a), 0, sin(a))
	var hull := out * BERTH_RING + Vector3(0, BERTH_TIER if tier == 0 else -BERTH_TIER, 0)
	return {"hull": hull, "basis": Basis(out, Vector3.UP, out.cross(Vector3.UP)), "out": out}


## Where a carrier berthed at `pad` has its bridge (its position in space), 64-bit.
func _berth_pos(station_id: String, pad: int) -> Array:
	var b := _berth_frame(pad)
	var hull: Vector3 = b.hull
	var basis: Basis = b.basis
	return System.offset(_stations[station_id].pos, hull + basis * Models.CARRIER_BRIDGE)


## Every Builder home planet gets a High Port; planets beyond Aster are added to the sky as they appear.
## Every contested world of the system gets its orbital station once the war map arrives.
func _sync_stations() -> void:
	if not System.home():
		for wp in WarInfo.planets_in(System.current):
			if not _stations.has(wp.id) and not System.builder_planet(wp.id).is_empty():
				_add_station(wp.id, System.orbital_name(wp.name), System.orbital_pos(wp.id), true)
		return
	var index := 0
	for p in Net.state.system.planets:
		if p.get("kind", "") == "satellite" or p.id == "aster":
			continue
		if System.builder_planet(p.id).is_empty():
			var body := System.home_planet(p.id, p.name, index)
			System.homes.append(body)
			_sky.add_body(body)
		index += 1
		if not _stations.has(p.id):
			_add_station(p.id, System.station_name(p.name), System.station_pos(p.id))
	for wp in WarInfo.planets_in(System.current):
		if not _stations.has(wp.id) and not System.builder_planet(wp.id).is_empty():
			_add_station(wp.id, System.orbital_name(wp.name), System.orbital_pos(wp.id), true)


func _mesh(mesh: Mesh, color: Color, glow := false) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow:
		m.emission_enabled = true
		m.emission = color
	mesh.material = m
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _build_ship() -> void:
	# The pilot's seat. The camera never leaves it.
	_ship = Node3D.new()
	add_child(_ship)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = LOCAL_RANGE
	_camera.fov = 75
	_ship.add_child(_camera)
	_camera.make_current()
	_chase = Camera3D.new()
	_chase.near = 0.5
	_chase.far = LOCAL_RANGE
	_chase.fov = 60
	_ship.add_child(_chase)
	_cockpit = Node3D.new()
	_ship.add_child(_cockpit)

	var frame := Color(0.12, 0.13, 0.15)
	var dash := _mesh(BoxMesh.new(), frame)
	dash.mesh.size = Vector3(1.7, 0.4, 0.55)
	dash.position = Vector3(0, -0.72, -0.95)
	dash.rotation_degrees.x = -18
	_cockpit.add_child(dash)
	_accent = StandardMaterial3D.new()
	_accent.emission_enabled = true
	_accent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(1.6, 0.01, 0.02)
	strip_mesh.material = _accent
	strip.mesh = strip_mesh
	strip.position = Vector3(0, 0.205, -0.26)
	dash.add_child(strip)
	for side in [-1, 1]:
		var strut := _mesh(BoxMesh.new(), frame)
		strut.mesh.size = Vector3(0.06, 1.6, 0.06)
		strut.position = Vector3(0.95 * side, 0.05, -1.0)
		strut.rotation_degrees.z = -14 * side
		_cockpit.add_child(strut)
	var top := _mesh(BoxMesh.new(), frame)
	top.mesh.size = Vector3(1.8, 0.06, 0.06)
	top.position = Vector3(0, 0.82, -1.05)
	_cockpit.add_child(top)

	# Two dashboard monitors: ship systems on the left, navigation on the right.
	for x in [-0.4, 0.4]:
		var panel := _mesh(QuadMesh.new(), Color(0.02, 0.04, 0.05))
		panel.mesh.size = Vector2(0.62, 0.2)
		panel.position = Vector3(x, -0.43, -0.74)
		panel.rotation_degrees.x = -32
		_cockpit.add_child(panel)
		var screen := Label3D.new()
		screen.position = Vector3(0, 0, 0.002)
		screen.pixel_size = 0.0007
		screen.font_size = 40
		screen.outline_size = 0
		screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		screen.width = 840
		screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(screen)
		_cockpit_screens.append(screen)
	_place_chase()


## The outside view's camera: behind and above the ship, looking along it.
func _place_chase() -> void:
	var centre := -Models.CARRIER_BRIDGE if _carrier else Vector3.ZERO
	var back := Vector3(150, 95, 380) if _carrier else Vector3(0, 6, 24)
	_chase.position = centre + back
	_chase.look_at_from_position(_chase.position, centre + Vector3(0, 0, -60 if _carrier else -6), Vector3.UP)


func _set_outside(on: bool) -> void:
	_outside = on
	(_chase if on else _camera).make_current()


## The demo's fleet carrier, once the server says pilots fly one: the heavier flight model, the
## hull under the bridge, the berth rings round the stations, and other pilots drawn as carriers.
func _apply_ship_class() -> void:
	if Net.catalog.get("carrier", false) != true:
		return
	if not _carrier:
		_carrier = true
		flight.stats = Flight.CARRIER
		for id in _stations:
			_add_berths(_stations[id].node)
		for id in _others:
			_set_other_model(_others[id])
		_place_chase()
	var side := WarInfo.my_faction()
	if side != _hull_side:
		_hull_side = side
		if _hull:
			_hull.queue_free()
		_hull = Models.fleet_carrier(WarInfo.faction_color(side) if side != "" else Models.TEAL)
		_hull.position = -Models.CARRIER_BRIDGE
		_ship.add_child(_hull)


## Another pilot's ship model: a carrier (drawn so the node is at its bridge) or the small ship.
func _set_other_model(o: Dictionary) -> void:
	var node: Node3D = o.node
	for child in node.get_children():
		if child.name != "Tag":
			child.queue_free()
	var tag: Label3D = node.get_node("Tag")
	if _carrier:
		var side = Net.state.get("pilots", {}).get(o.name, {}).get("faction") if not Net.state.is_empty() else null
		var hull := Models.fleet_carrier(WarInfo.faction_color(side) if side != null else Models.TEAL)
		hull.position = -Models.CARRIER_BRIDGE
		node.add_child(hull)
		tag.position = Vector3(0, 60, 0)
	else:
		node.add_child(Models.starter_ship())
		tag.position = Vector3(0, 10, 0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_layer = layer
	_phase_tint = ColorRect.new()
	_phase_tint.color = Color(0.3, 0.5, 1.0, 0.07)
	_phase_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_tint.visible = false
	layer.add_child(_phase_tint)

	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)

	_info = Label.new()
	_info.position = Vector2(16, 16)
	_hud.add_child(_info)
	_flight_info = Label.new()
	_flight_info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_flight_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_flight_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_flight_info.position -= Vector2(24, 24)
	_flight_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_flight_info)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 150
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", 20)
	_hud.add_child(_prompt)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.position += Vector2(-16, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hud.add_child(_hint)
	_seat_button = Button.new()
	_seat_button.text = "Leave seat (G)"
	_seat_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_seat_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_seat_button.position += Vector2(-16, 48)
	_seat_button.visible = false
	_seat_button.focus_mode = Control.FOCUS_NONE
	_seat_button.pressed.connect(_leave_helm)
	_hud.add_child(_seat_button)

	_chat = ChatBox.new()
	_chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat.position += Vector2(16, -190)
	layer.add_child(_chat)
	_chat.opened.connect(_refresh_focus)
	_chat.closed.connect(_refresh_focus)

	_nav = NavMap.new()
	_nav.visible = false
	layer.add_child(_nav)
	_nav.route_changed.connect(func(r): _route = r.duplicate())
	_nav.waypoint_added.connect(_add_waypoint)
	_nav.waypoint_removed.connect(_remove_waypoint)
	_nav.war_planet_picked.connect(func(id): _nav.visible = false; _open_war(id))

	var dock_layer := CanvasLayer.new()
	dock_layer.layer = 5
	add_child(dock_layer)
	_build_dock_panel(dock_layer)

	# The war's screens, over everything else (the ship's menu included).
	var war_layer := CanvasLayer.new()
	war_layer.layer = 6
	add_child(war_layer)
	_war_panel = WarPanel.new()
	_war_panel.visible = false
	war_layer.add_child(_war_panel)
	_jump_panel = JumpPanel.new()
	_jump_panel.visible = false
	war_layer.add_child(_jump_panel)
	_jump_panel.closed.connect(_close_panel)
	_jump_panel.jump_requested.connect(_request_jump)
	# The jump itself: the view washes out to the FTL tunnel's blue, then back in at the far end.
	_jump_veil = ColorRect.new()
	_jump_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_jump_veil.color = Color(0.55, 0.75, 1.0, 0.0)
	_jump_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	war_layer.add_child(_jump_veil)
	_jump_text = Label.new()
	_jump_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_jump_text.offset_left = -500
	_jump_text.offset_right = 500
	_jump_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_jump_text.add_theme_font_size_override("font_size", 30)
	_jump_text.add_theme_color_override("font_color", Color(0.05, 0.1, 0.2))
	_jump_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	war_layer.add_child(_jump_text)
	_war_panel.closed.connect(_close_panel)
	_war_panel.wants_faction.connect(_show_picker)
	_war_panel.wants_battles.connect(_open_battles)
	_trade = TradePanel.new()
	_trade.visible = false
	war_layer.add_child(_trade)
	_trade.closed.connect(_close_panel)
	_trade.wants_faction.connect(_show_picker)
	_picker = FactionPicker.new()
	_picker.visible = false
	war_layer.add_child(_picker)
	_picker.dismissed.connect(func(): _picker_dismissed = true; _close_panel())

	_build_refusal(layer)

	_settings = SettingsMenu.new()
	_settings.controls = controls
	_settings.visible = false
	layer.add_child(_settings)
	_settings.closed.connect(func(): _settings.visible = false; _refresh_focus())


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _battle:
		return
	if _panel_open() and (event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel")):
		if _picker.visible:
			_picker_dismissed = true
		_close_panel()
		get_viewport().set_input_as_handled()
		return
	if _panel_open():
		return
	if _station and _menu_standing and (event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel")):
		_close_standing_menu()
		get_viewport().set_input_as_handled()
		return
	if _raid or _station:
		return
	if _settings.visible:
		if event.is_action_pressed("menu") and not _settings.is_rebinding():
			_settings.visible = false
			_refresh_focus()
		return
	if _chat.is_typing():
		if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
			_chat.close()
			get_viewport().set_input_as_handled()
		return
	if _nav.visible:
		if event.is_action_pressed("nav_map") or event.is_action_pressed("menu"):
			_nav.visible = false
			_refresh_focus()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		controls.capture_mouse()
	if event.is_action_pressed("chat"):
		_chat.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		_settings.visible = true
		_refresh_focus()
	elif event.is_action_pressed("nav_map"):
		_nav.visible = true
		_nav_timer = 0.0
		_refresh_focus()
	elif event.is_action_pressed("drift") and not controls.drift_hold:
		flight.drift = not flight.drift
		_say("Drift on: flight assist off" if flight.drift else "Flight assist on")
	elif event.is_action_pressed("pip_sys"):
		flight.add_pip(Flight.SYS)
	elif event.is_action_pressed("pip_eng"):
		flight.add_pip(Flight.ENG)
	elif event.is_action_pressed("pip_wep"):
		flight.add_pip(Flight.WEP)
	elif event.is_action_pressed("pip_reset"):
		flight.reset_pips()
	elif event.is_action_pressed("leave_seat"):
		_leave_helm()
	elif event.is_action_pressed("outside_view") and _approach.is_empty():
		_set_outside(not _outside)


func _refresh_focus() -> void:
	if _station or _raid:
		return # on foot the place looks after the mouse, and the ship's menu frees it
	var overlay: bool = _settings.visible or _nav.visible or _dock_panel.visible or _panel_open()
	controls.enabled = not overlay and not _chat.is_typing()
	if overlay:
		controls.release_mouse()
	else:
		controls.capture_mouse()


# --- Flying ------------------------------------------------------------------

func _process(delta: float) -> void:
	_jump_step(delta)
	_check_battle()
	_sync_space(delta)
	if _land_wait != "":
		_land_wait_time -= delta
		if _land_wait_time <= 0.0:
			_berth_granted(_land_wait, 0) # no answer (an older server): land on the first berth, alone
	if _battle:
		_send_ship(delta)
		return
	if _raid:
		return
	if _station is Carrier:
		_aboard(delta)
		return
	if _station:
		return
	if controls.drift_hold and controls.enabled:
		flight.drift = Input.is_action_pressed("drift")
	var input: Dictionary = controls.read() if _approach.is_empty() else {}
	if _docked != "":
		flight.velocity = Vector3.ZERO
		flight.throttle = 0.0
	if _approach.is_empty():
		for said in flight.step(input, _flight_env(), delta):
			_say(said)
		_pos = System.offset(_pos, flight.velocity * delta)
		_collide()
	else:
		_approach_step(delta)
	_ship.basis = flight.basis
	if flight.hull <= 0.0:
		_respawn()

	_place_world(delta)
	for stop in _route:
		var pilot_id: int = int(stop.id.substr(6)) if stop.id.begins_with("pilot-") else 0
		if _others.has(pilot_id):
			stop.pos = _others[pilot_id].shown
	_check_arrival()
	_send_ship(delta)

	_mine_timer -= delta
	if _dock_wait != "":
		_dock_wait_time -= delta
		_prompt.text = "Asked %s for a berth..." % _stations[_dock_wait].name
		if _dock_wait_time <= 0.0:
			_berth_anyway(_dock_wait)
	elif not _approach.is_empty():
		_prompt.text = _approach_text()
	elif _docked == "":
		_interact()
	else:
		_prompt.text = ""
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = 0.25
		_nav.refresh(_nav_items(), _pos, flight.forward())
	_update_hud(delta)


## Tells the others where your ship is (and the contested world it's over, for sector battles).
## Aboard someone else's carrier, yours is where you left it, clamped at its berth.
func _send_ship(delta: float) -> void:
	_send_timer -= delta
	if _send_timer > 0.0 or Net.refused != "": # a pilot the server turned away has nobody to tell
		return
	var crew := not _crew.is_empty()
	var still := crew or _station != null or _battle or (_docked != "" and _approach.is_empty())
	_send_timer = SEND_EVERY * (5.0 if still else 1.0)
	var r: Vector3 = (_crew.basis if crew else flight.basis).get_euler()
	var msg := {"type": "ship", "pos": _crew.pos if crew else _pos, "rot": [r.x, r.y, r.z], "system": str(_crew.get("system", System.current)) if crew else System.current}
	var over := _over_planet()
	if crew:
		over = _docked if not WarInfo.planet(_docked).is_empty() else ""
	if over != "":
		msg.over = over
	Net.send(msg)


## The contested world whose orbit you're in: docked at its orbital station, or within 30 km of it.
func _over_planet() -> String:
	if _docked != "" and not WarInfo.planet(_docked).is_empty():
		return _docked
	for id in _stations:
		if _stations[id].orbital and System.distance(_stations[id].pos, _pos) < OVER_RANGE:
			return id
	return ""


func _flight_env() -> Dictionary:
	var altitude := INF
	for body in System.bodies():
		altitude = minf(altitude, System.distance(body.pos, _pos) - body.radius)
	return {
		"mass_locked": _near_station(Flight.MASS_LOCK_DISTANCE) != "",
		"altitude": altitude,
		"dest_distance": _dest_distance(),
	}


## Draws space around the ship. `view` is how the ship lies (flying: nothing to undo, since the
## ship turns; aboard: space is turned the other way, so the interior stays level) and `cam` is the
## camera looking out, for the sky.
func _place_world(delta: float, view := Basis(), cam: Camera3D = null) -> void:
	if cam == null:
		cam = _chase if _outside else _camera
	_space.basis = view.inverse()
	for id in _stations:
		var port: Node3D = _stations[id].node
		port.position = System.diff(_stations[id].pos, _pos)
		port.visible = port.position.length() < LOCAL_RANGE
		port.get_node("Ring").rotate_y(0.03 * delta)
	_field.position = System.diff(System.FIELD_POS, _pos)
	_field.visible = System.home() and _field.position.length() < LOCAL_RANGE

	for id in _others:
		var o: Dictionary = _others[id]
		var t := minf(1.0, delta * 10.0)
		o.shown = [lerpf(o.shown[0], o.pos[0], t), lerpf(o.shown[1], o.pos[1], t), lerpf(o.shown[2], o.pos[2], t)]
		o.node.position = System.diff(o.shown, _pos)
		# Carriers berthed in another copy of the station you're docked at lie where others of
		# your copy do: only your copy's are drawn.
		var elsewhere: bool = _docked != "" and not o.get("berth", {}).is_empty() and str(o.berth.get("station", "")) == _docked and int(o.berth.get("copy", 1)) != int(_berth.get("copy", 1))
		var here: bool = str(o.get("system", "teal-prime")) == System.current # another system's ships aren't here
		o.node.visible = here and o.node.position.length() < LOCAL_RANGE and o.name != _crew.get("owner", "") and not elsewhere

	var to_star := System.diff(System.star().pos, _pos).normalized()
	_sun.basis = Basis.looking_at(-to_star, Vector3.UP if absf(to_star.y) < 0.99 else Vector3.RIGHT)
	_sky.follow(_pos, view * cam.global_basis)
	if _station:
		return # aboard: no dust or phase tint, the view's the interior's own

	# Dust: hidden in the phase-shift drive, where it would only flicker.
	var phase := flight.mode == Flight.Mode.PHASE
	_dust.visible = not phase
	_phase_tint.visible = phase
	_camera.fov = lerpf(_camera.fov, 80.0 if phase else 75.0, minf(1.0, delta * 2.0))
	if not phase:
		var mm := _dust.multimesh
		for i in _dust_points.size():
			var p := _dust_points[i] - flight.velocity * delta
			p = Vector3(fposmod(p.x + 200, 400) - 200, fposmod(p.y + 200, 400) - 200, fposmod(p.z + 200, 400) - 200)
			_dust_points[i] = p
			mm.set_instance_transform(i, Transform3D(Basis(), p))


func _collide() -> void:
	var spheres := []
	for rock in _rocks:
		spheres.append([System.diff(System.FIELD_POS, _pos) + rock.node.position, rock.radius])
	for id in _stations:
		spheres.append([System.diff(_stations[id].pos, _pos), PORT_RADIUS])
	for s in spheres:
		var rel: Vector3 = s[0]
		var reach: float = s[1] + (CARRIER_RADIUS if _carrier else SHIP_RADIUS)
		var d := rel.length()
		if d >= reach or d < 0.001:
			continue
		var n := rel / d
		_pos = System.offset(_pos, -n * (reach - d))
		var impact := flight.velocity.dot(n)
		if impact > 0.0:
			flight.velocity -= n * impact * 1.4
			if impact > 15.0:
				flight.damage(impact * 0.5)
				_say("Collision! Shields %d%%" % flight.shields)

	for body in System.bodies():
		var floor_r: float = body.radius + (PLANET_FLOOR if body.kind == "planet" else body.radius * 0.5)
		var d := System.distance(body.pos, _pos)
		if d < floor_r:
			var n := System.diff(body.pos, _pos).normalized()
			_pos = System.offset(_pos, -n * (floor_r - d))
			flight.velocity -= n * maxf(0.0, flight.velocity.dot(n)) * 1.4
			flight.damage(10.0 * get_process_delta_time() * 10.0)
			_say("Too close to %s: landing isn't built yet" % body.name if body.kind == "planet" else "Too close to the star!")


func _respawn() -> void:
	if not System.home():
		_enter_system("teal-prime")
	_pos = System.SPAWN_POS.duplicate()
	flight.repair()
	flight.basis = Basis()
	_say("Your ship was destroyed. You're back at %s." % System.PORT_NAME)


# --- Navigation ----------------------------------------------------------------

func _nav_items() -> Array:
	var items := []
	for body in System.bodies():
		items.append({"id": body.id, "name": body.name, "kind": "landmark", "pos": body.pos,
			"radius": body.radius, "standoff": body.radius + 300_000.0})
	for id in _stations:
		var st: Dictionary = _stations[id]
		items.append({"id": "port-" + id, "name": st.name, "kind": "landmark", "pos": st.pos, "standoff": 5_500.0, "local": id == "aster", "near": id})
	if System.home():
		items.append({"id": "field", "name": System.FIELD_NAME, "kind": "landmark", "pos": System.FIELD_POS, "standoff": 2_500.0, "local": true})
	for w in _waypoints:
		items.append({"id": w.id, "name": w.name, "kind": "waypoint", "pos": w.pos, "standoff": 0.0})
	for id in _others:
		if str(_others[id].get("system", "teal-prime")) == System.current:
			items.append({"id": "pilot-%d" % id, "name": _others[id].name, "kind": "pilot", "pos": _others[id].shown, "standoff": 500.0})
	return items


func _set_route(route: Array) -> void:
	_route = route
	_nav.set_route(route)


func _dest_distance() -> float:
	if _route.is_empty():
		return -1.0
	var dest: Dictionary = _route[0]
	return maxf(0.0, System.distance(dest.pos, _pos) - dest.get("standoff", 0.0))


func _check_arrival() -> void:
	if _route.is_empty() or flight.mode == Flight.Mode.PHASE:
		return
	if _dest_distance() < ARRIVE_DISTANCE:
		var done: Dictionary = _route.pop_front()
		_say("Arrived at %s" % done.name + (". Next: %s" % _route[0].name if not _route.is_empty() else ""))
		_nav.set_route(_route.duplicate())


func _load_waypoints() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WAYPOINTS_PATH) == OK:
		_waypoints = cfg.get_value("waypoints", "list", [])


func _save_waypoints() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("waypoints", "list", _waypoints)
	cfg.save(WAYPOINTS_PATH)


func _add_waypoint() -> void:
	var n := _waypoints.size() + 1
	_waypoints.append({"id": "wp-%d" % Time.get_ticks_msec(), "name": "Waypoint %d" % n, "pos": _pos.duplicate()})
	_save_waypoints()
	_nav.refresh(_nav_items(), _pos, flight.forward())
	_say("Waypoint %d saved" % n)


func _remove_waypoint(id: String) -> void:
	_waypoints = _waypoints.filter(func(w): return w.id != id)
	_route = _route.filter(func(r): return r.id != id)
	_save_waypoints()
	_nav.set_route(_route.duplicate())
	_nav.refresh(_nav_items(), _pos, flight.forward())


# --- Mining and jobs -------------------------------------------------------------

func _interact() -> void:
	var holding: bool = controls.enabled and Input.is_action_pressed("interact")
	if _near_rock():
		if flight.mode != Flight.Mode.SUBLIGHT:
			_prompt.text = "Drop to sub-light to mine"
		elif flight.capacitor[Flight.WEP] < MINE_ENERGY:
			_prompt.text = "Mining laser recharging: put power to weapons"
		else:
			_prompt.text = "Hold %s to mine ice" % controls.binding_text("interact", false)
			if holding and _mine_timer <= 0 and flight.draw(Flight.WEP, MINE_ENERGY):
				_mine_timer = MINE_EVERY
				Net.send({"type": "collect", "resource": "ice", "amount": 1})
	elif _carrier and _near_station(CARRIER_DOCK_RANGE) != "":
		var id := _near_station(CARRIER_DOCK_RANGE)
		if flight.speed() > CARRIER_DOCK_SPEED:
			_prompt.text = "Slow below %d m/s to dock at %s" % [CARRIER_DOCK_SPEED, _stations[id].name]
		else:
			_prompt.text = "Press %s to request docking at %s: the carrier flies itself to its berth" % [controls.binding_text("interact", false), _stations[id].name]
			if holding:
				_request_dock(id)
	elif not _carrier and _near_station(DOCK_RANGE) != "":
		var id := _near_station(DOCK_RANGE)
		if flight.speed() > DOCK_SPEED:
			_prompt.text = "Slow below %d m/s to dock at %s" % [DOCK_SPEED, _stations[id].name]
		else:
			_prompt.text = "Press %s to dock at %s" % [controls.binding_text("interact", false), _stations[id].name]
			if holding:
				dock(id)
	else:
		_prompt.text = ""


## The planet whose High Port is within `range_m`, or "".
func _near_station(range_m: float) -> String:
	for id in _stations:
		if System.distance(_stations[id].pos, _pos) < range_m:
			return id
	return ""


# --- Docking and surface transit ----------------------------------------------------------

## Lands at a planet's High Port: the ship sets down on pad 06 in the hangar and you're in the
## pilot's seat, with the ship's menu up. The server is asked for a pad too (dock_request), which
## puts you in that station's shared copy with the other pilots there.
## A fleet carrier is clamped at its berth on the station's berth ring at once, with you in its
## pilot's chair (flying in, the automated approach ends here; see _request_dock).
func dock(planet_id: String) -> void:
	_docked = planet_id
	flight.velocity = Vector3.ZERO
	flight.throttle = 0.0
	_approach = {}
	if _berth.get("station", "") != planet_id:
		_berth = {"station": planet_id, "copy": 1, "pad": _local_pad(), "local": true}
		Net.send({"type": "dock_request", "station": planet_id})
	if _carrier:
		_snap_to_berth()
		_enter_carrier(Net.my_name, "seat")
		return
	_land_in(Station.new(planet_id), false)


## Moves the ship (and you in it) to a place: the High Port's hangar, or a base on the surface.
func _land_in(place: Node3D, at_base: bool) -> void:
	_leave_place()
	_at_spaceport = at_base
	controls.enabled = false
	_set_space_visible(false)
	_adopt(place)
	_station.seated_down.connect(_show_ship_menu)
	add_child(_station)
	_show_ship_menu()


## Makes a place the one you're in, listening to what's used in it.
func _adopt(place: Node3D) -> void:
	_station = place
	_station.controls = controls
	_station.wants_menu.connect(_open_standing_menu)
	_station.service.connect(_on_service)
	_station.wants_space.connect(_go_space)


# --- The fleet carrier: berths, the automated approach, walking aboard -----------------------

## A berth number of our own for when the server gives none (an older server without pads).
func _local_pad() -> int:
	return absi(hash(Net.my_name)) % BERTHS + 1


## "Berth 12, Cinder Orbital (1)": the berth and the station's copy.
func _berth_text() -> String:
	if _berth.is_empty() or not _stations.has(_berth.station):
		return ""
	return "Berth %d, %s (%d)" % [int(_berth.pad), _stations[_berth.station].name, int(_berth.copy)]


## Near a station in a carrier: ask for a berth. The approach starts when the server grants one.
func _request_dock(id: String) -> void:
	if _dock_wait != "" or not _approach.is_empty():
		return
	if _berth.get("station", "") == id and not _berth.get("local", false):
		_start_approach(id)
		return
	_dock_wait = id
	_dock_wait_time = 4.0
	Net.send({"type": "dock_request", "station": id})


## No answer from the server (or a refusal): dock at a berth of our own anyway, alone.
func _berth_anyway(id: String) -> void:
	_dock_wait = ""
	_berth = {"station": id, "copy": 1, "pad": _local_pad(), "local": true}
	if _station == null:
		_start_approach(id)


## The automated approach to the berth, about 25 seconds in four legs: out to the approach point
## (round the station if it's in the way), sliding in sideways to line up alongside the berth while
## turning to lie along it, the slow final approach, and the clamps. Seen from outside; F skips it.
func _start_approach(id: String) -> void:
	var st: Dictionary = _stations[id]
	var b := _berth_frame(int(_berth.pad))
	var berth: Vector3 = b.hull
	var lie: Basis = b.basis
	var out: Vector3 = b.out
	var start := System.diff(_pos, st.pos) - flight.basis * Models.CARRIER_BRIDGE
	var line_up := berth + out * 480.0
	var far := berth + out * 1800.0 + Vector3(0, signf(berth.y) * 160.0, 0)
	var points := [start]
	# Round the station rather than through it.
	var seg := far - start
	var t := clampf(-start.dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	if (start + seg * t).length() < 700.0:
		var side := (start + far)
		if side.length() < 100.0:
			side = Vector3.UP
		points.append(side.normalized() * 2200.0)
	points.append(far)
	var legs := []
	var basis := flight.basis
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var z: Vector3 = points[i]
		var dir := (z - a).normalized() if (z - a).length() > 1.0 else -basis.z
		var facing := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
		legs.append({"from": a, "to": z, "b0": basis, "b1": facing, "time": clampf(a.distance_to(z) / 200.0, 5.0, 12.0), "stage": "Approach"})
		basis = facing
	legs.append({"from": far, "to": line_up, "b0": basis, "b1": lie, "time": 9.0, "stage": "Lining up"})
	legs.append({"from": line_up, "to": berth, "b0": lie, "b1": lie, "time": 8.0, "stage": "Final approach"})
	legs.append({"from": berth, "to": berth, "b0": lie, "b1": lie, "time": 2.5, "stage": "Clamps"})
	_approach = {"station": id, "t": 0.0, "legs": legs}
	controls.enabled = false
	_set_outside(true)
	_say("Docking granted: %s" % _berth_text())


func _approach_step(delta: float) -> void:
	_approach.t += delta
	if _approach.t > 1.0 and Input.is_action_just_pressed("interact"):
		_clamp()
		return
	var t: float = _approach.t
	for leg in _approach.legs:
		if t > leg.time:
			t -= leg.time
			continue
		var u := smoothstep(0.0, 1.0, t / leg.time)
		var hull: Vector3 = leg.from.lerp(leg.to, u)
		var basis: Basis = leg.b0.slerp(leg.b1, u).orthonormalized()
		var st: Dictionary = _stations[_approach.station]
		var was := _pos
		_pos = System.offset(st.pos, hull + basis * Models.CARRIER_BRIDGE)
		flight.velocity = System.diff(_pos, was) / maxf(delta, 0.001)
		flight.basis = basis
		_approach.stage = leg.stage
		return
	_clamp()


func _approach_text() -> String:
	var left := 0.0
	for leg in _approach.legs:
		left += leg.time
	return "Automated docking: %s · %s · %d s · %s to skip" % [_berth_text(), _approach.get("stage", "Approach"), ceili(left - _approach.t), controls.binding_text("interact", false)]


## The clamps close: the carrier lies at its berth and you're in the pilot's chair.
func _clamp() -> void:
	var id: String = _approach.station
	_approach = {}
	_set_outside(false)
	dock(id)
	_say("Clamps engaged. %s" % _berth_text())
	if _station:
		_station._say("Clamps engaged. %s" % _berth_text(), 5.0)


## Puts the carrier at its berth, stopped.
func _snap_to_berth() -> void:
	if _berth.is_empty() or not _stations.has(_berth.station):
		return
	var b := _berth_frame(int(_berth.pad))
	_pos = _berth_pos(_berth.station, int(_berth.pad))
	flight.basis = b.basis
	flight.velocity = Vector3.ZERO
	flight.throttle = 0.0


## Leave seat (G), flying: the carrier holds still (shedding its speed over 2 s) and you're on
## your feet on the Bridge, beside the pilot's chair.
func _leave_helm() -> void:
	if _station or _raid or _battle:
		return
	if not _carrier:
		_say("Your ship's cabin is only the cockpit. Fleet carriers have room to walk around.")
		return
	if not _approach.is_empty() or _dock_wait != "":
		return # the carrier is docking (or about to): stay at the helm
	_hold_rate = flight.speed() / 2.0
	flight.throttle = 0.0
	flight.mode = Flight.Mode.SUBLIGHT
	_enter_carrier(Net.my_name, "bridge")


## Into a carrier's interior: your own (from the chair, the airlock, the shuttle) or someone
## else's (once the server lets you aboard). `at` is "seat" (in the pilot's chair, docked),
## "bridge" (standing by it) or "hangar" (just in from the airlock).
func _enter_carrier(owner: String, at := "seat") -> void:
	_leave_place()
	controls.enabled = false
	_set_outside(false)
	_set_view("aboard")
	var c := Carrier.new(owner, "")
	_adopt(c)
	c.seated_down.connect(_on_chair)
	_update_carrier(c)
	add_child(c)
	if at == "seat":
		_show_ship_menu()
	else:
		c.arrive(at)


## What a carrier's interior shows: where it's docked, the berth, the planet below.
func _update_carrier(c: Node) -> void:
	if _crew.is_empty():
		c.docked_at = _docked
		c.berth_text = _berth_text() if _docked != "" else ""
		c.over = _over_planet()
	else:
		var o := _other_named(_crew.owner)
		var at: Dictionary = o.get("berth", {}) if not o.is_empty() else {}
		if at.is_empty() and not o.is_empty():
			at = _berth_at(o.pos)
		c.docked_at = str(at.get("station", ""))
		c.berth_text = ("Berth %d, %s" % [int(at.pad), _stations[at.station].name]) if _stations.has(str(at.get("station", ""))) else ""
		c.over = str(o.get("over", "")) if not o.is_empty() else ""


## Each frame aboard a carrier: your own holds still (or sits at its berth); someone else's goes
## where its owner flies it, and you with it. Space is drawn turned to the ship.
func _aboard(delta: float) -> void:
	var view := flight.basis
	if _crew.is_empty():
		if _docked == "":
			flight.velocity = flight.velocity.move_toward(Vector3.ZERO, maxf(_hold_rate, 1.0) * delta)
			_pos = System.offset(_pos, flight.velocity * delta)
	else:
		var o := _other_named(_crew.owner)
		if not o.is_empty():
			_pos = o.shown.duplicate()
			view = Basis.from_euler(o.get("rot", Vector3.ZERO))
	_update_carrier(_station)
	_place_world(delta, view, _station._camera)
	_send_ship(delta)


## Sitting in the pilot's chair: docked, the ship's menu; in open space, back to flying.
func _on_chair() -> void:
	if not _station.mine:
		_station._say("Only %s flies this carrier." % _station.owner_name)
		return
	if _docked != "":
		_station.sit()
		_show_ship_menu()
		return
	_leave_place()
	_set_view("flight")
	_set_outside(false)
	controls.enabled = true
	flight.throttle = 0.0
	_refresh_focus()
	Net.send({"type": "walk", "pos": CHAIR_POSE.pos, "yaw": CHAIR_POSE.yaw, "anim": CHAIR_POSE.anim})
	_say("At the helm. %s to leave your seat." % controls.binding_text("leave_seat", false))


## A door into another shared space, from a place: your carrier's airlock into the station, a
## boarding door onto someone's carrier, the gate back to your own, the shuttle home.
func _go_space(space: String) -> void:
	if space == "ship:" + Net.my_name:
		_home_to_carrier()
	elif space.begins_with("ship:"):
		_board(space.substr(5))
	elif space.begins_with("station:"):
		_walk_into_station(space.substr(8))


## Back aboard your own carrier, in from the airlock.
func _home_to_carrier() -> void:
	if not _crew.is_empty():
		if str(_crew.get("system", System.current)) != System.current:
			_enter_system(str(_crew.system)) # your carrier stayed where you boarded the other
		_pos = _crew.pos
		flight.basis = _crew.basis
		_crew = {}
	_enter_carrier(Net.my_name, "hangar")


## Asks to board someone's carrier; aboard when the server says yes (space_joined).
func _board(owner: String) -> void:
	_boarding = owner
	_boarding_time = 5.0
	Net.send({"type": "enter_space", "space": "ship:" + owner, "pos": [-18.6, -15.95, 8.0], "yaw": -PI / 2.0, "anim": "idle"})
	if _station:
		_station._say("Asking to come aboard %s's carrier..." % owner, 3.0)


func _boarded(msg: Dictionary) -> void:
	var owner := _boarding
	_boarding = ""
	_space_id = str(msg.space)
	if _crew.is_empty():
		_crew = {"owner": owner, "pos": _pos.duplicate(), "basis": flight.basis, "system": System.current}
	else:
		_crew.owner = owner
	_enter_carrier(owner, "hangar")
	_station.space_id = _space_id
	_station.walkers.on_message(msg)
	_station._say("Aboard %s's carrier. The shuttle on the Hangar Deck takes you back to yours." % owner, 5.0)


## Through the airlock into a station's Carrier Berth hall, arriving at the gate you came by.
func _walk_into_station(id: String) -> void:
	if not _stations.has(id):
		return
	var from := ""
	if _station is Carrier and not _station.mine:
		from = _station.owner_name
	if not _crew.is_empty():
		_pos = _crew.pos
		flight.basis = _crew.basis
		_crew = {}
	_leave_place()
	_at_station = id
	controls.enabled = false
	_set_view("away")
	var st := Station.new(id)
	st.carrier_mode = true
	st.berth = _berth
	st.gates_provider = _docked_carriers.bind(id)
	st.arrive_from = from
	_adopt(st)
	st.seated_down.connect(func(): pass)
	add_child(st)
	st.stand()
	st._say("%s · Carrier Berths. Your carrier's gate is lit green." % _stations[id].name, 4.0)


## Every carrier berthed in your copy of a station: [{"name", "pad"}]. The server says which berth
## each ship holds (`berth` on its `ship` messages); without that, it's read off where the ship lies.
func _docked_carriers(station_id: String) -> Array:
	var out := []
	for id in _others:
		var at: Dictionary = _others[id].get("berth", {})
		if at.is_empty():
			at = _berth_at(_others[id].pos)
		elif int(at.get("copy", 1)) != int(_berth.get("copy", 1)):
			continue # docked in another copy of the station: not beside you
		if at.get("station", "") == station_id:
			out.append({"name": _others[id].name, "pad": int(at.pad)})
	return out


## Which berth a ship at `pos` lies at, or {}: {"station", "pad"}.
func _berth_at(pos: Array) -> Dictionary:
	for id in _stations:
		if System.distance(_stations[id].pos, pos) > 2_000.0:
			continue
		for pad in range(1, BERTHS + 1):
			if System.distance(_berth_pos(id, pad), pos) < 40.0:
				return {"station": id, "pad": pad}
	return {}


func _other_named(pilot: String) -> Dictionary:
	for id in _others:
		if _others[id].name == pilot:
			return _others[id]
	return {}


## Keeps the server told which shared space you're in, from where you are: your carrier (flying
## it, or aboard), someone else's, a station's copy (on foot; in a carrier station, as soon as you
## walk in), a Builder's base on foot. Seated in a small ship at a station you're in none.
func _sync_space(delta: float) -> void:
	if _boarding != "":
		_boarding_time -= delta
		if _boarding_time <= 0.0:
			_boarding = ""
		return
	var want := ""
	if _raid:
		want = ""
	elif _station is Carrier:
		want = "ship:" + _station.owner_name
	elif _station and _station.get_script() == Station:
		var id: String = _station.planet_id
		if _station.carrier_mode or (not _station.seated and _berth.get("station", "") == id and not _berth.get("local", false)):
			want = "station:" + id
	elif _station and _station.get_script() == Surface:
		want = "" if _station.seated else "surface:" + _station.planet_id
	elif _station == null and _carrier and _crew.is_empty():
		want = "ship:" + Net.my_name # at the helm of your carrier
	if want.begins_with("ship:") and want != "ship:" + Net.my_name and want != _space_id:
		want = _space_id # someone else's carrier only by boarding, with the server's yes
	if want != _space_id:
		if want == "":
			Net.send({"type": "leave_space"})
		else:
			var msg := {"type": "enter_space", "space": want}
			var pose: Dictionary = _station.walker_pose() if _station and _station.has_method("walker_pose") else {}
			if _station == null:
				pose = {"pos": Vector3(CHAIR_POSE.pos[0], CHAIR_POSE.pos[1], CHAIR_POSE.pos[2]), "yaw": CHAIR_POSE.yaw, "anim": CHAIR_POSE.anim}
			if not pose.is_empty():
				msg.pos = [pose.pos.x, pose.pos.y, pose.pos.z]
				msg.yaw = pose.yaw
				msg.anim = pose.anim
			Net.send(msg)
		_space_id = want
	if _station:
		_station.space_id = _space_id


func _leave_place() -> void:
	if _station:
		_station.queue_free()
		_station = null
	_at_station = ""
	_menu_standing = false
	_dock_panel.visible = false


## Seated in your ship: the ship's menu, with the mouse free to click it.
func _show_ship_menu() -> void:
	_menu_standing = false
	_dock_panel.visible = true
	controls.release_mouse()
	_refresh_dock()


## Leave the pilot's seat and walk down the ramp (or, docked in a carrier, get up from its chair).
func _leave_seat() -> void:
	_hide_panels()
	_dock_panel.visible = false
	_station.stand()


## Something used on foot in a place: Ship Services, a War terminal, the Job Board's contracts
## console, a base's Carrier Dock.
func _on_service(kind: String) -> void:
	match kind:
		"repair":
			flight.repair()
		"war":
			_open_war()
		"jump":
			_open_jump()
		"contracts":
			_open_trade("contracts")
		"dock_market":
			_open_trade("market", str(Net.planet(_here()).get("owner", "")))


## The transit terminal in the station: the same trips, while you stand at the console. (Off
## someone else's carrier at another station than yours: trips go from where your carrier is.)
func _open_standing_menu() -> void:
	if _here() != _docked:
		_station._say("Your carrier is docked at %s: the shuttle at your gate takes you back to it for trips from there." % (_stations[_docked].name if _stations.has(_docked) else "another station"), 5.0)
		return
	_menu_standing = true
	_station.set_menu_open(true)
	_dock_panel.visible = true
	_refresh_dock()


func _close_standing_menu() -> void:
	_menu_standing = false
	_dock_panel.visible = false
	if _station:
		_station.set_menu_open(false)


## Ask the Star Port for a berth (land_request); the ship flies down when it's granted
## (_berth_granted). A carrier stays docked up here and sends its lander down instead.
func _fly_to_base() -> void:
	if _land_wait != "":
		return
	_land_problem = ""
	_land_wait = _docked
	_land_wait_time = 4.0
	Net.send({"type": "land_request", "base": _docked, "lander": _carrier})
	_refresh_dock()


## The Star Port gave us berth `berth`: your ship flies down to the planet's surface and lands on it.
func _berth_granted(base: String, berth: int) -> void:
	_land_wait = ""
	if base != _docked or _at_spaceport:
		return
	var p := Net.planet(_docked)
	if not _carrier:
		_berth = {} # the ship left its High Port pad (flying back up asks for one again)
	var place := Surface.new(_docked)
	place.berth = berth
	_land_in(place, true)
	_say("Landed on berth %d at %s's Star Port on %s." % [berth + 1, p.get("owner", "the Builder"), p.get("name", _docked)])


## The shuttle down from the High Port, when the Star Port's berths are full: your ship stays on its
## pad up here, and you arrive on foot at the base's shuttle stop.
func _shuttle_to_base() -> void:
	var p := Net.planet(_docked)
	var place := Surface.new(_docked)
	place.shuttle = true
	_close_standing_menu()
	_land_in(place, true)
	_dock_panel.visible = false
	_station.stand()
	_say("The shuttle sets you down at %s's base on %s. Your ship waits at the High Port." % [p.get("owner", "the Builder"), p.get("name", _docked)])


## Back up to orbit: from a base to the High Port's hangar.
func _fly_to_station() -> void:
	dock(_docked)


## Launch from the High Port: the ship lifts off the pad and flies out of the hangar into space.
## A carrier's clamps let go instead and it drifts clear of its berth, with you at the helm.
func undock() -> void:
	var from := _docked
	Net.send({"type": "undock"})
	_berth = {}
	if _carrier:
		_leave_place()
		_docked = ""
		_at_spaceport = false
		_set_view("flight")
		_set_outside(false)
		controls.enabled = true
		flight.velocity = flight.basis.x * 25.0 # out from the berth
		flight.throttle = 0.0
		_refresh_focus()
		Net.send({"type": "walk", "pos": CHAIR_POSE.pos, "yaw": CHAIR_POSE.yaw, "anim": CHAIR_POSE.anim})
		_say("Clamps released at %s. Fly safe." % (_stations[from].name if _stations.has(from) else "the station"))
		return
	_leave_place()
	_docked = ""
	_at_spaceport = false
	_set_space_visible(true)
	_camera.make_current()
	controls.enabled = true
	if _stations.has(from):
		teleport(System.offset(_stations[from].pos, Vector3(0, 0, 1_200)))
		flight.basis = Basis()
	_refresh_focus()
	_say("Launched from %s. Fly safe." % (_stations[from].name if _stations.has(from) else "the High Port"))


## Facilities on the outposts standing on a planet: a contested world's sectors (for its orbital
## station), or a Builder's home for sites from before the war (and any still on its own pads).
func facilities_on(planet_id: String) -> Array:
	return Net.facilities().filter(func(f): return f.planet == planet_id or Net.planet(f.planet).get("parent", "") == planet_id)


func _refresh_dock() -> void:
	if _docked == "" or Net.state.is_empty():
		return
	for child in _dock_list.get_children():
		child.queue_free()
	var p := Net.planet(_docked)
	var owner: String = str(p.get("owner", "nobody")) if p.get("owner") != null else "nobody"
	var orbital: bool = _stations.get(_docked, {}).get("orbital", false)
	if _at_spaceport:
		_dock_title.text = "Landed at %s's base on %s" % [owner, p.get("name", _docked)]
		var job := Net.open_job(_docked)
		var stash: Array = _me().get("stash", [])
		if job.is_empty():
			_dock_note("No open jobs at this Star Port.")
		elif _cargo(job.resource) <= 0:
			_dock_note("Job #%d wants %d %s (%d delivered). Go mine some." % [job.id, job.amount, job.resource, job.delivered])
		else:
			_dock_button("Deliver %d %s for job #%d" % [_cargo(job.resource), job.resource, job.id],
				func(): Net.send({"type": "deliver", "job": int(job.id)}))
		if stash.is_empty():
			_dock_note("Nothing to sell to the Fence.")
		else:
			_dock_button("Sell %d raided items to the Fence for %d credits" % [stash.size(), _stash_value() / 2],
				func(): Net.send({"type": "sell"}))
		_star_port_bids(owner, _station != null and _station.get("shuttle") == true)
		_dock_market_entry(owner)
		_war_row()
		if _station and _station.get("shuttle"):
			_dock_button("Take the shuttle back up to %s" % _stations[_docked].name, _fly_to_station)
			_dock_button("Close", _close_standing_menu)
		else:
			_dock_button("Leave your seat and walk around the base", _leave_seat)
			_dock_button(("Lift off, back up to your carrier at %s" if _carrier else "Fly back up to %s") % _stations[_docked].name, _fly_to_station)
	else:
		if _menu_standing:
			_dock_title.text = "Surface Transit, %s" % _stations[_docked].name
		elif _carrier:
			_dock_title.text = "In your carrier's chair · %s" % _berth_text()
			_dock_button("Leave your seat and walk around your carrier (the airlock leads into the station)", _leave_seat)
		else:
			_dock_title.text = "In your ship on pad 06, %s" % _stations[_docked].name
			_dock_button("Leave your seat and walk into the station", _leave_seat)
		var where: String = p.get("name", _docked)
		if orbital:
			var wp := WarInfo.planet(_docked)
			where = wp.get("name", _docked)
			_dock_note(_front_note(wp), WarInfo.faction_color(wp.get("owner")).lightened(0.2))
		elif Net.has_building("spaceport", _docked):
			var open := _berths_open(_docked)
			var taken: int = Net.state.get("berths", {}).get(_docked, []).filter(func(n): return n != null).size()
			if _land_wait != "":
				_dock_note("Asked %s's Star Port for a berth..." % owner)
			elif open > 0:
				_dock_button(("Take a lander down to %s's base, to the Star Port (%d of %d berths free)" if _carrier else "Fly down to %s's base and land at the Star Port (%d of %d berths free)") % [owner, maxi(0, open - taken), open], _fly_to_base)
			if _land_problem != "":
				_dock_note("The Star Port: %s." % _land_problem, Color(1.0, 0.75, 0.4))
			_dock_button("Take the shuttle down to %s's base (your ship stays here)" % owner, _shuttle_to_base)
			_star_port_bids(owner, true)
		else:
			_dock_note("%s has no Star Port yet." % where)
		var facs := facilities_on(_docked)
		if facs.is_empty():
			_dock_note("No outposts to raid on %s." % where)
		for f in facs:
			_raid_entry(f)
		_war_row()
		if _menu_standing:
			_dock_button("Close", _close_standing_menu)
		else:
			_dock_button("Undock" if _carrier else "Launch", undock)
	var first := _dock_list.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	if not first.is_empty():
		first[0].grab_focus.call_deferred()


## One outpost in the ship's menu: a button that flies you there to raid it, or why you can't.
## Outposts of the war are raided only by pilots of another faction; your own side's are
## friendly. A dormant outpost (its faction lost the planet) can still be raided.
func _raid_entry(f: Dictionary) -> void:
	var b: Dictionary = f.building
	var site := Net.planet(f.planet)
	var fac_name: String = site.name if site.get("kind", "") == "satellite" else f.name
	var builder: String = str(site.get("owner")) if site.get("owner") != null else "nobody"
	var side = site.get("faction")
	var mine := WarInfo.my_faction()
	var whose := "%s's" % builder + (", %s" % WarInfo.faction_name(side) if side != null else "")
	var dormant: bool = site.get("dormant", false)
	if side != null and mine == str(side):
		_dock_note("%s (%s): friendly, your own side's outpost, so it can't be raided" % [fac_name, whose], WarInfo.faction_color(side).lightened(0.2))
		return
	if side != null and mine == "":
		_dock_note("%s (%s): choose a faction to raid outposts of the war" % [fac_name, whose])
		return
	if side != null and builder == Net.my_name:
		_dock_note("%s: your own outpost, you can't raid it" % fac_name)
		return
	var vault := 0
	for id in b.vault:
		vault += int(b.vault[id])
	var cool := (float(b.get("cooldownUntil", 0)) - Net.now_ms()) / 1000.0
	var label := "Raid %s (%s%s): security tier %d, %d items in the vault" % [fac_name, whose, ", dormant" if dormant else "", int(b.security), vault]
	if not Net.raid_on(f.planet, f.slot).is_empty():
		_dock_note("%s: someone is already inside" % fac_name)
	elif cool > 0:
		_dock_note("%s: security on alert after a raid (%d s)" % [fac_name, ceili(cool)])
	else:
		_dock_button(label, board.bind(f.planet, f.slot))


## A contested world from its orbital station: who holds it and how hard it's fought over.
func _front_note(wp: Dictionary) -> String:
	if wp.is_empty():
		return "A contested world of the war."
	var held := "held by %s (%d of %d sectors)" % [WarInfo.the(wp.owner), WarInfo.held(wp, wp.owner), wp.sectors.size()] if wp.owner != null else "held by nobody"
	var lock := WarInfo.lock_left(wp)
	return "%s is a contested world, %s: %s%s. No Builder lives here; their outposts stand in its sectors." % [
		wp.name, held, WarInfo.contention(wp), (", locked for " + lock) if lock != "" else ""]


## How many berths a planet's Star Port has open, by its level (the server's berthsOpen).
func _berths_open(planet_id: String) -> int:
	for b in Net.planet(planet_id).get("buildings", []):
		if b.type == "spaceport" and int(b.get("level", 1)) >= 1:
			return mini(int(Net.catalog.get("berthsMax", 10)), int(b.level) * int(Net.catalog.get("berthsPerLevel", 2)))
	return 0


## The Builder's Star Port buy orders: sell them what you carry. Landed on a berth you're paid in
## full; from the High Port (`tariffed`) the platform keeps its tariff.
func _star_port_bids(builder: String, tariffed: bool) -> void:
	if builder == Net.my_name or builder == "nobody":
		return
	var bids: Dictionary = Net.state.get("bases", {}).get(builder, {}).get("bids", {})
	if bids.is_empty():
		_dock_note("%s's Star Port isn't buying anything right now." % builder)
		_star_port_asks(builder, tariffed)
		return
	var tariff: float = float(Net.catalog.get("tariff", 0.2)) if tariffed else 0.0
	var hold: Dictionary = _me().get("hold", {})
	var any := false
	for item in bids:
		var bid: Dictionary = bids[item]
		var have := _cargo(item) + int(hold.get(item, 0))
		var qty := mini(have, int(bid.want))
		var label := "%s buys %s at %d credits each (wants %d)" % [builder, WarInfo.goods_name(item), int(bid.price), int(bid.want)]
		if qty <= 0:
			_dock_note(label + ": you have none")
			continue
		any = true
		var pay := int(bid.price) * qty
		var cut := roundi(pay * tariff)
		var text := "Sell %d %s to %s for %d credits" % [qty, WarInfo.goods_name(item), builder, pay - cut]
		if cut > 0:
			text += " (the High Port's tariff takes %d)" % cut
		_dock_button(text, func(): Net.send({"type": "sell_to_builder", "builder": builder, "item": item, "qty": qty}))
	if tariffed and any:
		_dock_note("Land at the Star Port to sell without the High Port's %d%% tariff." % roundi(tariff * 100.0))
	_star_port_asks(builder, tariffed)


## The Builder's Star Port sell listings: buy up to 10 at a time into your cargo. From the High
## Port (`tariffed`) the platform's tariff goes on top.
func _star_port_asks(builder: String, tariffed: bool) -> void:
	var base: Dictionary = Net.state.get("bases", {}).get(builder, {})
	var asks: Dictionary = base.get("asks", {})
	var tariff: float = float(Net.catalog.get("tariff", 0.2)) if tariffed else 0.0
	var credits := int(_me().get("credits", 0))
	for item in asks:
		var price := int(asks[item])
		var stock := int(base.get("stock", {}).get(item, 0))
		var qty := mini(stock, 10)
		while qty > 0 and price * qty + roundi(price * qty * tariff) > credits:
			qty -= 1
		if qty <= 0:
			_dock_note("%s sells %s at %d credits each: %s" % [builder, WarInfo.goods_name(item), price, "sold out" if stock <= 0 else "you can't afford one"])
			continue
		var cut := roundi(price * qty * tariff)
		var text := "Buy %d %s from %s for %d credits" % [qty, WarInfo.goods_name(item), builder, price * qty + cut]
		if cut > 0:
			text += " (%d of it the High Port's tariff)" % cut
		_dock_button(text, func(): Net.send({"type": "buy_from_builder", "builder": builder, "item": item, "qty": qty}))


## At a Builder's base: their Carrier Dock market, if it's finished and trades with your side.
func _dock_market_entry(builder: String) -> void:
	var dock := WarInfo.dock_of(builder)
	if dock.is_empty():
		return
	if not WarInfo.dock_finished(builder):
		_dock_note("%s's Carrier Dock is still being built." % builder)
		return
	var why := WarInfo.dock_problem(builder)
	if why != "":
		_dock_note(why)
		return
	var listed: int = Net.state.get("bases", {}).get(builder, {}).get("market", {}).size()
	_dock_button("Carrier Dock market: %d goods listed by %s" % [listed, builder], _open_trade.bind("market", builder))


## The war, from the ship's menu: the War terminal, supply contracts, and a side if you have none.
func _war_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var entries := [["War terminal", _open_war.bind("")], ["Supply contracts", _open_trade.bind("contracts", "")]]
	if WarInfo.my_faction() == "":
		entries.append(["Choose your faction", _show_picker])
	for e in entries:
		var b := Button.new()
		b.text = e[0]
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(e[1])
		row.add_child(b)
	_dock_list.add_child(row)


func _dock_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	_dock_list.add_child(b)


func _dock_note(text: String, colour := Color(1, 1, 1, 0.6)) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = colour
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	_dock_list.add_child(l)


func _build_dock_panel(layer: CanvasLayer) -> void:
	# Low on the screen, like a cockpit display, so the view out of the canopy stays clear.
	_dock_panel = PanelContainer.new()
	_dock_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dock_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dock_panel.position.y -= 40
	_dock_panel.custom_minimum_size = Vector2(620, 0)
	_dock_panel.visible = false
	layer.add_child(_dock_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_dock_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	_dock_title = Label.new()
	_dock_title.add_theme_font_size_override("font_size", 24)
	col.add_child(_dock_title)
	_dock_list = VBoxContainer.new()
	_dock_list.add_theme_constant_override("separation", 8)
	col.add_child(_dock_list)


## The server's answer when it turns a pilot away (a character of an admins-only faction, from an
## app without the admin key): shown in the middle of the screen until a hello is welcomed.
func _build_refusal(layer: CanvasLayer) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	_refusal = PanelContainer.new()
	_refusal.visible = false
	_refusal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refusal.custom_minimum_size = Vector2(640, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.09, 0.95)
	style.border_color = Color(0.95, 0.4, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	_refusal.add_theme_stylebox_override("panel", style)
	center.add_child(_refusal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_refusal.add_child(col)
	var title := Label.new()
	title.text = "The galaxy server turned you away"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.5, 0.45))
	col.add_child(title)
	_refusal_text = Label.new()
	_refusal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refusal_text.add_theme_font_size_override("font_size", 18)
	col.add_child(_refusal_text)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.text = "If you're an admin, put your admin key in Settings (%s) and press Enter there to try again. Otherwise, start the game again under another name." % controls.binding_text("menu", false)
	col.add_child(hint)


func _refresh_refusal() -> void:
	if _refusal == null:
		return
	_refusal.visible = Net.refused != ""
	if _refusal.visible:
		_refusal_text.text = Net.refused.substr(0, 1).to_upper() + Net.refused.substr(1) + "."


# --- The war's screens ------------------------------------------------------------------------

func _panel_open() -> bool:
	return _picker.visible or _war_panel.visible or _trade.visible


## Opens one of the war's screens (the faction choice, the War terminal, the dock market or
## contracts) over what you're doing: flying, seated in your ship, or standing at a console.
func _open_panel(panel: Control) -> void:
	for p in [_picker, _war_panel, _trade, _jump_panel]:
		p.visible = p == panel
	if "colour" in panel:
		panel.colour = controls.hud_color()
	if _station:
		_dock_panel.visible = false
		if not _station.seated:
			_station.set_menu_open(true)
		controls.release_mouse()
	else:
		_nav.visible = false
		_refresh_focus()


## Back to where the screen was opened from: the ship's menu, the transit menu, or walking.
func _close_panel() -> void:
	_hide_panels()
	if _station:
		if _station.seated:
			_show_ship_menu()
		elif _menu_standing:
			_open_standing_menu()
		else:
			_station.set_menu_open(false)
	elif _raid == null:
		_refresh_focus()


func _hide_panels() -> void:
	for p in [_picker, _war_panel, _trade, _jump_panel]:
		p.visible = false


func _show_picker() -> void:
	_picker_dismissed = false
	_picker.refresh()
	_open_panel(_picker)


## The station you're at: the one you're walking in, else where your ship is docked (or "").
func _here() -> String:
	return _at_station if _at_station != "" else _docked


## The War terminal, on a planet: the one you're at if it's contested, else the first of the system.
# --- FTL jumps (fleet carriers only) ---------------------------------------------

## The GALAXY MAP terminal aboard your fleet carrier: where to jump it.
func _open_jump() -> void:
	if not (_carrier and _station is Carrier and _station.mine and _crew.is_empty()):
		if _station:
			_station._say("Only a fleet carrier's captain can jump it, from its galaxy map.", 4.0)
		return
	_jump_panel.open(System.current, _over_planet())
	_open_panel(_jump_panel)


## Asks the server to jump your carrier (released from its berth first, if it's docked).
func _request_jump(system_id: String, planet_id: String) -> void:
	if not _jump.is_empty():
		_jump_panel.say("A jump is already under way.")
		return
	if _docked != "":
		Net.send({"type": "undock"})
		_berth = {}
		_docked = ""
		_at_spaceport = false
	Net.send({"type": "carrier_jump", "system": system_id, "planet": planet_id})
	_jump_panel.say("Plotting the jump...")


## The server cleared a jump: yours (you fly it), or the one your host carrier is making (you ride).
func _start_jump(msg: Dictionary) -> void:
	var owner := str(msg.get("owner", ""))
	if owner != Net.my_name and owner != str(_crew.get("owner", "")):
		return
	var seconds := float(msg.get("seconds", 5.0))
	_jump = {"system": str(msg.get("system", "teal-prime")), "planet": str(msg.get("planet", "")) if msg.get("planet") != null else "", "owner": owner, "left": seconds, "total": seconds, "arrived": false}
	if _jump_panel.visible:
		_close_panel()
	var to: String = str(WarInfo.planet(_jump.planet).get("name", "") if _jump.planet != "" else WarInfo.system(_jump.system).get("name", _jump.system))
	_say("FTL jump to %s in %d seconds" % [to, ceili(seconds)])


func _jump_step(delta: float) -> void:
	if _jump.is_empty():
		return
	_jump.left -= delta
	var to: String = str(WarInfo.planet(_jump.planet).get("name", "") if _jump.planet != "" else WarInfo.system(_jump.system).get("name", _jump.system))
	if not _jump.arrived:
		# Spooling up: the view washes out toward the jump.
		var k := clampf(1.0 - _jump.left / maxf(0.1, _jump.total), 0.0, 1.0)
		_jump_veil.color.a = k * k
		_jump_text.text = "FTL JUMP · %s · %d" % [to.to_upper(), ceili(maxf(0.0, _jump.left))]
		if _jump.left <= 0.0:
			_arrive(_jump.system, _jump.planet, _jump.owner == Net.my_name)
			_jump.arrived = true
			_jump.left = JUMP_FLASH_S
		return
	# Through: the view comes back in at the far end.
	_jump_veil.color.a = clampf(_jump.left / JUMP_FLASH_S, 0.0, 1.0)
	_jump_text.text = ""
	if _jump.left <= 0.0:
		_jump = {}
		_jump_veil.color.a = 0.0
		_say("Arrived: %s" % to)


## Out of the jump: into the system, and (flying it) to where the carrier comes out: in the planet's
## orbit, off its orbital station, or out in the system near its first world.
func _arrive(system_id: String, planet_id: String, mine: bool) -> void:
	if system_id != System.current:
		_enter_system(system_id)
	if not mine:
		return
	var at: Array
	if planet_id != "" and not System.builder_planet(planet_id).is_empty():
		at = System.offset(System.orbital_pos(planet_id), Vector3(0, 0, 10_000))
	elif System.home():
		at = System.SPAWN_POS.duplicate()
	elif not System.planets().is_empty():
		at = System.offset(System.orbital_pos(System.planets()[0].id), Vector3(0, 0, 60_000_000))
	else:
		at = [0.0, 0.0, -80_000_000_000.0]
	teleport(at)
	_send_timer = 0.0 # tell everyone at once


## Into another system: its star and planets in the sky, its orbital stations; the stations, ships
## and field of the one you left are gone from view.
func _enter_system(system_id: String) -> void:
	var planets: Array = []
	for wp in WarInfo.planets_in(system_id):
		planets.append({"id": wp.id, "name": wp.name})
	System.enter(system_id, str(WarInfo.system(system_id).get("name", system_id)), planets)
	_sky.rebuild()
	for id in _stations:
		(_stations[id].node as Node3D).queue_free()
	_stations = {}
	if System.home():
		_add_station("aster", System.PORT_NAME, System.PORT_POS)
	_sync_stations()
	_set_route([])


func _open_war(planet_id := "") -> void:
	if planet_id == "":
		planet_id = _here() if not WarInfo.planet(_here()).is_empty() else ""
	if planet_id == "":
		var here := WarInfo.planets_in(str(Net.state.get("system", {}).get("id", "teal-prime")))
		planet_id = here[0].id if not here.is_empty() else "cinder"
	_war_panel.open(planet_id)
	_open_panel(_war_panel)


## The War terminal's Sector Battles: that screen (game/battle/battle_menu.gd) for the planet, over
## whatever you're doing. Attacking needs you aboard a carrier in its orbit; the defender's pilots
## may also join from its station. A battle it starts takes over the screen (see _check_battle).
func _open_battles(planet_id: String) -> void:
	var path := "res://battle/battle_menu.gd"
	if not ResourceLoader.exists(path):
		return
	var menu: Control = load(path).open(self, planet_id)
	if menu == null:
		# The screen failed to load (a project that hasn't been imported since the battle code
		# arrived: run godot --headless --path game --import). Keep the War terminal and the controls.
		var why := "Sector Battles couldn't open. Re-import the project (see the README) and try again."
		_say(why)
		if _station:
			_station._say(why)
		return
	_hide_panels()
	_dock_panel.visible = false
	if _station:
		_station.set_menu_open(true)
	controls.enabled = false
	controls.release_mouse()
	menu.closed.connect(func():
		await get_tree().process_frame
		if Place.battle_active():
			return # the battle view has the screen; _check_battle brings everything back after
		_close_panel(), CONNECT_ONE_SHOT)


## The dock market of a Builder's Carrier Dock, or supply contracts.
func _open_trade(page: String, builder := "") -> void:
	if page == "market":
		var why := WarInfo.dock_problem(builder) if WarInfo.dock_finished(builder) else "%s has no Carrier Dock open." % builder
		if why != "":
			_say(why)
			if _station:
				_station._say(why)
			return
	_trade.open(page, builder)
	_open_panel(_trade)


## Asks the server to start a raid on a facility; the raid begins when it answers.
func board(planet_id: String, slot: int) -> void:
	_raid_from = _docked
	Net.send({"type": "raid_start", "planet": planet_id, "slot": slot})


func _stash_value() -> int:
	var total := 0
	for k in _me().get("stash", []):
		total += int(Net.catalog.get("items", {}).get(k.item, {}).get("value", 0)) * int(k.qty)
	return total


func _near_rock() -> bool:
	var field := System.diff(System.FIELD_POS, _pos)
	if field.length() > 5_000.0:
		return false
	for rock in _rocks:
		if (field + rock.node.position).length() < rock.radius + MINE_RANGE:
			return true
	return false


## For tests: put the ship somewhere, stopped.
func teleport(pos: Array) -> void:
	_approach = {}
	_dock_wait = ""
	_pos = pos.duplicate()
	flight.velocity = Vector3.ZERO
	flight.throttle = 0.0


func rock_position(i: int) -> Array:
	return System.offset(System.FIELD_POS, _rocks[i].node.position)


func _me() -> Dictionary:
	if Net.state.is_empty():
		return {}
	return Net.state.pilots.get(Net.my_name, {})


func _cargo(resource: String) -> int:
	var me := _me()
	return int(me.get("cargo", {}).get(resource, 0)) if not me.is_empty() else 0


# --- HUD -------------------------------------------------------------------------

func _say(text: String) -> void:
	_message = text
	_message_time = 4.0


func _update_hud(delta: float) -> void:
	var colour: Color = controls.hud_color()
	_hud.modulate = colour
	_hint.modulate = Color(colour, 0.6)
	_chat.modulate = colour.lightened(0.3)
	_nav.colour = colour
	_accent.albedo_color = colour
	_accent.emission = colour

	var me := _me()
	var job := Net.open_job()
	var stash: Array = me.get("stash", [])
	var side := WarInfo.my_faction()
	var hold: Dictionary = me.get("hold", {})
	_info.text = "%s · %s%s%s\nIce in cargo %d\nCredits %d   Reputation %d\n%s%s%s" % [
		Net.my_name,
		WarInfo.faction_name(side) if side != "" else "no faction yet",
		" · admin" if Net.admin else "",
		" · fleet carrier (demo)" if _carrier else "",
		_cargo("ice"),
		int(me.get("credits", 0)),
		int(me.get("reputation", 0)),
		("Job #%d: deliver %s %d/%d to %s's Star Port" % [job.id, job.resource, job.delivered, job.amount, Net.planet(job.get("planet", "aster")).get("name", "Aster")]) if not job.is_empty() else "No open jobs",
		("\nRaided loot: %d items, about %d credits at the Fence" % [stash.size(), _stash_value() / 2]) if not stash.is_empty() else "",
		("\nWar goods hold: %s" % WarInfo.goods_list(hold)) if WarInfo.goods_list(hold, "") != "" else "",
	]

	var lines := []
	match flight.mode:
		Flight.Mode.PHASE:
			lines.append("PHASE-SHIFT  %s" % System.format_speed(flight.speed()))
		Flight.Mode.CHARGING:
			lines.append("PHASE-SHIFT CHARGING  %.1f s" % flight.charge_left)
		_:
			lines.append("%s" % System.format_speed(flight.speed()))
	lines.append("Throttle %d%%" % roundi(flight.throttle * 100))
	lines.append("DRIFT (flight assist off)" if flight.drift else "Flight assist on")
	if flight.mode == Flight.Mode.SUBLIGHT:
		if flight.boost_left > 0.0:
			lines.append("BOOSTING")
		elif flight.boost_ready():
			lines.append("Boost ready")
		else:
			lines.append("Boost in %.1f s" % flight.boost_cooldown if flight.boost_cooldown > 0.0 else "Boost: low engine power")
	if _flight_env().mass_locked:
		lines.append("MASS LOCKED")
	var menu = _battle_script("battle_menu")
	if menu and not menu.queued.is_empty():
		var q: Dictionary = menu.queued
		lines.append("In the %s queue at %s: %s" % [Net.catalog.get("campaign", {}).get("modes", {}).get(str(q.mode), {}).get("name", "match"), WarInfo.planet(str(q.planet)).get("name", ""), menu.time_text(Net.now_ms() - float(q.since))])
	_flight_info.text = "\n".join(lines)

	_hint.text = "%s map   %s chat   %s settings   %s phase-shift   %s drift" % [
		controls.binding_text("nav_map", false), controls.binding_text("chat", false),
		controls.binding_text("menu", false), controls.binding_text("phase", false), controls.binding_text("drift", false)]
	if _carrier:
		_hint.text += "\n%s leave seat (walk your carrier)   %s outside view" % [controls.binding_text("leave_seat", false), controls.binding_text("outside_view", false)]
	_seat_button.visible = _carrier and _approach.is_empty() and _dock_wait == ""
	_seat_button.text = "Leave seat (%s)" % controls.binding_text("leave_seat", false)
	_seat_button.position.y = 70.0

	_message_time -= delta
	if _message_time > 0.0 and _prompt.text == "":
		_prompt.text = _message
	elif _message_time > 0.0:
		_prompt.text = _message + "\n" + _prompt.text

	# Cockpit monitors.
	_cockpit_screens[0].modulate = colour
	_cockpit_screens[1].modulate = colour
	_cockpit_screens[0].text = "SHIELDS %d%%  HULL %d%%\nPOWER  SYS %s  ENG %s  WEP %s" % [
		flight.shields, flight.hull, _pips_text(Flight.SYS), _pips_text(Flight.ENG), _pips_text(Flight.WEP)]
	if _route.is_empty():
		_cockpit_screens[1].text = "NAV\nNo destination"
	else:
		var d := System.distance(_route[0].pos, _pos)
		_cockpit_screens[1].text = "NAV  %s\n%s" % [_route[0].name, System.format_distance(d)]
	_hud.queue_redraw()


func _pips_text(system: int) -> String:
	return "%.1f" % (flight.pips[system] / 2.0)


func _draw_hud() -> void:
	var size := _hud.size
	var c := size * 0.5
	var white := Color.WHITE
	var font := _hud.get_theme_default_font()

	# Reticle and the mouse's virtual stick.
	_hud.draw_arc(c, 6, 0, TAU, 24, white, 1.5)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_hud.draw_arc(c, 110, 0, TAU, 64, Color(white, 0.15), 1.0)
		var m: Vector2 = c + controls.mouse_stick() * 110.0
		_hud.draw_line(c, m, Color(white, 0.35), 1.0)
		_hud.draw_circle(m, 3, Color(white, 0.8))

	# Velocity marker: where the ship is actually going. With drift on this separates from the nose.
	if flight.speed() > 1.0 and flight.mode == Flight.Mode.SUBLIGHT:
		var v := flight.velocity.normalized() * 1000.0
		if not _camera.is_position_behind(v):
			var p := _camera.unproject_position(v)
			_hud.draw_arc(p, 9, 0, TAU, 16, white, 1.0)
			_hud.draw_line(p + Vector2(-15, 0), p + Vector2(-9, 0), white, 1.0)
			_hud.draw_line(p + Vector2(9, 0), p + Vector2(15, 0), white, 1.0)
			_hud.draw_line(p + Vector2(0, -15), p + Vector2(0, -9), white, 1.0)

	# Destination marker, or an arrow at the edge of the screen pointing toward it.
	if not _route.is_empty():
		var dest: Dictionary = _route[0]
		var dir := System.diff(dest.pos, _pos).normalized() * 1000.0
		var dist := System.distance(dest.pos, _pos)
		var text := "%s  %s" % [dest.name, System.format_distance(dist)]
		var closing := flight.velocity.dot(dir.normalized())
		if flight.mode == Flight.Mode.PHASE:
			text += "  ETA %s" % System.format_time(flight.phase_eta(_dest_distance()))
		elif closing > 1.0:
			text += "  ETA %s" % System.format_time(_dest_distance() / closing)
		if not _camera.is_position_behind(dir) and Rect2(Vector2.ZERO, size).grow(-30).has_point(_camera.unproject_position(dir)):
			var p := _camera.unproject_position(dir)
			var pts := PackedVector2Array([p + Vector2(0, -10), p + Vector2(10, 0), p + Vector2(0, 10), p + Vector2(-10, 0), p + Vector2(0, -10)])
			_hud.draw_polyline(pts, white, 2.0)
			_hud.draw_string(font, p + Vector2(14, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, white)
		else:
			var local := _camera.global_basis.inverse() * dir
			var flat := Vector2(local.x, -local.y)
			if flat.length() < 0.001:
				flat = Vector2(0, 1)
			var p := c + flat.normalized() * minf(size.x, size.y) * 0.42
			var a := flat.angle()
			var tri := PackedVector2Array([p + Vector2(14, 0).rotated(a), p + Vector2(-8, -8).rotated(a), p + Vector2(-8, 8).rotated(a)])
			_hud.draw_colored_polygon(tri, white)
			_hud.draw_string(font, p + Vector2(-60, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, white)

	# Power distributor, bottom left, as in Elite: three columns of four pips over capacitor bars.
	var base := Vector2(24, size.y - 30)
	var names := ["SYS", "ENG", "WEP"]
	for i in 3:
		var x := base.x + i * 46.0
		for pip in 4:
			var fill := clampf(flight.pips[i] / 2.0 - pip, 0.0, 1.0)
			var r := Rect2(x, base.y - 30 - pip * 12.0, 36, 9)
			_hud.draw_rect(r, Color(white, 0.2), false, 1.0)
			if fill > 0.0:
				_hud.draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), white)
		var cap: float = flight.capacitor[i] / Flight.CAPACITOR[i]
		_hud.draw_rect(Rect2(x, base.y - 14, 36, 4), Color(white, 0.2))
		_hud.draw_rect(Rect2(x, base.y - 14, 36 * cap, 4), white)
		_hud.draw_string(font, Vector2(x + 4, base.y + 4), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)

	# Drive status icons, bottom centre: boost, phase-shift, and mass lock when it applies.
	var icons := []
	if flight.mode == Flight.Mode.SUBLIGHT:
		var ready := flight.boost_left > 0.0 or flight.boost_ready()
		var cool := 1.0 - clampf(flight.boost_cooldown / flight.stats.boost_cooldown, 0.0, 1.0)
		icons.append([HUD_ICONS.boost, 1.0 if ready else 0.3, 1.0 if ready else cool])
	var phase_alpha := 1.0 if flight.mode == Flight.Mode.PHASE else 0.3
	var phase_fill := 0.0
	if flight.mode == Flight.Mode.CHARGING:
		phase_alpha = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
		phase_fill = 1.0 - flight.charge_left / flight.stats.phase_charge
	icons.append([HUD_ICONS.phase, phase_alpha, phase_fill])
	if _flight_env().mass_locked:
		icons.append([HUD_ICONS.mass_lock, 1.0, 0.0])
	var ix := c.x - icons.size() * 26.0
	for icon in icons:
		var r := Rect2(ix + 4, size.y - 64, 44, 44)
		_hud.draw_texture_rect(icon[0], r, false, Color(white, icon[1]))
		if icon[2] > 0.0 and icon[2] < 1.0:
			_hud.draw_arc(r.get_center(), 27, -PI / 2, -PI / 2 + TAU * icon[2], 32, white, 2.0)
		ix += 52.0

	# Shields and hull.
	var sx := base.x + 150.0
	_hud.draw_string(font, Vector2(sx, base.y - 34), "Shields", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
	_hud.draw_rect(Rect2(sx, base.y - 28, 120, 6), Color(white, 0.2))
	_hud.draw_rect(Rect2(sx, base.y - 28, 120 * flight.shields / 100.0, 6), white)
	_hud.draw_string(font, Vector2(sx, base.y - 8), "Hull", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
	_hud.draw_rect(Rect2(sx, base.y - 2, 120, 6), Color(white, 0.2))
	_hud.draw_rect(Rect2(sx, base.y - 2, 120 * flight.hull / 100.0, 6), white)

	# Throttle bar, right side.
	var tx := size.x - 40.0
	var top := size.y * 0.35
	var height := size.y * 0.3
	var zero := top + height * 2.0 / 3.0
	_hud.draw_rect(Rect2(tx, top, 10, height), Color(white, 0.15))
	_hud.draw_line(Vector2(tx - 4, zero), Vector2(tx + 14, zero), white, 1.0)
	var t := flight.throttle
	var h := t * height * 2.0 / 3.0 if t >= 0 else t * height / 3.0
	_hud.draw_rect(Rect2(tx, zero - maxf(h, 0.0), 10, absf(h)), white)


# --- Server events ----------------------------------------------------------------

func _on_state(_state: Dictionary) -> void:
	_refresh_refusal()
	_apply_ship_class()
	_sync_stations()
	# A pilot with no side is asked to pick one, once a session ("Not now" leaves it to the ship's menu).
	var side := WarInfo.my_faction()
	if _picker.visible and side != "":
		_close_panel()
		_say("You joined %s." % WarInfo.the(side))
	elif side == "" and not _picker_dismissed and not _panel_open() and _raid == null and not WarInfo.factions().is_empty():
		_show_picker()
	_picker.refresh()
	if _war_panel.visible:
		_war_panel.refresh()
	if _trade.visible:
		_trade.refresh()
	if _docked != "" and _raid == null and _station and _dock_panel.visible:
		_refresh_dock()


# --- Raids -------------------------------------------------------------------------------

func _on_raid_event(msg: Dictionary) -> void:
	if msg.ev == "begin" and _raid == null:
		_enter_raid(msg.run)


func _enter_raid(briefing: Dictionary) -> void:
	flight.velocity = Vector3.ZERO
	flight.throttle = 0.0
	controls.enabled = false
	_hide_panels()
	_leave_place()
	_set_space_visible(false)
	_raid = Raid.new(briefing)
	_raid.controls = controls
	_raid.finished.connect(_leave_raid)
	add_child(_raid)


func _leave_raid(result: Dictionary) -> void:
	_raid.queue_free()
	_raid = null
	var back := _raid_from if _stations.has(_raid_from) else "aster"
	teleport(System.offset(_stations[back].pos, Vector3(0, 0, 900)))
	dock(back)
	if result.get("outcome", "") == "destroyed":
		# The ship went up with the facility: a replacement waits for you on your pad.
		_say("Your ship went down with the facility. A replacement is waiting on pad 06 at %s." % _stations[back].name)
	else:
		_say("Back in your ship at %s. The black market terminal is in the Cantina." % _stations[back].name)


func _set_space_visible(on: bool) -> void:
	_set_view("flight" if on else "away")


## What's drawn of space: "flight" (all of it, from the seat), "aboard" (walking a carrier: space
## and the sky out of its windows, but not your own hull, the cockpit or the flight HUD; the sun
## casts shadows so it shines in through them) or "away" (in a station, a base, a raid).
func _set_view(mode: String) -> void:
	var space_on := mode != "away"
	_space.visible = space_on
	_dust.visible = mode == "flight"
	_ship.visible = mode == "flight"
	_sky_layer.visible = space_on
	_hud_layer.visible = mode == "flight"
	_sun.shadow_enabled = mode == "aboard"
	if mode != "aboard":
		_space.basis = Basis()
	# Aboard, the interior is lit like a station's; out in space it's the dim light of space.
	var env := _world_env.environment
	env.ambient_light_color = Color(0.55, 0.62, 0.7) if mode == "aboard" else Color(0.2, 0.24, 0.32)
	env.ambient_light_energy = 0.6 if mode == "aboard" else 1.0
	env.glow_enabled = mode == "aboard"
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if mode == "aboard" else Environment.TONE_MAPPER_LINEAR
	# Name tags out in space show through everything in flight, but not through a carrier's walls.
	for node in _space.find_children("Tag", "Label3D", true, false):
		(node as Label3D).no_depth_test = mode != "aboard"
	_sky.render_target_update_mode = SubViewport.UPDATE_ALWAYS if space_on else SubViewport.UPDATE_DISABLED
	if space_on and _world_env.get_parent() == null:
		add_child(_world_env)
	elif not space_on and _world_env.get_parent() != null:
		remove_child(_world_env)


## A sector battle's RTS view (game/battle/battle_view.gd) has its own camera, world and input:
## while it's up, everything of ours is hidden and ignores the keys; when it closes, back to
## where you were (the carrier's Command Deck, at the holo table).
func _check_battle() -> void:
	var on := Place.battle_active()
	if on == _battle:
		return
	_battle = on
	controls.enabled = not on and _station == null and _raid == null
	if on:
		_hide_panels()
		_dock_panel.visible = false
		_battle_env = []
		if _world_env.get_parent() != null:
			_battle_env.append(_world_env)
			remove_child(_world_env)
		for node in [_space, _ship]:
			node.visible = false
		_sky_layer.visible = false
		_hud_layer.visible = false
		if _station:
			_station.battle_hide(true)
		return
	if _station:
		_station.battle_hide(false)
		_set_view("aboard" if _station is Carrier else "away")
		_station._camera.make_current()
		if _station.seated:
			_show_ship_menu()
		else:
			_station.set_menu_open(false)
	elif _raid == null:
		_set_view("flight")
		_set_outside(_outside)
		_refresh_focus()
	_battle_env = []


## A new connection (the Wi-Fi came back, the server restarted, a new admin key): the server has
## forgotten our pad, our space and whether our carrier takes visitors. Ask for the pad again, then
## enter our space afresh with where we stand (_sync_space, next frame; crew go straight back
## aboard), the place's walkers waiting for the server's new word on who is there.
func _rejoin() -> void:
	if not _berth.is_empty() and not _berth.get("local", false):
		Net.send({"type": "dock_request", "station": _berth.station})
	if not Carrier.open_to_visitors:
		Net.send({"type": "ship_open", "open": false})
	var was := _space_id
	_space_id = ""
	if _station:
		_station.walkers.rejoin()
	if was.begins_with("ship:") and was != "ship:" + Net.my_name and not _crew.is_empty():
		var msg := {"type": "enter_space", "space": was}
		var pose: Dictionary = _station.walker_pose() if _station and _station.has_method("walker_pose") else {}
		if not pose.is_empty():
			msg.merge({"pos": [pose.pos.x, pose.pos.y, pose.pos.z], "yaw": pose.yaw, "anim": pose.anim})
		Net.send(msg)
		_space_id = was


## One of the sector battles' scripts (game/battle/<name>.gd), loaded by path so the explorer still
## runs if they fail to load; null then.
var _battle_scripts := {}
func _battle_script(name: String):
	if not _battle_scripts.has(name):
		var path := "res://battle/%s.gd" % name
		var s = load(path) if ResourceLoader.exists(path) else null
		_battle_scripts[name] = s if s is GDScript and s.can_instantiate() else null
	return _battle_scripts[name]


## Server messages for the carrier and the shared spaces (Net.message).
func _on_net_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"welcome":
			_rejoin()
		"campaign_queued":
			var menu = _battle_script("battle_menu")
			if menu:
				menu.queued = msg if msg.get("planet") != null else {}
		"battle_joined":
			# Matchmaking put us in a match: the RTS view takes over, wherever we are. (The Sector
			# Battles screen, if it's open, closes itself.)
			var menu = _battle_script("battle_menu")
			var view = _battle_script("battle_view")
			if menu:
				menu.queued = {}
			if view and not view.active:
				view.open(self, msg)
		"defense_joined":
			# Matchmaking put us in a Sector Defense squad: the first-person view takes over.
			var menu = _battle_script("battle_menu")
			if menu:
				menu.queued = {}
			var path := "res://defense/defense_view.gd"
			var dv = load(path) if ResourceLoader.exists(path) else null
			if dv and dv.can_instantiate() and not dv.active:
				dv.open(self, msg)
		"facility_joined":
			# Matchmaking put us in a Facility Battle: the first-person view takes over.
			var menu = _battle_script("battle_menu")
			if menu:
				menu.queued = {}
			var path := "res://facility/facility_view.gd"
			var fv = load(path) if ResourceLoader.exists(path) else null
			if fv and fv.can_instantiate() and not fv.active:
				fv.open(self, msg)
		"supremacy_joined":
			# Matchmaking put us in a Supremacy battle: its first-person view takes over.
			var menu = _battle_script("battle_menu")
			if menu:
				menu.queued = {}
			var path := "res://supremacy/supremacy_view.gd"
			var sv = load(path) if ResourceLoader.exists(path) else null
			if sv and sv.can_instantiate() and not sv.active:
				sv.open(self, msg)
		"starfight_joined":
			# Matchmaking put us in a Space Battle: the starfighter's cockpit takes over.
			var menu = _battle_script("battle_menu")
			if menu:
				menu.queued = {}
			var path := "res://space/space_view.gd"
			var spv = load(path) if ResourceLoader.exists(path) else null
			if spv and spv.can_instantiate() and not spv.active:
				spv.open(self, msg)
		"dock_granted":
			var st := str(msg.get("station", ""))
			if not _stations.has(st):
				return
			_berth = {"station": st, "copy": int(msg.get("copy", 1)), "pad": clampi(int(msg.get("pad", 1)), 1, BERTHS)}
			if _dock_wait == st:
				_dock_wait = ""
				if _carrier and _station == null:
					_start_approach(st) # (away from the helm, F near the station flies it in later)
			elif _carrier and _docked == st and _crew.is_empty():
				# Docked before the answer came (back from a raid, say): over to the real berth.
				_snap_to_berth()
				if _station is Carrier:
					_update_carrier(_station)
				if _dock_panel.visible:
					_refresh_dock()
		"berth_granted":
			if _land_wait != "" and str(msg.get("base", "")) == _land_wait:
				_berth_granted(_land_wait, int(msg.get("berth", 0)))
		"space_joined":
			if _boarding != "" and str(msg.get("space", "")) == "ship:" + _boarding:
				_boarded(msg)
		"error":
			if _boarding != "":
				if _station:
					_station._say("Can't board: %s" % str(msg.get("reason", "")), 4.0)
				_boarding = ""
			elif _dock_wait != "":
				_berth_anyway(_dock_wait)
			elif _land_wait != "":
				_land_wait = ""
				_land_problem = str(msg.get("reason", ""))
				if _dock_panel.visible:
					_refresh_dock()
		"ship":
			if _others.has(int(msg.get("id", -1))):
				var o: Dictionary = _others[int(msg.id)]
				o.over = str(msg.get("over", ""))
				o.berth = msg.get("berth", {}) if msg.get("berth") is Dictionary else {}
				o.system = str(msg.get("system", "teal-prime"))
				# Aboard someone's carrier that jumped: we went with it.
				if not _crew.is_empty() and o.name == _crew.owner and o.system != System.current and _jump.is_empty():
					_enter_system(o.system)
		"carrier_jump":
			_start_jump(msg)


func _on_ship_moved(id: int, pilot_name: String, pos: Vector3, rot: Vector3) -> void:
	# Net turns positions into Vector3 for convenience, but they arrive as 64-bit numbers.
	# Use the raw array when Net provides it.
	var world: Array = Net.last_ship_pos if Net.last_ship_pos.size() == 3 else [pos.x, pos.y, pos.z]
	if not _others.has(id):
		var node := Node3D.new()
		var tag := Label3D.new()
		tag.name = "Tag"
		tag.text = pilot_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = true
		tag.pixel_size = 0.0006
		tag.font_size = 40
		tag.no_depth_test = true
		node.add_child(tag)
		_space.add_child(node)
		_others[id] = {"node": node, "pos": world, "shown": world.duplicate(), "name": pilot_name, "rot": rot, "over": "", "berth": {}}
		_set_other_model(_others[id])
		node.visible = _space.visible
	_others[id].pos = world
	_others[id].rot = rot
	_others[id].node.rotation = rot


func _on_ship_left(id: int) -> void:
	if _others.has(id):
		_others[id].node.queue_free()
		_others.erase(id)
		_route = _route.filter(func(r): return r.id != "pilot-%d" % id)
