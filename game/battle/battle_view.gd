class_name BattleView
extends Node3D
## A sector battle's RTS view, full screen, opened on battle_joined (from the Sector Battles screen,
## battle_menu.gd). Supreme Commander: Forged Alliance is the model: one seamless zoom from a unit's
## treads up to the whole map, where units turn into strategic icons; box selection, groups and
## shift-queued orders; engineers building on mass points; mass as the one resource; drop pods
## from the carrier in orbit. Take control (P) of one of your units and drive it yourself.
##
## The server (server/battle.js) simulates the battle and sends a battle_state every 200 ms; this
## view draws it, interpolating between snapshots, and sends the pilot's orders. It has its own
## world (terrain, sky, sun), camera and input: while it's up (BattleView.active) the explorer and
## the place it was opened from hide and ignore the keys. Leave battle, or the end of the battle,
## frees it and they come back (the carrier's Command Deck, at the holo table).
##
## Controls (command): left click or drag to select (Shift adds, double click: all of that type on
## screen), right click to move or attack, A then left click to attack-move, S to stop, Shift to
## queue, Ctrl+1-9 to set a group and 1-9 to recall it (twice: look at it), Space to look at your
## units (H: your landing zone), WASD / arrows / the screen's edges to pan (A and S pan while
## held), the wheel to zoom (toward the mouse), Q/E or middle drag to turn. Right click on a free
## mass point with engineers selected builds an extractor there. P takes control of the selected unit: WASD drives
## it, the mouse aims, left mouse fires, P or Esc gives it back.

const Terrain := preload("res://battle/battle_terrain.gd")
const Units := preload("res://battle/battle_units.gd")
const Fx := preload("res://battle/battle_fx.gd")
const Models := preload("res://battle/battle_models.gd")
const Overlay := preload("res://battle/battle_overlay.gd")
const Hud := preload("res://battle/battle_hud.gd")
const WarInfo := preload("res://war_info.gd")

const SIZE := 1600.0
const ZOOM_MIN := 25.0
const ZOOM_MAX := 2600.0
const ICONS_FROM := 500.0 # camera height past which units are strategic icons
const UNIT_CAP := 120
const MILITIA := Color(0.86, 0.6, 0.28)
const DRIVE_HZ := 20.0
const END_S := 6.0 # the banner stays this long before the view closes
const TAP_S := 0.22 # A or S released sooner than this is an order, not a pan
const SILENT_S := 15.0 # no snapshot for this long (the server went away, say): the battle is lost to us

## True while a battle view is open (place.gd and explorer.gd look for it).
static var active := false

signal finished

## battle_joined, as the server sent it.
var info: Dictionary = {}
var battle_id := ""
var my_side := "a"
var catalog: Dictionary = {}
var mass_points: Array = []
var units: Dictionary = {} # id -> Units.Unit
var selected: Dictionary = {} # id -> true
var pilots: Array = []
var mass := 0.0
var income := 0.0
var ends_at := 0.0
var ended := false
var sim_rate := 1.0 # simulated seconds a real one (BATTLE_SPEED)
var clock := 0.0 # real seconds since the view opened
var armed := "" # "amove", "build:turret", ...: what the next left click does
var drive_id := -1 # the unit the pilot drives, or -1
## For tests: {"move": Vector2 (world x, z), "fire": bool, "aim": Vector2} instead of the keys and mouse.
var drive_override = null
## How long this view's own work takes a frame (ms, smoothed): the units, effects and camera.
var work_ms := 0.0

var terrain: Node3D
var camera: Camera3D
var box_from = null # where a box selection started (screen), or null
var mouse := Vector2.ZERO

var _units_view: Node3D
var _fx: Node3D
var _hud: Control
var _overlay: Control
var _sun: DirectionalLight3D
var _env: Environment
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _reticle: MeshInstance3D
var _mass_marks := {} # mass point id -> Node3D (its light column)
var _minimap_tex: Texture2D

var _focus := Vector2(800, 200) # the ground point the camera looks at
var _focus_to := Vector2(800, 200)
var _dist := 260.0 # camera height over the focus
var _dist_to := 260.0
var _yaw := 0.0
var _yaw_to := 0.0
var _rotating := false
var _snap_at := -1.0
var _snap_dt := 0.2
var _sim_t := -1.0
var _groups := {} # 1..9 -> [ids]
var _group_at := {} # 1..9 -> clock when last recalled (twice quickly: look at it)
var _last_click := -10.0
var _keys_down := {} # KEY_A / KEY_S -> clock pressed
var _drive_yaw := 0.0
var _drive_pitch := 0.3
var _drive_since := 0.0
var _drive_send := 0.0
var _ended_at := 0.0
var _lost := {} # type -> count, since the feed last said
var _killed := 0
var _tally_at := 0.0


