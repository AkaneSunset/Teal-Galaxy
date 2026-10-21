class_name DefenseView
extends Node3D
## Sector Defense, on foot in first person: the squad holds a walled position on the planet against
## waves of AI troops (server/defense.js runs them). Opened on defense_joined, wherever the pilot
## was; it has its own world and HUD, and closes itself a few seconds after the match ends.
##
## You move and look on your own screen and tell the server where you stand (defense_move, 10 a
## second) and every shot you fire (defense_fire: the ray from your eye); the server says what was
## hit, moves the enemies, and sends everyone the state ten times a second (defense_state).
## W A S D walk, Shift run, Space jump, mouse look, left mouse fire, R reload, 1 rifle, 2 rocket
## launcher (from supply drops), Esc pause (with Leave match). Walk over a supply drop to take it.

const WarInfo := preload("res://war_info.gd")

const WALK := 5.0
const SPRINT := 7.5
const JUMP := 4.5
const GRAVITY := 14.0
const EYE := 1.6
const MAG := 32
const RESERVE := 192
const RELOAD_S := 1.8
const MOVE_HZ := 10.0
const END_S := 7.0
const SILENT_S := 10.0
const ENEMY_TINT := Color(0.86, 0.6, 0.28) # the militia's, when no faction sends the troops

## True from open() until the view closes: the explorer stays out of the way meanwhile.
static var active := false

signal finished

var info := {} # defense_joined
var match_id := ""
var ended := false

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0
var _enemies := {} # id -> {"node", "from", "to", "type", "hp", "max", "bar"}
var _pilots := {} # name -> {"node", "from", "to"}
var _pickups := {} # id -> Node3D
var _snap_t := 0.0 # real seconds since the last snapshot
var _snap_dt := 0.1
var _silent := 0.0
var _move_t := 0.0
var _weapon := "rifle"
var _mag := MAG
var _reserve := RESERVE
var _reload_left := 0.0
var _fire_cd := 0.0
var _rockets := 0
var _me := {}
var _state := {}
var _ended_at := 0.0
var _clock := 0.0
var _tracers: Array = [] # {"node", "t"}
var _mats := {}
var _hud: CanvasLayer
var _top: Label
var _wave_note: Label
var _feed: VBoxContainer
var _hp_bar: ProgressBar
var _shield_bar: ProgressBar
var _ammo: Label
var _down: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _pause: PanelContainer
var _hit_flash: ColorRect
var _last_hp := 100.0


## Opens the view for the match the server just put the pilot in (`joined`: defense_joined).
static func open(host: Node, joined: Dictionary) -> DefenseView:
	var v := DefenseView.new()
	v.info = joined
	active = true
	host.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	match_id = str(info.get("match", ""))
	_build_world()
	_build_player()
	_build_hud()
	Net.message.connect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_say("Sector Defense on %s: hold off %s for 3 sets of 5 waves" % [str(info.get("planetName", "")), _enemy_name()], Color(1.0, 0.85, 0.5))
	_say("Your squad shares its lives. Supply drops land between waves.", Color(0.75, 0.85, 0.9))


func _exit_tree() -> void:
	active = false
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enemy_name() -> String:
	var e = info.get("enemy")
	return "the militia" if e == null or str(e) == "" else WarInfo.the(e)


func _enemy_colour() -> Color:
	var e = info.get("enemy")
	return ENEMY_TINT if e == null or str(e) == "" else WarInfo.faction_color(e)


# --- The arena -----------------------------------------------------------------------------------

