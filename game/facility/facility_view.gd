class_name FacilityView
extends Node3D
## Facility Battles, on foot in first person: team against team inside an outpost facility
## (server/facility.js runs it). Opened on facility_joined, wherever the pilot was; it has its own
## world and HUD, and closes itself a few seconds after the match ends.
##
## You move and look on your own screen and tell the server where you stand (facility_move) and
## every shot you fire (facility_fire: the ray from your eye); the server checks your weapon's rate
## and magazine, decides what was hit (walls and shut doors stop shots), runs the AI troopers and
## keeps the score, and sends everyone the state ten times a second (facility_state).
## W A S D walk, Shift run, Space jump, mouse look, left mouse fire, right mouse aim (zoom with a
## Scope), R reload, 1 primary, 2 secondary, 3 power weapon (from supply drops), G frag grenade,
## H stim, F hold to repair a turret (defenders) or hack the power plant (attackers), 5-0 kill
## streaks, L class (Pick 10), Tab scoreboard, Esc pause (with Leave match).

const WarInfo := preload("res://war_info.gd")

const WALK := 5.0
const SPRINT := 7.0
const JUMP := 4.5
const GRAVITY := 14.0
const EYE := 1.6
const MOVE_HZ := 15.0
const END_S := 8.0
const SILENT_S := 10.0
const USE_EVERY := 0.2
const STREAK_KEYS := {KEY_5: "sensor", KEY_6: "drop", KEY_7: "barrage", KEY_8: "gunship", KEY_9: "emp", KEY_0: "nuke"}
const KIND_ORDER := ["primary", "secondary", "attachment", "perk", "equipment"]
const MILITIA := Color(0.86, 0.6, 0.28)

## True from open() until the view closes: the explorer stays out of the way meanwhile.
static var active := false

signal finished

var info := {} # facility_joined
var match_id := ""
## The messages' prefix: facility_move, facility_state... (Supremacy's view, built on this one, sets "supremacy").
var prefix := "facility"
var side := "a"
var ended := false

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0
var _bodies := {} # id -> {"node", "from", "to", "side", "bar"}
var _pickups := {} # id -> Node3D
var _grenades := {} # id -> Node3D
var _doors: Array = [] # [StaticBody3D]
var _turrets: Array = [] # [{"node", "label"}]
var _plant_label: Label3D
var _hill_ring: Node3D
var _points: Array = [] # [{"node", "disc", "label"}]
var _flags := {} # side -> Node3D
var _gunship: Node3D
var _snap_t := 0.0
var _snap_dt := 0.1
var _silent := 0.0
var _move_t := 0.0
var _use_t := 0.0
var _fire_cd := 0.0
var _mag := 0
var _me := {}
var _state := {}
var _ended_at := 0.0
var _clock := 0.0
var _tracers: Array = [] # {"node", "t", "life"}
var _mats := {}
var _last_hp := 999.0
var _spotted := {}
var _class_pick := false # the class menu is open

var _hud: CanvasLayer
var _top: Label
var _objective: Label
var _feed: VBoxContainer
var _hp_bar: ProgressBar
var _shield_bar: ProgressBar
var _ammo: Label
var _streak_label: Label
var _down: Label
var _use_bar: ProgressBar
var _minimap: Control
var _board: PanelContainer
var _board_text: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _pause: PanelContainer
var _classes: PanelContainer
var _class_list: VBoxContainer
var _editor: VBoxContainer
var _editor_slot := 0
var _editor_name: LineEdit
var _editor_points: Label
var _editor_checks := {} # item -> CheckBox
var _hit_flash: ColorRect


## Opens the view for the match the server just put the pilot in (`joined`: facility_joined).
static func open(host: Node, joined: Dictionary) -> FacilityView:
	var v := FacilityView.new()
	v.info = joined
	active = true
	host.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	match_id = str(info.get("match", ""))
	side = str(info.get("side", "a"))
	_build_world()
	_build_player()
	_build_hud()
	Net.message.connect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var them := _side_name(_other(side))
	_say("%s on %s, %s: %s against %s" % [str(info.get("modeName", "Facility Battle")), str(info.get("planetName", "")), str(_map().get("name", "")), _side_name(side), them], Color(1.0, 0.85, 0.5))
	_say("%s. %s" % [str(info.get("ruleName", "")), str(info.get("ruleText", ""))], Color(1.0, 0.75, 0.4))
	_say("You're %s. L: pick your class (Pick 10). Tab: scoreboard." % ("attacking" if side == "a" else "defending"), Color(0.75, 0.85, 0.9))
	_open_classes(true)


func _exit_tree() -> void:
	active = false
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _map() -> Dictionary:
	return info.get("map", {})


## The current map's size in metres (x by z).
func _map_w() -> float:
	return float(_map().get("w", info.get("size", 80)))


func _map_d() -> float:
	return float(_map().get("d", info.get("depth", _map_w())))


## A new map (Supremacy goes from the ground to a ship and back): the world is built again round the player.
func rebuild_world() -> void:
	_world.remove_child(_player)
	_world.queue_free()
	_bodies = {}
	_pickups = {}
	_grenades = {}
	_doors = []
	_turrets = []
	_points = []
	_flags = {}
	_hill_ring = null
	_plant_label = null
	_tracers = []
	_build_world()
	_world.add_child(_player)


func _other(s: String) -> String:
	return "d" if s == "a" else "a"


func _faction(s: String):
	return info.get("factions", {}).get(s)


func _side_name(s: String) -> String:
	var f = _faction(s)
	return "the militia" if f == null or str(f) == "" else WarInfo.faction_name(f)


func _side_colour(s: String) -> Color:
	var f = _faction(s)
	return MILITIA if f == null or str(f) == "" else WarInfo.faction_color(f)


# --- The facility -------------------------------------------------------------------------------

