extends Node3D
## On foot inside a Builder's facility: sneak or fight past the guards, search containers,
## open the vault, and get out through an extract before the clock runs out.
##
## The server sends the layout and owns the loot, Heat, the clock and every extraction; this
## scene simulates walking, the guards and the shooting, and reports what happened (see heist.js).
## Everything is built from simple shapes in code, like the rest of the prototype.

signal finished(result: Dictionary)

const InventoryView := preload("res://raid_inventory.gd")

# Movement, from the spec's starting values.
const WALK := 4.5
const SPRINT := 6.5
const CROUCH := 2.5
const JUMP := 4.2
const GRAVITY := 14.0
const EYE := 1.6
const EYE_CROUCHED := 1.0
const REACH := 2.4 # metres to use a container, door or guard
const LOOK_SPEED := 2.6 # rad/s with a gamepad or arrow keys at full deflection

# The rifle.
const MAG := 30
const RESERVE := 150
const FIRE_GAP := 0.1
const RELOAD_SECONDS := 2.0
const DAMAGE := 34.0
const RANGE := 120.0
const FOV := 90.0
const FOV_AIM := 60.0

# Noise radii (metres) that guards hear.
const NOISE_GUNSHOT := 120.0
const NOISE_SPRINT := 22.0
const NOISE_WALK := 8.0
const NOISE_DRILL := 60.0
const NOISE_EXTRACT := 150.0

# Guards.
const GUARD_HEALTH := 100.0
const GUARD_SPEED := 2.2
const GUARD_RUN := 4.6
const GUARD_DAMAGE := 12.0
const GUARD_SIGHT := 22.0
const GUARD_FOV := 0.6 # cosine of the half-angle they see (about 106 degrees wide)
const GUARD_REACTION := 0.45
const GUARD_TELL := 0.5 # the aiming laser shows this long before the first shot
const ATTACK_TOKENS := 2 # at most this many guards shoot at you at once
const REINFORCE_EVERY := 90.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_GUARDS := 4

const RARITY_COLOURS := {
	"common": Color(0.62, 0.64, 0.66), "uncommon": Color(0.4, 0.8, 0.4), "rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.45, 1.0), "legendary": Color(1.0, 0.78, 0.25),
}

var controls: Node # controls.gd, shared with flight
var god_mode := false # tests: guards can't hurt you

var brief: Dictionary
var layout: Dictionary
var room := 14.0
var rooms := {} # id -> room
var heat := 0
var level := 0
var remaining := 0.0
var extract_states := {}
var vault_open := false
var inventory: Array = []
var health := 100.0
var ammo := MAG
var reserve := RESERVE
var over := false

var _player: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0
var _crouched := false
var _fire_cd := 0.0
var _reload_left := 0.0
var _recoil := 0.0
var _step_noise := 0.0
var _hit_flash := 0.0
var _hurt_flash := 0.0
var _hurt_from := Vector3.ZERO
var _gunshot_sent_at := -10000

var _guards: Array = [] # {"id", "body", "health", "state", "route", "leg", "target", "aware", "tell", "cd", "seen_at", "dead", "noticed", "laser", "elite"}
var _turrets: Array = []
var _tokens := 0
var _last_known := Vector3.INF # where any guard last saw you
var _reinforce_in := REINFORCE_EVERY
var _elite_sent := false
var _containers := {} # id -> {"node", "data"}
var _vault_doors: Array[Node3D] = []
var _vault_room_centre := Vector3.ZERO
var _extract_nodes := {} # id -> {"node", "label", "data"}
var _drill: Node3D
var _drill_left := -1.0
var _extracting := "" # extract id while standing in one
var _extract_left := 0.0
var _open_container := ""

var _hud: Control
var _prompt: Label
var _status: Label
var _message: Label
var _message_time := 0.0
var _centre: Label
var _inv: Control
var _results: Control
var _paused: Control


func _init(briefing: Dictionary) -> void:
	brief = briefing
	layout = briefing.layout
	room = float(layout.room)
	heat = int(briefing.heat)
	level = int(briefing.level)
	remaining = float(briefing.remaining) / 1000.0
	extract_states = briefing.extracts
	vault_open = briefing.vaultOpen
	inventory = briefing.inventory


func _ready() -> void:
	for r in layout.rooms:
		rooms[int(r.id)] = r
	_build_environment()
	_build_rooms()
	_build_props()
	_build_player()
	_build_guards()
	_build_hud()
	Net.raid_event.connect(_on_raid_event)
	Net.server_error.connect(_on_server_error)
	controls.capture_mouse()
	_say("You're in %s. Find the vault, take what you can carry, and get out." % brief.facility, 6.0)


func _exit_tree() -> void:
	if Net.raid_event.is_connected(_on_raid_event):
		Net.raid_event.disconnect(_on_raid_event)
		Net.server_error.disconnect(_on_server_error)


# --- Building the facility -----------------------------------------------------------