func _mat(colour: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [colour, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
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


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.28, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.34, 0.4)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	_world.add_child(sun)
	var size := float(info.get("size", 120))
	# The ground, and the low wall round the position (troops come in through the gaps).
	_box(_world, Vector3(size + 80, 1, size + 80), Vector3(size / 2, -0.5, size / 2), Color(0.3, 0.27, 0.23))
	_box(_world, Vector3(size, 0.02, size), Vector3(size / 2, 0.01, size / 2), Color(0.26, 0.25, 0.23), false)
	for side in 4:
		for k in 2:
			var along := size * (0.22 if k == 0 else 0.78)
			var long := size * 0.4
			var pos := Vector3(along, 1.0, 0.5) if side == 0 else Vector3(along, 1.0, size - 0.5) if side == 1 else Vector3(0.5, 1.0, along) if side == 2 else Vector3(size - 0.5, 1.0, along)
			var dims := Vector3(long, 2.0, 1.0) if side < 2 else Vector3(1.0, 2.0, long)
			_box(_world, dims, pos, Color(0.36, 0.37, 0.4))
	for c in info.get("cover", []):
		var h := float(c[4])
		_box(_world, Vector3(float(c[2]), h, float(c[3])), Vector3(float(c[0]), h / 2.0, float(c[1])), Color(0.4, 0.41, 0.45))
		_box(_world, Vector3(float(c[2]) + 0.1, 0.08, float(c[3]) + 0.1), Vector3(float(c[0]), h + 0.04, float(c[1])), Color(0.3, 0.9, 0.85), false, 1.5)
	# Where the waves come in: glowing gates in the enemy's colour.
	for s in info.get("spawns", []):
		_box(_world, Vector3(4, 0.1, 4), Vector3(float(s[0]), 0.06, float(s[1])), _enemy_colour(), false, 2.0)
	# The beacon in the middle that the squad holds.
	_box(_world, Vector3(0.6, 9, 0.6), Vector3(size / 2, 4.5, size / 2), Color(0.25, 0.27, 0.3), false)
	_box(_world, Vector3(1.2, 1.2, 1.2), Vector3(size / 2, 9.5, size / 2), Color(0.3, 0.95, 0.9), false, 3.0)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.4
	shape.shape.height = 1.8
	shape.position.y = 0.9
	_player.add_child(shape)
	var start: Array = info.get("start", [60, 52])
	_player.position = Vector3(float(start[0]), 0.1, float(start[1]))
	_world.add_child(_player)
	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = 80.0
	_camera.near = 0.05
	_player.add_child(_camera)
	_camera.make_current()
	# The rifle, held low on the right.
	var gun := Node3D.new()
	gun.position = Vector3(0.22, -0.2, -0.75)
	_camera.add_child(gun)
	_box(gun, Vector3(0.05, 0.07, 0.4), Vector3.ZERO, Color(0.15, 0.16, 0.18), false)
	_box(gun, Vector3(0.03, 0.012, 0.14), Vector3(0, 0.04, -0.06), Color(0.3, 0.9, 0.85), false, 1.5)


# --- Input and moving ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		_set_paused(not _pause.visible)
		get_viewport().set_input_as_handled()
		return
	if _pause.visible or ended:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_player.rotate_y(-event.relative.x * 0.0025)
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.4, 1.4)
		_camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("foot_reload"):
		_reload()
	elif event.is_action_pressed("foot_weapon_1"):
		_switch("rifle")
	elif event.is_action_pressed("foot_weapon_2") or event.is_action_pressed("foot_weapon_next") or event.is_action_pressed("foot_weapon_prev"):
		_switch("rocket" if _weapon == "rifle" else "rifle")


func _set_paused(on: bool) -> void:
	_pause.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _switch(w: String) -> void:
	if w == "rocket" and _rockets <= 0:
		_say("No rocket launcher: take one from a supply drop", Color(1.0, 0.6, 0.5))
		return
	_weapon = w
	_reload_left = 0.0


func _reload() -> void:
	if _weapon != "rifle" or _mag >= MAG or _reserve <= 0 or _reload_left > 0.0:
		return
	_reload_left = RELOAD_S


func _alive() -> bool:
	return bool(_me.get("alive", true))