## Opens the RTS view for a battle the server just put the pilot in (`joined`: battle_joined).
## The view adds itself to the scene's root (it has its own world) and frees itself when done.
static func open(host: Node, joined: Dictionary) -> BattleView:
	var v := BattleView.new()
	v.info = joined
	active = true
	host.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	battle_id = str(info.get("battle", ""))
	my_side = str(info.get("side", "a"))
	catalog = info.get("units", {})
	mass_points = info.get("massPoints", [])
	mass = float(info.get("mass", 0))
	ends_at = float(info.get("endsAt", 0))
	_yaw = 0.0 if my_side == "a" else PI
	_yaw_to = _yaw
	var lz: Dictionary = info.get("lz", {"x": 800, "z": 170})
	_focus = Vector2(float(lz.x), float(lz.z)) + _forward2() * 60.0
	_focus_to = _focus

	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(int(info.get("seed", 1)), str(info.get("planet", "")), lz, info.get("enemyLz", {"x": 800, "z": 1430}), mass_points)
	_build_world()
	_build_markers()
	_units_view = Units.new()
	_units_view.terrain = terrain
	_units_view.side_colours = {"a": side_colour("a").srgb_to_linear(), "d": side_colour("d").srgb_to_linear()}
	add_child(_units_view)
	_fx = Fx.new()
	_fx.terrain = terrain
	add_child(_fx)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.5
	camera.far = 30000.0
	add_child(camera)
	camera.make_current()
	_build_ghost()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_overlay = Overlay.new()
	_overlay.view = self
	layer.add_child(_overlay)
	_hud = Hud.new()
	_hud.view = self
	layer.add_child(_hud)

	Net.message.connect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_place_camera(1.0)
	_hud.feed("%s: %s, held by %s" % [str(info.get("planetName", "")), str(info.get("sectorName", "")), side_name("d")], Color(0.35, 0.95, 0.88))
	if my_side == "a":
		_hud.feed("Destroy the Command Node to take the sector", Color(1.0, 0.85, 0.5))
	else:
		_hud.feed("Hold the Command Node until the time runs out", Color(1.0, 0.85, 0.5))


func _exit_tree() -> void:
	active = false
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Leave battle: your units stay on the field (idle), you go back to the carrier.
func leave() -> void:
	if not ended:
		Net.send({"type": "battle_leave", "battle": battle_id})
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	active = false
	if drive_id >= 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit()
	queue_free()


# --- Sides ------------------------------------------------------------------------------------

func enemy_side() -> String:
	return "d" if my_side == "a" else "a"


func side_faction(side: String):
	return info.get("attacker") if side == "a" else info.get("defender")


func side_colour(side: String) -> Color:
	var f = side_faction(side)
	if f == null or str(f) == "":
		return MILITIA
	return WarInfo.faction_color(f)


func side_name(side: String) -> String:
	var f = side_faction(side)
	if f == null or str(f) == "":
		return "the militia"
	return WarInfo.faction_name(f)


## The minimap and the camera start with your landing zone at the bottom: turned for the defender.
func flipped() -> bool:
	return my_side == "d"


func my_unit_count() -> int:
	var n := 0
	for u: Units.Unit in units.values():
		if u.mine and u.kind != "structure":
			n += 1
	return n


## Seconds until the view closes after the battle's end (its banner up).
func end_left() -> float:
	return maxf(0.0, END_S - (clock - _ended_at)) if ended else 0.0


func driving() -> bool:
	return drive_id >= 0


func strategic() -> bool:
	return _dist > ICONS_FROM and not driving()


func minimap_texture() -> Texture2D:
	if _minimap_tex == null:
		_minimap_tex = ImageTexture.create_from_image(terrain.minimap_image(192))
	return _minimap_tex


# --- The world --------------------------------------------------------------------------------

func _build_world() -> void:
	var pal: Dictionary = terrain.palette
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = (pal.sky as Color).darkened(0.35)
	sky_mat.sky_horizon_color = pal.horizon
	sky_mat.ground_horizon_color = pal.horizon
	sky_mat.ground_bottom_color = (pal.rock as Color).darkened(0.4)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.glow_hdr_threshold = 1.0
	_env.fog_enabled = true
	_env.fog_light_color = (pal.horizon as Color).darkened(0.15)
	_env.fog_density = 0.0004
	_env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.light_color = pal.sun
	_sun.light_energy = 1.25
	_sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(35 if my_side == "a" else 215), 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 400.0
	add_child(_sun)


## The landing zones as rings on the ground in their side's colour, and the mass points as glowing
## rings with a column of light (gone once an extractor stands there).
func _build_markers() -> void:
	var lz: Dictionary = info.get("lz", {})
	var enemy: Dictionary = info.get("enemyLz", {})
	if not lz.is_empty():
		_ground_ring(Vector2(lz.x, lz.z), float(lz.r), side_colour(my_side), 1.6, true)
	if not enemy.is_empty():
		_ground_ring(Vector2(enemy.x, enemy.z), float(enemy.r), side_colour(enemy_side()), 1.6, true)
	var column := CylinderMesh.new()
	column.top_radius = 1.2
	column.bottom_radius = 2.2
	column.height = 40.0
	column.radial_segments = 10
	var column_mat := StandardMaterial3D.new()
	column_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	column_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	column_mat.albedo_color = Color(0.3, 1.0, 0.35, 0.22)
	column_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for p in mass_points:
		var at := Vector2(float(p.x), float(p.z))
		_ground_ring(at, 7.0, Color(0.35, 1.0, 0.4), 1.2)
		_ground_ring(at, 3.0, Color(0.35, 1.0, 0.4), 0.8)
		var c := MeshInstance3D.new()
		c.mesh = column
		c.material_override = column_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.position = Vector3(at.x, terrain.height(at.x, at.y) + 20.0, at.y)
		add_child(c)
		_mass_marks[int(p.id)] = c