func _room_centre(id: int) -> Vector3:
	var r: Dictionary = rooms[id]
	return Vector3(r.pos[0], 0, r.pos[1])


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.48)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.1)
	env.fog_density = 0.012
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _box(size: Vector3, pos: Vector3, colour: Color, solid := true, glow := false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	if glow:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not solid:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.add_child(mi)
	add_child(body)
	return body


func _label(text: String, pos: Vector3, size := 48, colour := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = colour
	l.outline_size = 8
	add_child(l)
	return l


func _door_between(a: int, b: int) -> Dictionary:
	for d in layout.doors:
		if (int(d.a) == a and int(d.b) == b) or (int(d.a) == b and int(d.b) == a):
			return d
	return {}


func _build_rooms() -> void:
	var h := 4.0
	var t := 0.3
	var half := room / 2.0
	var door := 2.4
	var wall := Color(0.32, 0.35, 0.4)
	for id in rooms:
		var r: Dictionary = rooms[id]
		var c := _room_centre(id)
		var ring: String = r.ring
		var floor_col: Color = {"perimeter": Color(0.22, 0.24, 0.27), "interior": Color(0.18, 0.21, 0.27), "core": Color(0.25, 0.14, 0.14)}[ring]
		_box(Vector3(room, 0.2, room), c + Vector3(0, -0.1, 0), floor_col)
		_box(Vector3(room, 0.2, room), c + Vector3(0, h + 0.1, 0), Color(0.1, 0.11, 0.13), false)
		var light := OmniLight3D.new()
		light.position = c + Vector3(0, h - 0.4, 0)
		light.omni_range = room * 0.95
		light.light_energy = 1.6
		light.light_color = {"perimeter": Color(0.95, 0.95, 1.0), "interior": Color(0.7, 0.85, 1.0), "core": Color(1.0, 0.55, 0.45)}[ring]
		add_child(light)
		_box(Vector3(2.5, 0.06, 0.4), c + Vector3(0, h - 0.05, 0), light.light_color, false, true)

		# Each room builds its east and south walls; the edge of the grid gets the west and north.
		var x: int = int(r.x)
		var y: int = int(r.y)
		var sides := [[Vector3(half, 0, 0), true, x + 1 < int(layout.cols), id + 1], [Vector3(0, 0, half), false, y + 1 < int(layout.rows), id + int(layout.cols)]]
		if x == 0:
			sides.append([Vector3(-half, 0, 0), true, false, -1])
		if y == 0:
			sides.append([Vector3(0, 0, -half), false, false, -1])
		for side in sides:
			var offset: Vector3 = side[0]
			var along_z: bool = side[1]
			var inside: bool = side[2]
			var d := _door_between(id, side[3]) if inside else {}
			var is_airlock: bool = id == int(layout.entrance) and offset.z > 0
			var gap := not d.is_empty() or is_airlock
			var base := c + offset + Vector3(0, h / 2.0, 0)
			if not gap:
				_box(Vector3(t, h, room) if along_z else Vector3(room, h, t), base, wall)
				continue
			var seg := (room - door) / 2.0
			for sgn in [-1, 1]:
				var shift: float = (door / 2.0 + seg / 2.0) * sgn
				_box(Vector3(t, h, seg) if along_z else Vector3(seg, h, t), base + (Vector3(0, 0, shift) if along_z else Vector3(shift, 0, 0)), wall)
			_box(Vector3(t, h - 2.6, door) if along_z else Vector3(door, h - 2.6, t), base + Vector3(0, 1.3, 0), wall)
			if not d.is_empty() and d.locked:
				var slab := _box(Vector3(t * 0.6, 2.6, door) if along_z else Vector3(door, 2.6, t * 0.6), c + offset + Vector3(0, 1.3, 0), Color(0.75, 0.2, 0.15), true, true)
				_vault_doors.append(slab)
				slab.visible = not vault_open
				slab.get_child(0).disabled = vault_open

	# Outside the airlock: the landing platform with the Shuttle Pad.
	var e := _room_centre(int(layout.entrance))
	_box(Vector3(room, 0.2, 12), e + Vector3(0, -0.1, half + 6), Color(0.2, 0.22, 0.25))
	for sgn in [-1, 1]:
		_box(Vector3(0.15, 1.1, 12), e + Vector3(sgn * half, 0.55, half + 6), Color(0.9, 0.6, 0.2), true, true)
	_box(Vector3(room, 1.1, 0.15), e + Vector3(0, 0.55, half + 12), Color(0.9, 0.6, 0.2), true, true)
	_vault_room_centre = _room_centre(int(layout.vault))


func _build_props() -> void:
	var sizes := {"locker": Vector3(1.0, 2.0, 0.6), "crate": Vector3(1.4, 0.9, 1.0), "desk": Vector3(1.6, 0.8, 0.8), "rack": Vector3(0.8, 2.1, 1.0), "vault": Vector3(1.2, 1.2, 1.2)}
	var colours := {"locker": Color(0.4, 0.45, 0.5), "crate": Color(0.5, 0.42, 0.28), "desk": Color(0.35, 0.33, 0.3), "rack": Color(0.15, 0.17, 0.2), "vault": Color(0.75, 0.62, 0.2)}
	var names := {"locker": "Locker", "crate": "Crate", "desk": "Desk", "rack": "Server rack", "vault": "Vault box"}
	for c in layout.containers:
		var size: Vector3 = sizes[c.type]
		var pos := _room_centre(int(c.room)) + Vector3(c.pos[0], size.y / 2.0, c.pos[1])
		var node := _box(size, pos, colours[c.type], true, c.type == "vault")
		var tag := _label(names[c.type], pos + Vector3(0, size.y / 2.0 + 0.3, 0), 28, Color(1, 1, 1, 0.7))
		_containers[c.id] = {"node": node, "data": c, "name": names[c.type], "tag": tag}

	var ex_colours := {"shuttle": Color(0.3, 1.0, 0.6), "lift": Color(0.4, 0.7, 1.0), "pod": Color(1.0, 0.75, 0.3)}
	var ex_names := {"shuttle": "Shuttle Pad", "lift": "Service Lift", "pod": "Escape Pod"}
	for ex in layout.extracts:
		var pos := _room_centre(int(ex.room)) + Vector3(ex.pos[0], 0, ex.pos[1])
		var ring := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 2.2
		mesh.bottom_radius = 2.2
		mesh.height = 0.05
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(ex_colours[ex.kind], 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = ex_colours[ex.kind]
		mesh.material = mat
		ring.mesh = mesh
		ring.position = pos + Vector3(0, 0.03, 0)
		add_child(ring)
		var label := _label(ex_names[ex.kind], pos + Vector3(0, 2.6, 0), 40, ex_colours[ex.kind])
		_extract_nodes[ex.id] = {"node": ring, "label": label, "data": ex, "pos": pos, "name": ex_names[ex.kind]}
	_refresh_extract_labels()

	for t in layout.turrets:
		var pos := _vault_room_centre + Vector3(t.pos[0], 0, t.pos[1])
		var base := _box(Vector3(0.6, 1.2, 0.6), pos + Vector3(0, 0.6, 0), Color(0.3, 0.3, 0.32))
		var head := _box(Vector3(0.5, 0.35, 0.9), pos + Vector3(0, 1.4, 0), Color(0.6, 0.15, 0.12), false, true)
		_turrets.append({"base": base, "head": head, "pos": pos + Vector3(0, 1.4, 0), "health": 300.0, "tell": 0.0, "cd": 0.0, "dead": false, "laser": _laser()})


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.collision_layer = LAYER_PLAYER
	_player.collision_mask = LAYER_WORLD | LAYER_GUARDS
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.shape.height = 1.8
	shape.position.y = 0.9
	_player.add_child(shape)
	var e := _room_centre(int(layout.entrance))
	_player.position = e + Vector3(0, 0.05, room / 2.0 + 4.0)
	add_child(_player)
	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 400.0
	_player.add_child(_camera)
	_camera.make_current()

	# The rifle, held low and to the right.
	var gun := Node3D.new()
	gun.position = Vector3(0.22, -0.2, -0.45)
	gun.name = "Gun"
	_camera.add_child(gun)
	var parts := [[Vector3(0.07, 0.09, 0.55), Vector3(0, 0, 0), Color(0.12, 0.13, 0.15)],
		[Vector3(0.04, 0.04, 0.3), Vector3(0, 0.015, -0.4), Color(0.08, 0.08, 0.09)],
		[Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, 0.08), Color(0.12, 0.13, 0.15)],
		[Vector3(0.03, 0.02, 0.12), Vector3(0, 0.065, -0.05), Color(0.35, 0.95, 0.88)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = p[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[2]
		if p[2].g > 0.9:
			mat.emission_enabled = true
			mat.emission = p[2]
		mesh.material = mat
		mi.mesh = mesh
		mi.position = p[1]
		gun.add_child(mi)


func _guard_body(elite := false) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = LAYER_GUARDS
	body.collision_mask = LAYER_WORLD | LAYER_PLAYER
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.38
	shape.shape.height = 1.85
	shape.position.y = 0.925
	body.add_child(shape)
	var colour := Color(0.75, 0.2, 0.2) if elite else Color(0.62, 0.55, 0.3)
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	cap.material = mat
	torso.mesh = cap
	torso.position.y = 0.75
	body.add_child(torso)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = colour.darkened(0.3)
	sphere.material = hmat
	head.mesh = sphere
	head.position.y = 1.65
	body.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.3, 0.07, 0.1)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(1.0, 0.3, 0.2)
	vmat.emission_enabled = true
	vmat.emission = Color(1.0, 0.3, 0.2)
	vm.material = vmat
	visor.mesh = vm
	visor.position = Vector3(0, 1.67, -0.18)
	visor.name = "Visor"
	body.add_child(visor)
	add_child(body)
	return body


func _laser() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	mi.mesh = mesh
	mi.visible = false
	add_child(mi)
	return mi


func _build_guards() -> void:
	for g in layout.guards:
		var route: Array = []
		for r in g.route:
			route.append(int(r))
		_spawn_guard(g.id, route, _room_centre(route[0]), false)


func _spawn_guard(id: String, route: Array, at: Vector3, elite: bool) -> Dictionary:
	var body := _guard_body(elite)
	body.position = at + Vector3(randf_range(-2, 2), 0.05, randf_range(-2, 2))
	var g := {"id": id, "body": body, "health": GUARD_HEALTH * (2.0 if elite else 1.0), "state": "patrol", "route": route,
		"leg": 0, "path": [], "target": Vector3.ZERO, "aware": 0.0, "tell": 0.0, "cd": 0.0, "dead": false,
		"noticed": {}, "laser": _laser(), "elite": elite, "search": 0.0, "has_token": false, "burst": 0}
	_guards.append(g)
	_path_to(g, _room_centre(route[min(1, route.size() - 1)]))
	return g


# --- HUD -------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_status = Label.new()
	_status.position = Vector2(16, 16)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_status)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 170
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_prompt)
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position.y += 70
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.add_theme_font_size_override("font_size", 18)
	_message.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_message)
	_centre = Label.new()
	_centre.set_anchors_preset(Control.PRESET_CENTER)
	_centre.position.y -= 90
	_centre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_centre.add_theme_font_size_override("font_size", 30)
	_centre.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_child(_centre)

	_inv = InventoryView.new()
	_inv.visible = false
	layer.add_child(_inv)
	_inv.take.connect(func(uid, to): Net.send({"type": "raid_take", "uid": uid, "to": to}))
	_inv.drop.connect(func(uid): Net.send({"type": "raid_drop", "uid": uid}))
	_inv.stow.connect(func(uid, to): Net.send({"type": "raid_stow", "uid": uid, "to": to}))
	_inv.closed.connect(_close_inventory)
	_inv.set_inventory(inventory, brief.backpack, brief.secure)

	_paused = _overlay_panel()
	layer.add_child(_paused)


func _overlay_panel() -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0.02, 0.05, 0.85)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := Label.new()
	title.text = "Paused (the raid clock keeps running)"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var resume := Button.new()
	resume.text = "Back to the raid (Esc)"
	resume.pressed.connect(func(): _set_paused(false))
	col.add_child(resume)
	var bail := Button.new()
	bail.name = "Bail"
	bail.text = "Bail out (only in the first 2 minutes; you keep nothing you found)"
	bail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bail.pressed.connect(func(): Net.send({"type": "raid_bail"}); _set_paused(false))
	col.add_child(bail)
	return root