func _mat(colour: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [colour, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, solid := true, glow := 0.0) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(colour, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
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
	parent.add_child(node)
	return node


func _tag(parent: Node3D, text: String, y: float, colour: Color, size := 44) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.005
	l.font_size = size
	l.outline_size = 8
	l.modulate = colour
	l.position.y = y
	l.no_depth_test = false
	parent.add_child(l)
	return l


func _disc(parent: Node3D, radius: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	mesh.material = _mat(colour, 1.5)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.22, 0.27)
	env.fog_density = 0.008
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	_world.add_child(sun)
	var mw := _map_w()
	var md := _map_d()
	var m := _map()
	# Floor, and the outer wall.
	_box(_world, Vector3(mw + 20, 1, md + 20), Vector3(mw / 2, -0.5, md / 2), _floor_colour())
	for k in 4:
		var horizontal := k < 2
		var at := (0.0 if k % 2 == 0 else md) if horizontal else (0.0 if k % 2 == 0 else mw)
		var dims := Vector3(mw + 2, 4.0, 1.0) if horizontal else Vector3(1.0, 4.0, md + 2)
		var pos := Vector3(mw / 2, 2.0, at + (-0.5 if k % 2 == 0 else 0.5)) if horizontal else Vector3(at + (-0.5 if k % 2 == 0 else 0.5), 2.0, md / 2)
		_box(_world, dims, pos, Color(0.3, 0.31, 0.35))
	for w in m.get("walls", []):
		var h := float(w[4])
		var tall := h > 2.0
		_box(_world, Vector3(float(w[2]), h, float(w[3])), Vector3(float(w[0]), h / 2.0, float(w[1])), Color(0.38, 0.39, 0.43) if tall else Color(0.45, 0.43, 0.38))
		_box(_world, Vector3(float(w[2]) + 0.06, 0.06, float(w[3]) + 0.06), Vector3(float(w[0]), h + 0.03, float(w[1])), Color(0.3, 0.85, 0.85) if tall else Color(0.9, 0.7, 0.3), false, 1.2)
	# Doors: solid while shut, sunk into the floor while open. A locked door glows red.
	for d in m.get("doors", []):
		var door := _box(_world, Vector3(float(d[2]), 3.0, float(d[3])), Vector3(float(d[0]), 1.5, float(d[1])), Color(0.75, 0.25, 0.22) if bool(d[4]) else Color(0.25, 0.45, 0.6))
		_doors.append(door)
	# The defenders' turrets and the power plant.
	for t in m.get("turrets", []):
		var root := Node3D.new()
		root.position = Vector3(float(t[0]), 0, float(t[1]))
		_world.add_child(root)
		_box(root, Vector3(0.8, 1.0, 0.8), Vector3(0, 0.5, 0), Color(0.3, 0.32, 0.36))
		_box(root, Vector3(0.25, 0.25, 1.2), Vector3(0, 1.2, -0.3), _side_colour("d"), false, 1.0)
		_turrets.append({"node": root, "label": _tag(root, "TURRET", 2.0, _side_colour("d"), 36)})
	var plant = m.get("plant")
	if plant is Array:
		var root := Node3D.new()
		root.position = Vector3(float(plant[0]), 0, float(plant[1]))
		_world.add_child(root)
		_box(root, Vector3(1.6, 2.2, 1.6), Vector3(0, 1.1, 0), Color(0.3, 0.33, 0.3))
		_box(root, Vector3(1.7, 0.2, 1.7), Vector3(0, 2.3, 0), Color(1.0, 0.85, 0.3), false, 2.5)
		_plant_label = _tag(root, "POWER PLANT", 3.0, Color(1.0, 0.85, 0.3), 40)
	# Spawns: a pad in each side's colour.
	for s in ["a", "d"]:
		for p in m.get("spawns", {}).get(s, []):
			_disc(_world, 0.6, Vector3(float(p[0]), 0.03, float(p[1])), _side_colour(s).darkened(0.4))
	_build_objectives(m)
	# The gunship, when one is up.
	_gunship = Node3D.new()
	_box(_gunship, Vector3(3.0, 0.8, 6.0), Vector3.ZERO, Color(0.25, 0.27, 0.3), false)
	_box(_gunship, Vector3(8.0, 0.15, 1.2), Vector3(0, 0.2, 0.5), Color(0.3, 0.32, 0.35), false)
	_box(_gunship, Vector3(0.4, 0.3, 0.4), Vector3(0, -0.5, -2.0), Color(1.0, 0.4, 0.2), false, 3.0)
	_gunship.visible = false
	_world.add_child(_gunship)


func _floor_colour() -> Color:
	return Color(0.24, 0.25, 0.27)


## The rule's objectives on the map: the hill, the control points, the flags.
func _build_objectives(m: Dictionary) -> void:
	match str(info.get("rule", "")):
		"koth":
			_hill_ring = Node3D.new()
			_world.add_child(_hill_ring)
			_disc(_hill_ring, 6.0, Vector3(0, 0.04, 0), Color(1.0, 0.85, 0.3, 0.35))
			_box(_hill_ring, Vector3(0.3, 10, 0.3), Vector3(0, 5, 0), Color(1.0, 0.85, 0.3), false, 2.5)
			_tag(_hill_ring, "HILL", 10.6, Color(1.0, 0.85, 0.3), 64)
		"domination":
			var names := "ABC"
			var i := 0
			for p in m.get("points", []):
				var root := Node3D.new()
				root.position = Vector3(float(p[0]), 0, float(p[1]))
				_world.add_child(root)
				var disc := _disc(root, 5.0, Vector3(0, 0.04, 0), Color(0.9, 0.9, 0.9, 0.3))
				_box(root, Vector3(0.25, 6, 0.25), Vector3(0, 3, 0), Color(0.9, 0.9, 0.9), false, 2.0)
				_points.append({"node": root, "disc": disc, "label": _tag(root, names[i], 6.8, Color.WHITE, 90)})
				i += 1
		"ctf":
			for s in ["a", "d"]:
				var home: Array = m.get("flags", {}).get(s, [40, 40])
				_disc(_world, 1.6, Vector3(float(home[0]), 0.04, float(home[1])), _side_colour(s).darkened(0.2))
				var flag := Node3D.new()
				flag.position = Vector3(float(home[0]), 0, float(home[1]))
				_world.add_child(flag)
				_box(flag, Vector3(0.08, 2.6, 0.08), Vector3(0, 1.3, 0), Color(0.8, 0.8, 0.8), false)
				_box(flag, Vector3(0.9, 0.6, 0.04), Vector3(0.45, 2.25, 0), _side_colour(s), false, 2.0)
				_tag(flag, "FLAG", 3.0, _side_colour(s), 40)
				_flags[s] = flag


func _build_player() -> void:
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.4
	shape.shape.height = 1.8
	shape.position.y = 0.9
	_player.add_child(shape)
	var start: Array = info.get("start", [40, 4])
	_player.position = Vector3(float(start[0]), 0.1, float(start[1]))
	_player.rotation.y = PI if side == "a" else 0.0
	_world.add_child(_player)
	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = 80.0
	_camera.near = 0.05
	_player.add_child(_camera)
	_camera.make_current()
	var gun := Node3D.new()
	gun.position = Vector3(0.22, -0.2, -0.75)
	_camera.add_child(gun)
	_box(gun, Vector3(0.05, 0.07, 0.42), Vector3.ZERO, Color(0.15, 0.16, 0.18), false)
	_box(gun, Vector3(0.03, 0.012, 0.14), Vector3(0, 0.04, -0.06), _side_colour(side), false, 1.5)


# --- Input and moving -----------------------------------------------------------------------------

func _menu_open() -> bool:
	return _pause.visible or _classes.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		if _classes.visible:
			_close_classes()
		else:
			_set_paused(not _pause.visible)
		get_viewport().set_input_as_handled()
		return
	if ended:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		if _classes.visible:
			_close_classes()
		else:
			_open_classes(false)
		return
	if _menu_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0025 * (_camera.fov / 80.0)
		_player.rotate_y(-event.relative.x * k)
		_pitch = clampf(_pitch - event.relative.y * k, -1.4, 1.4)
		_camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("foot_reload"):
		Net.send({"type": prefix + "_reload", "match": match_id})
	elif event.is_action_pressed("foot_weapon_1"):
		_switch("primary")
	elif event.is_action_pressed("foot_weapon_2"):
		_switch("secondary")
	elif event.is_action_pressed("foot_weapon_next") or event.is_action_pressed("foot_weapon_prev"):
		_switch("secondary" if str(_me.get("weapon", "primary")) == "primary" else "primary")
	elif event.is_action_pressed("foot_heal"):
		Net.send({"type": prefix + "_stim", "match": match_id})
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key == KEY_3:
			_switch("power")
		elif key == KEY_G:
			throw_frag()
		elif STREAK_KEYS.has(key):
			call_streak(str(STREAK_KEYS[key]))


func _set_paused(on: bool) -> void:
	_pause.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _switch(w: String) -> void:
	if w == "power" and _me.get("power") == null:
		_say("No power weapon: they come in supply drops", Color(1.0, 0.6, 0.5))
		return
	if w != "power" and not (_me.get("guns", {}) as Dictionary).has(w):
		_say("Your class has no %s weapon" % w, Color(1.0, 0.6, 0.5))
		return
	Net.send({"type": prefix + "_switch", "match": match_id, "weapon": w})
	_me["weapon"] = w


func _alive() -> bool:
	return bool(_me.get("alive", true))


func _aim_dir() -> Vector3:
	return -_camera.global_basis.z


## Where the crosshair meets the facility (a wall or the floor), for marking a kill streak.
func _crosshair_point() -> Vector3:
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + _aim_dir() * 150.0, 0xFFFFFFFF, [_player.get_rid()])
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else from + _aim_dir() * 30.0


func _physics_process(delta: float) -> void:
	_clock += delta
	if ended:
		if _clock - _ended_at > END_S:
			close()
		return
	var walking := not _menu_open() and _alive()
	var input := Input.get_vector("foot_left", "foot_right", "foot_forward", "foot_back") if walking else Vector2.ZERO
	var speed := (SPRINT if Input.is_action_pressed("foot_sprint") else WALK) * float(_me.get("speed", 1.0))
	var dir := (_player.global_basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
	_player.velocity.x = dir.x * speed
	_player.velocity.z = dir.z * speed
	if _player.is_on_floor():
		if walking and Input.is_action_just_pressed("foot_jump"):
			_player.velocity.y = JUMP
	else:
		_player.velocity.y -= GRAVITY * delta
	_player.move_and_slide()
	_player.position.x = clampf(_player.position.x, 0.5, _map_w() - 0.5)
	_player.position.z = clampf(_player.position.z, 0.5, _map_d() - 0.5)
	# Aiming down sights: a scope zooms further.
	var aiming := walking and Input.is_action_pressed("foot_aim")
	var fov := 80.0 if not aiming else (35.0 if bool(_me.get("scope", false)) and str(_me.get("weapon", "")) == "primary" else 60.0)
	_camera.fov = lerpf(_camera.fov, fov, 1.0 - exp(-14.0 * delta))
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if walking and Input.is_action_pressed("foot_fire") and _fire_cd <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		fire()
	# Holding use: repair or hack.
	_use_t -= delta
	if walking and Input.is_action_pressed("interact") and _use_t <= 0.0:
		_use_t = USE_EVERY
		Net.send({"type": prefix + "_use", "match": match_id})
	_move_t -= delta
	if _move_t <= 0.0:
		_move_t = 1.0 / MOVE_HZ
		Net.send({"type": prefix + "_move", "match": match_id, "x": _player.position.x, "z": _player.position.z, "yaw": _player.rotation.y})


## One pull of the trigger, as the weapon allows (the server has the last word).
func fire() -> void:
	var gun := str(_me.get("gun", ""))
	var def: Dictionary = info.get("weapons", {}).get(gun, {})
	if def.is_empty() or bool(_me.get("reloading", false)):
		return
	if _mag <= 0:
		Net.send({"type": prefix + "_reload", "match": match_id})
		_fire_cd = 0.5
		return
	_mag -= 1
	_fire_cd = float(def.get("gap", 0.1))
	var from := _camera.global_position
	var dir := _aim_dir()
	Net.send({"type": prefix + "_fire", "match": match_id, "y": _player.position.y + EYE, "dx": dir.x, "dy": dir.y, "dz": dir.z})
	var to := from + dir * float(def.get("range", 90))
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [_player.get_rid()])
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	var colour := Color(1.0, 0.6, 0.2) if def.has("splash") else Color(0.6, 0.9, 1.0) if gun == "railgun" else _side_colour(side).lightened(0.4)
	_tracer(from + dir * 0.6 + _camera.global_basis.x * 0.2 - _camera.global_basis.y * 0.15, to, colour)


func throw_frag() -> void:
	if int(_me.get("frags", 0)) <= 0:
		_say("No grenades left", Color(1.0, 0.6, 0.5))
		return
	var d := _aim_dir()
	Net.send({"type": prefix + "_throw", "match": match_id, "dx": d.x, "dy": d.y, "dz": d.z})


func call_streak(kind: String) -> void:
	var earned: Array = _me.get("earned", [])
	var def: Dictionary = info.get("streaks", {}).get(kind, {})
	if not earned.has(kind):
		_say("%s: %d kills without dying" % [def.get("name", kind), int(def.get("kills", 0))], Color(0.8, 0.8, 0.85))
		return
	var msg := {"type": prefix + "_streak", "match": match_id, "streak": kind}
	if bool(def.get("mark", false)):
		var p := _crosshair_point()
		msg.x = p.x
		msg.z = p.z
	Net.send(msg)


func _tracer(a: Vector3, b: Vector3, colour: Color, life := 0.08) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat(colour, 3.0))
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	_tracers.append({"node": mi, "t": _clock, "life": life})


