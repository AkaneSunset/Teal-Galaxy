extends "res://place.gd"
## A Builder's base on their planet's surface, where your ship lands when you shuttle down to their
## Spaceport. It's the same base the Builder sees on their phone: the same icy terrain (terrain.gd,
## generated from the planet id), the command centre, and every building on its pad, at the same
## places and levels, live from the server. Your ship lands on a pad beside the Spaceport.
##
## You arrive seated in your ship (see place.gd); the ship's menu has the Spaceport's services.
## Walk down the ramp to look around the base on foot; the base plate's edge keeps you on it.
## Once the Builder's Carrier Dock is finished, a console in front of it opens the dock market
## (trade_panel.gd), for pilots of the Builder's faction.

const BaseModels := preload("res://base_models.gd")
const Terrain := preload("res://terrain.gd")

const PAD_RING := 34.0 # as on the Builder's screen (builder.gd)
const PAD_RADIUS := 9.5
const PLATE := PAD_RING + 16.0
const LANDING_RADIUS := 18.0 # your ship's pad, between the command centre and the ring of pads

var _owner := ""
var _base: Node3D
var _pads := [] # {"root", "key", "model", "label"}
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

	# The base sits 0.4 m down so its plate's top is the floor you walk on (y = 0).
	_base = Node3D.new()
	_base.position.y = -0.4
	add_child(_base)
	var terrain := Terrain.new()
	_base.add_child(terrain)
	terrain.generate(planet_id, PAD_RING + 22.0)
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = PLATE
	plate_mesh.bottom_radius = PLATE + 1.5
	plate_mesh.height = 0.4
	plate_mesh.radial_segments = 6
	plate.mesh = plate_mesh
	plate.position.y = 0.2
	plate.rotation_degrees.y = 30
	plate.material_override = _mat(Color(0.2, 0.25, 0.35))
	_base.add_child(plate)
	# Something to stand on, and a low invisible fence at the plate's edge.
	_cyl(self, PLATE, 0.4, Vector3(0, -0.2, 0), Color(0, 0, 0), true, 0.0, -1.0, 6).visible = false
	for i in 36:
		var a := TAU * i / 36.0
		var f := Node3D.new()
		f.rotation.y = -a
		add_child(f)
		_box(f, Vector3(0.4, 3.0, TAU * (PLATE - 4.0) / 36.0 + 0.4), Vector3(PLATE - 4.0, 1.5, 0), Color(0, 0, 0), true, 0.0, 0.0)

	var hq := BaseModels.command_center()
	hq.rotation_degrees.y = 45
	_base.add_child(hq)
	_cyl(self, 9.0, 18.0, Vector3(0, 9.0, 0), Color(0, 0, 0), true, 0.0, -1.0, 8).visible = false
	if _owner != "":
		_tag(Vector3(0, 21.0, 0), "%s's Command Centre" % _owner, Color(0.85, 0.95, 1.0))

	for i in 6:
		var ang := deg_to_rad(-90.0 + 60.0 * i)
		var pos := Vector3(cos(ang), 0, sin(ang)) * PAD_RING
		var path := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 0.2, PAD_RING - 16.0)
		path.mesh = box
		path.material_override = _mat(Color(0.15, 0.19, 0.28))
		_base.add_child(path)
		path.position = pos * 0.5 + Vector3(0, 0.45, 0)
		path.look_at(Vector3(0, 0.45, 0) + _base.global_position, Vector3.UP)
		var root := Node3D.new()
		root.position = pos
		_base.add_child(root)
		root.add_child(BaseModels.pad())
		_cyl(self, PAD_RADIUS, 1.0, pos + Vector3(0, 0.5, 0), Color(0, 0, 0), true, 0.0, -1.0, 8).visible = false
		var label := _tag(pos + Vector3(0, 17.0, 0), "", Color(1, 1, 1, 0.9))
		_pads.append({"root": root, "key": "", "model": null, "label": label, "solid": null})
	for a in 4:
		var beacon := Models.nav_beacon()
		var ang := deg_to_rad(a * 90.0)
		beacon.position = Vector3(cos(ang), 0, sin(ang)) * (PAD_RING + 18.0)
		beacon.scale = Vector3.ONE * 0.7
		_base.add_child(beacon)

	# Your ship's landing pad, beside the Spaceport (or the first pad if there isn't one yet).
	var port_slot := 0
	for b in _planet.get("buildings", []):
		if b.type == "spaceport":
			port_slot = int(b.slot)
	var land_ang := deg_to_rad(-90.0 + 60.0 * port_slot + 30.0)
	var land := Vector3(cos(land_ang), 0, sin(land_ang)) * LANDING_RADIUS
	_cyl(self, 4.0, 0.35, land + Vector3(0, 0.17, 0), TRIM)
	_cyl(self, 3.4, 0.06, land + Vector3(0, 0.37, 0), Color(0.18, 0.22, 0.26), false)
	_ring_line(self, 3.7, land + Vector3(0, 0.37, 0), CYAN, 0.15, 3.0)
	_ring_line(self, 2.2, land + Vector3(0, 0.41, 0), HAZARD, 0.06, 2.0)
	# Nose toward the command centre, so from the pilot's seat you look across the base.
	var to_hq := -land
	var yaw := rad_to_deg(atan2(-to_hq.x, -to_hq.z))
	_landed_ship(self, land, yaw, Net.my_name, true, true, 1)
	_light(self, land + Vector3(0, 6.0, 0), Color(0.9, 0.95, 1.0), 1.0, 14.0)


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
		var key := "%s:%s:%d" % [b.get("type", ""), building, int(b.get("level", 1))] if not b.is_empty() else ""
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
		p.model.rotation_degrees.y = 45.0 + 60.0 * i
		p.root.add_child(p.model)
		var m := BaseModels.construction(14.0) if building else BaseModels.building(b.type)
		# The Spaceport model parks a little ship on its pad; yours is the real one now.
		for child in m.get_children():
			if child.name == "StarterShip":
				child.queue_free()
		p.model.add_child(m)
		p.solid = _cyl(self, 7.0, 14.0, p.root.position + Vector3(0, 7.0, 0) + _base.position, Color(0, 0, 0), true, 0.0, -1.0, 8)
		p.solid.visible = false
		var name: String = Net.catalog.get("buildings", {}).get(b.type, {}).get("name", str(b.type).capitalize())
		p.label.text = "%s\n%s" % [name, "Under construction" if building else "Level %d" % int(b.get("level", 1))]
		if b.type == "dock" and not building:
			_add_dock_console(i)


