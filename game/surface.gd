extends "res://place.gd"
## A Builder's base on their planet's surface, where your ship lands on one of the Star Port's
## berths. It's the same base the Builder sees on their phone (base_layout.gd): the same icy terrain
## (terrain.gd, generated from the planet id), the Command Centre with its eight nodes around it,
## the streets and the wall, every building at the same place and level, live from the server.
## The base is about 300 m across; your ship lands on the front apron, inside the gate.
##
## You arrive seated in your ship (see place.gd); the ship's menu has the Star Port's services.
## Walk down the ramp to look around the base on foot; the base plate's edge keeps you on it.
## Once the Builder's Carrier Dock is finished, a console in front of it opens the dock market
## (trade_panel.gd), for pilots of the Builder's faction.

const BaseModels := preload("res://base_models.gd")
const Layout := preload("res://base_layout.gd")
const Terrain := preload("res://terrain.gd")

var berth := 0 # the Star Port berth your ship is on (from 0)
var shuttle := false # came down on the shuttle from the High Port, on foot: your ship stayed up there
var _owner := ""
var _base: Node3D
var _pads := [] # per slot (base_layout.gd): {"root", "key", "model", "label", "solid"}
var _wall: Node3D
var _wall_level := 0
var _berths: Node3D
var _berths_open := -1
var _dock_console := false


func _build() -> void:
	_owner = str(_planet.get("owner", "")) if _planet.get("owner") != null else ""
	place_name = "%s's base, %s" % [_owner if _owner != "" else "Nobody", _planet.get("name", planet_id)]
	_build_world()
	_refresh_buildings()
	Net.state_changed.connect(_on_state)


func _exit_tree() -> void:
	if Net.state_changed.is_connected(_on_state):
		Net.state_changed.disconnect(_on_state)


func _location() -> String:
	return ""


func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.1, 0.11, 0.16)
	sky_mat.sky_horizon_color = Color(0.55, 0.6, 0.7)
	sky_mat.ground_horizon_color = Color(0.55, 0.6, 0.7)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.67, 0.78)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

	# The base sits 0.4 m down so its paving's top is the floor you walk on (y = 0).
	_base = Node3D.new()
	_base.position.y = -0.4
	add_child(_base)
	var terrain := Terrain.new()
	_base.add_child(terrain)
	terrain.generate(planet_id, Layout.FLAT)
	_base.add_child(Layout.ground(func(c): return _mat(c)))
	# Something to stand on, and the wall all round (the gate is barred: your ship is the way out).
	_box(self, Vector3(Layout.WALL * 2.0, 0.4, Layout.WALL * 2.0), Vector3(0, -0.2, 0), Color(0, 0, 0), true).visible = false
	for i in 4:
		var along := i % 2 == 0
		var at := Layout.WALL * (1.0 if i < 2 else -1.0)
		var size := Vector3(Layout.WALL * 2.0, 12.0, 4.0) if along else Vector3(4.0, 12.0, Layout.WALL * 2.0)
		_box(self, size, Vector3(0, 6.0, at) if along else Vector3(at, 6.0, 0), Color(0, 0, 0), true).visible = false

	for slot in Layout.CELLS.size():
		var pos := Layout.slot_pos(slot)
		var root := Node3D.new()
		root.position = pos
		_base.add_child(root)
		var label := _tag(pos + Vector3(0, 50.0, 0), "", Color(1, 1, 1, 0.9))
		_pads.append({"root": root, "key": "", "model": null, "label": label, "solid": null})
	_refresh_layout()

	if shuttle:
		_build_shuttle_stop()
	else:
		# Your ship, on its berth: nose toward the Command Centre, so from the pilot's seat you look up
		# the avenue across the base.
		var land := Layout.berth_pos(berth)
		var yaw := rad_to_deg(atan2(land.x, land.z))
		_landed_ship(self, land, yaw, Net.my_name, true, true, berth + 1)
		_light(self, land + Vector3(0, 8.0, 0), Color(0.9, 0.95, 1.0), 1.0, 16.0)
	if _owner != "":
		_tag(Vector3(0, 70.0, 0), "%s's Command Centre" % _owner, Color(0.85, 0.95, 1.0))