func _boom(at: Vector3, radius: float, colour: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _mat(Color(colour.r, colour.g, colour.b, 0.6), 4.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	_tracers.append({"node": mi, "t": _clock, "life": 0.35})


func _process(delta: float) -> void:
	_snap_t += delta
	_silent += delta
	if not ended and _silent > SILENT_S:
		_end({"won": false, "text": "Contact with the match was lost"})
	var alpha := clampf(_snap_t / maxf(_snap_dt, 0.05), 0.0, 1.0)
	for id in _bodies:
		var b: Dictionary = _bodies[id]
		var g: Vector2 = (b.from as Vector2).lerp(b.to, alpha)
		var n: Node3D = b.node
		n.position = Vector3(g.x, 0, g.y)
		n.rotation.y = lerp_angle(n.rotation.y, float(b.yaw), 1.0 - exp(-10.0 * delta))
	var keep: Array = []
	for t in _tracers:
		if _clock - float(t.t) > float(t.life):
			t.node.queue_free()
		else:
			keep.append(t)
	_tracers = keep
	if _gunship.visible:
		var a := _clock * 0.35
		_gunship.position = Vector3(_map_w() / 2 + cos(a) * 22.0, 22.0, _map_d() / 2 + sin(a) * 22.0)
		_gunship.rotation.y = -a
	_hit_flash.color.a = maxf(0.0, _hit_flash.color.a - delta * 1.5)
	_board.visible = Input.is_action_pressed("foot_inventory") and not ended
	_update_hud()
	_minimap.queue_redraw()


# --- The server ----------------------------------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		var t when t == prefix + "_state":
			if str(msg.get("match", "")) == match_id:
				_snapshot(msg)
		var t when t == prefix + "_end":
			if str(msg.get("match", "")) == match_id:
				_end(msg)
		"error":
			if not ended:
				_say(str(msg.get("reason", "")), Color(1.0, 0.5, 0.42))


func _snapshot(msg: Dictionary) -> void:
	_snap_dt = lerpf(_snap_dt, clampf(_snap_t, 0.03, 0.5), 0.3)
	_snap_t = 0.0
	_silent = 0.0
	_state = msg
	var me: Dictionary = msg.get("me", {}) if msg.get("me") != null else {}
	var was_alive := _alive()
	var old_gun := str(_me.get("gun", ""))
	_me = me
	# The magazine: the server's, unless we're mid-burst with the same gun (then ours, which is ahead).
	if str(me.get("gun", "")) != old_gun or _fire_cd <= 0.0 or int(me.get("mag", 0)) < _mag:
		_mag = int(me.get("mag", 0))
	var hp := float(me.get("hp", 100)) + float(me.get("shield", 0))
	if hp < _last_hp - 0.5 and _alive():
		_hit_flash.color.a = 0.3
	_last_hp = hp
	var at := Vector2(float(me.get("x", _player.position.x)), float(me.get("z", _player.position.z)))
	if (not was_alive and _alive()) or at.distance_to(Vector2(_player.position.x, _player.position.z)) > 4.0:
		_player.position = Vector3(at.x, 0.2, at.y)
		_player.velocity = Vector3.ZERO
		if not was_alive:
			_player.rotation.y = PI if side == "a" else 0.0
	_spotted = {}
	for id in msg.get("spotted", []):
		_spotted[str(id)] = true
	_update_bodies(msg.get("bodies", []))
	_update_facility(msg)
	_update_pickups(msg.get("pickups", []))
	_update_grenades(msg.get("grenades", []))
	var gunship := false
	for a in msg.get("active", []):
		if str(a[0]) == "gunship":
			gunship = true
	_gunship.visible = gunship
	for s in msg.get("shots", []):
		var who := str(s[0])
		var kind := str(s[5])
		var a := Vector3(float(s[1]), 1.4, float(s[2]))
		var b := Vector3(float(s[3]), 1.2, float(s[4]))
		if kind == "frag":
			_boom(Vector3(a.x, 0.6, a.z), 2.5, Color(1.0, 0.6, 0.2))
		elif kind == "shell":
			_boom(Vector3(a.x, 0.8, a.z), 3.0, Color(1.0, 0.45, 0.2))
			_tracer(Vector3(a.x, 60, a.z), Vector3(a.x, 0.5, a.z), Color(1.0, 0.7, 0.3), 0.15)
		elif who == "gunship":
			_tracer(_gunship.position, b, Color(1.0, 0.5, 0.2), 0.1)
		elif who == Net.my_name:
			continue
		else:
			var b2: Dictionary = _bodies.get(who, {})
			var colour := _side_colour(str(b2.get("side", "d"))).lightened(0.3) if not b2.is_empty() else _side_colour("d")
			if who == "turret":
				a.y = 1.3
			_tracer(a, b, colour)
			if kind == "rockets" or kind == "launcher":
				_boom(b, 2.0, Color(1.0, 0.55, 0.2))
	for f in msg.get("feed", []):
		var text := str(f.get("text", ""))
		if text == "":
			continue
		var colour := Color(0.9, 0.93, 0.95)
		if f.has("kill"):
			var k: Array = f.kill
			colour = Color(0.5, 1.0, 0.6) if str(k[0]) == Net.my_name else Color(1.0, 0.5, 0.42) if str(k[1]) == Net.my_name else Color(0.8, 0.82, 0.86)
		elif f.has("earned") and str(f.get("name", "")) == Net.my_name:
			var key := 0
			for kk in STREAK_KEYS:
				if STREAK_KEYS[kk] == str(f.earned):
					key = kk
			text = "Kill streak: %s ready, press %s" % [info.get("streaks", {}).get(str(f.earned), {}).get("name", f.earned), OS.get_keycode_string(key)]
			colour = Color(1.0, 0.85, 0.3)
		_say(text, colour)
	if not _alive() and was_alive and not ended:
		_open_classes(false)


func _update_bodies(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := str(row[0])
		if id == Net.my_name:
			continue
		seen[id] = true
		var s := str(row[2])
		var to := Vector2(float(row[3]), float(row[4]))
		if not _bodies.has(id):
			var root := Node3D.new()
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.4
			cap.height = 1.8
			cap.material = _mat(_side_colour(s).darkened(0.1 if s == side else 0.3))
			body.mesh = cap
			body.position.y = 0.9
			root.add_child(body)
			_box(root, Vector3(0.5, 0.14, 0.2), Vector3(0, 1.55, -0.3), Color(0.5, 1.0, 0.9) if s == side else Color(1.0, 0.3, 0.2), false, 3.0)
			var bar := _tag(root, "", 2.25, Color(0.5, 1.0, 0.9) if s == side else Color(1.0, 0.45, 0.35), 34)
			_dress_body(root, row)
			_world.add_child(root)
			root.position = Vector3(to.x, 0, to.y)
			_bodies[id] = {"node": root, "from": to, "to": to, "side": s, "bar": bar, "yaw": 0.0}
		var b: Dictionary = _bodies[id]
		b.from = Vector2(b.node.position.x, b.node.position.z)
		b.to = to
		b.yaw = float(row[5])
		b.alive = bool(row[7])
		b.node.visible = bool(row[7])
		var bar: Label3D = b.bar
		bar.text = (str(row[1]) + "\n" if s == side else "") + "|".repeat(clampi(ceili(float(row[6]) / 15.0), 0, 10))
	for id in _bodies.keys():
		if not seen.has(id):
			_bodies[id].node.queue_free()
			_bodies.erase(id)


## A mode's touch on a body as it's first seen (Supremacy: fodder bots and elite troopers).
func _dress_body(_root: Node3D, _row: Array) -> void:
	pass


func _update_facility(msg: Dictionary) -> void:
	var doors: Array = msg.get("doors", [])
	for i in mini(doors.size(), _doors.size()):
		var door: Node3D = _doors[i]
		var open := bool(doors[i])
		door.position.y = -1.45 if open else 1.5
		var shape: CollisionShape3D = door.get_child(0)
		shape.disabled = open
	var turrets: Array = msg.get("turrets", [])
	for i in mini(turrets.size(), _turrets.size()):
		var hp := int(turrets[i][0])
		var label: Label3D = _turrets[i].label
		label.text = "TURRET  %d" % hp if hp > 0 else ("DESTROYED" + ("  repairing %d%%" % int(turrets[i][1]) if int(turrets[i][1]) > 0 else "  (defenders: hold F)"))
	if _plant_label:
		_plant_label.text = "POWER PLANT: HACKED" if bool(msg.get("hacked", false)) else "POWER PLANT" + ("  %d%%" % int(msg.get("plant", 0)) if int(msg.get("plant", 0)) > 0 else ("  (hold F to hack)" if side == "a" else ""))
	if _hill_ring and msg.get("hill") != null:
		var hills: Array = _map().get("hills", [])
		var h: Array = hills[int(msg.hill) % hills.size()]
		_hill_ring.position = Vector3(float(h[0]), 0, float(h[1]))
	var points = msg.get("points")
	if points is Array:
		for i in mini(points.size(), _points.size()):
			var owner = points[i][0]
			var c := Color(0.9, 0.9, 0.9, 0.3) if owner == null else Color(_side_colour(str(owner)), 0.45)
			(_points[i].disc as MeshInstance3D).mesh.material = _mat(c, 1.5)
			(_points[i].label as Label3D).modulate = Color.WHITE if owner == null else _side_colour(str(owner)).lightened(0.3)
	var flags = msg.get("flags")
	if flags is Dictionary:
		for s in _flags:
			var fl: Array = flags.get(s, [])
			if fl.size() >= 2:
				var carried: bool = fl.size() > 2 and fl[2] != null
				(_flags[s] as Node3D).position = Vector3(float(fl[0]), 1.0 if carried else 0.0, float(fl[1]))


func _update_pickups(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		if _pickups.has(id):
			continue
		var weapon := str(row[1])
		var root := Node3D.new()
		root.position = Vector3(float(row[2]), 0, float(row[3]))
		_box(root, Vector3(1.2, 0.5, 0.6), Vector3(0, 0.25, 0), Color(0.3, 0.3, 0.32), false)
		_box(root, Vector3(1.0, 0.12, 0.2), Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.2), false, 3.0)
		_box(root, Vector3(0.1, 8.0, 0.1), Vector3(0, 4.5, 0), Color(1.0, 0.55, 0.2), false, 2.0)
		_tag(root, str(info.get("weapons", {}).get(weapon, {}).get("name", weapon)).to_upper(), 1.3, Color(1.0, 0.7, 0.3), 40)
		_world.add_child(root)
		_pickups[id] = root
	for id in _pickups.keys():
		if not seen.has(id):
			_pickups[id].queue_free()
			_pickups.erase(id)


func _update_grenades(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		if not _grenades.has(id):
			var mesh := SphereMesh.new()
			mesh.radius = 0.12
			mesh.height = 0.24
			mesh.material = _mat(Color(0.2, 0.3, 0.2), 0.0)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			_world.add_child(mi)
			_grenades[id] = mi
		(_grenades[id] as Node3D).position = Vector3(float(row[1]), float(row[2]), float(row[3]))
	for id in _grenades.keys():
		if not seen.has(id):
			_grenades[id].queue_free()
			_grenades.erase(id)


func _end(msg: Dictionary) -> void:
	if ended:
		return
	ended = true
	_ended_at = _clock
	var won := bool(msg.get("won", false))
	var draw := str(msg.get("winner", "")) == "draw"
	_banner_title.text = "Draw" if draw else ("Victory" if won else "Defeat")
	_banner_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9) if draw else (Color(0.45, 1.0, 0.6) if won else Color(1.0, 0.42, 0.35)))
	_banner_text.text = str(msg.get("text", ""))
	_banner.visible = true
	_pause.visible = false
	_classes.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Leave match: your side fights on (an AI trooper takes your place).
func leave() -> void:
	if not ended:
		Net.send({"type": prefix + "_leave", "match": match_id})
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	active = false
	finished.emit()
	queue_free()


# --- Classes (Pick 10) --------------------------------------------------------------------------

## The pilot's own classes, kept on their record by the server: [{name, items}] (null for empty slots).
func custom_classes() -> Array:
	var rec: Dictionary = Net.state.get("pilots", {}).get(Net.my_name, {})
	var out: Array = rec.get("loadouts", [])
	return out


## Picks a class to fight with (now if you haven't spawned with one yet, else on the next respawn).
func pick_class(id: String) -> void:
	Net.send({"type": prefix + "_class", "match": match_id, "cls": id})
	_say("Class: %s%s" % [_class_name(id), "" if not _alive() else " (from your next respawn)"], Color(0.6, 0.9, 1.0))
	_close_classes()


func _class_name(id: String) -> String:
	var d: Dictionary = info.get("classes", {})
	if d.has(id):
		return str(d[id].name)
	var slot := int(id.substr(7)) if id.begins_with("custom:") else -1
	var mine := custom_classes()
	if slot >= 0 and slot < mine.size() and mine[slot] is Dictionary:
		return str(mine[slot].name)
	return id


func _item_kind(item: String) -> String:
	var w: Dictionary = info.get("weapons", {}).get(item, {})
	if not w.is_empty():
		return str(w.get("slot", ""))
	for k in ["attachments", "perks", "equipment"]:
		if (info.get(k, {}) as Dictionary).has(item):
			return {"attachments": "attachment", "perks": "perk", "equipment": "equipment"}[k]
	return ""


func _item_name(item: String) -> String:
	for k in ["weapons", "attachments", "perks", "equipment"]:
		var d: Dictionary = info.get(k, {}).get(item, {})
		if not d.is_empty():
			return str(d.get("name", item))
	return item


func _items_text(items: Array) -> String:
	var names: Array = []
	for i in items:
		names.append(_item_name(str(i)))
	return ", ".join(names)


func _open_classes(first: bool) -> void:
	_classes.visible = true
	_editor.visible = false
	_class_list.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in _class_list.get_children():
		c.free()
	var head := _label(_class_list, 22, Color.WHITE)
	head.text = "Pick a class" + (" to start with" if first else "")
	var d: Dictionary = info.get("classes", {})
	for id in d:
		_class_button(id, str(d[id].name), d[id].items)
	var mine := custom_classes()
	for slot in int(info.get("customMax", 3)):
		var c = mine[slot] if slot < mine.size() else null
		if c is Dictionary:
			_class_button("custom:%d" % slot, str(c.name), c.items)
	var row := HBoxContainer.new()
	_class_list.add_child(row)
	var edit := Button.new()
	edit.text = "Build your own classes (Pick 10)"
	edit.pressed.connect(func(): _open_editor(0))
	row.add_child(edit)
	var shut := Button.new()
	shut.text = "Close (L)"
	shut.pressed.connect(_close_classes)
	row.add_child(shut)


func _class_button(id: String, name: String, items: Array) -> void:
	var b := Button.new()
	b.text = "%s%s:  %s" % [name, "  (current)" if str(_me.get("want", "")) == id else "", _items_text(items)]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(760, 34)
	b.pressed.connect(func(): pick_class(id))
	_class_list.add_child(b)


func _close_classes() -> void:
	_classes.visible = false
	if not _pause.visible and not ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The Pick 10 editor for custom class `slot`: tick items, up to 10 points.
func _open_editor(slot: int) -> void:
	_editor_slot = slot
	_class_list.visible = false
	_editor.visible = true
	for c in _editor.get_children():
		c.free()
	_editor_checks = {}
	var tabs := HBoxContainer.new()
	_editor.add_child(tabs)
	for s in int(info.get("customMax", 3)):
		var t := Button.new()
		t.text = "Custom %d" % (s + 1)
		t.toggle_mode = true
		t.button_pressed = s == slot
		t.pressed.connect(func(): _open_editor(s))
		tabs.add_child(t)
	var mine := custom_classes()
	var current = mine[slot] if slot < mine.size() else null
	var have: Array = current.items if current is Dictionary else []
	_editor_name = LineEdit.new()
	_editor_name.text = str(current.name) if current is Dictionary else "Custom %d" % (slot + 1)
	_editor_name.max_length = 24
	_editor.add_child(_editor_name)
	_editor_points = _label(_editor, 18, Color(1.0, 0.85, 0.4))
	var grid := GridContainer.new()
	grid.columns = 3
	_editor.add_child(grid)
	var all := {}
	for w in info.get("weapons", {}):
		if str(info.weapons[w].get("slot", "")) != "power":
			all[w] = true
	for k in ["attachments", "perks", "equipment"]:
		for i in info.get(k, {}):
			all[i] = true
	for kind in KIND_ORDER:
		for item in all:
			if _item_kind(item) != kind:
				continue
			var cb := CheckBox.new()
			cb.text = "%s · %s" % [kind.capitalize(), _item_name(item)]
			var tip := ""
			for k in ["attachments", "perks", "equipment"]:
				tip = str(info.get(k, {}).get(item, {}).get("text", tip))
			cb.tooltip_text = tip
			cb.button_pressed = have.has(item)
			cb.toggled.connect(func(_on): _editor_count())
			grid.add_child(cb)
			_editor_checks[item] = cb
	var row := HBoxContainer.new()
	_editor.add_child(row)
	var save := Button.new()
	save.text = "Save class"
	save.pressed.connect(save_class)
	row.add_child(save)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): _open_classes(false))
	row.add_child(back)
	_editor_count()