func _say(text: String, seconds := 4.0) -> void:
	_message.text = text
	_message_time = seconds


func _set_paused(on: bool) -> void:
	_paused.visible = on
	if on:
		controls.release_mouse()
	elif not _inv.visible:
		controls.capture_mouse()


# --- Input -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if over:
		return
	if _paused.visible:
		if event.is_action_pressed("menu"):
			_set_paused(false)
		return
	if event.is_action_pressed("menu"):
		if _inv.visible:
			_close_inventory()
		else:
			_set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("foot_inventory"):
		if _inv.visible:
			_close_inventory()
		else:
			_open_inventory()
		get_viewport().set_input_as_handled()
		return
	if _inv.visible:
		if event.is_action_pressed("interact"):
			_close_inventory()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = controls.mouse_sensitivity * 0.0022 * (FOV_AIM / FOV if _aiming() else 1.0)
		var dy: float = -event.relative.y if controls.invert_mouse else event.relative.y
		_look(-event.relative.x * s, -dy * s)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		controls.capture_mouse()
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("foot_reload"):
		_reload()
	elif event.is_action_pressed("foot_heal"):
		_heal()
	elif event.is_action_pressed("foot_crouch"):
		_crouched = not _crouched


func _look(yaw: float, pitch: float) -> void:
	_player.rotate_y(yaw)
	_pitch = clampf(_pitch + pitch, -1.45, 1.45)
	_camera.rotation.x = _pitch + _recoil


