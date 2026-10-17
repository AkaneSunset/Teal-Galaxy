extends Node3D
## Explorer mode (PC): fly from the pilot's seat around Teal Prime, mine ice, deliver jobs,
## and raid Builders' facilities on foot (raid.gd).
## Every Builder planet has a High Port in orbit. Docking there opens the transit menu, which
## shuttles the pilot down to the planet's Spaceport (jobs and the Fence) or into one of its
## facilities to raid it.
## Everything is built from simple shapes in code, so there are no art assets yet.
##
## The ship always sits at the scene origin and the system is drawn around it (a floating
## origin), because positions out here are far too large for 32-bit coordinates.
## See controls.gd for the bindings; Esc opens settings to change them.

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
var _stations := {} # planet id -> {"node", "pos", "name", "planet"}: the High Port over each Builder planet
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
var _raid_from := "" # the High Port (planet id) the raid left from, to return to
var _station: Node3D # where the ship is landed: the High Port's hangar (station.gd) or a base (surface.gd)
var _menu_standing := false # the ship's menu is up over the place while you stand (the transit terminal)
var _world_env: WorldEnvironment
var _sky_layer: CanvasLayer
var _hud_layer: CanvasLayer
var _route: Array = []

var _hud: Control
var _info: Label
var _flight_info: Label
var _prompt: Label
var _hint: Label
var _phase_tint: ColorRect
var _nav: Control
var _settings: Control
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
	_build_sky()
	_build_local_space()
	_build_ship()
	_build_hud()
	_load_waypoints()

	Net.state_changed.connect(_on_state)
	Net.ship_moved.connect(_on_ship_moved)
	Net.ship_left.connect(_on_ship_left)
	Net.server_error.connect(func(reason): _say("Server: " + reason))
	Net.raid_event.connect(_on_raid_event)
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
	add_child(_sun)


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
	add_child(_field)

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
	add_child(_dust)


## A High Port: the orbital station over a Builder planet, where pilots dock to go down to the surface.
func _add_station(planet_id: String, station_name: String, pos: Array) -> void:
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
	port.add_child(tag)
	add_child(port)
	_stations[planet_id] = {"node": port, "pos": pos, "name": station_name, "planet": planet_id}


## Every Builder home planet gets a High Port; planets beyond Aster are added to the sky as they appear.
func _sync_stations() -> void:
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

	var frame := Color(0.12, 0.13, 0.15)
	var dash := _mesh(BoxMesh.new(), frame)
	dash.mesh.size = Vector3(1.7, 0.4, 0.55)
	dash.position = Vector3(0, -0.72, -0.95)
	dash.rotation_degrees.x = -18
	_ship.add_child(dash)
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
		_ship.add_child(strut)
	var top := _mesh(BoxMesh.new(), frame)
	top.mesh.size = Vector3(1.8, 0.06, 0.06)
	top.position = Vector3(0, 0.82, -1.05)
	_ship.add_child(top)

	# Two dashboard monitors: ship systems on the left, navigation on the right.
	for x in [-0.4, 0.4]:
		var panel := _mesh(QuadMesh.new(), Color(0.02, 0.04, 0.05))
		panel.mesh.size = Vector2(0.62, 0.2)
		panel.position = Vector3(x, -0.43, -0.74)
		panel.rotation_degrees.x = -32
		_ship.add_child(panel)
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

	var dock_layer := CanvasLayer.new()
	dock_layer.layer = 5
	add_child(dock_layer)
	_build_dock_panel(dock_layer)

	_settings = SettingsMenu.new()
	_settings.controls = controls
	_settings.visible = false
	layer.add_child(_settings)
	_settings.closed.connect(func(): _settings.visible = false; _refresh_focus())


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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


func _refresh_focus() -> void:
	var overlay: bool = _settings.visible or _nav.visible or _dock_panel.visible
	controls.enabled = not overlay and not _chat.is_typing()
	if overlay:
		controls.release_mouse()
	else:
		controls.capture_mouse()


# --- Flying ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _raid or _station:
		return
	if controls.drift_hold and controls.enabled:
		flight.drift = Input.is_action_pressed("drift")
	var input: Dictionary = controls.read()
	if _docked != "":
		flight.velocity = Vector3.ZERO
		flight.throttle = 0.0
	for said in flight.step(input, _flight_env(), delta):
		_say(said)
	_pos = System.offset(_pos, flight.velocity * delta)
	_ship.basis = flight.basis
	_collide()
	if flight.hull <= 0.0:
		_respawn()

	_place_world(delta)
	for stop in _route:
		var pilot_id: int = int(stop.id.substr(6)) if stop.id.begins_with("pilot-") else 0
		if _others.has(pilot_id):
			stop.pos = _others[pilot_id].shown
	_check_arrival()

	_send_timer -= delta
	if _send_timer <= 0:
		_send_timer = SEND_EVERY
		var r := flight.basis.get_euler()
		Net.send({"type": "ship", "pos": _pos, "rot": [r.x, r.y, r.z]})

	_mine_timer -= delta
	if _docked == "":
		_interact()
	else:
		_prompt.text = ""
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = 0.25
		_nav.refresh(_nav_items(), _pos, flight.forward())
	_update_hud(delta)