func _editor_items() -> Array:
	var out: Array = []
	for item in _editor_checks:
		if (_editor_checks[item] as CheckBox).button_pressed:
			out.append(item)
	return out


func _editor_count() -> void:
	var n := _editor_items().size()
	var most := int(info.get("points", 10))
	_editor_points.text = "%d of %d points  ·  one primary, one secondary, up to 3 attachments (on the primary) and 3 perks" % [n, most]
	_editor_points.add_theme_color_override("font_color", Color(1.0, 0.5, 0.42) if n > most else Color(1.0, 0.85, 0.4))


## Saves the editor's class to the pilot's record (the server checks it) and picks it.
func save_class() -> void:
	var items := _editor_items()
	Net.send({"type": "loadout_save", "slot": _editor_slot, "name": _editor_name.text, "items": items})
	_say("Saved %s: %s" % [_editor_name.text, _items_text(items)], Color(0.6, 0.9, 1.0))
	Net.send({"type": prefix + "_class", "match": match_id, "cls": "custom:%d" % _editor_slot})
	_close_classes()


# --- HUD ------------------------------------------------------------------------------------------

func _label(parent: Node, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Node, colour: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(260, 12)
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	p.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	p.add_theme_stylebox_override("background", bg)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	root.add_child(p)
	return p


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_hit_flash = ColorRect.new()
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.color = Color(0.9, 0.1, 0.05, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hit_flash)
	_top = _label(root, 20, Color(0.9, 0.95, 1.0))
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top.offset_top = 12
	_top.offset_left = -560
	_top.offset_right = 560
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective = _label(root, 18, Color(1.0, 0.85, 0.5))
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective.offset_top = 44
	_objective.offset_left = -560
	_objective.offset_right = 560
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -16
	_feed.offset_top = 90
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	_minimap = FacilityMinimap.new()
	_minimap.view = self
	_minimap.position = Vector2(16, 16)
	_minimap.size = Vector2(200, 200)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_minimap)
	var vitals := VBoxContainer.new()
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24
	vitals.offset_top = -90
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_label(vitals, 14, Color(0.6, 0.85, 1.0)).text = "Shield"
	_shield_bar = _bar(vitals, Color(0.4, 0.8, 1.0))
	_label(vitals, 14, Color(0.6, 1.0, 0.7)).text = "Health"
	_hp_bar = _bar(vitals, Color(0.45, 1.0, 0.55))
	_hp_bar.max_value = float(info.get("hp", 100))
	_ammo = _label(root, 22, Color(0.95, 0.95, 1.0))
	_ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.offset_left = -460
	_ammo.offset_right = -24
	_ammo.offset_top = -96
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_streak_label = _label(root, 16, Color(1.0, 0.85, 0.4))
	_streak_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_streak_label.offset_left = -500
	_streak_label.offset_right = 500
	_streak_label.offset_top = -40
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_down = _label(root, 28, Color(1.0, 0.5, 0.42))
	_down.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_down.offset_left = -450
	_down.offset_right = 450
	_down.offset_top = 40
	_down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_bar = ProgressBar.new()
	_use_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_use_bar.offset_left = -120
	_use_bar.offset_right = 120
	_use_bar.offset_top = 90
	_use_bar.offset_bottom = 104
	_use_bar.show_percentage = false
	_use_bar.visible = false
	_use_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_use_bar)
	# The scoreboard (Tab).
	_board = _panel(root)
	_board_text = _label(_board, 16, Color(0.92, 0.94, 0.96))
	_board_text.custom_minimum_size = Vector2(620, 0)
	# The end banner.
	_banner = _panel(root)
	var bv := VBoxContainer.new()
	_banner.add_child(bv)
	_banner_title = _label(bv, 40, Color.WHITE)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text = _label(bv, 18, Color(0.9, 0.93, 0.95))
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(bv, 14, Color(0.7, 0.75, 0.8)).text = "Back to your carrier in a few seconds"
	# Paused: Esc. Leave match goes back to the carrier.
	_pause = _panel(root)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	_pause.add_child(pv)
	_label(pv, 26, Color.WHITE).text = "Facility Battle"
	_label(pv, 14, Color(0.8, 0.85, 0.9)).text = "The match goes on while you're here."
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): _set_paused(false))
	pv.add_child(resume)
	var cls := Button.new()
	cls.text = "Change class (L)"
	cls.pressed.connect(func():
		_pause.visible = false
		_open_classes(false))
	pv.add_child(cls)
	var leave_b := Button.new()
	leave_b.text = "Leave match"
	leave_b.pressed.connect(leave)
	pv.add_child(leave_b)
	# Classes: pick one, or build your own (Pick 10).
	_classes = _panel(root)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	_classes.add_child(cv)
	_class_list = VBoxContainer.new()
	cv.add_child(_class_list)
	_editor = VBoxContainer.new()
	_editor.visible = false
	cv.add_child(_editor)