func _physics_process(delta: float) -> void:
	_clock += delta
	if ended:
		if _clock - _ended_at > END_S:
			close()
		return
	var walking := not _pause.visible and _alive()
	var input := Input.get_vector("foot_left", "foot_right", "foot_forward", "foot_back") if walking else Vector2.ZERO
	var speed := SPRINT if Input.is_action_pressed("foot_sprint") else WALK
	var dir := (_player.global_basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
	_player.velocity.x = dir.x * speed
	_player.velocity.z = dir.z * speed
	if _player.is_on_floor():
		if walking and Input.is_action_just_pressed("foot_jump"):
			_player.velocity.y = JUMP
	else:
		_player.velocity.y -= GRAVITY * delta
	_player.move_and_slide()
	var size := float(info.get("size", 120))
	_player.position.x = clampf(_player.position.x, 0.5, size - 0.5)
	_player.position.z = clampf(_player.position.z, 0.5, size - 0.5)
	# Weapons.
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var n := mini(MAG - _mag, _reserve)
			_mag += n
			_reserve -= n
	if walking and Input.is_action_pressed("foot_fire") and _fire_cd <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_fire()
	# Tell the server where we are.
	_move_t -= delta
	if _move_t <= 0.0:
		_move_t = 1.0 / MOVE_HZ
		Net.send({"type": "defense_move", "match": match_id, "x": _player.position.x, "z": _player.position.z, "yaw": _player.rotation.y})


func _fire() -> void:
	if _weapon == "rifle":
		if _reload_left > 0.0:
			return
		if _mag <= 0:
			_reload()
			return
		_mag -= 1
		_fire_cd = 0.1
	else:
		if _rockets <= 0:
			_switch("rifle")
			return
		_rockets -= 1
		_fire_cd = 1.0
	var from := _camera.global_position
	var dir := -_camera.global_basis.z
	Net.send({"type": "defense_fire", "match": match_id, "weapon": _weapon, "y": from.y, "dx": dir.x, "dy": dir.y, "dz": dir.z})
	_tracer(from + dir * 0.6 + _camera.global_basis.x * 0.2 - _camera.global_basis.y * 0.15, from + dir * 60.0, Color(0.5, 1.0, 0.95) if _weapon == "rifle" else Color(1.0, 0.6, 0.2))


func _tracer(a: Vector3, b: Vector3, colour: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat(colour, 3.0))
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mi)
	_tracers.append({"node": mi, "t": _clock})


func _process(delta: float) -> void:
	_snap_t += delta
	_silent += delta
	if not ended and _silent > SILENT_S:
		_end({"won": false, "text": "Contact with the match was lost"})
	var alpha := clampf(_snap_t / maxf(_snap_dt, 0.05), 0.0, 1.0)
	for id in _enemies:
		var e: Dictionary = _enemies[id]
		var g: Vector2 = (e.from as Vector2).lerp(e.to, alpha)
		var n: Node3D = e.node
		n.position = Vector3(g.x, n.position.y, g.y)
		n.rotation.y = lerp_angle(n.rotation.y, float(e.heading), 1.0 - exp(-8.0 * delta))
	for name in _pilots:
		var p: Dictionary = _pilots[name]
		var g2: Vector2 = (p.from as Vector2).lerp(p.to, alpha)
		p.node.position = Vector3(g2.x, 0, g2.y)
	while not _tracers.is_empty() and _clock - float(_tracers[0].t) > 0.08:
		_tracers.pop_front().node.queue_free()
	_hit_flash.color.a = maxf(0.0, _hit_flash.color.a - delta * 1.5)
	_update_hud()