func _aiming() -> bool:
	return Input.is_action_pressed("foot_aim") and not _inv.visible and not _paused.visible


func _active() -> bool:
	return not over and not _inv.visible and not _paused.visible


# --- Simulation ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	_message_time -= delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if over:
		return
	_move_player(delta)
	_shoot(delta)
	_update_guards(delta)
	_update_turrets(delta)
	_update_drill(delta)
	_update_extract(delta)
	_reinforce(delta)
	_update_prompt()
	_update_hud()


func _move_player(delta: float) -> void:
	var input := Vector2.ZERO
	var look := Vector2.ZERO
	if _active():
		input = Input.get_vector("foot_left", "foot_right", "foot_forward", "foot_back")
		look = Input.get_vector("foot_look_left", "foot_look_right", "foot_look_up", "foot_look_down")
	if look.length() > 0.1:
		_look(-look.x * LOOK_SPEED * delta, -look.y * LOOK_SPEED * delta)
	var sprinting: bool = _active() and Input.is_action_pressed("foot_sprint") and input.y < -0.1 and not _crouched
	var speed := CROUCH if _crouched else (SPRINT if sprinting else WALK)
	if _aiming():
		speed = minf(speed, WALK * 0.6)
	var dir := (_player.global_basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
	_player.velocity.x = dir.x * speed
	_player.velocity.z = dir.z * speed
	if _player.is_on_floor():
		if _active() and Input.is_action_just_pressed("foot_jump"):
			_player.velocity.y = JUMP
	else:
		_player.velocity.y -= GRAVITY * delta
	_player.move_and_slide()
	_camera.position.y = lerpf(_camera.position.y, EYE_CROUCHED if _crouched else EYE, minf(1.0, delta * 10.0))
	if _player.position.y < -20.0:
		_player.position = _room_centre(int(layout.entrance)) + Vector3(0, 0.5, 0)

	# Footsteps: guards hear sprinting further than walking, and crouching not at all.
	if input.length() > 0.1 and _player.is_on_floor() and not _crouched:
		_step_noise -= delta
		if _step_noise <= 0.0:
			_step_noise = 0.4
			_noise(_player.position, NOISE_SPRINT if sprinting else NOISE_WALK, false)

	_camera.fov = lerpf(_camera.fov, FOV_AIM if _aiming() else FOV, minf(1.0, delta * 12.0))
	_recoil = lerpf(_recoil, 0.0, minf(1.0, delta * 6.0))
	_camera.rotation.x = _pitch + _recoil


func _shoot(delta: float) -> void:
	_fire_cd -= delta
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var n := mini(MAG - ammo, reserve)
			ammo += n
			reserve -= n
		return
	if not _active() or not Input.is_action_pressed("foot_fire") or _fire_cd > 0.0:
		return
	if ammo <= 0:
		if Input.is_action_just_pressed("foot_fire"):
			_say("Empty. Reload with %s." % controls.binding_text("foot_reload", false), 2.0)
		return
	_fire_cd = FIRE_GAP
	ammo -= 1
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length()
	var spread := (0.004 if _aiming() else 0.02) + moving * 0.004
	var dir := -_camera.global_basis.z + _camera.global_basis.x * randf_range(-spread, spread) + _camera.global_basis.y * randf_range(-spread, spread)
	var from := _camera.global_position
	var hit := _ray(from, from + dir.normalized() * RANGE, LAYER_WORLD | LAYER_GUARDS)
	_recoil += 0.012
	_tracer(from + _camera.global_basis * Vector3(0.22, -0.18, -0.9), hit.get("position", from + dir.normalized() * RANGE))
	if hit and hit.collider is CharacterBody3D:
		var head: bool = hit.position.y - hit.collider.global_position.y > 1.45
		_damage_guard(hit.collider, DAMAGE * (2.0 if head else 1.0))
	elif hit:
		for t in _turrets:
			if not t.dead and hit.collider == t.base:
				t.health -= DAMAGE
				_hit_flash = 0.15
				if t.health <= 0:
					t.dead = true
					t.head.visible = false
					t.laser.visible = false
	_noise(_player.position, NOISE_GUNSHOT, true)
	if Time.get_ticks_msec() - _gunshot_sent_at > 1000: # the server counts one a second
		_gunshot_sent_at = Time.get_ticks_msec()
		Net.send({"type": "raid_noise", "kind": "gunshot"})
	if ammo == 0 and reserve > 0:
		_reload()


func _reload() -> void:
	if _reload_left > 0.0 or ammo == MAG or reserve <= 0:
		return
	_reload_left = RELOAD_SECONDS
	_say("Reloading", RELOAD_SECONDS)


func _heal() -> void:
	for it in inventory:
		if it.cat == "medical":
			Net.send({"type": "raid_use", "uid": it.uid})
			return
	_say("No trauma kits. Search lockers and crates.", 2.0)


func _tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.6)
	mesh.material = mat
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = (from + to) / 2.0
	if length > 0.01:
		mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(0.04).timeout.connect(mi.queue_free)