func _say(text: String, colour := Color(0.9, 0.93, 0.95)) -> void:
	var l := _label(_feed, 16, colour)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.set_meta("t", _clock)
	while _feed.get_child_count() > 8:
		_feed.get_child(0).free()


func _time(s: int) -> String:
	return "%d:%02d" % [s / 60, s % 60]


func _update_hud() -> void:
	_top.text = _top_text()
	_objective.text = _objective_text()
	_update_vitals()


## The line across the top: the rule, map, score, clock and reinforcements.
func _top_text() -> String:
	var s := _state
	var score: Dictionary = s.get("score", {"a": 0, "d": 0})
	var reinf: Dictionary = s.get("reinforcements", {"a": 0, "d": 0})
	var target := int(info.get("target", 0))
	return "%s · %s   ·   %s %d  –  %d %s  (to %d)   ·   %s   ·   Reinforcements %d / %d" % [
		str(info.get("ruleName", "")).to_upper(), str(_map().get("name", "")),
		_side_name("a"), int(score.get("a", 0)), int(score.get("d", 0)), _side_name("d"), target,
		_time(int(s.get("left", info.get("seconds", 600)))), int(reinf.get("a", 0)), int(reinf.get("d", 0))]


## Health, shield, ammo, streaks, the down notice, the use bar, the scoreboard and the feed.
func _update_vitals() -> void:
	_hp_bar.max_value = float(_me.get("hpMax", info.get("hp", 100)))
	_hp_bar.value = float(_me.get("hp", 100))
	_shield_bar.max_value = float(_me.get("shieldMax", 50))
	_shield_bar.value = float(_me.get("shield", 0))
	var gun := str(_me.get("gun", ""))
	var def: Dictionary = info.get("weapons", {}).get(gun, {})
	_ammo.text = "%s  %s\nFrags %d (G)   Stims %d (H)%s" % [
		str(def.get("name", "")), "Reloading…" if bool(_me.get("reloading", false)) else "%d / %d" % [_mag, int(_me.get("reserve", 0))],
		int(_me.get("frags", 0)), int(_me.get("stims", 0)), "   Power weapon (3)" if _me.get("power") != null and str(_me.get("weapon", "")) != "power" else ""]
	var earned: Array = _me.get("earned", [])
	var ready: Array = []
	for k in STREAK_KEYS:
		if earned.has(STREAK_KEYS[k]):
			ready.append("[%s] %s" % [OS.get_keycode_string(k), info.get("streaks", {}).get(STREAK_KEYS[k], {}).get("name", "")])
	_streak_label.text = "Streak %d%s" % [int(_me.get("streak", 0)), ("   ·   " + "   ".join(ready)) if not ready.is_empty() else ""]
	if not _alive() and not ended:
		var r := float(_me.get("respawnIn", 0))
		_down.text = "You're down. Back in %d (L: change class)" % ceili(r) if r > 0.0 else "You're out: your side has no reinforcements left"
	else:
		_down.text = ""
	_update_use_bar()
	_update_board()
	for l in _feed.get_children():
		l.modulate.a = clampf(9.0 - (_clock - float(l.get_meta("t"))), 0.0, 1.0)