## The Carrier Dock's market console: on the walk in from the dock's pad, beside the path, on the
## side away from your ship.
func _add_dock_console(slot: int) -> void:
	if _dock_console:
		return
	_dock_console = true
	var ang := deg_to_rad(-90.0 + 60.0 * slot)
	var out := Vector3(cos(ang), 0, sin(ang))
	var side := out.cross(Vector3.UP)
	var port_slot := 0
	for b in _planet.get("buildings", []):
		if b.type == "spaceport":
			port_slot = int(b.slot)
	var land_ang := deg_to_rad(-90.0 + 60.0 * port_slot + 30.0)
	if Vector3(cos(land_ang), 0, sin(land_ang)).dot(side) > 0.0:
		side = -side
	var pos := out * (PAD_RING - PAD_RADIUS - 2.5) + side * 3.2
	_console(self, pos, -out, "CARRIER DOCK", "%s's dock market\nPress F." % _owner, 1.8)
	_light(self, pos + Vector3(0, 3.0, 0) - out, Color(0.85, 0.92, 1.0), 0.8, 6.0)
	_use(self, pos - out * 0.7 + Vector3(0, 1.0, 0), _dock_prompt, func():
		var why := WarInfo.dock_problem(_owner)
		if why == "":
			service.emit("dock_market")
		else:
			_say(why))


func _dock_prompt() -> String:
	var why := WarInfo.dock_problem(_owner)
	return "Press %s to trade at %s's Carrier Dock" % [_key(), _owner] if why == "" else why