## A ring lying on the ground (dashed: every other few segments left out, for the landing zones).
func _ground_ring(at: Vector2, r: float, colour: Color, width: float, dashed := false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := clampi(int(r * 0.8), 24, 128)
	for k in n:
		if dashed and (k / 3) % 2 == 1:
			continue
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var pts := []
		for a in [a0, a1]:
			for rr in [r - width * 0.5, r + width * 0.5]:
				var x: float = at.x + cos(a) * rr
				var z: float = at.y + sin(a) * rr
				pts.append(Vector3(x, terrain.height(x, z) + 0.6, z))
		for v in [pts[0], pts[1], pts[3], pts[0], pts[3], pts[2]]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.35)
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_reticle = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.4
	ring.outer_radius = 3.0
	ring.rings = 24
	ring.ring_segments = 4
	_reticle.mesh = ring
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.45, 0.3, 0.9)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.no_depth_test = true
	_reticle.material_override = rm
	_reticle.visible = false
	add_child(_reticle)


# --- The server -------------------------------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"battle_state":
			if str(msg.get("battle", "")) == battle_id:
				_snapshot(msg)
		"battle_end":
			if str(msg.get("battle", "")) == battle_id:
				_end(msg)
		"battle_joined":
			if str(msg.get("battle", "")) == battle_id:
				mass = float(msg.get("mass", mass))
		"error":
			if not ended:
				_hud.notice(_sentence(str(msg.get("reason", ""))), Color(1.0, 0.5, 0.42))