func _ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q)


# --- Guards ----------------------------------------------------------------------------

func _guard_for(body: Node) -> Dictionary:
	for g in _guards:
		if g.body == body:
			return g
	return {}


func _damage_guard(body: Node, amount: float) -> void:
	var g := _guard_for(body)
	if g.is_empty() or g.dead:
		return
	_hit_flash = 0.15
	g.health -= amount
	if g.health <= 0:
		_kill_guard(g)
	elif g.state != "combat":
		g.state = "combat"
		g.aware = GUARD_REACTION
		_last_known = _player.position


func _kill_guard(g: Dictionary) -> void:
	g.dead = true
	g.laser.visible = false
	if g.has_token:
		_tokens -= 1
		g.has_token = false
	var body: CharacterBody3D = g.body
	body.collision_layer = 0
	body.collision_mask = 0
	body.rotation.x = -PI / 2.0
	body.position.y = 0.35
	body.get_node("Visor").visible = false


func _path_to(g: Dictionary, goal: Vector3) -> void:
	# Room to room through doors (the vault only once it's open), then straight to the goal.
	var from := _room_at(g.body.position)
	var to := _room_at(goal)
	var path: Array = []
	if from >= 0 and to >= 0 and from != to:
		var prev := {from: -1}
		var queue := [from]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			if cur == to:
				break
			for d in layout.doors:
				if d.locked and not vault_open:
					continue
				var other := -1
				if int(d.a) == cur:
					other = int(d.b)
				elif int(d.b) == cur:
					other = int(d.a)
				if other >= 0 and not prev.has(other):
					prev[other] = cur
					queue.append(other)
		if prev.has(to):
			var rooms_path := []
			var at := to
			while at != -1:
				rooms_path.push_front(at)
				at = prev[at]
			for i in range(1, rooms_path.size()):
				path.append((_room_centre(rooms_path[i - 1]) + _room_centre(rooms_path[i])) / 2.0)
				path.append(_room_centre(rooms_path[i]))
	path.append(goal)
	g.path = path


func _room_at(p: Vector3) -> int:
	var x := floori((p.x + room / 2.0) / room)
	var y := floori((p.z + room / 2.0) / room)
	if x < 0 or y < 0 or x >= int(layout.cols) or y >= int(layout.rows):
		return int(layout.entrance) if p.z > 0 else -1
	return y * int(layout.cols) + x


func _can_see(from: Vector3, to: Vector3, exclude: Array) -> bool:
	return _ray(from, to, LAYER_WORLD, exclude).is_empty()