# --- The server -----------------------------------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"defense_state":
			if str(msg.get("match", "")) == match_id:
				_snapshot(msg)
		"defense_end":
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
	_me = me
	_rockets = int(me.get("rockets", _rockets))
	if _rockets <= 0 and _weapon == "rocket":
		_weapon = "rifle"
	var hp := float(me.get("hp", 100)) + float(me.get("shield", 0))
	if hp < _last_hp - 0.5:
		_hit_flash.color.a = 0.35
	_last_hp = hp
	# The server's place for us: a respawn, or our screen drifted too far from what it allowed.
	var at := Vector2(float(me.get("x", _player.position.x)), float(me.get("z", _player.position.z)))
	if (not was_alive and _alive()) or at.distance_to(Vector2(_player.position.x, _player.position.z)) > 4.0:
		_player.position = Vector3(at.x, 0.2, at.y)
		_player.velocity = Vector3.ZERO
	if not was_alive and _alive():
		_mag = MAG
		_reserve = RESERVE
	_update_enemies(msg.get("enemies", []))
	_update_pilots(msg.get("pilots", []))
	_update_pickups(msg.get("pickups", []))
	for s in msg.get("shots", []):
		var who := str(s[0])
		if who == Net.my_name:
			continue
		var y := 1.4
		_tracer(Vector3(float(s[1]), y, float(s[2])), Vector3(float(s[3]), 1.2, float(s[4])), _enemy_colour().lightened(0.3) if who.begins_with("e") else Color(0.5, 1.0, 0.95))
	for f in msg.get("feed", []):
		if f.has("text"):
			_say(str(f.text))
		elif f.has("took") and str(f.get("name", "")) == Net.my_name:
			_took(str(f.took))
		elif f.has("took"):
			_say("%s took the %s" % [f.name, _pickup_name(str(f.took))], Color(0.75, 0.85, 0.9))


func _took(kind: String) -> void:
	match kind:
		"ammo":
			_reserve = RESERVE
			_mag = MAG
			_say("Ammo refilled", Color(0.5, 1.0, 0.6))
		"health":
			_say("Health restored", Color(0.5, 1.0, 0.6))
		"shield":
			_say("Shields recharged", Color(0.5, 1.0, 0.6))
		"rocket":
			_say("Rocket launcher: press 2", Color(1.0, 0.75, 0.3))


func _pickup_name(kind: String) -> String:
	return {"ammo": "ammo crate", "health": "med pack", "shield": "shield cell", "rocket": "rocket launcher"}.get(kind, kind)


func _enemy_node(type: String) -> Node3D:
	var c: Dictionary = info.get("enemies", {}).get(type, {})
	var radius := float(c.get("radius", 0.5))
	var height := float(c.get("height", 1.8))
	var tint := _enemy_colour()
	var root := Node3D.new()
	if type == "drone":
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 0.8
		sm.material = _mat(tint.darkened(0.2))
		s.mesh = sm
		s.position.y = float(c.get("fly", 3.5)) + 0.4
		root.add_child(s)
		_box(s, Vector3(0.3, 0.12, 0.2), Vector3(0, 0, -0.45), Color(1.0, 0.3, 0.2), false, 3.0)
	else:
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = radius
		cap.height = height
		cap.material = _mat(tint.darkened(0.15 if type != "boss" else 0.35))
		body.mesh = cap
		body.position.y = height / 2.0
		root.add_child(body)
		_box(root, Vector3(radius * 1.4, 0.16, 0.2), Vector3(0, height * 0.85, -radius * 0.8), Color(1.0, 0.3, 0.2), false, 3.0)
		if type == "boss" or type == "brute":
			_box(root, Vector3(radius * 2.6, radius * 0.6, radius * 1.4), Vector3(0, height * 0.72, 0), tint.darkened(0.45), false)
	# Its health, over its head.
	var bar := Label3D.new()
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.pixel_size = 0.004
	bar.font_size = 48 if type != "boss" else 72
	bar.outline_size = 8
	bar.position.y = height + 0.5 + (float(c.get("fly", 0)))
	bar.modulate = Color(1.0, 0.45, 0.35)
	root.add_child(bar)
	root.set_meta("bar", bar)
	_world.add_child(root)
	return root