static func _sentence(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


## A battle_state: every unit where it is now. Each unit is drawn moving from where it was drawn
## to its new place over the next snapshot's time.
func _snapshot(msg: Dictionary) -> void:
	var now := clock
	var alpha := _alpha()
	if _snap_at >= 0.0:
		var dt := clampf(now - _snap_at, 0.05, 1.0)
		_snap_dt = lerpf(_snap_dt, dt, 0.25)
		var t := float(msg.get("t", 0))
		if _sim_t >= 0.0 and t > _sim_t:
			sim_rate = lerpf(sim_rate, clampf((t - _sim_t) / dt, 0.1, 100.0), 0.3)
		_sim_t = t
	else:
		_sim_t = float(msg.get("t", 0))
	_snap_at = now
	mass = float(msg.get("mass", mass))
	income = float(msg.get("income", income))
	ends_at = float(msg.get("endsAt", ends_at))
	pilots = msg.get("pilots", pilots)
	var names: Dictionary = info.get("names", {})
	var seen := {}
	for row in msg.get("units", []):
		var id := int(row[0])
		seen[id] = true
		var u: Units.Unit = units.get(id)
		var at := Vector2(float(row[4]), float(row[5]))
		if u == null:
			u = Units.Unit.new()
			u.id = id
			u.type = str(row[1])
			u.side = str(row[2])
			u.owner = str(row[3])
			var c: Dictionary = catalog.get(u.type, {})
			u.kind = str(c.get("kind", "land"))
			u.radius = float(c.get("radius", 3))
			u.max_hp = float(c.get("hp", 100))
			u.mine = u.owner != "" and u.owner == Net.my_name
			u.friend = u.side == my_side
			u.name = str(names.get(str(id), "Command Node" if u.type == "node" else ""))
			u.from = at
			u.to = at
			u.heading = float(row[7])
			u.yaw = u.heading
			u.top_yaw = u.heading
			u.pos = Vector3(at.x, terrain.height(at.x, at.y), at.y)
			units[id] = u
		else:
			u.from = u.from.lerp(u.to, alpha)
			u.to = at
		var hp := float(row[6])
		if hp < u.hp - 0.01:
			u.hit_at = now
		u.hp = hp
		u.heading = float(row[7])
		var state := str(row[8])
		if u.state == "drop" and state != "drop":
			u.landed_at = now
			u.from = at # out of the pod where it landed
			if not u.pod_down:
				_fx.dust(Vector3(at.x, terrain.height(at.x, at.y), at.y))
		u.state = state
		u.progress = 1.0
		if u.mine and not u.orders.is_empty():
			_track_orders(u)
	for b in msg.get("build", []):
		var u: Units.Unit = units.get(int(b[0]))
		if u:
			u.progress = float(b[1])
	for id in msg.get("dead", []):
		_died(int(id))
	for id in units.keys():
		if not seen.has(id):
			units.erase(id)
			selected.erase(id)
	_shots(msg.get("shots", []))
	for line in msg.get("feed", []):
		var s := str(line)
		var colour := Color(0.85, 0.9, 0.95)
		if s.contains("incoming"):
			colour = Color(1.0, 0.6, 0.3)
		elif s.contains("destroyed"):
			colour = Color(1.0, 0.75, 0.6)
		elif s.contains(" built "):
			colour = Color(0.45, 0.95, 0.88)
		_hud.feed(s, colour)
	_update_mass_marks()


## What the pilot told a unit, crossed off as it gets there (for the waypoint lines).
func _track_orders(u: Units.Unit) -> void:
	if u.state == "idle":
		u.idle_for += _snap_dt
		if u.idle_for > 0.6:
			u.orders.clear()
		return
	u.idle_for = 0.0
	var o: Dictionary = u.orders[0]
	if o.order != "attack" and o.order != "build" and u.to.distance_to(o.p) < 6.0 + 3.0 * sqrt(float(selected.size())):
		u.orders.pop_front()
	elif o.order == "attack" and not units.has(o.get("target", -1)):
		u.orders.pop_front()


func _died(id: int) -> void:
	var u: Units.Unit = units.get(id)
	if u == null:
		return
	if not u.dropping():
		_fx.explode(u.pos + Vector3(0, 1.5 if u.kind != "air" else 0.0, 0), u.radius * (1.0 if u.kind != "structure" else 1.6))
		_units_view.add_wreck(u)
	if u.mine:
		_lost[u.type] = int(_lost.get(u.type, 0)) + 1
	elif not u.friend:
		_killed += 1
	if id == drive_id:
		_hud.notice("Your %s was destroyed: back to command" % str(catalog.get(u.type, {}).get("name", u.type)), Color(1.0, 0.5, 0.42))
		_stop_driving(false)
	units.erase(id)
	selected.erase(id)


## Shots since the last snapshot: [shooter id, x, z, type]. A tracer from the shooter's muzzle to
## the point (at the height of whatever stands there), its turret turned that way.
func _shots(list: Array) -> void:
	if list.is_empty():
		return
	var grid := {}
	for u: Units.Unit in units.values():
		var k := Vector2i(int(u.to.x / 20.0), int(u.to.y / 20.0))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(u)
	for s in list:
		var u: Units.Unit = units.get(int(s[0]))
		var to := Vector2(float(s[1]), float(s[2]))
		if u == null:
			continue
		u.aim = to
		u.aim_until = clock + 1.6
		u.last_shot = clock
		var y: float = terrain.height(to.x, to.y) + 1.2
		var k := Vector2i(int(to.x / 20.0), int(to.y / 20.0))
		var best := 8.0
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for t: Units.Unit in grid.get(k + Vector2i(dx, dz), []):
					if t.side == u.side:
						continue
					var d := t.to.distance_to(to)
					if d < best:
						best = d
						y = t.pos.y + (0.0 if t.kind == "air" else (3.0 if t.kind == "structure" else 1.6))
		var m: Dictionary = Models.model(u.type)
		var muzzle := u.pos + Vector3(0, 2.0, 0)
		var dir := Vector3(to.x - u.pos.x, 0, to.y - u.pos.z).normalized()
		if m.top:
			muzzle = u.pos + (m.top_at as Vector3) + Vector3(0, 0.6, 0) + dir * float(m.muzzle)
		elif u.kind == "air":
			muzzle = u.pos + Vector3(0, -0.9, 0) + dir * 3.0
		elif u.type == "node":
			muzzle = u.pos + Vector3(0, 34.0, 0)
		elif u.type == "striker":
			muzzle = u.pos + Vector3(0, 3.3, 0) + dir * 2.2
		_fx.shot(muzzle, Vector3(to.x, y, to.y), str(s[3]), side_colour(u.side), sim_rate)


func _update_mass_marks() -> void:
	for p in mass_points:
		var taken := false
		for u: Units.Unit in units.values():
			if u.type == "extractor" and u.to.distance_to(Vector2(p.x, p.z)) < 8.0:
				taken = true
				break
		_mass_marks[int(p.id)].visible = not taken


func _end(msg: Dictionary) -> void:
	if ended:
		return
	ended = true
	_ended_at = clock
	if driving():
		_stop_driving(false)
	armed = ""
	var won := str(msg.get("side", "")) == my_side
	var title := ""
	if my_side == "a":
		title = "Sector taken" if won else "Attack failed"
	else:
		title = "Sector held" if won else "Sector lost"
	var text := str(msg.get("text", ""))
	if text.begins_with(title + ": "): # "Sector taken: Scar 1 falls to ..." under "Sector taken"
		text = _sentence(text.substr(title.length() + 2))
	_hud.banner(title, text, won)
	if won and my_side == "a":
		for u: Units.Unit in units.values(): # the Command Node is gone: the base burns
			if not u.friend and u.kind == "structure":
				_fx.explode(u.pos + Vector3(0, 4, 0), u.radius)


## The snapshots stopped (the connection dropped, or the server restarted and the battle with it):
## say so and go back to the carrier.
func _lost_contact() -> void:
	ended = true
	_ended_at = clock
	if driving():
		_stop_driving(false)
	armed = ""
	_hud.banner("Contact lost", "The battle's feed went silent: back to the carrier", false)


# --- Each frame -------------------------------------------------------------------------------

func _alpha() -> float:
	if _snap_at < 0.0:
		return 1.0
	return clampf((clock - _snap_at) / maxf(_snap_dt, 0.05), 0.0, 1.0)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame(delta)
	work_ms = lerpf(work_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _frame(delta: float) -> void:
	clock += delta
	mouse = get_viewport().get_mouse_position()
	if ended and clock - _ended_at > END_S:
		close()
		return
	if not ended and clock - maxf(_snap_at, 0.0) > SILENT_S:
		_lost_contact()
	_units_view.show_units = not strategic()
	_units_view.update(units, _alpha(), clock, delta, selected if not driving() else {})
	if driving(): # after the units, so the camera follows where the driven one is this frame
		_drive_camera()
	else:
		_command_camera(delta)
	_pods_and_beams()
	_update_ghost()
	if driving():
		_drive_step(delta)
	_tally()
	var shadows := _dist < 700.0 or driving()
	_sun.shadow_enabled = shadows
	_sun.directional_shadow_max_distance = clampf(_dist * 2.5, 150.0, 900.0)
	_env.fog_density = 0.12 / (maxf(_dist, 30.0) * 3.0 + 600.0)


## Drop pods trail fire as they fall; engineers at work reach out to what they build with a beam.
func _pods_and_beams() -> void:
	var pulse := 0.6 + 0.4 * sin(clock * 9.0)
	for u: Units.Unit in units.values():
		if u.dropping():
			var up: float = _units_view.pod_height(u, clock)
			if up > 0.5:
				var at := u.pos + Vector3(0, up, 0)
				_fx.beam(at, at + Vector3(0, 30.0 + up * 0.1, 0), Color(1.0, 0.55, 0.25, 0.8), 1.6)
				_fx.beam(at, at + Vector3(0, 12.0, 0), Color(1.0, 0.9, 0.7, 1.0), 0.9)
			elif not u.pod_down:
				u.pod_down = true
				_fx.dust(u.pos)
		elif u.type == "engineer" and u.state == "build":
			var target := _build_target(u)
			if target:
				var nozzle := u.pos + Basis(Vector3.UP, u.yaw) * Vector3(0.7, 3.6, 2.0)
				var to := target.pos + Vector3(0, 2.5 if target.kind == "structure" else 1.5, 0)
				_fx.beam(nozzle, to, Color(0.4, 1.0, 0.7, 0.6 * pulse), 0.35)


func _build_target(u: Units.Unit) -> Units.Unit:
	var best: Units.Unit = null
	var best_d := 40.0
	for t: Units.Unit in units.values():
		if t == u or t.side != u.side:
			continue
		if not (t.progress < 1.0 or t.hp < t.max_hp):
			continue
		var d := t.to.distance_to(u.to) - t.radius
		if d < best_d:
			best_d = d
			best = t
	return best


## Every few seconds the feed says what was lost and what was destroyed.
func _tally() -> void:
	if clock - _tally_at < 2.5:
		return
	_tally_at = clock
	if not _lost.is_empty():
		var parts := []
		for t in _lost:
			var n: int = _lost[t]
			parts.append("%d %s%s" % [n, str(catalog.get(t, {}).get("name", t)), "" if n == 1 else "s"])
		_hud.feed("Lost " + ", ".join(parts), Color(1.0, 0.5, 0.42))
		_lost.clear()
	if _killed > 0:
		_hud.feed("Destroyed %d enem%s" % [_killed, "y" if _killed == 1 else "ies"], Color(0.6, 1.0, 0.6))
		_killed = 0


# --- The command camera -----------------------------------------------------------------------

func _forward2() -> Vector2:
	return Vector2(sin(_yaw), cos(_yaw))


func _right2() -> Vector2:
	return Vector2(-cos(_yaw), sin(_yaw))


func _pitch() -> float:
	return lerpf(deg_to_rad(46.0), deg_to_rad(84.0), smoothstep(40.0, 1400.0, _dist))


func _command_camera(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or _held(KEY_S):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT) or _held(KEY_A):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		_yaw_to += 1.4 * delta
	if Input.is_physical_key_pressed(KEY_E):
		_yaw_to -= 1.4 * delta
	if DisplayServer.get_name() != "headless" and get_window().has_focus() and box_from == null:
		var r := get_viewport().get_visible_rect().size
		var edge := 4.0
		if mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= r.x and mouse.y <= r.y:
			if mouse.x < edge:
				pan.x -= 1.0
			elif mouse.x > r.x - edge:
				pan.x += 1.0
			if mouse.y < edge:
				pan.y += 1.0
			elif mouse.y > r.y - edge:
				pan.y -= 1.0
	if pan != Vector2.ZERO:
		var speed := (_dist * 1.3 + 60.0) * delta
		_focus_to += (_forward2() * pan.y + _right2() * pan.x).normalized() * speed
	_focus_to = _focus_to.clamp(Vector2(-150, -150), Vector2(SIZE + 150, SIZE + 150))
	var k := 1.0 - exp(-10.0 * delta)
	_dist = lerpf(_dist, _dist_to, k)
	_focus = _focus.lerp(_focus_to, k)
	_yaw = lerp_angle(_yaw, _yaw_to, k)
	_place_camera(k)


## A key that pans while held (A and S): pans once held past a tap, or straight away with nothing
## selected (when it can't be an order).
func _held(key: int) -> bool:
	if not Input.is_physical_key_pressed(key):
		return false
	if selected.is_empty():
		return true
	return clock - float(_keys_down.get(key, clock)) > TAP_S


func _place_camera(_k: float) -> void:
	var p := _pitch()
	var fwd := Vector3(sin(_yaw) * cos(p), -sin(p), cos(_yaw) * cos(p))
	var ground: float = terrain.height(_focus.x, _focus.y)
	var at := Vector3(_focus.x, ground, _focus.y)
	camera.global_position = at - fwd * (_dist / sin(p))
	camera.look_at(at, Vector3.UP)


## Moves the camera to look at a point of the map (the minimap, Space, a group recalled twice).
func look_at_ground(p: Vector2) -> void:
	_focus_to = p.clamp(Vector2.ZERO, Vector2(SIZE, SIZE))


## The ground the camera sees: the corners of the screen on the map (for the minimap).
func view_quad() -> Array:
	if camera == null:
		return []
	var r := get_viewport().get_visible_rect().size
	var out := []
	var plane_y: float = terrain.height(_focus.x, _focus.y)
	for c in [Vector2(0, 0), Vector2(r.x, 0), Vector2(r.x, r.y), Vector2(0, r.y)]:
		var o := camera.project_ray_origin(c)
		var d := camera.project_ray_normal(c)
		if d.y > -0.05:
			d.y = -0.05
			d = d.normalized()
		var t := (plane_y - o.y) / d.y
		var p := o + d * minf(t, 6000.0)
		out.append(Vector2(p.x, p.z).clamp(Vector2(-300, -300), Vector2(SIZE + 300, SIZE + 300)))
	return out


func _ground_at(screen: Vector2) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	return terrain.pick(o, d, Vector3(-1, 0, -1))


# --- Selecting ---------------------------------------------------------------------------------

## The unit under a point of the screen, or null.
func unit_at(screen: Vector2) -> Units.Unit:
	var best: Units.Unit = null
	var best_d := 1e9
	var icons := strategic()
	for u: Units.Unit in units.values():
		var at := u.pos + Vector3(0, 0.0 if icons else (2.0 if u.kind != "structure" else 5.0), 0)
		if camera.is_position_behind(at):
			continue
		var s := camera.unproject_position(at)
		var d := s.distance_to(screen)
		var reach := 12.0
		if not icons:
			reach = maxf(12.0, u.radius * 1.4 * get_viewport().get_visible_rect().size.y / maxf(camera.global_position.distance_to(u.pos), 1.0))
		if d < reach and d < best_d:
			best_d = d
			best = u
	return best


func select(ids: Array, add := false) -> void:
	if not add:
		selected.clear()
	for id in ids:
		if units.has(id):
			selected[id] = true


func _select_box(a: Vector2, b: Vector2, add: bool) -> void:
	var r := Rect2(a, b - a).abs()
	var mobile := []
	var structures := []
	for u: Units.Unit in units.values():
		if not u.mine or camera.is_position_behind(u.pos):
			continue
		if r.has_point(camera.unproject_position(u.pos)):
			if u.kind == "structure":
				structures.append(u.id)
			else:
				mobile.append(u.id)
	select(mobile if not mobile.is_empty() else structures, add)


## Every unit of yours of the same type on screen (a double click).
func _select_type(type: String, add: bool) -> void:
	var r := get_viewport().get_visible_rect()
	var ids := []
	for u: Units.Unit in units.values():
		if u.mine and u.type == type and not camera.is_position_behind(u.pos) and r.has_point(camera.unproject_position(u.pos)):
			ids.append(u.id)
	select(ids, add)


func _my_selected(mobile_only := true) -> Array:
	var out := []
	for id in selected:
		var u: Units.Unit = units.get(id)
		if u and u.mine and (not mobile_only or u.kind != "structure") and id != drive_id:
			out.append(id)
	return out


# --- Orders ------------------------------------------------------------------------------------

## Sends an order for `ids` (your own units): move, amove, attack (`target`), stop or build
## (`structure`). `queue` adds it after what they're doing.
func order_units(ids: Array, kind: String, p := Vector2.ZERO, queue := false, target := -1, structure := "") -> void:
	if ids.is_empty() or ended:
		return
	var msg := {"type": "battle_order", "battle": battle_id, "units": ids, "order": kind, "queue": queue}
	if kind in ["move", "amove", "build"]:
		msg.x = snappedf(p.x, 0.1)
		msg.z = snappedf(p.y, 0.1)
	if kind == "attack":
		msg.target = target
	if kind == "build":
		msg.structure = structure
	Net.send(msg)
	for id in ids:
		var u: Units.Unit = units.get(id)
		if u == null:
			continue
		if not queue or kind == "stop":
			u.orders.clear()
		if kind != "stop" and (kind != "build" or u.type == "engineer"):
			u.orders.append({"order": kind, "p": p if kind != "attack" else units[target].to if units.has(target) else p, "target": target})
		u.idle_for = 0.0
	var colour := Color(0.4, 1.0, 0.45) if kind == "move" else (Color(1.0, 0.8, 0.3) if kind == "build" else Color(1.0, 0.4, 0.3))
	if kind != "stop":
		_fx.flash(Vector3(p.x, terrain.height(p.x, p.y) + 0.5, p.y), 1.2, colour, 0.25)


## A right click on the map (or the minimap): attack what's there, build an extractor on a mass
## point (engineers), or move there.
func order_to(p: Vector2, target: Units.Unit = null) -> void:
	var ids := _my_selected()
	if ids.is_empty():
		return
	var queue := Input.is_key_pressed(KEY_SHIFT)
	if target and not target.friend:
		order_units(ids, "attack", target.to, queue, target.id)
		return
	var engineers := ids.filter(func(id): return units[id].type == "engineer")
	var point := _mass_point_near(p, 10.0)
	if not engineers.is_empty() and not point.is_empty() and _point_free(point):
		order_units(engineers, "build", Vector2(point.x, point.z), queue, -1, "extractor")
		var others := ids.filter(func(id): return units[id].type != "engineer")
		if not others.is_empty():
			order_units(others, "move", p, queue)
		return
	order_units(ids, "move", p, queue)


func order_stop() -> void:
	order_units(_my_selected(), "stop")
	armed = ""


## What the next left click does: "amove" or "build:<structure>".
func arm(what: String) -> void:
	if _my_selected().is_empty():
		_hud.notice("Select some of your units first")
		return
	armed = what


func armed_text() -> String:
	if armed == "amove":
		return "Attack-move: left click where (right click cancels)"
	if armed.begins_with("build:"):
		var s := armed.substr(6)
		return "Build %s: left click to place (Shift: more)" % str(catalog.get(s, {}).get("name", s))
	return ""


func _mass_point_near(p: Vector2, r: float) -> Dictionary:
	var best := {}
	var best_d := r
	for m in mass_points:
		var d := Vector2(m.x, m.z).distance_to(p)
		if d < best_d:
			best_d = d
			best = m
	return best


func _point_free(m: Dictionary) -> bool:
	for u: Units.Unit in units.values():
		if u.type == "extractor" and u.to.distance_to(Vector2(m.x, m.z)) < 8.0 and not (u.friend and u.progress < 1.0):
			return false
	return true


## Whether a structure fits at `p`: an extractor on a free mass point, anything else clear of
## other structures. Returns the spot it would go (an extractor snaps to its point) or null.
func _site(structure: String, p: Vector2):
	if structure == "extractor":
		var m := _mass_point_near(p, 40.0)
		if m.is_empty() or not _point_free(m):
			return null
		return Vector2(m.x, m.z)
	var r := float(catalog.get(structure, {}).get("radius", 8))
	for u: Units.Unit in units.values():
		if u.kind == "structure" and u.to.distance_to(p) < r + u.radius:
			return null
	return p


func _update_ghost() -> void:
	if not armed.begins_with("build:") or driving() or ended:
		_ghost.visible = false
		return
	var s := armed.substr(6)
	var g := _ground_at(mouse)
	if g.x < 0.0:
		_ghost.visible = false
		return
	var site = _site(s, Vector2(g.x, g.z))
	var at: Vector2 = site if site != null else Vector2(g.x, g.z)
	_ghost.mesh = Models.ghost(s)
	_ghost.position = Vector3(at.x, terrain.height(at.x, at.y), at.y)
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.35) if site != null else Color(1.0, 0.3, 0.25, 0.35)
	_ghost.visible = true


func _place_build(screen: Vector2) -> void:
	var s := armed.substr(6)
	var g := _ground_at(screen)
	if g.x < 0.0:
		return
	var site = _site(s, Vector2(g.x, g.z))
	if site == null:
		_hud.notice("Extractors go on a free mass point" if s == "extractor" else "Something is already built there", Color(1.0, 0.5, 0.42))
		return
	var engineers := _my_selected().filter(func(id): return units[id].type == "engineer")
	if engineers.is_empty():
		_hud.notice("Only engineers build")
		armed = ""
		return
	order_units(engineers, "build", site, Input.is_key_pressed(KEY_SHIFT), -1, s)
	if not Input.is_key_pressed(KEY_SHIFT):
		armed = ""


## The call-in panel: `count` units of `type` by drop pod to your landing zone.
func call_in(type: String, count: int) -> void:
	if ended:
		return
	var cost := int(catalog.get(type, {}).get("cost", 0)) * count
	if mass + 0.01 < cost:
		_hud.notice("Not enough mass: %d %s cost %d" % [count, _plural(type, count), cost], Color(1.0, 0.5, 0.42))
		return
	Net.send({"type": "battle_drop", "battle": battle_id, "unit": type, "count": count})
	_hud.feed("%d %s inbound by drop pod" % [count, _plural(type, count)], Color(0.45, 0.95, 0.88))


func _plural(type: String, n: int) -> String:
	var name := str(catalog.get(type, {}).get("name", type))
	return name if n == 1 or name == "AA" else name + "s"


## A selected factory of yours makes `count` of `type`.
func produce(type: String, count: int) -> void:
	for id in _my_selected(false):
		var u: Units.Unit = units[id]
		if u.type == "factory" and u.progress >= 1.0:
			Net.send({"type": "battle_produce", "battle": battle_id, "factory": u.id, "unit": type, "count": count})
			_hud.feed("%s: %d %s queued" % [str(catalog.factory.name), count, _plural(type, count)], Color(0.45, 0.95, 0.88))
			return


# --- Taking control of a unit -------------------------------------------------------------------

## P: drive the one selected unit yourself.
func take_control() -> void:
	if driving():
		_stop_driving(true)
		return
	var ids := _my_selected()
	if ids.size() != 1:
		_hud.notice("Select one of your units to take control of it")
		return
	var u: Units.Unit = units[ids[0]]
	if u.dropping():
		_hud.notice("That unit is still coming down")
		return
	Net.send({"type": "battle_possess", "battle": battle_id, "unit": u.id})
	drive_id = u.id
	_drive_since = clock
	_drive_yaw = u.yaw
	_drive_pitch = 0.2
	armed = ""
	box_from = null
	u.orders.clear()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _stop_driving(send: bool) -> void:
	if send:
		Net.send({"type": "battle_release", "battle": battle_id})
	var u: Units.Unit = units.get(drive_id)
	if u:
		_focus = u.ground()
		_focus_to = _focus
		_yaw_to = _drive_yaw
		_dist_to = maxf(_dist_to, 120.0)
	drive_id = -1
	_reticle.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _drive_camera() -> void:
	var u: Units.Unit = units.get(drive_id)
	if u == null:
		_stop_driving(false)
		return
	var size := u.radius
	var back := 14.0 + size * 2.6
	var up := 6.0 + size * 1.4
	if u.kind == "air":
		up += 3.0
	var yaw_basis := Basis(Vector3.UP, _drive_yaw)
	var target := u.pos + Vector3(0, up, 0) - (yaw_basis * Vector3(0, 0, 1)) * back
	# The unit is already drawn smoothly between snapshots: the camera sits right behind it (a lag
	# here would leave a fast unit sliding off the side of the screen).
	target.y = maxf(target.y, terrain.height(target.x, target.z) + 2.5) # never under a hill behind it
	camera.global_position = target
	# The camera looks along the yaw (+Z is forward for units, and a camera looks down its -Z, so
	# it's turned half round), tilted down by the pitch.
	camera.global_basis = yaw_basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -_drive_pitch)
	_dist = 80.0
	_reticle.visible = true


