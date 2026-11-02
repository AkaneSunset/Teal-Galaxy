class_name SpaceView
extends Node3D
## Space Battles, from a starfighter's cockpit (server/space.js runs it). Opened on starfight_joined,
## wherever the pilot was; it has its own battle space and HUD, and closes itself a few seconds after
## the battle ends.
##
## You fly with the game's flight model (flight.gd: throttle, boost, drift, pips) in the class you
## picked for this life, and tell the server where you are (starfight_move) and every laser bolt you fire
## (starfight_fire); the server decides what's hit, flies the missiles, torpedoes and AI, and sends the
## state ten times a second (starfight_state). Destroy the enemy capital ship: its two shield generators
## first, then its engines, bridge and reactor.
## Flight controls as usual; left mouse lasers, right mouse a missile (Fighter, Interceptor: lock a
## fighter ahead first) or a torpedo (Bomber: at a target on the enemy capital ship or a frigate),
## T target ahead, 1/2/3/4 pips, Tab scoreboard, Esc pause (with Leave battle). When you're shot
## down, pick the class for your next launch.

const WarInfo := preload("res://war_info.gd")
const Flight := preload("res://flight.gd")
const Controls := preload("res://controls.gd")
const Models := preload("res://models.gd")

const MOVE_HZ := 15.0
const END_S := 8.0
const SILENT_S := 10.0
const LOCK_S := 1.2
const MILITIA := Color(0.86, 0.6, 0.28)
const KIND_ORDER := {"gen": 0, "sub": 1, "frigate": 2, "turret": 3}

## True from open() until the view closes: the explorer stays out of the way meanwhile.
static var active := false

signal finished

var info := {} # starfight_joined
var match_id := ""
var side := "a"
var ended := false

var flight := Flight.new()
var controls: Node
var _world: Node3D
var _ship: Node3D
var _camera: Camera3D
var _pos := Vector3.ZERO
var _craft := {} # id -> {"node", "from", "to", "fwd", "up", "side", "cls", "label"}
var _parts := {} # id -> {"node", "label", "info"}
var _missiles := {} # id -> Node3D
var _drops := {} # id -> Node3D
var _tracers: Array = [] # {"node", "t", "life"}
var _mats := {}
var _me := {}
var _state := {}
var _snap_t := 0.0
var _snap_dt := 0.1
var _silent := 0.0
var _move_t := 0.0
var _fire_cd := 0.0
var _clock := 0.0
var _ended_at := 0.0
var _last_hp := 999.0
var target := "" # a craft id, or a part id (bombers)
var _lock := 0.0

var _hud: CanvasLayer
var _top: Label
var _capitals: Label
var _feed: VBoxContainer
var _hp_bar: ProgressBar
var _shield_bar: ProgressBar
var _flight_label: Label
var _weapons: Label
var _down: Label
var _bracket: Control
var _board: PanelContainer
var _board_text: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _pause: PanelContainer
var _picker: PanelContainer
var _picker_note: Label
var _hit_flash: ColorRect


## Opens the view for the battle the server just put the pilot in (`joined`: starfight_joined).
static func open(host: Node, joined: Dictionary) -> SpaceView:
	var v := SpaceView.new()
	v.info = joined
	active = true
	host.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	match_id = str(info.get("match", ""))
	side = str(info.get("side", "a"))
	controls = Controls.new()
	add_child(controls)
	_build_world()
	_build_hud()
	_apply_class("fighter")
	var start: Dictionary = info.get("start", {})
	_pos = _v3(start.get("pos", [0, 0, 0]))
	_face(_v3(start.get("fwd", [0, 0, 1])))
	Net.message.connect(_on_message)
	controls.capture_mouse()
	_say("Space Battle over %s: %s against %s" % [str(info.get("planetName", "")), _side_name(side), _side_name(_other(side))], Color(1.0, 0.85, 0.5))
	_say("Destroy %s: its shield generators first, then its engines, bridge and reactor." % _capital_name(_other(side)), Color(1.0, 0.75, 0.4))
	if info.get("hullBonus") != null:
		_say("Shipyard world: %s fly with 10%% more hull" % _side_name(str(info.hullBonus)), Color(0.8, 0.85, 1.0))
	_open_picker(true)