func _objective_text() -> String:
	var s := _state
	match str(info.get("rule", "")):
		"koth":
			var t := float(s.get("t", 0))
			return "Hold the hill alone   ·   it moves in %d s" % ceili(60.0 - fmod(t, 60.0))
		"domination":
			var parts: Array = []
			var names := "ABC"
			var pts = s.get("points")
			if pts is Array:
				for i in pts.size():
					var o = pts[i][0]
					parts.append("%s: %s" % [names[i], "neutral" if o == null else ("yours" if str(o) == side else "theirs")])
			return "   ".join(parts)
		"ctf":
			var fl = s.get("flags")
			if not (fl is Dictionary):
				return ""
			var theirs: Array = fl.get(_other(side), [])
			var mine: Array = fl.get(side, [])
			var has_it: bool = theirs.size() > 2 and str(theirs[2]) == Net.my_name
			return ("You have their flag: take it to your base" if has_it else "Their flag: " + ("carried" if theirs.size() > 2 and theirs[2] != null else "out")) + "   ·   Your flag: " + ("taken!" if mine.size() > 2 and mine[2] != null else "safe")
	return "Kills win it"


func _update_use_bar() -> void:
	var show := false
	var value := 0.0
	var me := Vector2(_player.position.x, _player.position.z)
	var turrets: Array = _state.get("turrets", [])
	var spots: Array = _map().get("turrets", [])
	for i in mini(turrets.size(), spots.size()):
		if int(turrets[i][1]) > 0 and me.distance_to(Vector2(float(spots[i][0]), float(spots[i][1]))) < 3.0:
			show = true
			value = float(turrets[i][1])
	var plant = _map().get("plant")
	if plant is Array and int(_state.get("plant", 0)) > 0 and not bool(_state.get("hacked", false)) and me.distance_to(Vector2(float(plant[0]), float(plant[1]))) < 3.0:
		show = true
		value = float(_state.get("plant", 0))
	_use_bar.visible = show
	_use_bar.value = value