func _drive_step(delta: float) -> void:
	var u: Units.Unit = units.get(drive_id)
	if u == null:
		return
	if clock - _drive_since > 2.0 and u.state != "driven":
		_hud.notice("Couldn't take control of that unit", Color(1.0, 0.5, 0.42))
		_stop_driving(false)
		return
	var fwd := Vector2(sin(_drive_yaw), cos(_drive_yaw))
	var right := Vector2(-cos(_drive_yaw), sin(_drive_yaw))
	var move := Vector2.ZERO
	var fire := false
	var screen := get_viewport().get_visible_rect().size * 0.5
	var g := _ground_at(screen)
	var aim := Vector2(g.x, g.z) if g.x >= 0.0 else u.ground() + fwd * 40.0
	if drive_override != null:
		move = drive_override.get("move", Vector2.ZERO)
		fire = drive_override.get("fire", false)
		aim = drive_override.get("aim", aim)
	else:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			move += fwd
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			move -= fwd
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			move += right
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			move -= right
		if Input.is_physical_key_pressed(KEY_Q):
			_drive_yaw += 1.6 * delta
		if Input.is_physical_key_pressed(KEY_E):
			_drive_yaw -= 1.6 * delta
		fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	move = move.limit_length(1.0)
	_reticle.position = Vector3(aim.x, terrain.height(aim.x, aim.y) + 0.4, aim.y)
	u.aim = aim
	u.aim_until = clock + 0.3
	_drive_send -= delta
	if _drive_send <= 0.0:
		_drive_send = 1.0 / DRIVE_HZ
		Net.send({"type": "battle_drive", "battle": battle_id, "move": [snappedf(move.x, 0.01), snappedf(move.y, 0.01)],
			"aim": [snappedf(aim.x, 0.1), snappedf(aim.y, 0.1)], "fire": fire})