func _update_enemies(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		var to := Vector2(float(row[2]), float(row[3]))
		if not _enemies.has(id):
			var n := _enemy_node(str(row[1]))
			n.position = Vector3(to.x, 0, to.y)
			_enemies[id] = {"node": n, "from": to, "to": to, "type": str(row[1]), "heading": 0.0}
		var e: Dictionary = _enemies[id]
		e.from = Vector2(e.node.position.x, e.node.position.z)
		e.to = to
		e.heading = float(row[6]) + PI
		var bar: Label3D = e.node.get_meta("bar")
		var hp := int(row[4])
		var most := maxi(1, int(row[5]))
		bar.text = "" if hp >= most and str(row[1]) != "boss" else ("%s  " % info.get("enemies", {}).get(str(row[1]), {}).get("name", "") if str(row[1]) == "boss" else "") + "|".repeat(clampi(ceili(10.0 * hp / most), 0, 10))
	for id in _enemies.keys():
		if not seen.has(id):
			_enemies[id].node.queue_free()
			_enemies.erase(id)


func _update_pilots(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var name := str(row[0])
		if name == Net.my_name:
			continue
		seen[name] = true
		var to := Vector2(float(row[1]), float(row[2]))
		if not _pilots.has(name):
			var root := Node3D.new()
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.4
			cap.height = 1.8
			cap.material = _mat(WarInfo.faction_color(info.get("faction")))
			body.mesh = cap
			body.position.y = 0.9
			root.add_child(body)
			var tag := Label3D.new()
			tag.text = name
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.pixel_size = 0.004
			tag.font_size = 40
			tag.outline_size = 8
			tag.position.y = 2.3
			tag.modulate = Color(0.5, 1.0, 0.9)
			root.add_child(tag)
			_world.add_child(root)
			root.position = Vector3(to.x, 0, to.y)
			_pilots[name] = {"node": root, "from": to, "to": to}
		var p: Dictionary = _pilots[name]
		p.from = Vector2(p.node.position.x, p.node.position.z)
		p.to = to
		p.node.rotation.y = float(row[3])
		p.node.visible = bool(row[6])
	for name in _pilots.keys():
		if not seen.has(name):
			_pilots[name].node.queue_free()
			_pilots.erase(name)


func _update_pickups(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id := int(row[0])
		seen[id] = true
		if _pickups.has(id):
			continue
		var kind := str(row[1])
		var colour: Color = {"ammo": Color(0.95, 0.8, 0.3), "health": Color(0.4, 1.0, 0.5), "shield": Color(0.4, 0.8, 1.0), "rocket": Color(1.0, 0.5, 0.2)}.get(kind, Color.WHITE)
		var root := Node3D.new()
		root.position = Vector3(float(row[2]), 0, float(row[3]))
		_box(root, Vector3(0.9, 0.6, 0.9), Vector3(0, 0.3, 0), colour.darkened(0.3), false)
		_box(root, Vector3(0.95, 0.08, 0.95), Vector3(0, 0.62, 0), colour, false, 3.0)
		_box(root, Vector3(0.1, 6.0, 0.1), Vector3(0, 3.5, 0), colour, false, 2.0) # a beacon so it can be found
		var tag := Label3D.new()
		tag.text = _pickup_name(kind).to_upper()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.004
		tag.font_size = 40
		tag.outline_size = 8
		tag.position.y = 1.3
		tag.modulate = colour
		root.add_child(tag)
		_world.add_child(root)
		_pickups[id] = root
	for id in _pickups.keys():
		if not seen.has(id):
			_pickups[id].queue_free()
			_pickups.erase(id)


func _end(msg: Dictionary) -> void:
	if ended:
		return
	ended = true
	_ended_at = _clock
	_banner_title.text = "Sector held" if bool(msg.get("won", false)) else "Sector lost"
	_banner_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6) if bool(msg.get("won", false)) else Color(1.0, 0.42, 0.35))
	_banner_text.text = str(msg.get("text", ""))
	_banner.visible = true
	_pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Leave match: the squad fights on without you (alone, the match is lost).
func leave() -> void:
	if not ended:
		Net.send({"type": "defense_leave", "match": match_id})
	close()


func close() -> void:
	if is_queued_for_deletion():
		return
	active = false
	finished.emit()
	queue_free()


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
	_top.offset_left = -500
	_top.offset_right = 500
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_note = _label(root, 26, Color(1.0, 0.85, 0.5))
	_wave_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wave_note.offset_top = 70
	_wave_note.offset_left = -500
	_wave_note.offset_right = 500
	_wave_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -16
	_feed.offset_top = 110
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	var vitals := VBoxContainer.new()
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24
	vitals.offset_top = -90
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_label(vitals, 14, Color(0.6, 0.85, 1.0)).text = "Shield"
	_shield_bar = _bar(vitals, Color(0.4, 0.8, 1.0))
	_shield_bar.max_value = float(info.get("shield", 60))
	_label(vitals, 14, Color(0.6, 1.0, 0.7)).text = "Health"
	_hp_bar = _bar(vitals, Color(0.45, 1.0, 0.55))
	_hp_bar.max_value = float(info.get("hp", 100))
	_ammo = _label(root, 24, Color(0.95, 0.95, 1.0))
	_ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.offset_left = -360
	_ammo.offset_right = -24
	_ammo.offset_top = -70
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_down = _label(root, 30, Color(1.0, 0.5, 0.42))
	_down.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_down.offset_left = -400
	_down.offset_right = 400
	_down.offset_top = 40
	_down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The end banner.
	_banner = PanelContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.visible = false
	root.add_child(_banner)
	var bv := VBoxContainer.new()
	_banner.add_child(bv)
	_banner_title = _label(bv, 40, Color.WHITE)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text = _label(bv, 18, Color(0.9, 0.93, 0.95))
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(bv, 14, Color(0.7, 0.75, 0.8)).text = "Back to your carrier in a few seconds"
	# Paused: Esc. Leave match goes back to the carrier.
	_pause = PanelContainer.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.visible = false
	root.add_child(_pause)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	_pause.add_child(pv)
	_label(pv, 26, Color.WHITE).text = "Sector Defense"
	_label(pv, 14, Color(0.8, 0.85, 0.9)).text = "The match goes on while you're here."
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): _set_paused(false))
	pv.add_child(resume)
	var leave_b := Button.new()
	leave_b.text = "Leave match"
	leave_b.pressed.connect(leave)
	pv.add_child(leave_b)