## The shuttle stop on the avenue inside the gate, where the High Port's shuttle sets you down: its
## console has the ship's menu (the Star Port's buy orders, the shuttle back up).
func _build_shuttle_stop() -> void:
	var stop := Vector3(0, 0, Layout.WALL - 14.0)
	var pad := BaseModels.landing_pad(6.0, true)
	pad.position = stop + Vector3(0, 0.0, 0)
	add_child(pad)
	_arrival = Marker3D.new()
	_arrival.position = stop + Vector3(0, 0.1, -3.0)
	_arrival.rotation.y = PI # facing up the avenue, toward the Command Centre
	add_child(_arrival)
	var at := stop + Vector3(5.0, 0, -4.0)
	var facing := Vector3(-1, 0, 0)
	_console(self, at, facing, "SHUTTLE", "To the High Port\nPress F.", 1.6)
	_light(self, at + Vector3(0, 3.0, 0), Color(0.85, 0.92, 1.0), 0.8, 6.0)
	_use(self, at + facing * 0.7 + Vector3(0, 1.0, 0), func(): return "Press %s for the shuttle and the Star Port" % _key(), func(): wants_menu.emit())


## The wall's turrets and the berths, as the Command Centre's and Star Port's levels have them.
func _refresh_layout() -> void:
	var command := 1
	var open := 0
	for b in _planet.get("buildings", []):
		if b.type == "command":
			command = maxi(1, int(b.get("level", 1)))
		if b.type == "spaceport" and int(b.get("level", 1)) >= 1:
			open = mini(Layout.BERTHS_MAX, int(b.get("level", 1)) * int(Net.catalog.get("berthsPerLevel", 2)))
	if command != _wall_level:
		if _wall:
			_wall.queue_free()
		_wall = Layout.wall(command)
		_base.add_child(_wall)
		_wall_level = command
	if open != _berths_open:
		if _berths:
			_berths.queue_free()
		_berths = Layout.berths(open)
		_base.add_child(_berths)
		_berths_open = open


func _tag(pos: Vector3, text: String, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.02
	l.font_size = 48
	l.outline_size = 10
	l.modulate = colour
	add_child(l)
	return l


func _on_state(_s: Dictionary) -> void:
	_planet = Net.planet(planet_id)
	_refresh_layout()
	_refresh_buildings()


## Every building on its pad, as the Builder has it now: under construction, or built at its level.
func _refresh_buildings() -> void:
	var by_slot := {}
	for b in _planet.get("buildings", []):
		by_slot[int(b.slot)] = b
	for i in _pads.size():
		var p: Dictionary = _pads[i]
		var b: Dictionary = by_slot.get(i, {})
		var building := not b.is_empty() and int(b.get("level", 1)) == 0
		var key := "%s:%s:%d" % [b.get("type", ""), building, int(b.get("level", 1)) if b.get("type") == "command" else 0] if not b.is_empty() else ""
		if key == p.key:
			continue
		p.key = key
		if p.model:
			p.model.queue_free()
			p.model = null
		if p.solid:
			p.solid.queue_free()
			p.solid = null
		p.label.text = ""
		if b.is_empty():
			continue
		p.model = Node3D.new()
		p.model.position.y = 1.0
		p.model.rotation.y = Layout.slot_yaw(i)
		p.root.add_child(p.model)
		p.model.add_child(Layout.building(b.type, 0 if building else maxi(1, int(b.get("level", 1)))))
		# You walk the streets; the buildings themselves are solid.
		var size := Layout.plate_size(i) * 0.75
		p.solid = _box(self, Vector3(size, 40.0, size), p.root.position + Vector3(0, 20.0, 0) + _base.position, Color(0, 0, 0), true)
		p.solid.visible = false
		var name: String = Net.catalog.get("buildings", {}).get(b.type, {}).get("name", str(b.type).capitalize())
		p.label.text = "%s\n%s" % [name, "Under construction" if building else "Level %d" % int(b.get("level", 1))]
		if b.type == "dock" and not building:
			_add_dock_console(i)


## The Carrier Dock's market console: at the street corner of the dock's node, toward the
## Command Centre.
func _add_dock_console(slot: int) -> void:
	if _dock_console:
		return
	_dock_console = true
	var centre := Layout.slot_pos(slot)
	var inward := -centre.normalized()
	var pos := centre + inward * (Layout.plate_size(slot) * 0.5 * sqrt(2.0) + 4.0)
	_console(self, pos, inward, "CARRIER DOCK", "%s's dock market\nPress F." % _owner, 1.8)
	_light(self, pos + Vector3(0, 3.0, 0) + inward, Color(0.85, 0.92, 1.0), 0.8, 6.0)
	_use(self, pos + inward * 0.7 + Vector3(0, 1.0, 0), _dock_prompt, func():
		var why := WarInfo.dock_problem(_owner)
		if why == "":
			service.emit("dock_market")
		else:
			_say(why))


func _dock_prompt() -> String:
	var why := WarInfo.dock_problem(_owner)
	return "Press %s to trade at %s's Carrier Dock" % [_key(), _owner] if why == "" else why