# --- Input ------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# A box selection ends wherever the mouse is let go, even over the HUD.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and box_from != null:
		var from: Vector2 = box_from
		box_from = null
		if from.distance_to(event.position) > 6.0:
			_select_box(from, event.position, Input.is_key_pressed(KEY_SHIFT))
		else:
			_click(event.position, event.double_click)
	if driving() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_drive_yaw -= event.relative.x * 0.0035
		_drive_pitch = clampf(_drive_pitch + event.relative.y * 0.0025, 0.06, 0.95)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if ended:
		return
	if driving():
		if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_P or event.physical_keycode == KEY_ESCAPE):
			_stop_driving(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion and _rotating:
		_yaw_to -= event.relative.x * 0.005
	elif event is InputEventKey:
		_key(event)


func _mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not e.pressed:
				return
			var old := _dist_to
			_dist_to = clampf(_dist_to * (0.84 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.19), ZOOM_MIN, ZOOM_MAX)
			if _dist_to < old: # zoom in toward the mouse, as Supreme Commander does
				var g := _ground_at(e.position)
				if g.x >= -100.0:
					_focus_to += (Vector2(g.x, g.z) - _focus_to) * (1.0 - _dist_to / old)
		MOUSE_BUTTON_MIDDLE:
			_rotating = e.pressed
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				if armed == "amove":
					var g := _ground_at(e.position)
					if g.x >= -100.0:
						order_units(_my_selected(), "amove", Vector2(g.x, g.z), Input.is_key_pressed(KEY_SHIFT))
					if not Input.is_key_pressed(KEY_SHIFT):
						armed = ""
				elif armed.begins_with("build:"):
					_place_build(e.position)
				else:
					box_from = e.position
		MOUSE_BUTTON_RIGHT:
			if not e.pressed:
				return
			if armed != "":
				armed = ""
				return
			var target := unit_at(e.position)
			var g := _ground_at(e.position)
			if target == null and g.x < -100.0:
				return
			order_to(Vector2(g.x, g.z) if g.x >= -100.0 else target.to, target)


func _click(at: Vector2, double: bool) -> void:
	var add := Input.is_key_pressed(KEY_SHIFT)
	var u := unit_at(at)
	if u == null:
		if not add:
			selected.clear()
		return
	if double or (clock - _last_click < 0.35 and selected.has(u.id) and u.mine):
		_select_type(u.type, add)
	elif add and selected.has(u.id):
		selected.erase(u.id)
	else:
		select([u.id], add)
	_last_click = clock


func _key(e: InputEventKey) -> void:
	var key := e.physical_keycode
	if not e.pressed:
		# A and S tapped (not held to pan) are orders.
		if _keys_down.has(key):
			var held: float = clock - float(_keys_down[key])
			_keys_down.erase(key)
			if held <= TAP_S and not selected.is_empty():
				if key == KEY_A:
					arm("amove")
				elif key == KEY_S:
					order_stop()
		return
	if e.echo:
		return
	if key == KEY_A or key == KEY_S:
		_keys_down[key] = clock
		return
	if key >= KEY_1 and key <= KEY_9:
		var n := key - KEY_0
		if e.ctrl_pressed:
			_groups[n] = _my_selected(false)
			_hud.feed("Group %d: %d units" % [n, _groups[n].size()])
		else:
			select(_groups.get(n, []).filter(func(id): return units.has(id)), e.shift_pressed)
			if clock - float(_group_at.get(n, -10.0)) < 0.45:
				_centre_on(selected.keys())
			_group_at[n] = clock
		return
	match key:
		KEY_SPACE:
			_centre_on(selected.keys() if not selected.is_empty() else units.keys().filter(func(id): return units[id].mine))
		KEY_P:
			take_control()
		KEY_ESCAPE:
			if armed != "":
				armed = ""
			else:
				selected.clear()
		KEY_H:
			_centre_on([], true)


func _centre_on(ids: Array, home := false) -> void:
	if home:
		var lz: Dictionary = info.get("lz", {})
		look_at_ground(Vector2(lz.x, lz.z))
		return
	var sum := Vector2.ZERO
	var n := 0
	for id in ids:
		var u: Units.Unit = units.get(id)
		if u:
			sum += u.ground()
			n += 1
	if n > 0:
		look_at_ground(sum / n)
	else:
		_centre_on([], true)