func _say(text: String, colour := Color(0.9, 0.93, 0.95)) -> void:
	var l := _label(_feed, 16, colour)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.set_meta("t", _clock)
	while _feed.get_child_count() > 7:
		_feed.get_child(0).free()


func _update_hud() -> void:
	var s := _state
	var mods := []
	for m in s.get("modifiers", []):
		mods.append(str(info.get("modifiers", {}).get(m, {}).get("name", m)))
	_top.text = "SECTOR DEFENSE · %s   ·   Set %d of %d   Wave %d of %d   ·   Lives %d   ·   Enemies %d%s" % [
		str(info.get("planetName", "")), int(s.get("set", 1)), int(info.get("sets", 3)), int(s.get("wave", 0)), int(info.get("waves", 5)),
		int(s.get("lives", 0)), s.get("enemies", []).size(), ("   ·   " + ", ".join(mods)) if not mods.is_empty() else ""]
	_wave_note.text = "Next wave in %d" % ceili(float(s.get("breakLeft", 0))) if str(s.get("phase", "")) == "break" and not ended else ""
	_hp_bar.value = float(_me.get("hp", 100))
	_shield_bar.value = float(_me.get("shield", 0))
	if _weapon == "rifle":
		_ammo.text = ("Reloading…" if _reload_left > 0.0 else "Rifle  %d / %d" % [_mag, _reserve]) + ("\nRockets %d (2)" % _rockets if _rockets > 0 else "")
	else:
		_ammo.text = "Rocket launcher  %d" % _rockets
	if not _alive() and not ended:
		var r := float(_me.get("respawnIn", 0))
		_down.text = "You're down. Back in %d" % ceili(r) if r > 0.0 else "You're down, and the squad has no lives left"
	else:
		_down.text = ""
	for l in _feed.get_children():
		l.modulate.a = clampf(8.0 - (_clock - float(l.get_meta("t"))), 0.0, 1.0)