func _update_board() -> void:
	if not _board.visible:
		return
	var lines: Array = []
	for s in [side, _other(side)]:
		lines.append("%s (%s)" % [_side_name(s), "attackers" if s == "a" else "defenders"])
		for row in _state.get("bodies", []):
			if str(row[2]) == s:
				lines.append("   %-22s %3d kills  %3d deaths%s" % [str(row[1]), int(row[9]), int(row[10]), "  (AI)" if bool(row[8]) else ""])
		lines.append("")
	_board_text.text = "\n".join(lines)


## A mode's own objectives on the minimap (`map` draws, `k`: pixels a metre).
func _minimap_objectives(_map_ctl: Control, _k: float) -> void:
	pass


## What the minimap shows: walls, objectives, your side, and enemies your side has spotted.
func minimap_data() -> Dictionary:
	return {"emp": bool(_state.get("emp", false)), "spotted": _spotted}


class FacilityMinimap:
	extends Control
	var view: FacilityView

	func _draw() -> void:
		if view == null:
			return
		var k := minf(self.size.x / view._map_w(), self.size.y / view._map_d())
		draw_rect(Rect2(Vector2.ZERO, self.size), Color(0, 0, 0, 0.55))
		var data := view.minimap_data()
		if bool(data.emp):
			for i in 60:
				var p := Vector2(randf() * self.size.x, randf() * self.size.y)
				draw_rect(Rect2(p, Vector2(randf() * 30, 2)), Color(0.6, 0.7, 0.8, 0.5))
			draw_string(ThemeDB.fallback_font, Vector2(8, 20), "EMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.5, 0.4))
			return
		var m := view._map()
		for w in m.get("walls", []):
			draw_rect(Rect2(Vector2(float(w[0]) - float(w[2]) / 2, float(w[1]) - float(w[3]) / 2) * k, Vector2(float(w[2]), float(w[3])) * k), Color(0.6, 0.62, 0.66) if float(w[4]) > 2.0 else Color(0.5, 0.45, 0.35))
		var doors: Array = view._state.get("doors", [])
		var i := 0
		for d in m.get("doors", []):
			var open: bool = i < doors.size() and bool(doors[i])
			if not open:
				draw_rect(Rect2(Vector2(float(d[0]) - float(d[2]) / 2, float(d[1]) - float(d[3]) / 2) * k, Vector2(float(d[2]), float(d[3])) * k), Color(0.3, 0.6, 0.9) if not bool(d[4]) else Color(0.9, 0.3, 0.25))
			i += 1
		match str(view.info.get("rule", "")):
			"koth":
				var hills: Array = m.get("hills", [])
				if view._state.get("hill") != null and not hills.is_empty():
					var h: Array = hills[int(view._state.hill) % hills.size()]
					draw_circle(Vector2(float(h[0]), float(h[1])) * k, 6.0 * k, Color(1.0, 0.85, 0.3, 0.4))
			"domination":
				var pts = view._state.get("points")
				var j := 0
				for p in m.get("points", []):
					var o = pts[j][0] if pts is Array and j < pts.size() else null
					draw_circle(Vector2(float(p[0]), float(p[1])) * k, 5.0 * k, Color(0.9, 0.9, 0.9, 0.35) if o == null else Color(view._side_colour(str(o)), 0.5))
					j += 1
			"ctf":
				var fl = view._state.get("flags")
				if fl is Dictionary:
					for s in fl:
						var f: Array = fl[s]
						draw_rect(Rect2(Vector2(float(f[0]), float(f[1])) * k - Vector2(3, 3), Vector2(6, 6)), view._side_colour(str(s)))
		view._minimap_objectives(self, k)
		for row in view._state.get("bodies", []):
			if not bool(row[7]) or str(row[0]) == Net.my_name:
				continue
			var mine := str(row[2]) == view.side
			if not mine and not (data.spotted as Dictionary).has(str(row[0])):
				continue
			draw_circle(Vector2(float(row[3]), float(row[4])) * k, 3.0, Color(0.4, 0.9, 1.0) if mine else Color(1.0, 0.3, 0.25))
		var me := Vector2(view._player.position.x, view._player.position.z) * k
		var fwd := Vector2(-sin(view._player.rotation.y), -cos(view._player.rotation.y))
		draw_line(me, me + fwd * 9.0, Color.WHITE, 2.0)
		draw_circle(me, 3.5, Color.WHITE)