func _flight_env() -> Dictionary:
	var altitude := INF
	for body in System.bodies():
		altitude = minf(altitude, System.distance(body.pos, _pos) - body.radius)
	return {
		"mass_locked": _near_station(Flight.MASS_LOCK_DISTANCE) != "",
		"altitude": altitude,
		"dest_distance": _dest_distance(),
	}


func _place_world(delta: float) -> void:
	for id in _stations:
		var port: Node3D = _stations[id].node
		port.position = System.diff(_stations[id].pos, _pos)
		port.visible = port.position.length() < LOCAL_RANGE
		port.get_node("Ring").rotate_y(0.03 * delta)
	_field.position = System.diff(System.FIELD_POS, _pos)
	_field.visible = _field.position.length() < LOCAL_RANGE

	for id in _others:
		var o: Dictionary = _others[id]
		var t := minf(1.0, delta * 10.0)
		o.shown = [lerpf(o.shown[0], o.pos[0], t), lerpf(o.shown[1], o.pos[1], t), lerpf(o.shown[2], o.pos[2], t)]
		o.node.position = System.diff(o.shown, _pos)
		o.node.visible = o.node.position.length() < LOCAL_RANGE

	var to_star := System.diff(System.STAR.pos, _pos).normalized()
	_sun.basis = Basis.looking_at(-to_star, Vector3.UP if absf(to_star.y) < 0.99 else Vector3.RIGHT)
	_sky.follow(_pos, _camera.global_basis)

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
		var reach: float = s[1] + SHIP_RADIUS
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
		items.append({"id": "port-" + id, "name": st.name, "kind": "landmark", "pos": st.pos, "standoff": 5_500.0, "local": id == "aster"})
	items.append({"id": "field", "name": System.FIELD_NAME, "kind": "landmark", "pos": System.FIELD_POS, "standoff": 2_500.0, "local": true})
	for w in _waypoints:
		items.append({"id": w.id, "name": w.name, "kind": "waypoint", "pos": w.pos, "standoff": 0.0})
	for id in _others:
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
	elif _near_station(DOCK_RANGE) != "":
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
## pilot's seat, with the ship's menu up.
func dock(planet_id: String) -> void:
	_docked = planet_id
	flight.velocity = Vector3.ZERO
	flight.throttle = 0.0
	_land_in(Station.new(planet_id), false)


## Moves the ship (and you in it) to a place: the High Port's hangar, or a base on the surface.
func _land_in(place: Node3D, at_base: bool) -> void:
	_leave_place()
	_at_spaceport = at_base
	controls.enabled = false
	_set_space_visible(false)
	_station = place
	_station.controls = controls
	_station.seated_down.connect(_show_ship_menu)
	_station.wants_menu.connect(_open_standing_menu)
	_station.service.connect(func(kind):
		if kind == "repair":
			flight.repair())
	add_child(_station)
	_show_ship_menu()


func _leave_place() -> void:
	if _station:
		_station.queue_free()
		_station = null
	_menu_standing = false
	_dock_panel.visible = false


## Seated in your ship: the ship's menu, with the mouse free to click it.
func _show_ship_menu() -> void:
	_menu_standing = false
	_dock_panel.visible = true
	controls.release_mouse()
	_refresh_dock()


## Leave the pilot's seat and walk down the ramp.
func _leave_seat() -> void:
	_dock_panel.visible = false
	_station.stand()


## The transit terminal in the station: the same trips, while you stand at the console.
func _open_standing_menu() -> void:
	_menu_standing = true
	_station.set_menu_open(true)
	_dock_panel.visible = true
	_refresh_dock()


func _close_standing_menu() -> void:
	_menu_standing = false
	_dock_panel.visible = false
	if _station:
		_station.set_menu_open(false)


## Your ship flies down to the planet's surface and lands at its Builder's base, beside the Spaceport.
func _fly_to_base() -> void:
	var p := Net.planet(_docked)
	_land_in(Surface.new(_docked), true)
	_say("Landed at %s's base on %s." % [p.get("owner", "the Builder"), p.get("name", _docked)])


## Back up to orbit: from a base to the High Port's hangar.
func _fly_to_station() -> void:
	dock(_docked)


## Launch from the High Port: the ship lifts off the pad and flies out of the hangar into space.
func undock() -> void:
	var from := _docked
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


## Facilities on a planet's satellite sites (and any still on its own pads).
func facilities_on(planet_id: String) -> Array:
	return Net.facilities().filter(func(f): return f.planet == planet_id or Net.planet(f.planet).get("parent", "") == planet_id)