func _exit_tree() -> void:
	active = false
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


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


func _capital_name(s: String) -> String:
	return str(info.get("capitals", {}).get(s, {}).get("name", "the capital ship"))


## The class's handling, on the game's small ship: speeds, turn rates, shields and hull.
func _apply_class(cls: String) -> void:
	var c: Dictionary = info.get("classes", {}).get(cls, {})
	var st: Dictionary = Flight.SMALL_SHIP.duplicate()
	st["class"] = str(c.get("name", "Fighter"))
	st["top_speed"] = float(c.get("speed", 300))
	st["boost_speed"] = float(c.get("boost", 420))
	for k in ["pitch", "yaw", "roll"]:
		st[k] = float(c.get(k, st[k]))
	st["shields"] = float(c.get("shields", 100))
	st["hull"] = float(c.get("hull", 100))
	flight.stats = st


func _face(fwd: Vector3) -> void:
	flight.basis = Basis.looking_at(fwd.normalized(), Vector3.UP)
	flight.velocity = fwd.normalized() * 150.0
	flight.throttle = 0.5


# --- The battle space ----------------------------------------------------------------------------

func _mat(colour: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [colour, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.6
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, glow := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(colour, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, radius: float, pos: Vector3, colour: Color, glow := 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = _mat(colour, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## A label over something, the same size on screen however far away it is.
func _tag(parent: Node3D, text: String, y: float, colour: Color, size := 32) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.font_size = size
	l.outline_size = 8
	l.modulate = colour
	l.position.y = y
	l.no_depth_test = true
	parent.add_child(l)
	return l


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.1
	_world.add_child(sun)
	# Stars, and the planet below.
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	var star := SphereMesh.new()
	star.radius = 18.0
	star.height = 36.0
	star.radial_segments = 4
	star.rings = 2
	star.material = _mat(Color(0.9, 0.92, 1.0), 2.0)
	stars.mesh = star
	stars.instance_count = 600
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in stars.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		stars.set_instance_transform(i, Transform3D(Basis(), d * 40000.0))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = stars
	_world.add_child(smi)
	var planet := _ball(_world, 30000.0, Vector3(0, -38000, 6000), Color(0.35, 0.3, 0.25))
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tag(planet, str(info.get("planetName", "")).to_upper(), 30500.0, Color(0.8, 0.8, 0.85), 40)
	# The capital ships: long hulls broadside on, their parts on top.
	for s in ["a", "d"]:
		var c: Dictionary = info.get("capitals", {}).get(s, {})
		var half := _v3(c.get("half", [260, 50, 60]))
		var root := Node3D.new()
		root.position = _v3(c.get("pos", [0, 0, 0]))
		_world.add_child(root)
		var col := _side_colour(s)
		_box(root, half * 2.0, Vector3.ZERO, col.darkened(0.55))
		_box(root, Vector3(half.x * 1.6, half.y * 0.6, half.z * 2.2), Vector3(0, -half.y * 0.2, 0), col.darkened(0.4))
		_box(root, Vector3(half.x * 2.0, 4, 4), Vector3(0, half.y * 0.5, half.z + 2), col, 1.5)
		_tag(root, _capital_name(s).to_upper(), half.y + 140.0, col.lightened(0.3), 40)
	for p in info.get("parts", []):
		var pos := _v3(p.pos)
		var col := _side_colour(str(p.side))
		var node: Node3D
		match str(p.kind):
			"gen":
				node = _ball(_world, float(p.r), pos, Color(0.4, 0.8, 1.0), 1.0)
			"sub":
				node = _ball(_world, float(p.r), pos, Color(1.0, 0.6, 0.25), 0.8)
			"frigate":
				node = Node3D.new()
				node.position = pos
				_world.add_child(node)
				_box(node, Vector3(180, 40, 50), Vector3.ZERO, col.darkened(0.5))
				_box(node, Vector3(60, 30, 30), Vector3(-30, 30, 0), col.darkened(0.35))
				_box(node, Vector3(180, 3, 3), Vector3(0, 0, 26), col, 1.5)
			_:
				node = _box(_world, Vector3(10, 8, 10), pos, col.darkened(0.2), 0.6)
		var label := _tag(node, "", float(p.r) + 18.0, col.lightened(0.4), 24) if str(p.kind) != "turret" else null
		_parts[str(p.id)] = {"node": node, "label": label, "info": p}
	# Pilots' fleet carriers, in a row behind each capital ship.
	for s in ["a", "d"]:
		for k in info.get("carriers", {}).get(s, []):
			var carrier := Models.fleet_carrier(_side_colour(s))
			carrier.position = _v3(k.pos)
			carrier.rotation.y = 0.0 if s == "d" else PI
			_world.add_child(carrier)
			_tag(carrier, "%s's carrier" % str(k.name), 90.0, _side_colour(s).lightened(0.3), 28)
	# Our own fighter, and the camera behind its canopy.
	_ship = Node3D.new()
	_world.add_child(_ship)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.6, 0.5)
	_camera.fov = 75.0
	_camera.near = 0.3
	_camera.far = 90000.0
	_ship.add_child(_camera)
	_camera.make_current()


## A fighter model by class in its side's colour (about 12 m; bombers bigger).
func _fighter(cls: String, s: String) -> Node3D:
	var n := Node3D.new()
	var col := _side_colour(s)
	match cls:
		"interceptor":
			_box(n, Vector3(1.6, 1.2, 9), Vector3.ZERO, col.darkened(0.2))
			_box(n, Vector3(10, 0.25, 2.5), Vector3(0, 0, 2), col.darkened(0.45))
			_box(n, Vector3(0.8, 0.6, 1.2), Vector3(0, 0.6, -2.5), Color(0.5, 0.8, 1.0), 1.0)
		"bomber":
			_box(n, Vector3(5, 3, 14), Vector3.ZERO, col.darkened(0.35))
			_box(n, Vector3(14, 0.8, 5), Vector3(0, -0.5, 2), col.darkened(0.5))
			_box(n, Vector3(2, 1.2, 2.5), Vector3(0, 1.4, -4.5), Color(0.5, 0.8, 1.0), 1.0)
		_:
			_box(n, Vector3(2.4, 1.6, 10), Vector3.ZERO, col.darkened(0.25))
			_box(n, Vector3(9, 0.4, 3.5), Vector3(0, 0, 1.5), col.darkened(0.45))
			_box(n, Vector3(0.4, 3, 2.5), Vector3(4.5, 0, 1.5), col.darkened(0.3))
			_box(n, Vector3(0.4, 3, 2.5), Vector3(-4.5, 0, 1.5), col.darkened(0.3))
			_box(n, Vector3(1.2, 0.8, 1.6), Vector3(0, 0.9, -2.5), Color(0.5, 0.8, 1.0), 1.0)
	_box(n, Vector3(1.4, 1.0, 0.4), Vector3(0, 0, 5.2 if cls != "bomber" else 7.2), Color(1.0, 0.6, 0.25), 3.0)
	return n


# --- Flying and fighting ------------------------------------------------------------------------------

func _menu_open() -> bool:
	return _pause.visible or _picker.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		if _picker.visible and _alive():
			_close_picker()
		else:
			_set_paused(not _pause.visible)
		get_viewport().set_input_as_handled()
		return
	if ended or _menu_open():
		return
	if event.is_action_pressed("ship_target"):
		cycle_target()
	elif event.is_action_pressed("ship_secondary"):
		fire_secondary()
	elif event.is_action_pressed("pip_sys"):
		flight.add_pip(Flight.SYS)
	elif event.is_action_pressed("pip_eng"):
		flight.add_pip(Flight.ENG)
	elif event.is_action_pressed("pip_wep"):
		flight.add_pip(Flight.WEP)
	elif event.is_action_pressed("pip_reset"):
		flight.reset_pips()
	elif event.is_action_pressed("drift") and not controls.drift_hold:
		flight.drift = not flight.drift
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		controls.capture_mouse()


func _set_paused(on: bool) -> void:
	_pause.visible = on
	_sync_mouse()


func _sync_mouse() -> void:
	controls.enabled = not _menu_open() and not ended
	if controls.enabled:
		controls.capture_mouse()
	else:
		controls.release_mouse()


func _alive() -> bool:
	return bool(_me.get("alive", true))


func _cls() -> String:
	return str(_me.get("cls", "fighter"))


func _physics_process(delta: float) -> void:
	_clock += delta
	if ended:
		if _clock - _ended_at > END_S:
			close()
		return
	if not _alive():
		_ship.visible = false
		return
	if controls.drift_hold and controls.enabled:
		flight.drift = Input.is_action_pressed("drift")
	var input: Dictionary = controls.read() if not _menu_open() else {}
	flight.step(input, {"mass_locked": true}, delta)
	_pos += flight.velocity * delta
	var arena := float(info.get("arena", 6000))
	_pos = Vector3(clampf(_pos.x, -arena, arena), clampf(_pos.y, -arena / 2, arena / 2), clampf(_pos.z, -arena, arena))
	_ship.position = _pos
	_ship.basis = flight.basis
	# Lasers, while the trigger's held, as the class's rate and the weapons capacitor allow.
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if not _menu_open() and Input.is_action_pressed("ship_fire") and _fire_cd <= 0.0:
		fire()
	_update_lock(delta)
	_move_t -= delta
	if _move_t <= 0.0:
		_move_t = 1.0 / MOVE_HZ
		var f := flight.forward()
		var u := flight.basis.y
		var v := flight.velocity
		Net.send({"type": "starfight_move", "match": match_id, "x": _pos.x, "y": _pos.y, "z": _pos.z, "fx": f.x, "fy": f.y, "fz": f.z, "ux": u.x, "uy": u.y, "uz": u.z, "vx": v.x, "vy": v.y, "vz": v.z})


## One laser bolt from the nose.
func fire() -> void:
	var c: Dictionary = info.get("classes", {}).get(_cls(), {})
	if not flight.draw(Flight.WEP, 0.8):
		return
	_fire_cd = float(c.get("gap", 0.12))
	var d := flight.forward()
	Net.send({"type": "starfight_fire", "match": match_id, "dx": d.x, "dy": d.y, "dz": d.z})
	var from := _pos + flight.basis * Vector3(1.4 if int(_clock * 20) % 2 == 0 else -1.4, 0.6, -4.0)
	_tracer(from, from + d * 900.0, _side_colour(side).lightened(0.5), 0.06)


## Targets what's nearest the crosshair ahead: enemy fighters, or (in a bomber) the enemy capital
## ship's weak points that can be hurt now (its shield generators, then its subsystems), then its
## frigates. Pressing it again moves on to the next.
func cycle_target() -> void:
	var fwd := flight.forward()
	var best := ""
	var bs := -INF
	if _cls() == "bomber":
		var gens_up := _gens_up(_other(side))
		for id in _parts:
			var p: Dictionary = _parts[id].info
			if str(p.side) == side or _part_hp(id) <= 0 or str(p.kind) == "turret":
				continue
			if str(p.kind) == "sub" and gens_up:
				continue
			var to := _v3(p.pos) - _pos
			# The capital ship's weak points first (what can be hurt now), then the frigates.
			var weak := 1.5 if str(p.kind) in ["gen", "sub"] else 0.0
			var score := weak + fwd.dot(to.normalized()) - to.length() / 20000.0
			if id != target and score > bs:
				best = id
				bs = score
	else:
		for id in _craft:
			var c: Dictionary = _craft[id]
			if str(c.side) == side or not bool(c.get("alive", true)):
				continue
			var to: Vector3 = (c.node as Node3D).position - _pos
			var score := fwd.dot(to.normalized()) - to.length() / 4000.0
			if id != target and score > bs:
				best = id
				bs = score
	target = best
	_lock = 0.0
	if target != "":
		_say("Target: %s" % _target_name(), Color(1.0, 0.85, 0.4))


func _target_pos() -> Vector3:
	if _craft.has(target):
		return (_craft[target].node as Node3D).position
	if _parts.has(target):
		return _v3(_parts[target].info.pos)
	return Vector3.INF


func _target_name() -> String:
	if _craft.has(target):
		return str(_craft[target].get("name", target))
	if _parts.has(target):
		return "%s (%s)" % [str(_parts[target].info.name), _capital_name(str(_parts[target].info.side))]
	return ""


## Holding a target ahead and in range for LOCK_S locks a missile on (torpedoes need no lock).
func _update_lock(delta: float) -> void:
	var at := _target_pos()
	if at == Vector3.INF:
		target = ""
		_lock = 0.0
		return
	var to := at - _pos
	var spec: Dictionary = info.get("torpedo" if _cls() == "bomber" else "missile", {})
	var ok := to.length() <= float(spec.get("range", spec.get("lockRange", 2000))) and flight.forward().dot(to.normalized()) >= cos(float(spec.get("cone", 0.5)))
	_lock = clampf(_lock + (delta if ok else -delta * 2.0), 0.0, LOCK_S)


func locked() -> bool:
	return target != "" and (_lock >= LOCK_S or (_cls() == "bomber" and _lock > 0.0))


## A missile at the locked fighter, or a torpedo at the targeted part.
func fire_secondary() -> void:
	if target == "":
		_say("No target: T targets what's ahead", Color(1.0, 0.6, 0.5))
		return
	if not locked():
		_say("Not locked on: keep the target ahead", Color(1.0, 0.6, 0.5))
		return
	if _cls() == "bomber":
		Net.send({"type": "starfight_torpedo", "match": match_id, "target": target})
	else:
		Net.send({"type": "starfight_missile", "match": match_id, "target": target})


func _tracer(a: Vector3, b: Vector3, colour: Color, life := 0.08) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat(colour, 4.0))
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	_tracers.append({"node": mi, "t": _clock, "life": life})


func _boom(at: Vector3, radius: float, colour: Color) -> void:
	var mi := _ball(_world, radius, at, Color(colour.r, colour.g, colour.b, 0.6), 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracers.append({"node": mi, "t": _clock, "life": 0.5})


func _process(delta: float) -> void:
	_snap_t += delta
	_silent += delta
	if not ended and _silent > SILENT_S:
		_end({"won": false, "text": "Contact with the battle was lost"})
	var alpha := clampf(_snap_t / maxf(_snap_dt, 0.05), 0.0, 1.0)
	for id in _craft:
		var c: Dictionary = _craft[id]
		var n: Node3D = c.node
		n.position = (c.from as Vector3).lerp(c.to, alpha)
		var fwd: Vector3 = c.fwd
		if fwd.length() > 0.1:
			n.basis = Basis.looking_at(fwd, c.up if (c.up as Vector3).length() > 0.1 else Vector3.UP)
	var keep: Array = []
	for t in _tracers:
		if _clock - float(t.t) > float(t.life):
			t.node.queue_free()
		else:
			keep.append(t)
	_tracers = keep
	_hit_flash.color.a = maxf(0.0, _hit_flash.color.a - delta * 1.5)
	_board.visible = Input.is_action_pressed("foot_inventory") and not ended
	_update_hud()


# --- The server ------------------------------------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"starfight_state":
			if str(msg.get("match", "")) == match_id:
				_snapshot(msg)
		"starfight_end":
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
	var was_cls := _cls()
	_me = me
	var hp := float(me.get("hp", 100)) + float(me.get("shield", 0))
	if hp < _last_hp - 0.5 and _alive():
		_hit_flash.color.a = 0.25
	_last_hp = hp
	# A (re)launch, or the server's place for us drifted far from ours: take the server's.
	var at := Vector3(float(me.get("x", _pos.x)), float(me.get("y", _pos.y)), float(me.get("z", _pos.z)))
	var relaunched := (not was_alive and _alive()) or _cls() != was_cls
	if relaunched or at.distance_to(_pos) > 400.0:
		_pos = at
		if relaunched:
			_apply_class(_cls())
			flight.repair()
			_face(Vector3(0, 0, 1) if side == "a" else Vector3(0, 0, -1))
			_ship.visible = true
	if was_alive and not _alive():
		_open_picker(false)
	_update_craft(msg.get("craft", []))
	_update_parts(msg.get("parts", []))
	_update_missiles(msg.get("missiles", []))
	_update_drops(msg.get("drops", []))
	for s in msg.get("shots", []):
		var a := Vector3(float(s[0]), float(s[1]), float(s[2]))
		var b := Vector3(float(s[3]), float(s[4]), float(s[5]))
		var kind := str(s[6])
		if kind == "missile":
			_boom(a, 12.0, Color(1.0, 0.7, 0.3))
		elif kind == "torpedo":
			_boom(a, 45.0, Color(1.0, 0.5, 0.2))
		elif kind.begins_with("turret"):
			_tracer(a, b, _side_colour(kind.substr(7)).lightened(0.2), 0.08)
		elif kind != side or a.distance_to(_pos) > 30.0:
			_tracer(a, b, _side_colour(kind).lightened(0.5), 0.06)
	for f in msg.get("feed", []):
		var text := str(f.get("text", ""))
		if text == "":
			continue
		var colour := Color(0.9, 0.93, 0.95)
		if f.has("kill"):
			var k: Array = f.kill
			colour = Color(0.5, 1.0, 0.6) if str(k[0]) == Net.my_name else Color(1.0, 0.5, 0.42) if str(k[1]) == Net.my_name else Color(0.8, 0.82, 0.86)
		_say(text, colour)


func _update_craft(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := str(row[0])
		if id == Net.my_name:
			continue
		seen[id] = true
		var to := Vector3(float(row[4]), float(row[5]), float(row[6]))
		var s := str(row[2])
		var cls := str(row[3])
		if not _craft.has(id) or str(_craft[id].cls) != cls:
			if _craft.has(id):
				(_craft[id].node as Node3D).queue_free()
			var n := _fighter(cls, s)
			_world.add_child(n)
			n.position = to
			var label := _tag(n, "", 9.0, Color(0.5, 1.0, 0.9) if s == side else Color(1.0, 0.45, 0.35), 22)
			_craft[id] = {"node": n, "from": to, "to": to, "side": s, "cls": cls, "label": label}
		var c: Dictionary = _craft[id]
		c.from = (c.node as Node3D).position
		c.to = to
		c.fwd = Vector3(float(row[7]), float(row[8]), float(row[9]))
		c.up = Vector3(float(row[10]), float(row[11]), float(row[12]))
		c.alive = bool(row[14])
		c.name = str(row[1])
		(c.node as Node3D).visible = bool(row[14])
		var near := to.distance_to(_pos) < 2500.0 or id == target
		(c.label as Label3D).text = ("%s\n" % str(row[1]) if s == side or id == target else "") + ("|".repeat(clampi(ceili(float(row[13]) / 10.0), 0, 10)) if near else "")
	for id in _craft.keys():
		if not seen.has(id):
			(_craft[id].node as Node3D).queue_free()
			_craft.erase(id)


func _part_hp(id: String) -> int:
	for p in _state.get("parts", []):
		if str(p[0]) == id:
			return int(p[1])
	return 1


func _gens_up(s: String) -> bool:
	return _part_hp("%s:gen0" % s) > 0 or _part_hp("%s:gen1" % s) > 0


func _update_parts(rows: Array) -> void:
	for row in rows:
		var id := str(row[0])
		if not _parts.has(id):
			continue
		var p: Dictionary = _parts[id]
		var hp := int(row[1])
		var max_hp := float(p.info.get("maxHp", 1))
		(p.node as Node3D).visible = hp > 0
		if p.label:
			var shielded: bool = str(p.info.kind) == "sub" and _gens_up(str(p.info.side))
			(p.label as Label3D).text = "%s  %d%%%s" % [str(p.info.name).to_upper(), roundi(100.0 * hp / max_hp), "  (shielded)" if shielded else ""]


func _update_missiles(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		if not _missiles.has(id):
			_missiles[id] = _ball(_world, 2.0 if str(row[1]) == "missile" else 3.5, Vector3.ZERO, Color(1.0, 0.75, 0.3) if str(row[1]) == "missile" else Color(1.0, 0.4, 0.25), 2.5)
		(_missiles[id] as Node3D).position = Vector3(float(row[2]), float(row[3]), float(row[4]))
	for id in _missiles.keys():
		if not seen.has(id):
			(_missiles[id] as Node3D).queue_free()
			_missiles.erase(id)


func _update_drops(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		if _drops.has(id):
			continue
		var n := Node3D.new()
		n.position = Vector3(float(row[2]), float(row[3]), float(row[4]))
		var col := Color(0.4, 0.8, 1.0) if str(row[1]) == "shield" else Color(1.0, 0.6, 0.25)
		_box(n, Vector3(12, 12, 12), Vector3.ZERO, col, 3.0)
		_tag(n, "SHIELD BOOST" if str(row[1]) == "shield" else "ORDNANCE", 20.0, col, 24)
		_world.add_child(n)
		_drops[id] = n
	for id in _drops.keys():
		if not seen.has(id):
			(_drops[id] as Node3D).queue_free()
			_drops.erase(id)


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
	_picker.visible = false
	_sync_mouse()


## Leave battle: your side fights on (an AI pilot takes your place).
func leave() -> void:
	if not ended:
		Net.send({"type": "starfight_leave", "match": match_id})
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	active = false
	finished.emit()
	queue_free()


# --- Ship classes -----------------------------------------------------------------------------------

## Picks the class to launch with (at once if this life has only just launched).
func pick_class(cls: String) -> void:
	Net.send({"type": "starfight_class", "match": match_id, "cls": cls})
	_say("Next launch: %s" % str(info.get("classes", {}).get(cls, {}).get("name", cls)), Color(0.6, 0.9, 1.0))
	_close_picker()


func _open_picker(first: bool) -> void:
	_picker.visible = true
	_picker_note.text = "Pick your ship for this launch" if first else "Shot down: pick your ship for the next launch"
	_sync_mouse()


func _close_picker() -> void:
	_picker.visible = false
	_sync_mouse()


# --- HUD ---------------------------------------------------------------------------------------------

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
	_top.offset_left = -600
	_top.offset_right = 600
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capitals = _label(root, 16, Color(1.0, 0.85, 0.5))
	_capitals.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_capitals.offset_top = 42
	_capitals.offset_left = -600
	_capitals.offset_right = 600
	_capitals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -16
	_feed.offset_top = 100
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	var vitals := VBoxContainer.new()
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24
	vitals.offset_top = -150
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_flight_label = _label(vitals, 16, Color(0.85, 0.95, 1.0))
	_label(vitals, 14, Color(0.6, 0.85, 1.0)).text = "Shields"
	_shield_bar = _bar(vitals, Color(0.4, 0.8, 1.0))
	_label(vitals, 14, Color(0.6, 1.0, 0.7)).text = "Hull"
	_hp_bar = _bar(vitals, Color(0.45, 1.0, 0.55))
	_weapons = _label(root, 20, Color(0.95, 0.95, 1.0))
	_weapons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapons.offset_left = -900
	_weapons.offset_right = -24
	_weapons.offset_top = -110
	_weapons.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -9
	cross.offset_top = -20
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	_bracket = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.8, 0.3)
	sb.set_border_width_all(2)
	_bracket.add_theme_stylebox_override("panel", sb)
	_bracket.size = Vector2(36, 36)
	_bracket.visible = false
	_bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bracket)
	_down = _label(root, 28, Color(1.0, 0.5, 0.42))
	_down.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_down.offset_left = -450
	_down.offset_right = 450
	_down.offset_top = 60
	_down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board = _panel(root)
	_board_text = _label(_board, 16, Color(0.92, 0.94, 0.96))
	_board_text.custom_minimum_size = Vector2(620, 0)
	_banner = _panel(root)
	var bv := VBoxContainer.new()
	_banner.add_child(bv)
	_banner_title = _label(bv, 40, Color.WHITE)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text = _label(bv, 18, Color(0.9, 0.93, 0.95))
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(bv, 14, Color(0.7, 0.75, 0.8)).text = "Back to your carrier in a few seconds"
	_pause = _panel(root)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	_pause.add_child(pv)
	_label(pv, 26, Color.WHITE).text = "Space Battle"
	_label(pv, 14, Color(0.8, 0.85, 0.9)).text = "The battle goes on while you're here."
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): _set_paused(false))
	pv.add_child(resume)
	var cls := Button.new()
	cls.text = "Change ship class"
	cls.pressed.connect(func():
		_pause.visible = false
		_open_picker(false))
	pv.add_child(cls)
	var leave_b := Button.new()
	leave_b.text = "Leave battle"
	leave_b.pressed.connect(leave)
	pv.add_child(leave_b)
	# The ship class picker: at launch and every time you're shot down.
	_picker = _panel(root)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_picker.add_child(cv)
	_picker_note = _label(cv, 22, Color.WHITE)
	var classes: Dictionary = info.get("classes", {})
	for id in ["fighter", "interceptor", "bomber"]:
		var c: Dictionary = classes.get(id, {})
		var b := Button.new()
		b.text = "%s: %s" % [str(c.get("name", id)), str(c.get("text", ""))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(720, 40)
		b.pressed.connect(func(): pick_class(id))
		cv.add_child(b)


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


## A capital ship's state: its shield generators, then its subsystems.
func _capital_text(s: String) -> String:
	var gens := 0
	for k in ["gen0", "gen1"]:
		if _part_hp("%s:%s" % [s, k]) > 0:
			gens += 1
	var subs: Array = []
	for k in ["engines", "bridge", "reactor"]:
		var id := "%s:%s" % [s, k]
		var mx := 1.0
		if _parts.has(id):
			mx = float(_parts[id].info.get("maxHp", 1))
		subs.append("%s %d%%" % [k.capitalize(), roundi(100.0 * _part_hp(id) / mx)])
	return "Shield generators %d/2  ·  %s%s" % [gens, "  ".join(subs), "  (shielded)" if gens > 0 else ""]


func _update_hud() -> void:
	var s := _state
	var dmg: Dictionary = s.get("damage", {"a": 0, "d": 0})
	_top.text = "SPACE BATTLE · %s   ·   %s %d  –  %d %s (damage done)   ·   %s" % [str(info.get("planetName", "")), _side_name("a"), int(dmg.get("a", 0)), int(dmg.get("d", 0)), _side_name("d"), _time(int(s.get("left", info.get("seconds", 900))))]
	_capitals.text = "Enemy: %s\nYours: %s" % [_capital_text(_other(side)), _capital_text(side)]
	_hp_bar.max_value = float(_me.get("maxHp", 100))
	_hp_bar.value = float(_me.get("hp", 100))
	_shield_bar.max_value = float(_me.get("maxShield", 100)) * 1.5
	_shield_bar.value = float(_me.get("shield", 0))
	_flight_label.text = "%s   %d m/s%s%s\nSYS %d  ENG %d  WEP %d" % [str(info.get("classes", {}).get(_cls(), {}).get("name", "")), roundi(flight.speed()), "   BOOST" if flight.boost_left > 0.0 else "", "   DRIFT" if flight.drift else "", flight.pips[0] / 2, flight.pips[1] / 2, flight.pips[2] / 2]
	var lock := ""
	if target != "":
		var d := _target_pos().distance_to(_pos)
		lock = "\nTarget: %s  %d m  %s" % [_target_name(), roundi(d), "LOCKED" if locked() else ("locking…" if _lock > 0.0 else "")]
	_weapons.text = ("Torpedoes %d (right mouse)" % int(_me.get("torpedoes", 0)) if _cls() == "bomber" else "Missiles %d (right mouse)" % int(_me.get("missiles", 0))) + lock
	# The target's bracket on screen.
	var at := _target_pos()
	_bracket.visible = at != Vector3.INF and not _camera.is_position_behind(at) and _alive()
	if _bracket.visible:
		_bracket.position = _camera.unproject_position(at) - _bracket.size / 2
		(_bracket.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(1.0, 0.3, 0.25) if locked() else Color(1.0, 0.8, 0.3)
	if not _alive() and not ended:
		_down.text = "Shot down. Relaunching in %d" % ceili(float(_me.get("respawnIn", 0)))
	else:
		_down.text = ""
	if _board.visible:
		var lines: Array = []
		for sd in [side, _other(side)]:
			lines.append(_side_name(sd))
			for row in s.get("craft", []):
				if str(row[2]) == sd and (not bool(row[15]) or int(row[18]) == 0):
					lines.append("   %-22s %-11s %3d kills  %3d deaths%s" % [str(row[1]), str(row[3]), int(row[16]), int(row[17]), "  (AI)" if bool(row[15]) else ""])
			lines.append("")
		_board_text.text = "\n".join(lines)
	for l in _feed.get_children():
		l.modulate.a = clampf(9.0 - (_clock - float(l.get_meta("t"))), 0.0, 1.0)