func _update_guards(delta: float) -> void:
	var eye := _player.position + Vector3(0, _camera.position.y, 0)
	for g in _guards:
		if g.dead:
			continue
		var body: CharacterBody3D = g.body
		var head := body.position + Vector3(0, 1.65, 0)
		var to_player := eye - head
		var dist := to_player.length()
		var facing := -body.global_basis.z
		var sight := GUARD_SIGHT * (1.3 if level >= 1 else 1.0) * (0.6 if _crouched else 1.0)
		var sees := dist < sight and facing.dot(to_player.normalized()) > GUARD_FOV and _can_see(head, eye, [body])
		if dist < 2.0 and _can_see(head, eye, [body]):
			sees = true # too close to miss

		if sees:
			g.aware += delta * (2.0 if g.state in ["investigate", "search"] else 1.0)
			if g.aware >= GUARD_REACTION and g.state != "combat":
				g.state = "combat"
				Net.send({"type": "raid_noise", "kind": "spotted"})
				_say("You've been spotted!", 2.0)
			if g.state == "combat":
				_last_known = _player.position
		else:
			g.aware = maxf(0.0, g.aware - delta * 0.5)

		# A guard who finds a body raises the alarm once per body.
		if g.state != "combat":
			for other in _guards:
				if other.dead and not g.noticed.has(other.id) and body.position.distance_to(other.body.position) < 12.0 \
						and _can_see(head, other.body.position + Vector3(0, 0.4, 0), [body]):
					g.noticed[other.id] = true
					Net.send({"type": "raid_noise", "kind": "body"})
					_investigate(g, other.body.position)

		match g.state:
			"patrol":
				if level >= 2 and _last_known != Vector3.INF:
					_investigate(g, _last_known)
				elif _follow(g, GUARD_SPEED, delta):
					g.leg = (g.leg + 1) % g.route.size()
					_path_to(g, _room_centre(g.route[g.leg]) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
			"investigate":
				if _follow(g, GUARD_RUN if level >= 2 else GUARD_SPEED, delta):
					g.state = "search"
					g.search = 6.0
			"search":
				body.rotate_y(delta * 1.2)
				g.search -= delta
				if g.search <= 0.0:
					g.state = "patrol"
					_path_to(g, _room_centre(g.route[g.leg]))
			"combat":
				_guard_combat(g, sees, dist, delta)
		_stand(body, delta)


func _investigate(g: Dictionary, where: Vector3) -> void:
	if g.state == "combat":
		return
	g.state = "investigate"
	_path_to(g, where)


func _stand(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * delta
	else:
		body.velocity.y = 0.0
	body.move_and_slide()


## Walks a guard along its path. Returns true once it's at the end.
func _follow(g: Dictionary, speed: float, _delta: float) -> bool:
	var body: CharacterBody3D = g.body
	while not g.path.is_empty():
		var p: Vector3 = g.path[0]
		var flat := Vector3(p.x - body.position.x, 0, p.z - body.position.z)
		if flat.length() < 0.5:
			g.path.pop_front()
			continue
		var dir := flat.normalized()
		body.velocity.x = dir.x * speed
		body.velocity.z = dir.z * speed
		body.look_at(body.position + dir, Vector3.UP)
		return false
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	return true


func _guard_combat(g: Dictionary, sees: bool, dist: float, delta: float) -> void:
	var body: CharacterBody3D = g.body
	var laser: MeshInstance3D = g.laser
	if not sees:
		laser.visible = false
		g.tell = 0.0
		if g.has_token:
			_tokens -= 1
			g.has_token = false
		# Lost sight: chase to where you were last seen.
		if g.path.is_empty() or g.path[-1].distance_to(_last_known) > 1.0:
			_path_to(g, _last_known)
		if _follow(g, GUARD_RUN, delta):
			g.state = "search"
			g.search = 8.0
		return
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	var flat := Vector3(_player.position.x - body.position.x, 0, _player.position.z - body.position.z)
	if flat.length() > 0.01:
		body.look_at(body.position + flat, Vector3.UP)
	if not g.has_token:
		if _tokens >= ATTACK_TOKENS:
			if dist > 6.0:
				_path_to(g, _player.position)
				_follow(g, GUARD_SPEED, delta) # close in while waiting for a turn to shoot
			return
		_tokens += 1
		g.has_token = true
		g.tell = 0.0
	# Every first shot is telegraphed by the aiming laser.
	var muzzle := body.position + Vector3(0, 1.4, 0)
	var target := _player.position + Vector3(0, _camera.position.y - 0.3, 0)
	_aim_laser(laser, muzzle, target)
	g.tell += delta
	if g.tell < GUARD_TELL:
		return
	g.cd -= delta
	if g.cd > 0.0:
		return
	g.cd = 0.18 if g.elite else 0.3
	g.burst += 1
	if g.burst >= 4:
		g.burst = 0
		g.cd = 0.9
	# Accuracy tightens over two seconds of firing.
	var accuracy := clampf(0.25 + (g.tell - GUARD_TELL) * 0.35, 0.25, 0.85) * (1.0 if dist < 15.0 else 0.7)
	_noise(body.position, NOISE_GUNSHOT, false)
	if randf() < accuracy:
		_hurt(GUARD_DAMAGE * (1.5 if g.elite else 1.0), body.position)


func _aim_laser(laser: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	laser.visible = true
	var length := from.distance_to(to)
	laser.scale = Vector3(1, 1, length)
	laser.global_position = (from + to) / 2.0
	laser.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)


func _update_turrets(delta: float) -> void:
	var eye := _player.position + Vector3(0, _camera.position.y - 0.2, 0)
	for t in _turrets:
		if t.dead:
			continue
		var awake := level >= 2 or _room_at(_player.position) == int(layout.vault)
		var sees: bool = awake and t.pos.distance_to(eye) < 20.0 and _can_see(t.pos, eye, [t.base])
		if not sees:
			t.laser.visible = false
			t.tell = 0.0
			continue
		t.head.look_at(eye, Vector3.UP)
		_aim_laser(t.laser, t.pos, eye)
		t.tell += delta
		t.cd -= delta
		if t.tell >= 0.6 and t.cd <= 0.0:
			t.cd = 0.25
			_noise(t.pos, NOISE_GUNSHOT, false)
			if randf() < 0.5:
				_hurt(8.0, t.pos)


func _hurt(amount: float, from: Vector3) -> void:
	if god_mode or over:
		return
	health -= amount
	_hurt_flash = 0.35
	_hurt_from = from
	if health <= 0.0:
		health = 0.0
		over = true
		_centre.text = "You're down."
		Net.send({"type": "raid_died"})


## A sound in the facility: guards in range come to look.
func _noise(at: Vector3, radius: float, from_player: bool) -> void:
	for g in _guards:
		if g.dead or g.state == "combat":
			continue
		# Guards follow your footsteps; of other sounds, only loud ones (gunfire, the drill) carry.
		if g.body.position.distance_to(at) <= radius and (from_player or radius >= NOISE_DRILL):
			_investigate(g, _player.position if from_player else at)


func _reinforce(delta: float) -> void:
	if level < 3:
		return
	_reinforce_in -= delta
	if _reinforce_in <= 0.0:
		_reinforce_in = REINFORCE_EVERY
		_spawn_away("Reinforcements are coming in.", false)
	if level >= 4 and not _elite_sent:
		_elite_sent = true
		_spawn_away("PURGE: an elite security team is hunting you.", true)


func _spawn_away(text: String, elite: bool) -> void:
	# Never inside your view or within 25 m of you.
	var best := -1
	for id in rooms:
		if id == int(layout.vault):
			continue
		var c := _room_centre(id)
		if c.distance_to(_player.position) > 25.0 and (best < 0 or c.distance_to(_player.position) > _room_centre(best).distance_to(_player.position)):
			best = id
	if best < 0:
		return
	var g := _spawn_guard("r%d" % _guards.size(), [best], _room_centre(best), elite)
	_investigate(g, _player.position)
	_say(text, 4.0)


# --- Interacting -----------------------------------------------------------------------

## For tests: stand somewhere, stopped.
func teleport_to(pos: Vector3) -> void:
	_player.position = Vector3(pos.x, 0.05, pos.z)
	_player.velocity = Vector3.ZERO


func _near_container() -> String:
	var best := ""
	var best_d := REACH + 0.6
	for id in _containers:
		var node: Node3D = _containers[id].node
		var d := Vector2(node.global_position.x - _player.position.x, node.global_position.z - _player.position.z).length()
		if d < best_d:
			best = id
			best_d = d
	return best


func _near_vault_door() -> bool:
	if vault_open:
		return false
	for slab in _vault_doors:
		if slab.global_position.distance_to(_player.position + Vector3(0, 1.0, 0)) < REACH + 0.4:
			return true
	return false


func _guard_to_take_down() -> Dictionary:
	for g in _guards:
		if g.dead or g.state == "combat":
			continue
		var to_guard: Vector3 = g.body.position - _player.position
		to_guard.y = 0
		if to_guard.length() < 1.8 and (-g.body.global_basis.z).dot(to_guard.normalized()) > 0.2:
			return g # behind them, facing the same way
	return {}


func _holding(item: String) -> bool:
	for it in inventory:
		if it.item == item:
			return true
	return false


func _interact() -> void:
	var g := _guard_to_take_down()
	if not g.is_empty():
		_kill_guard(g)
		_say("Silent takedown.", 2.0)
		return
	if _near_vault_door():
		if _holding("keycard"):
			Net.send({"type": "raid_keycard"})
		elif _drill_left < 0.0:
			Net.send({"type": "raid_drill_start"})
		return
	var c := _near_container()
	if c != "":
		open_container(c)


func open_container(id: String) -> void:
	_open_container = id
	Net.send({"type": "raid_open", "container": id})
	_open_inventory()
	_inv.set_container(_containers[id].name, [], [3, 3], "Opening...")


func _open_inventory() -> void:
	_inv.visible = true
	controls.release_mouse()


func _close_inventory() -> void:
	_inv.visible = false
	if _open_container != "":
		Net.send({"type": "raid_close"})
		_open_container = ""
		_inv.set_container("", [], [0, 0], "")
	if not over:
		controls.capture_mouse()


func _update_drill(delta: float) -> void:
	if _drill_left < 0.0:
		return
	_drill_left -= delta
	_noise(_drill.global_position, NOISE_DRILL, false)
	if _drill_left <= 0.0:
		_drill_left = -1.0
		Net.send({"type": "raid_drill_finish"})


func _start_drill(seconds: float) -> void:
	_drill_left = seconds
	if _drill == null:
		var slab: Node3D = _vault_doors[0]
		for s in _vault_doors:
			if s.global_position.distance_to(_player.position) < slab.global_position.distance_to(_player.position):
				slab = s
		_drill = _box(Vector3(0.5, 0.5, 0.5), slab.global_position + (_player.position - slab.global_position).normalized() * 0.5 * Vector3(1, 0, 1), Color(1.0, 0.6, 0.1), false, true)
	_say("Drill placed. It's loud: guards will come.", 3.0)


func _update_extract(delta: float) -> void:
	var inside := ""
	for id in _extract_nodes:
		var e: Dictionary = _extract_nodes[id]
		if Vector2(e.pos.x - _player.position.x, e.pos.z - _player.position.z).length() < 2.2:
			inside = id
	if inside != _extracting:
		if _extracting != "":
			Net.send({"type": "raid_extract_stop"})
			_centre.text = ""
		_extracting = inside
		_extract_left = -1.0
		if inside != "":
			Net.send({"type": "raid_extract_start", "extract": inside})
	if _extracting != "" and _extract_left >= 0.0:
		_extract_left -= delta
		_centre.text = "Extracting via %s: %.1f s" % [_extract_nodes[_extracting].name, maxf(0.0, _extract_left)]
		if _extract_left <= 0.0:
			_extract_left = -2.0 # sent; wait for the server
			Net.send({"type": "raid_extract_finish"})


func _update_prompt() -> void:
	var key: String = controls.binding_text("interact", false)
	var text := ""
	if _inv.visible:
		text = ""
	elif not _guard_to_take_down().is_empty():
		text = "%s: silent takedown" % key
	elif _near_vault_door():
		if _holding("keycard"):
			text = "%s: swipe the access keycard (silent)" % key
		elif _drill_left >= 0.0:
			text = "Drilling: %d s" % ceili(_drill_left)
		else:
			text = "Vault door: %s to drill it open (loud, %d s), or find an access keycard" % [key, 30]
	elif _near_container() != "":
		text = "%s: search the %s" % [key, _containers[_near_container()].name.to_lower()]
	_prompt.text = text


func _refresh_extract_labels() -> void:
	for id in _extract_nodes:
		var e: Dictionary = _extract_nodes[id]
		var st: Dictionary = extract_states.get(id, {})
		var line: String = e.name
		if not st.is_empty():
			if not st.open:
				line += " (closed: %s)" % st.why
			elif st.needs:
				line += " (needs a keycard, %d s)" % int(st.countdown)
			else:
				line += " (%d s)" % int(st.countdown)
		e.label.text = line
		e.node.visible = st.get("open", true)


func _update_hud() -> void:
	var levels: Array = Net.catalog.get("heatLevels", [{"name": "?"}])
	var carried := 0
	for it in inventory:
		carried += int(it.value) * int(it.qty)
	_status.text = "%s\nTime left %d:%02d\nHeat %d  %s\nHealth %d   Ammo %d / %d\nCarrying %d credits of loot\nVault: %s" % [
		brief.facility, int(remaining) / 60, int(remaining) % 60, heat, levels[mini(level, levels.size() - 1)].name.to_upper(),
		ceili(health), ammo, reserve, carried, "open" if vault_open else "locked"]
	if _message_time <= 0.0:
		_message.text = ""
	_hud.queue_redraw()


func _draw_hud() -> void:
	var size := _hud.size
	var c := size * 0.5
	var white := Color(0.35, 0.95, 0.88)
	if not _inv.visible:
		var gap := 6.0 if _aiming() else 10.0
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_hud.draw_line(c + d * gap, c + d * (gap + 8.0), white, 2.0)
		if _hit_flash > 0.0:
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				_hud.draw_line(c + d * 6.0, c + d * 13.0, Color.WHITE, 2.0)

	# Heat bar, top centre, marked at each level.
	var w := 320.0
	var bar := Rect2(c.x - w / 2.0, 24, w, 10)
	_hud.draw_rect(bar, Color(1, 1, 1, 0.15))
	var hot := Color(0.35, 0.95, 0.88).lerp(Color(1.0, 0.25, 0.15), heat / 100.0)
	_hud.draw_rect(Rect2(bar.position, Vector2(w * heat / 100.0, 10)), hot)
	for mark in [20, 40, 60, 80]:
		_hud.draw_line(Vector2(bar.position.x + w * mark / 100.0, 22), Vector2(bar.position.x + w * mark / 100.0, 36), Color(1, 1, 1, 0.5), 1.0)
	var levels: Array = Net.catalog.get("heatLevels", [{"name": "?"}])
	_hud.draw_string(_hud.get_theme_default_font(), Vector2(c.x - w / 2.0, 52), "HEAT  " + levels[mini(level, levels.size() - 1)].name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hot)

	# Extract markers, on screen or at its edge.
	for id in _extract_nodes:
		var e: Dictionary = _extract_nodes[id]
		var st: Dictionary = extract_states.get(id, {})
		var p: Vector3 = e.pos + Vector3(0, 1.5, 0)
		var col := Color(0.4, 1.0, 0.6) if st.get("open", true) else Color(1, 1, 1, 0.3)
		var text := "%s %d m" % [e.name, roundi(p.distance_to(_player.position))]
		if not _camera.is_position_behind(p):
			var sp := _camera.unproject_position(p)
			if Rect2(Vector2.ZERO, size).grow(-20).has_point(sp):
				_hud.draw_circle(sp, 4, col)
				_hud.draw_string(_hud.get_theme_default_font(), sp + Vector2(8, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	# Damage: red at the screen edge toward whoever hit you.
	if _hurt_flash > 0.0:
		var local := _camera.global_basis.inverse() * (_hurt_from - _player.position)
		var dir := Vector2(local.x, local.z).normalized()
		var a := _hurt_flash / 0.35
		_hud.draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, 0.12 * a))
		var p := c + dir * minf(size.x, size.y) * 0.35
		_hud.draw_circle(p, 18, Color(1.0, 0.1, 0.05, 0.6 * a))


# --- Server events ---------------------------------------------------------------------

func _on_server_error(reason: String) -> void:
	_say(reason, 3.0)


func _on_raid_event(msg: Dictionary) -> void:
	match msg.ev:
		"container":
			if msg.container == null or msg.container != _open_container:
				return
			_inv.set_container(_containers[msg.container].name, msg.slots, msg.grid, "Searching..." if msg.slots.any(func(s): return not s.has("item")) else "")
		"reveal":
			if msg.container == _open_container:
				_inv.reveal(msg.item)
		"inventory":
			inventory = msg.items
			_inv.set_inventory(inventory, brief.backpack, brief.secure)
		"heat":
			var before := level
			heat = int(msg.heat)
			level = int(msg.level)
			remaining = float(msg.remaining) / 1000.0
			extract_states = msg.extracts
			_refresh_extract_labels()
			if msg.vaultOpen and not vault_open:
				_open_vault()
			if level > before:
				var levels: Array = Net.catalog.get("heatLevels", [])
				_say("Security: %s" % (levels[level].name if levels else str(level)), 3.0)
		"heal":
			health = minf(100.0, health + float(msg.amount))
			_say("Patched up.", 2.0)
		"drill":
			_start_drill(float(msg.seconds))
		"extracting":
			if msg.extract == _extracting:
				_extract_left = float(msg.countdown)
				if msg.loud:
					_noise(_extract_nodes[_extracting].pos, NOISE_EXTRACT, false)
		"end":
			_show_results(msg.result)
		"begin":
			pass # a resumed run while already inside: nothing to rebuild


func _open_vault() -> void:
	vault_open = true
	for slab in _vault_doors:
		slab.visible = false
		slab.get_child(0).disabled = true
	if _drill:
		_drill.queue_free()
		_drill = null
	_drill_left = -1.0
	_say("The vault is open.", 3.0)


func _show_results(result: Dictionary) -> void:
	over = true
	_inv.visible = false
	_paused.visible = false
	_centre.text = ""
	controls.release_mouse()
	var titles := {"extracted": "EXTRACTED", "killed": "KILLED IN ACTION", "mia": "MISSING IN ACTION", "bailed": "BAILED OUT"}
	var root := ColorRect.new()
	root.color = Color(0, 0.02, 0.05, 0.9)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.get_parent().add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	var title := Label.new()
	title.text = titles.get(result.outcome, result.outcome)
	title.add_theme_font_size_override("font_size", 34)
	title.modulate = Color(0.4, 1.0, 0.6) if result.outcome == "extracted" else Color(1.0, 0.4, 0.35)
	col.add_child(title)
	var lines := ["%s   %d:%02d in the facility   peak Heat %d" % [brief.facility, int(result.seconds) / 60, int(result.seconds) % 60, int(result.heatPeak)]]
	if result.kept.is_empty():
		lines.append("You came away with nothing.")
	else:
		lines.append("\nYou kept, worth %d credits:" % int(result.value))
		for k in result.kept:
			lines.append("  %d x %s%s" % [k.qty, Net.item_name(k.item), "  (found in raid)" if k.fih else ""])
	if not result.lost.is_empty():
		lines.append("\nLost:")
		for k in result.lost:
			lines.append("  %d x %s" % [k.qty, Net.item_name(k.item)])
	if not result.stolen.is_empty():
		var s := []
		for id in result.stolen:
			s.append("%d %s" % [result.stolen[id], Net.item_name(id)])
		lines.append("\nTaken from the owner's vault: " + ", ".join(s))
	lines.append("\nSell loot to the Fence at the Spaceport.")
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var back := Button.new()
	back.text = "Back to the ship"
	back.pressed.connect(func(): finished.emit(result))
	col.add_child(back)
	back.grab_focus()