func _refresh_dock() -> void:
	if _docked == "" or Net.state.is_empty():
		return
	for child in _dock_list.get_children():
		child.queue_free()
	var p := Net.planet(_docked)
	var owner: String = str(p.get("owner", "nobody")) if p.get("owner") != null else "nobody"
	if _at_spaceport:
		_dock_title.text = "Landed at %s's base on %s" % [owner, p.get("name", _docked)]
		var job := Net.open_job(_docked)
		var stash: Array = _me().get("stash", [])
		if job.is_empty():
			_dock_note("No open jobs at this Spaceport.")
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
		_dock_button("Leave your seat and walk around the base", _leave_seat)
		_dock_button("Fly back up to %s" % _stations[_docked].name, _fly_to_station)
	else:
		if _menu_standing:
			_dock_title.text = "Surface Transit, %s" % _stations[_docked].name
		else:
			_dock_title.text = "In your ship on pad 06, %s" % _stations[_docked].name
			_dock_button("Leave your seat and walk into the station", _leave_seat)
		if Net.has_building("spaceport", _docked):
			_dock_button("Fly down to %s's base and land at the Spaceport" % owner, _fly_to_base)
		else:
			_dock_note("%s has no Spaceport yet." % p.get("name", _docked))
		var facs := facilities_on(_docked)
		if facs.is_empty():
			_dock_note("No facilities to raid on %s." % p.get("name", _docked))
		for f in facs:
			var b: Dictionary = f.building
			var vault := 0
			for id in b.vault:
				vault += int(b.vault[id])
			var cool := (float(b.get("cooldownUntil", 0)) - Net.now_ms()) / 1000.0
			var site := Net.planet(f.planet)
			var fac_name: String = site.name if site.get("kind", "") == "satellite" else f.name
			var label := "Raid %s (%s's): security tier %d, %d items in the vault" % [fac_name, owner, int(b.security), vault]
			if not Net.raid_on(f.planet, f.slot).is_empty():
				_dock_note("%s: someone is already inside" % fac_name)
			elif cool > 0:
				_dock_note("%s: security on alert after a raid (%d s)" % [fac_name, ceili(cool)])
			else:
				_dock_button(label, board.bind(f.planet, f.slot))
		if _menu_standing:
			_dock_button("Close", _close_standing_menu)
		else:
			_dock_button("Launch", undock)
	var first := _dock_list.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	if not first.is_empty():
		first[0].grab_focus.call_deferred()


func _dock_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	_dock_list.add_child(b)


func _dock_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
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
	_info.text = "%s\nIce in cargo %d\nCredits %d   Reputation %d\n%s%s" % [
		Net.my_name,
		_cargo("ice"),
		int(me.get("credits", 0)),
		int(me.get("reputation", 0)),
		("Job #%d: deliver %s %d/%d to %s's Spaceport" % [job.id, job.resource, job.delivered, job.amount, Net.planet(job.get("planet", "aster")).get("name", "Aster")]) if not job.is_empty() else "No open jobs",
		("\nRaided loot: %d items, about %d credits at the Fence" % [stash.size(), _stash_value() / 2]) if not stash.is_empty() else "",
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
	_flight_info.text = "\n".join(lines)

	_hint.text = "%s map   %s chat   %s settings   %s phase-shift   %s drift" % [
		controls.binding_text("nav_map", false), controls.binding_text("chat", false),
		controls.binding_text("menu", false), controls.binding_text("phase", false), controls.binding_text("drift", false)]

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
	_sync_stations()
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
	for node in [_ship, _dust, _sun, _sky_layer, _hud_layer]:
		node.visible = on
	_field.visible = on
	for id in _stations:
		_stations[id].node.visible = on
	for id in _others:
		_others[id].node.visible = on
	_sky.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on and _world_env.get_parent() == null:
		add_child(_world_env)
	elif not on and _world_env.get_parent() != null:
		remove_child(_world_env)


func _on_ship_moved(id: int, pilot_name: String, pos: Vector3, rot: Vector3) -> void:
	# Net turns positions into Vector3 for convenience, but they arrive as 64-bit numbers.
	# Use the raw array when Net provides it.
	var world: Array = Net.last_ship_pos if Net.last_ship_pos.size() == 3 else [pos.x, pos.y, pos.z]
	if not _others.has(id):
		var node := Node3D.new()
		node.add_child(Models.starter_ship())
		var tag := Label3D.new()
		tag.text = pilot_name
		tag.position = Vector3(0, 10, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = true
		tag.pixel_size = 0.0006
		tag.font_size = 40
		tag.no_depth_test = true
		node.add_child(tag)
		add_child(node)
		_others[id] = {"node": node, "pos": world, "shown": world.duplicate(), "name": pilot_name}
	_others[id].pos = world
	_others[id].node.rotation = rot


func _on_ship_left(id: int) -> void:
	if _others.has(id):
		_others[id].node.queue_free()
		_others.erase(id)
		_route = _route.filter(func(r): return r.id != "pilot-%d" % id)
